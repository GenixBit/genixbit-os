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
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || fail 'Valid --iso path is required.'
[[ -n "$DISK_PATH" ]] || fail '--disk path is required.'

# 1. Validate Candidate 2 ISO checksum
CAND2_VERIFIED_SHA=$(sha256sum "$ISO_PATH" | awk '{print $1}')
if [[ "$CAND2_VERIFIED_SHA" != "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669" ]]; then
    fail "Candidate 2 ISO SHA-256 mismatch! Got ${CAND2_VERIFIED_SHA} — expected 1cb79fbf..."
fi
CAND2_VERIFIED_SHA512=$(sha512sum "$ISO_PATH" | awk '{print $1}')
info "Candidate 2 ISO SHA-256 verified: $CAND2_VERIFIED_SHA"
info "Candidate 2 ISO SHA-512 verified: ${CAND2_VERIFIED_SHA512:0:16}..."

# 2. Setup state directory and unique run identifiers
VM_ID="cand2_${MODE}_$(date +%s)_$$"
state_dir="$(dirname "$DISK_PATH")/cand2-${MODE}-state"
REPO_TOP=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
stage_logs_dir="$REPO_TOP/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

# Persistent runtime evidence dir (survives TMP cleanup)
if [[ -z "$RUNTIME_EVIDENCE_DIR" ]]; then
    RUNTIME_EVIDENCE_DIR="$REPO_TOP/infra/package-staging/results/runtime/local-$(date +%s)-$$"
fi
mkdir -p "$RUNTIME_EVIDENCE_DIR"
info "Runtime evidence directory: $RUNTIME_EVIDENCE_DIR"

serial_log="${RUNTIME_EVIDENCE_DIR}/installer.serial.log"
qmp_path="${state_dir}/qmp-${VM_ID}.sock"
pid_file="${state_dir}/qemu-${VM_ID}.pid"
screenshot_path="${RUNTIME_EVIDENCE_DIR}/installer.ppm"
disk_inspect_json="${RUNTIME_EVIDENCE_DIR}/disk-inspection-${MODE}.json"
completion_json="${RUNTIME_EVIDENCE_DIR}/install-completion.json"
kernel_extraction_json="${RUNTIME_EVIDENCE_DIR}/kernel-extraction.json"
failure_summary_json="${RUNTIME_EVIDENCE_DIR}/failure-summary.json"

# 3. Create GENUINELY BLANK target QCOW2 disk.
# The target disk must be blank. The installer running inside QEMU is the ONLY entity
# permitted to partition, format, and populate this disk.
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

# 4. Generate ephemeral SSH keypair and extract real fingerprint (FAIL CLOSED on fingerprint failure)
KEY_JSON=$(bash "$(dirname "$0")/create-ephemeral-key.sh" --vm-id "$VM_ID" --state-dir "$state_dir")
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
cp -f "${state_dir}/vm-${VM_ID}.json" "$RUNTIME_EVIDENCE_DIR/vm-state.json" 2>/dev/null || true

# Copy to stage-logs for CI artifact upload
cp -f "$serial_log" "$stage_logs_dir/cand2-install-serial.log" 2>/dev/null || true

# 10. Stop installer VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

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
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$INSTALLED_VM_ID" --pid-file "$installed_pid_file" --qmp-socket "$installed_qmp_path"

INSTALLED_BOOT_RESULT="SSH_AUTHENTICATED_PASS"
printf '[PASS] Installed Candidate 2 guest authenticated and guest commands executed for VM %s (%s mode).\n' "$INSTALLED_VM_ID" "$MODE"

# 14. ONLY AFTER all verification steps succeed, create cand2-install-state.json
INSTALL_STATE_FILE="${state_dir}/cand2-install-state.json"
TOKEN_HASH=$(printf '%s' "$INSTALL_TOKEN" | sha256sum | awk '{print $1}')
CURR_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

python3 -c "
import json, sys

with open('$disk_inspect_json', 'r') as f: disk_report = json.load(f)
with open('$completion_json', 'r') as f: comp_report = json.load(f)

overall_status = 'PASS' if (disk_report.get('status') == 'PASS' and comp_report.get('final_status') == 'PASS') else 'FAIL'
if overall_status != 'PASS':
    sys.stderr.write('Candidate 2 verification failed! disk_report=' + str(disk_report.get('status')) + ', comp_report=' + str(comp_report.get('final_status')) + '\n')
    sys.exit(1)

state = {
    'schema_version': '1.0',
    'source_commit': '$CURR_SHA',
    'workflow_run_id': '$RUN_ID',
    'candidate2_iso_path': '$ISO_PATH',
    'source_iso_sha256': '$CAND2_VERIFIED_SHA',
    'source_iso_sha512': '$CAND2_VERIFIED_SHA512',
    'kernel_sha256': '$KERNEL_SHA256',
    'initrd_sha256': '$INITRD_SHA256',
    'seed_iso_sha256': '$SEED_SHA256',
    'kernel_command_line': '$KERNEL_APPEND',
    'vm_id': '$VM_ID',
    'firmware_mode': '$MODE',
    'installed_disk_path': '$DISK_PATH',
    'target_disk': '$DISK_PATH',
    'disk_inspection_result': '$disk_inspect_json',
    'install_completion_result': '$completion_json',
    'installed_guest_commands_log': '$installed_guest_cmd_log',
    'ssh_username': 'genixbit',
    'ssh_private_key_path': '$SSH_KEY',
    'ssh_public_key_path': '$SSH_PUB',
    'ssh_public_key_fingerprint': '$SSH_FP',
    'installation_timestamp': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")',
    'installed_boot_result': 'SSH_AUTHENTICATED_PASS',
    'runtime_evidence_dir': '$RUNTIME_EVIDENCE_DIR',
    'status': 'PASS'
}
with open('$INSTALL_STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"
chmod 0600 "$INSTALL_STATE_FILE"
cp -f "$INSTALL_STATE_FILE" "$RUNTIME_EVIDENCE_DIR/cand2-install-state.json" 2>/dev/null || true

printf 'GENIXBIT_CANDIDATE2_INSTALL_STATE=%s\n' "$INSTALL_STATE_FILE"
printf '[PASS] Candidate 2 guest installation and installed-boot verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
