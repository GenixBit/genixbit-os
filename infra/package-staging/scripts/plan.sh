#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Plan generation script for GenixBit OS Package Staging Infrastructure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

IAC_CMD=""
if command -v tofu >/dev/null 2>&1; then
    IAC_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    IAC_CMD="terraform"
else
    echo "[ERROR] OpenTofu or Terraform is required." >&2
    exit 1
fi

PROJECT_ID="${1:-${GCP_PROJECT_ID:-}}"
if [[ -z "$PROJECT_ID" ]]; then
    echo "[ERROR] Usage: $0 <PROJECT_ID> [TFVARS_FILE]" >&2
    exit 1
fi

TFVARS_FILE="${2:-$INFRA_DIR/terraform.tfvars}"

cd "$INFRA_DIR"

echo "=== Initializing $IAC_CMD Infrastructure Configuration ==="
"$IAC_CMD" init -backend=false

echo "=== Validating $IAC_CMD Syntax & Rules ==="
"$IAC_CMD" validate

echo "=== Generating Saved Execution Plan (tfplan) ==="
if [[ -f "$TFVARS_FILE" ]]; then
    "$IAC_CMD" plan -var="project_id=$PROJECT_ID" -var-file="$TFVARS_FILE" -out=tfplan
else
    "$IAC_CMD" plan -var="project_id=$PROJECT_ID" -out=tfplan
fi

echo "[PASS] Generated saved plan file: $INFRA_DIR/tfplan"
echo "[NOTE] Review plan details above. This script does NOT apply infrastructure changes."
