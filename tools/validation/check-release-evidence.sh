#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate machine-readable GenixBit OS release evidence.
#
# Two records are intentionally supported:
#   1. legacy candidate-validation records used by historical validation branches;
#   2. active-release records used by current LTS release automation.
#
# Keeping the schemas explicit prevents historical evidence from being rewritten just
# to satisfy current CI while allowing current release metadata to be validated.

set -Eeuo pipefail
IFS=$'\n\t'

STATUS_FILE="docs/VALIDATION-STATUS.env"
REQUIRE_COMPLETE=false
VERIFY_GIT_CANDIDATE=false

usage() {
    cat <<'EOF'
Usage: check-release-evidence.sh [--require-complete] [--verify-git-candidate] [--status-file PATH]

Options:
  --require-complete     Require all gates to PASS and immutable release metadata to be complete.
  --verify-git-candidate Verify the recorded git candidate against its branch.
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
import re
import shlex
import sys

status_file = sys.argv[1]
seen = set()
# These are allowed to be empty while an active artifact is not yet published.
allow_empty = {"ISO_SHA256", "ISO_URL", "SOURCE_COMMIT"}

with open(status_file, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            print("PARSE_ERROR=" + shlex.quote(f"Invalid line in {status_file} (missing =): {line}"))
            continue
        key, value = line.split("=", 1)
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            print("PARSE_ERROR=" + shlex.quote(f"Invalid key in {status_file}: {key}"))
            continue
        if key in seen:
            print("PARSE_ERROR=" + shlex.quote(f"Duplicate key in {status_file}: {key}"))
            continue
        seen.add(key)
        if not value and key not in allow_empty:
            print("PARSE_ERROR=" + shlex.quote(f"Empty value for {key} in {status_file}"))
            continue
        print(f"VAL_{key}=" + shlex.quote(value))
PYEOF
)"

[[ -z "${PARSE_ERROR:-}" ]] || fail "$PARSE_ERROR"

value_for() {
    local key=$1
    local varname="VAL_$key"
    printf '%s' "${!varname:-}"
}

require_keys() {
    local key
    for key in "$@"; do
        [[ -n "$(value_for "$key")" ]] || fail "Required key is missing or empty: $key"
    done
}

validate_statuses() {
    local allowed='^(PASS|PENDING|PARTIAL|FAIL|NOT_TESTED)$'
    local key value
    for key in "$@"; do
        value=$(value_for "$key")
        [[ "$value" =~ $allowed ]] || fail "$key has an unsupported status: $value"
    done
}

resolve_branch_head() {
    local branch=$1
    local remote_name="${GIT_REMOTE:-origin}"
    local head=""

    if git rev-parse --quiet --verify "refs/heads/$branch" >/dev/null 2>&1; then
        head=$(git rev-parse --verify "refs/heads/$branch")
    elif git rev-parse --quiet --verify "refs/remotes/$remote_name/$branch" >/dev/null 2>&1; then
        head=$(git rev-parse --verify "refs/remotes/$remote_name/$branch")
    else
        local remote_out
        remote_out=$(git ls-remote --heads "$remote_name" "$branch" 2>/dev/null || true)
        [[ -n "$remote_out" ]] && head=$(printf '%s\n' "$remote_out" | awk 'NR==1 {print $1}')
    fi

    printf '%s' "$head"
}

CANDIDATE_SHA="${VAL_CANDIDATE_SHA:-}"
CANDIDATE_BRANCH="${VAL_CANDIDATE_BRANCH:-}"

if [[ -n "${VAL_ACTIVE_RELEASE_VERSION:-}" ]]; then
    SCHEMA="active-release"
    active_required=(
        VALIDATION_VERSION
        ACTIVE_RELEASE_VERSION
        ACTIVE_RELEASE_MODE
        ACTIVE_RELEASE_PROVENANCE
        ISO_FILENAME
        ISO_URL
        ISO_SIZE_BYTES
        SOURCE_COMMIT
        HOST_PREP_STATUS
        FRESH_INSTALL_AMD64_STATUS
        UPGRADE_PATH_STATUS
        BRANDING_SUITE_STATUS
        PACKAGE_SUITE_STATUS
        SECURITY_SUITE_STATUS
        CANDIDATE_BRANCH
        CANDIDATE_SHA
        LAST_REHEARSAL_AT_UTC
        LAST_REHEARSAL_WORKFLOW
    )
    require_keys "${active_required[@]}"
    # ISO_SHA256 is required as a key but may be empty until immutable publication.
    [[ ${VAL_ISO_SHA256+x} ]] || fail 'Required key is missing: ISO_SHA256'

    [[ "${VAL_VALIDATION_VERSION}" == "${VAL_ACTIVE_RELEASE_VERSION}" ]] \
        || fail "VALIDATION_VERSION (${VAL_VALIDATION_VERSION}) must match ACTIVE_RELEASE_VERSION (${VAL_ACTIVE_RELEASE_VERSION})."

    case "${VAL_ACTIVE_RELEASE_MODE}" in
        fresh-install-only|fresh-install-and-upgrade|upgrade-only) ;;
        *) fail "Unsupported ACTIVE_RELEASE_MODE: ${VAL_ACTIVE_RELEASE_MODE}" ;;
    esac

    [[ "$CANDIDATE_SHA" =~ ^[0-9a-fA-F]{40}$ ]] \
        || fail 'CANDIDATE_SHA must be a full 40-character hexadecimal commit SHA.'
    [[ "$CANDIDATE_BRANCH" =~ ^[A-Za-z0-9._/-]+$ && "$CANDIDATE_BRANCH" != */../* ]] \
        || fail "CANDIDATE_BRANCH is not a valid branch name: $CANDIDATE_BRANCH"

    [[ "${VAL_ISO_FILENAME}" == *"${VAL_ACTIVE_RELEASE_VERSION}"* ]] \
        || fail "ISO_FILENAME (${VAL_ISO_FILENAME}) does not contain ACTIVE_RELEASE_VERSION (${VAL_ACTIVE_RELEASE_VERSION})."
    [[ "${VAL_ISO_URL}" == *"$(basename "${VAL_ISO_FILENAME}")"* ]] \
        || fail 'ISO_URL must reference ISO_FILENAME.'
    [[ "${VAL_ISO_SIZE_BYTES}" =~ ^[0-9]+$ ]] \
        || fail "ISO_SIZE_BYTES must be a non-negative integer: ${VAL_ISO_SIZE_BYTES}"

    active_status_keys=(
        HOST_PREP_STATUS
        FRESH_INSTALL_AMD64_STATUS
        UPGRADE_PATH_STATUS
        BRANDING_SUITE_STATUS
        PACKAGE_SUITE_STATUS
        SECURITY_SUITE_STATUS
    )
    validate_statuses "${active_status_keys[@]}"

    if [[ -n "${VAL_SOURCE_COMMIT:-}" ]]; then
        [[ "${VAL_SOURCE_COMMIT}" =~ ^[0-9a-fA-F]{40}$ ]] \
            || fail 'SOURCE_COMMIT must be a full 40-character hexadecimal commit SHA when present.'
    fi

    if [[ "$REQUIRE_COMPLETE" == true ]]; then
        incomplete=()
        for key in "${active_status_keys[@]}"; do
            [[ "$(value_for "$key")" == PASS ]] || incomplete+=("$key=$(value_for "$key")")
        done
        [[ "${VAL_ISO_SIZE_BYTES}" =~ ^[1-9][0-9]*$ ]] || incomplete+=("ISO_SIZE_BYTES=${VAL_ISO_SIZE_BYTES}")
        [[ "${VAL_ISO_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || incomplete+=("ISO_SHA256=missing-or-invalid")
        [[ "${VAL_SOURCE_COMMIT:-}" =~ ^[0-9a-fA-F]{40}$ ]] || incomplete+=("SOURCE_COMMIT=missing-or-invalid")
        [[ "${VAL_LAST_REHEARSAL_AT_UTC}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
            || incomplete+=("LAST_REHEARSAL_AT_UTC=${VAL_LAST_REHEARSAL_AT_UTC}")
        if ((${#incomplete[@]} > 0)); then
            printf '[FAIL] Active-release evidence is incomplete:\n' >&2
            printf '  %s\n' "${incomplete[@]}" >&2
            exit 1
        fi
    fi
else
    SCHEMA="candidate-validation"
    legacy_required=(
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
    require_keys "${legacy_required[@]}"

    [[ "$CANDIDATE_SHA" =~ ^[0-9a-fA-F]{40}$ ]] \
        || fail 'CANDIDATE_SHA must be a full 40-character hexadecimal commit SHA.'
    [[ "$CANDIDATE_BRANCH" == validation/* ]] \
        || fail 'CANDIDATE_BRANCH must use the validation/ namespace for candidate-validation evidence.'

    legacy_status_keys=(
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
    validate_statuses "${legacy_status_keys[@]}"

    if [[ "$REQUIRE_COMPLETE" == true ]]; then
        incomplete=()
        for key in "${legacy_status_keys[@]}"; do
            [[ "$(value_for "$key")" == PASS ]] || incomplete+=("$key=$(value_for "$key")")
        done
        if ((${#incomplete[@]} > 0)); then
            printf '[FAIL] Candidate-validation evidence is incomplete:\n' >&2
            printf '  %s\n' "${incomplete[@]}" >&2
            exit 1
        fi
    fi
fi

pass "Release-evidence schema '$SCHEMA' is valid for $CANDIDATE_BRANCH at $CANDIDATE_SHA."

if [[ "$VERIFY_GIT_CANDIDATE" == true ]]; then
    branch_head=$(resolve_branch_head "$CANDIDATE_BRANCH")
    [[ "$branch_head" =~ ^[0-9a-fA-F]{40}$ ]] \
        || fail "Candidate branch '$CANDIDATE_BRANCH' is missing or has an invalid HEAD."

    if [[ "$SCHEMA" == "candidate-validation" ]]; then
        [[ "$branch_head" == "$CANDIDATE_SHA" ]] \
            || fail "Candidate branch $CANDIDATE_BRANCH HEAD ($branch_head) differs from CANDIDATE_SHA ($CANDIDATE_SHA)."
        pass "Candidate branch $CANDIDATE_BRANCH exactly matches CANDIDATE_SHA ($CANDIDATE_SHA)."
    else
        # Released evidence is immutable while its source branch is allowed to advance.
        # If the recorded commit is available locally, require it to be an ancestor.
        if git cat-file -e "${CANDIDATE_SHA}^{commit}" 2>/dev/null; then
            git merge-base --is-ancestor "$CANDIDATE_SHA" "$branch_head" \
                || fail "Released CANDIDATE_SHA $CANDIDATE_SHA is not reachable from $CANDIDATE_BRANCH HEAD $branch_head."
        elif [[ "$branch_head" != "$CANDIDATE_SHA" ]]; then
            fail "Cannot prove released CANDIDATE_SHA $CANDIDATE_SHA is reachable from $CANDIDATE_BRANCH in this checkout."
        fi
        pass "Released candidate $CANDIDATE_SHA is consistent with branch $CANDIDATE_BRANCH."
    fi
fi
