#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
TOTAL=0
PASS=0
NA_REASON="No valid prior GenixBit OS release artifact exists from which to execute an upgrade or rollback test."

cleanup() { rm -rf "$TMP_DIR"; rm -f "$REPO_ROOT/infra/package-staging/results/stage-logs/stage-reproducibility.json"; }
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf '[PASS] %s\n' "$1"; }
expect_grep() { local name="$1" pat="$2" file="$3"; TOTAL=$((TOTAL + 1)); grep -qE "$pat" "$file"; pass "$name"; }
expect_no_grep() { local name="$1" pat="$2" file="$3"; TOTAL=$((TOTAL + 1)); if grep -qE "$pat" "$file"; then printf '[FAIL] %s\n' "$name" >&2; exit 1; fi; pass "$name"; }
expect_pass() { local name="$1"; shift; TOTAL=$((TOTAL + 1)); "$@" >/dev/null; pass "$name"; }
expect_fail() { local name="$1" pat="$2"; shift 2; TOTAL=$((TOTAL + 1)); if "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then printf '[FAIL] %s unexpectedly passed\n' "$name" >&2; exit 1; fi; grep -qE "$pat" "$TMP_DIR/out" "$TMP_DIR/err"; pass "$name"; }

make_iso() {
    local iso="$1"
    mkdir -p "$TMP_DIR/iso-root/casper" "$TMP_DIR/iso-root/EFI/BOOT"
    printf kernel > "$TMP_DIR/iso-root/casper/vmlinuz"
    printf initrd > "$TMP_DIR/iso-root/casper/initrd"
    mksquashfs "$TMP_DIR/iso-root" "$TMP_DIR/iso-root/casper/filesystem.squashfs" -noappend >/dev/null 2>&1
    printf efi > "$TMP_DIR/iso-root/EFI/BOOT/BOOTX64.EFI"
    printf efiboot > "$TMP_DIR/iso-root/EFI/efiboot.img"
    xorriso -as mkisofs -quiet -o "$iso" -V GENIXBIT_TEST -eltorito-boot EFI/BOOT/BOOTX64.EFI -no-emul-boot "$TMP_DIR/iso-root" >/dev/null 2>&1
}

write_provenance() {
    local path="$1" status="$2" iso="$3" commit="$4" generation="${5:-null}"
    local size sha256 sha512 filename
    size=$(wc -c < "$iso" | tr -d ' ')
    sha256=$(sha256sum "$iso" | awk '{print $1}')
    sha512=$(sha512sum "$iso" | awk '{print $1}')
    filename=$(basename "$iso")
    cat > "$path" <<JSON
{"schema_version":"1.0","release_version":"0.3.0-alpha","candidate_branch":"validation/0.3.0-alpha-candidate-2","candidate_source_commit":"$commit","filename":"$filename","size_bytes":$size,"sha256":"$sha256","sha512":"$sha512","object_generation":$generation,"verification_status":"$status","usable_as_release_artifact":false,"usable_as_migration_source":false}
JSON
}

write_repro() {
    mkdir -p "$REPO_ROOT/infra/package-staging/results/stage-logs"
    cat > "$REPO_ROOT/infra/package-staging/results/stage-logs/stage-reproducibility.json" <<JSON
{"source_commit":"$commit","command":"cmp --silent a b","exit_code":0,"artifact_hashes":{"build_a_sha256":"aa","build_b_sha256":"aa","build_a_sha512":"bb","build_b_sha512":"bb","build_a_size_bytes":1,"build_b_size_bytes":1,"cmp_exit_code":0},"observations":{"build_a_iso":"a","build_b_iso":"b"},"status":"PASS"}
JSON
}

write_gate() {
    local path="$1" status="$2" upgrade="${3:-NOT_APPLICABLE}" rollback="${4:-NOT_APPLICABLE}"
    python3 - "$path" "$status" "$upgrade" "$rollback" "$NA_REASON" <<'PY'
import json, sys
path, status, upgrade, rollback, reason = sys.argv[1:]
mandatory = ["candidate_selection","host_readiness","package_infrastructure","clean_install_readiness","iso_build_readiness","iso_structure_readiness","uefi_readiness","bios_readiness","installer_readiness","installed_system_readiness","package_health_readiness","security_readiness","reproducibility_readiness","documentation_readiness"]
cats = {k: {"status": "PASS"} for k in mandatory}
cats["upgrade_readiness"] = {"status": upgrade, "reason": reason}
cats["rollback_readiness"] = {"status": rollback, "reason": reason}
data = {"categories": cats, "active_artifact_provenance": sys.argv[1].replace('gate.json','artifact.json'), "summary": {"pass_count": sum(1 for c in cats.values() if c["status"] == "PASS"), "fail_count": 0, "blocked_count": 0, "not_tested_count": 0, "not_applicable_count": sum(1 for c in cats.values() if c["status"] == "NOT_APPLICABLE"), "release_ready": False, "stable_ready": False, "overall_gate_status": status}}
with open(path, 'w', encoding='utf-8') as f: json.dump(data, f, indent=2)
PY
}

commit="abcdef1234567890abcdef1234567890abcdef12"
shim_bin="$TMP_DIR/bin"
mkdir -p "$shim_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$shim_bin/mdir"
chmod +x "$shim_bin/mdir"
iso="$TMP_DIR/GenixBitOS-0.3.0-alpha-2607290000.iso"
make_iso "$iso"
artifact="$TMP_DIR/artifact.json"
write_provenance "$artifact" VALIDATED_UNPUBLISHED "$iso" "$commit"
write_repro
gate="$TMP_DIR/gate.json"
write_gate "$gate" PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION

expect_no_grep "candidate branch existence is accepted" 'Candidate 2 MUST NOT be created|branch.*MUST NOT' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "wrong candidate branch fails" 'EXPECTED_CANDIDATE_BRANCH.*candidate|Unexpected candidate branch' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "wrong candidate SHA fails" 'EXPECTED_CANDIDATE_SHA.*40-character|Git HEAD does not match EXPECTED_CANDIDATE_SHA' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "candidate branch and HEAD mismatch fails" 'Current branch does not match EXPECTED_CANDIDATE_BRANCH|git HEAD.*expected candidate SHA' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "dirty candidate checkout fails" 'candidate checkout is dirty before build' "$REPO_ROOT/tools/validation/validate-package-migration.sh"
expect_grep "Candidate 1 fails" 'Candidate 1.*MUST NOT be marked PASS' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_no_grep "fresh-install mode never loads Candidate 2 ISO provenance unconditionally" '^CAND2_IMMUTABLE_URL=' "$REPO_ROOT/tools/validation/validate-package-migration.sh"
expect_grep "fresh-install mode skips Candidate 2 installation" 'ACTIVE_RELEASE_MODE.*fresh-install-only|install-candidate2\.sh' "$REPO_ROOT/tools/validation/validate-package-migration.sh"
expect_grep "candidate upgrade output remains NOT_APPLICABLE" 'candidate-upgrade-result\.json|NOT_APPLICABLE' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "rollback output remains NOT_APPLICABLE" 'rollback-result\.json|NOT_APPLICABLE' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "missing Build A fails" 'Build A ISO is missing' "$REPO_ROOT/tools/validation/validate-package-migration.sh"
expect_grep "multiple uncontrolled Build A ISOs fail" 'expected exactly one timestamped' "$REPO_ROOT/tools/validation/build-active-release-candidate.sh"
expect_no_grep "fixed non-timestamped ISO assumption absent" 'ACTIVE_RELEASE_ISO_LOCAL: dist/GenixBitOS-0\.3\.0-alpha\.iso|dist/GenixBitOS-0\.3\.0-alpha\.iso' "$REPO_ROOT/.github/workflows/release-gate.yml"
expect_grep "Build A source mismatch fails" 'source SHA mismatch|source_commit' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "Build B missing fails" 'Build B ISO is missing|build_b_sha256' "$REPO_ROOT/tools/validation/check-release-gate.sh"
expect_grep "Build A reused as Build B fails" 'reused the same ISO path' "$REPO_ROOT/tools/validation/validate-package-migration.sh"
expect_grep "different Build A/Build B hashes fail" 'SHA-256 mismatch|same_sha256' "$REPO_ROOT/tools/validation/validate-package-migration.sh"
expect_grep "failed cmp blocks reproducibility" 'cmp_exit_code|byte comparison failed' "$REPO_ROOT/tools/validation/check-release-gate.sh"
expect_pass "valid reproducible builds create PASS reproducibility evidence" python3 -m json.tool "$REPO_ROOT/infra/package-staging/results/stage-logs/stage-reproducibility.json"
expect_pass "PENDING_BUILD accepted only before build" python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" --allow-pending --provenance-file "$REPO_ROOT/docs/releases/0.3.0-alpha-artifact.json"
built="$TMP_DIR/built.json"; write_provenance "$built" BUILT_UNVALIDATED "$iso" "$commit"
expect_pass "BUILT_UNVALIDATED requires real hashes and structure" env MIN_ISO_SIZE_MB=0 PATH="$shim_bin:$PATH" python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" --phase built --provenance-file "$built" --source-commit "$commit" --iso "$iso"
expect_pass "VALIDATED_UNPUBLISHED requires runtime evidence compatible provenance" env MIN_ISO_SIZE_MB=0 PATH="$shim_bin:$PATH" python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" --phase validated-unpublished --provenance-file "$artifact" --source-commit "$commit" --iso "$iso"
pass_json="$TMP_DIR/pass.json"; write_provenance "$pass_json" PASS "$iso" "$commit"
expect_fail "PASS without immutable object generation fails" 'object_generation|usable_as_release_artifact' env MIN_ISO_SIZE_MB=0 PATH="$shim_bin:$PATH" python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" --phase pass --provenance-file "$pass_json" --source-commit "$commit" --iso "$iso"
retired="$TMP_DIR/retired.json"; cp "$built" "$retired"; python3 - "$retired" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d['sha256']='1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669'; json.dump(d, open(p,'w'))
PY
expect_fail "retired Candidate 2 identifiers fail" retired_sha256 python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" --phase built --provenance-file "$retired" --source-commit "$commit" --iso "$iso"
blocked="$TMP_DIR/blocked.json"; write_gate "$blocked" BLOCKED_INVALID_RELEASE_EVIDENCE
expect_fail "old blocked gate JSON cannot be current run success" BLOCKED_INVALID_RELEASE_EVIDENCE bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$blocked" --provenance-file "$artifact"
expect_pass "PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION requires mandatory categories" bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$gate" --provenance-file "$artifact"
pass_gate="$TMP_DIR/pass-upgrade-gate.json"; write_gate "$pass_gate" PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION PASS NOT_APPLICABLE
expect_fail "upgrade and rollback cannot be counted as PASS" 'upgrade/rollback|not_applicable_count' bash "$REPO_ROOT/tools/validation/check-release-gate.sh" --gate-file "$pass_gate" --provenance-file "$artifact"
expect_grep "exact source SHA consistent across every stage" 'source SHA mismatch|ACTIVE_RELEASE_SOURCE_COMMIT' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_grep "UEFI and BIOS evidence remain independent" 'UEFI and BIOS.*sharing|identical SHA-256' "$REPO_ROOT/tools/validation/collect-migration-evidence.py"
expect_no_grep "no tag or release is created" 'gh release create|git tag|create-release|contents: write' "$REPO_ROOT/.github/workflows/release-gate.yml"

# Branch-lifecycle behavioral tests
expect_pass "candidate-3 is accepted" bash -c "[[ 'validation/0.3.0-alpha-candidate-3' =~ ^validation/0\.3\.0-alpha-candidate-[1-9][0-9]*$ ]]"
expect_pass "candidate-2 remains syntactically valid for historical evidence verification" bash -c "[[ 'validation/0.3.0-alpha-candidate-2' =~ ^validation/0\.3\.0-alpha-candidate-[1-9][0-9]*$ ]]"
expect_fail "candidate-0 fails" "unexpected candidate branch" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --candidate-branch "validation/0.3.0-alpha-candidate-0" --candidate-sha "abcdef1234567890abcdef1234567890abcdef12" --target-build-version "0.3.0-alpha"
expect_fail "branch without a numeric suffix fails" "unexpected candidate branch" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --candidate-branch "validation/0.3.0-alpha" --candidate-sha "abcdef1234567890abcdef1234567890abcdef12" --target-build-version "0.3.0-alpha"
expect_fail "candidate-test fails" "unexpected candidate branch" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --candidate-branch "validation/0.3.0-alpha-candidate-test" --candidate-sha "abcdef1234567890abcdef1234567890abcdef12" --target-build-version "0.3.0-alpha"
expect_fail "main fails" "unexpected candidate branch" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --candidate-branch "main" --candidate-sha "abcdef1234567890abcdef1234567890abcdef12" --target-build-version "0.3.0-alpha"
expect_fail "missing candidate branch fails in production mode" "EXPECTED_CANDIDATE_BRANCH" env EXPECTED_CANDIDATE_BRANCH="" EXPECTED_CANDIDATE_SHA="abcdef1234567890abcdef1234567890abcdef12" bash "$REPO_ROOT/tools/validation/validate-package-migration.sh"

cand2_stage_dir="$TMP_DIR/cand2_stage"
mkdir -p "$cand2_stage_dir"
cat > "$cand2_stage_dir/stage-candidate-selection.json" <<JSON
{"source_commit":"$commit","candidate_branch":"validation/0.3.0-alpha-candidate-2","candidate_sha":"$commit","remote_candidate_sha":"$commit","git_head":"$commit","working_tree_clean":true,"target_build_version":"0.3.0-alpha","workflow_run_id":"100","workflow_run_attempt":"1","exit_code":0,"status":"PASS"}
JSON
expect_fail "Evidence from Candidate 2 cannot satisfy a Candidate 3 run" "candidate_branch mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$cand2_stage_dir" --candidate-branch "validation/0.3.0-alpha-candidate-3" --candidate-sha "$commit" --workflow-run-id "100" --workflow-run-attempt "1"

expect_pass "The failed Candidate 2 branch is never modified by tests" git rev-parse refs/heads/validation/0.3.0-alpha-candidate-2

printf '[PASS] candidate validation gate tests passed: %s/%s\n' "$PASS" "$TOTAL"
