#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Evidence Anti-Fabrication & Integrity Test Suite for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))
INFRA_DIR="$REPO_ROOT/infra/package-staging"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$INFRA_DIR/scripts/lib/evidence.sh"

echo "=== Running Package Staging Evidence Anti-Fabrication Test Suite ==="

TEST_RUN_ID="run-evidence-test-001"
TEST_COMMIT=$(cd "$REPO_ROOT" && git rev-parse HEAD)
RESULTS_DIR="$TMP_DIR/results/$TEST_RUN_ID"

# 1. Test REPO_ROOT Calculation & Tooling Existence
echo "[INFO] Test 1: Verifying REPO_ROOT calculation and tool existence..."
if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] REPO_ROOT resolution failed: verify-release-signature.sh missing!" >&2
    exit 1
fi
echo "[PASS] REPO_ROOT verified: $REPO_ROOT"

# 2. Test Simulation Mode Emits SIMULATED (Not PASS)
echo "[INFO] Test 2: Verifying simulation mode emits SIMULATED status..."
write_stage_result "$RESULTS_DIR" "https" "SIMULATED" "$TEST_RUN_ID" "$TEST_COMMIT" "simulated-test" '["simulated_tls"]'
if ! grep -q '"status": "SIMULATED"' "$RESULTS_DIR/https-result.json"; then
    echo "[ERROR] write_stage_result did not record SIMULATED status!" >&2
    exit 1
fi

MARKER_OUT=$(emit_verified_marker "$RESULTS_DIR/https-result.json" "HTTPS" "$TEST_RUN_ID" "$TEST_COMMIT" 1)
if ! echo "$MARKER_OUT" | grep -q "STAGING_HTTPS=SIMULATED"; then
    echo "[ERROR] emit_verified_marker emitted PASS instead of SIMULATED!" >&2
    exit 1
fi
echo "[PASS] Simulation mode correctly emitted SIMULATED status."

# 3. Test collect-evidence Rejects Simulated Result for Real Staging Run
echo "[INFO] Test 3: Verifying collect-evidence rejects SIMULATED result for real run..."
if STAGING_RUN_ID="$TEST_RUN_ID" INFRA_DIR="$TMP_DIR" bash "$INFRA_DIR/scripts/collect-evidence.sh" "test-proj" 2>/dev/null; then
    echo "[ERROR] collect-evidence permitted SIMULATED result without --allow-simulated!" >&2
    exit 1
fi
echo "[PASS] collect-evidence correctly rejected SIMULATED stage result."

# 4. Test collect-evidence Rejects Missing Result File
echo "[INFO] Test 4: Verifying collect-evidence rejects missing stage result..."
rm -f "$RESULTS_DIR/https-result.json"
if STAGING_RUN_ID="$TEST_RUN_ID" INFRA_DIR="$TMP_DIR" bash "$INFRA_DIR/scripts/collect-evidence.sh" "test-proj" --allow-simulated 2>/dev/null; then
    echo "[ERROR] collect-evidence permitted missing stage result file!" >&2
    exit 1
fi
echo "[PASS] collect-evidence correctly rejected missing stage result."

# 5. Test collect-evidence Rejects Tampered Result File (Hash Mismatch)
echo "[INFO] Test 5: Verifying collect-evidence rejects tampered stage result..."
write_stage_result "$RESULTS_DIR" "https" "PASS" "$TEST_RUN_ID" "$TEST_COMMIT" "test-cmd" '["condition"]'
# Corrupt status in JSON without updating hash
python3 -c "p='$RESULTS_DIR/https-result.json'; open(p,'w').write(open(p).read().replace('\"status\": \"PASS\"', '\"status\": \"FAILED\"'))"
if verify_stage_result "$RESULTS_DIR/https-result.json" "$TEST_RUN_ID" "$TEST_COMMIT" 0 2>/dev/null; then
    echo "[ERROR] verify_stage_result permitted tampered JSON payload!" >&2
    exit 1
fi
echo "[PASS] Tampered stage result correctly rejected by hash verification."

# 6. Test collect-evidence Rejects Mismatched Run ID
echo "[INFO] Test 6: Verifying rejection of mismatched STAGING_RUN_ID..."
write_stage_result "$RESULTS_DIR" "https" "PASS" "wrong-run-id" "$TEST_COMMIT" "test-cmd" '["condition"]'
if verify_stage_result "$RESULTS_DIR/https-result.json" "$TEST_RUN_ID" "$TEST_COMMIT" 0 2>/dev/null; then
    echo "[ERROR] verify_stage_result permitted mismatched run ID!" >&2
    exit 1
fi
echo "[PASS] Mismatched run ID correctly rejected."

# 7. Test Mandatory Fingerprint Requirement in configure-repository.sh
echo "[INFO] Test 7: Verifying configure-repository.sh rejects empty STAGING_KEY_FPR..."
if STAGING_KEY_FPR="" STAGING_RUN_ID="$TEST_RUN_ID" GCP_PROJECT_ID="proj" GCP_ZONE="zone" STAGING_PUBLIC_KEYRING="/tmp/key" LOCAL_STAGING_DIR="/tmp/dir" bash "$INFRA_DIR/scripts/configure-repository.sh" 2>/dev/null; then
    echo "[ERROR] configure-repository.sh permitted empty STAGING_KEY_FPR!" >&2
    exit 1
fi
echo "[PASS] Empty STAGING_KEY_FPR correctly rejected."

# 8. Test Invalid Fingerprint Format (Must be 40 Hex Chars)
echo "[INFO] Test 8: Verifying configure-repository.sh rejects invalid fingerprint format..."
if STAGING_KEY_FPR="SHORT_INVALID_FPR" STAGING_RUN_ID="$TEST_RUN_ID" GCP_PROJECT_ID="proj" GCP_ZONE="zone" STAGING_PUBLIC_KEYRING="/tmp/key" LOCAL_STAGING_DIR="/tmp/dir" bash "$INFRA_DIR/scripts/configure-repository.sh" 2>/dev/null; then
    echo "[ERROR] configure-repository.sh permitted invalid fingerprint format!" >&2
    exit 1
fi
echo "[PASS] Invalid fingerprint format correctly rejected."

echo "[PASS] All package staging evidence integrity tests passed successfully."
