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
RUNTIME_EVIDENCE_DIR=""

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
        --runtime-evidence-dir)
            (($# >= 2)) || fail '--runtime-evidence-dir requires a path.'
            RUNTIME_EVIDENCE_DIR=$2
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

# Compute installation-state SHA-256 for binding (must match exactly between install and migrate)
INSTALLATION_STATE_SHA256=$(sha256sum "$INSTALLATION_STATE_JSON" | awk '{print $1}')

# Read binding fields from installation state for migration-result attestation
INSTALL_SOURCE_COMMIT=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('source_commit', 'unknown'))")
INSTALL_SOURCE_ISO_SHA256=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('source_iso_sha256', 'unknown'))")
INSTALL_SOURCE_ISO_SHA512=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('source_iso_sha512', 'unknown'))")
INSTALL_INSTALLER_VM_ID=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('vm_id', 'unknown'))")
INSTALL_INSTALLED_VM_ID=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('installed_vm_id', 'unknown'))")
INSTALL_WORKFLOW_RUN_ID=$(python3 -c "import sys, json; print(json.load(open('$INSTALLATION_STATE_JSON')).get('workflow_run_id', 'unknown'))")

# Current execution context
MIG_WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-local}"
MIG_SOURCE_COMMIT=$(git -C "$(dirname "$(readlink -f "$0")")/../.." rev-parse HEAD 2>/dev/null || echo "unknown")

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail "Installed disk path ($DISK_PATH) is required and must exist."
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] || fail "Provisioned SSH private key ($SSH_KEY) is required and must exist."

KEY_PERMS=$(stat -c "%a" "$SSH_KEY" 2>/dev/null || stat -f "%Lp" "$SSH_KEY" 2>/dev/null || echo "600")
[[ "$KEY_PERMS" == "600" || "$KEY_PERMS" == "0600" ]] || fail "SSH private key permissions ($KEY_PERMS) must be 0600."

# Require qemu-img for snapshot operations (FAIL CLOSED)
command -v qemu-img >/dev/null 2>&1 || fail "qemu-img binary required for snapshot rollback operations."

VM_ID="cand2_mig_${MODE}_$(date +%s)_$$"
RUN_ID="$(date +%s)_$$_$(git -C "$(dirname "$(readlink -f "$0")")/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
state_dir="$(dirname "$DISK_PATH")/cand2-migrate-${MODE}-state"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

# Persistent runtime evidence dir (survives validation cleanup)
if [[ -z "$RUNTIME_EVIDENCE_DIR" ]]; then
    RUNTIME_EVIDENCE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/runtime/mig-$(date +%s)-$$"
fi
mkdir -p "$RUNTIME_EVIDENCE_DIR"
info "Migration runtime evidence directory: $RUNTIME_EVIDENCE_DIR"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
snap_name="pre-migration-snap"
out_json="${state_dir}/migration-result-${VM_ID}.json"

# VM registry for fail-safe cleanup on any failure
declare -a MIG_VM_REGISTRY=()

mig_register_vm() {
    local label="$1"
    local vm_id="$2"
    local pid_file="$3"
    local qmp_socket="$4"
    local serial_log="$5"
    MIG_VM_REGISTRY+=("$label|$vm_id|$pid_file|$qmp_socket|$serial_log")
}

mig_unregister_vm() {
    local label="$1"
    local new_reg=()
    for entry in "${MIG_VM_REGISTRY[@]}"; do
        local entry_label="${entry%%|*}"
        if [[ "$entry_label" != "$label" ]]; then
            new_reg+=("$entry")
        fi
    done
    MIG_VM_REGISTRY=("${new_reg[@]}")
}

