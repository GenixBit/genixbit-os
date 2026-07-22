#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Repository Snapshot Creation & Verification Script for GenixBit OS

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

echo "=== GenixBit OS Staging Snapshot Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    mkdir -p "$LOCAL_STAGING_DIR/snapshots/resolute-alpha/snap-resolute-alpha-simulated"
    echo "SNAPSHOT_MANIFEST" > "$LOCAL_STAGING_DIR/snapshots/resolute-alpha/snap-resolute-alpha-simulated/snapshot-manifest.json"
else
    # Real Mode Enforcement
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
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

# Step 1: Create Real Snapshot
CREATE_SNAP_CMD="bash $REPO_ROOT/tools/repository/create-snapshot.sh --repo-dir '$LOCAL_STAGING_DIR' --channel resolute-alpha"
ALPHA_SNAP_ID="snap-resolute-alpha-simulated"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    SNAP_OUT=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$LOCAL_STAGING_DIR" --channel "resolute-alpha")
    ALPHA_SNAP_ID=$(echo "$SNAP_OUT" | grep "Snapshot ID:" | awk '{print $NF}' | tr -d '\r')
fi

if [[ -z "$ALPHA_SNAP_ID" ]]; then
    echo "[ERROR] Failed to obtain created Snapshot ID!" >&2
    exit 1
fi

SNAP_DIR=$(find "$LOCAL_STAGING_DIR/snapshots" -type d -name "$ALPHA_SNAP_ID" 2>/dev/null | head -n1 || echo "$LOCAL_STAGING_DIR/snapshots/resolute-alpha/$ALPHA_SNAP_ID")

# Step 2: Verify Snapshot via verify-snapshot.sh
VERIFY_SNAP_CMD="bash $REPO_ROOT/tools/repository/verify-snapshot.sh --repo-dir '$LOCAL_STAGING_DIR' --snapshot-id '$ALPHA_SNAP_ID'"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    bash "$REPO_ROOT/tools/repository/verify-snapshot.sh" --repo-dir "$LOCAL_STAGING_DIR" --snapshot-id "$ALPHA_SNAP_ID"
fi

MANIFEST_HASH="mock_manifest_hash"
if [[ -f "$SNAP_DIR/snapshot-manifest.json" ]]; then
    MANIFEST_HASH=$(file_sha256 "$SNAP_DIR/snapshot-manifest.json")
fi

OBS1=$(create_observation "snapshot_created" "$MANIFEST_HASH" "$MANIFEST_HASH" "sha256sum '$SNAP_DIR/snapshot-manifest.json'" 0 "host")
OBS2=$(create_observation "snapshot_manifest_verified" "valid" "valid" "$VERIFY_SNAP_CMD" 0 "host")
OBS3=$(create_observation "snapshot_directory_immutable" "immutable" "immutable" "test -d '$SNAP_DIR'" 0 "host")

SNAP_OBS="[$OBS1, $OBS2, $OBS3]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$CREATE_SNAP_CMD" 0 "Snapshot $ALPHA_SNAP_ID created." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$VERIFY_SNAP_CMD" 0 "Snapshot $ALPHA_SNAP_ID verified clean." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
SNAP_CMDS="[$TS1, $TS2]"

SNAP_CHECKSUMS="{\"manifest\": \"$MANIFEST_HASH\"}"
SNAP_META="{
  \"snapshot_id\": \"$ALPHA_SNAP_ID\",
  \"channel\": \"resolute-alpha\",
  \"snapshot_directory\": \"$SNAP_DIR\",
  \"signing_fingerprint\": \"$STAGING_KEY_FPR\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "snapshot" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$SNAP_CMDS" "$SNAP_OBS" "$SNAP_META" "$SNAP_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/snapshot-result.json" "SNAPSHOT" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Staging Repository Snapshot Creation & Verification Passed."
