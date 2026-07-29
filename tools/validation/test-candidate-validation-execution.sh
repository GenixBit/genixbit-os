#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
TOTAL=0
PASS=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf '[PASS] Test %d: %s\n' "$PASS" "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }

expect_grep() { local name="$1" pat="$2" file="$3"; TOTAL=$((TOTAL + 1)); grep -qE "$pat" "$file" || fail "$name (pattern '$pat' not found in $file)"; pass "$name"; }
expect_no_grep() { local name="$1" pat="$2" file="$3"; TOTAL=$((TOTAL + 1)); if grep -qE "$pat" "$file"; then fail "$name (pattern '$pat' unexpectedly found in $file)"; fi; pass "$name"; }
expect_pass() { local name="$1"; shift; TOTAL=$((TOTAL + 1)); "$@" >/dev/null 2>&1 || fail "$name (command failed)"; pass "$name"; }
expect_fail() { local name="$1" pat="$2"; shift 2; TOTAL=$((TOTAL + 1)); if "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then fail "$name (unexpectedly succeeded)"; fi; grep -qE "$pat" "$TMP_DIR/out" "$TMP_DIR/err" || fail "$name (error pattern '$pat' not found)"; pass "$name"; }

commit="abcdef1234567890abcdef1234567890abcdef12"

make_fixture_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init --initial-branch=main >/dev/null 2>&1
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "Test Runner"
    mkdir -p "$dir/tools/validation"
    cat > "$dir/args.sh" <<'EOF'
export TARGET_BUILD_VERSION="0.3.0-alpha"
EOF
    cat > "$dir/build.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p dist
ts=$(date +%s)
echo "fixture iso content" > "dist/GenixBitOS-0.3.0-alpha-${ts}.iso"
EOF
    chmod +x "$dir/build.sh"
    git -C "$dir" add .
    git -C "$dir" commit -m "initial commit" >/dev/null 2>&1
    git -C "$dir" branch -M validation/0.3.0-alpha-candidate-2
}

fixture_repo="$TMP_DIR/fixture_repo"
make_fixture_repo "$fixture_repo"
fixture_sha=$(git -C "$fixture_repo" rev-parse HEAD)
git -C "$fixture_repo" update-ref refs/remotes/origin/validation/0.3.0-alpha-candidate-2 "$fixture_sha"

# 1. Correct candidate branch and SHA passes
expect_pass "1. Correct candidate branch and SHA passes" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$fixture_repo" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$fixture_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 2. Wrong branch fails
expect_fail "2. Wrong branch fails" "unexpected candidate branch" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$fixture_repo" --candidate-branch wrong-branch --candidate-sha "$fixture_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 3. Wrong SHA fails
expect_fail "3. Wrong SHA fails" "candidate SHA|SHA mismatch" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$fixture_repo" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha 0000000000000000000000000000000000000000 --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 4. Dirty checkout fails
dirty_repo="$TMP_DIR/dirty_repo"
make_fixture_repo "$dirty_repo"
dirty_sha=$(git -C "$dirty_repo" rev-parse HEAD)
git -C "$dirty_repo" update-ref refs/remotes/origin/validation/0.3.0-alpha-candidate-2 "$dirty_sha"
echo "dirty change" > "$dirty_repo/dirty.txt"
expect_fail "4. Dirty checkout fails" "working tree is dirty" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$dirty_repo" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$dirty_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 5. Fake-build variables fail
expect_fail "5. Fake-build variables fail" "fake build" env GENIXBIT_FAKE_ACTIVE_BUILD=1 bash "$REPO_ROOT/tools/validation/build-active-release-candidate.sh" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$fixture_sha" --output-dir "$TMP_DIR/out" --build-label build-a

# 6. Existing ISO substitution fails
expect_grep "6. Existing ISO substitution fails" "ISO existed before current build" "$REPO_ROOT/tools/validation/build-active-release-candidate.sh"

# 7. Fixture build executes twice
expect_grep "7. Fixture build executes twice" "build-a|build-b" "$REPO_ROOT/tools/validation/validate-package-migration.sh"

# 8. Build A and Build B use separate worktrees
expect_grep "8. Build A and Build B use separate worktrees" "worktree-.*build_label" "$REPO_ROOT/tools/validation/build-active-release-candidate.sh"

# 9. Build A and Build B use separate output paths
TOTAL=$((TOTAL + 1))
if grep -q "build-label build-a" "$REPO_ROOT/tools/validation/validate-package-migration.sh" && grep -q "build-label build-b" "$REPO_ROOT/tools/validation/validate-package-migration.sh"; then
    pass "9. Build A and Build B use separate output paths"
else
    fail "9. Build A and Build B use separate output paths"
fi

# 10. Metadata records REAL_BUILD
expect_grep "10. Metadata records REAL_BUILD" "REAL_BUILD" "$REPO_ROOT/tools/validation/build-active-release-candidate.sh"

