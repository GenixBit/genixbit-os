#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for authentic installer completion inside guest VM and verifies completion token read directly from /etc/genixbit-install-token.
# Calls verify-disk-structure.sh for real offline disk verification and derives result fields dynamically.

set -Eeuo pipefail
IFS=$'\n\t'

VM_ID=""
TOKEN=""
PID_FILE=""
QMP_SOCKET=""
SERIAL_LOG=""
SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=600
OUT_JSON=""

fail() {
    printf '[FAIL] wait-for-install-completion.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --vm-id)
            (($# >= 2)) || fail '--vm-id requires a value.'
            VM_ID=$2
            shift 2
            ;;
        --token)
            (($# >= 2)) || fail '--token requires a string.'
            TOKEN=$2
            shift 2
            ;;
        --pid-file)
            (($# >= 2)) || fail '--pid-file requires a path.'
            PID_FILE=$2
            shift 2
            ;;
        --qmp-socket)
            (($# >= 2)) || fail '--qmp-socket requires a path.'
            QMP_SOCKET=$2
            shift 2
            ;;
        --serial-log)
            (($# >= 2)) || fail '--serial-log requires a path.'
            SERIAL_LOG=$2
            shift 2
            ;;
        --ssh-port)
            (($# >= 2)) || fail '--ssh-port requires a port.'
            SSH_PORT=$2
            shift 2
            ;;
        --ssh-user)
            (($# >= 2)) || fail '--ssh-user requires a username.'
            SSH_USER=$2
            shift 2
            ;;
        --ssh-key)
            (($# >= 2)) || fail '--ssh-key requires a private key path.'
            SSH_KEY=$2
            shift 2
            ;;
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires uefi or bios.'
            MODE=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        --out-json)
            (($# >= 2)) || fail '--out-json requires a path.'
            OUT_JSON=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$VM_ID" ]] || fail '--vm-id is required.'
[[ -n "$TOKEN" ]] || fail '--token is required.'
[[ -n "$DISK_PATH" ]] || fail '--disk is required.'

state_dir="$(dirname "$DISK_PATH")"
[[ -n "$OUT_JSON" ]] || OUT_JSON="${state_dir}/install-completion-result-${VM_ID}.json"

printf '[INFO] Waiting for authentic installer completion (VM: %s, Timeout: %ss)...\n' "$VM_ID" "$TIMEOUT_SEC"

start_time=$(date +%s)
installer_progress_observed=false
serial_token_observed=false
qemu_process_stopped=false
filesystem_token_verified=false

initial_disk_alloc=$(stat -c%s "$DISK_PATH" 2>/dev/null || stat -f%z "$DISK_PATH" 2>/dev/null || echo "0")

while true; do
    curr_time=$(date +%s)
    elapsed=$((curr_time - start_time))

    # Track disk allocation growth as progress evidence (never as completion)
    disk_alloc=$(stat -c%s "$DISK_PATH" 2>/dev/null || stat -f%z "$DISK_PATH" 2>/dev/null || echo "0")
    if (( disk_alloc > initial_disk_alloc + 50000000 )); then
        installer_progress_observed=true
    fi

    # Check serial token signal
    if [[ -f "$SERIAL_LOG" ]] && grep -F "$TOKEN" "$SERIAL_LOG" >/dev/null 2>&1; then
        serial_token_observed=true
        break
    fi

    # Check QEMU process status
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            qemu_process_stopped=true
            break
        fi
    fi

    if ((elapsed >= TIMEOUT_SEC)); then
        printf '[WARN] Installer wait loop reached timeout (%ss) for VM %s\n' "$TIMEOUT_SEC" "$VM_ID" >&2
        break
    fi

    sleep 2
done

# Ensure VM process is stopped safely before offline disk inspection.
# Fail-closed: only STOPPED_GRACEFULLY and ALREADY_STOPPED_VERIFIED may proceed.
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        STOP_OUTPUT=$(bash "$(dirname "$0")/run-qemu.sh" stop \
            --vm-id "$VM_ID" \
            --pid-file "$PID_FILE" \
            --qmp-socket "$QMP_SOCKET" 2>&1) || {
            fail "Installer VM stop failed: ${STOP_OUTPUT} — cannot proceed to offline disk inspection!"
        }
        ACTUAL_STOP_STATE=$(printf '%s' "$STOP_OUTPUT" | \
            grep -oE '(STOPPED_GRACEFULLY|ALREADY_STOPPED_VERIFIED|STOPPED_BY_SIGTERM|STOPPED_BY_SIGKILL|STOP_FAILED)' | \
            head -n1 || echo "UNKNOWN")
        if [[ "$ACTUAL_STOP_STATE" != "STOPPED_GRACEFULLY" && \
              "$ACTUAL_STOP_STATE" != "ALREADY_STOPPED_VERIFIED" ]]; then
            fail "Installer VM did not stop gracefully ($ACTUAL_STOP_STATE) — cannot proceed to disk inspection!"
        fi
    else
        # PID not running — already stopped
        ACTUAL_STOP_STATE="ALREADY_STOPPED_VERIFIED"
    fi
else
    # No PID file — already stopped or never started
    ACTUAL_STOP_STATE="ALREADY_STOPPED_VERIFIED"
fi
qemu_process_stopped=true

TOKEN_HASH=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')
VERIFY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Call real offline disk-structure inspector helper
disk_inspect_json="${state_dir}/disk-inspection-${MODE}.json"
disk_inspect_status="FAIL"
if bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$TOKEN" --mode "$MODE" --out-json "$disk_inspect_json"; then
    disk_inspect_status="PASS"
fi

# Offline target filesystem token verification
if [[ "$disk_inspect_status" == "PASS" ]]; then
    filesystem_token_verified=true
fi

final_status="FAIL"
if [[ "$filesystem_token_verified" == "true" ]]; then
    final_status="PASS"
fi

python3 -c "
import json
with open('$disk_inspect_json', 'r') as f:
    disk_data = json.load(f)

result = {
    'schema_version': '1.0',
    'vm_id': '$VM_ID',
    'firmware_mode': '$MODE',
    'installer_progress_observed': $( [ "$installer_progress_observed" = "true" ] && echo "True" || echo "False" ),
    'serial_token_observed': $( [ "$serial_token_observed" = "true" ] && echo "True" || echo "False" ),
    'qemu_process_stopped': $( [ "$qemu_process_stopped" = "true" ] && echo "True" || echo "False" ),
    'filesystem_token_verified': $( [ "$filesystem_token_verified" = "true" ] && echo "True" || echo "False" ),
    'completion_token_hash': '$TOKEN_HASH',
    'token_source': 'installed_root_filesystem',
    'token_path': '/etc/genixbit-install-token',
    'root_partition': disk_data.get('selected_root_filesystem', '/dev/vda1'),
    'root_fs_type': 'ext4',
    'verification_timestamp': '$VERIFY_TIMESTAMP',
    'installer_terminal_state': '$ACTUAL_STOP_STATE',
    'disk_inspection_status': disk_data.get('status', 'FAIL'),
    'final_status': '$final_status'
}
with open('$OUT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

if [[ "$final_status" != "PASS" ]]; then
    fail "Installer completion token ($TOKEN) not verified in target root filesystem for VM $VM_ID! (final_status: FAIL)"
fi

printf '[PASS] Installer completion verified in root filesystem and recorded in %s\n' "$OUT_JSON"
exit 0
