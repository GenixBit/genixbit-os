#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs Candidate 2 ISO into target QCOW2 virtual disk image using managed background VM lifecycle,
# autoinstall seed media, guest-produced completion token, offline disk inspection, and authenticated
# SSH installed-boot verification.
#
# The target disk MUST begin as a genuinely blank installation target. Only the installer running
# inside QEMU may create partitions, filesystems, OS files, user accounts, SSH authorization,
# bootloader, kernel, initramfs, and the completion token.
# Guestfish may inspect the disk AFTER shutdown but MUST NOT fabricate the installed state.
#
# Emits GENIXBIT_CANDIDATE2_INSTALL_STATE=<path> state file with 0600 permissions AFTER all
# verification steps succeed.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=2700
RUNTIME_EVIDENCE_DIR=""
C2_SOURCE_COMMIT=""
RETIRED_CANDIDATE2_SHA="1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"

fail() {
    printf '[FAIL] install-candidate2.sh: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$*"
}

while (($# > 0)); do
    case "$1" in
        --iso)
            (($# >= 2)) || fail '--iso requires a path.'
            ISO_PATH=$2
            shift 2
            ;;
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        --runtime-evidence-dir)
            (($# >= 2)) || fail '--runtime-evidence-dir requires a path.'
            RUNTIME_EVIDENCE_DIR=$2
            shift 2
            ;;
        --source-commit)
            (($# >= 2)) || fail '--source-commit requires a git SHA.'
            C2_SOURCE_COMMIT=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

# Initialize every lifecycle variable before EXIT trap can run
VM_ID="not-created"
INSTALLED_VM_ID="not-created"
state_dir=""
serial_log=""
qmp_path=""
pid_file=""
installed_pid_file=""
installed_qmp_path=""
INSTALLER_VM_PID=""
INSTALLED_VM_PID=""
INSTALLER_VM_STARTED=false
INSTALLED_VM_STARTED=false
INSTALL_PHASE="initialization"
INSTALL_EXIT_CODE=0
CLEANUP_RUNNING=false
WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-local}"
EXECUTION_ID="${WORKFLOW_RUN_ID}-$(date +%s)-$$"
screenshot_path=""
disk_inspect_json=""
completion_json=""
kernel_extraction_json=""
failure_summary_json=""

# 1. Resolve repository root
REPO_TOP=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# 2. Create a fallback persistent runtime directory
if [[ -z "$RUNTIME_EVIDENCE_DIR" ]]; then
    RUNTIME_EVIDENCE_DIR="$REPO_TOP/infra/package-staging/results/runtime/local-$(date +%s)-$$"
fi
mkdir -p "$RUNTIME_EVIDENCE_DIR"
failure_summary_json="${RUNTIME_EVIDENCE_DIR}/failure-summary.json"

# 3. Initialize safe VM IDs and paths (placeholder values for early-exit safety)
state_log_base="$REPO_TOP/infra/package-staging/results"
stage_logs_dir="$state_log_base/stage-logs"
mkdir -p "$stage_logs_dir" 2>/dev/null || true

[[ -n "$C2_SOURCE_COMMIT" ]] || C2_SOURCE_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

load_candidate2_provenance() {
    local provenance_file="$1"
    [[ -f "$provenance_file" && -r "$provenance_file" ]] || fail "Candidate 2 provenance file missing or unreadable: $provenance_file"

    local parsed rc
    set +e
    parsed=$(PROVENANCE_FILE="$provenance_file" python3 - <<'PYEOF'
import json
import os
import re
import sys

try:
    with open(os.environ["PROVENANCE_FILE"], encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:
    print(exc, file=sys.stderr)
    sys.exit(1)

status = str(data.get("verification_status", ""))
usable = data.get("usable_as_migration_source") is True
sha256 = str(data.get("sha256", ""))
if not re.fullmatch(r"[0-9a-f]{64}", sha256):
    sys.exit(2)
print(status)
print("true" if usable else "false")
print(sha256)
PYEOF
)
    rc=$?
    set -e

    if ((rc == 2)); then
        fail "Candidate 2 provenance file sha256 field is missing or invalid."
    elif ((rc != 0)); then
        fail "Candidate 2 provenance file is malformed: $provenance_file"
    fi

    CAND2_METADATA_STATUS=$(printf '%s\n' "$parsed" | sed -n '1p')
    CAND2_METADATA_USABLE=$(printf '%s\n' "$parsed" | sed -n '2p')
    CAND2_EXPECTED_SHA=$(printf '%s\n' "$parsed" | sed -n '3p')

    if [[ "$CAND2_METADATA_STATUS" == "RETIRED_INVALID_ZERO_FILLED" || "$CAND2_METADATA_USABLE" != "true" ]]; then
        fail "Candidate 2 artifact is retired or unusable: recorded object must not be used as an installation or migration source."
    fi
    if [[ "$CAND2_EXPECTED_SHA" == "$RETIRED_CANDIDATE2_SHA" ]]; then
        fail "Candidate 2 artifact is retired: recorded object is exactly 2540554240 zero bytes and is not an ISO."
    fi
    if [[ "$CAND2_METADATA_STATUS" != "PASS" ]]; then
        fail "Candidate 2 provenance status '$CAND2_METADATA_STATUS' is not an active artifact status."
    fi
}

# --- Helper functions ---

preserve_install_evidence() {
    local original_exit="$1"

    [[ "$CLEANUP_RUNNING" == "false" ]] || return 0
    CLEANUP_RUNNING=true

    mkdir -p "$RUNTIME_EVIDENCE_DIR"

    if [[ -n "${serial_log:-}" && -f "$serial_log" ]]; then
        cp -f "$serial_log" \
          "$RUNTIME_EVIDENCE_DIR/installer.serial.log" 2>/dev/null || true
    fi

    if [[ -n "${state_dir:-}" && "${VM_ID:-not-created}" != "not-created" ]]; then
        cp -f "${state_dir}/qemu-${VM_ID}.stderr" \
          "$RUNTIME_EVIDENCE_DIR/qemu.stderr.log" 2>/dev/null || true

        cp -f "${state_dir}/vm-${VM_ID}.json" \
          "$RUNTIME_EVIDENCE_DIR/installer-vm-state.raw.json" 2>/dev/null || true
    fi

    if [[ -n "${state_dir:-}" && "${INSTALLED_VM_ID:-not-created}" != "not-created" ]]; then
        cp -f "${state_dir}/vm-${INSTALLED_VM_ID}.json" \
          "$RUNTIME_EVIDENCE_DIR/installed-vm-state.raw.json" 2>/dev/null || true
    fi

    if [[ -n "${qmp_path:-}" && -S "$qmp_path" ]]; then
        bash "$(dirname "$0")/capture-screenshot.sh" \
          --socket "$qmp_path" \
          --output "$RUNTIME_EVIDENCE_DIR/final-installer.ppm" \
          2>/dev/null || true
    fi
}

cleanup_managed_vm() {
    local vm_id="$1"
    local vm_pid_file="$2"
    local vm_qmp_socket="$3"
    local vm_state_dir="$4"
    local vm_label="$5"

    local shutdown_json="$vm_state_dir/shutdown-${vm_id}.json"

    if [[ -f "$vm_pid_file" ]]; then
        local vpid
        vpid=$(cat "$vm_pid_file" 2>/dev/null || echo "")
        if [[ -n "$vpid" ]] && kill -0 "$vpid" 2>/dev/null; then
            info "Stopping $vm_label VM ($vm_id) via managed shutdown..."
            if [[ -S "$vm_qmp_socket" ]]; then
                bash "$(dirname "$0")/capture-screenshot.sh" \
                  --socket "$vm_qmp_socket" \
                  --output "${RUNTIME_EVIDENCE_DIR}/final-${vm_label}.ppm" \
                  2>/dev/null || true
            fi
            set +e
            bash "$(dirname "$0")/run-qemu.sh" stop \
                --vm-id "$vm_id" \
                --pid-file "$vm_pid_file" \
                --qmp-socket "$vm_qmp_socket" \
                --state-dir "$vm_state_dir"
            stop_rc=$?
            set -e

            local shutdown_state="MISSING_EVIDENCE"
            if [[ -f "$shutdown_json" ]]; then
                shutdown_state=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("shutdown_state", "MISSING"))
' "$shutdown_json" 2>/dev/null || echo "MISSING")
            fi

            case "$shutdown_state" in
                FORCED_SIGTERM|FORCED_SIGKILL|STOP_FAILED|MISSING|MISSING_EVIDENCE)
                    printf '[FAIL] Cleanup of %s VM (%s) resulted in %s (rc=%s)\n' "$vm_label" "$vm_id" "$shutdown_state" "$stop_rc" >&2
                    return 1
                    ;;
                *)
                    printf '[PASS] Cleanup of %s VM (%s) state=%s (rc=%s)\n' "$vm_label" "$vm_id" "$shutdown_state" "$stop_rc"
                    return 0
                    ;;
            esac
        fi
    fi
    if [[ -S "$vm_qmp_socket" ]]; then
        rm -f "$vm_qmp_socket"
    fi
    return 0
}

cleanup_exit() {
    local exit_code="$1"
    INSTALL_EXIT_CODE=$exit_code

    if [[ -n "${state_dir:-}" && "${VM_ID:-not-created}" != "not-created" ]]; then
        cp -f "${state_dir}/vm-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installer-vm-state.before-cleanup.json" 2>/dev/null || true
        cp -f "${state_dir}/shutdown-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installer-shutdown-result.before-cleanup.json" 2>/dev/null || true
    fi

    local installer_cleanup_state="NOT_STARTED"
    local installer_cleanup_exit=0
    if [[ "$INSTALLER_VM_STARTED" == "true" ]]; then
        local shutdown_json="$state_dir/shutdown-${VM_ID}.json"
        if cleanup_managed_vm "$VM_ID" "$pid_file" "$qmp_path" "$state_dir" "installer"; then
            installer_cleanup_exit=0
        else
            installer_cleanup_exit=$?
        fi
        if [[ -f "$shutdown_json" ]]; then
            installer_cleanup_state=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("shutdown_state", "MISSING_EVIDENCE"))
' "$shutdown_json" 2>/dev/null || echo "MISSING_EVIDENCE")
        else
            installer_cleanup_state="MISSING_EVIDENCE"
        fi
    fi

    local installed_cleanup_state="NOT_STARTED"
    local installed_cleanup_exit=0
    if [[ "$INSTALLED_VM_STARTED" == "true" ]]; then
        local inst_pid="${state_dir}/qemu-${VM_ID}_inst.pid"
        local inst_qmp="${state_dir}/qmp-${VM_ID}_inst.sock"
        local shutdown_json="$state_dir/shutdown-${VM_ID}_inst.json"
        if cleanup_managed_vm "${VM_ID}_inst" "$inst_pid" "$inst_qmp" "$state_dir" "installed"; then
            installed_cleanup_exit=0
        else
            installed_cleanup_exit=$?
        fi
        if [[ -f "$shutdown_json" ]]; then
            installed_cleanup_state=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("shutdown_state", "MISSING_EVIDENCE"))
' "$shutdown_json" 2>/dev/null || echo "MISSING_EVIDENCE")
        else
            installed_cleanup_state="MISSING_EVIDENCE"
        fi
    fi

    # Verify original PIDs directly — not inferred from PID file
    local installer_alive=false
    if [[ -n "$INSTALLER_VM_PID" ]] && kill -0 "$INSTALLER_VM_PID" 2>/dev/null; then
        installer_alive=true
    fi

    local installed_alive=false
    if [[ -n "$INSTALLED_VM_PID" ]] && kill -0 "$INSTALLED_VM_PID" 2>/dev/null; then
        installed_alive=true
    fi

    preserve_install_evidence "$exit_code"

    if [[ -n "${state_dir:-}" && "${VM_ID:-not-created}" != "not-created" ]]; then
        cp -f "${state_dir}/shutdown-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installer-shutdown-result.json" 2>/dev/null || true
        cp -f "${state_dir}/vm-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installer-vm-state.final.json" 2>/dev/null || true
    fi

    if [[ -n "${state_dir:-}" && "${INSTALLED_VM_ID:-not-created}" != "not-created" ]]; then
        if [[ -f "${state_dir}/shutdown-${INSTALLED_VM_ID}.json" ]]; then
            cp -f "${state_dir}/shutdown-${INSTALLED_VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installed-shutdown-result.json" 2>/dev/null || true
        fi
        if [[ -f "${state_dir}/vm-${INSTALLED_VM_ID}.json" ]]; then
            cp -f "${state_dir}/vm-${INSTALLED_VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installed-vm-state.final.json" 2>/dev/null || true
        fi
        if [[ -f "${state_dir}/installed-guest-health.json" ]]; then
            cp -f "${state_dir}/installed-guest-health.json" "$RUNTIME_EVIDENCE_DIR/installed-guest-health.json" 2>/dev/null || true
        fi
    fi

    if [[ -n "${pid_file:-}" ]]; then
        rm -f "$pid_file" 2>/dev/null || true
    fi
    if [[ -n "${qmp_path:-}" ]]; then
        rm -f "$qmp_path" 2>/dev/null || true
    fi

    # Determine cleanup exit code: nonzero if any cleanup failed
    local cleanup_rc=0
    if [[ "$installer_cleanup_exit" -ne 0 ]]; then
        cleanup_rc=$installer_cleanup_exit
    fi
    if [[ "$installed_cleanup_exit" -ne 0 ]]; then
        cleanup_rc=$installed_cleanup_exit
    fi
    if [[ "$installer_alive" == "true" ]]; then
        printf '[FAIL] Installer VM process still alive after cleanup\n' >&2
        cleanup_rc=1
    fi
    if [[ "$installed_alive" == "true" ]]; then
        printf '[FAIL] Installed VM process still alive after cleanup\n' >&2
        cleanup_rc=1
    fi

    if (( exit_code != 0 || cleanup_rc != 0 )); then
        local failure_class="functional_failure"
        local functional_exit_code="$exit_code"
        local cleanup_exit_code="$cleanup_rc"
        if (( exit_code == 0 && cleanup_rc != 0 )); then
            failure_class="cleanup_failure"
        elif (( exit_code != 0 && cleanup_rc != 0 )); then
            failure_class="both_failed"
        fi
        C2_SOURCE_COMMIT="$C2_SOURCE_COMMIT" \
        WF_RUN_ID="$WORKFLOW_RUN_ID" \
        EXECUTION_ID="$EXECUTION_ID" \
        VM_ID="$VM_ID" \
        INSTALL_PHASE="$INSTALL_PHASE" \
        EXIT_CODE="$functional_exit_code" \
        CLEANUP_EXIT="$cleanup_exit_code" \
        FAILURE_CLASS="$failure_class" \
        CAND2_VERIFIED_SHA="${CAND2_VERIFIED_SHA:-unknown}" \
        CAND2_VERIFIED_SHA512="${CAND2_VERIFIED_SHA512:-unknown}" \
        KERNEL_SHA256="${KERNEL_SHA256:-unknown}" \
        INITRD_SHA256="${INITRD_SHA256:-unknown}" \
        SEED_SHA256="${SEED_SHA256:-unknown}" \
        KERNEL_APPEND="${KERNEL_APPEND:-unknown}" \
        RUNTIME_EVIDENCE_DIR="$RUNTIME_EVIDENCE_DIR" \
        INSTALLER_VM_STARTED="$INSTALLER_VM_STARTED" \
        INSTALLED_VM_STARTED="$INSTALLED_VM_STARTED" \
        INSTALLER_CLEANUP_STATE="$installer_cleanup_state" \
        INSTALLED_CLEANUP_STATE="$installed_cleanup_state" \
        INSTALLER_CLEANUP_EXIT="$installer_cleanup_exit" \
        INSTALLED_CLEANUP_EXIT="$installed_cleanup_exit" \
        INSTALLER_ALIVE="$installer_alive" \
        INSTALLED_ALIVE="$installed_alive" \
        FAILURE_SUMMARY_JSON="$failure_summary_json" \
        python3 - <<'PYEOF'
import json, os, datetime

def boolean(name: str) -> bool:
    value = os.environ.get(name, "").strip().lower()
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be true or false, got {value!r}")
    return value == "true"

summary = {
    "source_commit": os.environ["C2_SOURCE_COMMIT"],
    "workflow_run_id": os.environ["WF_RUN_ID"],
    "execution_id": os.environ["EXECUTION_ID"],
    "vm_id": os.environ["VM_ID"],
    "phase": os.environ["INSTALL_PHASE"],
    "functional_exit_code": int(os.environ["EXIT_CODE"]),
    "cleanup_exit_code": int(os.environ.get("CLEANUP_EXIT", "0")),
    "final_exit_code": int(os.environ["EXIT_CODE"]) if int(os.environ["EXIT_CODE"]) != 0 else int(os.environ.get("CLEANUP_EXIT", "0")),
    "failure_class": os.environ["FAILURE_CLASS"],
    "failure_reason": f"install-candidate2.sh failed during phase {os.environ['INSTALL_PHASE']} with exit code {os.environ['EXIT_CODE']}",
    "source_iso_sha256": os.environ.get("CAND2_VERIFIED_SHA", "unknown"),
    "source_iso_sha512": os.environ.get("CAND2_VERIFIED_SHA512", "unknown"),
    "kernel_sha256": os.environ.get("KERNEL_SHA256", "unknown"),
    "initrd_sha256": os.environ.get("INITRD_SHA256", "unknown"),
    "seed_iso_sha256": os.environ.get("SEED_SHA256", "unknown"),
    "kernel_command_line": os.environ.get("KERNEL_APPEND", "unknown"),
    "runtime_evidence_dir": os.environ["RUNTIME_EVIDENCE_DIR"],
    "installer_vm_started": boolean("INSTALLER_VM_STARTED"),
    "installed_vm_started": boolean("INSTALLED_VM_STARTED"),
    "installer_cleanup_state": os.environ["INSTALLER_CLEANUP_STATE"],
    "installed_cleanup_state": os.environ["INSTALLED_CLEANUP_STATE"],
    "installer_cleanup_exit_code": int(os.environ.get("INSTALLER_CLEANUP_EXIT", "0")),
    "installed_cleanup_exit_code": int(os.environ.get("INSTALLED_CLEANUP_EXIT", "0")),
    "installer_process_alive_after_cleanup": boolean("INSTALLER_ALIVE"),
    "installed_process_alive_after_cleanup": boolean("INSTALLED_ALIVE"),
    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": "FAIL",
}
with open(os.environ["FAILURE_SUMMARY_JSON"], "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2)
PYEOF
    fi

    return "$cleanup_rc"
}

on_exit() {
    local original_exit=$?

    trap - EXIT
    set +e
    cleanup_exit "$original_exit"
    local cleanup_rc=$?
    set -e

    if (( original_exit != 0 )); then
        exit "$original_exit"
    fi

    exit "$cleanup_rc"
}

# Install EXIT trap only after every referenced handler is defined.
trap on_exit EXIT

# Validate ISO, disk, mode, checksums, and dependencies after trap setup.
INSTALL_PHASE="validation_mode"
case "$MODE" in
    uefi|bios)
        ;;
    *)
        fail "--mode must be uefi or bios."
        ;;