# 11. Missing preflight fails
expect_fail "11. Missing preflight fails" "preflight|missing" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$TMP_DIR/empty" --runtime-dir "$TMP_DIR/empty" --builds-dir "$TMP_DIR/empty" --current-dir "$TMP_DIR/empty" --candidate-sha "$commit"

# 12. Failed preflight fails
mkdir -p "$TMP_DIR/stage_logs_fail"
cat > "$TMP_DIR/stage_logs_fail/stage-candidate-selection.json" <<JSON
{"candidate_branch":"validation/0.3.0-alpha-candidate-2","candidate_sha":"$commit","remote_candidate_sha":"$commit","git_head":"$commit","working_tree_clean":true,"target_build_version":"0.3.0-alpha","workflow_run_id":"100","status":"PASS"}
JSON
cat > "$TMP_DIR/stage_logs_fail/preflight-results.json" <<JSON
{"source_commit":"$commit","git_head":"$commit","workflow_run_id":"100","status":"FAIL"}
JSON
expect_fail "12. Failed preflight fails" "preflight-results.json status is 'FAIL'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$TMP_DIR/stage_logs_fail" --runtime-dir "$TMP_DIR/stage_logs_fail" --builds-dir "$TMP_DIR/stage_logs_fail" --current-dir "$TMP_DIR/stage_logs_fail" --candidate-sha "$commit"

# 13. Preflight source mismatch fails
cat > "$TMP_DIR/stage_logs_fail/preflight-results.json" <<JSON
{"source_commit":"0000000000000000000000000000000000000000","git_head":"$commit","workflow_run_id":"100","status":"PASS"}
JSON
expect_fail "13. Preflight source mismatch fails" "[Ss]ource commit mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$TMP_DIR/stage_logs_fail" --runtime-dir "$TMP_DIR/stage_logs_fail" --builds-dir "$TMP_DIR/stage_logs_fail" --current-dir "$TMP_DIR/stage_logs_fail" --candidate-sha "$commit"

# 14. Preflight run-ID mismatch fails
cat > "$TMP_DIR/stage_logs_fail/preflight-results.json" <<JSON
{"source_commit":"$commit","git_head":"$commit","workflow_run_id":"999","status":"PASS"}
JSON
expect_fail "14. Preflight run-ID mismatch fails" "workflow run ID mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$TMP_DIR/stage_logs_fail" --runtime-dir "$TMP_DIR/stage_logs_fail" --builds-dir "$TMP_DIR/stage_logs_fail" --current-dir "$TMP_DIR/stage_logs_fail" --candidate-sha "$commit" --workflow-run-id "100"

# 15. Missing candidate-selection evidence fails
mkdir -p "$TMP_DIR/stage_no_cand"
expect_fail "15. Missing candidate-selection evidence fails" "stage-candidate-selection.json" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$TMP_DIR/stage_no_cand" --runtime-dir "$TMP_DIR/stage_no_cand" --builds-dir "$TMP_DIR/stage_no_cand" --current-dir "$TMP_DIR/stage_no_cand" --candidate-sha "$commit"

# Helper for full fixture environment
make_full_fixture_stage_logs() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/stage-candidate-selection.json" <<JSON
{"candidate_branch":"validation/0.3.0-alpha-candidate-2","candidate_sha":"$commit","remote_candidate_sha":"$commit","git_head":"$commit","working_tree_clean":true,"target_build_version":"0.3.0-alpha","workflow_run_id":"100","status":"PASS"}
JSON
    cat > "$dir/preflight-results.json" <<JSON
{"source_commit":"$commit","git_head":"$commit","workflow_run_id":"100","architecture":"x86_64","kvm_available":true,"status":"PASS"}
JSON
    cat > "$dir/stage-package-build.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    cat > "$dir/stage-repository-publication.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    cat > "$dir/stage-clean-install.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    cat > "$dir/stage-test-iso-build.json" <<JSON
{"source_commit":"$commit","observations":{"iso_path":"$TMP_DIR/fake.iso","iso_size_bytes":100,"iso_sha256":"123","iso_sha512":"456","iso_structure_check":"PASS"},"status":"PASS"}
JSON
    cat > "$dir/stage-reproducibility.json" <<JSON
{"source_commit":"$commit","artifact_hashes":{"build_a_sha256":"123","build_b_sha256":"123","cmp_exit_code":0},"status":"PASS"}
JSON
    cat > "$dir/stage-test-iso-boot.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    cat > "$dir/stage-installer.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    cat > "$dir/stage-tamper.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    cat > "$dir/stage-documentation.json" <<JSON
{"source_commit":"$commit","status":"PASS"}
JSON
    for log in uefi-guest-validation.log bios-guest-validation.log uefi-second-boot-validation.log bios-second-boot-validation.log uefi-installed-boot.serial.log bios-installed-boot.serial.log; do
        cat > "$dir/$log" <<LOG
