#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate the machine-readable GenixBit OS release-evidence record.

set -Eeuo pipefail
IFS=$'\n\t'

STATUS_FILE="docs/VALIDATION-STATUS.env"
REQUIRE_COMPLETE=false
VERIFY_GIT_CANDIDATE=false

usage() {
    cat <<'EOF'
Usage: check-release-evidence.sh [--require-complete] [--verify-git-candidate] [--status-file PATH]

Options:
  --require-complete     Require every release gate and the overall result to PASS.
  --verify-git-candidate Verify the git candidate branch HEAD matches CANDIDATE_SHA.
  --status-file PATH     Read a different machine-readable status file.
  -h, --help             Show this help.
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
        --require-complete)
            REQUIRE_COMPLETE=true
            shift
            ;;
        --verify-git-candidate)
            VERIFY_GIT_CANDIDATE=true
            shift
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

[[ -f "$STATUS_FILE" ]] || fail "Status file not found: $STATUS_FILE"

eval "$(python3 - "$STATUS_FILE" <<'PYEOF'
import sys, re

status_file = sys.argv[1]
seen = set()

with open(status_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' not in line:
            print(f"fail 'Invalid line in {status_file} (missing =): {line}'")
            sys.exit(0)
        key, value = line.split('=', 1)
        if not re.match(r'^[A-Z][A-Z0-9_]*$', key):
            print(f"fail 'Invalid key in {status_file}: {key}'")
            sys.exit(0)
        if not value:
            print(f"fail 'Empty value for {key} in {status_file}'")
            sys.exit(0)
        if key in seen:
            print(f"fail 'Duplicate key in {status_file}: {key}'")
            sys.exit(0)
        seen.add(key)
        # Escape value safely for sh eval
        safe_val = value.replace("'", "'\"'\"'")
        print(f"VAL_{key}='{safe_val}'")
PYEOF
)"

required_keys=(
    VALIDATION_VERSION
    CANDIDATE_BRANCH
    CANDIDATE_SHA
    CANDIDATE_SELECTION_STATUS
    HOST_STATUS
    BUILD_STATUS
    CHECKSUM_STATUS
    BIOS_STATUS
    UEFI_STATUS
    LIVE_SESSION_STATUS
    INSTALLER_STATUS
    INSTALLED_SYSTEM_STATUS
    APT_STATUS
    PACKAGE_HEALTH_STATUS
    SECOND_BUILD_STATUS
    REPRODUCIBILITY_STATUS
    OVERALL_RELEASE_STATUS
)

for key in "${required_keys[@]}"; do
    varname="VAL_$key"
    val="${!varname:-}"
    [[ -n "$val" ]] || fail "Required key is missing: $key"
done

CANDIDATE_SHA="${VAL_CANDIDATE_SHA:-}"
CANDIDATE_BRANCH="${VAL_CANDIDATE_BRANCH:-}"

[[ "$CANDIDATE_SHA" =~ ^[[:xdigit:]]{40}$ ]] \
    || fail 'CANDIDATE_SHA must be a full 40-character hexadecimal commit SHA.'

[[ "$CANDIDATE_BRANCH" == validation/* ]] \
    || fail 'CANDIDATE_BRANCH must use the validation/ namespace.'

allowed_statuses='^(PASS|PARTIAL|FAIL|NOT_TESTED)$'
status_keys=(
    CANDIDATE_SELECTION_STATUS
    HOST_STATUS
    BUILD_STATUS
    CHECKSUM_STATUS
    BIOS_STATUS
    UEFI_STATUS
    LIVE_SESSION_STATUS
    INSTALLER_STATUS
    INSTALLED_SYSTEM_STATUS
    APT_STATUS
    PACKAGE_HEALTH_STATUS
    SECOND_BUILD_STATUS
    REPRODUCIBILITY_STATUS
    OVERALL_RELEASE_STATUS
)

for key in "${status_keys[@]}"; do
    varname="VAL_$key"
    val="${!varname:-}"
    [[ "$val" =~ $allowed_statuses ]] \
        || fail "$key has an unsupported status: $val"
done

pass "Release-evidence schema is valid for $CANDIDATE_BRANCH at $CANDIDATE_SHA."

if [[ "$VERIFY_GIT_CANDIDATE" == true ]]; then
    branch="$CANDIDATE_BRANCH"
    sha="$CANDIDATE_SHA"

    [[ -n "$branch" ]] || fail "CANDIDATE_BRANCH is missing or empty."
    [[ -n "$sha" ]] || fail "CANDIDATE_SHA is missing or empty."

    REMOTE_NAME="${GIT_REMOTE:-origin}"

    # Query remote branch via git ls-remote
    if ! remote_out=$(git ls-remote --heads "$REMOTE_NAME" "$branch" 2>&1); then
        fail "Remote '$REMOTE_NAME' is unavailable: $remote_out"
    fi

    if [[ -z "$remote_out" ]]; then
        fail "Candidate branch '$branch' is missing on remote '$REMOTE_NAME'."
    fi

    branch_head=$(echo "$remote_out" | awk '{print $1}' | tr -d ' \t\r\n')
    if [[ -z "$branch_head" || ! "$branch_head" =~ ^[0-9a-fA-F]{40}$ ]]; then
        fail "Candidate branch '$branch' HEAD SHA is empty or invalid on remote '$REMOTE_NAME'."
    fi

    if [[ "$branch_head" != "$sha" ]]; then
        fail "Candidate branch $branch HEAD ($branch_head) differs from CANDIDATE_SHA ($sha)."
    fi

    pass "Candidate branch $branch exactly matches CANDIDATE_SHA ($sha)."
fi

if [[ "$REQUIRE_COMPLETE" == true ]]; then
    release_gate_keys=(
        CANDIDATE_SELECTION_STATUS
        HOST_STATUS
        BUILD_STATUS
        CHECKSUM_STATUS
        BIOS_STATUS
        UEFI_STATUS
        LIVE_SESSION_STATUS
        INSTALLER_STATUS
        INSTALLED_SYSTEM_STATUS
        APT_STATUS
        PACKAGE_HEALTH_STATUS
        SECOND_BUILD_STATUS
        REPRODUCIBILITY_STATUS
        OVERALL_RELEASE_STATUS
    )

    incomplete=()
    for key in "${release_gate_keys[@]}"; do
        varname="VAL_$key"
        val="${!varname:-}"
        if [[ "$val" != PASS ]]; then
            incomplete+=("$key=$val")
        fi
    done

    if ((${#incomplete[@]} > 0)); then
        printf '[FAIL] Candidate-validation PR is incomplete:\n' >&2
        printf '  %s\n' "${incomplete[@]}" >&2
        printf '[FAIL] Record direct evidence and set every required gate to PASS before merge.\n' >&2
        exit 1
    fi

    pass 'Every required candidate release gate is PASS.'
fi
