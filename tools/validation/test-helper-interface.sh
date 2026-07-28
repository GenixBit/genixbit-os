#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executable interface compatibility test suite for GenixBit OS helper scripts.
# Verifies argument parsers, required flags, and caller invocation correctness.
# Tests 1-15 as required by the release gate specification.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=()

pass_test() {
    PASS_COUNT=$(( PASS_COUNT + 1 ))
    printf '[PASS] %s\n' "$1"
}

fail_test() {
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    FAIL_NAMES+=("$1")
    printf '[FAIL] %s\n' "$1" >&2
}

info() { printf '[INFO] %s\n' "$*"; }

info "=== Running Helper Script Interface Compatibility Tests ==="

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

WAIT_SCRIPT="$REPO_ROOT/tools/vm/wait-for-guest.sh"
GUEST_SCRIPT="$REPO_ROOT/tools/vm/guest-command.sh"
INSTALL_CAND2="$REPO_ROOT/tools/vm/install-candidate2.sh"
MIGRATE_CAND2="$REPO_ROOT/tools/vm/migrate-candidate2.sh"
INSTALL_CURRENT="$REPO_ROOT/tools/vm/install-current-iso.sh"
VALIDATE_MIG="$REPO_ROOT/tools/validation/validate-package-migration.sh"
RELEASE_GATE_YML="$REPO_ROOT/.github/workflows/release-gate.yml"
PROVENANCE="$REPO_ROOT/docs/releases/0.2.0-alpha-artifact.json"

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: Every wait-for-guest.sh caller uses supported arguments (no --vm-id)
# ─────────────────────────────────────────────────────────────────────────────
info "Test 1: wait-for-guest.sh callers must not pass --vm-id..."
CALLERS=("$INSTALL_CAND2" "$MIGRATE_CAND2" "$INSTALL_CURRENT")
T1_FAIL=false
for f in "${CALLERS[@]}"; do
    if ! grep -q "wait-for-guest.sh" "$f" 2>/dev/null; then
        continue
    fi
    # Use Python to extract the argument continuation blocks after each wait-for-guest.sh line.
    # Reads successive lines starting with whitespace+-- (shell continuation args),
    # stops at first non-arg line. This avoids false positives from adjacent script calls.
    VMID_FOUND=$(python3 - "$f" <<'PYEOF'
import sys, re
path = sys.argv[1]
lines = open(path).read().splitlines()
found = False
for i, line in enumerate(lines):
    if "wait-for-guest.sh" in line:
        for j in range(i + 1, min(i + 30, len(lines))):
            arg_line = lines[j]
            if re.match(r'^\s+--', arg_line):
                if re.match(r'^\s+--vm-id\b', arg_line):
                    found = True
                    break
            else:
                # End of continuation block
                break
        if found:
            break
print("YES" if found else "NO")
PYEOF
)
    if [[ "$VMID_FOUND" == "YES" ]]; then
        fail_test "Test 1: $f passes unsupported --vm-id to wait-for-guest.sh"
        T1_FAIL=true
    fi
done
[[ "$T1_FAIL" == "false" ]] && pass_test "Test 1: No caller passes --vm-id to wait-for-guest.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: Every guest-command.sh caller uses --cmd, not --commands
# ─────────────────────────────────────────────────────────────────────────────
info "Test 2: guest-command.sh callers must not pass --commands..."
T2_FAIL=false
for f in "$INSTALL_CAND2" "$MIGRATE_CAND2" "$INSTALL_CURRENT"; do
    if grep -q "guest-command.sh" "$f" 2>/dev/null; then
        if grep -A 20 "guest-command.sh" "$f" 2>/dev/null | grep -q "^\s*--commands"; then
            fail_test "Test 2: $f passes unsupported --commands to guest-command.sh"
            T2_FAIL=true
        fi
    fi
done
[[ "$T2_FAIL" == "false" ]] && pass_test "Test 2: No caller passes --commands to guest-command.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: wait-for-guest.sh rejects missing --ssh-port
# ─────────────────────────────────────────────────────────────────────────────
info "Test 3: wait-for-guest.sh must reject missing --ssh-port..."
if bash "$WAIT_SCRIPT" --ssh-user genixbit > /dev/null 2>&1; then
    fail_test "Test 3: wait-for-guest.sh did NOT fail when --ssh-port was missing"
else
    pass_test "Test 3: wait-for-guest.sh correctly rejected missing --ssh-port"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 4: wait-for-guest.sh rejects unknown arguments
