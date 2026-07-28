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
CANDIDATE2_SOURCE_STATUS="NOT_CHECKED"
CANDIDATE2_EXPECTED_SHA="unknown"
CANDIDATE2_OBSERVED_SHA="unknown"
ISO_STRUCTURE_STATUS="NOT_CHECKED"
RETIRED_CANDIDATE2_SHA="1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"

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
    SOURCE_COMMIT="${GITHUB_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)}" \
    WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-unknown}" \
    WORKFLOW_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-unknown}" \
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
    CANDIDATE2_SOURCE_STATUS="$CANDIDATE2_SOURCE_STATUS" \
    CANDIDATE2_EXPECTED_SHA="$CANDIDATE2_EXPECTED_SHA" \
    CANDIDATE2_OBSERVED_SHA="$CANDIDATE2_OBSERVED_SHA" \
    ISO_STRUCTURE_STATUS="$ISO_STRUCTURE_STATUS" \
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
    "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
    "workflow_run_attempt": os.environ["WORKFLOW_RUN_ATTEMPT"],
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
    "candidate2_source_status": os.environ["CANDIDATE2_SOURCE_STATUS"],
    "candidate2_expected_sha256": os.environ["CANDIDATE2_EXPECTED_SHA"],
    "candidate2_observed_sha256": os.environ["CANDIDATE2_OBSERVED_SHA"],
    "iso_structural_check_status": os.environ["ISO_STRUCTURE_STATUS"],
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

echo "=== Executing Operator Release Gate Strict Preflight Checks ==="

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

PHASE="candidate2_url"
cand2_url="${CANDIDATE2_ISO_URL:-${GENIXBIT_STAGING_SERVER}/iso/GenixBitOS-0.2.0-alpha-2607220558.iso}"
cand2_local="${PREFLIGHT_CANDIDATE2_LOCAL:-$REPO_ROOT/dist/GenixBitOS-0.2.0-alpha-2607220558.iso}"
if [[ -f "$cand2_local" ]] || curl --silent --head --fail "$cand2_url" >/dev/null 2>&1; then
    CANDIDATE2_SOURCE_STATUS="REACHABLE"
else
    CANDIDATE2_SOURCE_STATUS="UNREACHABLE"
    fail_phase "Candidate 2 ISO URL $cand2_url is unconfigured or unreachable."
fi

PHASE="candidate2_artifact_status"
artifact_provenance_file="${PREFLIGHT_ARTIFACT_PROVENANCE_FILE:-$REPO_ROOT/docs/releases/0.2.0-alpha-artifact.json}"
artifact_status=$(PROVENANCE_FILE="$artifact_provenance_file" python3 - <<'PYEOF'
import json
import os

with open(os.environ["PROVENANCE_FILE"], encoding="utf-8") as f:
    data = json.load(f)
print(data.get("verification_status", ""))
PYEOF
)
artifact_usable=$(PROVENANCE_FILE="$artifact_provenance_file" python3 - <<'PYEOF'
import json
import os

with open(os.environ["PROVENANCE_FILE"], encoding="utf-8") as f:
    data = json.load(f)
print(str(data.get("usable_as_migration_source", False)).lower())
PYEOF
)
if [[ "$artifact_status" == "RETIRED_INVALID_ZERO_FILLED" || "$artifact_usable" != "true" ]]; then
    fail_phase "Candidate 2 artifact is retired: recorded object is exactly 2540554240 zero bytes and is not an ISO."
fi

PHASE="candidate2_download"
mkdir -p "$(dirname "$cand2_local")"
if [[ ! -f "$cand2_local" ]]; then
    echo "[INFO] Downloading Candidate 2 ISO for structural preflight: $cand2_url"
    curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 "$cand2_url" -o "$cand2_local" || fail_phase "Failed to download Candidate 2 ISO from $cand2_url."
fi

PHASE="candidate2_sha256"
CANDIDATE2_EXPECTED_SHA=$(PROVENANCE_FILE="$artifact_provenance_file" python3 -c 'import json, os; print(json.load(open(os.environ["PROVENANCE_FILE"]))["sha256"])')
CANDIDATE2_OBSERVED_SHA=$(sha256sum "$cand2_local" | awk '{print $1}')
if [[ "$CANDIDATE2_OBSERVED_SHA" != "$CANDIDATE2_EXPECTED_SHA" ]]; then
    fail_phase "Candidate 2 ISO SHA-256 mismatch: got $CANDIDATE2_OBSERVED_SHA, expected $CANDIDATE2_EXPECTED_SHA"
fi
if [[ "$CANDIDATE2_OBSERVED_SHA" == "$RETIRED_CANDIDATE2_SHA" ]]; then
    fail_phase "Candidate 2 artifact is retired: recorded object is exactly 2540554240 zero bytes and is not an ISO."
fi

PHASE="iso_structure"
ISO_STRUCTURE_STATUS="RUNNING"
iso_structure_command="${PREFLIGHT_ISO_STRUCTURE_COMMAND:-bash "$REPO_ROOT/tools/validation/check-iso-structure.sh" --iso "$cand2_local"}"
if bash -c "$iso_structure_command"; then
    ISO_STRUCTURE_STATUS="PASS"
else
    ISO_STRUCTURE_STATUS="FAIL"
    fail_phase "Candidate 2 ISO structural validation failed."
fi

echo "[PASS] All preflight system, hardware, network, secret, checksum, and ISO structure requirements verified."
