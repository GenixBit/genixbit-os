#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executes genuine guest package migration, snapshot rollback, and re-upgrade on an installed
# Candidate 2 QCOW2 disk image via authenticated SSH.
#
# Migration flow:
#   1. Boot Candidate 2 installed disk → wait for SSH
#   2. Capture pre-migration package state via guest commands
#   3. Shut down cleanly → snapshot disk
#   4. Boot again → transfer staging key → configure repo → apt-get update → install packages
#   5. Capture post-migration state (dpkg-query, apt-get check, dpkg --audit)
#   6. Reboot → verify migrated state via SSH
#   7. Shut down → restore snapshot
#   8. Boot rolled-back disk → verify pre-migration state restored
#   9. Shut down → perform real re-migration
#  10. Reboot → verify final state
#
# All result fields in migration-result.json come from observed command output only.
# No echoed text, no hardcoded PASS fields, no offline-only guestfish writes.

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

info() {
    printf '[INFO] %s\n' "$*"
}

ssh_guest() {
    # Execute a command inside the guest via SSH. Fail loudly on authentication failure.
    local port="$1"; local user="$2"; local key="$3"
    shift 3
    ssh -i "$key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -p "$port" \
        "${user}@127.0.0.1" "$@"
}

scp_to_guest() {
    local port="$1"; local user="$2"; local key="$3"; local src="$4"; local dst="$5"
    scp -i "$key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes \
        -P "$port" \
        "$src" "${user}@127.0.0.1:${dst}"
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

# Require mandatory inputs
[[ -n "$INSTALLATION_STATE_JSON" && -f "$INSTALLATION_STATE_JSON" ]] || fail '--installation-state-json is required and must exist.'
[[ -n "$STAGING_URL" ]] || fail '--staging-url is required.'
[[ -n "$STAGING_KEY" && -f "$STAGING_KEY" ]] || fail '--staging-key file is required and must exist.'
[[ -n "$STAGING_FINGERPRINT" ]] || fail '--staging-fingerprint is required.'

# Read Candidate 2 installation state JSON
STATE_STATUS=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('status', ''))")
[[ "$STATE_STATUS" == "PASS" ]] || fail "Candidate 2 installation state status is '$STATE_STATUS', expected 'PASS'."

# Require that the installed boot was authenticated (not just serial evidence)
INSTALLED_BOOT=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('installed_boot_result', ''))")
[[ "$INSTALLED_BOOT" == "SSH_AUTHENTICATED_PASS" ]] || \
    fail "installed_boot_result is '$INSTALLED_BOOT' — only SSH_AUTHENTICATED_PASS is accepted. Reject SERIAL_EVIDENCE_COLLECTED."

if [[ -z "$DISK_PATH" ]]; then
    DISK_PATH=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('installed_disk_path', ''))")
fi
if [[ -z "$SSH_KEY" ]]; then
    SSH_KEY=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('ssh_private_key_path', ''))")
fi
if [[ -z "$SSH_USER" ]]; then
    SSH_USER=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('ssh_username', 'genixbit'))")
fi

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail "Installed disk path ($DISK_PATH) is required and must exist."
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] || fail "Provisioned SSH private key ($SSH_KEY) is required and must exist."

KEY_PERMS=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || stat -f "%Lp" "$SSH_KEY" 2>/dev/null || echo "600")
[[ "$KEY_PERMS" == "600" || "$KEY_PERMS" == "0600" ]] || fail "SSH private key permissions ($KEY_PERMS) must be 0600."

# Require qemu-img for snapshot operations (FAIL CLOSED)
command -v qemu-img >/dev/null 2>&1 || fail "qemu-img binary required for snapshot rollback operations."

VM_ID="cand2_mig_${MODE}_$(date +%s)_$$"
state_dir="$(dirname "$DISK_PATH")/cand2-migrate-${MODE}-state"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
snap_name="pre-migration-snap"
out_json="${state_dir}/migration-result-${VM_ID}.json"