# ─────────────────────────────────────────────────────────────────────────────
info "Test 4: wait-for-guest.sh must reject unknown arguments..."
if bash "$WAIT_SCRIPT" --ssh-port 22222 --vm-id testvm > /dev/null 2>&1; then
    fail_test "Test 4: wait-for-guest.sh did NOT reject unknown argument --vm-id"
else
    pass_test "Test 4: wait-for-guest.sh correctly rejected unknown argument --vm-id"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 5: guest-command.sh rejects missing --ssh-port
# ─────────────────────────────────────────────────────────────────────────────
info "Test 5: guest-command.sh must reject missing --ssh-port..."
if bash "$GUEST_SCRIPT" --cmd "echo hi" > /dev/null 2>&1; then
    fail_test "Test 5: guest-command.sh did NOT fail when --ssh-port was missing"
else
    pass_test "Test 5: guest-command.sh correctly rejected missing --ssh-port"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 6: guest-command.sh rejects --commands (unknown arg)
# ─────────────────────────────────────────────────────────────────────────────
info "Test 6: guest-command.sh must reject --commands as unknown argument..."
if bash "$GUEST_SCRIPT" --ssh-port 22222 --commands "echo hi" > /dev/null 2>&1; then
    fail_test "Test 6: guest-command.sh did NOT reject unsupported --commands argument"
else
    pass_test "Test 6: guest-command.sh correctly rejected --commands as unknown argument"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 7: Operator workflow sets EXECUTE_REAL_ISO_BUILD=true
# ─────────────────────────────────────────────────────────────────────────────
info "Test 7: release-gate.yml must set EXECUTE_REAL_ISO_BUILD=true..."
if grep -q 'EXECUTE_REAL_ISO_BUILD.*true\|EXECUTE_REAL_ISO_BUILD=true' "$RELEASE_GATE_YML" 2>/dev/null; then
    pass_test "Test 7: release-gate.yml sets EXECUTE_REAL_ISO_BUILD=true"
else
    fail_test "Test 7: release-gate.yml does NOT set EXECUTE_REAL_ISO_BUILD=true"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 8: Operator workflow sets EXECUTE_REAL_CLIENT_INSTALL=true
# ─────────────────────────────────────────────────────────────────────────────
info "Test 8: release-gate.yml must set EXECUTE_REAL_CLIENT_INSTALL=true..."
if grep -q 'EXECUTE_REAL_CLIENT_INSTALL.*true\|EXECUTE_REAL_CLIENT_INSTALL=true' "$RELEASE_GATE_YML" 2>/dev/null; then
    pass_test "Test 8: release-gate.yml sets EXECUTE_REAL_CLIENT_INSTALL=true"
else
    fail_test "Test 8: release-gate.yml does NOT set EXECUTE_REAL_CLIENT_INSTALL=true"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 9: Operator workflow sets EXECUTE_REAL_MIGRATION=true
# ─────────────────────────────────────────────────────────────────────────────
info "Test 9: release-gate.yml must set EXECUTE_REAL_MIGRATION=true..."
if grep -q 'EXECUTE_REAL_MIGRATION.*true\|EXECUTE_REAL_MIGRATION=true' "$RELEASE_GATE_YML" 2>/dev/null; then
    pass_test "Test 9: release-gate.yml sets EXECUTE_REAL_MIGRATION=true"
else
    fail_test "Test 9: release-gate.yml does NOT set EXECUTE_REAL_MIGRATION=true"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 10: Operator workflow sets EXECUTE_REAL_VM_TESTS=true
# ─────────────────────────────────────────────────────────────────────────────
info "Test 10: release-gate.yml must set EXECUTE_REAL_VM_TESTS=true..."
if grep -q 'EXECUTE_REAL_VM_TESTS.*true\|EXECUTE_REAL_VM_TESTS=true' "$RELEASE_GATE_YML" 2>/dev/null; then
    pass_test "Test 10: release-gate.yml sets EXECUTE_REAL_VM_TESTS=true"
else
    fail_test "Test 10: release-gate.yml does NOT set EXECUTE_REAL_VM_TESTS=true"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 11: Missing required stage JSON causes evidence collection to fail
