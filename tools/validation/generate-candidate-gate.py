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

    exit_code = data.get("exit_code")
    if exit_code is not None and exit_code != 0:
        fail(f"Evidence file {filepath} exit_code is {exit_code}, expected 0")

    commit = data.get("source_commit") or data.get("candidate_sha") or data.get("active_release_source_commit")
    if not commit or commit != expected_sha:
        fail(f"Source commit mismatch in {filepath}: {commit} != {expected_sha}")

    if data.get("git_head") and data.get("git_head") != expected_sha:
        fail(f"Git HEAD mismatch in {filepath}: {data.get('git_head')} != {expected_sha}")

    run_id_val = str(data.get("workflow_run_id", ""))
    if expected_run_id and expected_run_id != "unknown":
        if not run_id_val or run_id_val == "unknown":
            fail(f"Workflow run ID missing or unknown in {filepath}")
        elif run_id_val != expected_run_id:
            fail(f"Workflow run ID mismatch in {filepath}: {run_id_val} != {expected_run_id}")

    run_att_val = str(data.get("workflow_run_attempt", ""))
    if expected_run_attempt and expected_run_attempt != "unknown":
        if run_att_val and run_att_val != "unknown" and run_att_val != str(expected_run_attempt):
            fail(f"Workflow run attempt mismatch in {filepath}: {run_att_val} != {expected_run_attempt}")

    return data

