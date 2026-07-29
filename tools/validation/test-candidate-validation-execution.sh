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

expect_pass() { local name="$1"; shift; TOTAL=$((TOTAL + 1)); if ! "$@" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then echo "=== STDOUT ($name) ===" >&2; cat "$TMP_DIR/out" >&2; echo "=== STDERR ($name) ===" >&2; cat "$TMP_DIR/err" >&2; fail "$name (command failed)"; fi; pass "$name"; }
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
    cp "$REPO_ROOT/tools/validation/check-iso-structure.sh" "$work/tools/validation/check-iso-structure.sh"
    chmod +x "$work/tools/validation/check-iso-structure.sh"
    cat > "$work/args.sh" <<'EOF'
export TARGET_BUILD_VERSION="0.3.0-alpha"
EOF
    cat > "$work/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist
iso_dir=$(mktemp -d)
mkdir -p "$iso_dir/casper" "$iso_dir/EFI/BOOT"
dd if=/dev/zero of="$iso_dir/casper/vmlinuz" bs=1K count=10 status=none
dd if=/dev/zero of="$iso_dir/casper/initrd" bs=1K count=10 status=none

sq_dir=$(mktemp -d)
echo "rootfs" > "$sq_dir/root.txt"
mksquashfs "$sq_dir" "$iso_dir/casper/filesystem.squashfs" -noappend >/dev/null 2>&1
rm -rf "$sq_dir"

fat_img=$(mktemp)
dd if=/dev/zero of="$fat_img" bs=1K count=1440 status=none
mformat -i "$fat_img" -C -f 1440 :: >/dev/null 2>&1
mmd -i "$fat_img" ::EFI ::EFI/BOOT >/dev/null 2>&1
tbin=$(mktemp)
echo "BOOTX64" > "$tbin"
mcopy -i "$fat_img" "$tbin" ::EFI/BOOT/BOOTX64.EFI
rm -f "$tbin"

mkdir -p "$iso_dir/EFI"
cp "$fat_img" "$iso_dir/EFI/efiboot.img"
rm -f "$fat_img"

out_iso="dist/GenixBitOS-0.3.0-alpha-2607290000.iso"
xorriso -as mkisofs \
    -r -V "GENIXBIT_OS" \
    -J -joliet-long \
    -b casper/vmlinuz \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e EFI/efiboot.img \
    -no-emul-boot \
    -o "$out_iso" \
    "$iso_dir" >/dev/null 2>&1

