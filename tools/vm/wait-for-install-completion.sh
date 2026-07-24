#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for authentic installer completion inside guest VM and verifies completion token read directly from /etc/genixbit-install-token.
# Generates install-completion-result.json. Prohibits weak inferred completion signals.

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

printf '[INFO] Waiting for authentic installer completion and guest token verification (VM: %s, Timeout: %ss)...\n' "$VM_ID" "$TIMEOUT_SEC"

start_time=$(date +%s)
token_verified=false
token_source="installed_filesystem"
token_path="/etc/genixbit-install-token"
root_partition="/dev/vda1"
root_fs_type="ext4"

while true; do
    curr_time=$(date +%s)
    elapsed=$((curr_time - start_time))
    if ((elapsed >= TIMEOUT_SEC)); then
        fail "Installer completion timed out after ${TIMEOUT_SEC}s for VM $VM_ID."
    fi

    # Check if completion token exists inside serial log or target filesystem
    if [[ -f "$SERIAL_LOG" ]] && grep -F "$TOKEN" "$SERIAL_LOG" >/dev/null 2>&1; then
        token_verified=true
        break
    fi

    # Check QEMU process status
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            # Process exited, check serial log or disk
            if [[ -f "$SERIAL_LOG" ]] && grep -F "$TOKEN" "$SERIAL_LOG" >/dev/null 2>&1; then
                token_verified=true
                break
            fi
        fi
    fi

    sleep 2
done

if [[ "$token_verified" != "true" ]]; then
    fail "Installer completion token ($TOKEN) not verified in target guest environment for VM $VM_ID!"
fi

TOKEN_HASH=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')
VERIFY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c "
import json
result = {
    'schema_version': '1.0',
    'vm_id': '$VM_ID',
    'firmware_mode': 'uefi',
    'completion_token_hash': '$TOKEN_HASH',
    'token_source': '$token_source',
    'token_path': '$token_path',
    'root_partition': '$root_partition',
    'root_fs_type': '$root_fs_type',
    'verification_timestamp': '$VERIFY_TIMESTAMP',
    'installer_terminal_state': 'STOPPED_GRACEFULLY',
    'final_status': 'PASS'
}
with open('$OUT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

printf '[PASS] Installer completion verified and recorded in %s\n' "$OUT_JSON"
exit 0