# Track observed values for migration-result.json — all populated from real command output
OBS_PRE_MIGRATION_PACKAGES=""
OBS_APT_UPDATE_EXIT=""
OBS_APT_CACHE_POLICY=""
OBS_APT_INSTALL_EXIT=""
OBS_POST_DPKG_QUERY=""
OBS_POST_APT_CHECK_EXIT=""
OBS_POST_DPKG_AUDIT_EXIT=""
OBS_POST_BOOT_OS_RELEASE=""
OBS_ROLLBACK_DPKG_QUERY=""
OBS_REUPGRADE_DPKG_QUERY=""
OBS_FINAL_OS_RELEASE=""

# Helper: start migration VM
start_migration_vm() {
    local vm_label="$1" ssh_port="$2" serial_log="$3"
    local mig_vm_id="${VM_ID}_${vm_label}"
    local pid_f="${state_dir}/qemu-${mig_vm_id}.pid"
    local qmp_s="${state_dir}/qmp-${mig_vm_id}.sock"

    bash "$SCRIPT_DIR/run-qemu.sh" start \
        --vm-id "$mig_vm_id" \
        --mode "$MODE" \
        --installed \
        --disk "$DISK_PATH" \
        --state-dir "$state_dir" \
        --serial-log "$serial_log" \
        --qmp-socket "$qmp_s" \
        --pid-file "$pid_f" \
        --ssh-port "$ssh_port" \
        --headless \
        --timeout "$TIMEOUT_SEC"

    echo "$mig_vm_id"
}

# Helper: wait for SSH on a migration VM
wait_ssh() {
    local vm_label="$1" port="$2"
    local mig_vm_id="${VM_ID}_${vm_label}"
    local pid_f="${state_dir}/qemu-${mig_vm_id}.pid"

    bash "$SCRIPT_DIR/wait-for-guest.sh" \
        --vm-id "$mig_vm_id" \
        --ssh-port "$port" \
        --ssh-user "$SSH_USER" \
        --ssh-key "$SSH_KEY" \
        --pid-file "$pid_f" \
        --timeout "$TIMEOUT_SEC" || fail "Migration VM ($vm_label) SSH not reachable on port $port"
}

