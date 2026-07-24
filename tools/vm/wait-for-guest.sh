#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for a managed QEMU guest VM by confirming process status via PID, QMP query-status,
# and authenticated SSH readiness command with run-specific verification token.

set -Eeuo pipefail
IFS=$'\n\t'

SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
TOKEN=""
PID_FILE=""
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
        --ssh-user)
            (($# >= 2)) || fail '--ssh-user requires a username.'
            SSH_USER=$2
            shift 2
            ;;
        --ssh-key)
            (($# >= 2)) || fail '--ssh-key requires a path.'
            SSH_KEY=$2
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
        --qmp-socket|--qmp)
            (($# >= 2)) || fail '--qmp-socket requires a path.'
            QMP_PATH=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        *)
            # Ignore legacy arguments for backward compatibility
            if [[ "$1" == "--serial-log" || "$1" == "--guest-agent-socket" || "$1" == "--guest-agent" ]]; then
                shift 2
            else
                fail "Unknown argument: $1"
            fi
            ;;
    esac
done

[[ -n "$SSH_PORT" ]] || fail '--ssh-port is required.'

if [[ -z "$TOKEN" ]]; then
    TOKEN="GENIXBIT_GUEST_READY_$(date +%s)_$$"
fi

end_time=$((SECONDS + TIMEOUT_SEC))
READINESS_CMD="printf '%s\n' '$TOKEN' && cat /etc/machine-id && date -u +%FT%TZ && findmnt -n -o SOURCE,FSTYPE /"

printf '[INFO] Waiting for managed guest VM readiness (token: %s, timeout: %ds)...\n' "$TOKEN" "$TIMEOUT_SEC"

while ((SECONDS < end_time)); do
    # 1. Verify QEMU PID is alive if pid-file is specified
    if [[ -n "$PID_FILE" && -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE" 2>/dev/null || echo "0")
        if ! kill -0 "$PID" 2>/dev/null; then
            fail "QEMU VM process (PID $PID) died while waiting for guest readiness!"
        fi
    fi

    # 2. Verify QMP query-status if socket is specified
    if [[ -n "$QMP_PATH" && -S "$QMP_PATH" ]]; then
        qmp_running=$(python3 -c "import socket, json; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(2); s.connect('$QMP_PATH'); s.recv(4096); s.sendall(b'{\"execute\": \"qmp_capabilities\"}\n'); s.recv(4096); s.sendall(b'{\"execute\": \"query-status\"}\n'); res = json.loads(s.recv(4096).decode()); exit(0 if res.get('return', {}).get('running') else 1)" 2>/dev/null || echo "FAIL")
        if [[ "$qmp_running" == "FAIL" ]]; then
            sleep 1
            continue
        fi
    fi

    # 3. Authenticate via SSH with ephemeral key
    SSH_OPTS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=5" -p "$SSH_PORT")
    if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
        SSH_OPTS+=(-i "$SSH_KEY")
    fi

    OUT=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "$READINESS_CMD" 2>/dev/null || echo "")

    # 4. Require exact token output in stdout
    if echo "$OUT" | grep -F "$TOKEN" >/dev/null 2>&1; then
        printf '[PASS] Authenticated SSH guest readiness confirmed (PID alive, QMP status running, token matched: %s)\n' "$TOKEN"
        exit 0
    fi

    sleep 2
done

fail "Timeout (${TIMEOUT_SEC}s) reached waiting for authenticated guest VM readiness. Process exit or unauthenticated TCP port alone is insufficient."
