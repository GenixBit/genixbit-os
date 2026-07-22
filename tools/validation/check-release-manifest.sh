#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate the machine-readable GenixBit OS release manifest.

set -Eeuo pipefail
IFS=$'\n\t'

MANIFEST_FILE=""
ARGS_FILE="args.sh"
STATUS_FILE="docs/VALIDATION-STATUS.env"

usage() {
    cat <<'EOF'
Usage: check-release-manifest.sh [--manifest PATH] [--args-file PATH] [--status-file PATH]

Options:
  --manifest PATH     Read a specific release manifest file.
  --args-file PATH    Read build args from PATH (default: args.sh).
  --status-file PATH  Read validation status from PATH (default: docs/VALIDATION-STATUS.env).
  -h, --help          Show this help.
EOF
}

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

while (($# > 0)); do
    case "$1" in
        --manifest)
            (($# >= 2)) || fail '--manifest requires a path.'
            MANIFEST_FILE=$2
            shift 2
            ;;
        --args-file)
            (($# >= 2)) || fail '--args-file requires a path.'
            ARGS_FILE=$2
            shift 2
            ;;
        --status-file)
            (($# >= 2)) || fail '--status-file requires a path.'
            STATUS_FILE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

if [[ -z "$MANIFEST_FILE" ]]; then
    manifests=(docs/releases/*.env)
    if [[ ${#manifests[@]} -eq 0 || ! -f "${manifests[0]}" ]]; then
        fail 'No release manifest found in docs/releases/*.env.'
    fi
    MANIFEST_FILE="${manifests[0]}"
fi

[[ -f "$MANIFEST_FILE" ]] || fail "Manifest file not found: $MANIFEST_FILE"
[[ -f "$ARGS_FILE" ]] || fail "Args file not found: $ARGS_FILE"
[[ -f "$STATUS_FILE" ]] || fail "Status file not found: $STATUS_FILE"

get_key_val() {
    local file=$1
    local target_key=$2
    local val
    val=$(grep -E "^${target_key}=" "$file" | head -n 1 | cut -d'=' -f2-)
    printf '%s' "$val"
}

RELEASE_VERSION=$(get_key_val "$MANIFEST_FILE" "RELEASE_VERSION")
CANDIDATE_BRANCH=$(get_key_val "$MANIFEST_FILE" "CANDIDATE_BRANCH")
CANDIDATE_SHA=$(get_key_val "$MANIFEST_FILE" "CANDIDATE_SHA")
ISO_FILENAME=$(get_key_val "$MANIFEST_FILE" "ISO_FILENAME")
ISO_SIZE_BYTES=$(get_key_val "$MANIFEST_FILE" "ISO_SIZE_BYTES")
ISO_SHA256=$(get_key_val "$MANIFEST_FILE" "ISO_SHA256")
EVIDENCE_PR=$(get_key_val "$MANIFEST_FILE" "EVIDENCE_PR")
VALIDATION_STATUS=$(get_key_val "$MANIFEST_FILE" "VALIDATION_STATUS")

# 1. RELEASE_VERSION is present
[[ -n "$RELEASE_VERSION" ]] || fail 'RELEASE_VERSION is missing or empty.'

# 2 & 4. Candidate branch exists and candidate branch HEAD equals candidate SHA
[[ -n "$CANDIDATE_BRANCH" ]] || fail 'CANDIDATE_BRANCH is missing or empty.'

# 3. Candidate SHA is 40 lowercase hexadecimal characters
[[ "$CANDIDATE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "CANDIDATE_SHA must be exactly 40 lowercase hexadecimal characters: $CANDIDATE_SHA"

# Verify candidate branch head in git
branch_head=""
if git rev-parse --quiet --verify "refs/heads/$CANDIDATE_BRANCH" >/dev/null 2>&1; then
    branch_head=$(git rev-parse --verify "refs/heads/$CANDIDATE_BRANCH")
elif git rev-parse --quiet --verify "refs/remotes/origin/$CANDIDATE_BRANCH" >/dev/null 2>&1; then
    branch_head=$(git rev-parse --verify "refs/remotes/origin/$CANDIDATE_BRANCH")
fi

if [[ -z "$branch_head" ]]; then
    remote_out=$(git ls-remote origin "refs/heads/$CANDIDATE_BRANCH" 2>/dev/null || true)
    if [[ -n "$remote_out" ]]; then
        branch_head=$(echo "$remote_out" | awk '{print $1}')
    fi
fi

[[ -n "$branch_head" ]] || fail "Candidate branch $CANDIDATE_BRANCH does not exist locally or on origin."

if [[ "$branch_head" != "$CANDIDATE_SHA" ]]; then
    fail "Candidate branch $CANDIDATE_BRANCH HEAD ($branch_head) differs from CANDIDATE_SHA ($CANDIDATE_SHA)."
fi

# 5. ISO_FILENAME contains RELEASE_VERSION
[[ -n "$ISO_FILENAME" ]] || fail 'ISO_FILENAME is missing or empty.'
if [[ "$ISO_FILENAME" != *"$RELEASE_VERSION"* ]]; then
    fail "ISO_FILENAME ($ISO_FILENAME) does not contain RELEASE_VERSION ($RELEASE_VERSION)."
fi

# 6. ISO_SIZE_BYTES is a positive integer
[[ "$ISO_SIZE_BYTES" =~ ^[1-9][0-9]*$ ]] || fail "ISO_SIZE_BYTES must be a positive integer without commas or units: $ISO_SIZE_BYTES"

# 7. ISO_SHA256 is exactly 64 lowercase hexadecimal characters
[[ "$ISO_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "ISO_SHA256 must be exactly 64 lowercase hexadecimal characters: $ISO_SHA256"

# 8. EVIDENCE_PR is a positive integer
[[ "$EVIDENCE_PR" =~ ^[1-9][0-9]*$ ]] || fail "EVIDENCE_PR must be a positive integer: $EVIDENCE_PR"

# 9. VALIDATION_STATUS is PASS
[[ "$VALIDATION_STATUS" == "PASS" ]] || fail "VALIDATION_STATUS must be PASS (found: $VALIDATION_STATUS)."

# 10. docs/VALIDATION-STATUS.env matches manifest candidate branch, SHA and version
STATUS_VERSION=$(get_key_val "$STATUS_FILE" "VALIDATION_VERSION")
STATUS_BRANCH=$(get_key_val "$STATUS_FILE" "CANDIDATE_BRANCH")
STATUS_SHA=$(get_key_val "$STATUS_FILE" "CANDIDATE_SHA")

if [[ "$STATUS_VERSION" != "$RELEASE_VERSION" ]]; then
    fail "$STATUS_FILE VALIDATION_VERSION ($STATUS_VERSION) does not match manifest RELEASE_VERSION ($RELEASE_VERSION)."
fi
if [[ "$STATUS_BRANCH" != "$CANDIDATE_BRANCH" ]]; then
    fail "$STATUS_FILE CANDIDATE_BRANCH ($STATUS_BRANCH) does not match manifest CANDIDATE_BRANCH ($CANDIDATE_BRANCH)."
fi
if [[ "$STATUS_SHA" != "$CANDIDATE_SHA" ]]; then
    fail "$STATUS_FILE CANDIDATE_SHA ($STATUS_SHA) does not match manifest CANDIDATE_SHA ($CANDIDATE_SHA)."
fi

# 11. args.sh TARGET_BUILD_VERSION matches RELEASE_VERSION
ARGS_BUILD_VERSION=$(grep -E '^export TARGET_BUILD_VERSION=' "$ARGS_FILE" | cut -d'"' -f2)
if [[ "$ARGS_BUILD_VERSION" != "$RELEASE_VERSION" ]]; then
    fail "$ARGS_FILE TARGET_BUILD_VERSION ($ARGS_BUILD_VERSION) does not match manifest RELEASE_VERSION ($RELEASE_VERSION)."
fi

pass "Release manifest $MANIFEST_FILE is valid and matches $STATUS_FILE and $ARGS_FILE."
