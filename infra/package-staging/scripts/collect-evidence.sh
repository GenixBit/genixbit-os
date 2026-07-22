#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Evidence Manifest Aggregator for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR="${INFRA_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Unable to resolve repository root at '$REPO_ROOT'!" >&2
    exit 1
fi

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

echo "=== GenixBit OS Staging Evidence Collection ==="

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
REGION="${GCP_REGION:-asia-south1}"
ZONE="${GCP_ZONE:-asia-south1-a}"
ALLOW_SIMULATED="${ALLOW_SIMULATED:-0}"

for arg in "$@"; do
    case "$arg" in
        --allow-simulated)
            ALLOW_SIMULATED=1
            ;;
    esac
done

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == --* || -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] Usage: $0 <PROJECT_ID> (with STAGING_RUN_ID set in environment)" >&2
    exit 1
fi

SOURCE_COMMIT=$(cd "$REPO_ROOT" && git rev-parse HEAD)
RESULTS_DIR="$INFRA_DIR/results/${STAGING_RUN_ID}"
EVIDENCE_MANIFEST="$INFRA_DIR/evidence-${STAGING_RUN_ID}.json"
EVIDENCE_HASH_FILE="$INFRA_DIR/evidence-${STAGING_RUN_ID}.sha256"

REQUIRED_STAGES=(
    "repository-publication"
    "https"
    "apt-update"
    "install"
    "upgrade"
    "promotion"
    "snapshot"
    "rollback"
    "tamper-rejection"
    "recovery-drill"
    "revocation-drill"
)

echo "=== Step 1: Consuming & Verifying Stage Result Files ==="
STAGE_JSON_MAP="{}"
OVERALL_PASS=1
SIMULATED_COUNT=0

for stage in "${REQUIRED_STAGES[@]}"; do
    res_file="$RESULTS_DIR/${stage}-result.json"

    if ! verify_stage_result "$res_file" "$STAGING_RUN_ID" "$SOURCE_COMMIT" "$ALLOW_SIMULATED"; then
        echo "[ERROR] Verification failed for required stage '$stage' ($res_file)!" >&2
        OVERALL_PASS=0
        break
    fi

    status=$(jq -r '.status' "$res_file")
    res_hash=$(jq -r '.result_sha256' "$res_file")
    verified_ts=$(jq -r '.completed_at' "$res_file")

    if [[ "$status" == "SIMULATED" ]]; then
        SIMULATED_COUNT=$((SIMULATED_COUNT + 1))
    fi

    # Map hyphens to underscores for JSON stage key
    stage_key=$(echo "$stage" | tr '-' '_')

    STAGE_SUMMARY=$(cat << EOF
{
  "status": "$status",
  "result_sha256": "$res_hash",
  "verified_at": "$verified_ts"
}
EOF
)
    STAGE_JSON_MAP=$(jq --arg key "$stage_key" --argjson val "$STAGE_SUMMARY" '. + {($key): $val}' <<< "$STAGE_JSON_MAP")
done

if [[ "$OVERALL_PASS" -ne 1 ]]; then
    echo "[ERROR] Evidence collection failed: One or more required stage results are missing or invalid!" >&2
    exit 1
fi

OVERALL_STATUS="PASS"
if [[ "$SIMULATED_COUNT" -gt 0 ]]; then
    if [[ "$ALLOW_SIMULATED" -eq 1 ]]; then
        OVERALL_STATUS="OPERATIONS_IMPLEMENTED_NOT_DEPLOYED"
    else
        echo "[ERROR] Rejected simulated stage results for real staging evidence manifest!" >&2
        exit 1
    fi
fi

EVIDENCE_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat << EOF > "$EVIDENCE_MANIFEST"
{
  "schema_version": "1.0.0",
  "staging_run_id": "$STAGING_RUN_ID",
  "source_commit": "$SOURCE_COMMIT",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "endpoint_class": "STAGING_PRIVATE_HTTPS",
  "evidence_timestamp": "$EVIDENCE_TS",
  "overall_status": "$OVERALL_STATUS",
  "stages": $STAGE_JSON_MAP
}
EOF

SCHEMA_FILE="$REPO_ROOT/infra/package-staging/schemas/staging-evidence.schema.json"
if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
    python3 -c "import json, jsonschema; jsonschema.validate(json.load(open('$EVIDENCE_MANIFEST')), json.load(open('$SCHEMA_FILE')))"
    echo "[PASS] Evidence manifest validated against staging-evidence.schema.json."
fi

# Calculate and record evidence SHA-256
MANIFEST_HASH=$(file_sha256 "$EVIDENCE_MANIFEST")
echo "$MANIFEST_HASH  evidence-${STAGING_RUN_ID}.json" > "$EVIDENCE_HASH_FILE"

echo "[PASS] Evidence Manifest Created: $EVIDENCE_MANIFEST (SHA: $MANIFEST_HASH)"

# Upload to Evidence Storage Bucket if bucket exists
BUCKET_NAME="genixbit-staging-evidence-${PROJECT_ID}"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    echo "=== Step 2: Uploading & Verifying Evidence Cloud Storage Object ==="
    if ! gcloud storage buckets describe "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        echo "[ERROR] Evidence bucket gs://$BUCKET_NAME unreachable!" >&2
        exit 1
    fi

    gcloud storage cp "$EVIDENCE_MANIFEST" "gs://$BUCKET_NAME/evidence-${STAGING_RUN_ID}.json"
    gcloud storage cp "$EVIDENCE_HASH_FILE" "gs://$BUCKET_NAME/evidence-${STAGING_RUN_ID}.sha256"

    # Download back and verify checksum matching
    TMP_VERIFY=$(mktemp)
    gcloud storage cp "gs://$BUCKET_NAME/evidence-${STAGING_RUN_ID}.json" "$TMP_VERIFY"
    DOWNLOAD_HASH=$(file_sha256 "$TMP_VERIFY")
    rm -f "$TMP_VERIFY"

    if [[ "$DOWNLOAD_HASH" != "$MANIFEST_HASH" ]]; then
        echo "[ERROR] Uploaded evidence manifest SHA256 mismatch! Cloud object corrupted." >&2
        exit 1
    fi
    echo "[PASS] Uploaded Evidence Object Verified on gs://$BUCKET_NAME/ (SHA: $DOWNLOAD_HASH)"
fi

echo "OVERALL_STATUS=$OVERALL_STATUS"