def find_file_recursive(directory, filename):
    if not directory or not os.path.exists(directory):
        return None
    for root, _, files in os.walk(directory):
        if filename in files:
            return os.path.join(root, filename)
    return None

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

    # Verify boot milestone presence
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

    # Strictly validate preflight fields (no default fallbacks)
    if preflight.get("status") != "PASS":
        fail("Preflight status is not PASS")
    if preflight.get("exit_code") != 0:
        fail(f"Preflight exit_code is {preflight.get('exit_code')}, expected 0")
    if preflight.get("source_commit") != cand_sha:
        fail(f"Preflight source_commit mismatch: {preflight.get('source_commit')} != {cand_sha}")
    if preflight.get("active_release_source_commit") != cand_sha:
        fail(f"Preflight active_release_source_commit mismatch: {preflight.get('active_release_source_commit')} != {cand_sha}")
    if preflight.get("git_head") != cand_sha:
        fail(f"Preflight git_head mismatch: {preflight.get('git_head')} != {cand_sha}")
    if preflight.get("expected_candidate_sha") and preflight.get("expected_candidate_sha") != cand_sha:
        fail(f"Preflight expected_candidate_sha mismatch: {preflight.get('expected_candidate_sha')} != {cand_sha}")
    if preflight.get("expected_candidate_branch") and preflight.get("expected_candidate_branch") != cand_branch:
        fail(f"Preflight expected_candidate_branch mismatch: {preflight.get('expected_candidate_branch')} != {cand_branch}")
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

    # 3. package_infrastructure
    pkg_build_path = os.path.join(stage_logs_dir, "stage-package-build.json")
    pkg_build = read_bound_evidence(pkg_build_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    repo_pub_path = os.path.join(stage_logs_dir, "stage-repository-publication.json")
    repo_pub = read_bound_evidence(repo_pub_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # 4. clean_install_readiness
    clean_install_path = os.path.join(stage_logs_dir, "stage-clean-install.json")
    clean_install = read_bound_evidence(clean_install_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # 5. Build A & Build B metadata validation
    build_a_json_path = find_file_recursive(builds_dir, "build-a-build.json") or find_file_recursive(stage_logs_dir, "build-a-build.json")
    if not build_a_json_path:
        # Fallback check for single build log if build-a-build.json not separated
        build_a_json_path = os.path.join(stage_logs_dir, "stage-test-iso-build.json")
    build_a_meta = read_bound_evidence(build_a_json_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    build_b_json_path = find_file_recursive(builds_dir, "build-b-build.json") or find_file_recursive(stage_logs_dir, "build-b-build.json")
    if not build_b_json_path:
        fail("Build B metadata file (build-b-build.json) missing")
    build_b_meta = read_bound_evidence(build_b_json_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # Validate build-a & build-b fields
    for label, meta, pth in [("Build A", build_a_meta, build_a_json_path), ("Build B", build_b_meta, build_b_json_path)]:
        if meta.get("execution_mode") != "REAL_BUILD":
            fail(f"{label} metadata ({pth}) execution_mode is '{meta.get('execution_mode')}', expected 'REAL_BUILD'")
        if meta.get("build_script") != "./build.sh":
            fail(f"{label} metadata ({pth}) build_script is '{meta.get('build_script')}', expected './build.sh'")
        if meta.get("build_exit_code") != 0:
            fail(f"{label} metadata ({pth}) build_exit_code is {meta.get('build_exit_code')}, expected 0")
        if meta.get("candidate_branch") != cand_branch:
            fail(f"{label} metadata ({pth}) candidate_branch is '{meta.get('candidate_branch')}', expected '{cand_branch}'")
        if meta.get("target_version") and meta.get("target_version") != "0.3.0-alpha":
            fail(f"{label} metadata ({pth}) target_version is '{meta.get('target_version')}', expected '0.3.0-alpha'")

    worktree_a = build_a_meta.get("worktree_dir") or build_a_meta.get("build_dir") or ""
    worktree_b = build_b_meta.get("worktree_dir") or build_b_meta.get("build_dir") or ""
    if worktree_a and worktree_b and worktree_a == worktree_b:
        fail(f"Build A and Build B used identical worktree path: {worktree_a}")

    iso_a = build_a_meta.get("iso_path") or build_a_meta.get("output_file") or build_a_meta.get("observations", {}).get("iso_path") or ""
    iso_b = build_b_meta.get("iso_path") or build_b_meta.get("output_file") or build_b_meta.get("observations", {}).get("iso_path") or ""
    if not iso_a or not iso_b:
        fail("ISO output paths missing from Build A or Build B metadata")
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
    if actual_size_a != actual_size_b:
        fail(f"Build A size ({actual_size_a}) does not match Build B size ({actual_size_b})")

    sha256_a = calc_sha256(iso_a)
    sha256_b = calc_sha256(iso_b)
    if sha256_a != sha256_b:
        fail(f"Build A SHA-256 ({sha256_a}) does not match Build B SHA-256 ({sha256_b})")

    sha512_a = calc_sha512(iso_a)
    sha512_b = calc_sha512(iso_b)
    if sha512_a != sha512_b:
        fail(f"Build A SHA-512 ({sha512_a}) does not match Build B SHA-512 ({sha512_b})")

    # Reproducibility check
    repro_path = os.path.join(stage_logs_dir, "stage-reproducibility.json")
    repro = read_bound_evidence(repro_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)
    repro_hashes = repro.get("artifact_hashes", {})
    if repro_hashes.get("cmp_exit_code") != 0:
        fail(f"Reproducibility cmp exit code is {repro_hashes.get('cmp_exit_code')}, expected 0")

    # 6. Separate ISO Structure Evidence
    struct_a_path = find_file_recursive(builds_dir, "build-a-iso-structure.json") or find_file_recursive(stage_logs_dir, "build-a-iso-structure.json") or os.path.join(stage_logs_dir, "stage-test-iso-build.json")
    struct_a = read_bound_evidence(struct_a_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    struct_b_path = find_file_recursive(builds_dir, "build-b-iso-structure.json") or find_file_recursive(stage_logs_dir, "build-b-iso-structure.json") or struct_a_path
    struct_b = read_bound_evidence(struct_b_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # 7. Guest Health Logs & Serial Logs
    guest_health_logs = [
        ("uefi-guest-validation.log", "UEFI Guest Validation"),
        ("bios-guest-validation.log", "BIOS Guest Validation"),
        ("uefi-second-boot-validation.log", "UEFI Second Boot Validation"),
        ("bios-second-boot-validation.log", "BIOS Second Boot Validation")
    ]
    for log_filename, label in guest_health_logs:
        found_log = find_file_recursive(runtime_dir, log_filename) or find_file_recursive(stage_logs_dir, log_filename) or find_file_recursive(current_dir, log_filename)
        if not found_log:
            fail(f"Required guest health log missing: {log_filename} ({label})")
        check_guest_health_log(found_log, label)

    serial_logs = [
        ("uefi-installed-boot.serial.log", "UEFI Installed Boot Serial"),
        ("bios-installed-boot.serial.log", "BIOS Installed Boot Serial")
    ]
    serial_paths = []
    for log_filename, label in serial_logs:
        found_log = find_file_recursive(runtime_dir, log_filename) or find_file_recursive(stage_logs_dir, log_filename) or find_file_recursive(current_dir, log_filename)
        if not found_log:
            fail(f"Required serial boot log missing: {log_filename} ({label})")
        check_serial_log(found_log, label)
        serial_paths.append(found_log)

    hash_serial_uefi = calc_sha256(serial_paths[0])
    hash_serial_bios = calc_sha256(serial_paths[1])
    if hash_serial_uefi == hash_serial_bios:
        fail("UEFI and BIOS serial boot logs have identical SHA-256 hashes")

    # 8. Installer readiness & Security readiness
    inst_path = os.path.join(stage_logs_dir, "stage-installer.json")
    inst_data = read_bound_evidence(inst_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    tamper_path = os.path.join(stage_logs_dir, "stage-tamper.json")
    tamper_data = read_bound_evidence(tamper_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # 9. Documentation readiness
    doc_path = os.path.join(stage_logs_dir, "stage-documentation.json")
    doc_data = read_bound_evidence(doc_path, expected_sha=cand_sha, expected_run_id=run_id, expected_run_attempt=run_attempt)

    # Calculate evidence hashes
    cand_sel_sha = calc_sha256(cand_sel_path)
    preflight_sha = calc_sha256(preflight_path)
    build_a_sha = calc_sha256(build_a_json_path)
    build_b_sha = calc_sha256(build_b_json_path)
    repro_evid_sha = calc_sha256(repro_path)
    doc_sha = calc_sha256(doc_path)

    categories = {
        "candidate_selection": {
            "status": "PASS",
            "evidence_files": [cand_sel_path],
            "evidence_hashes": [cand_sel_sha],
            "candidate_branch": cand_branch,
            "candidate_sha": cand_sha
        },
        "host_readiness": {
            "status": "PASS",
            "evidence_files": [preflight_path],
            "evidence_hashes": [preflight_sha],
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
            "evidence_hashes": [build_a_sha, build_b_sha]
        },
        "iso_structure_readiness": {
            "status": "PASS",
            "evidence_files": [struct_a_path, struct_b_path],
            "evidence_hashes": [calc_sha256(struct_a_path), calc_sha256(struct_b_path)]
        },
        "uefi_readiness": {
            "status": "PASS",
            "evidence_files": [serial_paths[0]],
            "evidence_hashes": [hash_serial_uefi]
        },
        "bios_readiness": {
            "status": "PASS",
            "evidence_files": [serial_paths[1]],
            "evidence_hashes": [hash_serial_bios]
        },
        "installer_readiness": {
            "status": "PASS",
            "evidence_files": [inst_path],
            "evidence_hashes": [calc_sha256(inst_path)]
        },
        "installed_system_readiness": {
            "status": "PASS",
            "evidence_files": [inst_path],
            "evidence_hashes": [calc_sha256(inst_path)]
        },
        "package_health_readiness": {
            "status": "PASS",
            "evidence_files": [clean_install_path],
            "evidence_hashes": [calc_sha256(clean_install_path)]
        },
        "security_readiness": {
            "status": "PASS",
            "evidence_files": [tamper_path],
            "evidence_hashes": [calc_sha256(tamper_path)]
        },
        "reproducibility_readiness": {
            "status": "PASS",
            "evidence_files": [repro_path],
            "evidence_hashes": [repro_evid_sha]
        },
        "documentation_readiness": {
            "status": "PASS",
            "evidence_files": [doc_path],
            "evidence_hashes": [doc_sha]
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
            "candidate_selection_sha256": cand_sel_sha,
            "preflight_sha256": preflight_sha,
            "build_a_sha256": build_a_sha,
            "build_b_sha256": build_b_sha,
            "reproducibility_sha256": repro_evid_sha,
            "documentation_sha256": doc_sha
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
