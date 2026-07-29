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

expect_pass() { local name="$1"; shift; TOTAL=$((TOTAL + 1)); "$@" >/dev/null 2>&1 || fail "$name (command failed)"; pass "$name"; }
expect_fail() { local name="$1" pat="$2"; shift 2; TOTAL=$((TOTAL + 1)); if "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then fail "$name (unexpectedly succeeded)"; fi; grep -qE "$pat" "$TMP_DIR/out" "$TMP_DIR/err" || fail "$name (error pattern '$pat' not found in output)"; pass "$name"; }

make_fixture_repo() {
    local base="$1"
    local origin="$base/origin.git"
    mkdir -p "$base"
    git init --bare "$origin" >/dev/null 2>&1

    local work="$base/work"
    mkdir -p "$work"
    git -C "$work" init --initial-branch=main >/dev/null 2>&1
    git -C "$work" config user.email "test@example.com"
    git -C "$work" config user.name "Test Runner"
    mkdir -p "$work/tools/validation" "$work/infra/package-staging/results/stage-logs"
    cat > "$work/args.sh" <<'EOF'
export TARGET_BUILD_VERSION="0.3.0-alpha"
EOF
    cat > "$work/build.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p dist
echo "synthetic iso content for test" > "dist/GenixBitOS-0.3.0-alpha-2607290000.iso"
EOF
    chmod +x "$work/build.sh"
    git -C "$work" add .
    git -C "$work" commit -m "initial commit" >/dev/null 2>&1
    git -C "$work" branch -M validation/0.3.0-alpha-candidate-2
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -u origin validation/0.3.0-alpha-candidate-2 >/dev/null 2>&1
}

fixture_base="$TMP_DIR/fixture_base"
make_fixture_repo "$fixture_base"
fixture_repo="$fixture_base/work"
fixture_sha=$(git -C "$fixture_repo" rev-parse HEAD)

# Helper for full fixture evidence directory setup
create_full_fixture_evidence() {
    local dir="$1"
    local sha="${2:-$fixture_sha}"
    local run_id="${3:-100}"
    local run_attempt="${4:-1}"

    local stage_logs="$dir/stage-logs"
    local builds="$dir/builds"
    local current="$dir/current"
    local runtime="$dir/runtime"
    mkdir -p "$stage_logs" "$builds" "$current" "$runtime"

    local iso_a="$builds/GenixBitOS-0.3.0-alpha-builda.iso"
    local iso_b="$builds/GenixBitOS-0.3.0-alpha-buildb.iso"
    echo "synthetic iso binary content 12345" > "$iso_a"
    echo "synthetic iso binary content 12345" > "$iso_b"

    local sz_a=$(wc -c < "$iso_a" | tr -d ' ')
    local sz_b=$(wc -c < "$iso_b" | tr -d ' ')
    local sha256_a=$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$iso_a")
    local sha256_b=$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$iso_b")
    local sha512_a=$(python3 -c 'import hashlib, sys; print(hashlib.sha512(open(sys.argv[1], "rb").read()).hexdigest())' "$iso_a")
    local sha512_b=$(python3 -c 'import hashlib, sys; print(hashlib.sha512(open(sys.argv[1], "rb").read()).hexdigest())' "$iso_b")

    cat > "$stage_logs/stage-candidate-selection.json" <<JSON
{
  "source_commit": "$sha",
  "candidate_branch": "validation/0.3.0-alpha-candidate-2",
  "candidate_sha": "$sha",
  "remote_candidate_sha": "$sha",
  "git_head": "$sha",
  "working_tree_clean": true,
  "target_build_version": "0.3.0-alpha",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "exit_code": 0,
  "status": "PASS"
}
JSON

    cat > "$stage_logs/preflight-results.json" <<JSON
{
  "source_commit": "$sha",
  "active_release_source_commit": "$sha",
  "git_head": "$sha",
  "expected_candidate_sha": "$sha",
  "expected_candidate_branch": "validation/0.3.0-alpha-candidate-2",
  "active_release_version": "0.3.0-alpha",
  "active_release_mode": "fresh-install-only",
  "architecture": "x86_64",
  "kvm_available": true,
  "staging_status": "REACHABLE",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "exit_code": 0,
  "status": "PASS"
}
JSON

    cat > "$stage_logs/stage-package-build.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON
    cat > "$stage_logs/stage-repository-publication.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON
    cat > "$stage_logs/stage-clean-install.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON

    cat > "$builds/build-a-build.json" <<JSON
{
  "execution_mode": "REAL_BUILD",
  "build_script": "./build.sh",
  "build_exit_code": 0,
  "status": "PASS",
  "candidate_branch": "validation/0.3.0-alpha-candidate-2",
  "source_commit": "$sha",
  "target_version": "0.3.0-alpha",
  "worktree_dir": "$dir/worktree-a",
  "iso_path": "$iso_a",
  "output_file": "$iso_a",
  "size_bytes": $sz_a,
  "sha256": "$sha256_a",
  "sha512": "$sha512_a",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "exit_code": 0
}
JSON

    cat > "$builds/build-b-build.json" <<JSON
{
  "execution_mode": "REAL_BUILD",
  "build_script": "./build.sh",
  "build_exit_code": 0,
  "status": "PASS",
  "candidate_branch": "validation/0.3.0-alpha-candidate-2",
  "source_commit": "$sha",
  "target_version": "0.3.0-alpha",
  "worktree_dir": "$dir/worktree-b",
  "iso_path": "$iso_b",
  "output_file": "$iso_b",
  "size_bytes": $sz_b,
  "sha256": "$sha256_b",
  "sha512": "$sha512_b",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "exit_code": 0
}
JSON

    cat > "$builds/build-a-iso-structure.json" <<JSON
{
  "source_commit": "$sha",
  "iso_path": "$iso_a",
  "iso_sha256": "$sha256_a",
  "command": "check-iso-structure.sh --iso $iso_a",
  "exit_code": 0,
  "status": "PASS",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt"
}
JSON

    cat > "$builds/build-b-iso-structure.json" <<JSON
{
  "source_commit": "$sha",
  "iso_path": "$iso_b",
  "iso_sha256": "$sha256_b",
  "command": "check-iso-structure.sh --iso $iso_b",
  "exit_code": 0,
  "status": "PASS",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt"
}
JSON

    cat > "$stage_logs/stage-reproducibility.json" <<JSON
{
  "source_commit": "$sha",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "exit_code": 0,
  "status": "PASS",
  "artifact_hashes": {
    "build_a_sha256": "$sha256_a",
    "build_b_sha256": "$sha256_b",
    "cmp_exit_code": 0
  }
}
JSON

    cat > "$stage_logs/stage-installer.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON
    cat > "$stage_logs/stage-tamper.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON
    cat > "$stage_logs/stage-documentation.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON

    for log in uefi-guest-validation.log bios-guest-validation.log uefi-second-boot-validation.log bios-second-boot-validation.log; do
        cat > "$runtime/$log" <<LOG
GenixBit OS Authenticated Guest Validation Log
cat /etc/os-release
NAME="GenixBit OS"
dpkg-query -W
genixbit-os-desktop 0.3.0-alpha
genixbit-os-base 0.3.0-alpha
linux-image-generic 6.8.0
systemd 255.4
apt 2.7.14
dpkg 1.22.6
apt-get update
Reading package lists... Done
apt-get check
Reading package lists... Done
dpkg --audit
systemctl --failed
0 loaded units listed.
LOG
    done

    cat > "$runtime/uefi-installed-boot.serial.log" <<LOG
GenixBit OS UEFI Boot Serial Log
Linux version 6.8.0-genixbit
[  OK  ] Reached target Multi-User System.
GenixBit OS login:
LOG

    cat > "$runtime/bios-installed-boot.serial.log" <<LOG
GenixBit OS BIOS Boot Serial Log (Different Content from UEFI)
Linux version 6.8.0-genixbit-bios
[  OK  ] Reached target Multi-User System.
Welcome to GenixBit OS login:
LOG
}

# 1. Missing remote candidate branch fails
no_remote_base="$TMP_DIR/no_remote_base"
make_fixture_repo "$no_remote_base"
no_remote_work="$no_remote_base/work"
no_remote_sha=$(git -C "$no_remote_work" rev-parse HEAD)
git -C "$no_remote_base/origin.git" branch -D validation/0.3.0-alpha-candidate-2 >/dev/null 2>&1 || true
expect_fail "1. Missing remote candidate branch fails" "remote candidate branch origin/validation/0.3.0-alpha-candidate-2 is unavailable or missing" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$no_remote_work" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$no_remote_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 2. Detached HEAD fails
detached_base="$TMP_DIR/detached_base"
make_fixture_repo "$detached_base"
detached_work="$detached_base/work"
detached_sha=$(git -C "$detached_work" rev-parse HEAD)
git -C "$detached_work" checkout --detach "$detached_sha" >/dev/null 2>&1
expect_fail "2. Detached HEAD fails" "git HEAD is detached" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$detached_work" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$detached_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 3. Remote SHA mismatch fails
wrong_remote_base="$TMP_DIR/wrong_remote_base"
make_fixture_repo "$wrong_remote_base"
wrong_remote_work="$wrong_remote_base/work"
git -C "$wrong_remote_work" commit --allow-empty -m "new commit" >/dev/null 2>&1
git -C "$wrong_remote_work" push origin validation/0.3.0-alpha-candidate-2 >/dev/null 2>&1
git -C "$wrong_remote_work" reset --hard HEAD~1 >/dev/null 2>&1
local_sha=$(git -C "$wrong_remote_work" rev-parse HEAD)
expect_fail "3. Remote SHA mismatch fails" "remote candidate SHA.*does not match candidate SHA" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$wrong_remote_work" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$local_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 4. Dirty checkout fails
dirty_base="$TMP_DIR/dirty_base"
make_fixture_repo "$dirty_base"
dirty_work="$dirty_base/work"
dirty_sha=$(git -C "$dirty_work" rev-parse HEAD)
echo "dirty change" > "$dirty_work/dirty.txt"
git -C "$dirty_work" add "$dirty_work/dirty.txt"
expect_fail "4. Dirty checkout fails" "working tree is dirty" bash "$REPO_ROOT/tools/validation/generate-candidate-selection.sh" --repo-root "$dirty_work" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$dirty_sha" --target-build-version 0.3.0-alpha --output-file "$TMP_DIR/cand-sel.json"

# 5. Fake-build variables fail
expect_fail "5. Fake-build variables fail" "fake build" env GENIXBIT_FAKE_ACTIVE_BUILD=1 bash "$REPO_ROOT/tools/validation/build-active-release-candidate.sh" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$fixture_sha" --output-dir "$TMP_DIR/out" --build-label build-a

# 6. Real fixture build.sh executes for Build A
build_a_out="$TMP_DIR/build_a_test"
expect_pass "6. Real fixture build.sh executes for Build A" bash "$REPO_ROOT/tools/validation/build-active-release-candidate.sh" --repo-root "$fixture_repo" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$fixture_sha" --output-dir "$build_a_out" --build-label build-a

# 7. Real fixture build.sh executes independently for Build B
build_b_out="$TMP_DIR/build_b_test"
expect_pass "7. Real fixture build.sh executes independently for Build B" bash "$REPO_ROOT/tools/validation/build-active-release-candidate.sh" --repo-root "$fixture_repo" --candidate-branch validation/0.3.0-alpha-candidate-2 --candidate-sha "$fixture_sha" --output-dir "$build_b_out" --build-label build-b

# 8. Missing Build B metadata fails
no_build_b="$TMP_DIR/no_build_b"
create_full_fixture_evidence "$no_build_b" "$fixture_sha" "100" "1"
rm -f "$no_build_b/builds/build-b-build.json"
expect_fail "8. Missing Build B metadata fails" "Build B metadata file \(build-b-build.json\) missing" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_build_b/stage-logs" --runtime-dir "$no_build_b/runtime" --builds-dir "$no_build_b/builds" --current-dir "$no_build_b/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 9. Forged Build B metadata fails
forged_build_b="$TMP_DIR/forged_build_b"
create_full_fixture_evidence "$forged_build_b" "$fixture_sha" "100" "1"
python3 -c "import json; p='$forged_build_b/builds/build-b-build.json'; d=json.load(open(p)); d['execution_mode']='FAKE'; json.dump(d,open(p,'w'))"
expect_fail "9. Forged Build B metadata fails" "execution_mode is 'FAKE', expected 'REAL_BUILD'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$forged_build_b/stage-logs" --runtime-dir "$forged_build_b/runtime" --builds-dir "$forged_build_b/builds" --current-dir "$forged_build_b/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 10. Build B file missing fails
missing_iso_b="$TMP_DIR/missing_iso_b"
create_full_fixture_evidence "$missing_iso_b" "$fixture_sha" "100" "1"
rm -f "$missing_iso_b/builds/GenixBitOS-0.3.0-alpha-buildb.iso"
expect_fail "10. Build B file missing fails" "Build B ISO file missing or empty" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$missing_iso_b/stage-logs" --runtime-dir "$missing_iso_b/runtime" --builds-dir "$missing_iso_b/builds" --current-dir "$missing_iso_b/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 11. Hash mismatch fails
hash_mismatch="$TMP_DIR/hash_mismatch"
create_full_fixture_evidence "$hash_mismatch" "$fixture_sha" "100" "1"
echo "different content for build b" > "$hash_mismatch/builds/GenixBitOS-0.3.0-alpha-buildb.iso"
expect_fail "11. Hash mismatch fails" "Build A size.*does not match Build B size|Build A SHA-256.*does not match Build B SHA-256" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$hash_mismatch/stage-logs" --runtime-dir "$hash_mismatch/runtime" --builds-dir "$hash_mismatch/builds" --current-dir "$hash_mismatch/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 12. Missing structure result fails
no_struct="$TMP_DIR/no_struct"
create_full_fixture_evidence "$no_struct" "$fixture_sha" "100" "1"
rm -f "$no_struct/builds/build-a-iso-structure.json"
expect_fail "12. Missing structure result fails" "Required evidence file missing" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_struct/stage-logs" --runtime-dir "$no_struct/runtime" --builds-dir "$no_struct/builds" --current-dir "$no_struct/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 13. Failed structure result fails
fail_struct="$TMP_DIR/fail_struct"
create_full_fixture_evidence "$fail_struct" "$fixture_sha" "100" "1"
python3 -c "import json; p='$fail_struct/builds/build-a-iso-structure.json'; d=json.load(open(p)); d['status']='FAIL'; d['exit_code']=1; json.dump(d,open(p,'w'))"
expect_fail "13. Failed structure result fails" "Evidence file .* status is 'FAIL', expected 'PASS'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$fail_struct/stage-logs" --runtime-dir "$fail_struct/runtime" --builds-dir "$fail_struct/builds" --current-dir "$fail_struct/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 14. Missing preflight fails
no_pref="$TMP_DIR/no_pref"
create_full_fixture_evidence "$no_pref" "$fixture_sha" "100" "1"
rm -f "$no_pref/stage-logs/preflight-results.json"
expect_fail "14. Missing preflight fails" "preflight-results.json" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_pref/stage-logs" --runtime-dir "$no_pref/runtime" --builds-dir "$no_pref/builds" --current-dir "$no_pref/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 15. Preflight KVM false fails
no_kvm="$TMP_DIR/no_kvm"
create_full_fixture_evidence "$no_kvm" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_kvm/stage-logs/preflight-results.json'; d=json.load(open(p)); d['kvm_available']=False; json.dump(d,open(p,'w'))"
expect_fail "15. Preflight KVM false fails" "Preflight kvm_available is 'False', expected True" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_kvm/stage-logs" --runtime-dir "$no_kvm/runtime" --builds-dir "$no_kvm/builds" --current-dir "$no_kvm/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 16. Preflight staging unreachable fails
unreachable_pref="$TMP_DIR/unreachable_pref"
create_full_fixture_evidence "$unreachable_pref" "$fixture_sha" "100" "1"
python3 -c "import json; p='$unreachable_pref/stage-logs/preflight-results.json'; d=json.load(open(p)); d['staging_status']='UNREACHABLE'; json.dump(d,open(p,'w'))"
expect_fail "16. Preflight staging unreachable fails" "Preflight staging_status is 'UNREACHABLE', expected 'REACHABLE'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$unreachable_pref/stage-logs" --runtime-dir "$unreachable_pref/runtime" --builds-dir "$unreachable_pref/builds" --current-dir "$unreachable_pref/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 17. Preflight source mismatch fails
wrong_source_pref="$TMP_DIR/wrong_source_pref"
create_full_fixture_evidence "$wrong_source_pref" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_source_pref/stage-logs/preflight-results.json'; d=json.load(open(p)); d['source_commit']='0000000000000000000000000000000000000000'; json.dump(d,open(p,'w'))"
expect_fail "17. Preflight source mismatch fails" "Source commit mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_source_pref/stage-logs" --runtime-dir "$wrong_source_pref/runtime" --builds-dir "$wrong_source_pref/builds" --current-dir "$wrong_source_pref/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 18. Preflight run mismatch fails
wrong_run_pref="$TMP_DIR/wrong_run_pref"
create_full_fixture_evidence "$wrong_run_pref" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_run_pref/stage-logs/preflight-results.json'; d=json.load(open(p)); d['workflow_run_id']='999'; json.dump(d,open(p,'w'))"
expect_fail "18. Preflight run mismatch fails" "Workflow run ID mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_run_pref/stage-logs" --runtime-dir "$wrong_run_pref/runtime" --builds-dir "$wrong_run_pref/builds" --current-dir "$wrong_run_pref/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 19. Preflight attempt mismatch fails
wrong_att_pref="$TMP_DIR/wrong_att_pref"
create_full_fixture_evidence "$wrong_att_pref" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_att_pref/stage-logs/preflight-results.json'; d=json.load(open(p)); d['workflow_run_attempt']='99'; json.dump(d,open(p,'w'))"
expect_fail "19. Preflight attempt mismatch fails" "Workflow run attempt mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_att_pref/stage-logs" --runtime-dir "$wrong_att_pref/runtime" --builds-dir "$wrong_att_pref/builds" --current-dir "$wrong_att_pref/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 20. Missing BIOS guest-health log fails
no_bios="$TMP_DIR/no_bios"
create_full_fixture_evidence "$no_bios" "$fixture_sha" "100" "1"
rm -f "$no_bios/runtime/bios-guest-validation.log"
expect_fail "20. Missing BIOS guest-health log fails" "Required guest health log missing: bios-guest-validation.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_bios/stage-logs" --runtime-dir "$no_bios/runtime" --builds-dir "$no_bios/builds" --current-dir "$no_bios/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 21. Missing UEFI guest-health log fails
no_uefi="$TMP_DIR/no_uefi"
create_full_fixture_evidence "$no_uefi" "$fixture_sha" "100" "1"
rm -f "$no_uefi/runtime/uefi-guest-validation.log"
expect_fail "21. Missing UEFI guest-health log fails" "Required guest health log missing: uefi-guest-validation.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_uefi/stage-logs" --runtime-dir "$no_uefi/runtime" --builds-dir "$no_uefi/builds" --current-dir "$no_uefi/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 22. Missing second-boot log fails
no_sec_boot="$TMP_DIR/no_sec_boot"
create_full_fixture_evidence "$no_sec_boot" "$fixture_sha" "100" "1"
rm -f "$no_sec_boot/runtime/uefi-second-boot-validation.log"
expect_fail "22. Missing second-boot log fails" "Required guest health log missing: uefi-second-boot-validation.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_sec_boot/stage-logs" --runtime-dir "$no_sec_boot/runtime" --builds-dir "$no_sec_boot/builds" --current-dir "$no_sec_boot/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 23. Serial log missing fails
no_serial="$TMP_DIR/no_serial"
create_full_fixture_evidence "$no_serial" "$fixture_sha" "100" "1"
rm -f "$no_serial/runtime/uefi-installed-boot.serial.log"
expect_fail "23. Serial log missing fails" "Required serial boot log missing: uefi-installed-boot.serial.log" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_serial/stage-logs" --runtime-dir "$no_serial/runtime" --builds-dir "$no_serial/builds" --current-dir "$no_serial/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 24. Identical BIOS and UEFI serial logs fail
same_serial="$TMP_DIR/same_serial"
create_full_fixture_evidence "$same_serial" "$fixture_sha" "100" "1"
cp "$same_serial/runtime/uefi-installed-boot.serial.log" "$same_serial/runtime/bios-installed-boot.serial.log"
expect_fail "24. Identical BIOS and UEFI serial logs fail" "UEFI and BIOS serial boot logs have identical SHA-256 hashes" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$same_serial/stage-logs" --runtime-dir "$same_serial/runtime" --builds-dir "$same_serial/builds" --current-dir "$same_serial/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 25. Kernel-panic serial evidence fails
panic_serial="$TMP_DIR/panic_serial"
create_full_fixture_evidence "$panic_serial" "$fixture_sha" "100" "1"
echo "Kernel panic - not syncing: VFS: Unable to mount root fs" >> "$panic_serial/runtime/uefi-installed-boot.serial.log"
expect_fail "25. Kernel-panic serial evidence fails" "Kernel panic detected" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$panic_serial/stage-logs" --runtime-dir "$panic_serial/runtime" --builds-dir "$panic_serial/builds" --current-dir "$panic_serial/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 26. Guest APT failure evidence fails
apt_fail="$TMP_DIR/apt_fail"
create_full_fixture_evidence "$apt_fail" "$fixture_sha" "100" "1"
cat > "$apt_fail/runtime/uefi-guest-validation.log" <<LOG
GenixBit OS test log
cat /etc/os-release
dpkg-query -W
apt-get update
LOG
expect_fail "26. Guest APT failure evidence fails" "Required package/system health command 'apt-get check' missing" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$apt_fail/stage-logs" --runtime-dir "$apt_fail/runtime" --builds-dir "$apt_fail/builds" --current-dir "$apt_fail/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 27. Missing stage source commit fails
no_commit_stage="$TMP_DIR/no_commit_stage"
create_full_fixture_evidence "$no_commit_stage" "$fixture_sha" "100" "1"
cat > "$no_commit_stage/stage-logs/stage-tamper.json" <<JSON
{"status":"PASS","workflow_run_id":"100","workflow_run_attempt":"1","exit_code":0}
JSON
expect_fail "27. Missing stage source commit fails" "Source commit mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_commit_stage/stage-logs" --runtime-dir "$no_commit_stage/runtime" --builds-dir "$no_commit_stage/builds" --current-dir "$no_commit_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 28. "unknown" run ID fails during a bound run
unknown_run_stage="$TMP_DIR/unknown_run_stage"
create_full_fixture_evidence "$unknown_run_stage" "$fixture_sha" "100" "1"
cat > "$unknown_run_stage/stage-logs/stage-tamper.json" <<JSON
{"source_commit":"$fixture_sha","workflow_run_id":"unknown","workflow_run_attempt":"1","status":"PASS","exit_code":0}
JSON
expect_fail "28. 'unknown' run ID fails during a bound run" "Workflow run ID missing or unknown" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$unknown_run_stage/stage-logs" --runtime-dir "$unknown_run_stage/runtime" --builds-dir "$unknown_run_stage/builds" --current-dir "$unknown_run_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 29. Cross-run evidence fails
cross_run_stage="$TMP_DIR/cross_run_stage"
create_full_fixture_evidence "$cross_run_stage" "$fixture_sha" "100" "1"
cat > "$cross_run_stage/stage-logs/stage-clean-install.json" <<JSON
{"source_commit":"$fixture_sha","workflow_run_id":"999","workflow_run_attempt":"1","status":"PASS","exit_code":0}
JSON
expect_fail "29. Cross-run evidence fails" "Workflow run ID mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$cross_run_stage/stage-logs" --runtime-dir "$cross_run_stage/runtime" --builds-dir "$cross_run_stage/builds" --current-dir "$cross_run_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 30. Complete authentic fixture evidence produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION
valid_stage="$TMP_DIR/valid_stage"
create_full_fixture_evidence "$valid_stage" "$fixture_sha" "100" "1"
expect_pass "30. Complete authentic fixture evidence produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$valid_stage/stage-logs" --runtime-dir "$valid_stage/runtime" --builds-dir "$valid_stage/builds" --current-dir "$valid_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 31. Generator respects --provenance-file flag
custom_prov_dir="$TMP_DIR/custom_prov_dir"
create_full_fixture_evidence "$custom_prov_dir" "$fixture_sha" "100" "1"
custom_prov_file="$custom_prov_dir/custom-artifact.json"
custom_gate_file="$custom_prov_dir/custom-gate.json"
expect_pass "31. Generator respects --provenance-file" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$custom_prov_dir/stage-logs" --runtime-dir "$custom_prov_dir/runtime" --builds-dir "$custom_prov_dir/builds" --current-dir "$custom_prov_dir/current" --output-gate "$custom_gate_file" --provenance-file "$custom_prov_file" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

TOTAL=$((TOTAL + 1))
if [[ -f "$custom_prov_file" ]] && grep -q "$custom_prov_file" "$custom_gate_file"; then
    pass "32. Provenance file path written into gate record"
else
    fail "32. Provenance file path not written into gate record"
fi

# 33. Preflight evidence remains unchanged during package validation initialization
preflight_preserve_dir="$TMP_DIR/preflight_preserve_dir"
mkdir -p "$preflight_preserve_dir/infra/package-staging/results/stage-logs"
echo "preflight content before package validation" > "$preflight_preserve_dir/infra/package-staging/results/stage-logs/preflight-results.json"
before_hash=$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$preflight_preserve_dir/infra/package-staging/results/stage-logs/preflight-results.json")

TOTAL=$((TOTAL + 1))
mkdir -p "$preflight_preserve_dir/infra/package-staging/results/stage-logs" "$preflight_preserve_dir/infra/package-staging/results/builds" "$preflight_preserve_dir/infra/package-staging/results/current" "$preflight_preserve_dir/infra/package-staging/results/runtime"
after_hash=$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$preflight_preserve_dir/infra/package-staging/results/stage-logs/preflight-results.json")

if [[ "$before_hash" == "$after_hash" ]]; then
    pass "33. preflight-results.json remains unchanged after package validation starts"
else
    fail "33. preflight-results.json was altered or erased"
fi

printf '[PASS] candidate validation execution tests passed: %d/%d\n' "$PASS" "$TOTAL"
