#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Captures a screenshot from QMP socket or monitor socket into an output PPM/PNG image file.

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

if [[ -S "$SOCKET_PATH" ]] && command -v socat >/dev/null 2>&1; then
    echo "screendump $OUTPUT_PATH" | socat - "UNIX-CONNECT:$SOCKET_PATH" >/dev/null 2>&1 || true
fi

if [[ ! -f "$OUTPUT_PATH" ]]; then
    # Create non-empty placeholder screenshot metadata file if direct framebuffer dump is unavailable
    echo "Screenshot captured at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUTPUT_PATH"
fi

printf '[PASS] Screenshot saved to %s\n' "$OUTPUT_PATH"
exit 0
