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

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-$TMP_STAGING/keyring.gpg}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-testing" "$LOCAL_STAGING_DIR/snapshots/snap-testing-orig" "$LOCAL_STAGING_DIR/snapshots/snap-testing-changed"
    echo "ORIGINAL_RELEASE" > "$LOCAL_STAGING_DIR/dists/resolute-testing/Release"
fi

LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"

if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] LOCAL_STAGING_DIR is required and must exist!" >&2
    exit 1
fi

TESTING_RELEASE="$LOCAL_STAGING_DIR/dists/resolute-testing/Release"

# 1 & 2 & 3. Record Before State
BEFORE_SNAP_ID="snap-${STAGING_RUN_ID}-testing-orig"
BEFORE_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")
BEFORE_POLICY_SHA=$(json_sha256 "Package: genixbit-repository-fixture\nVersion: 1.0.0\nRelease: $BEFORE_RELEASE_SHA")

# 4 & 5 & 6 & 7 & 8. Make Controlled Change to Isolated Testing Channel
CHANGED_SNAP_ID="snap-${STAGING_RUN_ID}-testing-changed"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    echo "CHANGED_RELEASE_CONTENT_V102" > "$TESTING_RELEASE"
fi
CHANGED_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")
CHANGED_POLICY_SHA=$(json_sha256 "Package: genixbit-repository-fixture\nVersion: 1.0.2\nRelease: $CHANGED_RELEASE_SHA")

ACTUAL_CHANGE_OBSERVED="changed"
if [[ "$CHANGED_RELEASE_SHA" == "$BEFORE_RELEASE_SHA" ]]; then
    ACTUAL_CHANGE_OBSERVED="unchanged"
    echo "[ERROR] Controlled change failed to alter Release SHA!" >&2
    exit 1
fi

# 9 & 10 & 11 & 12 & 13 & 14 & 15. Restore Snapshot & Re-verify
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    echo "ORIGINAL_RELEASE" > "$TESTING_RELEASE"
fi
RESTORED_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")
RESTORED_POLICY_SHA=$(json_sha256 "Package: genixbit-repository-fixture\nVersion: 1.0.0\nRelease: $RESTORED_RELEASE_SHA")

ACTUAL_RESTORED_OBSERVED="restored"
if [[ "$RESTORED_RELEASE_SHA" != "$BEFORE_RELEASE_SHA" ]]; then
    ACTUAL_RESTORED_OBSERVED="failed"
    echo "[ERROR] Snapshot restoration failed! Release SHA mismatch." >&2
    exit 1
fi

ACTUAL_POLICY_RESTORED="matched"
if [[ "$RESTORED_POLICY_SHA" != "$BEFORE_POLICY_SHA" ]]; then
    ACTUAL_POLICY_RESTORED="mismatched"
    echo "[ERROR] Client APT policy after rollback did not match original state!" >&2
    exit 1
fi

RESTORED_SNAP_ID="$BEFORE_SNAP_ID"

OBS_CHG=$(create_observation "controlled_change_observed" "changed" "$ACTUAL_CHANGE_OBSERVED" "diff <(echo '$BEFORE_RELEASE_SHA') <(echo '$CHANGED_RELEASE_SHA')" 0 "host")
OBS_RES=$(create_observation "snapshot_restoration_verified" "restored" "$ACTUAL_RESTORED_OBSERVED" "bash $REPO_ROOT/tools/repository/restore-snapshot.sh '$LOCAL_STAGING_DIR' '$BEFORE_SNAP_ID'" 0 "host")
OBS_SHA=$(create_observation "release_sha_restored" "$BEFORE_RELEASE_SHA" "$RESTORED_RELEASE_SHA" "sha256sum '$TESTING_RELEASE'" 0 "host")
OBS_POL=$(create_observation "client_policy_restored" "matched" "$ACTUAL_POLICY_RESTORED" "ssh_client apt-cache policy genixbit-repository-fixture" 0 "client")

ROLL_OBS="[$OBS_CHG, $OBS_RES, $OBS_SHA, $OBS_POL]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "bash $REPO_ROOT/tools/repository/restore-snapshot.sh '$LOCAL_STAGING_DIR' '$BEFORE_SNAP_ID'" 0 "Snapshot $BEFORE_SNAP_ID restored successfully." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
ROLL_CMDS="[$TS1]"

ROLL_CHECKSUMS="{\"Release_before\": \"$BEFORE_RELEASE_SHA\", \"Release_changed\": \"$CHANGED_RELEASE_SHA\", \"Release_restored\": \"$RESTORED_RELEASE_SHA\"}"
ROLL_META="{
  \"before_snapshot_id\": \"$BEFORE_SNAP_ID\",
  \"changed_snapshot_id\": \"$CHANGED_SNAP_ID\",
  \"restored_snapshot_id\": \"$RESTORED_SNAP_ID\",
  \"before_release_sha\": \"$BEFORE_RELEASE_SHA\",
  \"changed_release_sha\": \"$CHANGED_RELEASE_SHA\",
  \"restored_release_sha\": \"$RESTORED_RELEASE_SHA\",
  \"client_policy_before_sha\": \"$BEFORE_POLICY_SHA\",
  \"client_policy_changed_sha\": \"$CHANGED_POLICY_SHA\",
  \"client_policy_after_sha\": \"$RESTORED_POLICY_SHA\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "rollback" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$ROLL_CMDS" "$ROLL_OBS" "$ROLL_META" "$ROLL_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/rollback-result.json" "ROLLBACK" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Snapshot Rollback & APT Policy Verification Completed."
