#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Negative unit test suite for Evidence Collector integrity

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

info "=== Running Negative Unit Tests for Evidence Collector ==="

TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

STAGE_LOGS_DIR="$REPO_ROOT/infra/package-staging/results/stage-logs"
mkdir -p "$STAGE_LOGS_DIR"
ACTIVE_CANDIDATE2_SHA="09a00e22c73d91ce0bf6f1e8558dbc80a7f9061ca6b36edc434281c761aeb204"
ACTIVE_PROVENANCE="$TEST_DIR/active-candidate2-provenance.json"
printf '{"verification_status":"PASS","usable_as_migration_source":true,"sha256":"%s"}\n' "$ACTIVE_CANDIDATE2_SHA" > "$ACTIVE_PROVENANCE"

run_collector() {
    python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" --candidate2-provenance-file "$ACTIVE_PROVENANCE" "$@"
}

# Helper to create valid stage logs in TEST_DIR
setup_valid_logs() {
    rm -rf "$TEST_DIR"/*
    mkdir -p "$TEST_DIR/stage-logs" "$TEST_DIR/current" "$TEST_DIR/debs"
    
    cat <<EOF > "$TEST_DIR/stage-logs/stage-package-build.json"
{"command": "build", "exit_code": 0, "status": "PASS"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-repository-publication.json"
{"command": "pub", "exit_code": 0, "status": "PASS"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-clean-install.json"
{"command": "apt-get update && apt-get install -y genixbit-os-desktop && apt-get check", "exit_code": 0, "status": "PASS", "environment_id": "Disposable Ubuntu client", "observations": {"captured_apt_output": "Reading package lists... Done\nGet:1 http://127.0.0.1 resolute-alpha main"}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-candidate-upgrade.json"
{"command": "upgrade", "exit_code": 0, "status": "PASS", "observations": {"candidate2_iso_sha256": "$ACTIVE_CANDIDATE2_SHA"}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-tamper.json"
{"command": "tamper", "exit_code": 0, "status": "PASS"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-rollback.json"
{"command": "rollback", "exit_code": 0, "status": "PASS"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-installer.json"
{"command": "installer", "exit_code": 0, "status": "PASS", "observations": {"slideshow_verified": true}}
EOF
    CURR_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
    cat <<EOF > "$TEST_DIR/stage-logs/stage-test-iso-build.json"
{"command": "iso", "exit_code": 0, "status": "PASS", "observations": {"source_commit": "$CURR_SHA", "iso_filename": "GenixBitOS-0.3.0-alpha-dev-internal.iso", "iso_size_bytes": 67108864, "iso_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-test-iso-boot.json"
{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}}
EOF

}

# Test 1: Fake hash rejection
info "Test 1: Testing rejection of fake_hash value..."
setup_valid_logs
echo '{"command": "build", "exit_code": 0, "status": "PASS", "hash": "fake_hash"}' > "$TEST_DIR/stage-logs/stage-package-build.json"
cp -r "$TEST_DIR/stage-logs"/* "$STAGE_LOGS_DIR/"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject fake_hash!"
fi
pass "Test 1 PASS: Fake hash correctly rejected."

# Test 2: Missing result file rejection
info "Test 2: Testing rejection of missing result stage file..."
setup_valid_logs
rm -f "$STAGE_LOGS_DIR/stage-tamper.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject missing stage file!"
fi
pass "Test 2 PASS: Missing stage file correctly rejected."

# Test 3: Placeholder fingerprint rejection
info "Test 3: Testing rejection of placeholder GPG fingerprint..."
setup_valid_logs
echo '{"command": "pub", "exit_code": 0, "status": "PASS", "fingerprint": "0000000000000000000000000000000000000000"}' > "$STAGE_LOGS_DIR/stage-repository-publication.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject placeholder fingerprint!"
fi
pass "Test 3 PASS: Placeholder fingerprint correctly rejected."

# Test 4: False PASS with failed exit code rejection
info "Test 4: Testing rejection of false PASS with non-zero exit code..."
setup_valid_logs
echo '{"command": "clean", "exit_code": 1, "status": "PASS"}' > "$STAGE_LOGS_DIR/stage-clean-install.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject non-zero exit code with PASS status!"
fi
pass "Test 4 PASS: False PASS with non-zero exit code correctly rejected."

# Test 5: Incorrect source commit rejection
info "Test 5: Testing rejection of incorrect source commit SHA..."
setup_valid_logs
echo '{"command": "iso", "exit_code": 0, "status": "PASS", "observations": {"source_commit": "1111111111111111111111111111111111111111"}}' > "$STAGE_LOGS_DIR/stage-test-iso-build.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject mismatched source commit SHA!"
fi
pass "Test 5 PASS: Incorrect source commit SHA correctly rejected."

# Test 6: Dry-run QEMU VM execution log rejection
info "Test 6: Testing rejection of dry-run QEMU execution log..."
setup_valid_logs
echo '{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "[COMMAND] qemu-system-x86_64 --mode uefi --dry-run"}}' > "$STAGE_LOGS_DIR/stage-test-iso-boot.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject dry-run QEMU VM log!"
fi
pass "Test 6 PASS: Dry-run QEMU VM execution log correctly rejected."

# Test 7: Synthetic echo-generated APT log rejection
info "Test 7: Testing rejection of synthetic echo-generated APT log..."
setup_valid_logs
echo '{"command": "install", "exit_code": 0, "status": "PASS", "observations": {"captured_apt_output": "0 upgraded, 7 newly installed, 0 to remove and 0 not upgraded."}}' > "$STAGE_LOGS_DIR/stage-clean-install.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject synthetic echo-generated APT log!"
fi
pass "Test 7 PASS: Synthetic echo-generated APT log correctly rejected."

# Test 8: Command containing || true rejection
info "Test 8: Testing rejection of command containing || true..."
setup_valid_logs
echo '{"command": "run-qemu.sh --mode uefi || true", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}}' > "$STAGE_LOGS_DIR/stage-test-iso-boot.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject command containing || true!"
fi
pass "Test 8 PASS: Command containing || true correctly rejected."

# Test 9: Candidate 2 ISO SHA mismatch rejection
info "Test 9: Testing rejection of mismatched Candidate 2 ISO SHA-256..."
setup_valid_logs
echo '{"command": "upgrade", "exit_code": 0, "status": "PASS", "observations": {"candidate2_iso_sha256": "0000000000000000000000000000000000000000000000000000000000000000"}}' > "$STAGE_LOGS_DIR/stage-candidate-upgrade.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject mismatched Candidate 2 ISO SHA!"
fi
pass "Test 9 PASS: Mismatched Candidate 2 ISO SHA correctly rejected."

# Test 10: APT dry-run / simulate flag rejection
info "Test 10: Testing rejection of apt-get install --dry-run command..."
setup_valid_logs
echo '{"command": "apt-get install -y --dry-run genixbit-os-desktop", "exit_code": 0, "status": "PASS", "observations": {"captured_apt_output": "Reading package lists..."}}' > "$STAGE_LOGS_DIR/stage-clean-install.json"
if run_collector 2>/dev/null; then
    fail "Collector failed to reject apt-get --dry-run command!"
fi
pass "Test 10 PASS: APT --dry-run flag in command string correctly rejected."

# Restore valid execution if a real ISO is present
ISO_FILE=$(find "$REPO_ROOT/dist" -maxdepth 1 -name "*.iso" 2>/dev/null | head -n 1 || echo "")
if [[ -n "$ISO_FILE" && -f "$ISO_FILE" ]]; then
    bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" >/dev/null
fi


pass "=== All Evidence Collector Negative Security Tests Passed ==="
exit 0
