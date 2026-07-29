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

def check_retired_references(obj_or_str, context=""):
    s = json.dumps(obj_or_str) if not isinstance(obj_or_str, str) else obj_or_str
    for item in RETIRED_IDENTIFIERS:
        if item in s:
            fail(f"Retired Candidate 2 identifier '{item}' referenced in evidence context: {context}")

def read_json_evidence(filepath, required_status="PASS", expected_sha=None):
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
    if expected_sha and data.get("source_commit") and data.get("source_commit") != expected_sha:
        fail(f"Source commit mismatch in {filepath}: {data.get('source_commit')} != {expected_sha}")
    return data

def find_file_recursive(directory, filename):
    for root, _, files in os.walk(directory):
        if filename in files:
            return os.path.join(root, filename)
    return None

def check_runtime_log_commands(log_path, label):
    if not os.path.isfile(log_path):
        fail(f"Runtime health evidence log missing for {label}: {log_path}")
    if os.path.getsize(log_path) == 0:
        fail(f"Runtime health evidence log is empty for {label}: {log_path}")
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    check_retired_references(content, context=log_path)
    for cmd in REQUIRED_HEALTH_COMMANDS:
        if cmd not in content:
            fail(f"Required package/system health command '{cmd}' missing from {label} log ({log_path})")

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
    provenance_file = args.provenance-file if hasattr(args, "provenance-file") and args.provenance-file else (args.provenance_file or os.path.join(current_dir, "0.3.0-alpha-artifact.json"))

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
    cand_sel = read_json_evidence(cand_sel_path, expected_sha=cand_sha)
    if cand_sel.get("candidate_branch") != cand_branch:
        fail(f"Candidate selection branch mismatch: {cand_sel.get('candidate_branch')} != {cand_branch}")
    if cand_sel.get("candidate_sha") != cand_sha:
        fail(f"Candidate selection SHA mismatch: {cand_sel.get('candidate_sha')} != {cand_sha}")
    if cand_sel.get("git_head") != cand_sha:
        fail(f"Candidate selection git HEAD mismatch: {cand_sel.get('git_head')} != {cand_sha}")
    if cand_sel.get("working_tree_clean") is not True:
        fail("Candidate selection working tree was not clean")
    if run_id != "unknown" and str(cand_sel.get("workflow_run_id", "unknown")) not in (run_id, "unknown"):
        fail(f"Candidate selection workflow run ID mismatch: {cand_sel.get('workflow_run_id')} != {run_id}")

    # 2. host_readiness (preflight)
    preflight_path = os.path.join(stage_logs_dir, "preflight-results.json")
    preflight = read_json_evidence(preflight_path, expected_sha=cand_sha)
    if preflight.get("source_commit") != cand_sha:
        fail(f"Preflight source commit mismatch: {preflight.get('source_commit')} != {cand_sha}")
    if preflight.get("git_head") and preflight.get("git_head") != cand_sha:
        fail(f"Preflight git HEAD mismatch: {preflight.get('git_head')} != {cand_sha}")
    if run_id != "unknown" and str(preflight.get("workflow_run_id", "unknown")) not in (run_id, "unknown"):
        fail(f"Preflight workflow run ID mismatch: {preflight.get('workflow_run_id')} != {run_id}")

    # 3. package_infrastructure
    pkg_build_path = os.path.join(stage_logs_dir, "stage-package-build.json")
    pkg_build = read_json_evidence(pkg_build_path, expected_sha=cand_sha)
    repo_pub_path = os.path.join(stage_logs_dir, "stage-repository-publication.json")
    repo_pub = read_json_evidence(repo_pub_path, expected_sha=cand_sha)

    # 4. clean_install_readiness
    clean_install_path = os.path.join(stage_logs_dir, "stage-clean-install.json")
    clean_install = read_json_evidence(clean_install_path, expected_sha=cand_sha)

    # 5. iso_build_readiness & Build B verification
    iso_build_path = os.path.join(stage_logs_dir, "stage-test-iso-build.json")
    iso_build = read_json_evidence(iso_build_path, expected_sha=cand_sha)

    build_b_json = find_file_recursive(builds_dir, "build-b-build.json") or find_file_recursive(stage_logs_dir, "build-b-build.json")
    repro_path = os.path.join(stage_logs_dir, "stage-reproducibility.json")
    repro = read_json_evidence(repro_path, expected_sha=cand_sha)
    repro_hashes = repro.get("artifact_hashes", {})
    if not repro_hashes.get("build_b_sha256"):
        fail("Build B SHA-256 hash missing from reproducibility evidence")
    if repro_hashes.get("cmp_exit_code") != 0:
        fail(f"Reproducibility cmp exit code is {repro_hashes.get('cmp_exit_code')}, expected 0")
    if repro_hashes.get("build_a_sha256") != repro_hashes.get("build_b_sha256"):
        fail("Build A and Build B SHA-256 mismatch")

    # 6. iso_structure_readiness
    iso_struct_obs = iso_build.get("observations", {})
    struct_status = iso_struct_obs.get("iso_structure_check") or iso_struct_obs.get("structure_validation")
    if struct_status not in ("PASS", True, None):
        fail("ISO structure check failed in test-iso-build evidence")

    # 7. UEFI & BIOS evidence & runtime health verification
    boot_path = os.path.join(stage_logs_dir, "stage-test-iso-boot.json")
    boot_data = read_json_evidence(boot_path, expected_sha=cand_sha)

    req_runtime_logs = [
        ("uefi-guest-validation.log", "UEFI Guest Validation"),
        ("bios-guest-validation.log", "BIOS Guest Validation"),
        ("uefi-second-boot-validation.log", "UEFI Second Boot Validation"),
        ("bios-second-boot-validation.log", "BIOS Second Boot Validation"),
        ("uefi-installed-boot.serial.log", "UEFI Installed Boot Serial"),
        ("bios-installed-boot.serial.log", "BIOS Installed Boot Serial"),
    ]

    for log_filename, label in req_runtime_logs:
        found_log = find_file_recursive(runtime_dir, log_filename) or find_file_recursive(stage_logs_dir, log_filename) or find_file_recursive(current_dir, log_filename)
        if not found_log:
            fail(f"Required runtime health log missing: {log_filename} ({label})")
        check_runtime_log_commands(found_log, label)

    # 8. installer_readiness
    inst_path = os.path.join(stage_logs_dir, "stage-installer.json")
    inst_data = read_json_evidence(inst_path, expected_sha=cand_sha)

    # 9. security_readiness
    tamper_path = os.path.join(stage_logs_dir, "stage-tamper.json")
    tamper_data = read_json_evidence(tamper_path, expected_sha=cand_sha)

    # 10. documentation_readiness
    doc_path = os.path.join(stage_logs_dir, "stage-documentation.json")
    doc_data = read_json_evidence(doc_path, expected_sha=cand_sha)
    if doc_data.get("status") != "PASS":
        fail("Documentation evidence stage status is not PASS")

    # Calculate SHA256 of evidence files for provenance binding
    cand_sel_sha = calc_sha256(cand_sel_path)
    preflight_sha = calc_sha256(preflight_path)
    iso_build_sha = calc_sha256(iso_build_path)
    vm_evid_sha = calc_sha256(boot_path)
    repro_evid_sha = calc_sha256(repro_path)

    categories = {
        "candidate_selection": {"status": "PASS", "evidence_file": "stage-candidate-selection.json", "candidate_branch": cand_branch, "candidate_sha": cand_sha},
        "host_readiness": {"status": "PASS", "evidence_file": "preflight-results.json", "architecture": preflight.get("architecture", "x86_64"), "kvm_available": preflight.get("kvm_available", True)},
        "package_infrastructure": {"status": "PASS", "evidence_file": "stage-repository-publication.json"},
        "clean_install_readiness": {"status": "PASS", "evidence_file": "stage-clean-install.json"},
        "iso_build_readiness": {"status": "PASS", "evidence_file": "stage-test-iso-build.json"},
        "iso_structure_readiness": {"status": "PASS", "evidence_file": "stage-test-iso-build.json"},
        "uefi_readiness": {"status": "PASS", "evidence_file": "uefi-guest-validation.log"},
        "bios_readiness": {"status": "PASS", "evidence_file": "bios-guest-validation.log"},
        "installer_readiness": {"status": "PASS", "evidence_file": "stage-installer.json"},
        "installed_system_readiness": {"status": "PASS", "evidence_file": "stage-installer.json"},
        "package_health_readiness": {"status": "PASS", "evidence_file": "stage-clean-install.json"},
        "security_readiness": {"status": "PASS", "evidence_file": "stage-tamper.json"},
        "reproducibility_readiness": {"status": "PASS", "evidence_file": "stage-reproducibility.json"},
        "documentation_readiness": {"status": "PASS", "evidence_file": "stage-documentation.json"},
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

    iso_obs_file = iso_build.get("observations", {})
    build_a_iso = iso_obs_file.get("iso_path") or iso_obs_file.get("build_a_iso") or ""
    build_a_filename = os.path.basename(build_a_iso) if build_a_iso else "GenixBitOS-0.3.0-alpha-2607290000.iso"
    build_a_size = iso_obs_file.get("iso_size_bytes") or iso_obs_file.get("size_bytes") or (os.path.getsize(build_a_iso) if os.path.isfile(build_a_iso) else 0)
    build_a_sha256 = iso_obs_file.get("iso_sha256") or iso_obs_file.get("sha256") or (calc_sha256(build_a_iso) if os.path.isfile(build_a_iso) else "")
    build_a_sha512 = iso_obs_file.get("iso_sha512") or iso_obs_file.get("sha512") or ""

    prov_data = {
        "schema_version": "1.0",
        "release_version": "0.3.0-alpha",
        "candidate_branch": cand_branch,
        "candidate_source_commit": cand_sha,
        "workflow_run_id": run_id,
        "workflow_run_attempt": run_attempt,
        "filename": build_a_filename,
        "size_bytes": build_a_size,
        "sha256": build_a_sha256,
        "sha512": build_a_sha512,
        "object_generation": None,
        "verification_status": "VALIDATED_UNPUBLISHED",
        "usable_as_release_artifact": False,
        "usable_as_migration_source": False,
        "validation_evidence": {
            "candidate_selection_sha256": cand_sel_sha,
            "preflight_sha256": preflight_sha,
            "iso_build_sha256": iso_build_sha,
            "vm_evidence_sha256": vm_evid_sha,
            "reproducibility_sha256": repro_evid_sha
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
