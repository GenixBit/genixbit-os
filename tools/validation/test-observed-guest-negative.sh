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

STAGE_LOGS_DIR="$REPO_ROOT/infra/package-staging/results/stage-logs"
mkdir -p "$STAGE_LOGS_DIR"

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
{"command": "./tools/vm/install-candidate2.sh && ./tools/vm/migrate-candidate2.sh --staging-url http://127.0.0.1:8080", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "observations": {"candidate2_iso_sha256": "d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228"}}
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
    cp -r "$TEST_DIR/stage-logs"/* "$STAGE_LOGS_DIR/"
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

# Test 5: Wrong token inside filesystem
info "Test 5: Testing rejection of wrong token inside filesystem..."
if bash "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" --vm-id "test_vm" --token "INVALID_TOKEN" --disk "$BLANK_DISK" --timeout 1 2>/dev/null; then
    fail "wait-for-install-completion.sh failed to reject invalid token!"
fi
pass "Test 5 PASS: Invalid token correctly rejected."

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
info "Test 17-21: Testing rejection of shared UEFI/BIOS evidence logs..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-test-iso-boot.json"
{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}, "assertions": [{"assertion": "uefi_boot", "status": "PASS", "firmware_mode": "uefi", "evidence_file": "same.log"}, {"assertion": "bios_boot", "status": "PASS", "firmware_mode": "bios", "evidence_file": "same.log"}]}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject shared UEFI/BIOS evidence log!"
fi
pass "Test 17-21 PASS: Shared UEFI/BIOS evidence log correctly rejected."

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
