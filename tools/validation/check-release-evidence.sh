#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate machine-readable GenixBit OS release evidence.
#
# Two evidence schemas are intentionally supported:
#   1. historical candidate-validation records used by validation/* branches;
#   2. the canonical active-release record in docs/VALIDATION-STATUS.env.
#
# Historical evidence must remain immutable. Current CI therefore validates the
# active schema that actually exists in the repository instead of rewriting old
# candidate records to match newer releases.

set -Eeuo pipefail
IFS=$'\n\t'

STATUS_FILE="docs/VALIDATION-STATUS.env"
REQUIRE_COMPLETE=false
VERIFY_GIT_CANDIDATE=false

usage() {
    cat <<'EOF'
Usage: check-release-evidence.sh [--require-complete] [--verify-git-candidate] [--status-file PATH]

Options:
  --require-complete     Require every status gate to be PASS.
  --verify-git-candidate Verify the recorded candidate against its branch.
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
        if not value:
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

prove_commit_reachable_from_branch() {
    local commit_sha=$1
    local branch=$2
    local branch_head=$3
    local remote_name="${GIT_REMOTE:-origin}"
    local remote_ref="refs/remotes/$remote_name/$branch"
    local branch_refspec="refs/heads/$branch:$remote_ref"

    if ! git cat-file -e "${commit_sha}^{commit}" 2>/dev/null; then
        git fetch --quiet --no-tags "$remote_name" "$commit_sha" 2>/dev/null || true
    fi

    if git cat-file -e "${commit_sha}^{commit}" 2>/dev/null && \
       git merge-base --is-ancestor "$commit_sha" "$branch_head" 2>/dev/null; then
        return 0
    fi

    # A depth-1 checkout can know the remote HEAD but still lack the parent
    # chain needed to prove ancestry. Fetch only this branch's history first;
    # never treat missing shallow history as evidence of validity.
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || printf false)" == true ]]; then
        git fetch --quiet --no-tags --deepen=256 "$remote_name" "$branch_refspec" 2>/dev/null || true

        if git cat-file -e "${commit_sha}^{commit}" 2>/dev/null && \
           git merge-base --is-ancestor "$commit_sha" "$branch_head" 2>/dev/null; then
            return 0
        fi

        # If 256 commits are insufficient, complete only the named branch's
        # history. Any fetch failure leaves the verifier fail-closed below.
        if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || printf false)" == true ]]; then
            git fetch --quiet --no-tags --unshallow "$remote_name" "$branch_refspec" 2>/dev/null || true
        fi
    fi

    git cat-file -e "${commit_sha}^{commit}" 2>/dev/null && \
        git merge-base --is-ancestor "$commit_sha" "$branch_head" 2>/dev/null
}

CANDIDATE_SHA="${VAL_CANDIDATE_SHA:-}"
CANDIDATE_BRANCH="${VAL_CANDIDATE_BRANCH:-}"

