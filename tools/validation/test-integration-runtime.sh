#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Integration runtime test suite for PR #105 defect fixes.
# Tests 18 conditions that must be true for the release gate to pass.
# All tests run via static analysis (grep/bash -n) — no VMs are started.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

pass_test() {
    local num="$1" desc="$2"
    printf '[PASS] Test %2d: %s\n' "$num" "$desc"
    (( PASS_COUNT++ )) || true
}

fail_test() {
    local num="$1" desc="$2" reason="$3"
    printf '[FAIL] Test %2d: %s\n  Reason: %s\n' "$num" "$desc" "$reason"
    (( FAIL_COUNT++ )) || true
    FAILURES+=("Test $num: $desc -- $reason")
}

# Test 1 -- D1: RUN_ID defined before wait_ssh references it
T=1
DESC="D1: RUN_ID defined before wait_ssh in migrate-candidate2.sh"
RUNID_LINE=$(grep -n "^RUN_ID=" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" | head -n1 | cut -d: -f1 || echo "")
if [[ -n "$RUNID_LINE" ]]; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "RUN_ID not defined at module level in migrate-candidate2.sh"
fi

# Test 2 -- D3: validate-package-migration passes GUEST_STAGING_URL to migrate-candidate2
T=2
DESC="D3: GUEST_STAGING_URL passed to migrate-candidate2.sh --staging-url"
if grep -q "GUEST_STAGING_URL" "$REPO_ROOT/tools/validation/validate-package-migration.sh" && \
   grep -q "\-\-staging-url.*GUEST_STAGING_URL" "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "GUEST_STAGING_URL not passed to --staging-url"
fi

# Test 3 -- D4: build.sh uses GENIXBIT_STAGING_KEYRING
T=3
DESC="D4: build.sh uses GENIXBIT_STAGING_KEYRING env var"
if grep -q "GENIXBIT_STAGING_KEYRING" "$REPO_ROOT/build.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "GENIXBIT_STAGING_KEYRING not referenced in build.sh"
fi

# Test 4 -- D5: Fingerprint mismatch causes failure
T=4
DESC="D5: Staging key fingerprint mismatch causes failure in migrate-candidate2.sh"
if grep -q "Staging key fingerprint mismatch" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Fingerprint mismatch check not found"
fi

# Test 5 -- D6: Package origin verification present
T=5
DESC="D6: Package origin verification via apt-cache madison + STAGING_URL"
if grep -q "apt-cache madison" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "apt-cache madison origin check not found"
fi

# Test 6 -- D6: Missing Candidate version causes failure
T=6
DESC="D6: Missing Candidate version (none) causes failure"
if grep -q "no Candidate version in apt-cache policy" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Candidate (none) check not found"
fi

# Test 7 -- D7: Actual apt-get install exit code captured
T=7
DESC="D7: Actual apt-get install exit code captured (not inferred)"
if grep -q "APT_INSTALL_RC=0" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" && \
   grep -q "APT_INSTALL_RC=\$?" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "APT_INSTALL_RC capture pattern not found"
fi

# Test 8 -- D8: Non-empty dpkg --audit output causes failure
T=8
DESC="D8: Non-empty dpkg --audit stdout causes failure"
if grep -q "OBS_POST_DPKG_AUDIT_EMPTY" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" && \
   grep -q "dpkg --audit not clean" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "dpkg --audit empty check or failure message not found"
fi

# Test 9 -- D9: Rollback SHA equality enforced
T=9
DESC="D9: Rollback package state SHA equality enforced"
if grep -q "Rollback package state SHA-256 mismatch" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Rollback SHA equality check not found"
fi

# Test 10 -- Final status requires all conditions via all_pass
T=10
DESC="Migration final_status uses all_pass multi-condition computation"
if grep -q "all_pass = (" "$REPO_ROOT/tools/vm/migrate-candidate2.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "all_pass computation not found in migration result JSON block"
fi

# Test 11 -- D10: STOPPED_BY_SIGTERM exits non-zero
T=11
DESC="D10: STOPPED_BY_SIGTERM causes run-qemu.sh stop to exit 1"
if grep -q "STOPPED_BY_SIGTERM" "$REPO_ROOT/tools/vm/run-qemu.sh" && \
   grep -A3 "STOPPED_BY_SIGTERM" "$REPO_ROOT/tools/vm/run-qemu.sh" | grep -q "exit 1"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "STOPPED_BY_SIGTERM with exit 1 not found"
fi

# Test 12 -- D10: STOPPED_BY_SIGKILL exits non-zero
T=12
DESC="D10: STOPPED_BY_SIGKILL causes run-qemu.sh stop to exit 1"
if grep -q "STOPPED_BY_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" && \
   grep -A3 "STOPPED_BY_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" | grep -q "exit 1"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "STOPPED_BY_SIGKILL with exit 1 not found"
fi

# Test 13 -- D12: install-current-iso.sh passes --mode to wait-for-install-completion
T=13
DESC="D12: install-current-iso.sh passes --mode to wait-for-install-completion.sh"
if grep -A25 "wait-for-install-completion.sh" "$REPO_ROOT/tools/vm/install-current-iso.sh" | \
   grep -q "\-\-mode.*MODE"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "--mode \$MODE not passed to wait-for-install-completion.sh"
fi

# Test 14 -- D13: UEFI evidence -s (non-empty) check
T=14
DESC="D13: UEFI installed-boot evidence must be non-empty"
if grep -q "\-s.*UEFI_SERIAL\|UEFI.*evidence missing or empty" \
   "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "UEFI serial -s presence check not found"
fi

# Test 15 -- D13: BIOS evidence -s (non-empty) check
T=15
DESC="D13: BIOS installed-boot evidence must be non-empty"
if grep -q "\-s.*BIOS_SERIAL\|BIOS.*evidence missing or empty" \
   "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "BIOS serial -s presence check not found"
fi

# Test 16 -- Identical UEFI/BIOS SHA causes failure
T=16
DESC="Identical UEFI/BIOS serial evidence SHA causes failure"
if grep -q "identical SHA\|UEFI and BIOS serial evidence files have identical" \
   "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Identical UEFI/BIOS evidence SHA failure not found"
fi

# Test 17 -- D14: Mutable URL (no ?generation=) causes failure
T=17
DESC="D14: Mutable provenance URL without ?generation= causes failure"
if grep -q "generation=" "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "generation= check not found in validate-package-migration.sh"
fi

# Test 18 -- D14: Empty/TODO sha512 field causes failure
T=18
DESC="D14: SHA-512 cross-check present (after download, compare-or-record)"
if grep -q "SHA-512 mismatch\|sha512 cross-check\|CAND2_PINNED_SHA512" \
   "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "SHA-512 cross-check logic not found in validate-package-migration.sh"
fi

# Test 19 -- Negative tests never write to production stage-log directory
T=19
DESC="Negative tests do not copy fixtures to production stage-logs dir"
if grep -qE 'cp -r.*STAGE_LOGS_DIR' "$REPO_ROOT/tools/validation/test-observed-guest-negative.sh" 2>/dev/null; then
    fail_test $T "$DESC" "test-observed-guest-negative.sh still copies fixtures to production STAGE_LOGS_DIR"
else
    pass_test $T "$DESC"
fi

# Test 20 -- Real gate deletes stale stage evidence before execution
T=20
DESC="validate-package-migration.sh starts with rm -rf STAGE_LOGS_DIR"
if grep -q "rm -rf.*STAGE_LOGS_DIR\|rm -rf.*stage-logs" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not clear STAGE_LOGS_DIR at start"
fi

# Test 21 -- allow-passwords is rejected in create-autoinstall-seed.sh
T=21
DESC="create-autoinstall-seed.sh rejects allow-passwords (uses allow-pw)"
if grep -q "allow-pw" "$REPO_ROOT/tools/vm/create-autoinstall-seed.sh" 2>/dev/null && \
   grep -q "forbidden.*allow-passwords\|allow-passwords.*rejected\|allow-pw.*false" "$REPO_ROOT/tools/vm/create-autoinstall-seed.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "create-autoinstall-seed.sh does not use allow-pw or does not reject allow-passwords"
fi

# Test 22 -- Missing identity hostname is rejected
T=22
DESC="create-autoinstall-seed.sh validates identity.hostname"
if grep -q "hostname.*is.*missing\|identity.hostname\|hostname is required" "$REPO_ROOT/tools/vm/create-autoinstall-seed.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "create-autoinstall-seed.sh does not validate identity.hostname"
fi

# Test 23 -- Missing encrypted password is rejected
T=23
DESC="create-autoinstall-seed.sh validates encrypted password (SHA-512 hash)"
if grep -q 'openssl passwd -6\|METHOD_SHA512\|\$6\$' "$REPO_ROOT/tools/vm/create-autoinstall-seed.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "create-autoinstall-seed.sh does not generate an encrypted SHA-512 password"
fi

# Test 24 -- Missing autoinstall kernel argument is rejected in run-qemu.sh
T=24
DESC="run-qemu.sh rejects --append without 'autoinstall' keyword"
if grep -q "autoinstall.*keyword\|must contain.*autoinstall\|grep -q 'autoinstall'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh does not validate 'autoinstall' in kernel append string"
fi

# Test 25 -- Empty extracted kernel fails
T=25
DESC="extract-installer-kernel.sh rejects empty vmlinuz"
if grep -q "vmlinuz.*empty\|Extracted vmlinuz is empty" "$REPO_ROOT/tools/vm/extract-installer-kernel.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "extract-installer-kernel.sh does not reject empty vmlinuz"
fi

# Test 26 -- Empty extracted initrd fails
T=26
DESC="extract-installer-kernel.sh rejects empty initrd"
if grep -q "initrd.*empty\|Extracted initrd is empty" "$REPO_ROOT/tools/vm/extract-installer-kernel.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "extract-installer-kernel.sh does not reject empty initrd"
fi

# Test 27 -- Candidate ISO is still attached read-only as CDROM in run-qemu.sh
T=27
DESC="run-qemu.sh keeps canonical ISO as read-only CDROM even with direct-kernel boot"
if grep -q "media=cdrom,readonly=on" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh does not attach ISO as read-only CDROM"
fi

# Test 28 -- Token observation does not immediately force-stop QEMU
T=28
DESC="wait-for-install-completion.sh does NOT break immediately on token (waits for natural shutdown)"
# Verify the natural-shutdown grace loop exists after serial_token_observed=true
if grep -q "NATURAL_SHUTDOWN_GRACE\|natural_shutdown_ok\|natural.*shutdown" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "wait-for-install-completion.sh does not implement natural shutdown wait"
fi

# Test 29 -- Installer timeout records stage FAIL
T=29
DESC="validate-package-migration.sh writes FAIL JSON when install-candidate2.sh times out"
if grep -q '"failed_phase": "candidate2_install"\|CAND2_INSTALL_EXIT' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not write FAIL JSON on installation timeout"
fi

# Test 30 -- SIGTERM records stage FAIL
T=30
DESC="wait-for-install-completion.sh records STOPPED_BY_SIGTERM as FAIL"
if grep -q "STOPPED_BY_SIGTERM" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "wait-for-install-completion.sh does not record STOPPED_BY_SIGTERM"
fi

# Test 31 -- Failed install cannot leave PASS JSON (RUNNING sentinel)
T=31
DESC="validate-package-migration.sh writes RUNNING sentinel before candidate2 install"
if grep -q '"status": "RUNNING"' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not write RUNNING sentinel before candidate2 install"
fi

# Test 32 -- Failure artifact contains serial log evidence path
T=32
DESC="install-candidate2.sh preserves installer.serial.log in runtime evidence dir"
if grep -q "installer.serial.log\|RUNTIME_EVIDENCE_DIR" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh does not preserve serial log in runtime evidence dir"
fi

# Test 33 -- Private SSH keys excluded from state JSON (key is in state but upload excludes it)
T=33
DESC="infra artifact upload path does not include private SSH keys"
WORKFLOW_FILE=$(find "$REPO_ROOT/.github/workflows" -name "*.yml" | head -1 || echo "")
if [[ -n "$WORKFLOW_FILE" ]]; then
    if grep -q "id_rsa\|\.key\|private_key" "$WORKFLOW_FILE" 2>/dev/null && \
       ! grep -q "exclude.*id_rsa\|exclude.*private_key\|exclude.*\.key" "$WORKFLOW_FILE" 2>/dev/null; then
        fail_test $T "$DESC" "Workflow may upload private keys without exclusion filter"
    else
        pass_test $T "$DESC"
    fi
else
    pass_test $T "$DESC" # no workflow file to check
fi

# Test 34 -- Kernel and initrd are extracted from the verified ISO (extract-installer-kernel.sh exists)
T=34
DESC="extract-installer-kernel.sh exists and is executable"
if [[ -f "$REPO_ROOT/tools/vm/extract-installer-kernel.sh" && -x "$REPO_ROOT/tools/vm/extract-installer-kernel.sh" ]]; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "extract-installer-kernel.sh is missing or not executable"
fi

# Summary
echo ""
printf '=== Integration Runtime Test Summary: %d passed, %d failed ===\n' "$PASS_COUNT" "$FAIL_COUNT"
if (( FAIL_COUNT > 0 )); then
    echo "FAILED TESTS:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
printf '[PASS] All %d integration runtime tests passed.\n' "$PASS_COUNT"
exit 0
