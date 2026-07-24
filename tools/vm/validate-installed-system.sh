#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validates installed guest system identity, APT repository status, and package health.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
MODE="uefi"

fail() {
    printf '[FAIL] validate-installed-system.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
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
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail 'Valid --disk path is required.'

state_dir="$(dirname "$DISK_PATH")/val-${MODE}-state"
serial_log="${state_dir}/validation-serial.log"
qmp_path="${state_dir}/qmp.sock"
pid_file="${state_dir}/qemu.pid"

mkdir -p "$state_dir"

printf '[INFO] Validating installed system health on %s (%s mode)...\n' "$DISK_PATH" "$MODE"
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --headless \
    --timeout 300

printf '[PASS] Installed system package health & identity verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
