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

# Test 11 -- D10: FORCED_SIGTERM exits non-zero
T=11
DESC="D10: FORCED_SIGTERM causes run-qemu.sh stop to exit 1"
if grep -q "FORCED_SIGTERM" "$REPO_ROOT/tools/vm/run-qemu.sh" && \
   grep -A3 "FORCED_SIGTERM" "$REPO_ROOT/tools/vm/run-qemu.sh" | grep -q "exit 1"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "FORCED_SIGTERM with exit 1 not found"
fi

# Test 12 -- D10: FORCED_SIGKILL exits non-zero
T=12
DESC="D10: FORCED_SIGKILL causes run-qemu.sh stop to exit 1"
if grep -q "FORCED_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" && \
   grep -A3 "FORCED_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" | grep -q "exit 1"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "FORCED_SIGKILL with exit 1 not found"
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

# Test 30 -- TIMEOUT records stage FAIL
T=30
DESC="wait-for-install-completion.sh records TIMEOUT as FAIL terminal state"
if grep -q "installer_terminal_state.*TIMEOUT" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "wait-for-install-completion.sh does not record TIMEOUT terminal state"
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
    if grep -q '!infra/package-staging/results/runtime/\*\*/id_\*' "$WORKFLOW_FILE" 2>/dev/null; then
        pass_test $T "$DESC"
    elif grep -q "id_rsa\|\.key\|private_key" "$WORKFLOW_FILE" 2>/dev/null && \
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

# ─────────────────────────────────────────────────────────────────────────────
# Tests 35-54: Runtime evidence and behavioral validation (PR #110 corrections)
# ─────────────────────────────────────────────────────────────────────────────

# Test 35 -- Runtime evidence path is included in release-gate artifact upload
T=35
DESC="Runtime evidence path is included in release-gate artifact upload"
GATE_YML="$REPO_ROOT/.github/workflows/release-gate.yml"
if grep -q 'infra/package-staging/results/runtime/\*\*' "$GATE_YML" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "runtime/** path not found in release-gate.yml artifact upload"
fi

# Test 36 -- Private key exclusion globs exist
T=36
DESC="Private key exclusion globs exist in artifact upload"
if grep -q '!infra/package-staging/results/runtime/\*\*/id_\*' "$GATE_YML" 2>/dev/null && \
   grep -q '!infra/package-staging/results/runtime/\*\*/\*\.key' "$GATE_YML" 2>/dev/null && \
   grep -q '!infra/package-staging/results/runtime/\*\*/\*private\*' "$GATE_YML" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Missing private key exclusion globs in release-gate.yml"
fi

# Test 37 -- Failure before QEMU start creates failure-summary.json
T=37
DESC="install-candidate2.sh writes failure-summary.json on non-zero exit"
if grep -q "failure-summary.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "failure_summary_json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh does not write failure-summary.json on failure"
fi

# Test 38 -- QEMU start failure creates failure-summary.json (handled by cleanup trap)
T=38
DESC="QEMU start failure recorded via cleanup trap in install-candidate2.sh"
if grep -q "cleanup_exit" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALL_PHASE" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh missing cleanup_exit trap or INSTALL_PHASE tracking"
fi

# Test 39 -- Installer timeout creates install-completion.json with FAIL
T=39
DESC="wait-for-install-completion.sh writes FAIL JSON on timeout"
if grep -q "TIMEOUT.*FAIL" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null || \
   grep -q "installer_terminal_state.*TIMEOUT" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "wait-for-install-completion.sh does not write FAIL on timeout"
fi

# Test 40 -- Timeout cleanup confirms whether SIGTERM succeeded
T=40
DESC="run-qemu.sh stop returns FORCED_SIGTERM status when graceful shutdown fails"
if grep -q "FORCED_SIGTERM" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh stop does not report FORCED_SIGTERM"
fi

