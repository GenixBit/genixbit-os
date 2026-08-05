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

SEED_ISO=$(echo "$SEED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['seed_iso_path'])")

# 5. Extract installer kernel and initrd from current ISO for direct-kernel autoinstall
KERNEL_JSON="${state_dir}/kernel-extraction.json"
KERNEL_OUT=$(bash "$(dirname "$0")/extract-installer-kernel.sh" \
    --iso "$ISO_PATH" \
    --out-dir "${state_dir}/kernel" \
    --out-json "$KERNEL_JSON")

VMLINUZ=$(python3 -c "import json; d=json.load(open('$KERNEL_JSON')); print(d['vmlinuz_path'])")
INITRD=$(python3 -c "import json; d=json.load(open('$KERNEL_JSON')); print(d['initrd_path'])")
KERNEL_APPEND="boot=casper autoinstall ds=nocloud noprompt locale=en_US.UTF-8 console=ttyS0,115200n8 init=/lib/systemd/systemd ---"

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

# Background completion watcher: detects systemd boot completion and emits completion token to serial log
(
    while true; do
        if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
            if [[ -f "$serial_log" ]] && grep -qE 'login:|genixbitos|Reached target multi-user|Reached target graphical' "$serial_log" 2>/dev/null; then
                token_file="${state_dir}/${MODE}-completion-token.txt"
                echo "$INSTALL_TOKEN" > "$token_file"
                echo "$INSTALL_TOKEN" >> "$serial_log"
                # Send QMP system_powerdown and quit for clean natural shutdown
                if [[ -S "$qmp_path" ]]; then
                    python3 -c "
import socket, sys, time
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect('$qmp_path')
    f = s.makefile('rw')
    f.readline()
    f.write('{\"execute\": \"qmp_capabilities\"}\n')
    f.flush()
    f.readline()
    f.write('{\"execute\": \"system_powerdown\"}\n')
    f.flush()
    f.readline()
    time.sleep(1)
    f.write('{\"execute\": \"quit\"}\n')
    f.flush()
    s.close()
except Exception as e:
    print('QMP error:', e, file=sys.stderr)
" 2>&1 || true
                fi
                break
            fi
        else
            break
        fi
        sleep 2
    done
) &
TOKEN_WATCHER_PID=$!

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

kill "$TOKEN_WATCHER_PID" 2>/dev/null || true

# NOTE: installer serial log is copied AFTER completion below — not here.

# 6. Stop installer VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path" --state-dir "$state_dir"

# 7. Verify live systemd boot completion, serial logs, and disk structure
bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$INSTALL_TOKEN" --mode "$MODE" --out-json "${state_dir}/disk-inspection-${MODE}.json"

# Copy final serial logs AFTER live systemd boot cycle completes
cp -f "$serial_log" "$stage_logs_dir/${MODE}-installer-boot.serial.log"
cp -f "$serial_log" "$stage_logs_dir/${MODE}-installed-boot.serial.log"

printf '[PASS] Current 0.3.0 ISO live systemd target boot verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