esac

INSTALL_PHASE="validation_iso_path"
[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || fail 'Valid --iso path is required.'

INSTALL_PHASE="validation_disk_arg"
[[ -n "$DISK_PATH" ]] || fail '--disk path is required.'

INSTALL_PHASE="validation_artifact_status"
artifact_file="${CANDIDATE2_PROVENANCE_FILE:-$REPO_TOP/docs/releases/0.2.0-alpha-artifact.json}"
CAND2_METADATA_STATUS=""
CAND2_METADATA_USABLE=""
CAND2_EXPECTED_SHA=""
load_candidate2_provenance "$artifact_file"

INSTALL_PHASE="validation_iso_nonempty"
[[ -s "$ISO_PATH" ]] || fail 'Candidate 2 ISO file is empty.'

INSTALL_PHASE="validation_iso_checksum"
CAND2_VERIFIED_SHA=$(sha256sum "$ISO_PATH" | awk '{print $1}')
if [[ "$CAND2_VERIFIED_SHA" == "$RETIRED_CANDIDATE2_SHA" ]]; then
    fail "Candidate 2 artifact is retired: recorded object is exactly 2540554240 zero bytes and is not an ISO."
fi
if [[ "$CAND2_VERIFIED_SHA" != "$CAND2_EXPECTED_SHA" ]]; then
    fail "Candidate 2 ISO SHA-256 mismatch! Got ${CAND2_VERIFIED_SHA}; expected ${CAND2_EXPECTED_SHA}."
fi

# Lifecycle variables — remaining setup after validation inputs are safe.
VM_ID="cand2_${MODE}_$(date +%s)_$$"
state_dir="$(dirname "$DISK_PATH")/cand2-${MODE}-state"
mkdir -p "$state_dir"

serial_log="${RUNTIME_EVIDENCE_DIR}/installer.serial.log"
qmp_path="${state_dir}/qmp-${VM_ID}.sock"
pid_file="${state_dir}/qemu-${VM_ID}.pid"
screenshot_path="${RUNTIME_EVIDENCE_DIR}/installer.ppm"
disk_inspect_json="${RUNTIME_EVIDENCE_DIR}/disk-inspection-${MODE}.json"
completion_json="${RUNTIME_EVIDENCE_DIR}/install-completion.json"
kernel_extraction_json="${RUNTIME_EVIDENCE_DIR}/kernel-extraction.json"

CAND2_VERIFIED_SHA512=$(sha512sum "$ISO_PATH" | awk '{print $1}')
info "Candidate 2 ISO SHA-256 verified: $CAND2_VERIFIED_SHA"
info "Candidate 2 ISO SHA-512 verified: ${CAND2_VERIFIED_SHA512:0:16}..."

# 3. Create GENUINELY BLANK target QCOW2 disk.
# The target disk must be blank. The installer running inside QEMU is the ONLY entity
# permitted to partition, format, and populate this disk.
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

# 4. Generate ephemeral SSH keypair and extract real fingerprint (FAIL CLOSED on fingerprint failure)
KEY_JSON=$(bash "$(dirname "$0")/create-ephemeral-key.sh" --vm-id "$VM_ID" --state-dir "$state_dir")
echo "$KEY_JSON" | python3 -c "import sys, json; json.load(sys.stdin)" || fail "create-ephemeral-key.sh produced invalid JSON output!"
SSH_KEY=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['private_key_path'])")
SSH_PUB=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['public_key_path'])")

