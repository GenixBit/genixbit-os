#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Negative unit test suite for Release Gate CI integrity and anti-fabrication enforcement.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

fail() {
    printf '[FAIL] Release Gate Negative Test Failed: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

info "=== Running Release Gate CI Integrity Negative Unit Tests ==="

TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Test 1: Reject vm_readiness marked PASS when Candidate 1 is retired
info "Test 1: Rejecting vm_readiness = PASS when candidate 1 is retired..."
DUMMY_GATE="$TMP_DIR/0.3.0-release-gate-dummy.json"
cat <<EOF > "$DUMMY_GATE"
{
  "gate_target": "Test Gate",
  "version": "0.3.0-alpha-dev",
  "categories": {
    "package_infrastructure": {"status": "PASS"},
    "vm_readiness": {"status": "PASS"}
  },
  "summary": {
    "pass_count": 2,
    "fail_count": 0,
    "blocked_count": 0,
    "not_tested_count": 0,
    "overall_gate_status": "PASS"
  }
}
EOF

if bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$DUMMY_GATE" >/dev/null 2>&1; then
    fail "check-release-gate.sh failed to reject vm_readiness = PASS when Candidate 1 is retired!"
fi
pass "Test 1 PASS: Falsified vm_readiness PASS correctly rejected."

# Test 2: Reject summary counter mismatch
info "Test 2: Rejecting release gate JSON with mismatched summary counters..."
cat <<EOF > "$DUMMY_GATE"
{
  "gate_target": "Test Gate",
  "version": "0.3.0-alpha-dev",
  "categories": {
    "package_infrastructure": {"status": "PASS"},
    "vm_readiness": {"status": "FAIL"}
  },
  "summary": {
    "pass_count": 2,
    "fail_count": 0,
    "blocked_count": 0,
    "not_tested_count": 0,
    "overall_gate_status": "FAIL"
  }
}
EOF

if bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$DUMMY_GATE" >/dev/null 2>&1; then
    fail "check-release-gate.sh failed to reject mismatched summary counters!"
fi
pass "Test 2 PASS: Mismatched summary counters correctly rejected."

# Test 3: Reject overall_gate_status = PASS when fail_count > 0
info "Test 3: Rejecting overall_gate_status = PASS when a gate is FAIL..."
cat <<EOF > "$DUMMY_GATE"
{
  "gate_target": "Test Gate",
  "version": "0.3.0-alpha-dev",
  "categories": {
    "package_infrastructure": {"status": "PASS"},
    "vm_readiness": {"status": "FAIL"}
  },
  "summary": {
    "pass_count": 1,
    "fail_count": 1,
    "blocked_count": 0,
    "not_tested_count": 0,
    "overall_gate_status": "PASS_STAGING_GATED"
  }
}
EOF

if bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$DUMMY_GATE" >/dev/null 2>&1; then
    fail "check-release-gate.sh failed to reject PASS overall status when fail_count > 0!"
fi
pass "Test 3 PASS: Falsified overall gate status correctly rejected."

pass "=== All Release Gate Negative Unit Tests Passed ==="
exit 0
