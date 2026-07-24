#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Dynamically allocates an unused localhost TCP port for QEMU SSH port forwarding without fallbacks.

set -Eeuo pipefail
IFS=$'\n\t'

fail() {
    printf '[FAIL] allocate-local-port.sh: %s\n' "$*" >&2
    exit 1
}

# Use python socket binding to get a free OS-assigned loopback port
PORT=$(python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()" 2>/dev/null || echo "")

if [[ -z "$PORT" || ! "$PORT" =~ ^[0-9]+$ || "$PORT" -le 1024 || "$PORT" -ge 65535 ]]; then
    fail "Failed to allocate free loopback TCP port in valid non-privileged range."
fi

# Verify port is currently free on 127.0.0.1
if (exec 3<"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    exec 3<&- 2>/dev/null || true
    fail "Allocated port $PORT is unexpectedly in use!"
fi

printf '%s\n' "$PORT"
exit 0