SSH_FP=$(ssh-keygen -lf "$SSH_PUB" 2>/dev/null | awk '{print $2}')
[[ -n "$SSH_FP" && "$SSH_FP" =~ ^SHA256: ]] || fail "SSH public key fingerprint extraction failed for $SSH_PUB!"

# 5. Allocate unique loopback SSH port
SSH_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")

# 6. Build autoinstall seed media
RUN_ID="$(date +%s)_$$"
INSTALL_TOKEN="GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_cand2"

SEED_JSON=$(bash "$(dirname "$0")/create-autoinstall-seed.sh" \
    --vm-id "$VM_ID" \
    --hostname "genixbit-cand2" \
    --username "genixbit" \
    --ssh-key "$SSH_PUB" \
    --token "$INSTALL_TOKEN" \
    --out-dir "${RUNTIME_EVIDENCE_DIR}/seed" \
    --mode "$MODE")

echo "$SEED_JSON" | python3 -c "import sys, json; json.load(sys.stdin)" || fail "create-autoinstall-seed.sh produced invalid JSON output!"
SEED_ISO=$(echo "$SEED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['seed_iso_path'])")
SEED_SHA256=$(echo "$SEED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['seed_iso_sha256'])")

# Copy seed user-data/meta-data to runtime evidence dir for forensics
cp -f "${RUNTIME_EVIDENCE_DIR}/seed/user-data" "${RUNTIME_EVIDENCE_DIR}/seed-user-data.yaml" 2>/dev/null || true
cp -f "${RUNTIME_EVIDENCE_DIR}/seed/meta-data" "${RUNTIME_EVIDENCE_DIR}/seed-meta-data.yaml" 2>/dev/null || true

