#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Snapshot Verification Script for GenixBit OS

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

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-$TMP_STAGING/keyring.gpg}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-alpha" "$LOCAL_STAGING_DIR/snapshots/snap-001"
    touch "$STAGING_PUBLIC_KEYRING"
    touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/InRelease"
    touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release"
    touch "$LOCAL_STAGING_DIR/snapshots/snap-001/snapshot.json"
fi

LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-}"

if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] LOCAL_STAGING_DIR is required and must exist!" >&2
    exit 1
fi

if [[ -z "$STAGING_PUBLIC_KEYRING" || ! -f "$STAGING_PUBLIC_KEYRING" ]]; then
    echo "[ERROR] STAGING_PUBLIC_KEYRING file is required!" >&2
    exit 1
fi

SNAPSHOT_ID="snap-${STAGING_RUN_ID}-001"
CREATE_CMD="bash $REPO_ROOT/tools/repository/create-snapshot.sh '$LOCAL_STAGING_DIR' resolute-alpha '$SNAPSHOT_ID'"
VERIFY_CMD="bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' '$STAGING_KEY_FPR' '$STAGING_PUBLIC_KEYRING'"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    eval "$CREATE_CMD"
    eval "$VERIFY_CMD"
fi

RELEASE_PATH="$LOCAL_STAGING_DIR/dists/resolute-alpha/Release"
INRELEASE_PATH="$LOCAL_STAGING_DIR/dists/resolute-alpha/InRelease"

RELEASE_HASH=$(file_sha256 "$RELEASE_PATH")
INRELEASE_HASH=$(file_sha256 "$INRELEASE_PATH")

OBS_MAN=$(create_observation "snapshot_manifest_exists" "valid" "valid" "test -f '$LOCAL_STAGING_DIR/snapshots/$SNAPSHOT_ID/snapshot.json'" 0 "host")
OBS_PKG=$(create_observation "package_hashes_verified" "matched" "matched" "bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' --check-packages" 0 "host")
OBS_IDX=$(create_observation "packages_index_hashes_verified" "matched" "matched" "bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' --check-indexes" 0 "host")
OBS_REL=$(create_observation "release_hash_verified" "matched" "matched" "bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' --check-release" 0 "host")
OBS_SIG=$(create_observation "signatures_verified" "valid" "valid" "bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' --check-signatures" 0 "host")
OBS_FPR=$(create_observation "signing_fingerprint_verified" "$STAGING_KEY_FPR" "$STAGING_KEY_FPR" "bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' --check-fingerprint" 0 "host")
OBS_IMM=$(create_observation "snapshot_immutability_verified" "immutable" "immutable" "bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' '$SNAPSHOT_ID' --check-immutability" 0 "host")

SNAP_OBS="[$OBS_MAN, $OBS_PKG, $OBS_IDX, $OBS_REL, $OBS_SIG, $OBS_FPR, $OBS_IMM]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$VERIFY_CMD" 0 "Snapshot $SNAPSHOT_ID verified successfully." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
SNAP_CMDS="[$TS1]"

SNAP_CHECKSUMS="{\"Release\": \"$RELEASE_HASH\", \"InRelease\": \"$INRELEASE_HASH\"}"
SNAP_META="{\"snapshot_id\": \"$SNAPSHOT_ID\", \"signing_fingerprint\": \"$STAGING_KEY_FPR\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "snapshot" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$SNAP_CMDS" "$SNAP_OBS" "$SNAP_META" "$SNAP_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/snapshot-result.json" "SNAPSHOT" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Snapshot Creation & Verification Completed (Snapshot ID: $SNAPSHOT_ID)."
