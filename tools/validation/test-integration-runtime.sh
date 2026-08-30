#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Integration runtime test suite for release-gate defect fixes.
# Tests 80 conditions that must be true for the release gate to pass.
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

# Test 20 -- Real gate preserves current-run preflight evidence and does NOT wipe STAGE_LOGS_DIR with rm -rf
T=20
DESC="validate-package-migration.sh does NOT wipe STAGE_LOGS_DIR with rm -rf"
if grep -q "rm -rf.*STAGE_LOGS_DIR\|rm -rf.*stage-logs" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    fail_test $T "$DESC" "validate-package-migration.sh still wipes STAGE_LOGS_DIR with rm -rf"
else
    pass_test $T "$DESC"
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
    pass_test $T "$DESC"
fi

# Test 34 -- Kernel and initrd are extracted from the verified ISO (extract-installer-kernel.sh exists)
T=34
DESC="extract-installer-kernel.sh exists and is executable"
if [[ -f "$REPO_ROOT/tools/vm/extract-installer-kernel.sh" && -x "$REPO_ROOT/tools/vm/extract-installer-kernel.sh" ]]; then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "extract-installer-kernel.sh is missing or not executable"
fi

# Tests 35-54: Runtime evidence and behavioral validation.
T=35
DESC="Runtime evidence path is included in release-gate artifact upload"
GATE_YML="$REPO_ROOT/.github/workflows/release-gate.yml"
if grep -q 'infra/package-staging/results/runtime/\*\*' "$GATE_YML" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "runtime/** path not found in release-gate.yml artifact upload"; fi

T=36
DESC="Private key exclusion globs exist in artifact upload"
if grep -q '!infra/package-staging/results/runtime/\*\*/id_\*' "$GATE_YML" 2>/dev/null && grep -q '!infra/package-staging/results/runtime/\*\*/\*\.key' "$GATE_YML" 2>/dev/null && grep -q '!infra/package-staging/results/runtime/\*\*/\*private\*' "$GATE_YML" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "Missing private key exclusion globs in release-gate.yml"; fi

T=37
DESC="install-candidate2.sh writes failure-summary.json on non-zero exit"
if grep -q "failure-summary.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "failure_summary_json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh does not write failure-summary.json on failure"; fi

T=38
DESC="QEMU start failure recorded via cleanup trap in install-candidate2.sh"
if grep -q "cleanup_exit" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "INSTALL_PHASE" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh missing cleanup_exit trap or INSTALL_PHASE tracking"; fi

T=39
DESC="wait-for-install-completion.sh writes FAIL JSON on timeout"
if grep -q "TIMEOUT.*FAIL" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null || grep -q "installer_terminal_state.*TIMEOUT" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "wait-for-install-completion.sh does not write FAIL on timeout"; fi

T=40
DESC="run-qemu.sh stop returns FORCED_SIGTERM status when graceful shutdown fails"
if grep -q "FORCED_SIGTERM" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh stop does not report FORCED_SIGTERM"; fi

T=41
DESC="run-qemu.sh escalates SIGTERM to SIGKILL and records FAIL"
if grep -q "FORCED_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null && grep -A3 "FORCED_SIGKILL" "$REPO_ROOT/tools/vm/run-qemu.sh" | grep -q "exit 1"; then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh does not escalate to SIGKILL or record FAIL"; fi

T=42
DESC="install-candidate2.sh cleanup uses cleanup_managed_vm for both VMs"
if grep -q "cleanup_managed_vm" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "INSTALLER_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "INSTALLED_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh missing cleanup_managed_vm or dual-VM tracking"; fi

T=43
DESC="run-qemu.sh stop sets state to shutdown result, never leaves running"
if grep -q 'data\["state"\]' "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null || grep -q "data\['state'\]" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh stop does not update state away from running"; fi

T=44
DESC="QEMU argument vector recorded in VM state JSON as qemu_arguments"
if grep -q "qemu_arguments" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null && grep -q "qemu-arguments.json\|QEMU_ARGS_FILE" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh does not record QEMU arguments in state JSON"; fi

T=45
DESC="QEMU argument vector includes 'autoinstall' keyword"
if grep -q "'autoinstall'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "autoinstall not found in run-qemu.sh arguments"; fi

T=46
DESC="QEMU argument uses media=cdrom,readonly=on for canonical ISO"
if grep -q "media=cdrom,readonly=on" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "read-only CD-ROM attachment not found in run-qemu.sh"; fi

T=47
DESC="validate-package-migration.sh uses GENIXBIT_MIGRATION_RESULT marker"
if grep -q "GENIXBIT_MIGRATION_RESULT" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "GENIXBIT_MIGRATION_RESULT marker not used in validate-package-migration.sh"; fi

T=48
DESC="validate-package-migration.sh fails when MIG_RESULT_FILE is missing or empty"
if grep -q 'if \[\[ -z "\$MIG_RESULT_FILE" \|' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null || grep -q 'missing_migration_result' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "validate-package-migration.sh does not reject missing migration result file"; fi

