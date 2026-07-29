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
    git -C "$work" branch -M validation/0.3.0-alpha-candidate-3
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -u origin validation/0.3.0-alpha-candidate-3 >/dev/null 2>&1
}

fixture_base="$TMP_DIR/fixture_base"
make_fixture_repo "$fixture_base"
fixture_repo="$fixture_base/work"
fixture_sha=$(git -C "$fixture_repo" rev-parse HEAD)

calc_sha256() {
    python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

calc_sha512() {
    python3 -c 'import hashlib, sys; print(hashlib.sha512(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# Full production-layout fixture evidence builder
create_full_fixture_evidence() {
    local dir="$1"
    local sha="${2:-$fixture_sha}"
    local run_id="${3:-100}"
    local run_attempt="${4:-1}"
    local cand_branch="${5:-validation/0.3.0-alpha-candidate-3}"

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
    local sha256_a=$(calc_sha256 "$iso_a")
    local sha256_b=$(calc_sha256 "$iso_b")
    local sha512_a=$(calc_sha512 "$iso_a")
    local sha512_b=$(calc_sha512 "$iso_b")

    cat > "$stage_logs/stage-candidate-selection.json" <<JSON
{
  "source_commit": "$sha",
  "candidate_branch": "$cand_branch",
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
  "expected_candidate_branch": "$cand_branch",
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
  "candidate_branch": "$cand_branch",
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
  "candidate_branch": "$cand_branch",
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
  "candidate_branch": "$cand_branch",
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
  "candidate_branch": "$cand_branch",
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
    cat > "$stage_logs/stage-tamper.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON
    cat > "$stage_logs/stage-documentation.json" <<JSON
{"source_commit":"$sha","workflow_run_id":"$run_id","workflow_run_attempt":"$run_attempt","exit_code":0,"status":"PASS"}
JSON

    # Place initial VM logs in stage-logs/ per production layout
    cat > "$stage_logs/uefi-installer-boot.serial.log" <<LOG
GenixBit OS UEFI Installer Serial Log
Linux version 6.8.0-genixbit
Installer completed successfully.
LOG
    cat > "$stage_logs/bios-installer-boot.serial.log" <<LOG
GenixBit OS BIOS Installer Serial Log (Different Content from UEFI)
Linux version 6.8.0-genixbit-bios
Installer completed successfully.
LOG
    cat > "$stage_logs/uefi-installed-boot.serial.log" <<LOG
GenixBit OS UEFI Installed Boot Serial Log
Linux version 6.8.0-genixbit
[  OK  ] Reached target Multi-User System.
GenixBit OS login:
LOG
    cat > "$stage_logs/bios-installed-boot.serial.log" <<LOG
GenixBit OS BIOS Installed Boot Serial Log (Different Content from UEFI)
Linux version 6.8.0-genixbit-bios
[  OK  ] Reached target Multi-User System.
Welcome to GenixBit OS login:
LOG

    for log in uefi-guest-validation.log bios-guest-validation.log uefi-second-boot-validation.log bios-second-boot-validation.log; do
        cat > "$stage_logs/$log" <<LOG
=== Authenticated Guest Command Output (ssh) ===
Start Timestamp: 2026-07-29T00:00:00Z
Completion Timestamp: 2026-07-29T00:01:00Z
Exit Code: 0
Channel: ssh
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

    # Run production evidence collector to generate run-scoped runtime/ dir
    rm -rf "$runtime"
    bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" \
      --stage-logs-dir "$stage_logs" \
      --runtime-dir "$runtime" \
      --candidate-sha "$sha" \
      --workflow-run-id "$run_id" \
      --workflow-run-attempt "$run_attempt" \
      --build-a-sha256 "$sha256_a" >/dev/null

    local manifest_path="$runtime/runtime-evidence-manifest.json"
    local manifest_sha256=$(calc_sha256 "$manifest_path")

    local uefi_disk="$dir/genixbit-0.3.0-uefi.qcow2"
    local bios_disk="$dir/genixbit-0.3.0-bios.qcow2"
    echo "synthetic uefi qcow2 disk 1111" > "$uefi_disk"
    echo "synthetic bios qcow2 disk 222222" > "$bios_disk"

    local sz_uefi_disk=$(wc -c < "$uefi_disk" | tr -d ' ')
    local sz_bios_disk=$(wc -c < "$bios_disk" | tr -d ' ')
    local sha_uefi_disk=$(calc_sha256 "$uefi_disk")
    local sha_bios_disk=$(calc_sha256 "$bios_disk")

    cat > "$stage_logs/stage-real-installation.json" <<JSON
{
  "source_commit": "$sha",
  "candidate_sha": "$sha",
  "workflow_run_id": "$run_id",
  "workflow_run_attempt": "$run_attempt",
  "iso_sha256": "$sha256_a",
  "uefi_installation_result": "PASS",
  "bios_installation_result": "PASS",
  "uefi_installed_disk": "$uefi_disk",
  "bios_installed_disk": "$bios_disk",
  "uefi_installed_disk_size_bytes": $sz_uefi_disk,
  "bios_installed_disk_size_bytes": $sz_bios_disk,
  "uefi_installed_disk_sha256": "$sha_uefi_disk",
  "bios_installed_disk_sha256": "$sha_bios_disk",
  "runtime_evidence_manifest": "$manifest_path",
  "runtime_evidence_manifest_sha256": "$manifest_sha256",
  "uefi_first_boot_result": "PASS",
  "bios_first_boot_result": "PASS",
  "uefi_second_boot_result": "PASS",
  "bios_second_boot_result": "PASS",
  "authenticated_guest_validation_result": "PASS",
  "exit_code": 0,
  "status": "PASS"
}
JSON
}

# 1. Valid stage-log evidence is collected into the run-scoped directory
test1_dir="$TMP_DIR/test1_dir"
create_full_fixture_evidence "$test1_dir" "$fixture_sha" "100" "1"
TOTAL=$((TOTAL + 1))
if [[ -f "$test1_dir/runtime/runtime-evidence-manifest.json" ]]; then
    pass "1. Valid stage-log evidence is collected into the run-scoped directory"
else
    fail "1. Runtime evidence collection failed to produce manifest"
fi

# 2. Missing runtime handoff causes gate generation to fail
no_handoff="$TMP_DIR/no_handoff"
create_full_fixture_evidence "$no_handoff" "$fixture_sha" "100" "1"
rm -rf "$no_handoff/runtime"
expect_fail "2. Missing runtime handoff causes gate generation to fail" "Required evidence file missing|Runtime file missing or empty" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_handoff/stage-logs" --runtime-dir "$no_handoff/runtime" --builds-dir "$no_handoff/builds" --current-dir "$no_handoff/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 3. Missing source runtime file fails
no_src_file="$TMP_DIR/no_src_file"
create_full_fixture_evidence "$no_src_file" "$fixture_sha" "100" "1"
rm -f "$no_src_file/stage-logs/uefi-guest-validation.log"
rm -rf "$no_src_file/runtime"
expect_fail "3. Missing source runtime file fails" "source file does not exist" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$no_src_file/stage-logs" --runtime-dir "$no_src_file/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$no_src_file/builds/build-a-build.json'))['sha256'])")"

# 4. Empty source runtime file fails
empty_src="$TMP_DIR/empty_src"
create_full_fixture_evidence "$empty_src" "$fixture_sha" "100" "1"
> "$empty_src/stage-logs/uefi-guest-validation.log"
rm -rf "$empty_src/runtime"
expect_fail "4. Empty source runtime file fails" "source file is empty" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$empty_src/stage-logs" --runtime-dir "$empty_src/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$empty_src/builds/build-a-build.json'))['sha256'])")"

# 5. Pre-existing destination file fails
pre_dst="$TMP_DIR/pre_dst"
create_full_fixture_evidence "$pre_dst" "$fixture_sha" "100" "1"
expect_fail "5. Pre-existing destination file fails" "destination file already exists" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$pre_dst/stage-logs" --runtime-dir "$pre_dst/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$pre_dst/builds/build-a-build.json'))['sha256'])")"

# 6. Source and destination path equality fails
same_path_dir="$TMP_DIR/same_path_dir"
create_full_fixture_evidence "$same_path_dir" "$fixture_sha" "100" "1"
expect_fail "6. Source and destination path equality fails" "destination file already exists|identical" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$same_path_dir/stage-logs" --runtime-dir "$same_path_dir/stage-logs" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$same_path_dir/builds/build-a-build.json'))['sha256'])")"

# 7. Guest log Exit Code: 1 fails
guest_exit1="$TMP_DIR/guest_exit1"
create_full_fixture_evidence "$guest_exit1" "$fixture_sha" "100" "1"
sed -i.bak 's/Exit Code: 0/Exit Code: 1/g' "$guest_exit1/stage-logs/uefi-guest-validation.log"
rm -rf "$guest_exit1/runtime"
expect_fail "7. Guest log Exit Code: 1 fails" "missing Exit Code: 0|contains non-zero command exit code" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$guest_exit1/stage-logs" --runtime-dir "$guest_exit1/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$guest_exit1/builds/build-a-build.json'))['sha256'])")"

# 8. Guest log missing Exit Code fails
guest_no_exit="$TMP_DIR/guest_no_exit"
create_full_fixture_evidence "$guest_no_exit" "$fixture_sha" "100" "1"
grep -v "Exit Code:" "$guest_no_exit/stage-logs/uefi-guest-validation.log" > "$guest_no_exit/stage-logs/uefi-guest-validation.log.tmp"
mv "$guest_no_exit/stage-logs/uefi-guest-validation.log.tmp" "$guest_no_exit/stage-logs/uefi-guest-validation.log"
rm -rf "$guest_no_exit/runtime"
expect_fail "8. Guest log missing Exit Code fails" "missing Exit Code: 0" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$guest_no_exit/stage-logs" --runtime-dir "$guest_no_exit/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$guest_no_exit/builds/build-a-build.json'))['sha256'])")"

# 9. Guest log using a non-SSH channel fails
guest_channel="$TMP_DIR/guest_channel"
create_full_fixture_evidence "$guest_channel" "$fixture_sha" "100" "1"
sed -i.bak 's/Channel: ssh/Channel: simulated/g' "$guest_channel/stage-logs/uefi-guest-validation.log"
sed -i.bak 's/=== Authenticated Guest Command Output (ssh) ===/=== Authenticated Guest Command Output (simulated) ===/g' "$guest_channel/stage-logs/uefi-guest-validation.log"
rm -rf "$guest_channel/runtime"
expect_fail "9. Guest log using a non-SSH channel fails" "missing SSH channel header|missing Channel: ssh" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$guest_channel/stage-logs" --runtime-dir "$guest_channel/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$guest_channel/builds/build-a-build.json'))['sha256'])")"

# 10. Guest log missing a start timestamp fails
guest_no_start="$TMP_DIR/guest_no_start"
create_full_fixture_evidence "$guest_no_start" "$fixture_sha" "100" "1"
grep -v "Start Timestamp:" "$guest_no_start/stage-logs/uefi-guest-validation.log" > "$guest_no_start/stage-logs/uefi-guest-validation.log.tmp"
mv "$guest_no_start/stage-logs/uefi-guest-validation.log.tmp" "$guest_no_start/stage-logs/uefi-guest-validation.log"
rm -rf "$guest_no_start/runtime"
expect_fail "10. Guest log missing a start timestamp fails" "missing Start Timestamp" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$guest_no_start/stage-logs" --runtime-dir "$guest_no_start/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$guest_no_start/builds/build-a-build.json'))['sha256'])")"

# 11. Guest log missing a completion timestamp fails
guest_no_comp="$TMP_DIR/guest_no_comp"
create_full_fixture_evidence "$guest_no_comp" "$fixture_sha" "100" "1"
grep -v "Completion Timestamp:" "$guest_no_comp/stage-logs/uefi-guest-validation.log" > "$guest_no_comp/stage-logs/uefi-guest-validation.log.tmp"
mv "$guest_no_comp/stage-logs/uefi-guest-validation.log.tmp" "$guest_no_comp/stage-logs/uefi-guest-validation.log"
rm -rf "$guest_no_comp/runtime"
expect_fail "11. Guest log missing a completion timestamp fails" "missing Completion Timestamp" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$guest_no_comp/stage-logs" --runtime-dir "$guest_no_comp/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$guest_no_comp/builds/build-a-build.json'))['sha256'])")"

# 12. Identical BIOS and UEFI installer serial logs fail
same_inst_serial="$TMP_DIR/same_inst_serial"
create_full_fixture_evidence "$same_inst_serial" "$fixture_sha" "100" "1"
cp "$same_inst_serial/stage-logs/uefi-installer-boot.serial.log" "$same_inst_serial/stage-logs/bios-installer-boot.serial.log"
rm -rf "$same_inst_serial/runtime"
expect_fail "12. Identical BIOS and UEFI installer serial logs fail" "UEFI and BIOS installer serial logs have identical SHA-256" bash "$REPO_ROOT/tools/validation/collect-current-runtime-evidence.sh" --stage-logs-dir "$same_inst_serial/stage-logs" --runtime-dir "$same_inst_serial/runtime" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1" --build-a-sha256 "$(python3 -c "import json; print(json.load(open('$same_inst_serial/builds/build-a-build.json'))['sha256'])")"

# 13. Runtime manifest source-SHA mismatch fails
wrong_manifest_sha="$TMP_DIR/wrong_manifest_sha"
create_full_fixture_evidence "$wrong_manifest_sha" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_manifest_sha/runtime/runtime-evidence-manifest.json'; d=json.load(open(p)); d['source_commit']='0'*40; json.dump(d,open(p,'w'))"
expect_fail "13. Runtime manifest source-SHA mismatch fails" "Source commit mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_manifest_sha/stage-logs" --runtime-dir "$wrong_manifest_sha/runtime" --builds-dir "$wrong_manifest_sha/builds" --current-dir "$wrong_manifest_sha/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 14. Runtime manifest workflow-run mismatch fails
wrong_manifest_run="$TMP_DIR/wrong_manifest_run"
create_full_fixture_evidence "$wrong_manifest_run" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_manifest_run/runtime/runtime-evidence-manifest.json'; d=json.load(open(p)); d['workflow_run_id']='99999'; json.dump(d,open(p,'w'))"
expect_fail "14. Runtime manifest workflow-run mismatch fails" "Workflow run ID mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_manifest_run/stage-logs" --runtime-dir "$wrong_manifest_run/runtime" --builds-dir "$wrong_manifest_run/builds" --current-dir "$wrong_manifest_run/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 15. Runtime manifest attempt mismatch fails
wrong_manifest_att="$TMP_DIR/wrong_manifest_att"
create_full_fixture_evidence "$wrong_manifest_att" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_manifest_att/runtime/runtime-evidence-manifest.json'; d=json.load(open(p)); d['workflow_run_attempt']='99'; json.dump(d,open(p,'w'))"
expect_fail "15. Runtime manifest attempt mismatch fails" "Workflow run attempt mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_manifest_att/stage-logs" --runtime-dir "$wrong_manifest_att/runtime" --builds-dir "$wrong_manifest_att/builds" --current-dir "$wrong_manifest_att/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 16. Runtime manifest Build A hash mismatch fails
wrong_manifest_builda="$TMP_DIR/wrong_manifest_builda"
create_full_fixture_evidence "$wrong_manifest_builda" "$fixture_sha" "100" "1"
python3 -c "import json; p='$wrong_manifest_builda/runtime/runtime-evidence-manifest.json'; d=json.load(open(p)); d['build_a_iso_sha256']='0'*64; json.dump(d,open(p,'w'))"
expect_fail "16. Runtime manifest Build A hash mismatch fails" "Runtime manifest Build A ISO SHA-256 mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_manifest_builda/stage-logs" --runtime-dir "$wrong_manifest_builda/runtime" --builds-dir "$wrong_manifest_builda/builds" --current-dir "$wrong_manifest_builda/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 17. Runtime file size mismatch fails
wrong_runtime_size="$TMP_DIR/wrong_runtime_size"
create_full_fixture_evidence "$wrong_runtime_size" "$fixture_sha" "100" "1"
python3 -c "import json, hashlib; p='$wrong_runtime_size/runtime/runtime-evidence-manifest.json'; d=json.load(open(p)); d['files']['uefi-guest-validation.log']['size_bytes']=999999; json.dump(d,open(p,'w')); new_h=hashlib.sha256(open(p,'rb').read()).hexdigest(); rp='$wrong_runtime_size/stage-logs/stage-real-installation.json'; rd=json.load(open(rp)); rd['runtime_evidence_manifest_sha256']=new_h; json.dump(rd,open(rp,'w'))"
expect_fail "17. Runtime file size mismatch fails" "Runtime file size mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_runtime_size/stage-logs" --runtime-dir "$wrong_runtime_size/runtime" --builds-dir "$wrong_runtime_size/builds" --current-dir "$wrong_runtime_size/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 18. Runtime file SHA-256 mismatch fails
wrong_runtime_hash="$TMP_DIR/wrong_runtime_hash"
create_full_fixture_evidence "$wrong_runtime_hash" "$fixture_sha" "100" "1"
python3 -c "import json, hashlib; p='$wrong_runtime_hash/runtime/runtime-evidence-manifest.json'; d=json.load(open(p)); d['files']['uefi-guest-validation.log']['sha256']='0'*64; json.dump(d,open(p,'w')); new_h=hashlib.sha256(open(p,'rb').read()).hexdigest(); rp='$wrong_runtime_hash/stage-logs/stage-real-installation.json'; rd=json.load(open(rp)); rd['runtime_evidence_manifest_sha256']=new_h; json.dump(rd,open(rp,'w'))"
expect_fail "18. Runtime file SHA-256 mismatch fails" "Runtime file SHA-256 mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$wrong_runtime_hash/stage-logs" --runtime-dir "$wrong_runtime_hash/runtime" --builds-dir "$wrong_runtime_hash/builds" --current-dir "$wrong_runtime_hash/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 19. Missing evidence source_commit fails
no_commit_stage="$TMP_DIR/no_commit_stage"
create_full_fixture_evidence "$no_commit_stage" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_commit_stage/stage-logs/stage-clean-install.json'; d=json.load(open(p)); del d['source_commit']; json.dump(d,open(p,'w'))"
expect_fail "19. Missing evidence source_commit fails" "is missing source_commit" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_commit_stage/stage-logs" --runtime-dir "$no_commit_stage/runtime" --builds-dir "$no_commit_stage/builds" --current-dir "$no_commit_stage/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 20. Generator run ID unknown fails
unknown_gen_run="$TMP_DIR/unknown_gen_run"
create_full_fixture_evidence "$unknown_gen_run" "$fixture_sha" "100" "1"
expect_fail "20. Generator run ID unknown fails" "workflow_run_id is required and cannot be empty or 'unknown'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$unknown_gen_run/stage-logs" --runtime-dir "$unknown_gen_run/runtime" --builds-dir "$unknown_gen_run/builds" --current-dir "$unknown_gen_run/current" --candidate-sha "$fixture_sha" --workflow-run-id "unknown" --workflow-run-attempt "1"

# 21. Generator run attempt unknown fails
unknown_gen_att="$TMP_DIR/unknown_gen_att"
create_full_fixture_evidence "$unknown_gen_att" "$fixture_sha" "100" "1"
expect_fail "21. Generator run attempt unknown fails" "workflow_run_attempt is required and cannot be empty or 'unknown'" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$unknown_gen_att/stage-logs" --runtime-dir "$unknown_gen_att/runtime" --builds-dir "$unknown_gen_att/builds" --current-dir "$unknown_gen_att/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "unknown"

# 22. Missing structure candidate branch fails
no_struct_branch="$TMP_DIR/no_struct_branch"
create_full_fixture_evidence "$no_struct_branch" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_struct_branch/builds/build-a-iso-structure.json'; d=json.load(open(p)); del d['candidate_branch']; json.dump(d,open(p,'w'))"
expect_fail "22. Missing structure candidate branch fails" "structure evidence candidate_branch mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_struct_branch/stage-logs" --runtime-dir "$no_struct_branch/runtime" --builds-dir "$no_struct_branch/builds" --current-dir "$no_struct_branch/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 23. Missing structure SHA-512 fails
no_struct_sha512="$TMP_DIR/no_struct_sha512"
create_full_fixture_evidence "$no_struct_sha512" "$fixture_sha" "100" "1"
python3 -c "import json; p='$no_struct_sha512/builds/build-a-iso-structure.json'; d=json.load(open(p)); del d['iso_sha512']; json.dump(d,open(p,'w'))"
expect_fail "23. Missing structure SHA-512 fails" "structure evidence ISO SHA-512 mismatch" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_struct_sha512/stage-logs" --runtime-dir "$no_struct_sha512/runtime" --builds-dir "$no_struct_sha512/builds" --current-dir "$no_struct_sha512/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 24. Missing installed disk fails
no_disk_dir="$TMP_DIR/no_disk_dir"
create_full_fixture_evidence "$no_disk_dir" "$fixture_sha" "100" "1"
rm -f "$no_disk_dir/genixbit-0.3.0-uefi.qcow2"
expect_fail "24. Missing installed disk fails" "Real installation uefi_installed_disk missing or empty" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$no_disk_dir/stage-logs" --runtime-dir "$no_disk_dir/runtime" --builds-dir "$no_disk_dir/builds" --current-dir "$no_disk_dir/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 25. Identical installed disk paths fail
same_disk_path="$TMP_DIR/same_disk_path"
create_full_fixture_evidence "$same_disk_path" "$fixture_sha" "100" "1"
python3 -c "import json; p='$same_disk_path/stage-logs/stage-real-installation.json'; d=json.load(open(p)); d['bios_installed_disk']=d['uefi_installed_disk']; json.dump(d,open(p,'w'))"
expect_fail "25. Identical installed disk paths fail" "UEFI and BIOS disk paths are identical" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$same_disk_path/stage-logs" --runtime-dir "$same_disk_path/runtime" --builds-dir "$same_disk_path/builds" --current-dir "$same_disk_path/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

# 26. Complete production-layout fixture produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION
valid_prod="$TMP_DIR/valid_prod"
create_full_fixture_evidence "$valid_prod" "$fixture_sha" "100" "1"
expect_pass "26. Complete production-layout fixture produces PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION" python3 "$REPO_ROOT/tools/validation/generate-candidate-gate.py" --stage-logs-dir "$valid_prod/stage-logs" --runtime-dir "$valid_prod/runtime" --builds-dir "$valid_prod/builds" --current-dir "$valid_prod/current" --candidate-sha "$fixture_sha" --workflow-run-id "100" --workflow-run-attempt "1"

printf '[PASS] candidate validation execution tests passed: %d/%d\n' "$PASS" "$TOTAL"
