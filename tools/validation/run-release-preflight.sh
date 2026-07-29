#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

RESULTS_DIR="${PREFLIGHT_RESULTS_DIR:-$REPO_ROOT/infra/package-staging/results/stage-logs}"
RESULT_FILE="$RESULTS_DIR/preflight-results.json"
START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PHASE="initialization"
FAILURE_REASON=""

ARCH="unknown"
CPU_THREADS=0
AVAILABLE_MEMORY_KB=0
AVAILABLE_DISK_KB=0
KVM_STATE="UNKNOWN"
KVM_AVAILABLE=false
OVMF_CODE=""
OVMF_VARS=""
SEABIOS=""
STAGING_STATUS="NOT_CHECKED"
ACTIVE_RELEASE_VERSION="${ACTIVE_RELEASE_VERSION:-0.3.0-alpha}"
ACTIVE_RELEASE_MODE="${ACTIVE_RELEASE_MODE:-fresh-install-only}"
ACTIVE_RELEASE_SOURCE_COMMIT="${ACTIVE_RELEASE_SOURCE_COMMIT:-${EXPECTED_CANDIDATE_SHA:-${GITHUB_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)}}}"
ACTIVE_RELEASE_PROVENANCE_FILE="${ACTIVE_RELEASE_PROVENANCE_FILE:-docs/releases/0.3.0-alpha-artifact.json}"
ACTIVE_ARTIFACT_STATUS="PENDING_BUILD"
RETIRED_CANDIDATE2_SHA="1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"
EXPECTED_CANDIDATE_BRANCH="${EXPECTED_CANDIDATE_BRANCH:-validation/0.3.0-alpha-candidate-2}"
EXPECTED_CANDIDATE_SHA="${EXPECTED_CANDIDATE_SHA:-$ACTIVE_RELEASE_SOURCE_COMMIT}"
WORKFLOW_RUN_ID="${WORKFLOW_RUN_ID:-${GITHUB_RUN_ID:-unknown}}"
WORKFLOW_RUN_ATTEMPT="${WORKFLOW_RUN_ATTEMPT:-${GITHUB_RUN_ATTEMPT:-unknown}}"
WORKFLOW_DISPATCH_REF_SHA="${WORKFLOW_DISPATCH_REF_SHA:-${GITHUB_SHA:-$ACTIVE_RELEASE_SOURCE_COMMIT}}"
GIT_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"

