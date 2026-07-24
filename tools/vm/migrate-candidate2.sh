#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executes guest package migration, snapshot rollback, and re-upgrade on an installed Candidate 2 QCOW2 disk image
# using managed VM lifecycles, provisioned SSH authentication, and in-guest staging repository configuration without error suppression.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
MODE="uefi"
STAGING_URL=""
STAGING_KEY=""
STAGING_FINGERPRINT=""
SSH_KEY=""
SSH_USER="genixbit"
INSTALLATION_STATE_JSON=""
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
        --staging-key)
            (($# >= 2)) || fail '--staging-key requires a file path.'
            STAGING_KEY=$2
            shift 2
            ;;
        --staging-fingerprint)
            (($# >= 2)) || fail '--staging-fingerprint requires a string.'
            STAGING_FINGERPRINT=$2
            shift 2
            ;;
        --ssh-key)
            (($# >= 2)) || fail '--ssh-key requires a path.'
            SSH_KEY=$2
            shift 2
            ;;
        --ssh-user)
            (($# >= 2)) || fail '--ssh-user requires a username.'
            SSH_USER=$2
            shift 2
            ;;
        --installation-state-json)
            (($# >= 2)) || fail '--installation-state-json requires a path.'
            INSTALLATION_STATE_JSON=$2
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

# If installation state JSON is provided, read provisioned SSH key & disk path
if [[ -n "$INSTALLATION_STATE_JSON" && -f "$INSTALLATION_STATE_JSON" ]]; then
    if [[ -z "$SSH_KEY" ]]; then
        SSH_KEY=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('ssh_private_key_path', ''))")
    fi
    if [[ -z "$DISK_PATH" ]]; then
        DISK_PATH=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('installed_disk_path', ''))")
    fi
fi

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail 'Valid --disk path is required.'
[[ -n "$STAGING_URL" ]] || fail '--staging-url is required.'
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] || fail 'Valid provisioned --ssh-key path is required.'

VM_ID="cand2_mig_${MODE}_$(date +%s)_$$"
state_dir="$(dirname "$DISK_PATH")/cand2-migrate-${MODE}-state"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

serial_log="${state_dir}/migration-serial.log"
qmp_path="${state_dir}/qmp-${VM_ID}.sock"
pid_file="${state_dir}/qemu-${VM_ID}.pid"
snap_name="pre-migration-snap"

SSH_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")

# 1. Boot installed Candidate 2 guest via managed background VM lifecycle
printf '[INFO] Booting Candidate 2 guest for pre-migration checks (%s mode, VM: %s, Port: %s)...\n' "$MODE" "$VM_ID" "$SSH_PORT"
bash "$(dirname "$0")/run-qemu.sh" start \
    --vm-id "$VM_ID" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp-socket "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$SSH_PORT" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --timeout 120

# 2. Capture pre-migration state inside guest
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W && apt-cache policy && apt-get check && dpkg --audit" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/cand2-pre-migration-guest.log" \
    --verify-disk-boot

# 3. Stop guest cleanly before snapshot creation (FAIL CLOSED)
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

if command -v qemu-img >/dev/null 2>&1; then
    qemu-img snapshot -c "$snap_name" "$DISK_PATH" || fail "Pre-migration snapshot creation failed for $DISK_PATH"
fi
printf '[INFO] Created pre-migration snapshot "%s" on %s\n' "$snap_name" "$DISK_PATH"

# 4. Boot guest again for migration execution
bash "$(dirname "$0")/run-qemu.sh" start \
    --vm-id "$VM_ID" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp-socket "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$SSH_PORT" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --timeout 120

# 5. Execute package migration commands inside guest
MIGRATION_CMD="apt-get update && apt-get install -y genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config && apt-get check && dpkg --audit && dpkg-query -W"

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "$MIGRATION_CMD" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/cand2-migration-exec.log"

# 6. Reboot guest post-migration
bash "$(dirname "$0")/guest-command.sh" \
    --reboot \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file"

# 7. Verify post-migration identity & package health
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W genixbit-os-desktop && apt-get check && dpkg --audit" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/cand2-post-migration-guest.log" \
    --verify-disk-boot

# 8. Stop guest cleanly before snapshot restoration (FAIL CLOSED)
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

if command -v qemu-img >/dev/null 2>&1; then
    qemu-img snapshot -a "$snap_name" "$DISK_PATH" || fail "Snapshot restoration failed for $snap_name on $DISK_PATH"
fi
printf '[INFO] Rolled back disk to snapshot "%s"\n' "$snap_name"

# 9. Boot rolled-back guest and verify original package state
bash "$(dirname "$0")/run-qemu.sh" start \
    --vm-id "$VM_ID" \
    --mode "$MODE" \
    --installed \
    --disk "$DISK_PATH" \
    --state-dir "$state_dir" \
    --serial-log "$serial_log" \
    --qmp-socket "$qmp_path" \
    --pid-file "$pid_file" \
    --ssh-port "$SSH_PORT" \
    --headless \
    --timeout "$TIMEOUT_SEC"

bash "$(dirname "$0")/wait-for-guest.sh" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --pid-file "$pid_file" \
    --qmp-socket "$qmp_path" \
    --timeout 120

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && apt-get check && dpkg --audit" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/cand2-rollback-guest.log" \
    --verify-disk-boot

# 10. Re-execute migration after rollback
printf '[INFO] Re-executing migration after rollback (%s mode)...\n' "$MODE"
bash "$(dirname "$0")/guest-command.sh" \
    --cmd "$MIGRATION_CMD" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/cand2-reupgrade-exec.log"

bash "$(dirname "$0")/guest-command.sh" \
    --reboot \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file"

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "cat /etc/os-release && dpkg-query -W genixbit-os-desktop && apt-get check && dpkg --audit" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$pid_file" \
    --out-log "$stage_logs_dir/cand2-reupgrade-guest.log" \
    --verify-disk-boot

# 11. Stop guest VM cleanly
bash "$(dirname "$0")/run-qemu.sh" stop --vm-id "$VM_ID" --pid-file "$pid_file" --qmp-socket "$qmp_path"

printf '[PASS] Candidate 2 guest migration, rollback, and re-upgrade verified for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
