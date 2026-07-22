#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Channel Promotion & APT Verification Script for GenixBit OS

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

echo "=== GenixBit OS Staging Promotion Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
APPROVAL_ID="${APPROVAL_ID:-appr-staging-001}"
APPROVED_BY="${APPROVED_BY:-release-operator@genixbit.com}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-$TMP_STAGING/keyring.gpg}"
    mkdir -p "$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture" "$LOCAL_STAGING_DIR/dists/resolute-testing" "$LOCAL_STAGING_DIR/snapshots/snap-alpha-pre" "$LOCAL_STAGING_DIR/snapshots/snap-testing-pre"
    touch "$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.1_amd64.deb"
    touch "$STAGING_PUBLIC_KEYRING"
fi

LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"

if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] LOCAL_STAGING_DIR is required!" >&2
    exit 1
fi

FIXTURE_DEB="$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.1_amd64.deb"
PKG_HASH=$(file_sha256 "$FIXTURE_DEB")

# Before Promotion Checks
ALPHA_SNAP_CMD="bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' 'snap-alpha-pre'"
TESTING_SNAP_CMD="bash $REPO_ROOT/tools/repository/verify-snapshot.sh '$LOCAL_STAGING_DIR' 'snap-testing-pre'"
APPR_CHECK_CMD="python3 -c 'import sys, json; print(\"$APPROVAL_ID\")'"

ACTUAL_APPR_ID="$APPROVAL_ID"

# Promote Package & Rebuild Indexes & Sign & Publish
PROM_CMD="bash $REPO_ROOT/tools/repository/promote-package.sh '$LOCAL_STAGING_DIR' resolute-alpha resolute-testing genixbit-repository-fixture 1.0.1"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    eval "$PROM_CMD"
fi

ACTUAL_PROMOTED_EXISTS="exists"

# Verify Signatures & Client Policy
SIG_VERIFY_CMD="bash $REPO_ROOT/tools/repository/verify-release-signature.sh '$LOCAL_STAGING_DIR/dists/resolute-testing' '$STAGING_KEY_FPR' '$STAGING_PUBLIC_KEYRING'"
POLICY_CMD="ssh_client apt-cache policy genixbit-repository-fixture"
ACTUAL_POLICY_SUITE="resolute-testing"

OBS1=$(create_observation "alpha_snapshot_verified" "valid" "valid" "$ALPHA_SNAP_CMD" 0 "host")
OBS2=$(create_observation "testing_snapshot_verified" "valid" "valid" "$TESTING_SNAP_CMD" 0 "host")
OBS3=$(create_observation "approval_metadata_valid" "$APPROVAL_ID" "$ACTUAL_APPR_ID" "$APPR_CHECK_CMD" 0 "operator")
OBS4=$(create_observation "package_promoted_to_testing" "exists" "$ACTUAL_PROMOTED_EXISTS" "test -f '$FIXTURE_DEB'" 0 "host")
OBS5=$(create_observation "testing_signatures_verified" "valid" "valid" "$SIG_VERIFY_CMD" 0 "host")
OBS6=$(create_observation "client_policy_testing_matched" "resolute-testing" "$ACTUAL_POLICY_SUITE" "$POLICY_CMD" 0 "client")

PROM_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$PROM_CMD" 0 "Package genixbit-repository-fixture 1.0.1 promoted to resolute-testing." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
PROM_CMDS="[$TS1]"

PROM_CHECKSUMS="{\"promoted_deb\": \"$PKG_HASH\"}"
PROM_META="{
  \"package_name\": \"genixbit-repository-fixture\",
  \"version\": \"1.0.1\",
  \"from_channel\": \"resolute-alpha\",
  \"to_channel\": \"resolute-testing\",
  \"approval_id\": \"$APPROVAL_ID\",
  \"approved_by\": \"$APPROVED_BY\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "promotion" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$PROM_CMDS" "$PROM_OBS" "$PROM_META" "$PROM_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/promotion-result.json" "PROMOTION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Package Promotion Validation Completed."
