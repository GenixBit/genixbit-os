#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Evidence-Derived Candidate Validation Gate Generator for GenixBit OS

import os
import sys
import json
import re
import hashlib
import argparse

RETIRED_CANDIDATE2_SHA = "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669"
RETIRED_IDENTIFIERS = {
    RETIRED_CANDIDATE2_SHA,
    "51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e",
    "GenixBitOS-0.2.0-alpha-2607220558.iso",
    "1784810864397202"
}
NA_REASON = "No valid prior GenixBit OS release artifact exists from which to execute an upgrade or rollback test."

REQUIRED_HEALTH_COMMANDS = [
    "cat /etc/os-release",
    "dpkg-query -W",
    "apt-get update",
    "apt-get check",
    "dpkg --audit",
    "systemctl --failed"
]

REQUIRED_PACKAGES = [
    "genixbit-os-desktop",
    "genixbit-os-base",
    "linux-image-generic",
    "systemd",
    "apt",
    "dpkg"
]

def fail(msg):
    print(f"[FAIL] Candidate Gate Generator Error: {msg}", file=sys.stderr)
    sys.exit(1)

def calc_sha256(filepath):
    if not os.path.isfile(filepath):
        fail(f"File not found for SHA-256 calculation: {filepath}")
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def calc_sha512(filepath):
    if not os.path.isfile(filepath):
        fail(f"File not found for SHA-512 calculation: {filepath}")
    h = hashlib.sha512()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def check_retired_references(obj_or_str, context=""):
    s = json.dumps(obj_or_str) if not isinstance(obj_or_str, str) else obj_or_str
    for item in RETIRED_IDENTIFIERS:
        if item in s:
            fail(f"Retired Candidate 2 identifier '{item}' referenced in evidence context: {context}")

def read_bound_evidence(filepath, *, expected_sha, expected_run_id, expected_run_attempt, required_status="PASS"):
    if not os.path.isfile(filepath):
        fail(f"Required evidence file missing: {filepath}")
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        fail(f"Failed to parse JSON from {filepath}: {e}")

    check_retired_references(data, context=filepath)

    status = data.get("status")
    if required_status and status != required_status:
        fail(f"Evidence file {filepath} status is '{status}', expected '{required_status}'")

    if "exit_code" not in data:
        fail(f"Evidence file {filepath} is missing exit_code")

    if data["exit_code"] != 0:
        fail(f"Evidence file {filepath} exit_code is {data['exit_code']}, expected 0")

    commit = data.get("source_commit") or data.get("candidate_sha") or data.get("active_release_source_commit")
    if not commit or commit != expected_sha:
        fail(f"Source commit mismatch in {filepath}: {commit} != {expected_sha}")

    if data.get("git_head") and data.get("git_head") != expected_sha:
        fail(f"Git HEAD mismatch in {filepath}: {data.get('git_head')} != {expected_sha}")

    run_id_val = str(data.get("workflow_run_id", ""))
    if expected_run_id and expected_run_id != "unknown":
        if not run_id_val or run_id_val == "unknown":
            fail(f"Workflow run ID missing or unknown in {filepath}")
        elif run_id_val != str(expected_run_id):
            fail(f"Workflow run ID mismatch in {filepath}: {run_id_val} != {expected_run_id}")

    run_att_val = str(data.get("workflow_run_attempt", ""))
    if expected_run_attempt and str(expected_run_attempt) != "unknown":
        if not run_att_val or run_att_val == "unknown":
            fail(f"Workflow run attempt missing or unknown in {filepath}")
        elif run_att_val != str(expected_run_attempt):
            fail(f"Workflow run attempt mismatch in {filepath}: {run_att_val} != {expected_run_attempt}")

    return data

def check_guest_health_log(log_path, label):
    if not os.path.isfile(log_path):
        fail(f"Runtime guest health log missing for {label}: {log_path}")
    if os.path.getsize(log_path) == 0:
        fail(f"Runtime guest health log is empty for {label}: {log_path}")
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    check_retired_references(content, context=log_path)

    for cmd in REQUIRED_HEALTH_COMMANDS:
        if cmd not in content:
            fail(f"Required package/system health command '{cmd}' missing from {label} log ({log_path})")

    if "GenixBit" not in content and "genixbit" not in content.lower():
        fail(f"GenixBit OS product identity missing from {label} log ({log_path})")

    for pkg in REQUIRED_PACKAGES:
        if pkg not in content:
            fail(f"Required package '{pkg}' missing from {label} log ({log_path})")

