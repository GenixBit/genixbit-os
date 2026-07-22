#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Safe infrastructure teardown script for GenixBit OS Package Staging Infrastructure

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

STAGING_RUN_ID="${1:-${STAGING_RUN_ID:-}}"
if [[ -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] Usage: $0 <STAGING_RUN_ID>" >&2
    exit 1
fi

echo "=== GenixBit OS Package Staging Teardown ($STAGING_RUN_ID) ==="

if [[ "${GENIXBIT_CONFIRM_DESTROY:-0}" != "1" ]]; then
    echo "[WARNING] This will destroy all staging infrastructure for run ID '$STAGING_RUN_ID'."
    read -rp "Type 'DESTROY-STAGING' to confirm teardown: " CONFIRM
    if [[ "$CONFIRM" != "DESTROY-STAGING" ]]; then
        echo "[ABORT] Operator confirmation failed. Aborting teardown."
        exit 1
    fi
fi

cd "$INFRA_DIR"
echo "=== Executing $IAC_CMD Destroy ==="
"$IAC_CMD" destroy -auto-approve

echo "[PASS] Staging infrastructure teardown completed cleanly."
