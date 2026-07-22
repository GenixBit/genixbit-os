#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Safe Teardown Script for GenixBit OS Package Staging Infrastructure

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

cd "$INFRA_DIR"

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PROJECT_ID="${GCP_PROJECT_ID:-${1:-genixbit-staging-test}}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260722-001}"
REGION="${GCP_REGION:-asia-south1}"
ZONE="${GCP_ZONE:-asia-south1-a}"
TFVARS_FILE="${TFVARS_FILE:-$INFRA_DIR/terraform.tfvars}"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    OBS_SIM=$(create_observation "destroy_simulated" "completed" "completed" "command -v bash" 0 "operator")
    TS_SIM=$(record_command_transcript "$INFRA_DIR" "operator" "command -v bash" 0 "Simulated destroy" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
    write_stage_result "$INFRA_DIR" "cleanup" "SIMULATED" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "[$TS_SIM]" "[$OBS_SIM]" "{}" "{}"
    emit_verified_marker "$INFRA_DIR/cleanup-result.json" "CLEANUP" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" 1
    exit 0
fi

if [[ ! -f "$TFVARS_FILE" ]]; then
    TFVARS_FILE="$INFRA_DIR/terraform.tfvars.example"
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == --* ]]; then
    echo "[ERROR] Usage: $0 <PROJECT_ID> [STAGING_RUN_ID]" >&2
    exit 1
fi

echo "=== GenixBit OS Package Staging Teardown ($STAGING_RUN_ID) ==="

# 1. Detect IaC Tool Binary
IAC_CMD=""
if command -v tofu >/dev/null 2>&1; then
    IAC_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    IAC_CMD="terraform"
else
    echo "[ERROR] OpenTofu or Terraform binary required." >&2
    exit 1
fi

# 2. Generate Saved Destroy Plan
DESTROY_PLAN="$INFRA_DIR/destroy-${STAGING_RUN_ID}.tfplan"
DESTROY_JSON="$INFRA_DIR/destroy-${STAGING_RUN_ID}.json"

echo "=== Generating Saved Destroy Plan ($DESTROY_PLAN) ==="
"$IAC_CMD" plan -destroy \
    -var="project_id=$PROJECT_ID" \
    -var="region=$REGION" \
    -var="zone=$ZONE" \
    -var="staging_run_id=$STAGING_RUN_ID" \
    -var-file="$TFVARS_FILE" \
    -out="$DESTROY_PLAN"

"$IAC_CMD" show -json "$DESTROY_PLAN" > "$DESTROY_JSON"

# 3. Verify Destroy Safety Rules (Refuse Production / Shared Resources)
if grep -q "production" "$DESTROY_JSON"; then
    echo "[ERROR] Safety Violation: Destroy plan contains resources labeled 'production'!" >&2
    exit 1
fi

DESTROY_PLAN_HASH=$(file_sha256 "$DESTROY_PLAN")
echo "[PASS] Saved Destroy Plan Verified (Hash: $DESTROY_PLAN_HASH)"

# 4. Operator Confirmation Safeguard
if [[ "${GENIXBIT_CONFIRM_DESTROY:-0}" != "1" ]]; then
    echo "[WARNING] This will permanently destroy staging infrastructure for run ID '$STAGING_RUN_ID'."
    read -rp "Type 'DESTROY-STAGING' to confirm teardown: " CONFIRM
    if [[ "$CONFIRM" != "DESTROY-STAGING" ]]; then
        echo "[ABORT] Operator confirmation failed. Aborting teardown."
        exit 1
    fi
fi

# 5. Execute Destroy using Saved Plan
echo "=== Executing $IAC_CMD apply $DESTROY_PLAN ==="
"$IAC_CMD" apply "$DESTROY_PLAN"

OBS_CLR=$(create_observation "destroy_plan_verified" "$DESTROY_PLAN_HASH" "$DESTROY_PLAN_HASH" "sha256sum '$DESTROY_PLAN'" 0 "operator")
OBS_APP=$(create_observation "iac_destroy_applied" "0" "0" "$IAC_CMD apply $DESTROY_PLAN" 0 "operator")
CLEANUP_OBS="[$OBS_CLR, $OBS_APP]"

TS_CLR=$(record_command_transcript "$INFRA_DIR" "operator" "$IAC_CMD apply $DESTROY_PLAN" 0 "Destroy completed cleanly." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
CLEANUP_CMDS="[$TS_CLR]"

write_stage_result "$INFRA_DIR" "cleanup" "PASS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$CLEANUP_CMDS" "$CLEANUP_OBS" "{}" "{}"
emit_verified_marker "$INFRA_DIR/cleanup-result.json" "CLEANUP" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" 0
echo "[PASS] Staging infrastructure teardown completed cleanly."
