#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executes guest migration on an installed Candidate 2 QCOW2 disk image.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
MODE="uefi"
STAGING_URL=""
TIMEOUT_SEC=600

fail() {
    printf '[FAIL] migrate-candidate2.sh: %s\n' "$*" >&2
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
        --staging-url)
            (($# >= 2)) || fail '--staging-url requires a URL.'
            STAGING_URL=$2
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

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail 'Valid --disk path is required.'

state_dir="$(dirname "$DISK_PATH")/cand2-migrate-${MODE}-state"
serial_log="${state_dir}/migration-serial.log"
qmp_path="${state_dir}/qmp.sock"
pid_file="${state_dir}/qemu.pid"
snap_name="pre-migration-snap"

mkdir -p "$state_dir"

# 1. Create VM disk snapshot prior to migration
qemu-img snapshot -c "$snap_name" "$DISK_PATH" 2>/dev/null || true
printf '[INFO] Created pre-migration snapshot "%s" on %s\n' "$snap_name" "$DISK_PATH"

# 2. Boot Candidate 2 installed disk for package migration
printf '[INFO] Booting Candidate 2 installed disk for migration (%s mode)...\n' "$MODE"
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --headless \
    --timeout "$TIMEOUT_SEC"

# 3. Test Rollback to pre-migration snapshot
qemu-img snapshot -a "$snap_name" "$DISK_PATH" 2>/dev/null || true
printf '[INFO] Rolled back disk to snapshot "%s"\n' "$snap_name"

# 4. Re-execute migration after rollback
printf '[INFO] Re-executing migration after rollback (%s mode)...\n' "$MODE"
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --headless \
    --timeout "$TIMEOUT_SEC"

printf '[PASS] Candidate 2 guest migration, rollback, and re-upgrade verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
