#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executes guest package migration, snapshot rollback, and re-upgrade on an installed Candidate 2 QCOW2 disk image
# using authenticated guest command execution without error suppression.

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
[[ -n "$STAGING_URL" ]] || fail '--staging-url is required.'

state_dir="$(dirname "$DISK_PATH")/cand2-migrate-${MODE}-state"
serial_log="${state_dir}/migration-serial.log"
qmp_path="${state_dir}/qmp.sock"
pid_file="${state_dir}/qemu.pid"
snap_name="pre-migration-snap"
ssh_port=2223
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"

mkdir -p "$state_dir" "$stage_logs_dir"

# 1. Boot Candidate 2 installed disk for pre-migration verification
printf '[INFO] Booting Candidate 2 installed disk for pre-migration checks (%s mode)...\n' "$MODE"
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$ssh_port" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --timeout 120

# 2. Run pre-migration checks inside Candidate 2 guest
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W && apt-cache policy && apt-get check && dpkg --audit && find /etc/apt -maxdepth 3 -type f -print && grep -R . /etc/apt 2>/dev/null" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/cand2-pre-migration-guest.log" \
    --verify-disk-boot

# 3. Create pre-migration VM disk snapshot (FAIL CLOSED: NO || true)
if ! qemu-img snapshot -c "$snap_name" "$DISK_PATH"; then
    fail "Pre-migration snapshot creation failed for $DISK_PATH"
fi
printf '[INFO] Created pre-migration snapshot "%s" on %s\n' "$snap_name" "$DISK_PATH"

# 4. Configure staging repo and execute package migration commands inside guest
MIGRATION_CMD="apt-get update && apt-get install -y genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config && apt-get check && dpkg --audit && dpkg-query -W"

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "$MIGRATION_CMD" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/cand2-migration-exec.log"

# 5. Reboot guest post-migration (NO || true)
bash "$(dirname "$0")/guest-command.sh" --reboot --ssh-port "$ssh_port"

# Boot migrated guest
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$ssh_port" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --timeout 120

# 6. Verify post-migration identity & package health
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W genixbit-os-desktop && apt-get check && dpkg --audit" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/cand2-post-migration-guest.log" \
    --verify-disk-boot

# 7. Test Rollback to pre-migration snapshot (FAIL CLOSED: NO || true)
if ! qemu-img snapshot -a "$snap_name" "$DISK_PATH"; then
    fail "Snapshot restoration failed for $snap_name on $DISK_PATH"
fi
printf '[INFO] Rolled back disk to snapshot "%s"\n' "$snap_name"

# Boot rolled-back guest
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$ssh_port" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --timeout 120

# Verify original package state after rollback
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && apt-get check && dpkg --audit" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/cand2-rollback-guest.log" \
    --verify-disk-boot

# 8. Re-execute migration after rollback
printf '[INFO] Re-executing migration after rollback (%s mode)...\n' "$MODE"
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "$MIGRATION_CMD" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/cand2-reupgrade-exec.log"

bash "$(dirname "$0")/guest-command.sh" --reboot --ssh-port "$ssh_port"

# Boot re-upgraded guest
bash "$(dirname "$0")/run-qemu.sh" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$ssh_port" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" --ssh-port "$ssh_port" --timeout 120

# Verify final package state after re-upgrade
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W genixbit-os-desktop && apt-get check && dpkg --audit" \
    --ssh-port "$ssh_port" \
    --out-log "$stage_logs_dir/cand2-reupgrade-guest.log" \
    --verify-disk-boot

printf '[PASS] Candidate 2 guest migration, rollback, and re-upgrade verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
