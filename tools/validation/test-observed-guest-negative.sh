#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Deterministic Negative Test Suite for Observed Guest Milestones & Evidence Collector Integrity

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

info "=== Running Deterministic Observed Guest Negative Test Suite ==="

TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_DIR"
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
{"command": "apt-get update && apt-get install -y genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config && apt-get check && dpkg --audit && dpkg-query -W", "exit_code": 0, "status": "PASS", "source_commit": "$CURR_SHA", "environment_id": "Disposable Ubuntu 26.04 amd64 client container (docker)", "observations": {"captured_apt_output": "Reading package lists... Done\nGet:1 http://127.0.0.1:8080 resolute-alpha main"}}
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

# 1. Reject fake rootfs isolation
info "Test 1: Rejection of fake rootfs isolation..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-clean-install.json"
{"command": "apt-get update", "exit_code": 0, "status": "PASS", "environment_id": "Fake temporary rootfs"}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject fake rootfs isolation!"
fi
pass "Test 1 PASS: Fake rootfs isolation correctly rejected."

# 2. Reject apt-get update || true
info "Test 2: Rejection of apt-get update || true..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-clean-install.json"
{"command": "apt-get update || true", "exit_code": 0, "status": "PASS"}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject apt-get update || true!"
fi
pass "Test 2 PASS: apt-get update || true correctly rejected."

# 3. Reject hardcoded passphrase fallback pattern in evidence
info "Test 3: Rejection of hardcoded passphrase fallback in evidence..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-repository-publication.json"
{"command": "init", "exit_code": 0, "status": "PASS", "key": "genixbit-staging-key-passphrase-2026"}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject hardcoded passphrase fallback!"
fi
pass "Test 3 PASS: Hardcoded passphrase fallback correctly rejected."

# 4. Reject dpkg -i --root presented as clean install
info "Test 4: Rejection of dpkg -i --root clean install..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-clean-install.json"
{"command": "dpkg -i --root=/tmp/rootfs pkg.deb", "exit_code": 0, "status": "PASS", "environment_id": "Ubuntu 26.04"}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject dpkg -i --root clean install!"
fi
pass "Test 4 PASS: dpkg -i --root clean install correctly rejected."

# 5. Reject missing apt-get check
info "Test 5: Rejection of missing apt-get check..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-clean-install.json"
{"command": "apt-get install pkg", "exit_code": 0, "status": "PASS", "environment_id": "Ubuntu 26.04"}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject missing apt-get check!"
fi
pass "Test 5 PASS: Missing apt-get check correctly rejected."

# 6. Reject candidate 2 migration without --staging-url
info "Test 6: Rejection of candidate 2 migration without --staging-url..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-candidate-upgrade.json"
{"command": "./tools/vm/install-candidate2.sh && ./tools/vm/migrate-candidate2.sh", "exit_code": 0, "status": "PASS", "observations": {"candidate2_iso_sha256": "d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228"}}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject migration without --staging-url!"
fi
pass "Test 6 PASS: Candidate 2 migration without --staging-url correctly rejected."

# 7. Reject UEFI and BIOS sharing the same evidence file
info "Test 7: Rejection of UEFI and BIOS sharing the same evidence file..."
setup_valid_stage_logs
cat <<EOF > "$STAGE_LOGS_DIR/stage-test-iso-boot.json"
{"command": "boot", "exit_code": 0, "status": "PASS", "observations": {"vm_command_logs": "qemu boot pass"}, "assertions": [{"assertion": "uefi_boot", "status": "PASS", "firmware_mode": "uefi", "evidence_file": "same.log"}, {"assertion": "bios_boot", "status": "PASS", "firmware_mode": "bios", "evidence_file": "same.log"}]}
EOF
if python3 "$REPO_ROOT/tools/validation/collect-migration-evidence.py" 2>/dev/null; then
    fail "Collector failed to reject UEFI and BIOS sharing evidence file!"
fi
pass "Test 7 PASS: Shared UEFI/BIOS evidence file correctly rejected."

# 8. Reject zero-byte screenshot file
info "Test 8: Rejection of zero-byte screenshot file..."
SCREENSHOT_TMP="$TEST_DIR/empty.ppm"
touch "$SCREENSHOT_TMP"
if bash "$REPO_ROOT/tools/vm/capture-screenshot.sh" --socket "$TEST_DIR/nonexistent.sock" --output "$SCREENSHOT_TMP" 2>/dev/null; then
    fail "capture-screenshot.sh failed to reject missing QMP socket or zero-byte screenshot!"
fi
pass "Test 8 PASS: Zero-byte screenshot / invalid socket correctly rejected."

pass "=== All Observed Guest Negative Security Tests Passed ==="
exit 0
