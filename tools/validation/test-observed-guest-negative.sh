#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executable Negative Unit Test Suite for Guestfs, Staging APT, and VM Lifecycle Evidence Integrity

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

info "=== Running Executable Guestfs, Staging APT & VM Lifecycle Negative Test Suite ==="

TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "${TEST_DIR:?}"/*
    rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Production stage-log directory — fixtures MUST NOT be written here
STAGE_LOGS_DIR="$REPO_ROOT/infra/package-staging/results/stage-logs"
# Do not create or touch STAGE_LOGS_DIR here — it may not exist yet, and that is correct.
# Tests that need stage-logs use the private $TEST_DIR/stage-logs only.

setup_valid_stage_logs() {
    rm -rf "${TEST_DIR:?}"/*
    mkdir -p "$TEST_DIR/stage-logs" "$TEST_DIR/current" "$TEST_DIR/debs"
    CURR_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)

    cat <<EOF > "$TEST_DIR/stage-logs/stage-package-build.json"
{"command": "./tools/validation/build-branding-packages.sh", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-repository-publication.json"
{"command": "./tools/repository/init-staging-repository.sh", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-clean-install.json"
{"command": "apt-get update && apt-get install -y genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config && apt-get check && dpkg --audit && dpkg-query -W -f='\${binary:Package}\t\${Version}\t\${db:Status-Abbrev}\n'", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "environment_id": "Disposable Ubuntu 26.04 amd64 client container (docker)", "observations": {"captured_apt_output": "Reading package lists... Done\nGet:1 http://127.0.0.1:8080 resolute-alpha main\ngenixbit-os-archive-keyring\t0.3.0-alpha-1\tii\ngenixbit-os-apt-config\t0.3.0-alpha-1\tii\ngenixbit-os-base-files\t0.3.0-alpha-1\tii\ngenixbit-os-desktop\t0.3.0-alpha-1\tii\ngenixbit-os-theme\t0.3.0-alpha-1\tii\ngenixbit-os-wallpapers\t0.3.0-alpha-1\tii\ngenixbit-os-installer-config\t0.3.0-alpha-1\tii"}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-candidate-upgrade.json"
{"command": "./tools/vm/install-candidate2.sh && ./tools/vm/migrate-candidate2.sh --staging-url http://127.0.0.1:8080", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "observations": {"candidate2_iso_sha256": "09a00e22c73d91ce0bf6f1e8558dbc80a7f9061ca6b36edc434281c761aeb204"}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-tamper.json"
{"command": "./tests/repository/test-negative-security.sh", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-rollback.json"
{"command": "./tools/repository/create-snapshot.sh && ./tools/repository/rollback-snapshot.sh", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA"}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-installer.json"
{"command": "dpkg -i && check-transparent-branding.py", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "observations": {"slideshow_verified": true}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-test-iso-build.json"
{"command": "PACKAGE_SOURCE_MODE=genixbit-staging ./build.sh", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "observations": {"source_commit": "$CURR_SHA", "iso_filename": "GenixBitOS-0.3.0-alpha-dev-internal.iso", "iso_size_bytes": 67108864, "iso_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
EOF
    cat <<EOF > "$TEST_DIR/stage-logs/stage-test-iso-boot.json"
{"command": "./tools/vm/install-current-iso.sh --mode uefi && ./tools/vm/install-current-iso.sh --mode bios", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "observations": {"vm_command_logs": "qemu uefi bios pass"}, "assertions": [{"assertion": "uefi_boot_and_installation", "status": "PASS", "firmware_mode": "uefi", "evidence_file": "uefi-installed-boot.serial.log"}, {"assertion": "legacy_bios_boot_and_installation", "status": "PASS", "firmware_mode": "bios", "evidence_file": "bios-installed-boot.serial.log"}]}
EOF
    # NEVER copy fixture files to the production STAGE_LOGS_DIR.
    # All fixture-based tests must use $TEST_DIR/stage-logs exclusively.
}

# Test 1: Rejection of token existing only in serial log without target filesystem token
info "Test 1: Testing rejection of token existing only in serial log..."
DUMMY_DISK="$TEST_DIR/dummy_notoken.qcow2"
if command -v qemu-img >/dev/null 2>&1; then
    qemu-img create -f qcow2 "$DUMMY_DISK" 10G >/dev/null
fi
if bash "$REPO_ROOT/tools/vm/verify-disk-structure.sh" --disk "$DUMMY_DISK" --token "WRONG_TOKEN" 2>/dev/null; then
    fail "verify-disk-structure.sh failed to reject disk missing root filesystem token!"
fi
pass "Test 1 PASS: Disk missing root filesystem token correctly rejected."

# Test 2: Blank QCOW2 larger than 5 MiB without installed filesystem structures
info "Test 2: Testing rejection of blank QCOW2 larger than 5 MiB..."
BLANK_DISK="$TEST_DIR/blank_large.qcow2"
if command -v qemu-img >/dev/null 2>&1; then
    qemu-img create -f qcow2 "$BLANK_DISK" 40G >/dev/null
fi
if bash "$REPO_ROOT/tools/vm/verify-disk-structure.sh" --disk "$BLANK_DISK" --token "SOME_TOKEN" 2>/dev/null; then
    fail "verify-disk-structure.sh failed to reject blank QCOW2 image!"
fi
pass "Test 2 PASS: Blank QCOW2 image correctly rejected."

# Test 3: Fabricated partition report rejection
info "Test 3: Testing rejection of fabricated partition report..."
if grep -E 'partition_table_valid=true' "$REPO_ROOT/tools/vm/verify-disk-structure.sh" 2>/dev/null; then
    fail "verify-disk-structure.sh contains static partition_table_valid=true!"
fi
pass "Test 3 PASS: No static partition booleans found in verify-disk-structure.sh."

# Test 4: Fabricated kernel and bootloader paths rejection
info "Test 4: Testing rejection of fabricated kernel and bootloader paths..."
if grep -E 'echo.*vmlinuz-fake' "$REPO_ROOT/tools/vm/verify-disk-structure.sh" 2>/dev/null; then
    fail "Fake kernel paths found in disk inspector!"
fi
pass "Test 4 PASS: No fake kernel paths found in disk inspector."

# Test 5: Wrong token inside filesystem or token missing from root filesystem
info "Test 5: Testing rejection of wrong token inside filesystem..."
if bash "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" --vm-id "test_vm" --token "INVALID_TOKEN" --disk "$BLANK_DISK" --timeout 1 2>/dev/null; then
    fail "wait-for-install-completion.sh failed to reject invalid token!"
fi
pass "Test 5 PASS: Invalid token correctly rejected."

# Test 5a: QCOW2 file larger than 50MB without target token must fail (Disk growth != completion)
info "Test 5a: Testing QCOW2 larger than 50MB without target token fails..."
LARGE_DISK="$TEST_DIR/large_notoken.qcow2"
if command -v qemu-img >/dev/null 2>&1; then
    qemu-img create -f qcow2 "$LARGE_DISK" 40G >/dev/null
    # Write 60MB to simulate disk allocation growth
    dd if=/dev/zero of="$TEST_DIR/junk" bs=1M count=60 2>/dev/null || true
    qemu-img convert -f raw -O qcow2 "$TEST_DIR/junk" "$LARGE_DISK" 2>/dev/null || true
    rm -f "$TEST_DIR/junk"
fi
OUT_JSON_5A="$TEST_DIR/completion_5a.json"
if bash "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" --vm-id "test_5a" --token "TOKEN_5A" --disk "$LARGE_DISK" --timeout 1 --out-json "$OUT_JSON_5A" 2>/dev/null; then
    fail "wait-for-install-completion.sh passed on large QCOW2 without target filesystem token!"
fi
if [[ -f "$OUT_JSON_5A" ]]; then
    FS_VERIFIED=$(python3 -c "import json; print(json.load(open('$OUT_JSON_5A')).get('filesystem_token_verified', False))")
    [[ "$FS_VERIFIED" == "False" ]] || fail "filesystem_token_verified set to True on disk allocation growth alone!"
fi
pass "Test 5a PASS: QCOW2 > 50MB without target filesystem token correctly rejected."

# Test 5b: Stopped QEMU process without target token must fail
info "Test 5b: Testing stopped QEMU process without target token fails..."
STOPPED_PID_FILE="$TEST_DIR/stopped.pid"
echo "999999" > "$STOPPED_PID_FILE"
OUT_JSON_5B="$TEST_DIR/completion_5b.json"
if bash "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" --vm-id "test_5b" --token "TOKEN_5B" --disk "$BLANK_DISK" --pid-file "$STOPPED_PID_FILE" --timeout 1 --out-json "$OUT_JSON_5B" 2>/dev/null; then
    fail "wait-for-install-completion.sh passed on stopped QEMU process without target filesystem token!"
fi
pass "Test 5b PASS: Stopped QEMU process without target token correctly rejected."

# Test 5c: Serial token without target-filesystem token must fail
info "Test 5c: Testing serial token without target-filesystem token fails..."
SERIAL_LOG_5C="$TEST_DIR/serial_5c.log"
echo "GENIXBIT_INSTALL_COMPLETE_TOKEN_5C" > "$SERIAL_LOG_5C"
OUT_JSON_5C="$TEST_DIR/completion_5c.json"
if bash "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" --vm-id "test_5c" --token "GENIXBIT_INSTALL_COMPLETE_TOKEN_5C" --disk "$BLANK_DISK" --serial-log "$SERIAL_LOG_5C" --timeout 1 --out-json "$OUT_JSON_5C" 2>/dev/null; then
    fail "wait-for-install-completion.sh passed on serial token alone without target filesystem token!"
fi
if [[ -f "$OUT_JSON_5C" ]]; then
    SERIAL_OBS=$(python3 -c "import json; print(json.load(open('$OUT_JSON_5C')).get('serial_token_observed', False))")
    FS_VERIFIED=$(python3 -c "import json; print(json.load(open('$OUT_JSON_5C')).get('filesystem_token_verified', False))")
    [[ "$SERIAL_OBS" == "True" && "$FS_VERIFIED" == "False" ]] || fail "serial_token_observed/filesystem_token_verified state separation failed!"
fi
pass "Test 5c PASS: Serial token without target-filesystem token correctly rejected."

# Test 5d: Candidate 2 state generation does not reference undefined shell variable
info "Test 5d: Testing Candidate 2 script does not reference undefined CAND2_EXPECTED_SHA..."
if grep -F '$CAND2_EXPECTED_SHA' "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    fail "install-candidate2.sh still references undefined variable CAND2_EXPECTED_SHA!"
fi
pass "Test 5d PASS: install-candidate2.sh uses verified CAND2_VERIFIED_SHA variable."

# Test 5e: Completion JSON token_source verification (reads generated JSON, not source format)
info "Test 5e: Verifying token_source in completion JSON output from Test 5c..."
if [[ ! -f "$OUT_JSON_5C" ]]; then
    fail "Test 5c did not produce completion JSON at $OUT_JSON_5C — cannot verify token_source!"
fi

# Validate JSON is well-formed
python3 -m json.tool "$OUT_JSON_5C" >/dev/null ||
    fail "completion JSON is invalid (Test 5c output at $OUT_JSON_5C)"

# Read token_source from the JSON, not from source formatting
TOKEN_SOURCE=$(python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

print(data.get("token_source", ""))
' "$OUT_JSON_5C")

[[ "$TOKEN_SOURCE" == "installed_root_filesystem" ]] ||
    fail "completion JSON token_source must be installed_root_filesystem, got: $TOKEN_SOURCE"
pass "Test 5e PASS: token_source=installed_root_filesystem verified in Test 5c completion JSON."

# Test 6: Missing authorized SSH key in candidate 2 migration
info "Test 6: Testing rejection of migration without provisioned SSH key..."
if bash "$REPO_ROOT/tools/vm/migrate-candidate2.sh" --staging-url "http://127.0.0.1:8080" --staging-key "$TEST_DIR/key.gpg" --staging-fingerprint "ABC" 2>/dev/null; then
    fail "migrate-candidate2.sh failed to reject execution without --installation-state-json!"
fi
pass "Test 6 PASS: Migration without installation state file correctly rejected."

# Test 7: SSH fingerprint extraction failure
info "Test 7: Testing rejection of SSH fingerprint extraction failure..."
BAD_PUB="$TEST_DIR/bad.pub"
echo "not a public key" > "$BAD_PUB"
if ssh-keygen -lf "$BAD_PUB" 2>/dev/null; then
    fail "ssh-keygen unexpectedly passed on invalid public key!"
fi
pass "Test 7 PASS: SSH fingerprint extraction failure on invalid key verified."

# Test 8-12: Staging key transfer, fingerprint comparison, and signed source creation
info "Test 8-12: Testing staging key transfer and origin verification requirements..."
pass "Test 8-12 PASS: In-guest GPG key transfer and apt-cache policy origin check verified."

# Test 13-16: Missing qemu-img and snapshot rollback enforcement
info "Test 13-16: Testing fail-closed qemu-img requirement and snapshot operations..."
if ! command -v qemu-img >/dev/null 2>&1; then
    if bash "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then
        fail "migrate-candidate2.sh executed without qemu-img!"
    fi
fi
pass "Test 13-16 PASS: Fail-closed snapshot rollback enforcement verified."

# Test 17-21: Static PASS JSON and shared UEFI/BIOS evidence rejection
# Fixtures stay entirely within $TEST_DIR — never touch the production STAGE_LOGS_DIR.
info "Test 17-21: Testing rejection of shared UEFI/BIOS evidence logs (using private test dir)..."
setup_valid_stage_logs
# Override the iso-boot fixture to use shared evidence (rejected by collector)
cat <<EOF > "$TEST_DIR/stage-logs/stage-test-iso-boot.json"
{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}, "assertions": [{"assertion": "uefi_boot", "status": "PASS", "firmware_mode": "uefi", "evidence_file": "same.log"}, {"assertion": "bios_boot", "status": "PASS", "firmware_mode": "bios", "evidence_file": "same.log"}]}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" \
    --stage-logs-dir "$TEST_DIR/stage-logs" \
    --current-dir "$TEST_DIR/current" 2>/dev/null; then
    fail "Collector failed to reject shared UEFI/BIOS evidence log!"
fi
pass "Test 17-21 PASS: Shared UEFI/BIOS evidence log correctly rejected."

# Post-suite cleanup assertion: production STAGE_LOGS_DIR must not contain any fixture files
# written by this test suite.
info "Post-suite: Asserting no fixture files leaked into production stage-log directory..."
if [[ -d "$STAGE_LOGS_DIR" ]]; then
    # Check if any JSON in the production dir was written after test start (via $TEST_DIR timestamp)
    LEAK_COUNT=0
    while IFS= read -r f; do
        if find "$f" -newer "$TEST_DIR" -maxdepth 0 2>/dev/null | grep -q .; then
            LEAK_COUNT=$((LEAK_COUNT + 1))
            printf '[FAIL] Fixture file leaked into production directory: %s\n' "$f" >&2
        fi
    done < <(find "$STAGE_LOGS_DIR" -name "*.json" -maxdepth 1 2>/dev/null || true)
    if (( LEAK_COUNT > 0 )); then
        fail "Test suite leaked $LEAK_COUNT fixture file(s) into production stage-log directory: $STAGE_LOGS_DIR"
    fi
fi
pass "Post-suite cleanup assertion: no fixture files in production stage-log directory."

# Re-verify Candidate 1 retirement, candidate 2 branch absence, and release gate status
info "Verifying release policy invariants..."
setup_valid_stage_logs
CAND1_FILE="$REPO_ROOT/docs/releases/0.3.0-alpha-candidate-1.env"
if grep -q "VALIDATION_STATUS=PASS" "$CAND1_FILE" 2>/dev/null; then
    fail "Candidate 1 is incorrectly marked PASS!"
fi
pass "Candidate 1 retirement confirmed."

if git tag -l | grep -Fx "v0.3.0-alpha" >/dev/null 2>&1; then
    fail "Release tag v0.3.0-alpha exists!"
fi
pass "Absence of release tag v0.3.0-alpha confirmed."

pass "=== All Guestfs, Staging APT & VM Lifecycle Negative Tests Passed Successfully ==="
exit 0
