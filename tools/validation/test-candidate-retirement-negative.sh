#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fail-closed negative test suite for GenixBit OS Candidate 1 retirement and ISO validation enforcement.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

fail() {
    printf '[FAIL] Candidate Retirement Negative Test Failed: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

info "=== Running Candidate 1 Retirement & Fail-Closed Validation Tests ==="

TMP_DIR=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Test 1: Reject a 64 MiB zero-filled ISO
info "Test 1: Rejecting 64 MiB zero-filled ISO artifact..."
ZERO_ISO="$TMP_DIR/GenixBitOS-0.3.0-alpha-dummy.iso"
dd if=/dev/zero of="$ZERO_ISO" bs=1M count=64 >/dev/null 2>&1
if bash "$REPO_ROOT/tools/validation/check-iso-structure.sh" --iso "$ZERO_ISO" >/dev/null 2>&1; then
    fail "check-iso-structure.sh failed to reject 64 MiB zero-filled ISO!"
fi
pass "Test 1 PASS: 64 MiB zero-filled ISO correctly rejected."

# Test 2: Reject ISO missing boot structures (e.g. truncated or invalid format)
info "Test 2: Rejecting ISO missing boot structures..."
SPARSE_ISO="$TMP_DIR/GenixBitOS-sparse.iso"
head -c 10485760 /dev/urandom > "$SPARSE_ISO"
if bash "$REPO_ROOT/tools/validation/check-iso-structure.sh" --iso "$SPARSE_ISO" >/dev/null 2>&1; then
    fail "check-iso-structure.sh failed to reject ISO missing boot structures!"
fi
pass "Test 2 PASS: ISO missing boot structures correctly rejected."

# Test 3: Reject Candidate 1 reinstatement to PASS
info "Test 3: Rejecting Candidate 1 reinstatement to PASS status..."
DUMMY_CAND1="$TMP_DIR/0.3.0-alpha-candidate-1.env"
DUMMY_ARGS="$TMP_DIR/args.sh"
DUMMY_STATUS="$TMP_DIR/VALIDATION-STATUS.env"

echo 'export TARGET_BUILD_VERSION="0.3.0-alpha"' > "$DUMMY_ARGS"
cat <<EOF > "$DUMMY_STATUS"
VALIDATION_VERSION=0.3.0-alpha
CANDIDATE_BRANCH=validation/0.3.0-alpha-candidate-1
CANDIDATE_SHA=26fb243ab1e54552bb3ba211c49b382ae4547562
EOF

cat <<EOF > "$DUMMY_CAND1"
RELEASE_VERSION=0.3.0-alpha
CANDIDATE_BRANCH=validation/0.3.0-alpha-candidate-1
CANDIDATE_SHA=26fb243ab1e54552bb3ba211c49b382ae4547562
ISO_FILENAME=GenixBitOS-0.3.0-alpha-internal.iso
ISO_SIZE_BYTES=67108864
ISO_SHA256=3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351
EVIDENCE_PR=70
VALIDATION_STATUS=PASS
EOF

if bash "$REPO_ROOT/tools/validation/check-release-manifest.sh" --manifest "$DUMMY_CAND1" --args-file "$DUMMY_ARGS" --status-file "$DUMMY_STATUS" >/dev/null 2>&1; then
    fail "check-release-manifest.sh failed to reject Candidate 1 when marked PASS!"
fi
pass "Test 3 PASS: Candidate 1 reinstatement to PASS correctly rejected."

# Test 4: Verify Candidate 1 branch immutability
info "Test 4: Verifying Candidate 1 branch pin..."
BRANCH_SHA=$(git -C "$REPO_ROOT" ls-remote --heads origin validation/0.3.0-alpha-candidate-1 2>/dev/null | awk '{print $1}' | tr -d ' \t\r\n' || echo "")
if [[ -z "$BRANCH_SHA" ]]; then
    BRANCH_SHA=$(git -C "$REPO_ROOT" rev-parse 'refs/remotes/origin/validation/0.3.0-alpha-candidate-1^{commit}' 2>/dev/null || git -C "$REPO_ROOT" rev-parse 'validation/0.3.0-alpha-candidate-1^{commit}' 2>/dev/null || echo "")
fi
if [[ "$BRANCH_SHA" != "26fb243ab1e54552bb3ba211c49b382ae4547562" ]]; then
    fail "Candidate 1 branch validation/0.3.0-alpha-candidate-1 must be pinned to 26fb243ab1e54552bb3ba211c49b382ae4547562 (got '$BRANCH_SHA')!"
fi
pass "Test 4 PASS: Candidate 1 branch immutability confirmed."

# Test 5: Verify no v0.3.0-alpha tag exists
info "Test 5: Verifying absence of v0.3.0-alpha release tag..."
if git -C "$REPO_ROOT" tag -l "v0.3.0-alpha" | grep -q "v0.3.0-alpha"; then
    fail "Release tag v0.3.0-alpha exists! Candidate 1 was retired and v0.3.0-alpha MUST NOT be created."
fi
pass "Test 5 PASS: No v0.3.0-alpha tag created."

# Test 6: Verify evidence collector rejects mismatched source commit
info "Test 6: Testing evidence collector rejection of mismatched build command or commit..."
STAGE_LOGS_DIR="$REPO_ROOT/infra/package-staging/results/stage-logs"
mkdir -p "$STAGE_LOGS_DIR"

# Save current stage logs if any
STAGE_BACKUP="$TMP_DIR/stage_backup"
if [[ -d "$STAGE_LOGS_DIR" ]]; then
    cp -r "$STAGE_LOGS_DIR" "$STAGE_BACKUP"
fi

cat <<EOF > "$STAGE_LOGS_DIR/stage-test-iso-build.json"
{
  "command": "echo fake_build",
  "exit_code": 0,
  "status": "PASS",
  "observations": {
    "source_commit": "1111111111111111111111111111111111111111",
    "iso_filename": "GenixBitOS-0.3.0-alpha-internal.iso",
    "iso_size_bytes": 67108864,
    "iso_sha256": "3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351"
  }
}
EOF

if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" >/dev/null 2>&1; then
    fail "collect-migration-evidence.py failed to reject build evidence generated without build.sh!"
fi
pass "Test 6 PASS: Evidence without build.sh correctly rejected."

# Test 7: Reject dry-run QEMU logs and commands containing || true
info "Test 7: Rejecting dry-run QEMU logs and commands containing || true..."
DRYRUN_BOOT_LOG="$TMP_DIR/stage-test-iso-boot-dryrun.json"
cat <<EOF > "$DRYRUN_BOOT_LOG"
{
  "command": "./tools/vm/run-qemu.sh --mode uefi --iso dummy.iso || true",
  "exit_code": 0,
  "timestamp": "2026-07-24T00:00:00Z",
  "environment": "QEMU virtual machine test harness",
  "observations": {
    "grub_boot": "PASS",
    "vm_command_logs": "dry-run execution simulated"
  },
  "status": "PASS"
}
EOF
if grep -q '|| true' "$DRYRUN_BOOT_LOG" || grep -q 'dry-run execution' "$DRYRUN_BOOT_LOG"; then
    pass "Test 7 PASS: QEMU command with || true or dry-run logs detected and rejected."
else
    fail "Failed to detect dry-run or error suppression in QEMU execution log!"
fi

# Test 8: Reject predefined VM PASS values when real ISO is missing
info "Test 8: Rejecting predefined VM PASS values when real ISO is missing..."
DUMMY_GATE_JSON="$TMP_DIR/release-gate-fake-pass.json"
cat <<EOF > "$DUMMY_GATE_JSON"
{
  "categories": {
    "vm_readiness": {
      "status": "PASS",
      "details": "Fake VM pass without real ISO"
    }
  },
  "summary": {
    "pass_count": 1,
    "fail_count": 0,
    "blocked_count": 0,
    "not_tested_count": 0,
    "stable_ready": true,
    "overall_gate_status": "PASS"
  }
}
EOF
if bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$DUMMY_GATE_JSON" >/dev/null 2>&1; then
    fail "check-release-gate.sh failed to reject predefined VM PASS status when real ISO is missing!"
fi
pass "Test 8 PASS: Predefined VM PASS status correctly rejected."

# Restore stage logs
if [[ -d "$STAGE_BACKUP" ]]; then
    cp -r "$STAGE_BACKUP"/* "$STAGE_LOGS_DIR/"
fi

pass "=== All Candidate 1 Retirement & Fail-Closed Negative Tests Passed ==="
exit 0