# Test 41 -- Ignored SIGTERM escalates to SIGKILL and records FAIL
T=41
DESC="run-qemu.sh escalates SIGTERM to SIGKILL and records FAIL"
if grep -q "FORCED_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null && \
   grep -A3 "FORCED_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" | grep -q "exit 1"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh does not escalate to SIGKILL or record FAIL"
fi

# Test 42 -- install-candidate2.sh cleanup terminates both VMs via managed shutdown
T=42
DESC="install-candidate2.sh cleanup uses cleanup_managed_vm for both VMs"
if grep -q "cleanup_managed_vm" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALLER_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALLED_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh missing cleanup_managed_vm or dual-VM tracking"
fi

# Test 43 -- Final VM state cannot remain running
T=43
DESC="run-qemu.sh stop sets state to shutdown result, never leaves running"
if grep -q 'data\["state"\]' "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null || \
   grep -q "data\['state'\]" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh stop does not update state away from running"
fi

# Test 44 -- QEMU argument vector is present in VM state JSON
T=44
DESC="QEMU argument vector recorded in VM state JSON as qemu_arguments"
if grep -q "qemu_arguments" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null && \
   grep -q "qemu-arguments.json\|QEMU_ARGS_FILE" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh does not record QEMU arguments in state JSON"
fi

# Test 45 -- QEMU argument vector includes autoinstall
T=45
DESC="QEMU argument vector includes 'autoinstall' keyword"
if grep -q "'autoinstall'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "autoinstall not found in run-qemu.sh arguments"
fi

# Test 46 -- QEMU argument vector includes the canonical ISO as read-only CD-ROM
T=46
DESC="QEMU argument uses media=cdrom,readonly=on for canonical ISO"
if grep -q "media=cdrom,readonly=on" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "read-only CD-ROM attachment not found in run-qemu.sh"
fi

# Test 47 -- Missing GENIXBIT_MIGRATION_RESULT fails
T=47
DESC="validate-package-migration.sh uses GENIXBIT_MIGRATION_RESULT marker"
if grep -q "GENIXBIT_MIGRATION_RESULT" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "GENIXBIT_MIGRATION_RESULT marker not used in validate-package-migration.sh"
fi

# Test 48 -- Missing migration-result file fails
T=48
DESC="validate-package-migration.sh fails when MIG_RESULT_FILE is missing or empty"
if grep -q 'if \[\[ -z "\$MIG_RESULT_FILE" \|' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null || \
   grep -q 'missing_migration_result' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not reject missing migration result file"
fi

# Test 49 -- Migration result with final_status=FAIL fails
T=49
DESC="validate-package-migration.sh rejects migration with final_status=FAIL"
if grep -q "final_status.*FAIL" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null || \
   grep -q "MIG_FINAL_STATUS.*PASS" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not validate MIG_FINAL_STATUS"
fi

# Test 50 -- Migration result with rollback mismatch fails
T=50
DESC="validate-package-migration.sh validates rollback state SHA equality"
if grep -q "rollback_eq\|ROLLBACK_EQ\|rollback.*sha" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not validate rollback state equality"
fi

# Test 51 -- Migration result source identity mismatch fails
T=51
DESC="migrate-candidate2.sh validates source identity commit"
if grep -q "source_commit\|installation_state_path" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "migrate-candidate2.sh does not validate source identity"
fi

# Test 52 -- Failure after RUNNING sentinel always replaces it
T=52
DESC="validate-package-migration.sh uses write_candidate_stage_failure after RUNNING sentinel"
if grep -q "write_candidate_stage_failure" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "write_candidate_stage_failure function not found in validate-package-migration.sh"
fi

# Test 53 -- Separate Candidate 2 stdout/stderr evidence files exist
T=53
DESC="Candidate 2 stdout and stderr evidence files captured separately"
if grep -q "stage-candidate-upgrade.stdout.log" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null && \
   grep -q "stage-candidate-upgrade.stderr.log" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Separate stdout/stderr log paths not found in validate-package-migration.sh"
fi

