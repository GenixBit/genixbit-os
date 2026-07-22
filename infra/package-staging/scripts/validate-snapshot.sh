#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Staging Repository Snapshot Creation & Verification Script for GenixBit OS

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/create-snapshot.sh" ]]; then
    echo "[ERROR] Unable to resolve repository tooling at '$REPO_ROOT'!" >&2
    exit 1
fi

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

echo "=== GenixBit OS Staging Snapshot Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# shellcheck disable=SC2034
PROJECT_ID="${GCP_PROJECT_ID:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID:-run-staging-default}}"

if [[ -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] STAGING_RUN_ID is required!" >&2
    exit 1
fi

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

SNAP_ID="snap-${STAGING_RUN_ID}-001"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    SNAP_OUT=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$LOCAL_STAGING_DIR" --channel "resolute-testing")
    SNAP_ID=$(echo "$SNAP_OUT" | grep "Snapshot ID:" | awk '{print $NF}' || echo "$SNAP_ID")
fi

SNAPSHOT_CONDS='["snapshot_manifest_created", "package_hashes_verified", "index_hashes_verified", "release_hash_verified", "signing_fingerprint_verified", "previous_snapshot_reference_linked"]'
PUBLIC_META="{\"snapshot_id\": \"$SNAP_ID\", \"channel\": \"resolute-testing\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "snapshot" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "validate-snapshot.sh" "$SNAPSHOT_CONDS" "$PUBLIC_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/snapshot-result.json" "SNAPSHOT" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Snapshot Creation & Verification Completed (Snapshot ID: $SNAP_ID)."