# ─────────────────────────────────────────────────────────────────────────────
info "Test 11: collect-migration-evidence.py must fail on missing stage JSON..."
DUMMY_EVIDENCE="$TMP/evidence_test"
mkdir -p "$DUMMY_EVIDENCE"
# Write only 3 of the 4 required stage files to trigger failure
echo '{"status":"PASS","source_commit":"abc"}' > "$DUMMY_EVIDENCE/stage-package-build.json"
echo '{"status":"PASS","source_commit":"abc"}' > "$DUMMY_EVIDENCE/stage-test-iso-build.json"
echo '{"status":"PASS","source_commit":"abc"}' > "$DUMMY_EVIDENCE/stage-test-iso-boot.json"
# stage-candidate-upgrade.json is intentionally missing
COLLECT_PY="$REPO_ROOT/tools/validation/collect-migration-evidence.py"
if python3 "$COLLECT_PY" --stage-logs-dir "$DUMMY_EVIDENCE" --output "$TMP/evidence-out.json" > /dev/null 2>&1; then
    fail_test "Test 11: collect-migration-evidence.py did NOT fail on missing stage-candidate-upgrade.json"
else
    pass_test "Test 11: collect-migration-evidence.py correctly failed with missing required stage JSON"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 12: Candidate 2 provenance file exists and records retired status
# ─────────────────────────────────────────────────────────────────────────────
info "Test 12: 0.2.0-alpha-artifact.json must exist with retired status..."
if [[ ! -f "$PROVENANCE" ]]; then
    fail_test "Test 12: docs/releases/0.2.0-alpha-artifact.json is missing"
else
    STATUS=$(python3 -c "import json; print(json.load(open('$PROVENANCE'))['verification_status'])" 2>/dev/null || echo "")
    if [[ "$STATUS" == "RETIRED_INVALID_ZERO_FILLED" ]]; then
        pass_test "Test 12: Provenance file records retired invalid Candidate 2 status"
    else
        fail_test "Test 12: Provenance file verification_status='$STATUS' — expected RETIRED_INVALID_ZERO_FILLED"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 13: validate-package-migration.sh must not contain fabricated d9aa0d2e as canonical SHA
# ─────────────────────────────────────────────────────────────────────────────
info "Test 13: validate-package-migration.sh must not contain fabricated d9aa0d2e SHA..."
if grep -q 'd9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228' "$VALIDATE_MIG" 2>/dev/null; then
    fail_test "Test 13: validate-package-migration.sh still contains fabricated d9aa0d2e SHA"
else
    pass_test "Test 13: validate-package-migration.sh does not contain fabricated d9aa0d2e SHA"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 14: install-candidate2.sh rejects retired Cand2 ISO hash
# ─────────────────────────────────────────────────────────────────────────────
info "Test 14: install-candidate2.sh must reject retired 1cb79fbf hash..."
if grep -q 'd9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228' "$INSTALL_CAND2" 2>/dev/null; then
    fail_test "Test 14: install-candidate2.sh still contains fabricated d9aa0d2e SHA"
elif grep -q 'Candidate 2 artifact is retired' "$INSTALL_CAND2" 2>/dev/null && grep -q '1cb79fbf66714ebc6a4f0789571664ab571a87749a75b9700d69acf8906e7669' "$INSTALL_CAND2" 2>/dev/null; then
    pass_test "Test 14: install-candidate2.sh rejects retired 1cb79fbf SHA"
else
    fail_test "Test 14: install-candidate2.sh does not contain expected 1cb79fbf SHA reference"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test 15: UEFI and identical BIOS evidence hash check present in validate-package-migration.sh
# ─────────────────────────────────────────────────────────────────────────────
info "Test 15: validate-package-migration.sh must reject identical UEFI/BIOS serial log hashes..."
if grep -q "UEFI.*BIOS.*identical\|identical.*sha.*uefi\|BIOS_SHA.*UEFI_SHA\|uefi_sha.*bios_sha\|UEFI_SHA.*BIOS_SHA\|serial.*identical\|identical.*serial" "$VALIDATE_MIG" 2>/dev/null; then
    pass_test "Test 15: validate-package-migration.sh contains identical UEFI/BIOS hash rejection"
else
    fail_test "Test 15: validate-package-migration.sh does NOT reject identical UEFI/BIOS serial log hashes"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "=== Interface Test Results ==="
printf '[INFO] PASS: %d  FAIL: %d\n' "$PASS_COUNT" "$FAIL_COUNT"

if (( FAIL_COUNT > 0 )); then
    printf '[FAIL] Failed tests:\n' >&2
    for t in "${FAIL_NAMES[@]}"; do
        printf '  - %s\n' "$t" >&2
    done
    exit 1
fi

printf '[PASS] === All %d interface tests passed ===\n' "$PASS_COUNT"
exit 0
