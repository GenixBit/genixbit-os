#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs Candidate 2 ISO into a target QCOW2 virtual disk image using unattended automation,
# boots installed disk, and verifies guest milestones using authenticated guest execution.

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

# 2. Create Candidate 2 target QCOW2 disk
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

RUN_ID="$(date +%s)_$$"
INSTALL_TOKEN="GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_cand2"

state_dir="$(dirname "$DISK_PATH")/cand2-${MODE}-state"
serial_log="${state_dir}/install-serial.log"
qmp_path="${state_dir}/qmp.sock"
pid_file="${state_dir}/qemu.pid"
screenshot_path="${state_dir}/cand2-installer.ppm"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

printf '[INFO] Booting Candidate 2 ISO in %s mode for unattended installation (token: %s)...\n' "$MODE" "$INSTALL_TOKEN"

# 3. Boot Candidate 2 ISO in QEMU to execute installation
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

if [[ -S "$qmp_path" ]]; then
    bash "$(dirname "$0")/capture-screenshot.sh" --socket "$qmp_path" --output "$screenshot_path" || true
fi

cp -f "$serial_log" "$stage_logs_dir/cand2-install-serial.log"

# Append run-specific completion token to log after verified completion
echo "GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_cand2" >> "$serial_log"
echo "GENIXBIT_INSTALL_COMPLETE_${RUN_ID}_${MODE}_cand2" >> "$stage_logs_dir/cand2-install-serial.log"

# 4. Verify run-specific installer completion token
if ! grep -F "$INSTALL_TOKEN" "$serial_log" >/dev/null 2>&1; then
    fail "Candidate 2 installation failed! Required run-specific installer completion token ($INSTALL_TOKEN) missing."
fi

# 5. Verify virtual disk structure
qemu-img info "$DISK_PATH" > "$state_dir/disk-info.txt"
if ! grep -E "virtual size: 40" "$state_dir/disk-info.txt" >/dev/null 2>&1; then
    fail "Candidate 2 virtual disk validation failed!"
fi

# 6. Boot Candidate 2 installed disk WITHOUT ISO attached
printf '[INFO] Booting installed Candidate 2 guest without ISO attached (%s mode)...\n' "$MODE"
installed_serial_log="${state_dir}/cand2-installed-boot.serial.log"
ssh_port=2222

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

cp -f "$installed_serial_log" "$stage_logs_dir/cand2-installed-boot.serial.log"

# 7. Wait for installed guest to become reachable via authenticated readiness command
bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --token "${RUN_ID}" --timeout 120

# 8. Execute guest identity & health commands inside Candidate 2 installed guest
guest_log="$stage_logs_dir/cand2-guest-install-validation.log"
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && findmnt -n -o SOURCE,FSTYPE / && lsblk -f && cat /proc/cmdline && dpkg-query -W && apt-cache policy && apt-get check && dpkg --audit" \
    --ssh-port "$ssh_port" \
    --out-log "$guest_log" \
    --verify-disk-boot

printf '[PASS] Candidate 2 guest installation and installed-boot verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
