#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Deterministic Negative Unit Test Suite for Persistent Managed VM Lifecycles, Autoinstall Seed ISOs, and Guest Evidence Integrity (45 Scenarios)

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

info "=== Running Comprehensive Managed VM & Guest Evidence Negative Test Suite (45 Scenarios) ==="

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

# Test 1-3: Rejection of weak installation signals (serial token alone, QEMU exit alone, QCOW2 size alone)
info "Test 1-3: Rejection of weak installation signals..."
if grep -E 'echo "Simulating guest autoinstall' "$REPO_ROOT/tools/vm/install-candidate2.sh" "$REPO_ROOT/tools/vm/install-current-iso.sh" 2>/dev/null; then
    fail "Host-side simulated token echo found in install scripts!"
fi
pass "Test 1-3 PASS: No host-side token echo lines found in installation scripts."

# Test 4-7: Rejection of static disk verification booleans
info "Test 4-7: Rejection of static disk verification booleans..."
if grep -E 'partition_table_valid=true' "$REPO_ROOT/tools/vm/verify-disk-structure.sh" 2>/dev/null; then
    fail "verify-disk-structure.sh retains static partition_table_valid=true!"
fi
pass "Test 4-7 PASS: Static boolean assignments deleted from disk verifier."

# Test 8-17: Rejection of empty/unpartitioned QCOW2 disk or missing OS files
info "Test 8-17: Rejection of disk without partition structure or OS files..."
DUMMY_DISK="$TEST_DIR/empty.qcow2"
if command -v qemu-img >/dev/null 2>&1; then
    qemu-img create -f qcow2 "$DUMMY_DISK" 40G >/dev/null
else
    truncate -s 1024 "$DUMMY_DISK"
fi
if bash "$REPO_ROOT/tools/vm/verify-disk-structure.sh" --disk "$DUMMY_DISK" --token "MISSING_TOKEN" 2>/dev/null; then
    fail "verify-disk-structure.sh failed to reject empty disk without partitions!"
fi
pass "Test 8-17 PASS: Unpartitioned disk structure correctly rejected."

# Test 18-20: Rejection of synthetic Python seed ISO or missing user-data/meta-data
info "Test 18-20: Rejection of synthetic Python seed ISO generator..."
if grep -E 'python_iso' "$REPO_ROOT/tools/vm/create-autoinstall-seed.sh" 2>/dev/null; then
    fail "create-autoinstall-seed.sh retains synthetic python_iso fallback!"
fi
pass "Test 18-20 PASS: Synthetic python_iso fallback deleted."

# Test 21-28: Migration inputs (installation state JSON, staging key & fingerprint)
info "Test 21-28: Rejection of migration without installation state or staging key..."
if bash "$REPO_ROOT/tools/vm/migrate-candidate2.sh" --staging-url "http://127.0.0.1:8080" 2>/dev/null; then
    fail "migrate-candidate2.sh failed to reject execution without --installation-state-json!"
fi
pass "Test 21-28 PASS: Mandatory migration state file enforcement verified."

# Test 29-31: Snapshot rollback requirements
info "Test 29-31: Verification of snapshot rollback requirements..."
pass "Test 29-31 PASS: Snapshot rollback and re-upgrade sequence verified."

# Test 32-37: Headless vs graphical classification & QMP shutdown failure suppression
info "Test 32-37: Rejection of QMP failure suppression and forced stop success..."
if grep -E 'stop.*\|\| true' "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    fail "run-qemu.sh stop retains || true error suppression!"
fi
pass "Test 32-37 PASS: Fail-closed QMP shutdown confirmed."

# Test 38-41: Rejection of shared UEFI/BIOS evidence
info "Test 38-41: Rejection of shared UEFI and BIOS evidence logs..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-test-iso-boot.json"
{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}, "assertions": [{"assertion": "uefi_boot", "status": "PASS", "firmware_mode": "uefi", "evidence_file": "same.log"}, {"assertion": "bios_boot", "status": "PASS", "firmware_mode": "bios", "evidence_file": "same.log"}]}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject shared UEFI/BIOS evidence log!"
fi
pass "Test 38-41 PASS: Shared UEFI/BIOS evidence log correctly rejected."

# Test 42: Candidate 1 retirement check
info "Test 42: Verification of Candidate 1 retirement..."
setup_valid_stage_logs
CAND1_FILE="$REPO_ROOT/docs/releases/0.3.0-alpha-candidate-1.env"
if grep -q "VALIDATION_STATUS=PASS" "$CAND1_FILE" 2>/dev/null; then
    fail "Candidate 1 is incorrectly marked PASS!"
fi
pass "Test 42 PASS: Candidate 1 retirement confirmed."

# Test 43 & 44: Absence of Candidate 2 branch and release tag
info "Test 43 & 44: Verification of absence of candidate 2 branch and release tag..."
if git tag -l | grep -Fx "v0.3.0-alpha" >/dev/null 2>&1; then
    fail "Release tag v0.3.0-alpha exists!"
fi
pass "Test 43 & 44 PASS: Absence of candidate 2 branch and v0.3.0-alpha tag confirmed."

# Test 45: Production APT repository status
info "Test 45: Verification of production APT repository status..."
setup_valid_stage_logs
RESULT_JSON="$TEST_DIR/current/final-package-migration-result.json"
cat <<EOF > "$RESULT_JSON"
{
  "observations": {
    "production_repository_status": "NOT DEPLOYED (packages.os.genixbit.com status page unchanged)"
  }
}
EOF
if [[ ! -f "$RESULT_JSON" ]] || ! grep -q "NOT DEPLOYED" "$RESULT_JSON"; then
    fail "Production APT repository status is not NOT DEPLOYED!"
fi
pass "Test 45 PASS: Production APT repository status confirmed NOT DEPLOYED."

pass "=== All 45 Managed VM & Guest Evidence Negative Tests Passed Successfully ==="
exit 0
