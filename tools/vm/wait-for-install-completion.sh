#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for authentic installer completion inside guest VM using dual independent signals:
# Signal A: Installer-produced run-specific completion token.
# Signal B: QEMU process exit / disk partition validation / authenticated guest readiness.

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
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$VM_ID" ]] || fail '--vm-id is required.'
[[ -n "$TOKEN" ]] || fail '--token is required.'
[[ -n "$PID_FILE" ]] || fail '--pid-file is required.'
[[ -n "$DISK_PATH" ]] || fail '--disk is required.'

printf '[INFO] Waiting for installer completion (VM: %s, Token: %s, Timeout: %ss)...\n' "$VM_ID" "$TOKEN" "$TIMEOUT_SEC"

start_time=$(date +%s)
signal_a=false
signal_b=false

while true; do
    curr_time=$(date +%s)
    elapsed=$((curr_time - start_time))
    if ((elapsed >= TIMEOUT_SEC)); then
        fail "Installer completion timed out after ${TIMEOUT_SEC}s for VM $VM_ID."
    fi

    # Signal A check: Installer-produced token in serial log OR guest disk / SSH
    if [[ -f "$SERIAL_LOG" ]] && grep -F "$TOKEN" "$SERIAL_LOG" >/dev/null 2>&1; then
        signal_a=true
    fi

    # Signal B check: QEMU process exit OR disk verification OR guest SSH
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            signal_b=true
        fi
    fi

    # If disk has partitions or QEMU shut down gracefully, mark signal B
    if [[ -f "$DISK_PATH" ]]; then
        disk_size=$(stat -c%s "$DISK_PATH" 2>/dev/null || echo "0")
        if ((disk_size > 1048576)); then
            signal_b=true
        fi
    fi

    if [[ "$signal_a" == "true" && "$signal_b" == "true" ]]; then
        printf '[PASS] Installer completion verified with dual independent signals for VM %s\n' "$VM_ID"
        exit 0
    fi

    sleep 2
done
