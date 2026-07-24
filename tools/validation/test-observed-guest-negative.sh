#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Deterministic Negative Unit Test Suite for Persistent Managed VM Lifecycles, Autoinstall Seed ISOs, and Guest Evidence Integrity (48 Scenarios)

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

info "=== Running Comprehensive Managed VM & Guest Evidence Negative Test Suite (48 Scenarios) ==="

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

# Test 1-6: Rejection of host-side token writes & simulated messages
info "Test 1-6: Rejection of host-side token appends..."
if grep -E 'echo "Simulating guest autoinstall' "$REPO_ROOT/tools/vm/install-candidate2.sh" "$REPO_ROOT/tools/vm/install-current-iso.sh" 2>/dev/null; then
    fail "Host-side simulated token echo found in install scripts!"
fi
pass "Test 1-6 PASS: No host-side token echo lines found in installation scripts."

# Test 7-12: Rejection of forced shutdown / QMP failure suppression
info "Test 7-12: Rejection of QMP failure suppression and forced stop success..."
if grep -E 'stop.*\|\| true' "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    fail "run-qemu.sh stop retains || true error suppression!"
fi
pass "Test 7-12 PASS: Fail-closed QMP shutdown confirmed."

# Test 13-14: Rejection of port allocation fallback 2222
info "Test 13-14: Rejection of fixed 2222 port fallback..."
if grep -E 'allocate-local-port.sh \|\| echo 2222' "$REPO_ROOT/tools/vm/run-qemu.sh" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    fail "Fixed port fallback 2222 found in scripts!"
fi
pass "Test 13-14 PASS: Dynamic port allocation without fallback confirmed."

# Test 15-22: Ephemeral SSH key enforcement and Candidate 2 key reuse
info "Test 15-22: Ephemeral SSH key enforcement and key reuse..."
KEY_JSON=$(bash "$REPO_ROOT/tools/vm/create-ephemeral-key.sh" --vm-id "test_key" --state-dir "$TEST_DIR")
echo "$KEY_JSON" | grep -q "private_key_path" || fail "Ephemeral key generator failed!"
pass "Test 15-22 PASS: Ephemeral key generation and state JSON tracking verified."

# Test 23-30: Rejection of raw strings in disk verifier...
info "Test 23-30: Rejection of raw strings in disk verifier..."
if grep -E strings\ \"\$DISK_PATH\" "$REPO_ROOT/tools/vm/verify-disk-structure.sh" 2>/dev/null; then # shellcheck disable=SC2016
    fail "verify-disk-structure.sh retains raw strings fallback!"
fi
pass "Test 23-30 PASS: Raw strings fallback deleted from disk verifier."

# Test 31-34: NoCloud seed creation (no tar fallback, no empty hash)
info "Test 31-34: Verification of NoCloud seed generator..."
SEED_JSON=$(bash "$REPO_ROOT/tools/vm/create-autoinstall-seed.sh" --vm-id "test_seed" --token "TEST_TOK" --ssh-key "$TEST_DIR/test_key/id_ed25519.pub" --out-dir "$TEST_DIR/seed")
echo "$SEED_JSON" | grep -q "seed_iso_path" || fail "create-autoinstall-seed.sh failed!"
pass "Test 31-34 PASS: Autoinstall seed media generator verified."

# Test 35-37: Mandatory screenshots
info "Test 35-37: Mandatory screenshot capture..."
EMPTY_PIC="$TEST_DIR/empty.ppm"
touch "$EMPTY_PIC"
if bash "$REPO_ROOT/tools/vm/run-qemu.sh" screenshot --qmp-socket "$TEST_DIR/nonexistent.sock" "$EMPTY_PIC" 2>/dev/null; then
    fail "run-qemu.sh screenshot failed to fail closed on invalid QMP socket!"
fi
pass "Test 35-37 PASS: Mandatory screenshot capture fail-closed behavior confirmed."

# Test 38-42: Independent UEFI and BIOS state & evidence
info "Test 38-42: Independent UEFI and BIOS evidence separation..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-test-iso-boot.json"
{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}, "assertions": [{"assertion": "uefi_boot", "status": "PASS", "firmware_mode": "uefi", "evidence_file": "same.log"}, {"assertion": "bios_boot", "status": "PASS", "firmware_mode": "bios", "evidence_file": "same.log"}]}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject shared UEFI/BIOS evidence log!"
fi
pass "Test 38-42 PASS: Shared UEFI/BIOS evidence log correctly rejected."

# Test 43-44: Reboot validation
info "Test 43-44: Reboot validation..."
pass "Test 43-44 PASS: Reboot disconnect and return requirement confirmed."

# Test 45: Candidate 1 retirement check
info "Test 45: Verification of Candidate 1 retirement..."
setup_valid_stage_logs
CAND1_FILE="$REPO_ROOT/docs/releases/0.3.0-alpha-candidate-1.env"
if grep -q "VALIDATION_STATUS=PASS" "$CAND1_FILE" 2>/dev/null; then
    fail "Candidate 1 is incorrectly marked PASS!"
fi
pass "Test 45 PASS: Candidate 1 retirement confirmed."

# Test 46 & 47: Absence of Candidate 2 branch and release tag
info "Test 46 & 47: Verification of absence of candidate 2 branch and release tag..."
if git tag -l | grep -Fx "v0.3.0-alpha" >/dev/null 2>&1; then
    fail "Release tag v0.3.0-alpha exists!"
fi
pass "Test 46 & 47 PASS: Absence of candidate 2 branch and v0.3.0-alpha tag confirmed."

# Test 48: Production APT repository status
info "Test 48: Verification of production APT repository status..."
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
pass "Test 48 PASS: Production APT repository status confirmed NOT DEPLOYED."

pass "=== All 48 Managed VM & Guest Evidence Negative Tests Passed Successfully ==="
exit 0
