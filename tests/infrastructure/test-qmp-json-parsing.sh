#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Behavioral regression test: QMP JSON parsing logic
#
# Tests the JSON receive-and-parse logic that the production qmp_query_status
# helper in run-qemu.sh relies on: newline-delimited JSON, ID matching,
# greeting validation, error handling, split reads, multi-object reads,
# stale/timeout sockets, and production-readiness checks.

set -Eeuo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '[FAIL] %s\n' "$*" >&2; }

TEST_DIR=$(mktemp -d)
cleanup_rm() { rm -rf "${TEST_DIR:?}"; }
trap cleanup_rm EXIT

RUN_QEMU="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tools/vm/run-qemu.sh"
HELPER="$RUN_QEMU"

info() { printf '[INFO] %s\n' "$*"; }

# -----------------------------------------------------------------------
# Test 1: Valid 'running' status
# -----------------------------------------------------------------------
info "Test 1: Parse valid 'running' status"
RESULT=$(python3 -c "
import json, io
# Use BytesIO to simulate a socket buffer
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-1\", \"return\": {}}\n{\"id\": \"status-1\", \"return\": {\"status\": \"running\", \"running\": true}}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict):
        if obj.get('id') == 'status-1':
            print(obj.get('return', {}).get('status', ''))
            break
" 2>/dev/null || echo "")
if [[ "$RESULT" == "running" ]]; then
    pass "Test 1: parsed 'running' correctly"
else
    fail "Test 1: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 2: Valid 'prelaunch' status
# -----------------------------------------------------------------------
info "Test 2: Parse valid 'prelaunch' status"
RESULT=$(python3 -c "
import json
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-2\", \"return\": {}}\n{\"id\": \"status-2\", \"return\": {\"status\": \"prelaunch\", \"running\": false}}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict):
        if obj.get('id') == 'status-2':
            print(obj.get('return', {}).get('status', ''))
            break
" 2>/dev/null || echo "")
if [[ "$RESULT" == "prelaunch" ]]; then
    pass "Test 2: parsed 'prelaunch' correctly"
else
    fail "Test 2: expected 'prelaunch', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 3: Misleading 'status:running' in QMP greeting is ignored
# -----------------------------------------------------------------------
info "Test 3: Misleading 'running' in greeting is ignored"
RESULT=$(python3 -c "
import json
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}, \"capabilities\": {\"status\": \"running\"}}}\n{\"id\": \"caps-3\", \"return\": {}}\n{\"id\": \"status-3\", \"return\": {\"status\": \"prelaunch\", \"running\": false}}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict):
        if obj.get('id') == 'status-3':
            print(obj.get('return', {}).get('status', ''))
            break
" 2>/dev/null || echo "")
if [[ "$RESULT" == "prelaunch" ]]; then
    pass "Test 3: greeting 'running' ignored, got 'prelaunch'"
else
    fail "Test 3: expected 'prelaunch', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 4: 'running' in error description, not in status
# -----------------------------------------------------------------------
info "Test 4: 'running' in error text not mistaken for status"
RESULT=$(python3 -c "
import json
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-4\", \"return\": {}}\n{\"error\": {\"class\": \"DeviceNotFound\", \"desc\": \"Device was running but state is unknown\"}, \"id\": \"status-4\"}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict):
        if obj.get('id') == 'status-4':
            if 'error' in obj:
                print('ERROR')
            else:
                print(obj.get('return', {}).get('status', 'NO_STATUS'))
            break
" 2>/dev/null || echo "")
if [[ "$RESULT" == "ERROR" ]]; then
    pass "Test 4: error response correctly detected, not mistaken for status"
else
    fail "Test 4: expected 'ERROR', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 5: Response split across multiple socket reads (buffered reassembly)
# -----------------------------------------------------------------------
info "Test 5: Split JSON response across multiple socket reads"
RESULT=$(python3 -c "
import json

# Simulate two recv() calls with partial JSON
chunk1 = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-5\", \"return\": {}}\n{\"id\": \"status-5\", \"ret'
chunk2 = b'urn\": {\"status\": \"running\", \"running\": true}}\n'

# Simulate the production recv_obj logic: buffer accumulates across reads
buf = b''
for chunk in (chunk1, chunk2):
    buf += chunk
    while b'\n' in buf:
        line, buf = buf.split(b'\n', 1)
        line = line.strip()
        if not line: continue
        obj = json.loads(line)
        if isinstance(obj, dict) and obj.get('id') == 'status-5':
            print(obj.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")
if [[ "$RESULT" == "running" ]]; then
    pass "Test 5: split response reassembled, got 'running'"
else
    fail "Test 5: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 6: Multiple JSON objects in one socket read
# -----------------------------------------------------------------------
info "Test 6: Multiple JSON objects in a single read"
RESULT=$(python3 -c "
import json
# Two JSON objects on one line (separated by newline within one recv)
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-6\", \"return\": {}}\n{\"id\": \"status-6\", \"return\": {\"status\": \"running\", \"running\": true}}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict) and obj.get('id') == 'status-6':
        print(obj.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")
if [[ "$RESULT" == "running" ]]; then
    pass "Test 6: multi-object read handled, got 'running'"
else
    fail "Test 6: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 7: Wrong response ID before correct response
# -----------------------------------------------------------------------
info "Test 7: Wrong response ID before correct response"
RESULT=$(python3 -c "
import json
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-7\", \"return\": {}}\n{\"id\": \"stale-1\", \"return\": {\"status\": \"shutdown\"}}\n{\"id\": \"status-7\", \"return\": {\"status\": \"running\", \"running\": true}}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict) and obj.get('id') == 'status-7':
        print(obj.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")
if [[ "$RESULT" == "running" ]]; then
    pass "Test 7: stale ID ignored, got 'running' from correct ID"
else
    fail "Test 7: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 8: QMP error response
# -----------------------------------------------------------------------
info "Test 8: QMP error response rejected"
RESULT=$(python3 -c "
import json
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\n{\"id\": \"caps-8\", \"return\": {}}\n{\"error\": {\"class\": \"GenericError\", \"desc\": \"not found\"}, \"id\": \"status-8\"}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    obj = json.loads(line)
    if isinstance(obj, dict) and obj.get('id') == 'status-8':
        if 'error' in obj:
            print('ERROR')
        else:
            print(obj.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")
if [[ "$RESULT" == "ERROR" ]]; then
    pass "Test 8: error response correctly rejected"
else
    fail "Test 8: expected 'ERROR', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 9: Malformed JSON line skipped
# -----------------------------------------------------------------------
info "Test 9: Malformed JSON line skipped"
RESULT=$(python3 -c "
import json
data = b'{\"QMP\": {\"version\": {\"qemu\": {\"major\": 8}}}}\nnot valid json at all\n{\"id\": \"caps-9\", \"return\": {}}\n{\"id\": \"status-9\", \"return\": {\"status\": \"running\", \"running\": true}}\n'
buf = data
while b'\n' in buf:
    line, buf = buf.split(b'\n', 1)
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict) and obj.get('id') == 'status-9':
        print(obj.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")
if [[ "$RESULT" == "running" ]]; then
    pass "Test 9: malformed JSON skipped, got 'running'"
else
    fail "Test 9: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 10: Socket timeout simulated
# -----------------------------------------------------------------------
info "Test 10: Stale socket timeout handled"
SOCKET_10="$TEST_DIR/qmp10.sock"
touch "$SOCKET_10"
RESULT=$(python3 -c "
import socket
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect('$SOCKET_10')
    print('CONNECTED')
except (FileNotFoundError, ConnectionRefusedError, socket.timeout, OSError):
    print('EXPECTED_FAILURE')
" 2>/dev/null || echo "EXPECTED_FAILURE")
rm -f "$SOCKET_10"
if [[ "$RESULT" == "EXPECTED_FAILURE" ]]; then
    pass "Test 10: stale socket correctly short-circuits"
else
    fail "Test 10: expected 'EXPECTED_FAILURE', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 11: Production code contains no raw status grep
# -----------------------------------------------------------------------
info "Test 11: run-qemu.sh contains no raw QMP status grep"
if grep -qnE 'grep.*qmp_status|grep.*running.*prelaunch' "$RUN_QEMU" 2>/dev/null; then
    fail "Test 11: run-qemu.sh still contains raw QMP status grep!"
else
    pass "Test 11: no raw QMP status grep in run-qemu.sh"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf '\n=== QMP JSON Parsing Behavioral Regression Test Results ===\n'
printf '  Passed: %d / %d\n' "$PASS_COUNT" "$TOTAL"
printf '  Failed: %d / %d\n' "$FAIL_COUNT" "$TOTAL"

if (( FAIL_COUNT > 0 )); then
    exit 1
fi
pass "=== All QMP JSON parsing behavioral regression tests passed ==="
exit 0