# Step 6 + 8: Extract installer kernel and initrd from the canonical ISO
info "Extracting /casper/vmlinuz and /casper/initrd from verified Candidate 2 ISO..."
KERNEL_EXTRACTION_OUT=$(bash "$(dirname "$0")/extract-installer-kernel.sh" \
    --iso "$ISO_PATH" \
    --out-dir "${RUNTIME_EVIDENCE_DIR}/kernel" \
    --out-json "$kernel_extraction_json")

INSTALLER_VMLINUZ=$(echo "$KERNEL_EXTRACTION_OUT" | grep '"vmlinuz_path"' | python3 -c "import sys,json; d=json.load(open('$kernel_extraction_json')); print(d['vmlinuz_path'])" 2>/dev/null || \
    python3 -c "import json; d=json.load(open('$kernel_extraction_json')); print(d['vmlinuz_path'])")
INSTALLER_INITRD=$(python3 -c "import json; d=json.load(open('$kernel_extraction_json')); print(d['initrd_path'])")
KERNEL_SHA256=$(python3 -c "import json; d=json.load(open('$kernel_extraction_json')); print(d['vmlinuz_sha256'])")
INITRD_SHA256=$(python3 -c "import json; d=json.load(open('$kernel_extraction_json')); print(d['initrd_sha256'])")