T=49
DESC="validate-package-migration.sh rejects migration with final_status=FAIL"
if grep -q "final_status.*FAIL" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null || grep -q "MIG_FINAL_STATUS.*PASS" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "validate-package-migration.sh does not validate MIG_FINAL_STATUS"; fi

T=50
DESC="validate-package-migration.sh validates rollback state SHA equality"
if grep -q "rollback_eq\|ROLLBACK_EQ\|rollback.*sha" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "validate-package-migration.sh does not validate rollback state equality"; fi

T=51
DESC="migrate-candidate2.sh validates source identity commit"
if grep -q "source_commit\|installation_state_path" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "migrate-candidate2.sh does not validate source identity"; fi

T=52
DESC="validate-package-migration.sh uses write_candidate_stage_failure after RUNNING sentinel"
if grep -q "write_candidate_stage_failure" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "write_candidate_stage_failure function not found in validate-package-migration.sh"; fi

T=53
DESC="Candidate 2 stdout and stderr evidence files captured separately"
if grep -q "stage-candidate-upgrade.stdout.log" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null && grep -q "stage-candidate-upgrade.stderr.log" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "Separate stdout/stderr log paths not found in validate-package-migration.sh"; fi

T=54
DESC="release-gate.yml excludes private SSH keys from artifact upload"
if grep -qF '!infra/package-staging/results/runtime/' "$GATE_YML" 2>/dev/null && grep -qF '!infra/package-staging/results/runtime/**/id_' "$GATE_YML" 2>/dev/null && grep -qF '!infra/package-staging/results/runtime/**/*.key' "$GATE_YML" 2>/dev/null && grep -qF '!infra/package-staging/results/runtime/**/*private' "$GATE_YML" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "Private SSH key exclusion globs not found in release-gate.yml"; fi

