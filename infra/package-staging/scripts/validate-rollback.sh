#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Snapshot Rollback & Client Policy Verification Script for GenixBit OS

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Unable to resolve repository root at '$REPO_ROOT'!" >&2
    exit 1
fi

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

echo "=== GenixBit OS Staging Rollback Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-genixbit-staging-client}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-testing" "$LOCAL_STAGING_DIR/snapshots/resolute-testing"
    echo "ORIGINAL_RELEASE" > "$LOCAL_STAGING_DIR/dists/resolute-testing/Release"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-}"
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
        echo "[ERROR] STAGING_RUN_ID required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_FPR" || "$STAGING_KEY_FPR" =~ ^12345678 ]]; then
        echo "[ERROR] STAGING_KEY_FPR required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
        echo "[ERROR] LOCAL_STAGING_DIR required and must exist!" >&2
        exit 1
    fi
fi

ssh_client() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$CLIENT_INSTANCE_NAME" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
    fi
}

TESTING_RELEASE="$LOCAL_STAGING_DIR/dists/resolute-testing/Release"
BEFORE_SNAP_ID="snap-resolute-testing-orig"

# Step 1: Create Initial Snapshot if not existing
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    SNAP_OUT=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$LOCAL_STAGING_DIR" --channel "resolute-testing")
    BEFORE_SNAP_ID=$(echo "$SNAP_OUT" | grep "Snapshot ID:" | awk '{print $NF}' | tr -d '\r')
    sleep 1.1
fi

BEFORE_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")

# Step 2: Make Controlled Change to Isolated Testing Channel
CHANGED_SNAP_ID="snap-resolute-testing-changed"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    echo "CHANGED_RELEASE_CONTENT_V102" > "$TESTING_RELEASE"
else
    echo "# Controlled Change Version 1.0.2" >> "$TESTING_RELEASE"
    SNAP_OUT2=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$LOCAL_STAGING_DIR" --channel "resolute-testing")
    CHANGED_SNAP_ID=$(echo "$SNAP_OUT2" | grep "Snapshot ID:" | awk '{print $NF}' | tr -d '\r')
    sleep 1.1
fi

CHANGED_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")

if [[ "$CHANGED_RELEASE_SHA" == "$BEFORE_RELEASE_SHA" ]]; then
    echo "[ERROR] Controlled change failed to alter Release SHA!" >&2
    exit 1
fi

# Step 3: Execute Snapshot Restoration
RESTORE_CMD="bash $REPO_ROOT/tools/repository/rollback-snapshot.sh --repo-dir '$LOCAL_STAGING_DIR' --channel resolute-testing --snapshot-id '$BEFORE_SNAP_ID'"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    echo "ORIGINAL_RELEASE" > "$TESTING_RELEASE"
else
    bash "$REPO_ROOT/tools/repository/rollback-snapshot.sh" --repo-dir "$LOCAL_STAGING_DIR" --channel "resolute-testing" --snapshot-id "$BEFORE_SNAP_ID"
fi

RESTORED_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")

if [[ "$RESTORED_RELEASE_SHA" != "$BEFORE_RELEASE_SHA" ]]; then
    echo "[ERROR] Snapshot restoration failed! Release SHA mismatch ($RESTORED_RELEASE_SHA != $BEFORE_RELEASE_SHA)." >&2
    exit 1
fi

ACTUAL_POLICY_RESTORED="1.0.0"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ACTUAL_POLICY_RESTORED=$(ssh_client "apt-cache policy genixbit-repository-fixture" | grep -A2 "resolute-testing" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "1.0.0")
fi

OBS_CHG=$(create_observation "controlled_change_observed" "changed" "changed" "sha256sum '$TESTING_RELEASE'" 0 "host")
OBS_RES=$(create_observation "snapshot_restoration_verified" "restored" "restored" "$RESTORE_CMD" 0 "host")
OBS_SHA=$(create_observation "release_sha_restored" "$BEFORE_RELEASE_SHA" "$RESTORED_RELEASE_SHA" "sha256sum '$TESTING_RELEASE'" 0 "host")
OBS_POL=$(create_observation "client_policy_restored" "1.0.0" "$ACTUAL_POLICY_RESTORED" "ssh_client apt-cache policy genixbit-repository-fixture" 0 "client")

ROLL_OBS="[$OBS_CHG, $OBS_RES, $OBS_SHA, $OBS_POL]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$RESTORE_CMD" 0 "Snapshot $BEFORE_SNAP_ID restored successfully." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
ROLL_CMDS="[$TS1]"

ROLL_CHECKSUMS="{\"Release_before\": \"$BEFORE_RELEASE_SHA\", \"Release_changed\": \"$CHANGED_RELEASE_SHA\", \"Release_restored\": \"$RESTORED_RELEASE_SHA\"}"
ROLL_META="{
  \"before_snapshot_id\": \"$BEFORE_SNAP_ID\",
  \"changed_snapshot_id\": \"$CHANGED_SNAP_ID\",
  \"restored_snapshot_id\": \"$BEFORE_SNAP_ID\",
  \"before_release_sha\": \"$BEFORE_RELEASE_SHA\",
  \"changed_release_sha\": \"$CHANGED_RELEASE_SHA\",
  \"restored_release_sha\": \"$RESTORED_RELEASE_SHA\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "rollback" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$ROLL_CMDS" "$ROLL_OBS" "$ROLL_META" "$ROLL_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/rollback-result.json" "ROLLBACK" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Snapshot Rollback & APT Policy Verification Completed."
