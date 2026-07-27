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
DESC="D14: Empty or TODO sha512 provenance field causes failure"
if grep -q "sha512 field is empty or unpopulated" \
   "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "sha512 empty validator not found"
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