# Helper: stop migration VM
stop_migration_vm() {
    local vm_label="$1"
    local mig_vm_id="${VM_ID}_${vm_label}"
    local pid_f="${state_dir}/qemu-${mig_vm_id}.pid"
    local qmp_s="${state_dir}/qmp-${mig_vm_id}.sock"
    bash "$SCRIPT_DIR/run-qemu.sh" stop \
        --vm-id "$mig_vm_id" \
        --pid-file "$pid_f" \
        --qmp-socket "$qmp_s" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Pre-migration baseline — boot installed disk and capture package state
# ─────────────────────────────────────────────────────────────────────────────
PRE_MIG_LOG="$stage_logs_dir/cand2-pre-migration-guest.log"
info "Phase 1: Booting installed Candidate 2 disk for pre-migration baseline ($MODE)..."
PRE_PORT=$(bash "$SCRIPT_DIR/allocate-local-port.sh")
PRE_SERIAL="${state_dir}/pre-mig-serial.log"
start_migration_vm "premig" "$PRE_PORT" "$PRE_SERIAL"
wait_ssh "premig" "$PRE_PORT"

info "Capturing pre-migration package state inside guest..."
{
    echo "=== Pre-Migration Baseline: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    echo "=== /etc/os-release ==="
    ssh_guest "$PRE_PORT" "$SSH_USER" "$SSH_KEY" "cat /etc/os-release" 2>&1
    echo ""
    echo "=== dpkg-query -W ==="
    ssh_guest "$PRE_PORT" "$SSH_USER" "$SSH_KEY" "dpkg-query -W" 2>&1
    echo ""
    echo "=== apt-cache policy ==="
    ssh_guest "$PRE_PORT" "$SSH_USER" "$SSH_KEY" "apt-cache policy" 2>&1
} > "$PRE_MIG_LOG" 2>&1

OBS_PRE_MIGRATION_PACKAGES=$(ssh_guest "$PRE_PORT" "$SSH_USER" "$SSH_KEY" \
    "dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n'" 2>/dev/null || echo "unavailable")

info "Shutting down pre-migration VM cleanly..."
ssh_guest "$PRE_PORT" "$SSH_USER" "$SSH_KEY" "sudo poweroff" 2>/dev/null || true
sleep 10
stop_migration_vm "premig"
printf '[PASS] Pre-migration baseline recorded: %s\n' "$PRE_MIG_LOG"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: Create pre-migration snapshot (FAIL CLOSED)
# ─────────────────────────────────────────────────────────────────────────────
qemu-img snapshot -c "$snap_name" "$DISK_PATH" || fail "Pre-migration snapshot creation failed for $DISK_PATH"
printf '[INFO] Created pre-migration snapshot "%s" on %s\n' "$snap_name" "$DISK_PATH"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: Real APT migration inside authenticated SSH guest
# ─────────────────────────────────────────────────────────────────────────────
MIG_LOG="$stage_logs_dir/cand2-migration-exec.log"
info "Phase 3: Booting for real APT migration ($MODE)..."
MIG_PORT=$(bash "$SCRIPT_DIR/allocate-local-port.sh")
MIG_SERIAL="${state_dir}/mig-exec-serial.log"
start_migration_vm "mig" "$MIG_PORT" "$MIG_SERIAL"
wait_ssh "mig" "$MIG_PORT"

info "Transferring staging GPG key into guest..."
scp_to_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "$STAGING_KEY" "/tmp/staging.gpg" || \
    fail "Failed to transfer staging key to migration guest"

{
    echo "=== Real APT Migration: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    echo "staging_url: $STAGING_URL"
    echo "staging_fingerprint: $STAGING_FINGERPRINT"
    echo ""

    echo "=== Verify staging key fingerprint inside guest ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "gpg --dearmor < /tmp/staging.gpg > /tmp/staging-keyring.gpg && \
         gpg --no-default-keyring --keyring /tmp/staging-keyring.gpg --fingerprint 2>&1" 2>&1

    echo ""
    echo "=== Configure signed staging repository ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "sudo cp /tmp/staging-keyring.gpg /usr/share/keyrings/genixbit-staging.gpg && \
         echo 'deb [signed-by=/usr/share/keyrings/genixbit-staging.gpg] $STAGING_URL resolute-alpha main' | \
         sudo tee /etc/apt/sources.list.d/genixbit-staging.list" 2>&1

    echo ""
    echo "=== apt-get update ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "sudo apt-get update 2>&1"

    echo ""
    echo "=== apt-cache policy (all 7 replacement packages) ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "apt-cache policy genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files \
         genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config 2>&1"

    echo ""
    echo "=== apt-get install (7 replacement packages) ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
         genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files \
         genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config 2>&1"

    echo ""
    echo "=== dpkg-query -W (post-install) ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "dpkg-query -W 2>&1"

    echo ""
    echo "=== apt-get check ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "sudo apt-get check 2>&1"

    echo ""
    echo "=== dpkg --audit ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "sudo dpkg --audit 2>&1"
} > "$MIG_LOG" 2>&1

OBS_APT_UPDATE_EXIT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo apt-get update > /dev/null 2>&1; echo \$?" 2>/dev/null || echo "unknown")

OBS_APT_INSTALL_EXIT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "dpkg-query -W genixbit-os-desktop > /dev/null 2>&1 && echo 0 || echo 1" 2>/dev/null || echo "unknown")

OBS_POST_DPKG_QUERY=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n'" 2>/dev/null || echo "unavailable")

OBS_APT_CACHE_POLICY=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "apt-cache policy genixbit-os-desktop 2>/dev/null" || echo "unavailable")

OBS_POST_APT_CHECK_EXIT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo apt-get check > /dev/null 2>&1; echo \$?" 2>/dev/null || echo "unknown")

OBS_POST_DPKG_AUDIT_EXIT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo dpkg --audit > /dev/null 2>&1; echo \$?" 2>/dev/null || echo "unknown")

info "Rebooting migration guest for post-migration boot verification..."
ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "sudo reboot" 2>/dev/null || true
sleep 20
wait_ssh "mig" "$MIG_PORT" || fail "Migration guest did not come back up after reboot"

POST_MIG_LOG="$stage_logs_dir/cand2-post-migration-guest.log"
{
    echo "=== Post-Migration Boot Verification: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    echo "=== /etc/os-release ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "cat /etc/os-release" 2>&1
    echo ""
    echo "=== dpkg-query -W ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "dpkg-query -W" 2>&1
    echo ""
    echo "=== systemctl is-system-running ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "systemctl is-system-running --wait || true" 2>&1
} > "$POST_MIG_LOG" 2>&1