def check_serial_log(log_path, label):
    if not os.path.isfile(log_path):
        fail(f"Serial boot log missing for {label}: {log_path}")
    if os.path.getsize(log_path) == 0:
        fail(f"Serial boot log is empty for {label}: {log_path}")
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    check_retired_references(content, context=log_path)

    lower_content = content.lower()
    if "kernel panic" in lower_content:
        fail(f"Kernel panic detected in {label} serial log ({log_path})")
    if "emergency mode" in lower_content:
        fail(f"Emergency mode detected in {label} serial log ({log_path})")
    if "initramfs" in lower_content and "unable to mount" in lower_content:
        fail(f"Initramfs boot failure detected in {label} serial log ({log_path})")
    if "placeholder" in lower_content or "dummy" in lower_content:
        fail(f"Fabricated placeholder marker detected in {label} serial log ({log_path})")

    boot_milestones = ["Linux version", "Reached target", "login:", "Welcome", "GenixBit", "systemd[1]", "GRUB"]
    if not any(m in content for m in boot_milestones):
        fail(f"No valid boot milestones found in {label} serial log ({log_path})")

def main():
    parser = argparse.ArgumentParser(description="GenixBit OS candidate gate generator")
    parser.add_argument("--stage-logs-dir", default=None, help="Path to stage-logs directory")
    parser.add_argument("--runtime-dir", default=None, help="Path to runtime evidence directory")
    parser.add_argument("--builds-dir", default=None, help="Path to builds directory")
    parser.add_argument("--current-dir", default=None, help="Path to current evidence output directory")
    parser.add_argument("--output-gate", default=None, help="Output path for release gate JSON")
    parser.add_argument("--provenance-file", default=None, help="Path for active artifact provenance JSON")
    parser.add_argument("--candidate-branch", default=os.environ.get("EXPECTED_CANDIDATE_BRANCH", "validation/0.3.0-alpha-candidate-2"))
    parser.add_argument("--candidate-sha", default=os.environ.get("EXPECTED_CANDIDATE_SHA", os.environ.get("ACTIVE_RELEASE_SOURCE_COMMIT", "")))
    parser.add_argument("--workflow-run-id", default=os.environ.get("WORKFLOW_RUN_ID", os.environ.get("GITHUB_RUN_ID", "unknown")))
    parser.add_argument("--workflow-run-attempt", default=os.environ.get("WORKFLOW_RUN_ATTEMPT", os.environ.get("GITHUB_RUN_ATTEMPT", "1")))
    args = parser.parse_args()

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    stage_logs_dir = args.stage_logs_dir or os.path.join(repo_root, "infra/package-staging/results/stage-logs")
    runtime_dir = args.runtime_dir or os.path.join(repo_root, "infra/package-staging/results/runtime")
    builds_dir = args.builds_dir or os.path.join(repo_root, "infra/package-staging/results/builds")
    current_dir = args.current_dir or os.path.join(repo_root, "infra/package-staging/results/current")
    output_gate = args.output_gate or os.path.join(current_dir, "0.3.0-alpha-release-gate.json")
    provenance_file = args.provenance_file or os.path.join(current_dir, "0.3.0-alpha-artifact.json")

    cand_branch = args.candidate_branch
    cand_sha = args.candidate_sha
    run_id = str(args.workflow_run_id)
    run_attempt = str(args.workflow_run_attempt)

    if cand_branch != "validation/0.3.0-alpha-candidate-2":
        fail(f"Unexpected candidate branch: {cand_branch}")
    if not re.fullmatch(r"[0-9a-f]{40}", cand_sha):
        fail("Candidate SHA must be a 40-character lowercase hexadecimal string")

    # 1. candidate_selection evidence
    cand_sel_path = os.path.join(stage_logs_dir, "stage-candidate-selection.json")
    cand_sel = read_bound_evidence(cand_sel_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    if cand_sel.get("candidate_branch") != cand_branch:
        fail(f"Candidate selection branch mismatch: {cand_sel.get('candidate_branch')} != {cand_branch}")
    if cand_sel.get("candidate_sha") != cand_sha:
        fail(f"Candidate selection SHA mismatch: {cand_sel.get('candidate_sha')} != {cand_sha}")
    if cand_sel.get("git_head") != cand_sha:
        fail(f"Candidate selection git HEAD mismatch: {cand_sel.get('git_head')} != {cand_sha}")
    if cand_sel.get("working_tree_clean") is not True:
        fail("Candidate selection working tree was not clean")

    # 2. host_readiness (preflight)
    preflight_path = os.path.join(stage_logs_dir, "preflight-results.json")
    preflight = read_bound_evidence(preflight_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    if "expected_candidate_sha" not in preflight or preflight.get("expected_candidate_sha") != cand_sha:
        fail(f"Preflight expected_candidate_sha mismatch: {preflight.get('expected_candidate_sha')} != {cand_sha}")
    if "expected_candidate_branch" not in preflight or preflight.get("expected_candidate_branch") != cand_branch:
        fail(f"Preflight expected_candidate_branch mismatch: {preflight.get('expected_candidate_branch')} != {cand_branch}")
    if preflight.get("source_commit") != cand_sha:
        fail(f"Preflight source_commit mismatch: {preflight.get('source_commit')} != {cand_sha}")
    if preflight.get("active_release_source_commit") != cand_sha:
        fail(f"Preflight active_release_source_commit mismatch: {preflight.get('active_release_source_commit')} != {cand_sha}")
    if preflight.get("git_head") != cand_sha:
        fail(f"Preflight git_head mismatch: {preflight.get('git_head')} != {cand_sha}")
    if preflight.get("active_release_version") != "0.3.0-alpha":
        fail(f"Preflight active_release_version is '{preflight.get('active_release_version')}', expected '0.3.0-alpha'")
    if preflight.get("active_release_mode") != "fresh-install-only":
        fail(f"Preflight active_release_mode is '{preflight.get('active_release_mode')}', expected 'fresh-install-only'")
    if preflight.get("architecture") != "x86_64":
        fail(f"Preflight architecture is '{preflight.get('architecture')}', expected 'x86_64'")
    if preflight.get("kvm_available") is not True:
        fail(f"Preflight kvm_available is '{preflight.get('kvm_available')}', expected True")
    if preflight.get("staging_status") != "REACHABLE":
        fail(f"Preflight staging_status is '{preflight.get('staging_status')}', expected 'REACHABLE'")
    if str(preflight.get("workflow_run_id", "")) != run_id:
        fail(f"Preflight workflow_run_id mismatch: {preflight.get('workflow_run_id')} != {run_id}")
    if str(preflight.get("workflow_run_attempt", "")) != run_attempt:
        fail(f"Preflight workflow_run_attempt mismatch: {preflight.get('workflow_run_attempt')} != {run_attempt}")
    if "exit_code" not in preflight or preflight.get("exit_code") != 0:
        fail(f"Preflight exit_code is {preflight.get('exit_code')}, expected 0")
    if preflight.get("status") != "PASS":
        fail("Preflight status is not PASS")

    # 3. package_infrastructure
    pkg_build_path = os.path.join(stage_logs_dir, "stage-package-build.json")
    pkg_build = read_bound_evidence(pkg_build_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    repo_pub_path = os.path.join(stage_logs_dir, "stage-repository-publication.json")
    repo_pub = read_bound_evidence(repo_pub_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # 4. clean_install_readiness
    clean_install_path = os.path.join(stage_logs_dir, "stage-clean-install.json")
    clean_install = read_bound_evidence(clean_install_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # 5. Build A & Build B metadata validation (strict 4 files)
    build_a_json_path = os.path.join(builds_dir, "build-a-build.json")
    build_b_json_path = os.path.join(builds_dir, "build-b-build.json")
    struct_a_path = os.path.join(builds_dir, "build-a-iso-structure.json")
    struct_b_path = os.path.join(builds_dir, "build-b-iso-structure.json")

    build_a_meta = read_bound_evidence(build_a_json_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    build_b_meta = read_bound_evidence(build_b_json_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    for label, meta, pth in [("Build A", build_a_meta, build_a_json_path), ("Build B", build_b_meta, build_b_json_path)]:
        if meta.get("execution_mode") != "REAL_BUILD":
            fail(f"{label} metadata ({pth}) execution_mode is '{meta.get('execution_mode')}', expected 'REAL_BUILD'")
        if meta.get("build_script") != "./build.sh":
            fail(f"{label} metadata ({pth}) build_script is '{meta.get('build_script')}', expected './build.sh'")
        if meta.get("build_exit_code") != 0:
            fail(f"{label} metadata ({pth}) build_exit_code is {meta.get('build_exit_code')}, expected 0")
        if meta.get("status") != "PASS":
            fail(f"{label} metadata ({pth}) status is '{meta.get('status')}', expected 'PASS'")
        if meta.get("candidate_branch") != cand_branch:
            fail(f"{label} metadata ({pth}) candidate_branch is '{meta.get('candidate_branch')}', expected '{cand_branch}'")
        if meta.get("source_commit") != cand_sha:
            fail(f"{label} metadata ({pth}) source_commit is '{meta.get('source_commit')}', expected '{cand_sha}'")
        if "target_version" not in meta or meta.get("target_version") != "0.3.0-alpha":
            fail(f"{label} metadata ({pth}) target_version is '{meta.get('target_version')}', expected '0.3.0-alpha'")
        if "workflow_run_id" not in meta or str(meta.get("workflow_run_id")) != run_id:
            fail(f"{label} metadata ({pth}) workflow_run_id mismatch")
        if "workflow_run_attempt" not in meta or str(meta.get("workflow_run_attempt")) != run_attempt:
            fail(f"{label} metadata ({pth}) workflow_run_attempt mismatch")
        if not meta.get("worktree_dir"):
            fail(f"{label} metadata ({pth}) worktree_dir is missing or empty")
        if not meta.get("output_dir"):
            fail(f"{label} metadata ({pth}) output_dir is missing or empty")
        if not meta.get("iso_path"):
            fail(f"{label} metadata ({pth}) iso_path is missing or empty")
        if not isinstance(meta.get("size_bytes"), int) or meta.get("size_bytes") <= 0:
            fail(f"{label} metadata ({pth}) size_bytes is not a positive integer")
        if not re.fullmatch(r"[0-9a-f]{64}", str(meta.get("sha256", ""))):
            fail(f"{label} metadata ({pth}) sha256 is not a valid lowercase SHA-256")
        if not re.fullmatch(r"[0-9a-f]{128}", str(meta.get("sha512", ""))):
            fail(f"{label} metadata ({pth}) sha512 is not a valid lowercase SHA-512")
        if not meta.get("start_timestamp"):
            fail(f"{label} metadata ({pth}) start_timestamp is missing")
        if not meta.get("completion_timestamp"):
            fail(f"{label} metadata ({pth}) completion_timestamp is missing")

    worktree_a = build_a_meta["worktree_dir"]
    worktree_b = build_b_meta["worktree_dir"]
    if worktree_a == worktree_b:
        fail(f"Build A and Build B used identical worktree path: {worktree_a}")

    iso_a = build_a_meta["iso_path"]
    iso_b = build_b_meta["iso_path"]
    if iso_a == iso_b:
        fail(f"Build A and Build B used identical ISO output path: {iso_a}")

    if not os.path.isfile(iso_a) or os.path.getsize(iso_a) == 0:
        fail(f"Build A ISO file missing or empty: {iso_a}")
    if not os.path.isfile(iso_b) or os.path.getsize(iso_b) == 0:
        fail(f"Build B ISO file missing or empty: {iso_b}")

    filename_a = os.path.basename(iso_a)
    filename_b = os.path.basename(iso_b)
    if not re.match(r"^GenixBitOS-0\.3\.0-alpha-.*\.iso$", filename_a):
        fail(f"Build A ISO filename '{filename_a}' does not match GenixBitOS-0.3.0-alpha-*.iso")
    if not re.match(r"^GenixBitOS-0\.3\.0-alpha-.*\.iso$", filename_b):
        fail(f"Build B ISO filename '{filename_b}' does not match GenixBitOS-0.3.0-alpha-*.iso")

    actual_size_a = os.path.getsize(iso_a)
    actual_size_b = os.path.getsize(iso_b)
    if actual_size_a != build_a_meta["size_bytes"]:
        fail(f"Build A actual file size ({actual_size_a}) does not match metadata size_bytes ({build_a_meta['size_bytes']})")
    if actual_size_b != build_b_meta["size_bytes"]:
        fail(f"Build B actual file size ({actual_size_b}) does not match metadata size_bytes ({build_b_meta['size_bytes']})")
    if actual_size_a != actual_size_b:
        fail(f"Build A size ({actual_size_a}) does not match Build B size ({actual_size_b})")

    sha256_a = calc_sha256(iso_a)
    sha256_b = calc_sha256(iso_b)
    if sha256_a != build_a_meta["sha256"]:
        fail(f"Build A calculated SHA-256 ({sha256_a}) does not match metadata sha256 ({build_a_meta['sha256']})")
    if sha256_b != build_b_meta["sha256"]:
        fail(f"Build B calculated SHA-256 ({sha256_b}) does not match metadata sha256 ({build_b_meta['sha256']})")
    if sha256_a != sha256_b:
        fail(f"Build A SHA-256 ({sha256_a}) does not match Build B SHA-256 ({sha256_b})")

    sha512_a = calc_sha512(iso_a)
    sha512_b = calc_sha512(iso_b)
    if sha512_a != build_a_meta["sha512"]:
        fail(f"Build A calculated SHA-512 ({sha512_a}) does not match metadata sha512 ({build_a_meta['sha512']})")
    if sha512_b != build_b_meta["sha512"]:
        fail(f"Build B calculated SHA-512 ({sha512_b}) does not match metadata sha512 ({build_b_meta['sha512']})")
    if sha512_a != sha512_b:
        fail(f"Build A SHA-512 ({sha512_a}) does not match Build B SHA-512 ({sha512_b})")

    # Reproducibility check
    repro_path = os.path.join(stage_logs_dir, "stage-reproducibility.json")
    repro = read_bound_evidence(repro_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    repro_hashes = repro.get("artifact_hashes", {})
    if repro_hashes.get("cmp_exit_code") != 0:
        fail(f"Reproducibility cmp exit code is {repro_hashes.get('cmp_exit_code')}, expected 0")

    # 6. Separate ISO Structure Evidence
    if struct_a_path == struct_b_path:
        fail("Build A and Build B ISO structure evidence paths must be different")
    struct_a = read_bound_evidence(struct_a_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    struct_b = read_bound_evidence(struct_b_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    for label, struct_data, expected_iso, expected_sha256, expected_sha512 in [
        ("Build A", struct_a, iso_a, sha256_a, sha512_a),
        ("Build B", struct_b, iso_b, sha256_b, sha512_b)
    ]:
        if struct_data.get("candidate_branch") and struct_data.get("candidate_branch") != cand_branch:
            fail(f"{label} structure evidence candidate_branch mismatch: {struct_data.get('candidate_branch')} != {cand_branch}")
        if struct_data.get("iso_path") != expected_iso:
            fail(f"{label} structure evidence ISO path mismatch: {struct_data.get('iso_path')} != {expected_iso}")
        if struct_data.get("iso_sha256") != expected_sha256:
            fail(f"{label} structure evidence ISO SHA-256 mismatch: {struct_data.get('iso_sha256')} != {expected_sha256}")
        if struct_data.get("iso_sha512") and struct_data.get("iso_sha512") != expected_sha512:
            fail(f"{label} structure evidence ISO SHA-512 mismatch: {struct_data.get('iso_sha512')} != {expected_sha512}")

    # 7. Real Installation Evidence
    real_inst_path = os.path.join(stage_logs_dir, "stage-real-installation.json")
    real_inst = read_bound_evidence(real_inst_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    if real_inst.get("source_commit") != cand_sha:
        fail(f"Real installation source_commit mismatch: {real_inst.get('source_commit')} != {cand_sha}")
    if real_inst.get("candidate_sha") != cand_sha:
        fail(f"Real installation candidate_sha mismatch: {real_inst.get('candidate_sha')} != {cand_sha}")
    if str(real_inst.get("workflow_run_id")) != run_id:
        fail(f"Real installation workflow_run_id mismatch: {real_inst.get('workflow_run_id')} != {run_id}")
    if str(real_inst.get("workflow_run_attempt")) != run_attempt:
        fail(f"Real installation workflow_run_attempt mismatch: {real_inst.get('workflow_run_attempt')} != {run_attempt}")
    if real_inst.get("iso_sha256") != sha256_a:
        fail(f"Real installation ISO SHA-256 mismatch: {real_inst.get('iso_sha256')} != {sha256_a}")
    if real_inst.get("uefi_installation_result") != "PASS":
        fail(f"Real installation uefi_installation_result is '{real_inst.get('uefi_installation_result')}', expected 'PASS'")
    if real_inst.get("bios_installation_result") != "PASS":
        fail(f"Real installation bios_installation_result is '{real_inst.get('bios_installation_result')}', expected 'PASS'")
    if real_inst.get("uefi_first_boot_result") != "PASS":
        fail(f"Real installation uefi_first_boot_result is '{real_inst.get('uefi_first_boot_result')}', expected 'PASS'")
    if real_inst.get("bios_first_boot_result") != "PASS":
        fail(f"Real installation bios_first_boot_result is '{real_inst.get('bios_first_boot_result')}', expected 'PASS'")
    if real_inst.get("uefi_second_boot_result") != "PASS":
        fail(f"Real installation uefi_second_boot_result is '{real_inst.get('uefi_second_boot_result')}', expected 'PASS'")
    if real_inst.get("bios_second_boot_result") != "PASS":
        fail(f"Real installation bios_second_boot_result is '{real_inst.get('bios_second_boot_result')}', expected 'PASS'")
    if real_inst.get("authenticated_guest_validation_result") != "PASS":
        fail(f"Real installation authenticated_guest_validation_result is '{real_inst.get('authenticated_guest_validation_result')}', expected 'PASS'")

    # 8. Guest Health Logs & Serial Logs
    guest_health_logs = [
        ("uefi-guest-validation.log", "UEFI Guest Validation"),
        ("bios-guest-validation.log", "BIOS Guest Validation"),
        ("uefi-second-boot-validation.log", "UEFI Second Boot Validation"),
        ("bios-second-boot-validation.log", "BIOS Second Boot Validation")
    ]
    guest_log_paths = {}
    for log_filename, label in guest_health_logs:
        log_path = os.path.join(runtime_dir, log_filename)
        check_guest_health_log(log_path, label)
        guest_log_paths[log_filename] = log_path

    serial_logs = [
        ("uefi-installed-boot.serial.log", "UEFI Installed Boot Serial"),
        ("bios-installed-boot.serial.log", "BIOS Installed Boot Serial")
    ]
    serial_log_paths = {}
    for log_filename, label in serial_logs:
        log_path = os.path.join(runtime_dir, log_filename)
        check_serial_log(log_path, label)
        serial_log_paths[log_filename] = log_path

    hash_serial_uefi = calc_sha256(serial_log_paths["uefi-installed-boot.serial.log"])
    hash_serial_bios = calc_sha256(serial_log_paths["bios-installed-boot.serial.log"])
    if hash_serial_uefi == hash_serial_bios:
        fail("UEFI and BIOS serial boot logs have identical SHA-256 hashes")

    # 9. Installer branding & Security & Documentation
    branding_path = os.path.join(stage_logs_dir, "stage-installer-branding.json")
    branding_data = read_bound_evidence(branding_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    tamper_path = os.path.join(stage_logs_dir, "stage-tamper.json")
    tamper_data = read_bound_evidence(tamper_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    doc_path = os.path.join(stage_logs_dir, "stage-documentation.json")
    doc_data = read_bound_evidence(doc_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    categories = {
        "candidate_selection": {
            "status": "PASS",
            "evidence_files": [cand_sel_path],
            "evidence_hashes": [calc_sha256(cand_sel_path)],
            "candidate_branch": cand_branch,
            "candidate_sha": cand_sha
        },
        "host_readiness": {
            "status": "PASS",
            "evidence_files": [preflight_path],
            "evidence_hashes": [calc_sha256(preflight_path)],
            "architecture": "x86_64",
            "kvm_available": True
        },
        "package_infrastructure": {
            "status": "PASS",
            "evidence_files": [pkg_build_path, repo_pub_path],
            "evidence_hashes": [calc_sha256(pkg_build_path), calc_sha256(repo_pub_path)]
        },
        "clean_install_readiness": {
            "status": "PASS",
            "evidence_files": [clean_install_path],
            "evidence_hashes": [calc_sha256(clean_install_path)]
        },
        "iso_build_readiness": {
            "status": "PASS",
            "evidence_files": [build_a_json_path, build_b_json_path],
            "evidence_hashes": [calc_sha256(build_a_json_path), calc_sha256(build_b_json_path)]
        },
        "iso_structure_readiness": {
            "status": "PASS",
            "evidence_files": [struct_a_path, struct_b_path],
            "evidence_hashes": [calc_sha256(struct_a_path), calc_sha256(struct_b_path)]
        },
        "uefi_readiness": {
            "status": "PASS",
            "evidence_files": [
                real_inst_path,
                serial_log_paths["uefi-installed-boot.serial.log"],
                guest_log_paths["uefi-guest-validation.log"],
                guest_log_paths["uefi-second-boot-validation.log"]
            ],
            "evidence_hashes": [
                calc_sha256(real_inst_path),
                calc_sha256(serial_log_paths["uefi-installed-boot.serial.log"]),
                calc_sha256(guest_log_paths["uefi-guest-validation.log"]),
                calc_sha256(guest_log_paths["uefi-second-boot-validation.log"])
            ]
        },
        "bios_readiness": {
            "status": "PASS",
            "evidence_files": [
                real_inst_path,
                serial_log_paths["bios-installed-boot.serial.log"],
                guest_log_paths["bios-guest-validation.log"],
                guest_log_paths["bios-second-boot-validation.log"]
            ],
            "evidence_hashes": [
                calc_sha256(real_inst_path),
                calc_sha256(serial_log_paths["bios-installed-boot.serial.log"]),
                calc_sha256(guest_log_paths["bios-guest-validation.log"]),
                calc_sha256(guest_log_paths["bios-second-boot-validation.log"])
            ]
        },
        "installer_readiness": {
            "status": "PASS",
            "evidence_files": [real_inst_path],
            "evidence_hashes": [calc_sha256(real_inst_path)]
        },
        "installed_system_readiness": {
            "status": "PASS",
            "evidence_files": [
                real_inst_path,
                guest_log_paths["uefi-guest-validation.log"],
                guest_log_paths["bios-guest-validation.log"],
                guest_log_paths["uefi-second-boot-validation.log"],
                guest_log_paths["bios-second-boot-validation.log"],
                serial_log_paths["uefi-installed-boot.serial.log"],
                serial_log_paths["bios-installed-boot.serial.log"]
            ],
            "evidence_hashes": [
                calc_sha256(real_inst_path),
                calc_sha256(guest_log_paths["uefi-guest-validation.log"]),
                calc_sha256(guest_log_paths["bios-guest-validation.log"]),
                calc_sha256(guest_log_paths["uefi-second-boot-validation.log"]),
                calc_sha256(guest_log_paths["bios-second-boot-validation.log"]),
                calc_sha256(serial_log_paths["uefi-installed-boot.serial.log"]),
                calc_sha256(serial_log_paths["bios-installed-boot.serial.log"])
            ]
        },
        "package_health_readiness": {
            "status": "PASS",
            "evidence_files": [
                guest_log_paths["uefi-guest-validation.log"],
                guest_log_paths["bios-guest-validation.log"],
                guest_log_paths["uefi-second-boot-validation.log"],
                guest_log_paths["bios-second-boot-validation.log"]
            ],
            "evidence_hashes": [
                calc_sha256(guest_log_paths["uefi-guest-validation.log"]),
                calc_sha256(guest_log_paths["bios-guest-validation.log"]),
                calc_sha256(guest_log_paths["uefi-second-boot-validation.log"]),
                calc_sha256(guest_log_paths["bios-second-boot-validation.log"])
            ]
        },
        "security_readiness": {
            "status": "PASS",
            "evidence_files": [tamper_path],
            "evidence_hashes": [calc_sha256(tamper_path)]
        },
        "reproducibility_readiness": {
            "status": "PASS",
            "evidence_files": [
                build_a_json_path,
                build_b_json_path,
                struct_a_path,
                struct_b_path,
                repro_path
            ],
            "evidence_hashes": [
                calc_sha256(build_a_json_path),
                calc_sha256(build_b_json_path),
                calc_sha256(struct_a_path),
                calc_sha256(struct_b_path),
                calc_sha256(repro_path)
            ]
        },
        "documentation_readiness": {
            "status": "PASS",
            "evidence_files": [doc_path, branding_path],
            "evidence_hashes": [calc_sha256(doc_path), calc_sha256(branding_path)]
        },
        "upgrade_readiness": {"status": "NOT_APPLICABLE", "reason": NA_REASON},
        "rollback_readiness": {"status": "NOT_APPLICABLE", "reason": NA_REASON}
    }

    pass_cnt = sum(1 for c in categories.values() if c["status"] == "PASS")
    fail_cnt = sum(1 for c in categories.values() if c["status"] in ("FAIL", "RETIRED"))
    blocked_cnt = sum(1 for c in categories.values() if c["status"] == "BLOCKED")
    not_tested_cnt = sum(1 for c in categories.values() if c["status"] == "NOT TESTED")
    na_cnt = sum(1 for c in categories.values() if c["status"] == "NOT_APPLICABLE")

    gate_data = {
        "release_version": "0.3.0-alpha",
        "candidate_branch": cand_branch,
        "candidate_source_commit": cand_sha,
        "workflow_run_id": run_id,
        "workflow_run_attempt": run_attempt,
        "active_artifact_provenance": provenance_file,
        "categories": categories,
        "summary": {
            "pass_count": pass_cnt,
            "fail_count": fail_cnt,
            "blocked_count": blocked_cnt,
            "not_tested_count": not_tested_cnt,
            "not_applicable_count": na_cnt,
            "release_ready": False,
            "stable_ready": False,
            "overall_gate_status": "PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION"
        }
    }

    os.makedirs(os.path.dirname(output_gate), exist_ok=True)
    with open(output_gate, "w", encoding="utf-8") as f:
        json.dump(gate_data, f, indent=2)
        f.write("\n")

    prov_data = {
        "schema_version": "1.0",
        "release_version": "0.3.0-alpha",
        "candidate_branch": cand_branch,
        "candidate_source_commit": cand_sha,
        "workflow_run_id": run_id,
        "workflow_run_attempt": run_attempt,
        "filename": filename_a,
        "size_bytes": actual_size_a,
        "sha256": sha256_a,
        "sha512": sha512_a,
        "object_generation": None,
        "verification_status": "VALIDATED_UNPUBLISHED",
        "usable_as_release_artifact": False,
        "usable_as_migration_source": False,
        "validation_evidence": {
            "candidate_selection_sha256": calc_sha256(cand_sel_path),
            "preflight_sha256": calc_sha256(preflight_path),
            "build_a_sha256": calc_sha256(build_a_json_path),
            "build_b_sha256": calc_sha256(build_b_json_path),
            "build_a_structure_sha256": calc_sha256(struct_a_path),
            "build_b_structure_sha256": calc_sha256(struct_b_path),
            "real_installation_sha256": calc_sha256(real_inst_path),
            "uefi_serial_sha256": calc_sha256(serial_log_paths["uefi-installed-boot.serial.log"]),
            "bios_serial_sha256": calc_sha256(serial_log_paths["bios-installed-boot.serial.log"]),
            "uefi_guest_validation_sha256": calc_sha256(guest_log_paths["uefi-guest-validation.log"]),
            "bios_guest_validation_sha256": calc_sha256(guest_log_paths["bios-guest-validation.log"]),
            "uefi_second_boot_validation_sha256": calc_sha256(guest_log_paths["uefi-second-boot-validation.log"]),
            "bios_second_boot_validation_sha256": calc_sha256(guest_log_paths["bios-second-boot-validation.log"]),
            "reproducibility_sha256": calc_sha256(repro_path),
            "documentation_sha256": calc_sha256(doc_path)
        }
    }

    os.makedirs(os.path.dirname(provenance_file), exist_ok=True)
    with open(provenance_file, "w", encoding="utf-8") as f:
        json.dump(prov_data, f, indent=2)
        f.write("\n")

    print(f"[PASS] Successfully generated release gate JSON: {output_gate}")
    print(f"[PASS] Successfully generated active artifact provenance JSON: {provenance_file}")

if __name__ == "__main__":
    main()
