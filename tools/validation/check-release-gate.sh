#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Release Gate Integrity & Execution Validation Checker for GenixBit OS
# Enforces executed validation evidence and summary count consistency.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
GATE_FILE="$REPO_ROOT/docs/releases/0.3.0-release-gate.json"
PROVENANCE_FILE=""

usage() {
    cat <<EOF
Usage: check-release-gate.sh [--gate-file PATH] [--provenance-file PATH]

Options:
  --gate-file PATH    Path to release gate JSON file (default: docs/releases/0.3.0-release-gate.json).
  --provenance-file PATH  Run-scoped active artifact provenance for candidate validation.
  -h, --help          Show this help.
EOF
}

fail() {
    printf '[FAIL] Release Gate Validator Error: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

while (($# > 0)); do
    case "$1" in
        --gate-file)
            (($# >= 2)) || fail '--gate-file requires a path.'
            GATE_FILE=$2
            shift 2
            ;;
        --provenance-file)
            (($# >= 2)) || fail '--provenance-file requires a path.'
            PROVENANCE_FILE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -f "$GATE_FILE" ]] || fail "Release gate JSON file not found: $GATE_FILE"

info "Validating release gate JSON: $GATE_FILE"

python3 - "$REPO_ROOT" "$GATE_FILE" "$PROVENANCE_FILE" <<'PYEOF'
import sys, os, json, subprocess

repo_root = sys.argv[1]
gate_file = sys.argv[2]
provenance_file = sys.argv[3]

with open(gate_file, "r") as f:
    try:
        data = json.load(f)
    except Exception as e:
        print(f"[FAIL] Invalid JSON syntax in {gate_file}: {e}")
        sys.exit(1)

categories = data.get("categories", {})
summary = data.get("summary", {})

if not categories:
    print(f"[FAIL] Missing categories object in {gate_file}")
    sys.exit(1)

# 1. Summary Counter Consistency Verification
actual_pass = sum(1 for c in categories.values() if c.get("status") == "PASS")
actual_fail = sum(1 for c in categories.values() if c.get("status") in ("FAIL", "RETIRED"))
actual_blocked = sum(1 for c in categories.values() if c.get("status") == "BLOCKED")
actual_not_tested = sum(1 for c in categories.values() if c.get("status") == "NOT TESTED")
actual_not_applicable = sum(1 for c in categories.values() if c.get("status") == "NOT_APPLICABLE")

rep_pass = summary.get("pass_count")
rep_fail = summary.get("fail_count")
rep_blocked = summary.get("blocked_count")
rep_not_tested = summary.get("not_tested_count")
rep_not_applicable = summary.get("not_applicable_count", 0)

if rep_pass != actual_pass:
    print(f"[FAIL] pass_count mismatch: reported {rep_pass}, actual {actual_pass}")
    sys.exit(1)

if rep_fail != actual_fail:
    print(f"[FAIL] fail_count mismatch: reported {rep_fail}, actual {actual_fail}")
    sys.exit(1)

if rep_blocked != actual_blocked:
    print(f"[FAIL] blocked_count mismatch: reported {rep_blocked}, actual {actual_blocked}")
    sys.exit(1)

if rep_not_tested != actual_not_tested:
    print(f"[FAIL] not_tested_count mismatch: reported {rep_not_tested}, actual {actual_not_tested}")
    sys.exit(1)

if rep_not_applicable != actual_not_applicable:
    print(f"[FAIL] not_applicable_count mismatch: reported {rep_not_applicable}, actual {actual_not_applicable}")
    sys.exit(1)

print(f"[PASS] Summary counters consistent (PASS={actual_pass}, FAIL={actual_fail}, BLOCKED={actual_blocked}, NOT TESTED={actual_not_tested}, NOT_APPLICABLE={actual_not_applicable}).")

# 2. Overall Gate Status Consistency Verification
overall_status = summary.get("overall_gate_status", "")
if actual_fail > 0:
    if "PASS" in overall_status:
        print(f"[FAIL] overall_gate_status cannot be '{overall_status}' when fail_count={actual_fail}!")
        sys.exit(1)

required_candidate_categories = [
    "candidate_selection", "host_readiness", "package_infrastructure",
    "clean_install_readiness", "iso_build_readiness", "iso_structure_readiness",
    "uefi_readiness", "bios_readiness", "installer_readiness",
    "installed_system_readiness", "package_health_readiness", "security_readiness",
    "reproducibility_readiness", "documentation_readiness",
]

if overall_status == "PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION":
    missing = [key for key in required_candidate_categories if key not in categories]
    if missing:
        print(f"[FAIL] candidate validation gate missing required categories: {missing}")
        sys.exit(1)
    non_pass = [key for key in required_candidate_categories if categories.get(key, {}).get("status") != "PASS"]
    if non_pass or actual_fail or actual_blocked or actual_not_tested:
        print(f"[FAIL] candidate validation awaiting publication requires all mandatory categories PASS; non_pass={non_pass}")
        sys.exit(1)
    if summary.get("release_ready") is not False or summary.get("stable_ready") is not False:
        print("[FAIL] candidate validation awaiting immutable publication requires release_ready=false and stable_ready=false")
        sys.exit(1)
    if categories.get("upgrade_readiness", {}).get("status") == "PASS" or categories.get("rollback_readiness", {}).get("status") == "PASS":
        print("[FAIL] upgrade/rollback must not be PASS in fresh-install-only validation")
        sys.exit(1)
    stage_repro = os.path.join(repo_root, "infra/package-staging/results/stage-logs/stage-reproducibility.json")
    if not os.path.isfile(stage_repro):
        print(f"[FAIL] reproducibility evidence missing: {stage_repro}")
        sys.exit(1)
    with open(stage_repro, encoding="utf-8") as f:
        repro = json.load(f)
    hashes = repro.get("artifact_hashes", {})
    if repro.get("status") != "PASS" or hashes.get("cmp_exit_code") != 0 or not hashes.get("build_b_sha256"):
        print("[FAIL] Build B reproducibility evidence is incomplete or failed")
        sys.exit(1)
    if not provenance_file:
        provenance_file = data.get("active_artifact_provenance", "")
    if not provenance_file or not os.path.isfile(provenance_file):
        print(f"[FAIL] run-scoped active provenance missing: {provenance_file}")
        sys.exit(1)
    with open(provenance_file, encoding="utf-8") as f:
        provenance = json.load(f)
    if provenance.get("verification_status") in ("PENDING_BUILD", "BUILT_UNVALIDATED"):
        print("[FAIL] active provenance is not runtime validated")
        sys.exit(1)
    if provenance.get("verification_status") == "PASS":
        print("[FAIL] active provenance must not be PASS before immutable publication")
        sys.exit(1)
    if provenance.get("verification_status") != "VALIDATED_UNPUBLISHED":
        print(f"[FAIL] unexpected active provenance status: {provenance.get('verification_status')}")
        sys.exit(1)
    if provenance.get("object_generation") is not None or provenance.get("usable_as_release_artifact") is not False:
        print("[FAIL] unpublished provenance must keep object_generation=null and usability=false")
        sys.exit(1)
    retired = {"GenixBitOS-0.2.0-alpha-2607220558.iso", "1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669", "51bdb60298460d1204dd6b641ed7d531c9d34da98fecf90fbfbbabf9beeef0dc42fe86e59646c7cd4c8746b1c5e48d05afc81712758c51cb2096a77c45e0902e", "1784810864397202"}
    if any(str(v) in retired for v in provenance.values()):
        print("[FAIL] active artifact provenance uses a retired Candidate 2 identifier")
        sys.exit(1)

if os.path.abspath(gate_file).endswith("docs/releases/0.3.0-release-gate.json") and overall_status == "BLOCKED_INVALID_RELEASE_EVIDENCE":
    print("[PASS] committed blocked release-gate template validated as historical status")
elif overall_status == "BLOCKED_INVALID_RELEASE_EVIDENCE":
    print("[FAIL] run-scoped candidate validation cannot end with old BLOCKED_INVALID_RELEASE_EVIDENCE status")
    sys.exit(1)

na_reason = "No valid prior GenixBit OS release artifact exists from which to execute an upgrade or rollback test."
for key in ("upgrade_readiness", "rollback_readiness"):
    cat = categories.get(key, {})
    if cat.get("status") == "NOT_APPLICABLE" and cat.get("reason") != na_reason:
        print(f"[FAIL] {key} is NOT_APPLICABLE without the required factual reason")
        sys.exit(1)

if overall_status == "PASS_ALPHA_FRESH_INSTALL":
    mandatory = ["clean_install_readiness", "vm_readiness", "installer_readiness", "package_health_readiness", "reproducibility_readiness"]
    missing = [key for key in mandatory if categories.get(key, {}).get("status") != "PASS"]
    if missing or actual_fail or actual_blocked:
        print(f"[FAIL] PASS_ALPHA_FRESH_INSTALL requires mandatory PASS categories and no failures/blockers; missing={missing}")
        sys.exit(1)
    if summary.get("release_ready") is not True or summary.get("stable_ready") is not False:
        print("[FAIL] PASS_ALPHA_FRESH_INSTALL requires release_ready=true and stable_ready=false")
        sys.exit(1)

# 3. Legacy committed-template validation for vm_readiness = PASS
vm_status = categories.get("vm_readiness", {}).get("status")
if vm_status == "PASS" and overall_status != "PASS_VALIDATION_AWAITING_IMMUTABLE_PUBLICATION":
    # If vm_readiness is PASS, check if candidate 1 environment was retired
    cand1_env = os.path.join(repo_root, "docs/releases/0.3.0-alpha-candidate-1.env")
    if os.path.exists(cand1_env):
        with open(cand1_env, "r") as f:
            if "VALIDATION_STATUS=FAIL" in f.read():
                print("[FAIL] vm_readiness cannot be PASS when Candidate 1 is retired!")
                sys.exit(1)

    # Must verify real ISO file & structural check
    iso_file = os.path.join(repo_root, "dist/GenixBitOS-0.3.0-alpha-internal.iso")
    if not os.path.isfile(iso_file):
        print(f"[FAIL] vm_readiness is PASS but real ISO artifact is missing: {iso_file}")
        sys.exit(1)

    checker = os.path.join(repo_root, "tools/validation/check-iso-structure.sh")
    res = subprocess.run(["bash", checker, "--iso", iso_file], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[FAIL] vm_readiness is PASS but ISO structural check failed:\n{res.stderr}")
        sys.exit(1)

print(f"[PASS] Release gate {gate_file} integrity verified.")
PYEOF

if (($? != 0)); then
    fail "Release gate validation failed for $GATE_FILE"
fi

pass "=== Release Gate Check Passed for $GATE_FILE ==="
exit 0