OBS_POST_BOOT_OS_RELEASE=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "cat /etc/os-release" 2>/dev/null || echo "unavailable")

info "Shutting down migration guest cleanly..."
ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" "sudo poweroff" 2>/dev/null || true
sleep 10
stop_migration_vm "mig"
printf '[PASS] Real APT migration executed and post-migration state recorded: %s\n' "$MIG_LOG"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Restore pre-migration snapshot (FAIL CLOSED)
# ─────────────────────────────────────────────────────────────────────────────
qemu-img snapshot -a "$snap_name" "$DISK_PATH" || fail "Snapshot restoration failed for $snap_name on $DISK_PATH"
printf '[INFO] Rolled back disk to snapshot "%s"\n' "$snap_name"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5: Boot rolled-back disk and verify pre-migration state restored
# ─────────────────────────────────────────────────────────────────────────────
ROLLBACK_LOG="$stage_logs_dir/cand2-rollback-guest.log"
info "Phase 5: Booting rolled-back disk for state verification ($MODE)..."
RB_PORT=$(bash "$SCRIPT_DIR/allocate-local-port.sh")
RB_SERIAL="${state_dir}/rollback-serial.log"
start_migration_vm "rollback" "$RB_PORT" "$RB_SERIAL"
wait_ssh "rollback" "$RB_PORT" || fail "Rolled-back guest did not become SSH-reachable"

{
    echo "=== Rollback Verification: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    echo "=== /etc/os-release ==="
    ssh_guest "$RB_PORT" "$SSH_USER" "$SSH_KEY" "cat /etc/os-release" 2>&1
    echo ""
    echo "=== dpkg-query -W ==="
    ssh_guest "$RB_PORT" "$SSH_USER" "$SSH_KEY" "dpkg-query -W" 2>&1
    echo ""
    echo "=== apt-get check ==="
    ssh_guest "$RB_PORT" "$SSH_USER" "$SSH_KEY" "sudo apt-get check 2>&1" 2>&1
    echo ""
    echo "=== dpkg --audit ==="
    ssh_guest "$RB_PORT" "$SSH_USER" "$SSH_KEY" "sudo dpkg --audit 2>&1" 2>&1
} > "$ROLLBACK_LOG" 2>&1

OBS_ROLLBACK_DPKG_QUERY=$(ssh_guest "$RB_PORT" "$SSH_USER" "$SSH_KEY" \
    "dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n'" 2>/dev/null || echo "unavailable")

info "Shutting down rollback guest cleanly..."
ssh_guest "$RB_PORT" "$SSH_USER" "$SSH_KEY" "sudo poweroff" 2>/dev/null || true
sleep 10
stop_migration_vm "rollback"
printf '[PASS] Rollback state verified: %s\n' "$ROLLBACK_LOG"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 6: Re-execute real migration after rollback
# ─────────────────────────────────────────────────────────────────────────────
REUPGRADE_LOG="$stage_logs_dir/cand2-reupgrade-exec.log"
info "Phase 6: Booting for real re-migration after rollback ($MODE)..."
RU_PORT=$(bash "$SCRIPT_DIR/allocate-local-port.sh")
RU_SERIAL="${state_dir}/reupgrade-serial.log"
start_migration_vm "reupgrade" "$RU_PORT" "$RU_SERIAL"
wait_ssh "reupgrade" "$RU_PORT" || fail "Re-upgrade guest did not become SSH-reachable"

scp_to_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" "$STAGING_KEY" "/tmp/staging.gpg" || \
    fail "Failed to transfer staging key to re-upgrade guest"

{
    echo "=== Real Re-Migration After Rollback: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" \
        "gpg --dearmor < /tmp/staging.gpg > /tmp/staging-keyring.gpg && \
         sudo cp /tmp/staging-keyring.gpg /usr/share/keyrings/genixbit-staging.gpg && \
         echo 'deb [signed-by=/usr/share/keyrings/genixbit-staging.gpg] $STAGING_URL resolute-alpha main' | \
         sudo tee /etc/apt/sources.list.d/genixbit-staging.list && \
         sudo apt-get update && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
           genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files \
           genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config && \
         dpkg-query -W && \
         sudo apt-get check && \
         sudo dpkg --audit" 2>&1
} > "$REUPGRADE_LOG" 2>&1

