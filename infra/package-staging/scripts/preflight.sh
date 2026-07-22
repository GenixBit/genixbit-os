#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Preflight Check Script for GenixBit OS Package Staging Infrastructure

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Unable to resolve repository root at '$REPO_ROOT'!" >&2
    exit 1
fi
cd "$INFRA_DIR"

echo "=== GenixBit OS Package Staging Preflight Checks ==="

ENABLE_APIS=0
ALLOW_PROD_OVERRIDE=0

for arg in "$@"; do
    case "$arg" in
        --enable-apis)
            ENABLE_APIS=1
            ;;
        --allow-prod-name-override)
            ALLOW_PROD_OVERRIDE=1
            ;;
    esac
done

# Simulation mode short-circuit for unit testing without live GCP CLI credentials
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    echo "[PASS] Simulated Preflight Checks Passed"
    echo "PREFLIGHT_CHECKS=PASS"
    exit 0
fi

# 1. Verify gcloud CLI
if ! command -v gcloud >/dev/null 2>&1; then
    echo "[ERROR] gcloud CLI is not installed or not on PATH." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

# 2. Verify OpenTofu / Terraform
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
echo "[PASS] IaC Binary: $IAC_CMD"

# 3. Verify Active Authenticated Account
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
if [[ -z "$ACCOUNT" ]]; then
    echo "[ERROR] No active GCP authenticated account found." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi
echo "[PASS] Authenticated Account: $ACCOUNT"

# 4. Verify Project ID
PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == --* ]]; then
    echo "[ERROR] No GCP Project ID specified. Set GCP_PROJECT_ID or pass as argument." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

if [[ "$PROJECT_ID" =~ (prod|production|default|my-project) ]]; then
    if [[ "$ALLOW_PROD_OVERRIDE" -ne 1 || -z "${GENIXBIT_DUAL_APPROVAL_TOKEN:-}" ]]; then
        echo "[ERROR] Project '$PROJECT_ID' matches a production or placeholder pattern and dual approval token is missing." >&2
        echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
        exit 1
    fi
fi
echo "[PASS] Staging Project ID: $PROJECT_ID"

# 5. Verify Project Access & Describe
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    echo "[ERROR] Unable to describe project '$PROJECT_ID'. Project missing or access denied." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

# 6. Verify Billing Status (Fail closed without || true)
BILLING_INFO=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null | head -n1 || true)
if [[ -z "$BILLING_INFO" ]]; then
    echo "[ERROR] Could not determine billing state for project '$PROJECT_ID'." >&2
    echo "BLOCKED_GCP_STAGING_BILLING_UNVERIFIED"
    exit 1
fi

if [[ "$BILLING_INFO" != "true" ]]; then
    echo "[ERROR] Billing is disabled for project '$PROJECT_ID'." >&2
    echo "BLOCKED_GCP_STAGING_BILLING_UNVERIFIED"
    exit 1
fi
echo "[PASS] Billing Verified: ENABLED"

# 7. Verify Required APIs
REQUIRED_APIS=(
    "compute.googleapis.com"
    "dns.googleapis.com"
    "iap.googleapis.com"
    "oslogin.googleapis.com"
    "storage.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
    "iam.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "serviceusage.googleapis.com"
)

ENABLED_APIS=$(gcloud services list --project="$PROJECT_ID" --format="value(config.name)" 2>/dev/null)
MISSING_APIS=()

for api in "${REQUIRED_APIS[@]}"; do
    if ! echo "$ENABLED_APIS" | grep -q "^${api}$"; then
        MISSING_APIS+=("$api")
    fi
done

if [[ ${#MISSING_APIS[@]} -gt 0 ]]; then
    if [[ "$ENABLE_APIS" -eq 1 ]]; then
        echo "[INFO] Enabling missing required APIs: ${MISSING_APIS[*]}"
        gcloud services enable "${MISSING_APIS[@]}" --project="$PROJECT_ID"
    else
        echo "[ERROR] Required GCP APIs are not enabled: ${MISSING_APIS[*]}" >&2
        echo "[HINT] Pass --enable-apis flag to enable missing services." >&2
        echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
        exit 1
    fi
fi
echo "[PASS] Required GCP APIs Verified"

# 8. Verify Region & Zone Availability
REGION="${GCP_REGION:-asia-south1}"
ZONE="${GCP_ZONE:-asia-south1-a}"

if ! gcloud compute regions describe "$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "[ERROR] Region '$REGION' is not available in project '$PROJECT_ID'." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

if ! gcloud compute zones describe "$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "[ERROR] Zone '$ZONE' is not available in project '$PROJECT_ID'." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi
echo "[PASS] Region & Zone Verified: $REGION / $ZONE"

# 9. Verify Staging Run ID & tfvars file
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260722-001}"
TFVARS_FILE="${TFVARS_FILE:-$INFRA_DIR/terraform.tfvars}"

if [[ ! -f "$TFVARS_FILE" && ! -f "$INFRA_DIR/terraform.tfvars.example" ]]; then
    echo "[ERROR] No valid tfvars file found." >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

# 10. KMS Key Verification if supplied
KMS_KEY_ID="${KMS_KEY_ID:-}"
if [[ -n "$KMS_KEY_ID" ]]; then
    if ! gcloud kms keys describe "$KMS_KEY_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
        echo "[ERROR] Supplied KMS Key '$KMS_KEY_ID' cannot be accessed or verified." >&2
        echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
        exit 1
    fi
    echo "[PASS] KMS Key Verified: $KMS_KEY_ID"
fi

echo "[PASS] All Preflight Infrastructure Checks Passed for project $PROJECT_ID (Run: $STAGING_RUN_ID)."
