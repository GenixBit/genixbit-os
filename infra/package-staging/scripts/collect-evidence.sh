#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Evidence Aggregator & Provenance Verifier for GenixBit OS Package Staging

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

PROJECT_ID="${GCP_PROJECT_ID:-${1:-genixbit-staging-test}}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
REGION="${GCP_REGION:-asia-south1}"
ZONE="${GCP_ZONE:-asia-south1-a}"
ALLOW_SIMULATED=0

for arg in "$@"; do
    if [[ "$arg" == "--allow-simulated" ]]; then
        ALLOW_SIMULATED=1
    fi
done

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    ALLOW_SIMULATED=1
fi

COMMIT_SHA=$(cd "$REPO_ROOT" && git rev-parse HEAD)
RESULTS_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

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

echo "=== Step 1: Consuming & Verifying 11 Stage Result Files ==="
if [[ ! -d "$RESULTS_DIR" ]]; then
    echo "[ERROR] Evidence results directory '$RESULTS_DIR' does not exist." >&2
    exit 1
fi

STAGE_SUMMARIES_JSON="{}"

for stage in "${REQUIRED_STAGES[@]}"; do
    result_file="$RESULTS_DIR/${stage}-result.json"
    
    if ! verify_stage_result "$result_file" "$STAGING_RUN_ID" "$COMMIT_SHA" "$ALLOW_SIMULATED"; then
        echo "[ERROR] Evidence collection aborted: Verification failed for stage '$stage'." >&2
        exit 1
    fi

    # Perform strict observation & transcript checks
    python3 -c "
import json, sys
res_file = sys.argv[1]
with open(res_file) as f:
    d = json.load(f)

obs = d.get('observations', [])
cmds = d.get('executed_commands', [])

if not obs:
    sys.stderr.write(f'[ERROR] Stage file {res_file} missing observations!\n')
    sys.exit(1)

if not cmds:
    sys.stderr.write(f'[ERROR] Stage file {res_file} missing executed_commands transcripts!\n')
    sys.exit(1)

for o in obs:
    if o['expected'] != o['actual']:
        sys.stderr.write(f'[ERROR] Stage file {res_file} observation {o[\"name\"]} mismatch!\n')
        sys.exit(1)
" "$result_file"

    res_hash=$(jq -r '.result_sha256' "$result_file")
    status_val=$(jq -r '.status' "$result_file")
    completed_ts=$(jq -r '.completed_at' "$result_file")
    key_name=$(echo "$stage" | tr '-' '_')

    STAGE_SUMMARIES_JSON=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
d[sys.argv[2]] = {'status': sys.argv[3], 'result_sha256': sys.argv[4], 'verified_at': sys.argv[5]}
print(json.dumps(d))
" "$STAGE_SUMMARIES_JSON" "$key_name" "$status_val" "$res_hash" "$completed_ts")
done

echo "[PASS] All 11 Stage Result Files Verified Cleanly."

EVIDENCE_MANIFEST="$RESULTS_DIR/evidence-${STAGING_RUN_ID}.json"
MANIFEST_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

OVERALL_STATUS="OPERATIONS_IMPLEMENTED_NOT_DEPLOYED"
if [[ "$ALLOW_SIMULATED" -eq 1 ]]; then
    OVERALL_STATUS="OPERATIONS_IMPLEMENTED_NOT_DEPLOYED"
else
    # Check if cleanup manifest exists for full run closure
    CLEANUP_FILE="$RESULTS_DIR/cleanup-result.json"
    if [[ -f "$CLEANUP_FILE" ]] && verify_stage_result "$CLEANUP_FILE" "$STAGING_RUN_ID" "$COMMIT_SHA" 0; then
        OVERALL_STATUS="PASS"
    else
        OVERALL_STATUS="OPERATIONS_IMPLEMENTED_NOT_DEPLOYED"
    fi
fi

cat <<EOF > "$EVIDENCE_MANIFEST"
{
  "schema_version": "1.0.0",
  "staging_run_id": "$STAGING_RUN_ID",
  "source_commit": "$COMMIT_SHA",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "endpoint_class": "STAGING_PRIVATE_HTTPS",
  "evidence_timestamp": "$MANIFEST_TS",
  "overall_status": "$OVERALL_STATUS",
  "stages": $STAGE_SUMMARIES_JSON
}
EOF

# Validate Final Evidence Manifest against Schema
SCHEMA_FILE="$REPO_ROOT/infra/package-staging/schemas/staging-evidence.schema.json"
if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
    python3 -c "import json, jsonschema; jsonschema.validate(json.load(open('$EVIDENCE_MANIFEST')), json.load(open('$SCHEMA_FILE')))"
    echo "[PASS] Evidence manifest validated against staging-evidence.schema.json."
fi

EVIDENCE_HASH=$(json_sha256 "$(cat "$EVIDENCE_MANIFEST")")
echo "OVERALL_STATUS=$OVERALL_STATUS"
echo "[PASS] Evidence Collection Complete: $EVIDENCE_MANIFEST (SHA: $EVIDENCE_HASH)"