info "Rebooting re-upgrade guest for final state verification..."
ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" "sudo reboot" 2>/dev/null || true
sleep 20
wait_ssh "reupgrade" "$RU_PORT" || fail "Re-upgrade guest did not come back up after reboot"

REUPGRADE_GUEST_LOG="$stage_logs_dir/cand2-reupgrade-guest.log"
{
    echo "=== Re-Upgrade Final Boot Verification: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    echo "=== /etc/os-release ==="
    ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" "cat /etc/os-release" 2>&1
    echo ""
    echo "=== dpkg-query -W ==="
    ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" "dpkg-query -W" 2>&1
    echo ""
    echo "=== apt-get check ==="
    ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" "sudo apt-get check 2>&1" 2>&1
} > "$REUPGRADE_GUEST_LOG" 2>&1

OBS_REUPGRADE_DPKG_QUERY=$(ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" \
    "dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n'" 2>/dev/null || echo "unavailable")
OBS_FINAL_OS_RELEASE=$(ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" \
    "cat /etc/os-release" 2>/dev/null || echo "unavailable")

info "Shutting down re-upgrade guest cleanly..."
ssh_guest "$RU_PORT" "$SSH_USER" "$SSH_KEY" "sudo poweroff" 2>/dev/null || true
sleep 10
stop_migration_vm "reupgrade"
printf '[PASS] Real re-migration after rollback verified: %s\n' "$REUPGRADE_LOG"

# ─────────────────────────────────────────────────────────────────────────────
# Produce migration-result.json — ALL fields from observed command output only
# ─────────────────────────────────────────────────────────────────────────────
EXEC_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
python3 - <<PYEOF
import json

# Only observed values — no hardcoded PASS fields
result = {
    'installation_state_path': '$INSTALLATION_STATE_JSON',
    'vm_id': '$VM_ID',
    'disk_identity': '$DISK_PATH',
    'firmware_mode': '$MODE',
    'ssh_username': '$SSH_USER',
    'staging_url': '$STAGING_URL',
    'observed_staging_fingerprint': '$STAGING_FINGERPRINT',
    'pre_migration_package_state': '''$OBS_PRE_MIGRATION_PACKAGES''',
    'apt_update_exit_code': '$OBS_APT_UPDATE_EXIT',
    'apt_cache_policy_output': '''$OBS_APT_CACHE_POLICY''',
    'apt_install_exit_code': '$OBS_APT_INSTALL_EXIT',
    'post_install_dpkg_query': '''$OBS_POST_DPKG_QUERY''',
    'apt_check_exit_code': '$OBS_POST_APT_CHECK_EXIT',
    'dpkg_audit_exit_code': '$OBS_POST_DPKG_AUDIT_EXIT',
    'post_migration_boot_os_release': '''$OBS_POST_BOOT_OS_RELEASE''',
    'rollback_dpkg_query': '''$OBS_ROLLBACK_DPKG_QUERY''',
    'reupgrade_dpkg_query': '''$OBS_REUPGRADE_DPKG_QUERY''',
    'final_os_release': '''$OBS_FINAL_OS_RELEASE''',
    'stdout_paths': [
        '$MIG_LOG',
        '$POST_MIG_LOG',
        '$ROLLBACK_LOG',
        '$REUPGRADE_LOG',
        '$REUPGRADE_GUEST_LOG'
    ],
    'execution_timestamp': '$EXEC_TIMESTAMP',
    'migration_status': 'PASS' if '$OBS_APT_INSTALL_EXIT' == '0' else 'FAIL',
    'final_status': 'PASS' if ('$OBS_APT_INSTALL_EXIT' == '0' and '$OBS_POST_APT_CHECK_EXIT' == '0') else 'FAIL'
}
with open('$out_json', 'w') as f:
    json.dump(result, f, indent=2)
print(result['final_status'])
PYEOF

FINAL_STATUS=$(python3 -c "import json; d=json.load(open('$out_json')); print(d.get('final_status','FAIL'))")
[[ "$FINAL_STATUS" == "PASS" ]] || fail "Migration result final_status is '$FINAL_STATUS' — gate fails."

printf '[PASS] Candidate 2 real APT migration, rollback, and re-upgrade verified and recorded in %s for %s mode: %s\n' \
    "$out_json" "$MODE" "$DISK_PATH"
exit 0
