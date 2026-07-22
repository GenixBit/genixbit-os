#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Preflight environment check script for GenixBit OS Package Staging Infrastructure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$INFRA_DIR"

echo "=== GenixBit OS Package Staging Preflight Checks ==="

if ! command -v gcloud >/dev/null 2>&1; then
    echo "[ERROR] gcloud CLI is missing." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

IAC_CMD=""
if command -v tofu >/dev/null 2>&1; then
    IAC_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    IAC_CMD="terraform"
else
    echo "[ERROR] Neither OpenTofu ('tofu') nor Terraform ('terraform') is installed." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [[ -z "$ACCOUNT" ]]; then
    echo "[ERROR] No active GCP authenticated account." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi
echo "[PASS] Authenticated GCP account: $ACCOUNT"

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
if [[ -z "$PROJECT_ID" ]]; then
    echo "[ERROR] No GCP project specified! Pass project ID as first parameter or set GCP_PROJECT_ID." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

if [[ "$PROJECT_ID" =~ (prod|production|default|my-project) ]]; then
    echo "[ERROR] Rejecting project '$PROJECT_ID' as it appears to be a production or placeholder project name." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi
echo "[PASS] Staging Project ID: $PROJECT_ID"

# Verify project access & billing
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    echo "[ERROR] Unable to describe GCP project '$PROJECT_ID'. Project missing or access denied." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

BILLING_ENABLED=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "true")
if [[ "$BILLING_ENABLED" == "false" ]]; then
    echo "[ERROR] Billing is not enabled for project '$PROJECT_ID'." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi
echo "[PASS] Project access & billing verified."

echo "[PASS] Preflight checks passed cleanly for $IAC_CMD on project $PROJECT_ID."