mig_cleanup_all_vms() {
    local rc=0
    for entry in "${MIG_VM_REGISTRY[@]}"; do
        IFS='|' read -r label vm_id pid_file qmp_socket serial_log <<< "$entry"
        info "Cleaning up migration VM: $label ($vm_id)"
        if [[ -f "$pid_file" ]]; then
            local vpid
            vpid=$(cat "$pid_file" 2>/dev/null || echo "")
            if [[ -n "$vpid" ]] && kill -0 "$vpid" 2>/dev/null; then
                bash "$SCRIPT_DIR/run-qemu.sh" stop \
                    --vm-id "$vm_id" \
                    --pid-file "$pid_file" \
                    --qmp-socket "$qmp_socket" \
                    --state-dir "$state_dir" || rc=1
            fi
        fi
        # Preserve lifecycle evidence
        if [[ -f "${state_dir}/vm-${vm_id}.json" ]]; then
            cp -f "${state_dir}/vm-${vm_id}.json" "$RUNTIME_EVIDENCE_DIR/migration-${label}-vm-state.json" 2>/dev/null || true
        fi
        if [[ -f "${state_dir}/shutdown-${vm_id}.json" ]]; then
            cp -f "${state_dir}/shutdown-${vm_id}.json" "$RUNTIME_EVIDENCE_DIR/migration-${label}-shutdown.json" 2>/dev/null || true
        fi
    done
    return "$rc"
}

mig_cleanup_trap() {
    local original_exit=$?
    trap - EXIT
    set +e
    mig_cleanup_all_vms
    set -e
    if [[ "$original_exit" -ne 0 ]]; then
        exit "$original_exit"
    fi
}

trap mig_cleanup_trap EXIT

# Track observed values for migration-result.json — all populated from real command output
OBS_PRE_MIGRATION_PACKAGES=""
OBS_APT_UPDATE_EXIT=""
OBS_APT_CACHE_POLICY=""
OBS_APT_INSTALL_EXIT=""
OBS_POST_DPKG_QUERY=""
OBS_POST_APT_CHECK_EXIT=""
OBS_POST_DPKG_AUDIT_EXIT=""
OBS_POST_DPKG_AUDIT_EMPTY="false"
OBS_POST_BOOT_OS_RELEASE=""
OBS_ROLLBACK_DPKG_QUERY=""
OBS_REUPGRADE_DPKG_QUERY=""
OBS_FINAL_OS_RELEASE=""
OBS_STAGING_FINGERPRINT_MATCH="false"
OBS_ALL_PACKAGE_ORIGINS_VERIFIED="false"
OBS_ROLLBACK_STATE_EQUALITY="false"
PRE_STATE_SHA256=""
ROLLBACK_STATE_SHA256=""

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

    mig_register_vm "$vm_label" "$mig_vm_id" "$pid_f" "$qmp_s" "$serial_log"

    echo "$mig_vm_id"
}

# Helper: wait for SSH on a migration VM
# Uses a unique per-VM-lifecycle readiness token so each wait is independently verified.
wait_ssh() {
    local vm_label="$1" port="$2"
    local mig_vm_id="${VM_ID}_${vm_label}"
    local pid_f="${state_dir}/qemu-${mig_vm_id}.pid"
    local readiness_token="MIG_GUEST_${vm_label}_${RUN_ID}_$(date +%s)"

    bash "$SCRIPT_DIR/wait-for-guest.sh" \
        --ssh-port "$port" \
        --ssh-user "$SSH_USER" \
        --ssh-key "$SSH_KEY" \
        --token "$readiness_token" \
        --pid-file "$pid_f" \
        --timeout "$TIMEOUT_SEC" || fail "Migration VM ($vm_label) SSH not reachable on port $port"
}

