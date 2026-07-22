#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Test suite for GenixBit OS Package Staging Infrastructure rules and security policies.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
INFRA_DIR="$REPO_ROOT/infra/package-staging"

echo "=== Running Infrastructure Security & Policy Test Suite ==="

# 1. OpenTofu Formatting & Validation (if binary present)
IAC_CMD=""
if command -v tofu >/dev/null 2>&1; then
    IAC_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    IAC_CMD="terraform"
fi

if [[ -n "$IAC_CMD" ]]; then
    echo "[INFO] 1. Running $IAC_CMD fmt check..."
    "$IAC_CMD" fmt -check -recursive "$INFRA_DIR"
    echo "[PASS] Infrastructure formatting valid."

    echo "[INFO] 2. Running $IAC_CMD init & validate..."
    "$IAC_CMD" -chdir="$INFRA_DIR" init -backend=false >/dev/null
    "$IAC_CMD" -chdir="$INFRA_DIR" validate >/dev/null
    echo "[PASS] Infrastructure configuration valid."
else
    echo "[WARN] Neither OpenTofu nor Terraform found; skipping live IaC binary validation."
fi

MAIN_TF="$INFRA_DIR/main.tf"
VARS_TF="$INFRA_DIR/variables.tf"
OUT_TF="$INFRA_DIR/outputs.tf"

# 3. Verify No Public IP Access Config Blocks
echo "[INFO] 3. Verifying zero public IP access_config blocks..."
if grep -v '^[[:space:]]*#' "$MAIN_TF" | grep -E '[[:space:]]*access_config[[:space:]]*\{'; then
    echo "[ERROR] Detected active 'access_config' block in main.tf! Compute instances must not have public IPs." >&2
    exit 1
fi
echo "[PASS] Zero public IP access_config blocks verified."

# 4. Verify Cloud NAT Presence
echo "[INFO] 4. Verifying Cloud NAT configuration..."
if ! grep -q "google_compute_router_nat" "$MAIN_TF"; then
    echo "[ERROR] Missing Cloud NAT configuration in main.tf!" >&2
    exit 1
fi
echo "[PASS] Cloud NAT present for controlled egress."

# 5. Verify Private Cloud DNS
echo "[INFO] 5. Verifying Private Cloud DNS configuration..."
if ! grep -q "google_dns_managed_zone" "$MAIN_TF"; then
    echo "[ERROR] Missing google_dns_managed_zone in main.tf!" >&2
    exit 1
fi
echo "[PASS] Private Cloud DNS present."

# 6. Verify Public Access Prevention on Bucket
echo "[INFO] 6. Verifying public access prevention on evidence bucket..."
if ! grep -E 'public_access_prevention[[:space:]]*=[[:space:]]*"enforced"' "$MAIN_TF"; then
    echo "[ERROR] Missing public_access_prevention = \"enforced\" in main.tf!" >&2
    exit 1
fi
echo "[PASS] Public access prevention enforced on storage bucket."

# 7. Verify Separate Service Accounts
echo "[INFO] 7. Verifying separate service accounts for host and client..."
if ! grep -q "google_service_account\" \"repo_sa\"" "$MAIN_TF" || ! grep -q "google_service_account\" \"client_sa\"" "$MAIN_TF"; then
    echo "[ERROR] Missing separate repo_sa or client_sa service account definitions!" >&2
    exit 1
fi
echo "[PASS] Separate host and client service accounts verified."

# 8. Verify No Broad Owner or Editor Roles
echo "[INFO] 8. Verifying absence of broad owner/editor roles..."
if grep -E 'roles/(owner|editor)' "$MAIN_TF"; then
    echo "[ERROR] Detected broad roles/owner or roles/editor in main.tf!" >&2
    exit 1
fi
echo "[PASS] No broad owner/editor roles present."

# 9. Verify No Private Key Material
echo "[INFO] 9. Verifying absence of private key material in infra files..."
if find "$INFRA_DIR" -type f \( -name "*.pem" -o -name "*.key" -o -name "*.sec" \) | grep .; then
    echo "[ERROR] Detected private key files in infra directory!" >&2
    exit 1
fi
echo "[PASS] Zero private key material detected."

# 10. Verify Safe Deployment Scripts & Operator Confirmation Safeguards
echo "[INFO] 10. Verifying deployment script safeguards..."
if ! grep -q "GENIXBIT_CONFIRM_APPLY" "$INFRA_DIR/scripts/apply.sh" || ! grep -q "GENIXBIT_CONFIRM_DESTROY" "$INFRA_DIR/scripts/destroy.sh"; then
    echo "[ERROR] Missing operator confirmation safeguards in deployment scripts!" >&2
    exit 1
fi
echo "[PASS] Operator confirmation safeguards verified."

# 11. Verify No Public Hostname Mutation in DNS
echo "[INFO] 11. Verifying public production hostname is not mutated in DNS records..."
if grep -F "packages.os.genixbit.com" "$MAIN_TF"; then
    echo "[ERROR] Production hostname packages.os.genixbit.com detected in main.tf DNS config!" >&2
    exit 1
fi
echo "[PASS] Production DNS safe."

# 12. Verify .gitignore Rules for Terraform Secrets & State
echo "[INFO] 12. Verifying .gitignore rules for state & secrets..."
GITIGNORE="$REPO_ROOT/.gitignore"
if ! grep -q "\.tfstate" "$GITIGNORE" || ! grep -q "terraform\.tfvars" "$GITIGNORE"; then
    echo "[ERROR] Missing terraform state or tfvars rules in .gitignore!" >&2
    exit 1
fi
echo "[PASS] Gitignore rules verified."

# 13. Verify Startup Templates Syntax
echo "[INFO] 13. Validating startup templates syntax..."
TMP_RENDER=$(mktemp -d)
trap 'rm -rf "$TMP_RENDER"' EXIT

sed -e 's/\${hostname}/staging-packages.genixbit.internal/g' -e 's/\${run_id}/run-test-001/g' "$INFRA_DIR/templates/repo-host-startup.sh.tftpl" > "$TMP_RENDER/repo-host-startup.sh"
sed -e 's/\${hostname}/staging-packages.genixbit.internal/g' -e 's/\${run_id}/run-test-001/g' "$INFRA_DIR/templates/client-startup.sh.tftpl" > "$TMP_RENDER/client-startup.sh"

bash -n "$TMP_RENDER/repo-host-startup.sh"
bash -n "$TMP_RENDER/client-startup.sh"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -e SC1091 "$TMP_RENDER/repo-host-startup.sh"
    shellcheck -e SC1091 "$TMP_RENDER/client-startup.sh"
fi
echo "[PASS] Startup templates syntax & shellcheck valid."

echo "[PASS] All infrastructure security & policy checks passed successfully."