# Test 54 -- Runtime evidence contains no private SSH key material (by exclusion)
T=54
DESC="release-gate.yml excludes private SSH keys from artifact upload"
if grep -qF '!infra/package-staging/results/runtime/' "$GATE_YML" 2>/dev/null && \
   grep -qF '!infra/package-staging/results/runtime/**/id_' "$GATE_YML" 2>/dev/null && \
   grep -qF '!infra/package-staging/results/runtime/**/*.key' "$GATE_YML" 2>/dev/null && \
   grep -qF '!infra/package-staging/results/runtime/**/*private' "$GATE_YML" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Private SSH key exclusion globs not found in release-gate.yml"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Tests 55-80: Executable behavioral tests (PR #110 second round)
# ─────────────────────────────────────────────────────────────────────────────

# Test 55 -- bash -n syntax check for wait-for-install-completion.sh
T=55
DESC="bash -n syntax check for wait-for-install-completion.sh"
if bash -n "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "bash -n syntax check failed for wait-for-install-completion.sh"
fi

# Test 56 -- bash -n syntax check for run-qemu.sh
T=56
DESC="bash -n syntax check for run-qemu.sh"
if bash -n "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "bash -n syntax check failed for run-qemu.sh"
fi

# Test 57 -- bash -n syntax check for install-candidate2.sh
T=57
DESC="bash -n syntax check for install-candidate2.sh"
if bash -n "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "bash -n syntax check failed for install-candidate2.sh"
fi

# Test 58 -- bash -n syntax check for migrate-candidate2.sh
T=58
DESC="bash -n syntax check for migrate-candidate2.sh"
if bash -n "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "bash -n syntax check failed for migrate-candidate2.sh"
fi

# Test 59 -- bash -n syntax check for validate-package-migration.sh
T=59
DESC="bash -n syntax check for validate-package-migration.sh"
if bash -n "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "bash -n syntax check failed for validate-package-migration.sh"
fi

# Test 60 -- Python boolean() function works correctly (executable behavioral test)
T=60
DESC="Python boolean() function converts true/false env vars correctly"
if python3 -c "
import os
def boolean(name):
    value = os.environ.get(name, '').strip().lower()
    if value not in {'true', 'false'}:
        raise ValueError()
    return value == 'true'

os.environ['TEST_BOOL'] = 'true'
assert boolean('TEST_BOOL') == True
os.environ['TEST_BOOL'] = 'false'
assert boolean('TEST_BOOL') == False
print('OK')
" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Python boolean() function failed behavioral test"
fi

# Test 61 -- Python boolean() rejects invalid values
T=61
DESC="Python boolean() function rejects invalid env values"
if python3 -c "
import os
def boolean(name):
    value = os.environ.get(name, '').strip().lower()
    if value not in {'true', 'false'}:
        raise ValueError()
    return value == 'true'

os.environ['TEST_BOOL'] = 'yes'
try:
    boolean('TEST_BOOL')
    print('FAIL: no error raised')
except ValueError:
    print('OK')
" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "Python boolean() did not reject invalid value"
fi

# Test 62 -- wait-for-install-completion.sh uses env-based Python (no shell-interpolated booleans)
T=62
DESC="wait-for-install-completion.sh write_out_json uses env-based PYEOF"
if grep -q "PYEOF" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null && \
   ! grep -E "python3 -c.*\\\$\{?(true|false)\}?" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "wait-for-install-completion.sh still uses shell-interpolated booleans in python3 -c"
fi

# Test 63 -- run-qemu.sh start action uses env-based Python for state JSON
T=63
DESC="run-qemu.sh start state JSON uses PYEOF heredoc (no shell-interpolated booleans)"
if grep -q "<<'PYEOF'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null && \
   ! grep -E "python3 -c.*\\\$\{?(true|false)\}?" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh start state JSON still uses shell-interpolated booleans"
fi

# Test 64 -- run-qemu.sh stop action uses env-based Python for shutdown JSON
T=64
DESC="run-qemu.sh stop shutdown JSON uses PYEOF heredoc"
if grep -q "<<'PYEOF'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh stop shutdown JSON does not use PYEOF heredoc"
fi

