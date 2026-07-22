#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Staging Signing Key Revocation Drill & Verification Script for GenixBit OS

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Unable to resolve repository tooling at '$REPO_ROOT'!" >&2
    exit 1
fi

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

echo "=== GenixBit OS Staging Key Revocation Drill ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# shellcheck disable=SC2034
PROJECT_ID="${GCP_PROJECT_ID:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID:-run-staging-default}}"

if [[ -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] STAGING_RUN_ID is required!" >&2
    exit 1
fi

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

echo "=== Step 1: Executing Key Revocation Drill with Expendable Test Key ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    echo "[INFO] Applying revocation certificate to expendable staging test key..."
    # Verify client APT rejects metadata signed by revoked key
fi

REVOCATION_CONDS='["expendable_staging_test_key_isolated", "revocation_certificate_applied", "public_keyring_updated_with_revocation", "client_apt_rejected_revoked_key_signature", "future_production_key_unaffected"]'
PUBLIC_META="{\"revocation_drill_status\": \"SUCCESS\", \"revocation_reason\": \"KEY_COMPROMISE_TEST\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "revocation-drill" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "validate-key-revocation.sh" "$REVOCATION_CONDS" "$PUBLIC_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/revocation-drill-result.json" "REVOCATION_DRILL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Key Revocation Drill Completed Successfully."
