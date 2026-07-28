#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Behavioral regression test: QMP JSON parsing via production qmp-client.py

set -Eeuo pipefail

PASS_COUNT=0
FAIL_COUNT=0
SERVER_PIDS=()

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '[FAIL] %s\n' "$*" >&2; }
info() { printf '[INFO] %s\n' "$*"; }

TEST_DIR=$(mktemp -d)
REPO_TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QMP_CLIENT="$REPO_TOP/tools/vm/qmp-client.py"
FAKE_SERVER="$REPO_TOP/tests/infrastructure/qmp-fake-server.py"

cleanup() {
    for pid in "${SERVER_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done

    rm -rf "${TEST_DIR:?}"
}
trap cleanup EXIT

start_server() {
    python3 "$FAKE_SERVER" "$@" 2>/dev/null &
    SERVER_PIDS+=("$!")
}

wait_sock() {
    local socket="$1"
    for _ in $(seq 1 50); do
        [[ -S "$socket" ]] && return 0
        sleep 0.1
    done
    return 1
}

run_qmp_capture() {
    local __out_var="$1"
    local __rc_var="$2"
    local socket="$3"
    shift 3

    wait_sock "$socket" || true
    local cmd_output=""
    local cmd_rc=0
    set +e
    cmd_output=$(python3 "$QMP_CLIENT" --socket "$socket" --timeout 4 "$@" 2>&1)
    cmd_rc=$?
    set -e
    printf -v "$__out_var" '%s' "$cmd_output"
    printf -v "$__rc_var" '%s' "$cmd_rc"
}

qmp_query_active_status_helper() {
    local socket_path="$1"

    python3 "$QMP_CLIENT" \
        --socket "$socket_path" \
        --timeout 5 \
        query-active-status
}

run_helper_capture() {
    local __out_var="$1"
    local __rc_var="$2"
    local socket="$3"

    wait_sock "$socket" || true
    local cmd_output=""
    local cmd_rc=0
    set +e
    cmd_output=$(qmp_query_active_status_helper "$socket" 2>&1)
    cmd_rc=$?
    set -e
    printf -v "$__out_var" '%s' "$cmd_output"
    printf -v "$__rc_var" '%s' "$cmd_rc"
}

expect_status() {
    local name="$1"
    local scenario="$2"
    local status="$3"
    local expected="$4"
    local socket="$TEST_DIR/${name}.sock"
    local result=""
    local rc=0

    info "$name: query-status expects $expected"
    start_server ${scenario:+--$scenario} "$socket" "$status"
    run_qmp_capture result rc "$socket" query-status
    if [[ "$rc" == "0" && "$result" == "$expected" ]]; then
        pass "$name: query-status returned $expected"
    else
        fail "$name: expected rc=0/$expected, got rc=$rc output='$result'"
    fi
}

expect_active_accept() {
    local status="$1"
    local socket="$TEST_DIR/active-${status}.sock"
    local result=""
    local rc=0

    info "Active readiness accepts $status"
    start_server "$socket" "$status"
    run_qmp_capture result rc "$socket" query-active-status
    if [[ "$rc" == "0" && "$result" == "$status" ]]; then
        pass "$status QMP status accepted"
    else
        fail "$status QMP status should be accepted, got rc=$rc output='$result'"
    fi
}

expect_active_reject() {
    local status="$1"
    local socket="$TEST_DIR/inactive-${status}.sock"
    local result=""
    local rc=0

    info "Active readiness rejects $status"
    start_server "$socket" "$status"
    run_qmp_capture result rc "$socket" query-active-status
    if [[ "$rc" != "0" && "$result" == *"not active"* ]]; then
        pass "$status QMP status rejected"
    else
        fail "$status QMP status should be rejected, got rc=$rc output='$result'"
    fi
}

expect_active_reject_raw() {
    local name="$1"
    local status="$2"
    local socket="$TEST_DIR/inactive-${name}.sock"
    local result=""
    local rc=0

    info "Active readiness rejects $name"
    start_server "$socket" "$status"
    run_qmp_capture result rc "$socket" query-active-status
    if [[ "$rc" != "0" ]]; then
        pass "$name QMP status rejected"
    else
        fail "$name QMP status should be rejected, got rc=$rc output='$result'"
    fi
}

expect_status "running-standard" "" "running" "running"
expect_status "prelaunch-standard" "" "prelaunch" "prelaunch"
expect_status "greeting-event-one-write" "one-write" "running" "running"
expect_status "status-split-two-writes" "split" "running" "running"
expect_status "caps-response-event-one-write" "caps-together" "prelaunch" "prelaunch"

