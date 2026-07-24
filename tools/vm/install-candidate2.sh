#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs Candidate 2 ISO into target QCOW2 virtual disk image using managed background VM lifecycle,
# autoinstall seed media, guest-produced completion token, and authenticated guest verification.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=600

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
CAND2_EXPECTED_SHA="d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228"
actual_sha=$(sha256sum "$ISO_PATH" | awk '{print $1}')
if [[ "$actual_sha" != "$CAND2_EXPECTED_SHA" ]]; then
    fail "Candidate 2 ISO SHA-256 mismatch! Expected ${CAND2_EXPECTED_SHA}, got ${actual_sha}"
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

# 3. Create target QCOW2 disk
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

# 4. Generate ephemeral SSH keypair
KEY_JSON=$(bash "$(dirname "$0")/create-ephemeral-key.sh" --vm-id "$VM_ID" --state-dir "$state_dir")
SSH_KEY=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['private_key_path'])")
SSH_PUB=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['public_key_path'])")

# 5. Allocate unique loopback SSH port (NO 2222 fallback!)
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

# 9. Wait for genuine installer completion (NO host token echo!)
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
    --timeout "$TIMEOUT_SEC"

cp -f "$serial_log" "$stage_logs_dir/cand2-install-serial.log"

# 10. Stop installer VM
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

# 11. Inspect target virtual disk structure (partitions, filesystems, OS files)
bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$INSTALL_TOKEN" --mode "$MODE"

# 12. Save private Candidate 2 installation state JSON for migration stage key reuse
INSTALL_STATE_FILE="${state_dir}/cand2-install-state.json"
TOKEN_HASH=$(printf '%s' "$INSTALL_TOKEN" | sha256sum | awk '{print $1}')

python3 -c "
import json
state = {
    'vm_id': '$VM_ID',
    'firmware_mode': '$MODE',
    'installed_disk_path': '$DISK_PATH',
    'ssh_user': 'genixbit',
    'ssh_private_key_path': '$SSH_KEY',
    'ssh_public_key_path': '$SSH_PUB',
    'ssh_port': $SSH_PORT,
    'completion_token_hash': '$TOKEN_HASH',
    'installation_timestamp': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'
}
with open('$INSTALL_STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"

# 13. Boot Candidate 2 installed disk WITHOUT ISO attached as managed background process
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

# 14. Wait for installed guest SSH readiness with provisioned key
bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --token "${RUN_ID}" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --timeout 120

# 15. Execute guest identity & health commands inside Candidate 2 installed guest
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

# 16. Stop installed guest VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$INSTALLED_VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

printf '[PASS] Candidate 2 guest installation and installed-boot verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