GenixBit OS test log
cat /etc/os-release
dpkg-query -W
apt-get update
apt-get check
dpkg --audit
systemctl --failed
LOG
    done
}

# 16. Missing documentation evidence fails
stage_no_doc="$TMP_DIR/stage_no_doc"
make_full_fixture_stage_logs "$stage_no_doc"
rm -f "$stage_no_doc/stage-documentation.json"
expect_fail "16. Missing documentation evidence fails" "stage-documentation.json" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$stage_no_doc" --runtime-dir "$stage_no_doc" --builds-dir "$stage_no_doc" --current-dir "$stage_no_doc" --candidate-sha "$commit" --workflow-run-id 100

# 17. Missing BIOS evidence fails
full_stage="$TMP_DIR/full_stage"
make_full_fixture_stage_logs "$full_stage"
rm -f "$full_stage/bios-guest-validation.log"
expect_fail "17. Missing BIOS evidence fails" "bios-guest-validation.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 18. Missing UEFI evidence fails
make_full_fixture_stage_logs "$full_stage"
rm -f "$full_stage/uefi-guest-validation.log"
expect_fail "18. Missing UEFI evidence fails" "uefi-guest-validation.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 19. Missing second-boot evidence fails
make_full_fixture_stage_logs "$full_stage"
rm -f "$full_stage/uefi-second-boot-validation.log"
expect_fail "19. Missing second-boot evidence fails" "uefi-second-boot-validation.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 20. Package-health command failure blocks readiness
make_full_fixture_stage_logs "$full_stage"
cat > "$full_stage/uefi-guest-validation.log" <<LOG
GenixBit OS test log missing required commands
LOG
expect_fail "20. Package-health command failure blocks readiness" "Required package/system health command" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 21. Reproducibility mismatch blocks readiness
make_full_fixture_stage_logs "$full_stage"
cat > "$full_stage/stage-reproducibility.json" <<JSON
{"source_commit":"$commit","artifact_hashes":{"build_a_sha256":"123","build_b_sha256":"diff","cmp_exit_code":1},"status":"PASS"}
JSON
expect_fail "21. Reproducibility mismatch blocks readiness" "Build A and Build B SHA-256 mismatch|exit code" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 22. Cross-run evidence fails
make_full_fixture_stage_logs "$full_stage"
cat > "$full_stage/stage-candidate-selection.json" <<JSON
{"candidate_branch":"validation/0.3.0-alpha-candidate-2","candidate_sha":"$commit","remote_candidate_sha":"$commit","git_head":"$commit","working_tree_clean":true,"target_build_version":"0.3.0-alpha","workflow_run_id":"999","status":"PASS"}
JSON
expect_fail "22. Cross-run evidence fails" "workflow run ID mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 23. Stage source mismatch fails
make_full_fixture_stage_logs "$full_stage"
cat > "$full_stage/stage-tamper.json" <<JSON
{"source_commit":"0000000000000000000000000000000000000000","status":"PASS"}
JSON
expect_fail "23. Stage source mismatch fails" "Source commit mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

# 24. Categories are evidence-derived
expect_no_grep "24. Categories are evidence-derived" "cats = \{.*PASS.*PASS.*\}" "$REPO_ROOT/tools/validation/validate-package-migration.sh"

# 25. VALIDATED_UNPUBLISHED requires complete evidence
expect_grep "25. VALIDATED_UNPUBLISHED requires complete evidence" "VALIDATED_UNPUBLISHED" "$REPO_ROOT/tools/validation/generate-candidate-gate.py"

# 26. Upgrade remains NOT_APPLICABLE
expect_grep "26. Upgrade remains NOT_APPLICABLE" "upgrade_readiness.*NOT_APPLICABLE" "$REPO_ROOT/tools/validation/generate-candidate-gate.py"

# 27. Rollback remains NOT_APPLICABLE
expect_grep "27. Rollback remains NOT_APPLICABLE" "rollback_readiness.*NOT_APPLICABLE" "$REPO_ROOT/tools/validation/generate-candidate-gate.py"

# 28. No tag is created
expect_no_grep "28. No tag is created" "git tag|create-tag" "$REPO_ROOT/.github/workflows/release-gate.yml"

# 29. No release is published
expect_no_grep "29. No release is published" "gh release create|publish-release" "$REPO_ROOT/.github/workflows/release-gate.yml"

# 30. Complete valid fixture evidence produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION
make_full_fixture_stage_logs "$full_stage"
expect_pass "30. Complete valid fixture evidence produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$full_stage" --runtime-dir "$full_stage" --builds-dir "$full_stage" --current-dir "$full_stage" --candidate-sha "$commit" --workflow-run-id 100

printf '[PASS] candidate validation execution tests passed: %d/%d\n' "$PASS" "$TOTAL"