info "Kernel SHA-256: $KERNEL_SHA256"
info "Initrd SHA-256: $INITRD_SHA256"

# Kernel append: autoinstall + NoCloud seed from virtio drive (/dev/vdb = cidata ISO)
KERNEL_APPEND="boot=casper autoinstall ds=nocloud console=ttyS0,115200n8 ---"

info "Booting Candidate 2 ISO in $MODE mode with direct-kernel autoinstall (VM: $VM_ID, Port: $SSH_PORT)..."

# 7. Start QEMU with direct-kernel boot (canonical ISO still attached read-only as CDROM)
bash "$(dirname "$0")/run-qemu.sh" start \
    --vm-id "$VM_ID" \
    --mode "$MODE" \
    --iso "$ISO_PATH" \
    --seed-iso "$SEED_ISO" \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp-socket "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$SSH_PORT" \
    --kernel "$INSTALLER_VMLINUZ" \
    --initrd "$INSTALLER_INITRD" \
    --append "$KERNEL_APPEND" \
    --no-reboot \
    --headless \
    --timeout "$TIMEOUT_SEC"

INSTALLER_VM_PID=$(cat "$pid_file" 2>/dev/null || echo "")
INSTALLER_VM_STARTED=true
INSTALL_PHASE="installer_running"

# 8. Capture initial screenshot
if [[ -S "$qmp_path" ]]; then
    bash "$(dirname "$0")/capture-screenshot.sh" --socket "$qmp_path" --output "$screenshot_path" || true
