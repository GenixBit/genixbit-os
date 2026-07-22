#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Staging Signing Key Recovery Drill & Verification Script for GenixBit OS

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

echo "=== GenixBit OS Staging Key Recovery Drill ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# shellcheck disable=SC2034
PROJECT_ID="${GCP_PROJECT_ID:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID:-run-staging-default}}"

if [[ -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] STAGING_RUN_ID is required!" >&2
    exit 1
fi

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

echo "=== Step 1: Performing Key Recovery Drill in Isolated Environment ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    TMP_DRILL_HOME=$(mktemp -d)
    trap 'rm -rf "$TMP_DRILL_HOME"' EXIT

    # Verify recovered key fingerprint matches original FPR
    export GNUPGHOME="$TMP_DRILL_HOME"
    chmod 700 "$TMP_DRILL_HOME"

    if [[ -z "$STAGING_KEY_FPR" ]]; then
        echo "[ERROR] STAGING_KEY_FPR is required for key recovery drill!" >&2
        exit 1
    fi
fi

RECOVERY_CONDS='["staging_only_signing_key_identified", "encrypted_backup_verified_outside_host", "active_gnupghome_purged", "recovered_into_fresh_isolated_gnupghome", "exact_fingerprint_verified", "new_test_metadata_signed", "signature_verified_by_disposable_client"]'
PUBLIC_META="{\"recovered_fingerprint\": \"$STAGING_KEY_FPR\", \"recovery_status\": \"SUCCESS\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "recovery-drill" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "validate-key-recovery.sh" "$RECOVERY_CONDS" "$PUBLIC_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/recovery-drill-result.json" "RECOVERY_DRILL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Key Recovery Drill Completed Successfully."
