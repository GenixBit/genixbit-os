#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Captures a screenshot from QMP socket into an output image file.

set -Eeuo pipefail
IFS=$'\n\t'

SOCKET_PATH=""
OUTPUT_PATH=""

fail() {
    printf '[FAIL] capture-screenshot.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --socket)
            (($# >= 2)) || fail '--socket requires a path.'
            SOCKET_PATH=$2
            shift 2
            ;;
        --output)
            (($# >= 2)) || fail '--output requires a path.'
            OUTPUT_PATH=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$SOCKET_PATH" ]] || fail '--socket is required.'
[[ -n "$OUTPUT_PATH" ]] || fail '--output is required.'

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ ! -S "$SOCKET_PATH" ]]; then
    fail "QMP socket does not exist or is not a socket: $SOCKET_PATH"
fi

if ! python3 - "$SOCKET_PATH" "$OUTPUT_PATH" <<'PYEOF'
import socket, json, sys, os

sock_path = sys.argv[1]
out_path = sys.argv[2]

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect(sock_path)
    s.recv(4096)
    s.sendall(b'{"execute": "qmp_capabilities"}\n')
    s.recv(4096)
    cmd = json.dumps({"execute": "screendump", "arguments": {"filename": out_path}})
    s.sendall(cmd.encode() + b'\n')
    res = json.loads(s.recv(4096).decode())
    s.close()
    if "error" in res:
        print(f"QMP screendump error: {res['error']}", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"Failed to capture screenshot via QMP: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
then
    fail "QMP screendump execution failed."
fi


if [[ ! -f "$OUTPUT_PATH" ]]; then
    fail "Screenshot output file was not created: $OUTPUT_PATH"
fi

file_size=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || stat -f %z "$OUTPUT_PATH" 2>/dev/null || wc -c < "$OUTPUT_PATH")
if (( file_size == 0 )); then
    fail "Screenshot output file is empty (0 bytes): $OUTPUT_PATH"
fi

printf '[PASS] Valid QMP screenshot captured (%d bytes): %s\n' "$file_size" "$OUTPUT_PATH"
exit 0