fi

# 9. Wait for genuine installer completion — token is written by the installer inside the guest
bash "$(dirname "$0")/wait-for-install-completion.sh" \
    --vm-id "$VM_ID" \
    --token "$INSTALL_TOKEN" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --serial-log "$serial_log" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --disk "$DISK_PATH" \
    --mode "$MODE" \
    --natural-shutdown-grace 180 \
    --timeout "$TIMEOUT_SEC" \
    --out-json "$completion_json"

# Preserve evidence files in runtime dir
cp -f "$serial_log" "$RUNTIME_EVIDENCE_DIR/installer.serial.log" 2>/dev/null || true
cp -f "${state_dir}/qemu-${VM_ID}.stderr" "$RUNTIME_EVIDENCE_DIR/qemu.stderr.log" 2>/dev/null || true
cp -f "$screenshot_path" "$RUNTIME_EVIDENCE_DIR/installer.ppm" 2>/dev/null || true

# Copy to stage-logs for CI artifact upload
cp -f "$serial_log" "$stage_logs_dir/cand2-install-serial.log" 2>/dev/null || true

# 10. Stop installer VM cleanly (with --state-dir to capture lifecycle result)
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path" --state-dir "$state_dir"

# Copy final VM state and shutdown result to runtime evidence with unambiguous names
cp -f "${state_dir}/vm-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installer-vm-state.final.json" 2>/dev/null || true
cp -f "${state_dir}/shutdown-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installer-shutdown-result.json" 2>/dev/null || true