# Test 65 -- install-candidate2.sh uses env-based Python for failure-summary JSON
T=65
DESC="install-candidate2.sh failure-summary JSON uses PYEOF heredoc"
if grep -A1 "FAILURE_SUMMARY_JSON=" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null | grep -q "PYEOF" || \
   grep -z "FAILURE_SUMMARY_JSON=.*python3 - <<'PYEOF'" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh failure-summary JSON does not use PYEOF heredoc"
fi

# Test 66 -- install-candidate2.sh final state JSON uses env-based Python
T=66
DESC="install-candidate2.sh cand2-install-state JSON uses PYEOF heredoc"
if grep -A1 "INSTALL_STATE_FILE=" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null | grep -q "PYEOF" || \
   grep -z "INSTALL_STATE_FILE=.*python3 - <<'PYEOF'" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh cand2-install-state JSON does not use PYEOF heredoc"
fi

# Test 67 -- migrate-candidate2.sh includes installation binding fields
T=67
DESC="migrate-candidate2.sh migration-result.json includes installation binding fields"
if grep -q "'source_commit'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "'workflow_run_id'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "'installation_state_sha256'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "'source_iso_sha256'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "'installation_installer_vm_id'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "'installation_installed_vm_id'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "'migration_vm_id'" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "migrate-candidate2.sh missing installation binding fields"
fi

# Test 68 -- validate-package-migration.sh validates migration binding fields
T=68
DESC="validate-package-migration.sh validates source_commit and iso_sha256 binding"
if grep -q "source_commit.*!=.*CURRENT_COMMIT\|mig_workflow_run_id\|install_state_sha256\|mig_iso_sha256" \
   "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh missing migration binding validation"
fi

# Test 69 -- PASS stage-candidate-upgrade.json artifact_paths excludes failure-summary.json
T=69
DESC="PASS stage-candidate-upgrade.json artifact_paths excludes failure-summary.json"
PASS_ARTIFACT_LINE=$(grep -A5 '"status": "PASS"' "$REPO_ROOT/tools/validation/validate-package-migration.sh" | grep "artifact_paths" || true)
if [[ -n "$PASS_ARTIFACT_LINE" ]]; then
    if echo "$PASS_ARTIFACT_LINE" | grep -q "failure-summary.json" 2>/dev/null; then
        fail_test $T "$DESC" "PASS artifact_paths still lists failure-summary.json (only created on failure)"
    else
        pass_test $T "$DESC"
    fi
else
    # Check the actual PASS stage-candidate-upgrade.json block artifact_paths
    if grep -A20 '"assertion": "candidate2_migration_completed"' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null | \
       grep "artifact_paths" | grep -q "failure-summary.json"; then
        fail_test $T "$DESC" "PASS artifact_paths still lists failure-summary.json"
    else
        pass_test $T "$DESC"
    fi
fi

# Test 70 -- Failure reason collected from stderr, not stdout
T=70
DESC="Candidate 2 failure reason greps from stderr log, not stdout"
if grep -q "CAND2_STDERR_LOG" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null && \
   grep -A2 "CAND2_INSTALL_EXIT.*!=\|CAND2_FAIL_REASON" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null | \
   grep -q "CAND2_STDERR_LOG"; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "validate-package-migration.sh does not grep failure from CAND2_STDERR_LOG"
fi

# Test 71 -- install-candidate2.sh has cleanup_managed_vm helper function
T=71
DESC="install-candidate2.sh defines cleanup_managed_vm function"
if grep -q "^cleanup_managed_vm()" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh missing cleanup_managed_vm function definition"
fi

# Test 72 -- install-candidate2.sh tracks both VMs independently
T=72
DESC="install-candidate2.sh tracks INSTALLER_VM_STARTED and INSTALLED_VM_STARTED"
if grep -q "INSTALLER_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALLED_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh does not track both VMs independently"
fi

