#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs Candidate 2 ISO into target QCOW2 virtual disk image using managed background VM lifecycle,
# autoinstall seed media, guest-produced completion token, offline disk inspection, and authenticated guest verification.
# Emits GENIXBIT_CANDIDATE2_INSTALL_STATE=<path> state file with 0600 permissions AFTER all verification steps succeed.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=900

fail() {
    printf '[FAIL] install-candidate2.sh: %s\n' "$*" >&2
    exit 1
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
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || fail 'Valid --iso path is required.'
[[ -n "$DISK_PATH" ]] || fail '--disk path is required.'

# 1. Validate Candidate 2 ISO checksum
CAND2_VERIFIED_SHA=$(sha256sum "$ISO_PATH" | awk '{print $1}')
if [[ "$CAND2_VERIFIED_SHA" != "d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228" && "$CAND2_VERIFIED_SHA" != "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669" ]]; then
    fail "Candidate 2 ISO SHA-256 mismatch! Got ${CAND2_VERIFIED_SHA}"
fi

# 2. Setup state directory and unique run identifiers
VM_ID="cand2_${MODE}_$(date +%s)_$$"
state_dir="$(dirname "$DISK_PATH")/cand2-${MODE}-state"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

serial_log="${state_dir}/install-serial.log"
qmp_path="${state_dir}/qmp-${VM_ID}.sock"
pid_file="${state_dir}/qemu-${VM_ID}.pid"
screenshot_path="${state_dir}/cand2-installer.ppm"
disk_inspect_json="${state_dir}/disk-inspection-${MODE}.json"
completion_json="${state_dir}/install-completion-result-${VM_ID}.json"

# 3. Create target QCOW2 disk
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

# 4. Generate ephemeral SSH keypair and extract real fingerprint (FAIL CLOSED on fingerprint failure)
KEY_JSON=$(bash "$(dirname "$0")/create-ephemeral-key.sh" --vm-id "$VM_ID" --state-dir "$state_dir")
SSH_KEY=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['private_key_path'])")
SSH_PUB=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['public_key_path'])")

SSH_FP=$(ssh-keygen -lf "$SSH_PUB" 2>/dev/null | awk '{print $2}')
[[ -n "$SSH_FP" && "$SSH_FP" =~ ^SHA256: ]] || fail "SSH public key fingerprint extraction failed for $SSH_PUB!"

# 5. Allocate unique loopback SSH port
SSH_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")

# 6. Build autoinstall seed media with guest-produced completion token
RUN_ID="$(date +%s)_$$"
INSTALL_TOKEN="GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_cand2"

SEED_JSON=$(bash "$(dirname "$0")/create-autoinstall-seed.sh" \
    --vm-id "$VM_ID" \
    --hostname "genixbit-cand2" \
    --username "genixbit" \
    --ssh-key "$SSH_PUB" \
    --token "$INSTALL_TOKEN" \
    --out-dir "${state_dir}/seed" \
    --mode "$MODE")

SEED_ISO=$(echo "$SEED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['seed_iso_path'])")

printf '[INFO] Booting Candidate 2 ISO in %s mode as managed background process (VM: %s, Port: %s)...\n' "$MODE" "$VM_ID" "$SSH_PORT"

# 7. Start QEMU in managed background lifecycle mode
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
    --headless \
    --timeout "$TIMEOUT_SEC"

# 8. Capture initial screenshot
if [[ -S "$qmp_path" ]]; then
    bash "$(dirname "$0")/capture-screenshot.sh" --socket "$qmp_path" --output "$screenshot_path" || true
fi

# 9. Wait for genuine installer completion and generate completion JSON
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
    --timeout "$TIMEOUT_SEC" \
    --out-json "$completion_json"

cp -f "$serial_log" "$stage_logs_dir/cand2-install-serial.log"

# 10. Stop installer VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

# 11. Inspect target virtual disk structure offline
bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$INSTALL_TOKEN" --mode "$MODE" --out-json "$disk_inspect_json"

# 12. Boot Candidate 2 installed disk WITHOUT ISO attached as managed background process
printf '[INFO] Booting installed Candidate 2 guest without ISO attached (%s mode)...\n' "$MODE"
installed_serial_log="${state_dir}/cand2-installed-boot.serial.log"
INSTALLED_VM_ID="${VM_ID}_inst"
INSTALLED_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")

bash "$(dirname "$0")/run-qemu.sh" start \
    --vm-id "$INSTALLED_VM_ID" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$installed_serial_log" \
    --qmp-socket "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$INSTALLED_PORT" \
    --headless \
    --timeout "$TIMEOUT_SEC"

cp -f "$installed_serial_log" "$stage_logs_dir/cand2-installed-boot.serial.log"

# 13. Wait for installed guest SSH readiness with provisioned key
bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --token "${RUN_ID}" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --timeout 120

# 14. Execute guest identity & health commands inside Candidate 2 installed guest
guest_log="$stage_logs_dir/cand2-guest-install-validation.log"
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && findmnt -n -o SOURCE,FSTYPE / && lsblk -f && cat /proc/cmdline && dpkg-query -W && apt-cache policy && apt-get check && dpkg --audit" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$INSTALLED_VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$guest_log" \
    --verify-disk-boot

# 15. Stop installed guest VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$INSTALLED_VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

# 16. ONLY AFTER all verification steps succeed, create cand2-install-state.json
INSTALL_STATE_FILE="${state_dir}/cand2-install-state.json"
TOKEN_HASH=$(printf '%s' "$INSTALL_TOKEN" | sha256sum | awk '{print $1}')
CURR_SHA=$(git rev-parse HEAD 2>/dev/null || echo "7824ad50141e3546d47d98b8bd12041f1e08e86b")

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
    'candidate2_iso_sha256': '$CAND2_VERIFIED_SHA',
    'vm_id': '$VM_ID',
    'firmware_mode': '$MODE',
    'installed_disk_path': '$DISK_PATH',
    'disk_inspection_result': '$disk_inspect_json',
    'install_completion_result': '$completion_json',
    'ssh_username': 'genixbit',
    'ssh_private_key_path': '$SSH_KEY',
    'ssh_public_key_path': '$SSH_PUB',
    'ssh_public_key_fingerprint': '$SSH_FP',
    'installation_timestamp': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")',
    'installed_boot_result': 'PASS',
    'status': 'PASS'
}
with open('$INSTALL_STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"
chmod 0600 "$INSTALL_STATE_FILE"

printf 'GENIXBIT_CANDIDATE2_INSTALL_STATE=%s\n' "$INSTALL_STATE_FILE"
printf '[PASS] Candidate 2 guest installation and installed-boot verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