if [[ -n "${VAL_ACTIVE_RELEASE_VERSION:-}" ]]; then
    SCHEMA="active-release"
    active_required=(
        VALIDATION_VERSION
        ACTIVE_RELEASE_VERSION
        ACTIVE_RELEASE_MODE
        ACTIVE_RELEASE_PROVENANCE_FILE
        ACTIVE_RELEASE_ISO_LOCAL
        ACTIVE_RELEASE_ISO_URL
        ACTIVE_RELEASE_SOURCE_COMMIT
        CANDIDATE_BRANCH
        CANDIDATE_SHA
        CANDIDATE_SELECTION_STATUS
        HOST_STATUS
        BUILD_STATUS
        CHECKSUM_STATUS
        SECURE_BOOT_STATUS
        HYPERV_STATUS
        PROXMOX_STATUS
        LIVE_ENVIRONMENT_STATUS
        CALAMARES_INSTALL_STATUS
        OFFLINE_INSTALL_STATUS
        INSTALLED_BOOT_STATUS
        GPU_DRIVERS_STATUS
        NETWORK_STACK_STATUS
        AUDIO_STATUS
        PACKAGE_ECOSYSTEM_STATUS
        DESKTOP_UI_STATUS
        UPSTREAM_PARITY_STATUS
        RELEASE_ARTIFACT_STATUS
        AUTOMATED_EVIDENCE_STATUS
        VALIDATION_WORKFLOW_STATUS
        EVIDENCE_PR_STATUS
        OVERALL_VALIDATION_STATUS
    )
    require_keys "${active_required[@]}"

    [[ "${VAL_VALIDATION_VERSION}" == "${VAL_ACTIVE_RELEASE_VERSION}" ]] \
        || fail "VALIDATION_VERSION (${VAL_VALIDATION_VERSION}) must match ACTIVE_RELEASE_VERSION (${VAL_ACTIVE_RELEASE_VERSION})."

    case "${VAL_ACTIVE_RELEASE_MODE}" in
        fresh-install-only|fresh-install-and-upgrade|upgrade-only) ;;
        *) fail "Unsupported ACTIVE_RELEASE_MODE: ${VAL_ACTIVE_RELEASE_MODE}" ;;
    esac

    [[ "$CANDIDATE_SHA" =~ ^[0-9a-fA-F]{40}$ ]] \
        || fail 'CANDIDATE_SHA must be a full 40-character hexadecimal commit SHA.'
    [[ "${VAL_ACTIVE_RELEASE_SOURCE_COMMIT}" =~ ^[0-9a-fA-F]{40}$ ]] \
        || fail 'ACTIVE_RELEASE_SOURCE_COMMIT must be a full 40-character hexadecimal commit SHA.'
    [[ "$CANDIDATE_BRANCH" =~ ^[A-Za-z0-9._/-]+$ && "$CANDIDATE_BRANCH" != */../* ]] \
        || fail "CANDIDATE_BRANCH is not a valid branch name: $CANDIDATE_BRANCH"

    [[ -f "${VAL_ACTIVE_RELEASE_PROVENANCE_FILE}" ]] \
        || fail "Active release provenance file does not exist: ${VAL_ACTIVE_RELEASE_PROVENANCE_FILE}"

    python3 - \
        "${VAL_ACTIVE_RELEASE_PROVENANCE_FILE}" \
        "${VAL_ACTIVE_RELEASE_VERSION}" \
        "${VAL_ACTIVE_RELEASE_SOURCE_COMMIT}" \
        "${VAL_ACTIVE_RELEASE_ISO_LOCAL}" <<'PYEOF' || exit 1
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
expected_version = sys.argv[2]
expected_source = sys.argv[3]
expected_iso = pathlib.Path(sys.argv[4]).name

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"[FAIL] Could not parse active release provenance {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

checks = [
    (data.get("release_version") == expected_version,
     f"provenance release_version ({data.get('release_version')}) does not match {expected_version}"),
    (data.get("candidate_sha") == expected_source,
     f"provenance candidate_sha ({data.get('candidate_sha')}) does not match ACTIVE_RELEASE_SOURCE_COMMIT ({expected_source})"),
    (pathlib.Path(str(data.get("iso_filename", ""))).name == expected_iso,
     f"provenance iso_filename ({data.get('iso_filename')}) does not match active ISO ({expected_iso})"),
    (isinstance(data.get("iso_size_bytes"), int) and data["iso_size_bytes"] > 0,
     "provenance iso_size_bytes must be a positive integer"),
    (isinstance(data.get("iso_sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", data["iso_sha256"]) is not None,
     "provenance iso_sha256 must be 64 lowercase hexadecimal characters"),
]
for ok, message in checks:
    if not ok:
        print(f"[FAIL] {message}", file=sys.stderr)
        raise SystemExit(1)
PYEOF

    active_status_keys=(
        CANDIDATE_SELECTION_STATUS
        HOST_STATUS
        BUILD_STATUS
        CHECKSUM_STATUS
        SECURE_BOOT_STATUS
        HYPERV_STATUS
        PROXMOX_STATUS
        LIVE_ENVIRONMENT_STATUS
        CALAMARES_INSTALL_STATUS
        OFFLINE_INSTALL_STATUS
        INSTALLED_BOOT_STATUS
        GPU_DRIVERS_STATUS
        NETWORK_STACK_STATUS
        AUDIO_STATUS
        PACKAGE_ECOSYSTEM_STATUS
        DESKTOP_UI_STATUS
        UPSTREAM_PARITY_STATUS
        RELEASE_ARTIFACT_STATUS
        AUTOMATED_EVIDENCE_STATUS
        VALIDATION_WORKFLOW_STATUS
        EVIDENCE_PR_STATUS
        OVERALL_VALIDATION_STATUS
    )
    validate_statuses "${active_status_keys[@]}"

    if [[ "$REQUIRE_COMPLETE" == true ]]; then
        incomplete=()
        for key in "${active_status_keys[@]}"; do
            [[ "$(value_for "$key")" == PASS ]] || incomplete+=("$key=$(value_for "$key")")
        done
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
        prove_commit_reachable_from_branch "$CANDIDATE_SHA" "$CANDIDATE_BRANCH" "$branch_head" \
            || fail "Cannot prove recorded CANDIDATE_SHA $CANDIDATE_SHA is reachable from $CANDIDATE_BRANCH HEAD $branch_head."
        pass "Recorded candidate $CANDIDATE_SHA is consistent with branch $CANDIDATE_BRANCH."
    fi
fi
