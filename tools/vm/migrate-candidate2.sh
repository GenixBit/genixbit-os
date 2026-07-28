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
# Format: label|vm_id|pid_file|qmp_socket|serial_log|original_pid
declare -a MIG_VM_REGISTRY=()

mig_register_vm() {
    local label="$1"
    local vm_id="$2"
    local pid_file="$3"
    local qmp_socket="$4"
    local serial_log="$5"
    local original_pid=""
    if [[ -f "$pid_file" ]]; then
        original_pid=$(cat "$pid_file" 2>/dev/null || echo "")
    fi
    MIG_VM_REGISTRY+=("$label|$vm_id|$pid_file|$qmp_socket|$serial_log|$original_pid")
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
        IFS='|' read -r label vm_id pid_file qmp_socket serial_log original_pid <<< "$entry"
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
        # Verify original PID directly, not inferred from PID file
        if [[ -n "$original_pid" ]] && kill -0 "$original_pid" 2>/dev/null; then
            printf '[FAIL] Migration VM %s original PID %s still alive after cleanup\n' "$label" "$original_pid" >&2
            rc=1
        fi
        # Preserve and validate lifecycle evidence
        local vm_state_file="${state_dir}/vm-${vm_id}.json"
        local shutdown_file="${state_dir}/shutdown-${vm_id}.json"
        if [[ -f "$vm_state_file" ]]; then
            cp -f "$vm_state_file" "$RUNTIME_EVIDENCE_DIR/migration-${label}-vm-state.json" 2>/dev/null || true
            # Validate VM state is not running
            local vm_state
            vm_state=$(python3 -c "import json; d=json.load(open('$vm_state_file')); print(d.get('state',''))" 2>/dev/null || echo "")
            if [[ "$vm_state" == "running" ]]; then
                printf '[FAIL] Migration VM %s final state is still running\n' "$label" >&2
                rc=1
            fi
        else
            printf '[FAIL] Migration VM %s state file missing: %s\n' "$label" "$vm_state_file" >&2
            rc=1
        fi
        if [[ -f "$shutdown_file" ]]; then
            cp -f "$shutdown_file" "$RUNTIME_EVIDENCE_DIR/migration-${label}-shutdown.json" 2>/dev/null || true
            # Validate shutdown result
            local shut_status shut_state proc_alive qmp_present
            shut_status=$(python3 -c "import json; d=json.load(open('$shutdown_file')); print(d.get('status',''))" 2>/dev/null || echo "")
            shut_state=$(python3 -c "import json; d=json.load(open('$shutdown_file')); print(d.get('shutdown_state',''))" 2>/dev/null || echo "")
            proc_alive=$(python3 -c "import json; d=json.load(open('$shutdown_file')); print(str(d.get('process_alive_after_stop',True)).lower())" 2>/dev/null || echo "true")
            qmp_present=$(python3 -c "import json; d=json.load(open('$shutdown_file')); print(str(d.get('qmp_socket_present_after_stop',True)).lower())" 2>/dev/null || echo "true")
            if [[ "$shut_status" != "PASS" ]]; then
                printf '[FAIL] Migration VM %s shutdown status is %s (expected PASS)\n' "$label" "$shut_status" >&2
                rc=1
            fi
            if [[ "$shut_state" != "NATURAL_EXIT" && "$shut_state" != "ALREADY_STOPPED_VERIFIED" ]]; then
                printf '[FAIL] Migration VM %s shutdown state is %s (expected NATURAL_EXIT or ALREADY_STOPPED_VERIFIED)\n' "$label" "$shut_state" >&2
                rc=1
            fi
            if [[ "$proc_alive" == "true" ]]; then
                printf '[FAIL] Migration VM %s process still alive after stop\n' "$label" >&2
                rc=1
            fi
            if [[ "$qmp_present" == "true" ]]; then
                printf '[FAIL] Migration VM %s QMP socket still present after stop\n' "$label" >&2
                rc=1
            fi
        else
            printf '[FAIL] Migration VM %s shutdown file missing: %s\n' "$label" "$shutdown_file" >&2
            rc=1
        fi
    done
    return "$rc"
}