# Helper: stop migration VM — fail-closed: only STOPPED_GRACEFULLY / ALREADY_STOPPED_VERIFIED are safe
# to proceed to offline disk access or snapshot operations.
stop_migration_vm() {
    local vm_label="$1"
    local mig_vm_id="${VM_ID}_${vm_label}"
    local pid_f="${state_dir}/qemu-${mig_vm_id}.pid"
    local qmp_s="${state_dir}/qmp-${mig_vm_id}.sock"
    local stop_out
    stop_out=$(bash "$SCRIPT_DIR/run-qemu.sh" stop \
        --vm-id "$mig_vm_id" \
        --pid-file "$pid_f" \
        --qmp-socket "$qmp_s" \
        --state-dir "$state_dir" 2>&1) || {
        fail "Migration VM stop FAILED for $vm_label (${stop_out}) — cannot proceed to offline disk access!"
    }
    # Verify process is truly gone before returning
    if [[ -f "$pid_f" ]]; then
        local pid; pid=$(cat "$pid_f" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            fail "Migration VM $vm_label PID $pid still alive after stop — cannot proceed to snapshot/offline operations!"
        fi
    fi

    # Copy lifecycle evidence to runtime evidence dir
    if [[ -f "${state_dir}/vm-${mig_vm_id}.json" ]]; then
        cp -f "${state_dir}/vm-${mig_vm_id}.json" "$RUNTIME_EVIDENCE_DIR/migration-${vm_label}-vm-state.json" 2>/dev/null || true
    fi
    if [[ -f "${state_dir}/shutdown-${mig_vm_id}.json" ]]; then
        cp -f "${state_dir}/shutdown-${mig_vm_id}.json" "$RUNTIME_EVIDENCE_DIR/migration-${vm_label}-shutdown.json" 2>/dev/null || true
    fi

    mig_unregister_vm "$vm_label"
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

    echo "=== Dearmor staging key inside guest ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "gpg --dearmor < /tmp/staging.gpg > /tmp/staging-keyring.gpg" 2>&1

    echo ""
    echo "=== Verify staging key fingerprint inside guest (machine-readable) ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "gpg --show-keys --with-colons /tmp/staging.gpg 2>&1" 2>&1

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
    echo "=== apt-cache madison (package origin verification) ==="
    ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "apt-cache madison genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files \
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

# D5: Exact fingerprint comparison — extract from guest via machine-readable gpg output
OBSERVED_FINGERPRINT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "gpg --show-keys --with-colons /tmp/staging.gpg 2>/dev/null | awk -F: '\$1==\"fpr\"{print \$10;exit}'" \
    2>/dev/null || echo "")
OBSERVED_FINGERPRINT=${OBSERVED_FINGERPRINT//[[:space:]]/}
EXPECTED_FINGERPRINT_NORM=${STAGING_FINGERPRINT//[[:space:]]/}
[[ -n "$OBSERVED_FINGERPRINT" ]] || fail "Could not read staging key fingerprint inside guest!"
[[ "$OBSERVED_FINGERPRINT" == "$EXPECTED_FINGERPRINT_NORM" ]] || \
    fail "Staging key fingerprint mismatch: got '$OBSERVED_FINGERPRINT', expected '$EXPECTED_FINGERPRINT_NORM'"
OBS_STAGING_FINGERPRINT_MATCH="true"
info "Staging key fingerprint verified: $OBSERVED_FINGERPRINT"

# D6: Package origin verification — each of the 7 packages must have a Candidate from STAGING_URL/resolute-alpha
for pkg in genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files \
           genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config; do
    CAND=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "apt-cache policy ${pkg} 2>/dev/null | awk '/Candidate:/{print \$2}'" 2>/dev/null || echo "")
    [[ -n "$CAND" && "$CAND" != "(none)" ]] || \
        fail "Package $pkg has no Candidate version in apt-cache policy — staging repo not reachable or index not loaded"
    ORIGIN=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
        "apt-cache madison ${pkg} 2>/dev/null | grep 'resolute-alpha'" 2>/dev/null || echo "")
    # Verify origin contains the staging URL
    printf '%s' "$ORIGIN" | grep -qF "$STAGING_URL" || \
        fail "Package $pkg Candidate does not come from $STAGING_URL resolute-alpha — wrong origin: '$ORIGIN'"
done
OBS_ALL_PACKAGE_ORIGINS_VERIFIED="true"
info "All 7 package origins verified from $STAGING_URL resolute-alpha"

# D7: Capture actual apt-get install exit code
APT_INSTALL_RC=0
ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
     genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files \
     genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config 2>&1" || APT_INSTALL_RC=$?
OBS_APT_INSTALL_EXIT="$APT_INSTALL_RC"
[[ "$APT_INSTALL_RC" == "0" ]] || fail "apt-get install failed with exit code $APT_INSTALL_RC — release gate fails!"
info "apt-get install completed successfully (exit 0)"

OBS_APT_UPDATE_EXIT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo apt-get update > /dev/null 2>&1; echo \$?" 2>/dev/null || echo "unknown")

OBS_POST_DPKG_QUERY=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n'" 2>/dev/null || echo "unavailable")

OBS_APT_CACHE_POLICY=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "apt-cache policy genixbit-os-desktop 2>/dev/null" || echo "unavailable")

OBS_POST_APT_CHECK_EXIT=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo apt-get check > /dev/null 2>&1; echo \$?" 2>/dev/null || echo "unknown")

