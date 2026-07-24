#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for a QEMU guest VM to become reachable and ready to receive commands.

set -Eeuo pipefail
IFS=$'\n\t'

SSH_PORT=""
SERIAL_LOG=""
QMP_PATH=""
TIMEOUT_SEC=300

fail() {
    printf '[FAIL] wait-for-guest.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --ssh-port)
            (($# >= 2)) || fail '--ssh-port requires a port number.'
            SSH_PORT=$2
            shift 2
            ;;
        --serial-log)
            (($# >= 2)) || fail '--serial-log requires a path.'
            SERIAL_LOG=$2
            shift 2
            ;;
        --qmp)
            (($# >= 2)) || fail '--qmp requires a path.'
            QMP_PATH=$2
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

end_time=$((SECONDS + TIMEOUT_SEC))

printf '[INFO] Waiting for guest VM readiness (timeout: %ds)...\n' "$TIMEOUT_SEC"

while ((SECONDS < end_time)); do
    # Check SSH port if provided
    if [[ -n "$SSH_PORT" ]]; then
        if nc -z 127.0.0.1 "$SSH_PORT" >/dev/null 2>&1 || (exec 3<"/dev/tcp/127.0.0.1/$SSH_PORT") 2>/dev/null; then
            exec 3<&- 2>/dev/null || true
            printf '[PASS] Guest SSH port %s is open and reachable.\n' "$SSH_PORT"
            exit 0
        fi
    fi

    # Check serial log for login prompt or boot completion milestone
    if [[ -n "$SERIAL_LOG" && -f "$SERIAL_LOG" ]]; then
        if grep -E "(login:|cloud-init.*finished|GenixBit OS|Reached target System Initialization|Welcome to GenixBit OS)" "$SERIAL_LOG" >/dev/null 2>&1; then
            printf '[PASS] Guest serial milestone detected in %s\n' "$SERIAL_LOG"
            exit 0
        fi
    fi

    # Check QMP socket readiness if provided
    if [[ -n "$QMP_PATH" && -S "$QMP_PATH" ]]; then
        printf '[PASS] Guest QMP socket %s is active.\n' "$QMP_PATH"
        exit 0
    fi

    sleep 2
done

fail "Timeout (${TIMEOUT_SEC}s) reached waiting for guest VM readiness."