info "Async event before expected response"
S_ASYNC="$TEST_DIR/async.sock"
start_server --async-event "$S_ASYNC" "running"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_ASYNC" query-status
if [[ "$RC" == "0" && "$RESULT" == "running" ]]; then
    pass "async event ignored"
else
    fail "expected running after async event, got rc=$RC output='$RESULT'"
fi

info "Wrong response ID plus correct response ID in one write"
S_WRONG="$TEST_DIR/wrong-id.sock"
start_server --wrong-id "$S_WRONG" "running"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_WRONG" query-status
if [[ "$RC" == "0" && "$RESULT" == "running" ]]; then
    pass "wrong response ID plus correct response ID in one write"
else
    fail "expected running after wrong ID, got rc=$RC output='$RESULT'"
fi

info "Misleading 'running' in greeting metadata"
S_MISLEAD="$TEST_DIR/misleading.sock"
start_server --misleading-greeting "$S_MISLEAD" "prelaunch"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_MISLEAD" query-status
if [[ "$RC" == "0" && "$RESULT" == "prelaunch" ]]; then
    pass "misleading greeting ignored"
else
    fail "expected prelaunch, got rc=$RC output='$RESULT'"
fi

info "QMP error response rejected"
S_ERR="$TEST_DIR/error.sock"
start_server --error-response "$S_ERR" "running"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_ERR" query-status
if [[ "$RC" != "0" && "$RESULT" == *"QMP query-status failed"* ]]; then
    pass "QMP error correctly rejected"
else
    fail "expected QMP error rejection, got rc=$RC output='$RESULT'"
fi

info "Malformed JSON then valid response"
S_MALFORMED="$TEST_DIR/malformed.sock"
start_server --malformed-json "$S_MALFORMED" "running"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_MALFORMED" query-status
if [[ "$RC" == "0" && "$RESULT" == "running" ]]; then
    pass "malformed JSON skipped"
else
    fail "expected running after malformed JSON, got rc=$RC output='$RESULT'"
fi

info "Premature EOF handled"
S_EOF="$TEST_DIR/eof.sock"
start_server --premature-eof "$S_EOF"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_EOF" query-status
if [[ "$RC" != "0" && "$RESULT" == *"closed"* ]]; then
    pass "premature EOF handled"
else
    fail "expected EOF failure, got rc=$RC output='$RESULT'"
fi

info "Socket timeout handled"
S_TIMEOUT="$TEST_DIR/timeout.sock"
start_server --timeout "$S_TIMEOUT"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_TIMEOUT" query-status
if [[ "$RC" != "0" && ( "$RESULT" == *"timeout"* || "$RESULT" == *"Timeout"* || "$RESULT" == *"timed out"* ) ]]; then
    pass "socket timeout handled"
else
    fail "expected timeout failure, got rc=$RC output='$RESULT'"
fi

info "system-powerdown command"
S_POWER="$TEST_DIR/power.sock"
start_server --powerdown "$S_POWER"
RESULT=""; RC=0
run_qmp_capture RESULT RC "$S_POWER" system-powerdown
if [[ "$RC" == "0" && "$RESULT" == "OK" ]]; then
    pass "system-powerdown verified"
else
    fail "expected OK, got rc=$RC output='$RESULT'"
fi

expect_active_accept "running"
expect_active_accept "prelaunch"
expect_active_reject "shutdown"
expect_active_reject "stop"
expect_active_reject "guest-panicked"
expect_active_reject "inmigrate"
expect_active_reject "postmigrate"
expect_active_reject_raw "colo" "colo"
expect_active_reject_raw "unknown" "unknown"
expect_active_reject_raw "empty" ""

info "Exact run-qemu active readiness helper accepts running"
S_HELPER="$TEST_DIR/helper.sock"
start_server "$S_HELPER" "running"
RESULT=""; RC=0
run_helper_capture RESULT RC "$S_HELPER"
if [[ "$RC" == "0" && "$RESULT" == "running" ]]; then
    pass "run-qemu readiness helper accepted running"
else
    fail "run-qemu readiness helper failed, rc=$RC output='$RESULT'"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf '\n=== QMP JSON Parsing Behavioral Regression Test Results ===\n'
printf '  Passed: %d / %d\n' "$PASS_COUNT" "$TOTAL"
printf '  Failed: %d / %d\n' "$FAIL_COUNT" "$TOTAL"

if (( FAIL_COUNT > 0 )); then
    exit 1
fi
pass "=== All QMP JSON parsing behavioral regression tests passed ==="
exit 0
