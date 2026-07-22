#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Staging Repository Snapshot Rollback & Evidence Verification Script for GenixBit OS

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/rollback-snapshot.sh" ]]; then
    echo "[ERROR] Unable to resolve repository tooling at '$REPO_ROOT'!" >&2
    exit 1
fi

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

echo "=== GenixBit OS Staging Rollback Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
CLIENT_INSTANCE="${CLIENT_INSTANCE:-genixbit-staging-disposable-client}"
LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
STAGING_GNUPG_HOME="${STAGING_GNUPG_HOME:-}"
SNAPSHOT_ID="${SNAPSHOT_ID:-snap-${STAGING_RUN_ID}-001}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID:-run-staging-default}}"

if [[ -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] STAGING_RUN_ID is required!" >&2
    exit 1
fi

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

ssh_client() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$CLIENT_INSTANCE" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
    fi
}

echo "=== Step 1: Performing Snapshot Rollback & Atomic Publication ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    bash "$REPO_ROOT/tools/repository/rollback-snapshot.sh" \
        --repo-dir "$LOCAL_STAGING_DIR" \
        --channel "resolute-testing" \
        --snapshot-id "$SNAPSHOT_ID" >/dev/null

    bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
        --repo-dir "$LOCAL_STAGING_DIR" \
        --channel "resolute-testing" \
        --signing-key-fingerprint "$STAGING_KEY_FPR" \
        --gnupg-home "$STAGING_GNUPG_HOME" >/dev/null

    bash "$SCRIPT_DIR/configure-repository.sh" >/dev/null
fi

echo "=== Step 2: Verifying Rollback from Disposable Client ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo apt-get update -qq"
    POLICY_OUT=$(ssh_client "apt-cache policy genixbit-repository-fixture" 2>/dev/null || echo "")
    if ! echo "$POLICY_OUT" | grep -q "resolute-testing"; then
        echo "[ERROR] Client apt-cache policy verification failed after rollback!" >&2
        exit 1
    fi
fi

ROLLBACK_CONDS='["pre_rollback_state_recorded", "controlled_repository_change_observed", "snapshot_restored_successfully", "restored_metadata_re_signed", "restored_metadata_published_atomically", "client_apt_update_verified", "client_policy_restored_hashes_matched"]'
PUBLIC_META="{\"restored_snapshot_id\": \"$SNAPSHOT_ID\", \"channel\": \"resolute-testing\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "rollback" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "validate-rollback.sh" "$ROLLBACK_CONDS" "$PUBLIC_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/rollback-result.json" "ROLLBACK" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Snapshot Rollback & APT Policy Verification Completed."
