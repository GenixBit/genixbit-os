#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regression test suite: detect fabricated release evidence patterns introduced in PRs #96-#104.
# This suite MUST run and pass before the release gate execute step.
# Exits non-zero if any forbidden pattern is detected.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
ERRORS=()

pass_test() {
    printf '[PASS] %s\n' "$*"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
}

fail_test() {
    printf '[FAIL] %s\n' "$*" >&2
    ERRORS+=("$*")
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

info() {
    printf '[INFO] %s\n' "$*"
}

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: install-candidate2.sh must not contain guestfish write of OS files
# ─────────────────────────────────────────────────────────────────────────────
info "Test 1: install-candidate2.sh must not pre-provision OS files via guestfish..."
INSTALL_SCRIPT="$REPO_ROOT/tools/vm/install-candidate2.sh"
GUESTFISH_FORBIDDEN_PATTERNS=(
    "write /etc/genixbit-install-token"
    "write /etc/os-release"
    "write /etc/passwd"
    "write /etc/fstab"
    "touch /boot/efi/EFI/BOOT/BOOTX64.EFI"
    "write /boot/grub/grub.cfg"
    "touch /boot/vmlinuz"
    "touch /boot/initrd.img"
)
for pat in "${GUESTFISH_FORBIDDEN_PATTERNS[@]}"; do
    if grep -qF "$pat" "$INSTALL_SCRIPT" 2>/dev/null; then
        fail_test "install-candidate2.sh contains forbidden guestfish pre-provision: '$pat'"
    fi
done
pass_test "install-candidate2.sh: no guestfish OS-file pre-provisioning detected"

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: install-candidate2.sh must not use sleep 30 as installed-boot evidence
# ─────────────────────────────────────────────────────────────────────────────
info "Test 2: install-candidate2.sh must not use sleep 30 as installed-boot evidence..."
if grep -q 'sleep 30' "$INSTALL_SCRIPT" 2>/dev/null; then
    fail_test "install-candidate2.sh contains 'sleep 30' — installed-boot must be verified via SSH, not a timer"
fi
if grep -q 'SERIAL_EVIDENCE_COLLECTED' "$INSTALL_SCRIPT" 2>/dev/null; then
    fail_test "install-candidate2.sh contains SERIAL_EVIDENCE_COLLECTED — installed-boot must be SSH_AUTHENTICATED_PASS"
fi
pass_test "install-candidate2.sh: no sleep-30 / SERIAL_EVIDENCE_COLLECTED installed-boot pattern"

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: migrate-candidate2.sh must not contain offline echoed migration text
# ─────────────────────────────────────────────────────────────────────────────
info "Test 3: migrate-candidate2.sh must not contain offline echoed migration text..."
MIGRATE_SCRIPT="$REPO_ROOT/tools/vm/migrate-candidate2.sh"
MIGRATION_FORBIDDEN_PATTERNS=(
    'echo "genixbit-os-archive-keyring INSTALLED"'
    'echo "genixbit-os-desktop INSTALLED"'
    'echo "apt-get check: OK"'
    'echo "dpkg --audit: OK'
    'echo "Migration status: PASS"'
    'echo "rollback_status: PASS"'
    'echo "reupgrade_status: PASS"'
    'echo "Post-migration status: PASS"'
    'echo "reupgrade_final_status: PASS"'
    "offline.migr"
    "Offline Migration Execution"
    "Applying offline staging migration markers"
    "pre-provisioned skeleton"
)
for pat in "${MIGRATION_FORBIDDEN_PATTERNS[@]}"; do
    if grep -qF "$pat" "$MIGRATE_SCRIPT" 2>/dev/null; then
        fail_test "migrate-candidate2.sh contains forbidden offline-echo pattern: '$pat'"
    fi
done
pass_test "migrate-candidate2.sh: no offline echoed migration text detected"

# ─────────────────────────────────────────────────────────────────────────────
# Test 4: migrate-candidate2.sh must not hardcode result fields as PASS
# ─────────────────────────────────────────────────────────────────────────────
info "Test 4: migrate-candidate2.sh must not hardcode PASS result fields..."
# Check for the specific hardcoded literal patterns used in the old offline-echo implementation.
# Note: conditional expressions like "'PASS' if condition else 'FAIL'" are NOT forbidden.
HARDCODED_PASS_PATTERNS=(
    "'apt_update_result': 'PASS'"
    "'package_origin_report': 'PASS'"
    "'pre_migration_package_state': 'PASS'"
    "'post_migration_boot_result': 'PASS'"
    "'rollback_result': 'PASS'"
    "'rolled_back_package_state': 'PASS'"
    "'reupgrade_result': 'PASS'"
    "'final_boot_result': 'PASS'"
    "'installed_package_records': 7"
)
for pat in "${HARDCODED_PASS_PATTERNS[@]}"; do
    if grep -qF "$pat" "$MIGRATE_SCRIPT" 2>/dev/null; then
        fail_test "migrate-candidate2.sh contains hardcoded PASS result field: '$pat'"
    fi
done
pass_test "migrate-candidate2.sh: no hardcoded PASS result fields"

# ─────────────────────────────────────────────────────────────────────────────
# Test 5: migrate-candidate2.sh must reject SERIAL_EVIDENCE_COLLECTED installed boot
# ─────────────────────────────────────────────────────────────────────────────
info "Test 5: migrate-candidate2.sh must reject SERIAL_EVIDENCE_COLLECTED installed boot..."
# SERIAL_EVIDENCE_COLLECTED must only appear inside a fail/reject message — never as an accepted result.
_SERIAL_LINES=$(grep -F 'SERIAL_EVIDENCE_COLLECTED' "$MIGRATE_SCRIPT" 2>/dev/null || true)
_ACCEPTED_USAGE=$(echo "$_SERIAL_LINES" | grep -vF 'fail\|Reject\|reject' | grep -vF 'only SSH_AUTHENTICATED_PASS' | grep -vE '^\s*$' || true)
if [[ -n "$_ACCEPTED_USAGE" ]]; then
    fail_test "migrate-candidate2.sh: SERIAL_EVIDENCE_COLLECTED appears outside a rejection/fail context — must require SSH_AUTHENTICATED_PASS"
fi
if grep -qF 'SSH_AUTHENTICATED_PASS' "$MIGRATE_SCRIPT" 2>/dev/null; then
    pass_test "migrate-candidate2.sh: requires SSH_AUTHENTICATED_PASS for installed boot (SERIAL_EVIDENCE_COLLECTED only in reject context)"
else
    fail_test "migrate-candidate2.sh: does not verify installed_boot_result is SSH_AUTHENTICATED_PASS"
fi


# ─────────────────────────────────────────────────────────────────────────────
# Test 6: validate-package-migration.sh must not rename Candidate 2 ISO
# ─────────────────────────────────────────────────────────────────────────────
info "Test 6: validate-package-migration.sh must not rename Candidate 2 ISO..."
VALIDATE_SCRIPT="$REPO_ROOT/tools/validation/validate-package-migration.sh"
RENAME_FORBIDDEN_PATTERNS=(
    "GenixBitOS-0.3.0-alpha-internal.iso"
    "Using verified Candidate 2 ISO as test ISO artifact"
    "Copied real Candidate 2 QEMU serial log as UEFI+BIOS boot evidence"
    "cand2-install-serial.log.*UEFI_SERIAL"
    "cand2-install-serial.log.*BIOS_SERIAL"
)
for pat in "${RENAME_FORBIDDEN_PATTERNS[@]}"; do
    if grep -qE "$pat" "$VALIDATE_SCRIPT" 2>/dev/null; then
        fail_test "validate-package-migration.sh contains forbidden Cand2 rename pattern: '$pat'"
    fi
done
pass_test "validate-package-migration.sh: no Candidate 2 ISO rename pattern detected"

# ─────────────────────────────────────────────────────────────────────────────
# Test 7: validate-package-migration.sh must not create placeholder boot evidence
# ─────────────────────────────────────────────────────────────────────────────
info "Test 7: validate-package-migration.sh must not create placeholder boot evidence..."
PLACEHOLDER_PATTERNS=(
    "SeaBIOS.*QEMU BIOS boot evidence"
    "OVMF UEFI boot evidence"
    "creating placeholder boot evidence"
)
for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
    if grep -qE "$pat" "$VALIDATE_SCRIPT" 2>/dev/null; then
        fail_test "validate-package-migration.sh creates placeholder boot evidence: '$pat'"
    fi
done
pass_test "validate-package-migration.sh: no placeholder boot evidence creation"

# ─────────────────────────────────────────────────────────────────────────────
# Test 8: validate-package-migration.sh must execute real build.sh
# ─────────────────────────────────────────────────────────────────────────────
info "Test 8: validate-package-migration.sh must call real build.sh..."
if ! grep -q 'PACKAGE_SOURCE_MODE=genixbit-staging' "$VALIDATE_SCRIPT" 2>/dev/null; then
    fail_test "validate-package-migration.sh: does not call PACKAGE_SOURCE_MODE=genixbit-staging ./build.sh"
fi
if ! grep -q 'bash.*build.sh' "$VALIDATE_SCRIPT" 2>/dev/null; then
    fail_test "validate-package-migration.sh: does not call build.sh"
fi
pass_test "validate-package-migration.sh: calls real build.sh with PACKAGE_SOURCE_MODE=genixbit-staging"

# ─────────────────────────────────────────────────────────────────────────────
# Test 9: validate-package-migration.sh must reject identical UEFI/BIOS evidence
# ─────────────────────────────────────────────────────────────────────────────
info "Test 9: validate-package-migration.sh must reject identical UEFI/BIOS evidence..."
if ! grep -q 'UEFI_HASH.*BIOS_HASH\|BIOS_HASH.*UEFI_HASH\|uefi_hash.*bios_hash\|bios_hash.*uefi_hash' "$VALIDATE_SCRIPT" 2>/dev/null; then
    # Try alternate: check for the identity check pattern
    if grep -q 'SHA-256.*identical\|identical.*SHA' "$VALIDATE_SCRIPT" 2>/dev/null; then
        pass_test "validate-package-migration.sh: UEFI/BIOS evidence identity check present"
    else
        fail_test "validate-package-migration.sh: no check that UEFI and BIOS serial evidence must differ"
    fi
else
    pass_test "validate-package-migration.sh: UEFI/BIOS evidence identity rejection check present"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 10: validate-package-migration.sh must call install-current-iso.sh for both modes
# ─────────────────────────────────────────────────────────────────────────────
info "Test 10: validate-package-migration.sh must call install-current-iso.sh --mode uefi AND --mode bios..."
UEFI_CALL=$(grep -c '\-\-mode uefi' "$VALIDATE_SCRIPT" 2>/dev/null || echo "0")
BIOS_CALL=$(grep -c '\-\-mode bios' "$VALIDATE_SCRIPT" 2>/dev/null || echo "0")
if [[ "$UEFI_CALL" -lt 1 ]]; then
    fail_test "validate-package-migration.sh: no --mode uefi call to install-current-iso.sh"
fi
if [[ "$BIOS_CALL" -lt 1 ]]; then
    fail_test "validate-package-migration.sh: no --mode bios call to install-current-iso.sh"
fi
pass_test "validate-package-migration.sh: calls install-current-iso.sh for both UEFI and BIOS modes"

# ─────────────────────────────────────────────────────────────────────────────
# Test 11: release-gate.yml must not pass release-validation bypass flags
# ─────────────────────────────────────────────────────────────────────────────
info "Test 11: release-gate.yml must not contain release-validation bypass flags..."
GATE_WORKFLOW="$REPO_ROOT/.github/workflows/release-gate.yml"
BYPASS_PATTERNS=(
    "EXECUTE_REAL_ISO_BUILD=false"
    "EXECUTE_REAL_VM_TESTS=false"
    "EXECUTE_REAL_CLIENT_INSTALL=false"
)
for pat in "${BYPASS_PATTERNS[@]}"; do
    if grep -q "$pat" "$GATE_WORKFLOW" 2>/dev/null; then
        fail_test "release-gate.yml contains bypass flag: '$pat'"
    fi
done
if grep -q 'EXECUTE_REAL_MIGRATION=false' "$GATE_WORKFLOW" 2>/dev/null && \
   ! grep -q 'ACTIVE_RELEASE_MODE=fresh-install-only' "$GATE_WORKFLOW" 2>/dev/null && \
   ! grep -q 'ACTIVE_RELEASE_MODE: fresh-install-only' "$GATE_WORKFLOW" 2>/dev/null; then
    fail_test "release-gate.yml disables migration without fresh-install-only active release mode"
fi
pass_test "release-gate.yml: no release-validation bypass flags beyond fresh-install-only migration NA"

# ─────────────────────────────────────────────────────────────────────────────
# Test 12: release-gate.yml must restore build dependencies installation step
# ─────────────────────────────────────────────────────────────────────────────
info "Test 12: release-gate.yml must have build dependency installation step..."
if ! grep -q 'debootstrap' "$GATE_WORKFLOW" 2>/dev/null; then
    fail_test "release-gate.yml: debootstrap not installed in CI — build.sh will fail"
fi
if ! grep -q 'squashfs-tools\|squashfs' "$GATE_WORKFLOW" 2>/dev/null; then
    fail_test "release-gate.yml: squashfs-tools not installed in CI"
fi
if ! grep -q 'xorriso' "$GATE_WORKFLOW" 2>/dev/null; then
    fail_test "release-gate.yml: xorriso not installed in CI"
fi
pass_test "release-gate.yml: ISO build dependencies (debootstrap, squashfs-tools, xorriso) installed"

# ─────────────────────────────────────────────────────────────────────────────
# Test 13: 0.3.0-release-gate.json must not contain PASS_AWAITING_PRODUCTION_SIGN_OFF
# ─────────────────────────────────────────────────────────────────────────────
info "Test 13: 0.3.0-release-gate.json must not have PASS_AWAITING_PRODUCTION_SIGN_OFF as gate status..."
# The string may appear legitimately in the retraction/documentation section.
# What must NOT happen: the overall_gate_status field itself set to that value.
GATE_JSON="$REPO_ROOT/docs/releases/0.3.0-release-gate.json"
GATE_STATUS=$(python3 -c "import json; d=json.load(open('$GATE_JSON')); print(d.get('summary',{}).get('overall_gate_status',''))" 2>/dev/null || echo "")

if [[ "$GATE_STATUS" == "PASS_AWAITING_PRODUCTION_SIGN_OFF" ]]; then
    fail_test "0.3.0-release-gate.json: summary.overall_gate_status is PASS_AWAITING_PRODUCTION_SIGN_OFF — fabricated gate PASS detected"
fi
if [[ "$GATE_STATUS" == "BLOCKED_INVALID_RELEASE_EVIDENCE" ]]; then
    pass_test "0.3.0-release-gate.json: overall_gate_status is correctly BLOCKED_INVALID_RELEASE_EVIDENCE"
else
    fail_test "0.3.0-release-gate.json: overall_gate_status is '$GATE_STATUS' — expected BLOCKED_INVALID_RELEASE_EVIDENCE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 14: collect-migration-evidence.py must reject retired 1cb79fbf Candidate 2 SHA
# ─────────────────────────────────────────────────────────────────────────────
info "Test 14: collect-migration-evidence.py must reject retired 1cb79fbf Candidate 2 SHA..."
COLLECT_PY="$REPO_ROOT/tools/validation/collect-migration-evidence.py"
if grep -q 'd9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228' "$COLLECT_PY" 2>/dev/null; then
    fail_test "collect-migration-evidence.py: still contains fabricated d9aa0d2e SHA"
fi
if ! grep -q '1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669' "$COLLECT_PY" 2>/dev/null; then
    fail_test "collect-migration-evidence.py: does not contain retired 1cb79fbf SHA guard"
fi
if ! grep -q 'retired zero-filled artifact' "$COLLECT_PY" 2>/dev/null; then
    fail_test "collect-migration-evidence.py: missing retired artifact rejection language"
fi
pass_test "collect-migration-evidence.py: rejects retired 1cb79fbf Candidate 2 SHA"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
printf '\n=== Release Evidence Integrity Regression Test Results ===\n'
printf 'PASS: %d\n' "$PASS_COUNT"
printf 'FAIL: %d\n' "$FAIL_COUNT"

if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    printf '\nFailed tests:\n'
    for e in "${ERRORS[@]}"; do
        printf '  [FAIL] %s\n' "$e" >&2
    done
    printf '\n[FAIL] Release evidence integrity check FAILED. Fabricated evidence patterns detected.\n' >&2
    exit 1
fi

printf '\n[PASS] All release evidence integrity regression tests passed.\n'
exit 0
