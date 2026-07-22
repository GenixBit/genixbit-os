#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Plan Generation Script with Provenance Tracking for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$INFRA_DIR/.." && pwd)

cd "$INFRA_DIR"

ALLOW_LOCAL_STATE=0
PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"

for arg in "$@"; do
    case "$arg" in
        --allow-local-state)
            ALLOW_LOCAL_STATE=1
            ;;
    esac
done

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == --* ]]; then
    echo "[ERROR] GCP Project ID is required. Pass as first argument or set GCP_PROJECT_ID." >&2
    exit 1
fi

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260722-001}"
REGION="${GCP_REGION:-asia-south1}"
ZONE="${GCP_ZONE:-asia-south1-a}"
TFVARS_FILE="${TFVARS_FILE:-$INFRA_DIR/terraform.tfvars}"

if [[ ! -f "$TFVARS_FILE" ]]; then
    TFVARS_FILE="$INFRA_DIR/terraform.tfvars.example"
fi

# 1. Run Preflight Check
echo "=== Step 1: Executing Preflight Checks ==="
bash "$SCRIPT_DIR/preflight.sh" "$PROJECT_ID"

# 2. Check Backend & Local State Restrictions
BACKEND_HCL="$INFRA_DIR/backend.hcl"
BACKEND_ARG=""

if [[ -f "$BACKEND_HCL" ]]; then
    BACKEND_ARG="-backend-config=$BACKEND_HCL"
    echo "[PASS] Using Remote Backend: $BACKEND_HCL"
else
    if [[ "$ALLOW_LOCAL_STATE" -ne 1 ]]; then
        echo "[ERROR] No backend.hcl found! Local state is forbidden for real cloud runs unless --allow-local-state is explicitly passed." >&2
        exit 1
    fi
    echo "[WARN] Local state permitted via --allow-local-state."
fi

# 3. Detect IaC Tool Binary
IAC_CMD=""
if command -v tofu >/dev/null 2>&1; then
    IAC_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    IAC_CMD="terraform"
else
    echo "[ERROR] OpenTofu or Terraform binary required." >&2
    exit 1
fi

TOFU_VERSION=$("$IAC_CMD" version | head -n1)

# 4. Initialize IaC Backend
echo "=== Step 2: Initializing OpenTofu / Terraform ==="
if [[ -n "$BACKEND_ARG" ]]; then
    "$IAC_CMD" init "$BACKEND_ARG" -reconfigure
else
    "$IAC_CMD" init -backend=false
fi

"$IAC_CMD" validate

# 5. Generate Saved Plan File
PLAN_FILE="$INFRA_DIR/plan-${STAGING_RUN_ID}.tfplan"
PLAN_JSON_FILE="$INFRA_DIR/plan-${STAGING_RUN_ID}.json"
MANIFEST_FILE="$INFRA_DIR/plan-manifest-${STAGING_RUN_ID}.json"

echo "=== Step 3: Generating Execution Plan ($PLAN_FILE) ==="
"$IAC_CMD" plan -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="zone=$ZONE" -var="staging_run_id=$STAGING_RUN_ID" -var-file="$TFVARS_FILE" -out="$PLAN_FILE"

# 6. Export Plan JSON for Security Analysis
"$IAC_CMD" show -json "$PLAN_FILE" > "$PLAN_JSON_FILE"

# 7. Analyze Plan JSON for Security Rules
echo "=== Step 4: Analyzing Plan JSON Security Rules ==="
NO_PUBLIC_IPS="PASS"
NO_PROD_DNS="PASS"

if grep -q '"access_config"' "$PLAN_JSON_FILE"; then
    echo "[ERROR] Security Violation: Detected active public IP access_config in plan JSON!" >&2
    NO_PUBLIC_IPS="FAIL"
    exit 1
fi

if grep -q "packages.os.genixbit.com" "$PLAN_JSON_FILE"; then
    echo "[ERROR] Security Violation: Detected public production DNS packages.os.genixbit.com in plan JSON!" >&2
    NO_PROD_DNS="FAIL"
    exit 1
fi

# Extract Resource Count Summary
ADD_COUNT=$(jq '[.resource_changes[]? | select(.change.actions[] == "create")] | length' "$PLAN_JSON_FILE" 2>/dev/null || echo "0")
CHANGE_COUNT=$(jq '[.resource_changes[]? | select(.change.actions[] == "update")] | length' "$PLAN_JSON_FILE" 2>/dev/null || echo "0")
DESTROY_COUNT=$(jq '[.resource_changes[]? | select(.change.actions[] == "delete")] | length' "$PLAN_JSON_FILE" 2>/dev/null || echo "0")

ADD_COUNT="${ADD_COUNT:-0}"
CHANGE_COUNT="${CHANGE_COUNT:-0}"
DESTROY_COUNT="${DESTROY_COUNT:-0}"

# 8. Record Provenance Metadata & Checksums
SOURCE_COMMIT=$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "0000000000000000000000000000000000000000")
CLEAN_TREE="true"
if ! (cd "$REPO_ROOT" && git diff --quiet 2>/dev/null); then
    CLEAN_TREE="false"
fi

TFVARS_HASH=$(sha256sum "$TFVARS_FILE" | cut -d' ' -f1)
BACKEND_HASH=$(if [[ -f "$BACKEND_HCL" ]]; then sha256sum "$BACKEND_HCL" | cut -d' ' -f1; else echo "0000000000000000000000000000000000000000000000000000000000000000"; fi)
LOCK_HASH=$(if [[ -f "$INFRA_DIR/.terraform.lock.hcl" ]]; then sha256sum "$INFRA_DIR/.terraform.lock.hcl" | cut -d' ' -f1; else echo "0000000000000000000000000000000000000000000000000000000000000000"; fi)
PLAN_HASH=$(sha256sum "$PLAN_FILE" | cut -d' ' -f1)
PLAN_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 9. Construct Plan Manifest File
cat << EOF > "$MANIFEST_FILE"
{
  "schema_version": "1.0.0",
  "source_commit": "$SOURCE_COMMIT",
  "clean_working_tree": $CLEAN_TREE,
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "staging_run_id": "$STAGING_RUN_ID",
  "tfvars_sha256": "$TFVARS_HASH",
  "backend_config_sha256": "$BACKEND_HASH",
  "opentofu_version": "$TOFU_VERSION",
  "provider_lock_sha256": "$LOCK_HASH",
  "plan_file_sha256": "$PLAN_HASH",
  "plan_timestamp": "$PLAN_TS",
  "no_public_ips": "$NO_PUBLIC_IPS",
  "no_prod_dns_mutation": "$NO_PROD_DNS",
  "resource_count": {
    "add": $ADD_COUNT,
    "change": $CHANGE_COUNT,
    "destroy": $DESTROY_COUNT
  }
}
EOF

# 10. Validate Plan Manifest against JSON Schema
if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
    python3 -c "import json, jsonschema; jsonschema.validate(json.load(open('$MANIFEST_FILE')), json.load(open('$INFRA_DIR/schemas/plan-manifest.schema.json')))"
    echo "[PASS] Plan manifest validated against schema."
fi

echo "[PASS] Generated plan file: $PLAN_FILE (SHA: $PLAN_HASH)"
echo "[PASS] Generated plan manifest: $MANIFEST_FILE"