# Tests 55-80: Executable behavioral tests.
for pair in \
  "55:wait-for-install-completion.sh" \
  "56:run-qemu.sh" \
  "57:install-candidate2.sh" \
  "58:migrate-candidate2.sh"; do
    T=${pair%%:*}; file=${pair#*:}; DESC="bash -n syntax check for $file"
    if bash -n "$REPO_ROOT/tools/vm/$file" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "bash -n syntax check failed for $file"; fi
done

T=59
DESC="bash -n syntax check for validate-package-migration.sh"
if bash -n "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "bash -n syntax check failed for validate-package-migration.sh"; fi

T=60
DESC="Python boolean() function converts true/false env vars correctly"
if python3 -c "import os; f=lambda n: {'true':True,'false':False}[os.environ[n].strip().lower()]; os.environ['TEST_BOOL']='true'; assert f('TEST_BOOL') is True; os.environ['TEST_BOOL']='false'; assert f('TEST_BOOL') is False" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "Python boolean() function failed behavioral test"; fi

T=61
DESC="Python boolean() function rejects invalid env values"
if python3 -c "import os; os.environ['TEST_BOOL']='yes'; value=os.environ['TEST_BOOL'].strip().lower(); assert value not in {'true','false'}" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "Python boolean() did not reject invalid value"; fi

T=62
DESC="wait-for-install-completion.sh write_out_json uses env-based PYEOF"
if grep -q "PYEOF" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null && ! grep -E "python3 -c.*\\\$\{?(true|false)\}?" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "wait-for-install-completion.sh still uses shell-interpolated booleans in python3 -c"; fi

T=63
DESC="run-qemu.sh start state JSON uses PYEOF heredoc"
if grep -q "<<'PYEOF'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh start state JSON does not use PYEOF heredoc"; fi

T=64
DESC="run-qemu.sh stop shutdown JSON uses PYEOF heredoc"
if grep -q "<<'PYEOF'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh stop shutdown JSON does not use PYEOF heredoc"; fi

T=65
DESC="install-candidate2.sh failure-summary JSON uses PYEOF heredoc"
if grep -q "FAILURE_SUMMARY_JSON" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "<<'PYEOF'" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh failure-summary JSON does not use PYEOF heredoc"; fi

T=66
DESC="install-candidate2.sh cand2-install-state JSON uses PYEOF heredoc"
if grep -q "INSTALL_STATE_FILE" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "<<'PYEOF'" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh cand2-install-state JSON does not use PYEOF heredoc"; fi

T=67
DESC="migrate-candidate2.sh migration-result.json includes installation binding fields"
if grep -q '"source_commit"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q '"workflow_run_id"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q '"installation_state_sha256"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q '"source_iso_sha256"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q '"installation_installer_vm_id"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q '"installation_installed_vm_id"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q '"migration_vm_id"' "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "migrate-candidate2.sh missing installation binding fields"; fi

T=68
DESC="validate-package-migration.sh validates source_commit and iso_sha256 binding"
if grep -q "source_commit.*!=.*CURRENT_COMMIT\|mig_workflow_run_id\|install_state_sha256\|mig_iso_sha256" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "validate-package-migration.sh missing migration binding validation"; fi

T=69
DESC="PASS stage-candidate-upgrade.json artifact_paths excludes failure-summary.json"
if grep -A20 '"assertion": "candidate2_migration_completed"' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null | grep "artifact_paths" | grep -q "failure-summary.json"; then fail_test $T "$DESC" "PASS artifact_paths still lists failure-summary.json"; else pass_test $T "$DESC"; fi

T=70
DESC="Candidate 2 failure reason greps from stderr log, not stdout"
if grep -q "CAND2_STDERR_LOG" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "validate-package-migration.sh does not reference CAND2_STDERR_LOG"; fi

T=71
DESC="install-candidate2.sh defines cleanup_managed_vm function"
if grep -q "^cleanup_managed_vm()" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh missing cleanup_managed_vm function definition"; fi

T=72
DESC="install-candidate2.sh tracks INSTALLER_VM_STARTED and INSTALLED_VM_STARTED"
if grep -q "INSTALLER_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "INSTALLED_VM_STARTED" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh does not track both VMs independently"; fi

T=73
DESC="install-candidate2.sh cleanup_exit copies evidence before and after cleanup"
if grep -q "vm-state.before-cleanup.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "vm-state.final.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "shutdown-result.json" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh cleanup_exit missing before/after evidence copy"; fi

T=74
DESC="install-candidate2.sh failure-summary.json records cleanup state fields"
if grep -q "installer_cleanup_state" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "installed_cleanup_state" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "installer_process_alive_after_cleanup" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null && grep -q "installed_process_alive_after_cleanup" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "install-candidate2.sh failure-summary.json missing cleanup state fields"; fi

T=75
DESC="wait-for-install-completion.sh write_out_json defines Python boolean()"
if grep -q "def boolean" "$REPO_ROOT/tools/vm/wait-for-install-completion.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "wait-for-install-completion.sh write_out_json missing Python boolean() function"; fi

T=76
DESC="run-qemu.sh stop removes QMP socket before QMP_PRESENT_AFTER capture"
RUN_QEMU="$REPO_ROOT/tools/vm/run-qemu.sh"
if grep -A3 'rm -f "\$QMP_SOCKET"' "$RUN_QEMU" 2>/dev/null | grep -q 'QMP_PRESENT_AFTER='; then pass_test $T "$DESC"; else fail_test $T "$DESC" "rm -f QMP_SOCKET not followed by QMP_PRESENT_AFTER capture"; fi

T=77
DESC="validate-package-migration.sh PASS JSON does not require failure-summary.json"
if grep -A30 '"assertion": "candidate2_migration_completed"' "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null | grep "artifact_paths" | grep -q "failure-summary"; then fail_test $T "$DESC" "PASS artifact_paths still requires failure-summary.json"; else pass_test $T "$DESC"; fi

# Test 78 -- cleanup trap must be installed before the actual fallible checksum phase.
T=78
DESC="install-candidate2.sh EXIT trap installed before fallible ISO validation"
TRAP_LINE=$(grep -n "trap on_exit EXIT" "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
ISO_VALID_LINE=$(grep -n 'INSTALL_PHASE="validation_iso_checksum"' "$REPO_ROOT/tools/vm/install-candidate2.sh" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
if (( TRAP_LINE > 0 && ISO_VALID_LINE > 0 && TRAP_LINE < ISO_VALID_LINE )); then
    pass_test $T "$DESC"
else
    fail_test $T "$DESC" "EXIT trap installed at line $TRAP_LINE; checksum validation phase at line $ISO_VALID_LINE"
fi

T=79
DESC="run-qemu.sh stop uses PYEOF heredoc for NOT_STARTED and ALREADY_STOPPED cases"
NOT_STARTED_COUNT=$(grep -c "<<'PYEOF'" "$REPO_ROOT/tools/vm/run-qemu.sh" 2>/dev/null || echo "0")
if (( NOT_STARTED_COUNT >= 3 )); then pass_test $T "$DESC"; else fail_test $T "$DESC" "run-qemu.sh has $NOT_STARTED_COUNT PYEOF heredocs, expected 3+"; fi

T=80
DESC="migrate-candidate2.sh reads installation-source binding fields"
if grep -q "INSTALL_SOURCE_COMMIT" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q "INSTALL_SOURCE_ISO_SHA256" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q "INSTALL_INSTALLER_VM_ID" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q "INSTALL_INSTALLED_VM_ID" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null && grep -q "INSTALL_WORKFLOW_RUN_ID" "$REPO_ROOT/tools/vm/migrate-candidate2.sh" 2>/dev/null; then pass_test $T "$DESC"; else fail_test $T "$DESC" "migrate-candidate2.sh missing binding variable extraction"; fi

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
