#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Controlled execution apply script for GenixBit OS Package Staging Infrastructure

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

PLAN_FILE="${1:-$INFRA_DIR/tfplan}"

if [[ ! -f "$PLAN_FILE" ]]; then
    echo "[ERROR] Missing required plan file: $PLAN_FILE" >&2
    echo "You must run 'plan.sh' and review the plan prior to running apply.sh." >&2
    exit 1
fi

if [[ "${GENIXBIT_CONFIRM_APPLY:-0}" != "1" ]]; then
    echo "[WARNING] Explicit operator confirmation required to apply infrastructure changes."
    read -rp "Type 'DEPLOY-STAGING' to confirm execution: " CONFIRM
    if [[ "$CONFIRM" != "DEPLOY-STAGING" ]]; then
        echo "[ABORT] Operator confirmation failed. Aborting apply."
        exit 1
    fi
fi

cd "$INFRA_DIR"
echo "=== Applying Reviewed Infrastructure Plan ($PLAN_FILE) ==="
"$IAC_CMD" apply "$PLAN_FILE"

echo "[PASS] Staging infrastructure deployment completed successfully."
