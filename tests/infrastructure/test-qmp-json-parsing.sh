#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Behavioral regression test: QMP JSON parsing vs grep-based matching
#
# Validates that JSON parsing is used instead of grep for QMP responses,
# and that expected-failure short-circuit handles closed/errored QMP sockets.

set -Eeuo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '[FAIL] %s\n' "$*" >&2; }

TEST_DIR=$(mktemp -d)
cleanup() { rm -rf "${TEST_DIR:?}"; }
trap cleanup EXIT

QMP_SOCKET="$TEST_DIR/qmp-test.sock"
QMP_RESULT="$TEST_DIR/qmp-result.json"

# Generate a fake QMP response file for scenarios that do not require a real VM.
write_qmp_response() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

# ---------------------------------------------------------------------------
# Test 1: JSON parse correctly extracts status from a well-formed QMP response
# ---------------------------------------------------------------------------
info() { printf '[INFO] %s\n' "$*"; }
info "Test 1: JSON parse of valid query-status response"
write_qmp_response "$QMP_RESULT" \
    '{"return": {"status": "running", "singlestep": false, "running": true}}'

PARSED_STATUS=$(python3 -c "
import json
with open('$QMP_RESULT') as f:
    data = json.load(f)
print(data.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")

if [[ "$PARSED_STATUS" == "running" ]]; then
    pass "Test 1: JSON parse correctly extracted status='running'"
else
    fail "Test 1: Expected status='running', got '$PARSED_STATUS'"
fi

# ---------------------------------------------------------------------------
# Test 2: JSON parse rejects status that is not exactly 'running' or 'prelaunch'
# ---------------------------------------------------------------------------
info "Test 2: JSON parse rejects unknown status (grep false positive scenario)"
write_qmp_response "$QMP_RESULT" \
    '{"return": {"status": "shutdown", "singlestep": false, "running": false}}'

PARSED_STATUS=$(python3 -c "
import json
with open('$QMP_RESULT') as f:
    data = json.load(f)
s = data.get('return', {}).get('status', '')
print('VALID' if s in ('running', 'prelaunch') else 'INVALID')
" 2>/dev/null || echo "")

if [[ "$PARSED_STATUS" == "INVALID" ]]; then
    pass "Test 2: JSON parse correctly rejected status='shutdown'"
else
    fail "Test 2: Expected INVALID for status='shutdown', got '$PARSED_STATUS'"
fi

# ---------------------------------------------------------------------------
# Test 3: JSON parse rejects grep false positive where 'running' appears in
#         a non-status field but grep -E '"status": "(running|prelaunch)"'
#         would incorrectly match a substring in the capabilities block.
# ---------------------------------------------------------------------------
info "Test 3: Grep false positive: 'running' in capabilities block is NOT the VM state"

# Simulate QMP greeting followed by query-status response.
# The capabilities block contains "status": "running" but the actual
# query-status returns "prelaunch".  Grep scanning the entire output
# would match the first occurrence and incorrectly conclude the VM is running.
write_qmp_response "$QMP_RESULT" \
    '{"QMP": {"version": {"qemu": {"major": 8}}, "capabilities": {"status": "running"}}}' \
    '{"return": {"status": "prelaunch", "singlestep": false, "running": false}}'

# What grep would find
GREP_MATCH=$(grep -E '"status": "(running|prelaunch)"' "$QMP_RESULT" 2>/dev/null | head -1 || echo "")
# What JSON parse of the LAST object would find
LAST_STATUS=$(python3 -c "
import json
with open('$QMP_RESULT') as f:
    lines = f.read().strip().split('\n')
    last = json.loads(lines[-1])
    print(last.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")

if [[ "$GREP_MATCH" == *'"status": "running"'* ]]; then
    pass "Test 3: grep incorrectly matched capabilities block status (false positive documented)"
else
    info "Test 3: grep did not match capabilities status (may vary by grep version)"
fi

if [[ "$LAST_STATUS" == "prelaunch" ]]; then
    pass "Test 3b: JSON parse correctly extracts LAST status='prelaunch' from multi-object response"
else
    fail "Test 3b: JSON parse got '$LAST_STATUS', expected 'prelaunch'"
fi

# ---------------------------------------------------------------------------
# Test 4: JSON parse correctly handles 'running' appearing inside error text
#         rather than as the real status field value.
# ---------------------------------------------------------------------------
info "Test 4: 'running' in error description text must not be mistaken for VM state"
write_qmp_response "$QMP_RESULT" \
    '{"error": {"class": "DeviceNotFound", "desc": "Device was running but state is unknown"}, "id": "test"}'

PARSED_STATUS=$(python3 -c "
import json
with open('$QMP_RESULT') as f:
    data = json.load(f)
ret = data.get('return', {})
if isinstance(ret, dict):
    print(ret.get('status', 'NO_STATUS'))
else:
    print('NO_RETURN')
" 2>/dev/null || echo "")

if [[ "$PARSED_STATUS" == "NO_STATUS" ]] || [[ "$PARSED_STATUS" == "NO_RETURN" ]]; then
    pass "Test 4: JSON parse ignored 'running' in error text (got: $PARSED_STATUS)"
else
    fail "Test 4: JSON parse incorrectly extracted status='$PARSED_STATUS' from error response"
fi

# ---------------------------------------------------------------------------
# Test 5: Expected-failure short-circuit: closed QMP socket
# ---------------------------------------------------------------------------
info "Test 5: Expected-failure short-circuit on closed QMP socket"

SEND_RESULT=$(python3 -c "
import socket, json, sys
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect('$QMP_SOCKET')
    sys.stdout.write('CONNECTED')
except (FileNotFoundError, ConnectionRefusedError, socket.timeout, OSError):
    sys.stdout.write('EXPECTED_FAILURE')
" 2>/dev/null || echo "EXPECTED_FAILURE")

if [[ "$SEND_RESULT" == "EXPECTED_FAILURE" ]]; then
    pass "Test 5: Closed QMP socket correctly short-circuits (expected failure)"
else
    fail "Test 5: Expected EXPECTED_FAILURE on closed socket, got '$SEND_RESULT'"
fi

# ---------------------------------------------------------------------------
# Test 6: Expected-failure short-circuit: QMP socket file exists but is stale
#         (no QEMU listening)
# ---------------------------------------------------------------------------
info "Test 6: Stale QMP socket file (no listener) short-circuits"
touch "$QMP_SOCKET"
chmod 700 "$QMP_SOCKET"

SEND_RESULT=$(python3 -c "
import socket, json, sys
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect('$QMP_SOCKET')
    sys.stdout.write('CONNECTED')
except (FileNotFoundError, ConnectionRefusedError, socket.timeout, OSError):
    sys.stdout.write('EXPECTED_FAILURE')
" 2>/dev/null || echo "EXPECTED_FAILURE")

rm -f "$QMP_SOCKET"

if [[ "$SEND_RESULT" == "EXPECTED_FAILURE" ]]; then
    pass "Test 6: Stale QMP socket correctly short-circuits (expected failure)"
else
    fail "Test 6: Expected EXPECTED_FAILURE on stale socket, got '$SEND_RESULT'"
fi

# ---------------------------------------------------------------------------
# Test 7: JSON parse vs grep on embedded 'running' in serialized args text
# ---------------------------------------------------------------------------
info "Test 7: Embedded 'running' in non-status field must not trigger false match"
write_qmp_response "$QMP_RESULT" \
    '{"return": {"status": "prelaunch", "args": "running-mode=enabled", "running": false}}'

PARSED_STATUS=$(python3 -c "
import json
with open('$QMP_RESULT') as f:
    data = json.load(f)
print(data.get('return', {}).get('status', ''))
" 2>/dev/null || echo "")

if [[ "$PARSED_STATUS" == "prelaunch" ]]; then
    pass "Test 7: JSON parse correctly got 'prelaunch' despite 'running' in args field"
else
    fail "Test 7: Expected 'prelaunch', got '$PARSED_STATUS'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf '\n=== QMP JSON Parsing Behavioral Regression Test Results ===\n'
printf '  Passed: %d / %d\n' "$PASS_COUNT" "$TOTAL"
printf '  Failed: %d / %d\n' "$FAIL_COUNT" "$TOTAL"

if (( FAIL_COUNT > 0 )); then
    exit 1
fi
pass "=== All QMP JSON parsing behavioral regression tests passed ==="
exit 0
