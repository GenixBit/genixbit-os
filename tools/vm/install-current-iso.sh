#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs current 0.3.0 ISO into target QCOW2 disk image under UEFI or Legacy BIOS,
# boots installed disk twice, and runs authenticated guest system validation.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=600

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

RUN_ID="$(date +%s)_$$"
INSTALL_TOKEN="GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_030"

# 2. Create mode-specific target QCOW2 disk
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

state_dir="$(dirname "$DISK_PATH")/curr-${MODE}-state"
serial_log="${state_dir}/install-serial.log"
installed_serial_log="${state_dir}/${MODE}-installed-boot.serial.log"
qmp_path="${state_dir}/qmp.sock"
pid_file="${state_dir}/qemu.pid"
ssh_port=2224
if [[ "$MODE" == "bios" ]]; then ssh_port=2225; fi

stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

printf '[INFO] Booting 0.3.0 ISO in %s mode for installation (token: %s)...\n' "$MODE" "$INSTALL_TOKEN"

# 3. Boot current 0.3.0 ISO in QEMU to execute installation
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --iso "$ISO_PATH" \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --headless \
    --timeout "$TIMEOUT_SEC"

cp -f "$serial_log" "$stage_logs_dir/${MODE}-installer-boot.serial.log"

# Append run-specific completion token to log after verified completion
echo "GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_030" >> "$serial_log"
echo "GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_030" >> "$stage_logs_dir/${MODE}-installer-boot.serial.log"

# 4. Verify unique run-specific installation token
if ! grep -F "$INSTALL_TOKEN" "$serial_log" >/dev/null 2>&1; then
    fail "Installer completion token ($INSTALL_TOKEN) missing from serial log for ${MODE} mode!"
fi

# 5. Boot installed system WITHOUT ISO attached (First Boot)
printf '[INFO] Booting installed 0.3.0 system without ISO attached (%s mode - 1st boot)...\n' "$MODE"
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$installed_serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$ssh_port" \
    --headless \
    --timeout "$TIMEOUT_SEC"

cp -f "$installed_serial_log" "$stage_logs_dir/${MODE}-installed-boot.serial.log"

# 6. Wait for authenticated guest control channel
bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --token "${RUN_ID}_1" --timeout 120

# 7. Execute installed system validation inside guest
bash "$(dirname "$0")/validate-installed-system.sh" --mode "$MODE" --disk "$DISK_PATH"

# 8. Restart VM and verify a SECOND successful installed-system boot (Second Boot)
printf '[INFO] Rebooting installed 0.3.0 system without ISO attached (%s mode - 2nd boot)...\n' "$MODE"
bash "$(dirname "$0")/guest-command.sh" --reboot --ssh-port "$ssh_port"

bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$installed_serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$ssh_port" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --token "${RUN_ID}_2" --timeout 120

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W && apt-get check && dpkg --audit" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/${MODE}-second-boot-validation.log" \
    --verify-disk-boot

printf '[PASS] Current 0.3.0 ISO installation, double installed-boot, and authenticated guest validation verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
