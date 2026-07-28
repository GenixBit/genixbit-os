#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Behavioral regression test: QMP JSON parsing via production qmp-client.py
#
# Each test creates a fake QMP Unix socket server that simulates various
# QMP protocol scenarios and invokes the production qmp-client.py helper.

set -Eeuo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '[FAIL] %s\n' "$*" >&2; }

TEST_DIR=$(mktemp -d)
cleanup_rm() {
    rm -rf "${TEST_DIR:?}"
    # Clean up any leftover fake server processes
    pkill -f "qmp-fake-server.py" 2>/dev/null || true
}
trap cleanup_rm EXIT

REPO_TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QMP_CLIENT="$REPO_TOP/tools/vm/qmp-client.py"

info() { printf '[INFO] %s\n' "$*"; }

run_qmp() {
    local socket="$1"; shift
    # Wait for socket to appear
    for i in $(seq 1 20); do
        if [[ -S "$socket" ]]; then break; fi
        sleep 0.2
    done
    python3 "$QMP_CLIENT" --socket "$socket" --timeout 4 "$@" 2>&1 || true
}

# -----------------------------------------------------------------------
# Test 1: Valid 'running' status
# -----------------------------------------------------------------------
info "Test 1: Valid 'running' status"
S1="$TEST_DIR/q1.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" "$S1" "running" 2>/dev/null &
RESULT=$(run_qmp "$S1" query-status)
if [[ "$RESULT" == "running" ]]; then
    pass "Test 1: parsed 'running' correctly"
else
    fail "Test 1: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 2: Valid 'prelaunch' status
# -----------------------------------------------------------------------
info "Test 2: Valid 'prelaunch' status"
S2="$TEST_DIR/q2.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" "$S2" "prelaunch" 2>/dev/null &
RESULT=$(run_qmp "$S2" query-status)
if [[ "$RESULT" == "prelaunch" ]]; then
    pass "Test 2: parsed 'prelaunch' correctly"
else
    fail "Test 2: expected 'prelaunch', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 3: Greeting and responses in one socket write
# -----------------------------------------------------------------------
info "Test 3: Greeting and responses in one write"
S3="$TEST_DIR/q3.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --one-write "$S3" "running" 2>/dev/null &
RESULT=$(run_qmp "$S3" query-status)
if [[ "$RESULT" == "running" ]]; then
    pass "Test 3: greeting+responses in one write"
else
    fail "Test 3: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 4: Status response split across multiple writes
# -----------------------------------------------------------------------
info "Test 4: Status response split across multiple writes"
S4="$TEST_DIR/q4.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --split "$S4" "running" 2>/dev/null &
RESULT=$(run_qmp "$S4" query-status)
if [[ "$RESULT" == "running" ]]; then
    pass "Test 4: split response reassembled"
else
    fail "Test 4: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 5: Capabilities and status in the same read
# -----------------------------------------------------------------------
info "Test 5: Capabilities and status in same read"
S5="$TEST_DIR/q5.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --caps-together "$S5" "prelaunch" 2>/dev/null &
RESULT=$(run_qmp "$S5" query-status)
if [[ "$RESULT" == "prelaunch" ]]; then
    pass "Test 5: caps+status in same read"
else
    fail "Test 5: expected 'prelaunch', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 6: Async event before expected response
# -----------------------------------------------------------------------
info "Test 6: Async event before expected response"
S6="$TEST_DIR/q6.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --async-event "$S6" "running" 2>/dev/null &
RESULT=$(run_qmp "$S6" query-status)
if [[ "$RESULT" == "running" ]]; then
    pass "Test 6: async event ignored"
else
    fail "Test 6: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 7: Wrong response ID before correct
# -----------------------------------------------------------------------
info "Test 7: Wrong response ID before correct"
S7="$TEST_DIR/q7.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --wrong-id "$S7" "running" 2>/dev/null &
RESULT=$(run_qmp "$S7" query-status)
if [[ "$RESULT" == "running" ]]; then
    pass "Test 7: wrong ID ignored"
else
    fail "Test 7: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 8: Misleading 'running' in greeting metadata
# -----------------------------------------------------------------------
info "Test 8: Misleading 'running' in greeting metadata"
S8="$TEST_DIR/q8.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --misleading-greeting "$S8" "prelaunch" 2>/dev/null &
RESULT=$(run_qmp "$S8" query-status)
if [[ "$RESULT" == "prelaunch" ]]; then
    pass "Test 8: misleading greeting ignored"
else
    fail "Test 8: expected 'prelaunch', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 9: 'running' in error description
# -----------------------------------------------------------------------
info "Test 9: 'running' in error text not mistaken"
S9="$TEST_DIR/q9.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --error-desc "$S9" "running" 2>/dev/null &
RESULT=$(run_qmp "$S9" query-status)
if [[ -z "$RESULT" || "$RESULT" == *"Error"* || "$RESULT" == *"error"* ]]; then
    pass "Test 9: error response rejected"
else
    fail "Test 9: expected error, got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 10: QMP error response
# -----------------------------------------------------------------------
info "Test 10: QMP error response"
S10="$TEST_DIR/q10.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --error-response "$S10" 2>/dev/null &
RESULT=$(run_qmp "$S10" query-status)
if [[ -z "$RESULT" || "$RESULT" == *"Error"* || "$RESULT" == *"error"* ]]; then
    pass "Test 10: QMP error correctly rejected"
else
    fail "Test 10: expected error, got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 11: Malformed JSON then valid
# -----------------------------------------------------------------------
info "Test 11: Malformed JSON then valid response"
S11="$TEST_DIR/q11.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --malformed-json "$S11" "running" 2>/dev/null &
RESULT=$(run_qmp "$S11" query-status)
if [[ "$RESULT" == "running" ]]; then
    pass "Test 11: malformed JSON skipped"
else
    fail "Test 11: expected 'running', got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 12: Premature EOF
# -----------------------------------------------------------------------
info "Test 12: Premature EOF"
S12="$TEST_DIR/q12.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --premature-eof "$S12" 2>/dev/null &
RESULT=$(run_qmp "$S12" query-status)
if [[ -z "$RESULT" || "$RESULT" == *"Error"* || "$RESULT" == *"closed"* ]]; then
    pass "Test 12: premature EOF handled"
else
    fail "Test 12: expected failure on EOF, got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 13: Socket timeout
# -----------------------------------------------------------------------
info "Test 13: Socket timeout"
S13="$TEST_DIR/q13.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --timeout "$S13" 2>/dev/null &
RESULT=$(run_qmp "$S13" query-status)
if [[ -z "$RESULT" || "$RESULT" == *"timeout"* || "$RESULT" == *"Timeout"* ]]; then
    pass "Test 13: socket timeout handled"
else
    fail "Test 13: expected timeout, got '$RESULT'"
fi

# -----------------------------------------------------------------------
# Test 14: system-powerdown command
# -----------------------------------------------------------------------
info "Test 14: system-powerdown command"
S14="$TEST_DIR/q14.sock"
python3 "$REPO_TOP/tests/infrastructure/qmp-fake-server.py" --powerdown "$S14" 2>/dev/null &
RESULT=$(run_qmp "$S14" system-powerdown)
if [[ "$RESULT" == "OK" ]]; then
    pass "Test 14: system-powerdown verified"
else
    fail "Test 14: expected 'OK', got '$RESULT'"
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