write_result() {
    local status="$1"
    local exit_code="$2"
    local failed_phase="$3"
    local failure_reason="$4"
    local completion_ts
    completion_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$RESULTS_DIR"

    RESULT_FILE="$RESULT_FILE" \
    STATUS="$status" \
    EXIT_CODE="$exit_code" \
    FAILED_PHASE="$failed_phase" \
    FAILURE_REASON="$failure_reason" \
    SOURCE_COMMIT="$ACTIVE_RELEASE_SOURCE_COMMIT" \
    GIT_HEAD="$GIT_HEAD" \
    EXPECTED_CANDIDATE_BRANCH="$EXPECTED_CANDIDATE_BRANCH" \
    EXPECTED_CANDIDATE_SHA="$EXPECTED_CANDIDATE_SHA" \
    WORKFLOW_RUN_ID="$WORKFLOW_RUN_ID" \
    WORKFLOW_RUN_ATTEMPT="$WORKFLOW_RUN_ATTEMPT" \
    WORKFLOW_DISPATCH_REF_SHA="$WORKFLOW_DISPATCH_REF_SHA" \
    RUNNER_NAME_VALUE="${RUNNER_NAME:-self-hosted}" \
    ARCH="$ARCH" \
    CPU_THREADS="$CPU_THREADS" \
    AVAILABLE_MEMORY_KB="$AVAILABLE_MEMORY_KB" \
    AVAILABLE_DISK_KB="$AVAILABLE_DISK_KB" \
    KVM_STATE="$KVM_STATE" \
    KVM_AVAILABLE="$KVM_AVAILABLE" \
    OVMF_CODE="$OVMF_CODE" \
    OVMF_VARS="$OVMF_VARS" \
    SEABIOS="$SEABIOS" \
    STAGING_STATUS="$STAGING_STATUS" \
    ACTIVE_RELEASE_VERSION="$ACTIVE_RELEASE_VERSION" \
    ACTIVE_RELEASE_MODE="$ACTIVE_RELEASE_MODE" \
    ACTIVE_RELEASE_SOURCE_COMMIT="$ACTIVE_RELEASE_SOURCE_COMMIT" \
    ACTIVE_RELEASE_PROVENANCE_FILE="$ACTIVE_RELEASE_PROVENANCE_FILE" \
    ACTIVE_ARTIFACT_STATUS="$ACTIVE_ARTIFACT_STATUS" \
    START_TS="$START_TS" \
    COMPLETION_TS="$completion_ts" \
    python3 - <<'PYEOF'
import json
import os

def as_int(name):
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return 0

def as_bool(name):
    return os.environ.get(name, "false").lower() == "true"

data = {
    "source_commit": os.environ["SOURCE_COMMIT"],
    "git_head": os.environ["GIT_HEAD"],
    "expected_candidate_branch": os.environ["EXPECTED_CANDIDATE_BRANCH"],
    "expected_candidate_sha": os.environ["EXPECTED_CANDIDATE_SHA"],
    "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
    "workflow_run_attempt": os.environ["WORKFLOW_RUN_ATTEMPT"],
    "workflow_dispatch_ref_sha": os.environ["WORKFLOW_DISPATCH_REF_SHA"],
    "runner_name": os.environ["RUNNER_NAME_VALUE"],
    "architecture": os.environ["ARCH"],
    "cpu_threads": as_int("CPU_THREADS"),
    "available_memory_kb": as_int("AVAILABLE_MEMORY_KB"),
    "available_disk_kb": as_int("AVAILABLE_DISK_KB"),
    "kvm_state": os.environ["KVM_STATE"],
    "kvm_available": as_bool("KVM_AVAILABLE"),
    "firmware_paths": {
        "ovmf_code": os.environ["OVMF_CODE"],
        "ovmf_vars": os.environ["OVMF_VARS"],
        "seabios": os.environ["SEABIOS"],
    },
    "staging_status": os.environ["STAGING_STATUS"],
    "active_release_version": os.environ["ACTIVE_RELEASE_VERSION"],
    "active_release_mode": os.environ["ACTIVE_RELEASE_MODE"],
    "active_release_source_commit": os.environ["ACTIVE_RELEASE_SOURCE_COMMIT"],
    "active_release_provenance_file": os.environ["ACTIVE_RELEASE_PROVENANCE_FILE"],
    "active_artifact_status": os.environ["ACTIVE_ARTIFACT_STATUS"],
    "start_timestamp": os.environ["START_TS"],
    "completion_timestamp": os.environ["COMPLETION_TS"],
    "exit_code": as_int("EXIT_CODE"),
    "status": os.environ["STATUS"],
}

if os.environ["STATUS"] != "PASS":
    data["failed_phase"] = os.environ["FAILED_PHASE"]
    data["failure_reason"] = os.environ["FAILURE_REASON"]

with open(os.environ["RESULT_FILE"], "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
}

on_exit() {
    local exit_code=$?
    if ((exit_code == 0)); then
        write_result "PASS" 0 "" ""
    else
        write_result "FAIL" "$exit_code" "$PHASE" "${FAILURE_REASON:-preflight failed during phase $PHASE with exit code $exit_code}"
    fi
    exit "$exit_code"
}
trap on_exit EXIT

fail_phase() {
    FAILURE_REASON="$1"
    printf '[FAIL] %s\n' "$FAILURE_REASON" >&2
    exit 1
}

first_existing_path() {
    local candidates="$1"
    local path
    IFS=':' read -r -a paths <<< "$candidates"
    for path in "${paths[@]}"; do
        if [[ -f "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    return 1
}

repo_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$REPO_ROOT" "$1" ;;
    esac
}

echo "=== Executing Operator Release Gate Strict Preflight Checks ==="

PHASE="candidate_sha_binding"
[[ "$ACTIVE_RELEASE_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail_phase "ACTIVE_RELEASE_SOURCE_COMMIT must be a 40-character lowercase hexadecimal SHA."
if [[ "${PREFLIGHT_STRICT_HEAD_MATCH:-true}" == "true" ]]; then
    [[ "$GIT_HEAD" == "$ACTIVE_RELEASE_SOURCE_COMMIT" ]] || fail_phase "git HEAD ($GIT_HEAD) does not match ACTIVE_RELEASE_SOURCE_COMMIT ($ACTIVE_RELEASE_SOURCE_COMMIT)."
fi
if [[ -n "${EXPECTED_CANDIDATE_SHA:-}" && "$EXPECTED_CANDIDATE_SHA" != "unknown" ]]; then
    [[ "$EXPECTED_CANDIDATE_SHA" == "$ACTIVE_RELEASE_SOURCE_COMMIT" ]] || fail_phase "EXPECTED_CANDIDATE_SHA ($EXPECTED_CANDIDATE_SHA) does not match ACTIVE_RELEASE_SOURCE_COMMIT ($ACTIVE_RELEASE_SOURCE_COMMIT)."
fi

PHASE="architecture"
ARCH=$(uname -m)
[[ "$ARCH" == "x86_64" ]] || fail_phase "Runner architecture is $ARCH, required x86_64."

PHASE="kvm"
KVM_PATH="${PREFLIGHT_KVM_PATH:-/dev/kvm}"
if [[ -e "$KVM_PATH" && -r "$KVM_PATH" && -w "$KVM_PATH" ]]; then
    KVM_STATE="READY:$KVM_PATH"
    KVM_AVAILABLE=true
else
    KVM_STATE="MISSING_OR_UNUSABLE:$KVM_PATH"
    fail_phase "Hardware virtualization $KVM_PATH is missing or not readable/writable."
fi

PHASE="required_binaries"
req_binaries=(qemu-system-x86_64 qemu-img timeout socat jq curl sha256sum sha512sum xorriso isoinfo mksquashfs unsquashfs gpg gpgv dpkg-deb apt-get python3)
for b in "${req_binaries[@]}"; do
    command -v "$b" >/dev/null 2>&1 || fail_phase "Required preflight binary missing: $b"
done

PHASE="python_jsonschema"
python3 -c "import jsonschema" >/dev/null 2>&1 || fail_phase "Required python module jsonschema is missing."

PHASE="firmware"
OVMF_CODE=$(first_existing_path "${PREFLIGHT_OVMF_CODE_CANDIDATES:-/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_CODE.fd:/usr/share/ovmf/OVMF.fd:/usr/share/edk2/ovmf/OVMF_CODE.fd}" || true)
OVMF_VARS=$(first_existing_path "${PREFLIGHT_OVMF_VARS_CANDIDATES:-/usr/share/OVMF/OVMF_VARS_4M.fd:/usr/share/OVMF/OVMF_VARS.fd:/usr/share/ovmf/OVMF_VARS.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd}" || true)
SEABIOS=$(first_existing_path "${PREFLIGHT_SEABIOS_CANDIDATES:-/usr/share/seabios/bios-256k.bin:/usr/share/seabios/bios.bin:/usr/share/qemu/bios-256k.bin}" || true)
[[ -n "$OVMF_CODE" && -n "$OVMF_VARS" ]] || fail_phase "OVMF UEFI firmware image or vars missing."
[[ -n "$SEABIOS" ]] || fail_phase "SeaBIOS legacy firmware image missing."

PHASE="disk"
AVAILABLE_DISK_KB=$(df -k . | awk 'NR==2 {print $4}')
MIN_DISK_KB="${PREFLIGHT_MIN_DISK_KB:-83886080}"
((AVAILABLE_DISK_KB >= MIN_DISK_KB)) || fail_phase "Insufficient disk space for ISO build and VM testing (found ${AVAILABLE_DISK_KB} KB, required >= ${MIN_DISK_KB} KB)."

PHASE="memory"
AVAILABLE_MEMORY_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}' || awk 'NR==2 {print $4}' <(free -k))
MIN_MEMORY_KB="${PREFLIGHT_MIN_MEMORY_KB:-16777216}"
((AVAILABLE_MEMORY_KB >= MIN_MEMORY_KB)) || fail_phase "Insufficient available RAM (found ${AVAILABLE_MEMORY_KB} KB, required >= ${MIN_MEMORY_KB} KB)."

PHASE="cpu"
CPU_THREADS=$(nproc || echo 1)
MIN_CPU_THREADS="${PREFLIGHT_MIN_CPU_THREADS:-4}"
((CPU_THREADS >= MIN_CPU_THREADS)) || fail_phase "Insufficient CPU threads (found ${CPU_THREADS}, required >= ${MIN_CPU_THREADS})."

PHASE="secret"
[[ -n "${STAGING_SIGNING_PASSPHRASE:-}" ]] || fail_phase "Protected secret STAGING_SIGNING_PASSPHRASE is empty or unmapped."

PHASE="staging_server"
[[ -n "${GENIXBIT_STAGING_SERVER:-}" ]] || fail_phase "GENIXBIT_STAGING_SERVER variable is empty or unconfigured."
if curl --silent --head --fail "$GENIXBIT_STAGING_SERVER" >/dev/null 2>&1; then
    STAGING_STATUS="REACHABLE"
else
    STAGING_STATUS="UNREACHABLE"
    fail_phase "Staging server $GENIXBIT_STAGING_SERVER is unreachable."
fi

PHASE="staging_metadata"
staging_meta="${GENIXBIT_STAGING_SERVER}/dists/resolute-alpha/Release"
curl --silent --head --fail "$staging_meta" >/dev/null 2>&1 || fail_phase "Staging metadata endpoint $staging_meta is unreachable."

PHASE="active_artifact_pending"
ACTIVE_RELEASE_PROVENANCE_PATH=$(repo_path "$ACTIVE_RELEASE_PROVENANCE_FILE")
python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" \
  --repo-root "$REPO_ROOT" \
  --release-version "$ACTIVE_RELEASE_VERSION" \
  --mode "$ACTIVE_RELEASE_MODE" \
  --provenance-file "$ACTIVE_RELEASE_PROVENANCE_PATH" \
  --allow-pending >/dev/null || fail_phase "Active release artifact provenance is not in the expected pre-build state."
ACTIVE_ARTIFACT_STATUS="PENDING_BUILD"

echo "[PASS] Host, hardware, dependency, staging, and pending active-artifact preflight verified. ISO build is the next gate phase."