truncate -s 501M "$out_iso"
rm -rf "$iso_dir"
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
  "output_dir": "$builds",
  "iso_path": "$iso_a",
  "output_file": "$iso_a",
  "size_bytes": $sz_a,
  "sha256": "$sha256_a",
  "sha512": "$sha512_a",
  "start_timestamp": "2026-07-29T00:00:00Z",
  "completion_timestamp": "2026-07-29T00:01:00Z",
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
  "output_dir": "$builds",
  "iso_path": "$iso_b",
  "output_file": "$iso_b",
  "size_bytes": $sz_b,
  "sha256": "$sha256_b",
  "sha512": "$sha512_b",
  "start_timestamp": "2026-07-29T00:01:00Z",
  "completion_timestamp": "2026-07-29T00:02:00Z",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "exit_code": 0
}
JSON

    cat > "$builds/build-a-iso-structure.json" <<JSON
{
  "source_commit": "$sha",
  "candidate_branch": "validation/0.3.0-alpha-candidate-2",
  "iso_path": "$iso_a",
  "iso_sha256": "$sha256_a",
  "iso_sha512": "$sha512_a",
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
  "candidate_branch": "validation/0.3.0-alpha-candidate-2",
  "iso_path": "$iso_b",
  "iso_sha256": "$sha256_b",
  "iso_sha512": "$sha512_b",
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

    cat > "$stage_logs/stage-installer-branding.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON
    cat > "$stage_logs/stage-real-installation.json" <<JSON
{
  "source_commit": "$sha",
  "candidate_sha": "$sha",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "iso_sha256": "$sha256_a",
  "uefi_installation_result": "PASS",
  "bios_installation_result": "PASS",
  "uefi_installed_disk": "$dir/genixbit-0.3.0-uefi.qcow2",
  "bios_installed_disk": "$dir/genixbit-0.3.0-bios.qcow2",
  "uefi_first_boot_result": "PASS",
  "bios_first_boot_result": "PASS",
  "uefi_second_boot_result": "PASS",
  "bios_second_boot_result": "PASS",
  "authenticated_guest_validation_result": "PASS",
  "exit_code": 0,
  "status": "PASS"
}
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

# 1. Missing stage exit_code fails
no_exit_code_stage="$TMP_DIR/no_exit_code_stage"
create_full_fixture_evidence "$no_exit_code_stage" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_exit_code_stage/stage-logs/stage-clean-install.json'; d=json.load(open(p)); del d['exit_code']; json.dump(d,open(p,'w'))"
expect_fail "1. Missing stage exit_code fails" "is missing exit_code" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_exit_code_stage/stage-logs" --runtime-dir "$no_exit_code_stage/runtime" --builds-dir "$no_exit_code_stage/builds" --current-dir "$no_exit_code_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 2. Missing workflow-run attempt fails
no_att_stage="$TMP_DIR/no_att_stage"
create_full_fixture_evidence "$no_att_stage" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_att_stage/stage-logs/stage-clean-install.json'; d=json.load(open(p)); del d['workflow_run_attempt']; json.dump(d,open(p,'w'))"
expect_fail "2. Missing workflow-run attempt fails" "Workflow run attempt missing or unknown" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_att_stage/stage-logs" --runtime-dir "$no_att_stage/runtime" --builds-dir "$no_att_stage/builds" --current-dir "$no_att_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 3. "unknown" workflow-run attempt fails
unknown_att_stage="$TMP_DIR/unknown_att_stage"
create_full_fixture_evidence "$unknown_att_stage" "$fixture_sha" "100" "1"
python3 -c "import json; p='$unknown_att_stage/stage-logs/stage-clean-install.json'; d=json.load(open(p)); d['workflow_run_attempt']='unknown'; json.dump(d,open(p,'w'))"
expect_fail "3. 'unknown' workflow-run attempt fails" "Workflow run attempt missing or unknown" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$unknown_att_stage/stage-logs" --runtime-dir "$unknown_att_stage/runtime" --builds-dir "$unknown_att_stage/builds" --current-dir "$unknown_att_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 4. Missing preflight expected candidate SHA fails
no_pref_cand_sha="$TMP_DIR/no_pref_cand_sha"
create_full_fixture_evidence "$no_pref_cand_sha" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_pref_cand_sha/stage-logs/preflight-results.json'; d=json.load(open(p)); del d['expected_candidate_sha']; json.dump(d,open(p,'w'))"
expect_fail "4. Missing preflight expected candidate SHA fails" "expected_candidate_sha mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_pref_cand_sha/stage-logs" --runtime-dir "$no_pref_cand_sha/runtime" --builds-dir "$no_pref_cand_sha/builds" --current-dir "$no_pref_cand_sha/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 5. Missing preflight expected candidate branch fails
no_pref_cand_branch="$TMP_DIR/no_pref_cand_branch"
create_full_fixture_evidence "$no_pref_cand_branch" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_pref_cand_branch/stage-logs/preflight-results.json'; d=json.load(open(p)); del d['expected_candidate_branch']; json.dump(d,open(p,'w'))"
expect_fail "5. Missing preflight expected candidate branch fails" "expected_candidate_branch mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_pref_cand_branch/stage-logs" --runtime-dir "$no_pref_cand_branch/runtime" --builds-dir "$no_pref_cand_branch/builds" --current-dir "$no_pref_cand_branch/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 6. Missing Build A metadata fails without fallback
no_build_a="$TMP_DIR/no_build_a"
create_full_fixture_evidence "$no_build_a" "$fixture_sha" "100" "1"
rm -f "$no_build_a/builds/build-a-build.json"
expect_fail "6. Missing Build A metadata fails without fallback" "Required evidence file missing" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_build_a/stage-logs" --runtime-dir "$no_build_a/runtime" --builds-dir "$no_build_a/builds" --current-dir "$no_build_a/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 7. Missing Build A target version fails
no_target_ver_a="$TMP_DIR/no_target_ver_a"
create_full_fixture_evidence "$no_target_ver_a" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_target_ver_a/builds/build-a-build.json'; d=json.load(open(p)); del d['target_version']; json.dump(d,open(p,'w'))"
expect_fail "7. Missing Build A target version fails" "target_version is 'None', expected '0.3.0-alpha'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_target_ver_a/stage-logs" --runtime-dir "$no_target_ver_a/runtime" --builds-dir "$no_target_ver_a/builds" --current-dir "$no_target_ver_a/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 8. Missing Build A worktree path fails
no_worktree_a="$TMP_DIR/no_worktree_a"
create_full_fixture_evidence "$no_worktree_a" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_worktree_a/builds/build-a-build.json'; d=json.load(open(p)); del d['worktree_dir']; json.dump(d,open(p,'w'))"
expect_fail "8. Missing Build A worktree path fails" "worktree_dir is missing or empty" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_worktree_a/stage-logs" --runtime-dir "$no_worktree_a/runtime" --builds-dir "$no_worktree_a/builds" --current-dir "$no_worktree_a/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 9. Build A recorded size mismatch fails
wrong_size_a="$TMP_DIR/wrong_size_a"
create_full_fixture_evidence "$wrong_size_a" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_size_a/builds/build-a-build.json'; d=json.load(open(p)); d['size_bytes']=99999; json.dump(d,open(p,'w'))"
expect_fail "9. Build A recorded size mismatch fails" "actual file size .* does not match metadata size_bytes" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_size_a/stage-logs" --runtime-dir "$wrong_size_a/runtime" --builds-dir "$wrong_size_a/builds" --current-dir "$wrong_size_a/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 10. Build A recorded SHA-256 mismatch fails
wrong_sha256_a="$TMP_DIR/wrong_sha256_a"
create_full_fixture_evidence "$wrong_sha256_a" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_sha256_a/builds/build-a-build.json'; d=json.load(open(p)); d['sha256']='0'*64; json.dump(d,open(p,'w'))"
expect_fail "10. Build A recorded SHA-256 mismatch fails" "calculated SHA-256 .* does not match metadata sha256" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_sha256_a/stage-logs" --runtime-dir "$wrong_sha256_a/runtime" --builds-dir "$wrong_sha256_a/builds" --current-dir "$wrong_sha256_a/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 11. Build A recorded SHA-512 mismatch fails
wrong_sha512_a="$TMP_DIR/wrong_sha512_a"
create_full_fixture_evidence "$wrong_sha512_a" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_sha512_a/builds/build-a-build.json'; d=json.load(open(p)); d['sha512']='0'*128; json.dump(d,open(p,'w'))"
expect_fail "11. Build A recorded SHA-512 mismatch fails" "calculated SHA-512 .* does not match metadata sha512" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_sha512_a/stage-logs" --runtime-dir "$wrong_sha512_a/runtime" --builds-dir "$wrong_sha512_a/builds" --current-dir "$wrong_sha512_a/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 12. Missing Build B structure evidence fails
no_struct_b="$TMP_DIR/no_struct_b"
create_full_fixture_evidence "$no_struct_b" "$fixture_sha" "100" "1"
rm -f "$no_struct_b/builds/build-b-iso-structure.json"
expect_fail "12. Missing Build B structure evidence fails" "Required evidence file missing" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_struct_b/stage-logs" --runtime-dir "$no_struct_b/runtime" --builds-dir "$no_struct_b/builds" --current-dir "$no_struct_b/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 13. Build B structure reusing Build A path fails
reused_struct_b="$TMP_DIR/reused_struct_b"
create_full_fixture_evidence "$reused_struct_b" "$fixture_sha" "100" "1"
cp "$reused_struct_b/builds/build-a-iso-structure.json" "$reused_struct_b/builds/build-b-iso-structure.json"
expect_fail "13. Build B structure reusing Build A path fails" "Build B structure evidence ISO path mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$reused_struct_b/stage-logs" --runtime-dir "$reused_struct_b/runtime" --builds-dir "$reused_struct_b/builds" --current-dir "$reused_struct_b/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 14. Structure ISO path mismatch fails
wrong_iso_path_struct="$TMP_DIR/wrong_iso_path_struct"
create_full_fixture_evidence "$wrong_iso_path_struct" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_iso_path_struct/builds/build-a-iso-structure.json'; d=json.load(open(p)); d['iso_path']='/tmp/other.iso'; json.dump(d,open(p,'w'))"
expect_fail "14. Structure ISO path mismatch fails" "structure evidence ISO path mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_iso_path_struct/stage-logs" --runtime-dir "$wrong_iso_path_struct/runtime" --builds-dir "$wrong_iso_path_struct/builds" --current-dir "$wrong_iso_path_struct/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 15. Structure SHA-256 mismatch fails
wrong_sha256_struct="$TMP_DIR/wrong_sha256_struct"
create_full_fixture_evidence "$wrong_sha256_struct" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_sha256_struct/builds/build-a-iso-structure.json'; d=json.load(open(p)); d['iso_sha256']='0'*64; json.dump(d,open(p,'w'))"
expect_fail "15. Structure SHA-256 mismatch fails" "structure evidence ISO SHA-256 mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_sha256_struct/stage-logs" --runtime-dir "$wrong_sha256_struct/runtime" --builds-dir "$wrong_sha256_struct/builds" --current-dir "$wrong_sha256_struct/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 16. Structure SHA-512 mismatch fails
wrong_sha512_struct="$TMP_DIR/wrong_sha512_struct"
create_full_fixture_evidence "$wrong_sha512_struct" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_sha512_struct/builds/build-a-iso-structure.json'; d=json.load(open(p)); d['iso_sha512']='0'*128; json.dump(d,open(p,'w'))"
expect_fail "16. Structure SHA-512 mismatch fails" "structure evidence ISO SHA-512 mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_sha512_struct/stage-logs" --runtime-dir "$wrong_sha512_struct/runtime" --builds-dir "$wrong_sha512_struct/builds" --current-dir "$wrong_sha512_struct/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 17. Branding-only installer evidence fails
branding_only_installer="$TMP_DIR/branding_only_installer"
create_full_fixture_evidence "$branding_only_installer" "$fixture_sha" "100" "1"
rm -f "$branding_only_installer/stage-logs/stage-real-installation.json"
expect_fail "17. Branding-only installer evidence fails" "Required evidence file missing.*stage-real-installation.json" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$branding_only_installer/stage-logs" --runtime-dir "$branding_only_installer/runtime" --builds-dir "$branding_only_installer/builds" --current-dir "$branding_only_installer/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 18. Missing real-installation evidence fails
no_real_inst="$TMP_DIR/no_real_inst"
create_full_fixture_evidence "$no_real_inst" "$fixture_sha" "100" "1"
rm -f "$no_real_inst/stage-logs/stage-real-installation.json"
expect_fail "18. Missing real-installation evidence fails" "stage-real-installation.json" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_real_inst/stage-logs" --runtime-dir "$no_real_inst/runtime" --builds-dir "$no_real_inst/builds" --current-dir "$no_real_inst/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 19. Failed UEFI installation result fails
fail_uefi_inst="$TMP_DIR/fail_uefi_inst"
create_full_fixture_evidence "$fail_uefi_inst" "$fixture_sha" "100" "1"
python3 -c "import json; p='$fail_uefi_inst/stage-logs/stage-real-installation.json'; d=json.load(open(p)); d['uefi_installation_result']='FAIL'; json.dump(d,open(p,'w'))"
expect_fail "19. Failed UEFI installation result fails" "uefi_installation_result is 'FAIL', expected 'PASS'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$fail_uefi_inst/stage-logs" --runtime-dir "$fail_uefi_inst/runtime" --builds-dir "$fail_uefi_inst/builds" --current-dir "$fail_uefi_inst/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 20. Failed BIOS installation result fails
fail_bios_inst="$TMP_DIR/fail_bios_inst"
create_full_fixture_evidence "$fail_bios_inst" "$fixture_sha" "100" "1"
python3 -c "import json; p='$fail_bios_inst/stage-logs/stage-real-installation.json'; d=json.load(open(p)); d['bios_installation_result']='FAIL'; json.dump(d,open(p,'w'))"
expect_fail "20. Failed BIOS installation result fails" "bios_installation_result is 'FAIL', expected 'PASS'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$fail_bios_inst/stage-logs" --runtime-dir "$fail_bios_inst/runtime" --builds-dir "$fail_bios_inst/builds" --current-dir "$fail_bios_inst/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 21. Failed UEFI second boot fails
fail_uefi_sec="$TMP_DIR/fail_uefi_sec"
create_full_fixture_evidence "$fail_uefi_sec" "$fixture_sha" "100" "1"
python3 -c "import json; p='$fail_uefi_sec/stage-logs/stage-real-installation.json'; d=json.load(open(p)); d['uefi_second_boot_result']='FAIL'; json.dump(d,open(p,'w'))"
expect_fail "21. Failed UEFI second boot fails" "uefi_second_boot_result is 'FAIL', expected 'PASS'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$fail_uefi_sec/stage-logs" --runtime-dir "$fail_uefi_sec/runtime" --builds-dir "$fail_uefi_sec/builds" --current-dir "$fail_uefi_sec/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 22. Failed BIOS second boot fails
fail_bios_sec="$TMP_DIR/fail_bios_sec"
create_full_fixture_evidence "$fail_bios_sec" "$fixture_sha" "100" "1"
python3 -c "import json; p='$fail_bios_sec/stage-logs/stage-real-installation.json'; d=json.load(open(p)); d['bios_second_boot_result']='FAIL'; json.dump(d,open(p,'w'))"
expect_fail "22. Failed BIOS second boot fails" "bios_second_boot_result is 'FAIL', expected 'PASS'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$fail_bios_sec/stage-logs" --runtime-dir "$fail_bios_sec/runtime" --builds-dir "$fail_bios_sec/builds" --current-dir "$fail_bios_sec/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 23. Real-installation ISO hash mismatch fails
wrong_real_inst_hash="$TMP_DIR/wrong_real_inst_hash"
create_full_fixture_evidence "$wrong_real_inst_hash" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_real_inst_hash/stage-logs/stage-real-installation.json'; d=json.load(open(p)); d['iso_sha256']='0'*64; json.dump(d,open(p,'w'))"
expect_fail "23. Real-installation ISO hash mismatch fails" "Real installation ISO SHA-256 mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_real_inst_hash/stage-logs" --runtime-dir "$wrong_real_inst_hash/runtime" --builds-dir "$wrong_real_inst_hash/builds" --current-dir "$wrong_real_inst_hash/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 24. Missing BIOS guest-health log fails
no_bios="$TMP_DIR/no_bios"
create_full_fixture_evidence "$no_bios" "$fixture_sha" "100" "1"
rm -f "$no_bios/runtime/bios-guest-validation.log"
expect_fail "24. Missing BIOS guest-health log fails" "Runtime guest health log missing for BIOS Guest Validation" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_bios/stage-logs" --runtime-dir "$no_bios/runtime" --builds-dir "$no_bios/builds" --current-dir "$no_bios/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 25. Missing UEFI guest-health log fails
no_uefi="$TMP_DIR/no_uefi"
create_full_fixture_evidence "$no_uefi" "$fixture_sha" "100" "1"
rm -f "$no_uefi/runtime/uefi-guest-validation.log"
expect_fail "25. Missing UEFI guest-health log fails" "Runtime guest health log missing for UEFI Guest Validation" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_uefi/stage-logs" --runtime-dir "$no_uefi/runtime" --builds-dir "$no_uefi/builds" --current-dir "$no_uefi/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 26. Package-health category contains all four guest logs
check_pkg_health="$TMP_DIR/check_pkg_health"
create_full_fixture_evidence "$check_pkg_health" "$fixture_sha" "100" "1"
gate_file="$check_pkg_health/gate.json"
expect_pass "26. Package-health category contains all four guest logs" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$check_pkg_health/stage-logs" --runtime-dir "$check_pkg_health/runtime" --builds-dir "$check_pkg_health/builds" --current-dir "$check_pkg_health/current" --output-gate "$gate_file" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"
TOTAL=$((TOTAL + 1))
if python3 -c "import json, sys; g=json.load(open('$gate_file')); files=g['categories']['package_health_readiness']['evidence_files']; sys.exit(0 if len(files)==4 and all('guest-validation' in f or 'second-boot' in f for f in files) else 1)"; then
    pass "26b. Verified package_health_readiness files list"
else
    fail "26b. package_health_readiness files list invalid"
fi

# 27. Installed-system category contains real installation, guest and serial evidence
TOTAL=$((TOTAL + 1))
if python3 -c "import json, sys; g=json.load(open('$gate_file')); files=g['categories']['installed_system_readiness']['evidence_files']; sys.exit(0 if len(files)==7 and any('stage-real-installation' in f for f in files) else 1)"; then
    pass "27. Installed-system category contains real installation, guest and serial evidence"
else
    fail "27. installed_system_readiness files list invalid"
fi

# 28. Reproducibility category contains both builds and both structure records
TOTAL=$((TOTAL + 1))
if python3 -c "import json, sys; g=json.load(open('$gate_file')); files=g['categories']['reproducibility_readiness']['evidence_files']; sys.exit(0 if len(files)==5 and any('build-a-iso-structure' in f for f in files) else 1)"; then
    pass "28. Reproducibility category contains both builds and both structure records"
else
    fail "28. reproducibility_readiness files list invalid"
fi

# 29. Provenance contains all runtime evidence hashes
prov_file="$check_pkg_health/current/0.3.0-alpha-artifact.json"
TOTAL=$((TOTAL + 1))
if python3 -c "import json, sys; p=json.load(open('$prov_file'))['validation_evidence']; sys.exit(0 if len(p)>=15 and 'real_installation_sha256' in p and 'uefi_serial_sha256' in p and 'bios_serial_sha256' in p else 1)"; then
    pass "29. Provenance contains all runtime evidence hashes"
else
    fail "29. Provenance validation_evidence missing required hashes"
fi

# 30. Complete valid fixture produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION
TOTAL=$((TOTAL + 1))
if python3 -c "import json, sys; g=json.load(open('$gate_file')); sys.exit(0 if g['summary']['overall_gate_status']=='PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION' else 1)"; then
    pass "30. Complete valid fixture produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION"
else
    fail "30. Gate status is not PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION"
fi

printf '[PASS] candidate validation execution tests passed: %d/%d\n' "$PASS" "$TOTAL"