# D8: Capture dpkg --audit exit code AND stdout; fail if non-empty output
OBS_DPKG_AUDIT_RAW=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo dpkg --audit 2>&1" 2>/dev/null || echo "")
OBS_POST_DPKG_AUDIT_EXIT=$?
OBS_POST_DPKG_AUDIT_EMPTY=$([[ -z "$OBS_DPKG_AUDIT_RAW" ]] && echo "true" || echo "false")
[[ "$OBS_POST_DPKG_AUDIT_EXIT" == "0" && -z "$OBS_DPKG_AUDIT_RAW" ]] || \
    fail "dpkg --audit not clean after migration (exit=$OBS_POST_DPKG_AUDIT_EXIT, output='$OBS_DPKG_AUDIT_RAW')"
info "dpkg --audit clean (exit 0, empty output)"

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

# D9: SHA-based equality check: rollback state MUST match pre-migration state exactly
PRE_STATE_SORTED=$(printf '%s' "$OBS_PRE_MIGRATION_PACKAGES" | LC_ALL=C sort)
PRE_STATE_SHA256=$(printf '%s' "$PRE_STATE_SORTED" | sha256sum | awk '{print $1}')
ROLLBACK_STATE_SORTED=$(printf '%s' "$OBS_ROLLBACK_DPKG_QUERY" | LC_ALL=C sort)
ROLLBACK_STATE_SHA256=$(printf '%s' "$ROLLBACK_STATE_SORTED" | sha256sum | awk '{print $1}')
if [[ "$PRE_STATE_SHA256" != "$ROLLBACK_STATE_SHA256" ]]; then
    fail "Rollback package state SHA-256 mismatch! pre=$PRE_STATE_SHA256, rollback=$ROLLBACK_STATE_SHA256 — snapshot did not restore original package state!"
fi
OBS_ROLLBACK_STATE_EQUALITY="true"
info "Rollback package state SHA-256 matches pre-migration state: $ROLLBACK_STATE_SHA256"

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
    'run_id': '$RUN_ID',
    'disk_identity': '$DISK_PATH',
    'firmware_mode': '$MODE',
    'ssh_username': '$SSH_USER',
    'staging_url': '$STAGING_URL',
    'observed_staging_fingerprint': '$OBSERVED_FINGERPRINT',
    'expected_staging_fingerprint': '$STAGING_FINGERPRINT',
    'staging_key_fingerprint_match': '$OBS_STAGING_FINGERPRINT_MATCH',
    'all_package_origins_verified': '$OBS_ALL_PACKAGE_ORIGINS_VERIFIED',
    'pre_migration_package_state': '''$OBS_PRE_MIGRATION_PACKAGES''',
    'pre_migration_state_sha256': '$PRE_STATE_SHA256',
    'apt_update_exit_code': '$OBS_APT_UPDATE_EXIT',
    'apt_cache_policy_output': '''$OBS_APT_CACHE_POLICY''',
    'apt_install_exit_code': '$OBS_APT_INSTALL_EXIT',
    'post_install_dpkg_query': '''$OBS_POST_DPKG_QUERY''',
    'apt_check_exit_code': '$OBS_POST_APT_CHECK_EXIT',
    'dpkg_audit_exit_code': '$OBS_POST_DPKG_AUDIT_EXIT',
    'dpkg_audit_output_empty': '$OBS_POST_DPKG_AUDIT_EMPTY',
    'post_migration_boot_os_release': '''$OBS_POST_BOOT_OS_RELEASE''',
    'rollback_dpkg_query': '''$OBS_ROLLBACK_DPKG_QUERY''',
    'rollback_state_sha256': '$ROLLBACK_STATE_SHA256',
    'rollback_package_state_matches_pre_migration': '$OBS_ROLLBACK_STATE_EQUALITY',
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
    # Migration VM lifecycle evidence paths
    'lifecycle_evidence': [
        '$RUNTIME_EVIDENCE_DIR/migration-premig-vm-state.json',
        '$RUNTIME_EVIDENCE_DIR/migration-premig-shutdown.json',
        '$RUNTIME_EVIDENCE_DIR/migration-mig-vm-state.json',
        '$RUNTIME_EVIDENCE_DIR/migration-mig-shutdown.json',
        '$RUNTIME_EVIDENCE_DIR/migration-rollback-vm-state.json',
        '$RUNTIME_EVIDENCE_DIR/migration-rollback-shutdown.json',
        '$RUNTIME_EVIDENCE_DIR/migration-reupgrade-vm-state.json',
        '$RUNTIME_EVIDENCE_DIR/migration-reupgrade-shutdown.json',
    ],
    'lifecycle_evidence_sha256': {
        'premig': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-premig-vm-state.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'premig_shutdown': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-premig-shutdown.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'mig': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-mig-vm-state.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'mig_shutdown': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-mig-shutdown.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'rollback': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-rollback-vm-state.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'rollback_shutdown': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-rollback-shutdown.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'reupgrade': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-reupgrade-vm-state.json" 2>/dev/null | awk "{print \$1}" || echo "")',
        'reupgrade_shutdown': '$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-reupgrade-shutdown.json" 2>/dev/null | awk "{print \$1}" || echo "")',
    },
    # Binding fields — attest that migration ran on the exact same candidate2 build
    'source_commit': '$MIG_SOURCE_COMMIT',
    'workflow_run_id': '$MIG_WORKFLOW_RUN_ID',
    'installation_state_sha256': '$INSTALLATION_STATE_SHA256',
    'source_iso_sha256': '$INSTALL_SOURCE_ISO_SHA256',
    'source_iso_sha512': '$INSTALL_SOURCE_ISO_SHA512',
    'installation_installer_vm_id': '$INSTALL_INSTALLER_VM_ID',
    'installation_installed_vm_id': '$INSTALL_INSTALLED_VM_ID',
    'installation_workflow_run_id': '$INSTALL_WORKFLOW_RUN_ID',
    'migration_vm_id': '$VM_ID',
}

