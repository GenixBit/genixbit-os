#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# End-to-end Operations & Evidence Test Suite for GenixBit OS Package Staging Infrastructure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))
INFRA_DIR="$REPO_ROOT/infra/package-staging"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== Running Staging Operations Test Suite ==="

export GENIXBIT_SIMULATE_OPS=1
export GCP_PROJECT_ID="genixbit-staging-test"
export GCP_REGION="asia-south1"
export GCP_ZONE="asia-south1-a"
export STAGING_RUN_ID="run-ops-test-999"
export STAGING_KEY_FPR="1234567890ABCDEF1234567890ABCDEF12345678"
export STAGING_PUBLIC_KEYRING="$TMP_DIR/dummy.gpg"
export LOCAL_STAGING_DIR="$TMP_DIR/staging_repo"
export EVIDENCE_OUT_DIR="$TMP_DIR/results/$STAGING_RUN_ID"

mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-alpha" "$EVIDENCE_OUT_DIR"
touch "$STAGING_PUBLIC_KEYRING"
touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/InRelease"
touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release"
touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release.gpg"

# 1. Run Preflight in simulation mode
echo "[INFO] Testing preflight.sh..."
PREFLIGHT_OUT=$(bash "$INFRA_DIR/scripts/preflight.sh" 2>&1)
echo "$PREFLIGHT_OUT" | grep -q "PREFLIGHT_CHECKS=SIMULATED"
echo "[PASS] preflight.sh verified."

# 2. Run Plan in simulation mode
echo "[INFO] Testing plan.sh..."
PLAN_OUT=$(bash "$INFRA_DIR/scripts/plan.sh" "$GCP_PROJECT_ID" 2>&1)
echo "$PLAN_OUT" | grep -q "STAGING_PLAN=SIMULATED"
echo "[PASS] plan.sh verified."

# 3. Run Configure Repository in simulation mode
echo "[INFO] Testing configure-repository.sh..."
CONF_OUT=$(bash "$INFRA_DIR/scripts/configure-repository.sh" 2>&1)
echo "$CONF_OUT" | grep -q "STAGING_REPOSITORY_PUBLICATION=SIMULATED"
echo "[PASS] configure-repository.sh verified."

# 4. Run Validate Client in simulation mode
echo "[INFO] Testing validate-client.sh..."
CLIENT_OUT=$(bash "$INFRA_DIR/scripts/validate-client.sh" 2>&1)
echo "$CLIENT_OUT" | grep -q "STAGING_HTTPS=SIMULATED"
echo "$CLIENT_OUT" | grep -q "STAGING_APT_UPDATE=SIMULATED"
echo "$CLIENT_OUT" | grep -q "STAGING_INSTALL=SIMULATED"
echo "$CLIENT_OUT" | grep -q "STAGING_UPGRADE=SIMULATED"
echo "[PASS] validate-client.sh verified."

# 5. Run Validate Promotion in simulation mode
echo "[INFO] Testing validate-promotion.sh..."
PROM_OUT=$(bash "$INFRA_DIR/scripts/validate-promotion.sh" 2>&1)
echo "$PROM_OUT" | grep -q "STAGING_PROMOTION=SIMULATED"
echo "[PASS] validate-promotion.sh verified."

# 6. Run Validate Snapshot in simulation mode
echo "[INFO] Testing validate-snapshot.sh..."
SNAP_OUT=$(bash "$INFRA_DIR/scripts/validate-snapshot.sh" 2>&1)
echo "$SNAP_OUT" | grep -q "STAGING_SNAPSHOT=SIMULATED"
echo "[PASS] validate-snapshot.sh verified."

# 7. Run Validate Rollback in simulation mode
echo "[INFO] Testing validate-rollback.sh..."
ROLL_OUT=$(bash "$INFRA_DIR/scripts/validate-rollback.sh" 2>&1)
echo "$ROLL_OUT" | grep -q "STAGING_ROLLBACK=SIMULATED"
echo "[PASS] validate-rollback.sh verified."

# 8. Run Validate Tamper Rejection in simulation mode
echo "[INFO] Testing validate-tamper-rejection.sh..."
TAMP_OUT=$(bash "$INFRA_DIR/scripts/validate-tamper-rejection.sh" 2>&1)
echo "$TAMP_OUT" | grep -q "STAGING_TAMPER_REJECTION=SIMULATED"
echo "[PASS] validate-tamper-rejection.sh verified."

# 9. Run Validate Key Recovery in simulation mode
echo "[INFO] Testing validate-key-recovery.sh..."
REC_OUT=$(bash "$INFRA_DIR/scripts/validate-key-recovery.sh" 2>&1)
echo "$REC_OUT" | grep -q "STAGING_RECOVERY_DRILL=SIMULATED"
echo "[PASS] validate-key-recovery.sh verified."

# 10. Run Validate Key Revocation in simulation mode
echo "[INFO] Testing validate-key-revocation.sh..."
REV_OUT=$(bash "$INFRA_DIR/scripts/validate-key-revocation.sh" 2>&1)
echo "$REV_OUT" | grep -q "STAGING_REVOCATION_DRILL=SIMULATED"
echo "[PASS] validate-key-revocation.sh verified."

# 11. Test Collect Evidence in simulation mode with --allow-simulated
echo "[INFO] Testing collect-evidence.sh with --allow-simulated..."
EVID_OUT=$(INFRA_DIR="$TMP_DIR" bash "$INFRA_DIR/scripts/collect-evidence.sh" "$GCP_PROJECT_ID" --allow-simulated 2>&1)
echo "$EVID_OUT" | grep -q "OVERALL_STATUS=OPERATIONS_IMPLEMENTED_NOT_DEPLOYED"
echo "[PASS] collect-evidence.sh verified."

echo "[PASS] All staging operational workflow scripts executed successfully."