# 11. Inspect target virtual disk structure offline via guestfish (inspection only, no writes)
bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$INSTALL_TOKEN" --mode "$MODE" --out-json "$disk_inspect_json"

# 12. Boot installed disk WITHOUT ISO attached and verify via authenticated SSH
# Serial output is supplementary only. Authentication is mandatory.
info "Booting installed Candidate 2 guest without ISO attached ($MODE mode) for authenticated verification..."
installed_serial_log="${state_dir}/cand2-installed-boot.serial.log"
installed_guest_cmd_log="${state_dir}/cand2-installed-guest-commands.log"
INSTALLED_VM_ID="${VM_ID}_inst"
INSTALLED_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")

installed_pid_file="${state_dir}/qemu-${INSTALLED_VM_ID}.pid"
installed_qmp_path="${state_dir}/qmp-${INSTALLED_VM_ID}.sock"

bash "$(dirname "$0")/run-qemu.sh" start \
    --vm-id "$INSTALLED_VM_ID" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$installed_serial_log" \
    --qmp-socket "$installed_qmp_path" \
    --pid-file "$installed_pid_file" \
    --ssh-port "$INSTALLED_PORT" \
    --headless \
    --timeout "$TIMEOUT_SEC"

INSTALLED_VM_PID=$(cat "$installed_pid_file" 2>/dev/null || echo "")
INSTALLED_VM_STARTED=true
INSTALL_PHASE="installed_boot_verification"

# Wait for installed guest SSH to become reachable — authentication is mandatory
INSTALLED_READINESS_TOKEN="CAND2_INSTALLED_BOOT_${RUN_ID}_$(date +%s)"
bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --token "$INSTALLED_READINESS_TOKEN" \
    --pid-file "$installed_pid_file" \
    --timeout "$TIMEOUT_SEC" || fail "Installed Candidate 2 guest ($MODE) did not become SSH-reachable. Cannot verify installed-boot."

# Execute verification commands inside the authenticated installed guest
# systemctl is-system-running may return 'degraded' legitimately; capture state but do not suppress
# apt-get check, dpkg --audit, dpkg-query, and findmnt must not be hidden with || true
GUEST_HEALTH_CMD='
set -e
cat /etc/os-release
findmnt -n -o SOURCE,FSTYPE /
lsblk -f
cat /proc/cmdline
SYSRUN=$(systemctl is-system-running 2>&1 || true); echo "systemctl_state=$SYSRUN"
dpkg-query -W
apt-cache policy
apt-get check
dpkg --audit
'
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "$GUEST_HEALTH_CMD" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$INSTALLED_VM_ID" \
    --pid-file "$installed_pid_file" \
    --out-log "$installed_guest_cmd_log" \
    --result-json "$state_dir/installed-guest-health.json" \
    --verify-disk-boot \
    --timeout "$TIMEOUT_SEC" || fail "Guest command execution failed for installed Candidate 2 ($MODE). Installed-boot cannot be verified."


cp -f "$installed_serial_log" "$stage_logs_dir/cand2-installed-boot.serial.log"
cp -f "$installed_guest_cmd_log" "$stage_logs_dir/cand2-installed-guest-commands.log"

# 13. Stop installed guest VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$INSTALLED_VM_ID" --pid-file "$installed_pid_file" --qmp-socket "$installed_qmp_path" --state-dir "$state_dir"

# Copy installed VM lifecycle evidence with unambiguous names
cp -f "${state_dir}/vm-${INSTALLED_VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installed-vm-state.final.json" 2>/dev/null || true
cp -f "${state_dir}/shutdown-${INSTALLED_VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/installed-shutdown-result.json" 2>/dev/null || true
cp -f "${state_dir}/installed-guest-health.json" "$RUNTIME_EVIDENCE_DIR/installed-guest-health.json" 2>/dev/null || true
cp -f "$installed_serial_log" "$RUNTIME_EVIDENCE_DIR/installed-boot.serial.log" 2>/dev/null || true
cp -f "$installed_guest_cmd_log" "$RUNTIME_EVIDENCE_DIR/installed-guest-commands.log" 2>/dev/null || true

