#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs Candidate 2 ISO into a target QCOW2 virtual disk image.

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

# 1. Create target disk if missing
bash "$(dirname "$0")/create-test-disk.sh" --disk "$DISK_PATH" --size "40G"

# 2. Boot Candidate 2 ISO in QEMU to execute installation
state_dir="$(dirname "$DISK_PATH")/cand2-${MODE}-state"
serial_log="${state_dir}/install-serial.log"
qmp_path="${state_dir}/qmp.sock"
pid_file="${state_dir}/qemu.pid"

mkdir -p "$state_dir"

printf '[INFO] Booting Candidate 2 ISO in %s mode for guest installation...\n' "$MODE"
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

printf '[PASS] Candidate 2 guest installation completed for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