mig_cleanup_trap() {
    local original_exit=$?
    trap - EXIT
    set +e
    mig_cleanup_all_vms
    local cleanup_rc=$?
    set -e
    if (( original_exit != 0 )); then
        exit "$original_exit"
    fi
    exit "$cleanup_rc"
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
set +e
OBS_DPKG_AUDIT_RAW=$(ssh_guest "$MIG_PORT" "$SSH_USER" "$SSH_KEY" \
    "sudo dpkg --audit 2>&1" 2>/dev/null)
OBS_POST_DPKG_AUDIT_EXIT=$?
set -e
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
exec_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write large values to temp files for safe Python consumption
OBS_PRE_MIG_PKGS_FILE="$state_dir/obs_pre_migration_packages.txt"
OBS_APT_CACHE_FILE="$state_dir/obs_apt_cache_policy.txt"
OBS_DPKG_QUERY_FILE="$state_dir/obs_post_dpkg_query.txt"
OBS_BOOT_OS_FILE="$state_dir/obs_post_boot_os.txt"
OBS_ROLLBACK_DPKG_FILE="$state_dir/obs_rollback_dpkg.txt"
OBS_REUPGRADE_DPKG_FILE="$state_dir/obs_reupgrade_dpkg.txt"
OBS_FINAL_OS_FILE="$state_dir/obs_final_os.txt"

printf '%s' "$OBS_PRE_MIGRATION_PACKAGES" > "$OBS_PRE_MIG_PKGS_FILE"
printf '%s' "$OBS_APT_CACHE_POLICY" > "$OBS_APT_CACHE_FILE"
printf '%s' "$OBS_POST_DPKG_QUERY" > "$OBS_DPKG_QUERY_FILE"
printf '%s' "$OBS_POST_BOOT_OS_RELEASE" > "$OBS_BOOT_OS_FILE"
printf '%s' "$OBS_ROLLBACK_DPKG_QUERY" > "$OBS_ROLLBACK_DPKG_FILE"
printf '%s' "$OBS_REUPGRADE_DPKG_QUERY" > "$OBS_REUPGRADE_DPKG_FILE"
printf '%s' "$OBS_FINAL_OS_RELEASE" > "$OBS_FINAL_OS_FILE"

# Compute lifecycle evidence hashes safely in shell
premig_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-premig-vm-state.json" 2>/dev/null | awk '{print $1}' || echo "")
premig_shut_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-premig-shutdown.json" 2>/dev/null | awk '{print $1}' || echo "")
mig_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-mig-vm-state.json" 2>/dev/null | awk '{print $1}' || echo "")
mig_shut_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-mig-shutdown.json" 2>/dev/null | awk '{print $1}' || echo "")
rb_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-rollback-vm-state.json" 2>/dev/null | awk '{print $1}' || echo "")
rb_shut_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-rollback-shutdown.json" 2>/dev/null | awk '{print $1}' || echo "")
ru_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-reupgrade-vm-state.json" 2>/dev/null | awk '{print $1}' || echo "")
ru_shut_hash=$(sha256sum "$RUNTIME_EVIDENCE_DIR/migration-reupgrade-shutdown.json" 2>/dev/null | awk '{print $1}' || echo "")

GENIXBIT_MIG_RESULT_JSON="$out_json" \
OBS_PRE_MIG_PKGS_FILE="$OBS_PRE_MIG_PKGS_FILE" \
OBS_APT_CACHE_FILE="$OBS_APT_CACHE_FILE" \
OBS_DPKG_QUERY_FILE="$OBS_DPKG_QUERY_FILE" \
OBS_BOOT_OS_FILE="$OBS_BOOT_OS_FILE" \
OBS_ROLLBACK_DPKG_FILE="$OBS_ROLLBACK_DPKG_FILE" \
OBS_REUPGRADE_DPKG_FILE="$OBS_REUPGRADE_DPKG_FILE" \
OBS_FINAL_OS_FILE="$OBS_FINAL_OS_FILE" \
INSTALLATION_STATE_PATH="$INSTALLATION_STATE_JSON" \
MV_ID="$VM_ID" \
MV_RUN_ID="$RUN_ID" \
MV_DISK_PATH="$DISK_PATH" \
MV_MODE="$MODE" \
MV_SSH_USER="$SSH_USER" \
MV_STAGING_URL="$STAGING_URL" \
MV_OBSERVED_FINGERPRINT="$OBSERVED_FINGERPRINT" \
MV_STAGING_FINGERPRINT="$STAGING_FINGERPRINT" \
MV_OBS_STAGING_FINGERPRINT_MATCH="$OBS_STAGING_FINGERPRINT_MATCH" \
MV_OBS_ALL_PKG_ORIGINS="$OBS_ALL_PACKAGE_ORIGINS_VERIFIED" \
MV_PRE_STATE_SHA256="$PRE_STATE_SHA256" \
MV_APT_UPDATE_EXIT="$OBS_APT_UPDATE_EXIT" \
MV_APT_INSTALL_EXIT="$OBS_APT_INSTALL_EXIT" \
MV_APT_CHECK_EXIT="$OBS_POST_APT_CHECK_EXIT" \
MV_DPKG_AUDIT_EXIT="$OBS_POST_DPKG_AUDIT_EXIT" \
MV_DPKG_AUDIT_EMPTY="$OBS_POST_DPKG_AUDIT_EMPTY" \
MV_ROLLBACK_STATE_SHA256="$ROLLBACK_STATE_SHA256" \
MV_ROLLBACK_STATE_EQUALITY="$OBS_ROLLBACK_STATE_EQUALITY" \
MV_EXEC_TIMESTAMP="$exec_timestamp" \
MV_RUNTIME_EVIDENCE_DIR="$RUNTIME_EVIDENCE_DIR" \
MV_MIG_LOG="$MIG_LOG" \
MV_POST_MIG_LOG="$POST_MIG_LOG" \
MV_ROLLBACK_LOG="$ROLLBACK_LOG" \
MV_REUPGRADE_LOG="$REUPGRADE_LOG" \
MV_REUPGRADE_GUEST_LOG="$REUPGRADE_GUEST_LOG" \
MV_PREMIG_HASH="$premig_hash" \
MV_PREMIG_SHUT_HASH="$premig_shut_hash" \
MV_MIG_HASH="$mig_hash" \
MV_MIG_SHUT_HASH="$mig_shut_hash" \
MV_RB_HASH="$rb_hash" \
MV_RB_SHUT_HASH="$rb_shut_hash" \
MV_RU_HASH="$ru_hash" \
MV_RU_SHUT_HASH="$ru_shut_hash" \
MV_SOURCE_COMMIT="$MIG_SOURCE_COMMIT" \
MV_WORKFLOW_RUN_ID="$MIG_WORKFLOW_RUN_ID" \
MV_INSTALLATION_STATE_SHA256="$INSTALLATION_STATE_SHA256" \
MV_SOURCE_ISO_SHA256="$INSTALL_SOURCE_ISO_SHA256" \
MV_SOURCE_ISO_SHA512="$INSTALL_SOURCE_ISO_SHA512" \
MV_INSTALL_INSTALLER_VM_ID="$INSTALL_INSTALLER_VM_ID" \
MV_INSTALL_INSTALLED_VM_ID="$INSTALL_INSTALLED_VM_ID" \
MV_INSTALL_WORKFLOW_RUN_ID="$INSTALL_WORKFLOW_RUN_ID" \
python3 - <<'PYEOF'
import json
import os

def read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except (OSError, IOError):
        return ""

result = {
    "installation_state_path": os.environ["INSTALLATION_STATE_PATH"],
    "vm_id": os.environ["MV_ID"],
    "run_id": os.environ["MV_RUN_ID"],
    "disk_identity": os.environ["MV_DISK_PATH"],
    "firmware_mode": os.environ["MV_MODE"],
    "ssh_username": os.environ["MV_SSH_USER"],
    "staging_url": os.environ["MV_STAGING_URL"],
    "observed_staging_fingerprint": os.environ["MV_OBSERVED_FINGERPRINT"],
    "expected_staging_fingerprint": os.environ["MV_STAGING_FINGERPRINT"],
    "staging_key_fingerprint_match": os.environ["MV_OBS_STAGING_FINGERPRINT_MATCH"],
    "all_package_origins_verified": os.environ["MV_OBS_ALL_PKG_ORIGINS"],
    "pre_migration_package_state": read_file(os.environ["OBS_PRE_MIG_PKGS_FILE"]),
    "pre_migration_state_sha256": os.environ["MV_PRE_STATE_SHA256"],
    "apt_update_exit_code": os.environ["MV_APT_UPDATE_EXIT"],
    "apt_cache_policy_output": read_file(os.environ["OBS_APT_CACHE_FILE"]),
    "apt_install_exit_code": os.environ["MV_APT_INSTALL_EXIT"],
    "post_install_dpkg_query": read_file(os.environ["OBS_DPKG_QUERY_FILE"]),
    "apt_check_exit_code": os.environ["MV_APT_CHECK_EXIT"],
    "dpkg_audit_exit_code": os.environ["MV_DPKG_AUDIT_EXIT"],
    "dpkg_audit_output_empty": os.environ["MV_DPKG_AUDIT_EMPTY"],
    "post_migration_boot_os_release": read_file(os.environ["OBS_BOOT_OS_FILE"]),
    "rollback_dpkg_query": read_file(os.environ["OBS_ROLLBACK_DPKG_FILE"]),
    "rollback_state_sha256": os.environ["MV_ROLLBACK_STATE_SHA256"],
    "rollback_package_state_matches_pre_migration": os.environ["MV_ROLLBACK_STATE_EQUALITY"],
    "reupgrade_dpkg_query": read_file(os.environ["OBS_REUPGRADE_DPKG_FILE"]),
    "final_os_release": read_file(os.environ["OBS_FINAL_OS_FILE"]),
    "stdout_paths": [
        os.environ["MV_MIG_LOG"],
        os.environ["MV_POST_MIG_LOG"],
        os.environ["MV_ROLLBACK_LOG"],
        os.environ["MV_REUPGRADE_LOG"],
        os.environ["MV_REUPGRADE_GUEST_LOG"],
    ],
    "execution_timestamp": os.environ["MV_EXEC_TIMESTAMP"],
    "lifecycle_evidence": [
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-premig-vm-state.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-premig-shutdown.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-mig-vm-state.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-mig-shutdown.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-rollback-vm-state.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-rollback-shutdown.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-reupgrade-vm-state.json"),
        os.path.join(os.environ["MV_RUNTIME_EVIDENCE_DIR"], "migration-reupgrade-shutdown.json"),
    ],
    "lifecycle_evidence_sha256": {
        "premig": os.environ["MV_PREMIG_HASH"],
        "premig_shutdown": os.environ["MV_PREMIG_SHUT_HASH"],
        "mig": os.environ["MV_MIG_HASH"],
        "mig_shutdown": os.environ["MV_MIG_SHUT_HASH"],
        "rollback": os.environ["MV_RB_HASH"],
        "rollback_shutdown": os.environ["MV_RB_SHUT_HASH"],
        "reupgrade": os.environ["MV_RU_HASH"],
        "reupgrade_shutdown": os.environ["MV_RU_SHUT_HASH"],
    },
    "source_commit": os.environ["MV_SOURCE_COMMIT"],
    "workflow_run_id": os.environ["MV_WORKFLOW_RUN_ID"],
    "installation_state_sha256": os.environ["MV_INSTALLATION_STATE_SHA256"],
    "source_iso_sha256": os.environ["MV_SOURCE_ISO_SHA256"],
    "source_iso_sha512": os.environ["MV_SOURCE_ISO_SHA512"],
    "installation_installer_vm_id": os.environ["MV_INSTALL_INSTALLER_VM_ID"],
    "installation_installed_vm_id": os.environ["MV_INSTALL_INSTALLED_VM_ID"],
    "installation_workflow_run_id": os.environ["MV_INSTALL_WORKFLOW_RUN_ID"],
    "migration_vm_id": os.environ["MV_ID"],
}

all_pass = (
    result["apt_install_exit_code"] == "0" and
    result["apt_check_exit_code"] == "0" and
    result["dpkg_audit_exit_code"] == "0" and
    result["dpkg_audit_output_empty"] == "true" and
    result["staging_key_fingerprint_match"] == "true" and
    result["all_package_origins_verified"] == "true" and
    result["rollback_package_state_matches_pre_migration"] == "true" and
    result["apt_update_exit_code"] == "0" and
    result["pre_migration_state_sha256"] != "" and
    result["rollback_state_sha256"] != "" and
    result["pre_migration_state_sha256"] == result["rollback_state_sha256"] and
    result["post_migration_boot_os_release"] not in ("", "unavailable") and
    result["post_install_dpkg_query"] not in ("", "unavailable") and
    result["rollback_dpkg_query"] not in ("", "unavailable") and
    result["reupgrade_dpkg_query"] not in ("", "unavailable") and
    result["final_os_release"] not in ("", "unavailable") and
    result["observed_staging_fingerprint"] != "" and
    result["vm_id"] != "" and
    result["source_commit"] != "" and
    result["workflow_run_id"] != "" and
    result["installation_state_sha256"] != "" and
    result["source_iso_sha256"] != "" and
    result["migration_vm_id"] != "" and
    all(result.get("lifecycle_evidence_sha256", {}).get(k, "") != ""
        for k in ("premig", "premig_shutdown", "mig", "mig_shutdown",
                  "rollback", "rollback_shutdown", "reupgrade", "reupgrade_shutdown"))
)
result["migration_status"] = "PASS" if all_pass else "FAIL"
result["final_status"] = "PASS" if all_pass else "FAIL"
with open(os.environ["GENIXBIT_MIG_RESULT_JSON"], "w") as f:
    json.dump(result, f, indent=2)
print(result["final_status"])
PYEOF

FINAL_STATUS=$(python3 -c "import json; d=json.load(open('$out_json')); print(d.get('final_status','FAIL'))")
[[ "$FINAL_STATUS" == "PASS" ]] || fail "Migration result final_status is '$FINAL_STATUS' — gate fails."

printf 'GENIXBIT_MIGRATION_RESULT=%s\n' "$out_json"
printf '[PASS] Candidate 2 real APT migration, rollback, and re-upgrade verified and recorded in %s for %s mode: %s\n' \
    "$out_json" "$MODE" "$DISK_PATH"
exit 0
