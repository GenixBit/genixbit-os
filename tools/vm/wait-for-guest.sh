#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for a QEMU guest VM to become ready by executing an authenticated readiness command
# and matching a run-specific verification token.

set -Eeuo pipefail
IFS=$'\n\t'

SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
QGA_SOCKET=""
TOKEN=""
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
        --guest-agent-socket|--guest-agent)
            (($# >= 2)) || fail '--guest-agent-socket requires a path.'
            QGA_SOCKET=$2
            shift 2
            ;;
        --token)
            (($# >= 2)) || fail '--token requires a string.'
            TOKEN=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        *)
            # Ignore legacy parameters like --qmp or --serial-log for backward compatibility
            if [[ "$1" == "--qmp" || "$1" == "--serial-log" ]]; then
                shift 2
            else
                fail "Unknown argument: $1"
            fi
            ;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    TOKEN="GENIXBIT_GUEST_READY_$(date +%s)_$$"
fi

end_time=$((SECONDS + TIMEOUT_SEC))
READINESS_CMD="printf 'GENIXBIT_GUEST_READY_%s\n' '$TOKEN' && cat /etc/machine-id 2>/dev/null || true"

printf '[INFO] Waiting for authenticated guest VM readiness (token: %s, timeout: %ds)...\n' "$TOKEN" "$TIMEOUT_SEC"

while ((SECONDS < end_time)); do
    # Method 1: Authenticated SSH readiness check
    if [[ -n "$SSH_PORT" ]]; then
        SSH_OPTS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=5" -p "$SSH_PORT")
        if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
            SSH_OPTS+=(-i "$SSH_KEY")
        fi

        OUT=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "$READINESS_CMD" 2>/dev/null || echo "")
        if echo "$OUT" | grep -F "GENIXBIT_GUEST_READY_$TOKEN" >/dev/null 2>&1; then
            printf '[PASS] Authenticated SSH guest readiness confirmed (token matched: %s)\n' "$TOKEN"
            exit 0
        fi
    fi

    # Method 2: Dedicated QEMU Guest Agent socket readiness check
    if [[ -n "$QGA_SOCKET" && -S "$QGA_SOCKET" ]]; then
        qga_ready=$(cat <<PYEOF
import socket, json, base64, sys

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect("${QGA_SOCKET}")
    s.sendall(b'{"execute": "guest-ping"}\n')
    res = json.loads(s.recv(4096).decode())
    if "error" in res:
        sys.exit(1)
    
    req = json.dumps({"execute": "guest-exec", "arguments": {"path": "/bin/bash", "arg": ["-c", "${READINESS_CMD}"], "capture-output": True}})
    s.sendall(req.encode() + b'\n')
    res = json.loads(s.recv(4096).decode())
    pid = res.get("return", {}).get("pid")
    if not pid:
        sys.exit(1)

    import time
    for _ in range(5):
        s.sendall(json.dumps({"execute": "guest-exec-status", "arguments": {"pid": pid}}).encode() + b'\n')
        status = json.loads(s.recv(4096).decode()).get("return", {})
        if status.get("exited", False):
            out = base64.b64decode(status.get("out-data", "")).decode()
            if "GENIXBIT_GUEST_READY_${TOKEN}" in out:
                sys.exit(0)
        time.sleep(0.5)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYEOF
)
        if python3 -c "$qga_ready" 2>/dev/null; then
            printf '[PASS] Authenticated QGA guest readiness confirmed (token matched: %s)\n' "$TOKEN"
            exit 0
        fi
    fi

    sleep 2
done

fail "Timeout (${TIMEOUT_SEC}s) reached waiting for authenticated guest VM readiness. QMP socket existence or unauthenticated TCP port is insufficient."
