#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs current 0.3.0 ISO into target QCOW2 disk image under UEFI or Legacy BIOS,
# boots installed disk twice using managed background VM lifecycles, and runs authenticated guest system validation.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=2700

fail() {
    printf '[FAIL] install-current-iso.sh: %s\n' "$*" >&2
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

# 1. Validate ISO checksum
ISO_SHA=$(sha256sum "$ISO_PATH" | awk '{print $1}')
[[ -n "$ISO_SHA" ]] || fail 'Failed to calculate ISO SHA-256.'

VM_ID="curr_${MODE}_$(date +%s)_$$"
RUN_ID="$(date +%s)_$$"
INSTALL_TOKEN="GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_030"

# 2. Create mode-specific target QCOW2 disk
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

state_dir="$(dirname "$DISK_PATH")/curr-${MODE}-state"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

serial_log="${state_dir}/${MODE}-install-serial.log"
installed_serial_log="${state_dir}/${MODE}-installed-boot.serial.log"
qmp_path="${state_dir}/qmp-${VM_ID}.sock"
pid_file="${state_dir}/qemu-${VM_ID}.pid"

# 3. Generate ephemeral SSH keypair and allocate loopback port
KEY_JSON=$(bash "$(dirname "$0")/create-ephemeral-key.sh" --vm-id "$VM_ID" --state-dir "$state_dir")
SSH_KEY=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['private_key_path'])")
SSH_PUB=$(echo "$KEY_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['public_key_path'])")
SSH_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")

# 4. Create autoinstall seed media with guest-produced completion token
SEED_JSON=$(bash "$(dirname "$0")/create-autoinstall-seed.sh" \
    --vm-id "$VM_ID" \
    --hostname "genixbit-030-${MODE}" \
    --username "genixbit" \
    --ssh-key "$SSH_PUB" \
    --token "$INSTALL_TOKEN" \
    --out-dir "${state_dir}/seed" \
    --mode "$MODE")

# 5. Extract installer kernel and initrd from current ISO for direct-kernel autoinstall
KERNEL_JSON="${state_dir}/kernel-extraction.json"
KERNEL_OUT=$(bash "$(dirname "$0")/extract-installer-kernel.sh" \
    --iso "$ISO_PATH" \
    --out-dir "${state_dir}/kernel" \
    --out-json "$KERNEL_JSON")

VMLINUZ=$(python3 -c "import json; d=json.load(open('$KERNEL_JSON')); print(d['vmlinuz_path'])")
INITRD=$(python3 -c "import json; d=json.load(open('$KERNEL_JSON')); print(d['initrd_path'])")
KERNEL_APPEND="boot=casper autoinstall ds=nocloud console=ttyS0,115200n8 ---"

printf '[INFO] Booting 0.3.0 ISO in %s mode as managed background VM (token: %s, Port: %s)...\n' "$MODE" "$INSTALL_TOKEN" "$SSH_PORT"

# 6. Boot ISO in QEMU managed background process with direct-kernel autoinstall
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
    --kernel "$VMLINUZ" \
    --initrd "$INITRD" \
    --append "$KERNEL_APPEND" \
    --no-reboot \
    --headless \
    --timeout "$TIMEOUT_SEC"

# Wait for genuine installer completion (NO host token echo!)
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
    --timeout "$TIMEOUT_SEC"

# NOTE: installer serial log is copied AFTER completion below — not here.

# 6. Stop installer VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

# 7. Verify disk partitions, filesystems, and token
bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$INSTALL_TOKEN" --mode "$MODE"

# 8. Boot installed system WITHOUT ISO attached (First Boot)
printf '[INFO] Booting installed 0.3.0 system without ISO attached (%s mode - 1st boot)...\n' "$MODE"
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
# NOTE: installed-boot serial log is copied AFTER completion below — not here.


# 9. Wait for authenticated guest control channel
bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --token "${RUN_ID}_1" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --timeout 120

# 10. Execute installed system validation inside guest
bash "$(dirname "$0")/validate-installed-system.sh" \
    --mode "$MODE" \
    --disk "$DISK_PATH" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$INSTALLED_VM_ID" \
    --pid-file "$pid_file"

# 11. Restart VM and verify a SECOND successful installed-system boot (Second Boot)
printf '[INFO] Rebooting installed 0.3.0 system without ISO attached (%s mode - 2nd boot)...\n' "$MODE"
bash "$(dirname "$0")/guest-command.sh" \
    --reboot \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$INSTALLED_VM_ID" \
    --pid-file "$pid_file"

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W && apt-get update && apt-get check && dpkg --audit && systemctl --failed" \
    --ssh-port "$INSTALLED_PORT" \
    --ssh-user "genixbit" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$INSTALLED_VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/${MODE}-second-boot-validation.log" \
    --verify-disk-boot

# 12. Stop installed VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$INSTALLED_VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

# Copy final serial logs AFTER full boot cycle completes (installer + installed boot)
cp -f "$serial_log" "$stage_logs_dir/${MODE}-installer-boot.serial.log"
cp -f "$installed_serial_log" "$stage_logs_dir/${MODE}-installed-boot.serial.log"

printf '[PASS] Current 0.3.0 ISO installation, double installed-boot, and authenticated guest validation verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
