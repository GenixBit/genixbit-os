#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Release Gate Integrity & Execution Validation Checker for GenixBit OS
# Enforces executed validation evidence and summary count consistency.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
GATE_FILE="$REPO_ROOT/docs/releases/0.3.0-release-gate.json"

usage() {
    cat <<EOF
Usage: check-release-gate.sh [--gate-file PATH]

Options:
  --gate-file PATH    Path to release gate JSON file (default: docs/releases/0.3.0-release-gate.json).
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

python3 - "$REPO_ROOT" "$GATE_FILE" <<'PYEOF'
import sys, os, json, subprocess

repo_root = sys.argv[1]
gate_file = sys.argv[2]

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

rep_pass = summary.get("pass_count")
rep_fail = summary.get("fail_count")
rep_blocked = summary.get("blocked_count")
rep_not_tested = summary.get("not_tested_count")

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

print(f"[PASS] Summary counters consistent (PASS={actual_pass}, FAIL={actual_fail}, BLOCKED={actual_blocked}, NOT TESTED={actual_not_tested}).")

# 2. Overall Gate Status Consistency Verification
overall_status = summary.get("overall_gate_status", "")
if actual_fail > 0:
    if "PASS" in overall_status:
        print(f"[FAIL] overall_gate_status cannot be '{overall_status}' when fail_count={actual_fail}!")
        sys.exit(1)

# 3. Executed Validation Requirement for vm_readiness = PASS
vm_status = categories.get("vm_readiness", {}).get("status")
if vm_status == "PASS":
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