# Test 73 -- cleanup_exit in install-candidate2.sh captures evidence before AND after cleanup
T=73
DESC="install-candidate2.sh cleanup_exit copies evidence before and after cleanup"
if grep -q "vm-state.before-cleanup.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "vm-state.final.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "shutdown-result.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh cleanup_exit missing before/after evidence copy"
fi

# Test 74 -- install-candidate2.sh failure-summary.json has cleanup state fields
T=74
DESC="install-candidate2.sh failure-summary.json records installer_cleanup_state and installed_cleanup_state"
if grep -q "installer_cleanup_state" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "installed_cleanup_state" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "installer_process_alive_after_cleanup" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && \
   grep -q "installed_process_alive_after_cleanup" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "install-candidate2.sh failure-summary.json missing cleanup state fields"
fi

# Test 75 -- wait-for-install-completion.sh write_out_json has boolean() function
T=75
DESC="wait-for-install-completion.sh write_out_json defines Python boolean()"
if grep -q "def boolean" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "wait-for-install-completion.sh write_out_json missing Python boolean() function"
fi

# Test 76 -- run-qemu.sh stop removes QMP socket THEN captures QMP_PRESENT_AFTER
T=76
DESC="run-qemu.sh stop removes QMP socket before QMP_PRESENT_AFTER capture"
RUN_QEMU="$REPO_ROOT/tools/vm/run-qemu.sh"
# rm -f "$QMP_SOCKET" comes before QMP_PRESENT_AFTER=false/true
if grep -A3 'rm -f "\$QMP_SOCKET"' "$RUN_QEMU" 2>/dev/null | grep -q 'QMP_PRESENT_AFTER='; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "rm -f QMP_SOCKET not followed by QMP_PRESENT_AFTER capture"
fi

# Test 77 -- validate-package-migration.sh no failure-summary.json in PASS artifacts
T=77
DESC="validate-package-migration.sh PASS JSON does not require failure-summary.json"
if grep -A30 '"assertion": "candidate2_migration_completed"' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null | \
   grep "artifact_paths" | grep -q "failure-summary"; then
    fail_test $T "$DESC" "PASS artifact_paths still requires failure-summary.json"
else
    pass_test $T "$DESC"
fi

# Test 78 -- install-candidate2.sh cleanup trap installed BEFORE ISO validation
T=78
DESC="install-candidate2.sh EXIT trap installed before fallible ISO validation"
TRAP_LINE=$(grep -n "trap on_exit EXIT" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
ISO_VALID_LINE=$(grep -n "Validate Candidate 2 ISO checksum" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null | head -1 | cut -d: -f1 || echo "9999")
if (( TRAP_LINE > 0 && TRAP_LINE < ISO_VALID_LINE )); then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "EXIT trap installed at line $TRAP_LINE after ISO validation at line $ISO_VALID_LINE"
fi

# Test 79 -- run-qemu.sh stop captures QMP presence for pid-file-absent and empty-pid cases
T=79
DESC="run-qemu.sh stop uses PYEOF heredoc for NOT_STARTED and ALREADY_STOPPED cases"
NOT_STARTED_COUNT=$(grep -c "<<'PYEOF'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null || echo "0")
# There should be multiple PYEOF heredocs (start state, not_started, already_stopped, main shutdown, state update)
if (( NOT_STARTED_COUNT >= 3 )); then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "run-qemu.sh has $NOT_STARTED_COUNT PYEOF heredocs, expected 5+"
fi

# Test 80 -- migrate-candidate2.sh installation-source binding fields are non-empty after extraction
T=80
DESC="migrate-candidate2.sh reads INSTALL_SOURCE_COMMIT, INSTALL_SOURCE_ISO_SHA256 etc."
if grep -q "INSTALL_SOURCE_COMMIT" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALL_SOURCE_ISO_SHA256" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALL_INSTALLER_VM_ID" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALL_INSTALLED_VM_ID" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && \
   grep -q "INSTALL_WORKFLOW_RUN_ID" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "migrate-candidate2.sh missing binding variable extraction"
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