# Final status: ALL observed conditions plus binding fields must be satisfied
all_pass = (
    result['apt_install_exit_code'] == '0' and
    result['apt_check_exit_code'] == '0' and
    result['dpkg_audit_exit_code'] == '0' and
    result['dpkg_audit_output_empty'] == 'true' and
    result['staging_key_fingerprint_match'] == 'true' and
    result['all_package_origins_verified'] == 'true' and
    result['rollback_package_state_matches_pre_migration'] == 'true' and
    result['apt_update_exit_code'] == '0' and
    result['pre_migration_state_sha256'] != '' and
    result['rollback_state_sha256'] != '' and
    result['pre_migration_state_sha256'] == result['rollback_state_sha256'] and
    result['post_migration_boot_os_release'] not in ('', 'unavailable') and
    result['post_install_dpkg_query'] not in ('', 'unavailable') and
    result['rollback_dpkg_query'] not in ('', 'unavailable') and
    result['reupgrade_dpkg_query'] not in ('', 'unavailable') and
    result['final_os_release'] not in ('', 'unavailable') and
    result['observed_staging_fingerprint'] != '' and
    result['vm_id'] != '' and
    # Binding field validation
    result['source_commit'] != '' and
    result['workflow_run_id'] != '' and
    result['installation_state_sha256'] != '' and
    result['source_iso_sha256'] != '' and
    result['migration_vm_id'] != '' and
    # Lifecycle evidence validation — all phases must have vm-state and shutdown evidence
    result.get('lifecycle_evidence_sha256', {}).get('premig', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('premig_shutdown', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('mig', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('mig_shutdown', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('rollback', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('rollback_shutdown', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('reupgrade', '') != '' and
    result.get('lifecycle_evidence_sha256', {}).get('reupgrade_shutdown', '') != ''
)
result['migration_status'] = 'PASS' if all_pass else 'FAIL'
result['final_status'] = 'PASS' if all_pass else 'FAIL'
with open('$out_json', 'w') as f:
    json.dump(result, f, indent=2)
print(result['final_status'])
PYEOF

FINAL_STATUS=$(python3 -c "import json; d=json.load(open('$out_json')); print(d.get('final_status','FAIL'))")
[[ "$FINAL_STATUS" == "PASS" ]] || fail "Migration result final_status is '$FINAL_STATUS' — gate fails."

printf 'GENIXBIT_MIGRATION_RESULT=%s\n' "$out_json"
printf '[PASS] Candidate 2 real APT migration, rollback, and re-upgrade verified and recorded in %s for %s mode: %s\n' \
    "$out_json" "$MODE" "$DISK_PATH"
exit 0