INSTALLED_BOOT_RESULT="SSH_AUTHENTICATED_PASS"
printf '[PASS] Installed Candidate 2 guest authenticated and guest commands executed for VM %s (%s mode).\n' "$INSTALLED_VM_ID" "$MODE"

# 14. ONLY AFTER all verification steps succeed, create cand2-install-state.json
INSTALL_STATE_FILE="${state_dir}/cand2-install-state.json"
TOKEN_HASH=$(printf '%s' "$INSTALL_TOKEN" | sha256sum | awk '{print $1}')
CURR_SHA="$C2_SOURCE_COMMIT"

DISK_INSPECT_JSON="$disk_inspect_json" \
COMPLETION_JSON="$completion_json" \
CURR_SHA="$CURR_SHA" \
WORKFLOW_RUN_ID="$WORKFLOW_RUN_ID" \
EXECUTION_ID="$EXECUTION_ID" \
ISO_PATH="$ISO_PATH" \
CAND2_VERIFIED_SHA="$CAND2_VERIFIED_SHA" \
CAND2_VERIFIED_SHA512="$CAND2_VERIFIED_SHA512" \
KERNEL_SHA256="$KERNEL_SHA256" \
INITRD_SHA256="$INITRD_SHA256" \
SEED_SHA256="$SEED_SHA256" \
KERNEL_APPEND="$KERNEL_APPEND" \
VM_ID="$VM_ID" \
MODE="$MODE" \
DISK_PATH="$DISK_PATH" \
INSTALLED_GUEST_CMD_LOG="$installed_guest_cmd_log" \
SSH_KEY="$SSH_KEY" \
SSH_PUB="$SSH_PUB" \
SSH_FP="$SSH_FP" \
RUNTIME_EVIDENCE_DIR="$RUNTIME_EVIDENCE_DIR" \
INSTALL_STATE_FILE="$INSTALL_STATE_FILE" \
python3 - <<'PYEOF'
import json, os, sys, datetime

with open(os.environ["DISK_INSPECT_JSON"], "r") as f:
    disk_report = json.load(f)
with open(os.environ["COMPLETION_JSON"], "r") as f:
    comp_report = json.load(f)

overall_status = "PASS" if (disk_report.get("status") == "PASS" and comp_report.get("final_status") == "PASS") else "FAIL"
if overall_status != "PASS":
    sys.stderr.write(f"Candidate 2 verification failed! disk_report={disk_report.get('status')}, comp_report={comp_report.get('final_status')}\n")
    sys.exit(1)

state = {
    "schema_version": "1.0",
    "source_commit": os.environ["CURR_SHA"],
    "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
    "execution_id": os.environ["EXECUTION_ID"],
    "candidate2_iso_path": os.environ["ISO_PATH"],
    "source_iso_sha256": os.environ["CAND2_VERIFIED_SHA"],
    "source_iso_sha512": os.environ["CAND2_VERIFIED_SHA512"],
    "kernel_sha256": os.environ["KERNEL_SHA256"],
    "initrd_sha256": os.environ["INITRD_SHA256"],
    "seed_iso_sha256": os.environ["SEED_SHA256"],
    "kernel_command_line": os.environ["KERNEL_APPEND"],
    "vm_id": os.environ["VM_ID"],
    "firmware_mode": os.environ["MODE"],
    "installed_disk_path": os.environ["DISK_PATH"],
    "target_disk": os.environ["DISK_PATH"],
    "disk_inspection_result": os.environ["DISK_INSPECT_JSON"],
    "install_completion_result": os.environ["COMPLETION_JSON"],
    "installed_guest_commands_log": os.environ["INSTALLED_GUEST_CMD_LOG"],
    "ssh_username": "genixbit",
    "ssh_private_key_path": os.environ["SSH_KEY"],
    "ssh_public_key_path": os.environ["SSH_PUB"],
    "ssh_public_key_fingerprint": os.environ["SSH_FP"],
    "installation_timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "installed_boot_result": "SSH_AUTHENTICATED_PASS",
    "runtime_evidence_dir": os.environ["RUNTIME_EVIDENCE_DIR"],
    "installed_vm_id": os.environ["VM_ID"] + "_inst",
    "status": "PASS",
}
with open(os.environ["INSTALL_STATE_FILE"], "w") as f:
    json.dump(state, f, indent=2)
PYEOF
chmod 0600 "$INSTALL_STATE_FILE"
cp -f "$INSTALL_STATE_FILE" "$RUNTIME_EVIDENCE_DIR/cand2-install-state.json" 2>/dev/null || true

printf 'GENIXBIT_CANDIDATE2_INSTALL_STATE=%s\n' "$INSTALL_STATE_FILE"
printf '[PASS] Candidate 2 guest installation and installed-boot verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
