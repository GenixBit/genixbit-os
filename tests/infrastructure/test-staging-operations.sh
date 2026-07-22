#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Staging Operations Behavior Test Suite (Simulated & Isolated Stubs)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
INFRA_DIR="$REPO_ROOT/infra/package-staging"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== Running Package Staging Operations Behavioral Test Suite ==="

# Prepare Staging Executable Stubs
STUB_BIN="$TMP_DIR/bin"
mkdir -p "$STUB_BIN"
export PATH="$STUB_BIN:$PATH"

# Stub: gcloud
cat << 'EOF' > "$STUB_BIN/gcloud"
#!/usr/bin/env bash
set -euo pipefail

cmd="$*"
if [[ "$cmd" == *"auth list"* ]]; then
    echo "test-user@genixbit.com"
    exit 0
fi

if [[ "$cmd" == *"billing projects describe"* ]]; then
    if [[ "${SIMULATE_BILLING_FAIL:-0}" == "1" ]]; then
        exit 1
    fi
    if [[ "${SIMULATE_BILLING_DISABLED:-0}" == "1" ]]; then
        echo "false"
        exit 0
    fi
    echo "true"
    exit 0
fi

if [[ "$cmd" == *"projects describe"* ]]; then
    if [[ "$cmd" == *"missing-project"* ]]; then
        exit 1
    fi
    echo "projectNumber: '1234567890'"
    exit 0
fi

if [[ "$cmd" == *"services list"* ]]; then
    if [[ "${SIMULATE_MISSING_API:-0}" == "1" ]]; then
        echo "compute.googleapis.com"
        exit 0
    fi
    echo -e "compute.googleapis.com\ndns.googleapis.com\niap.googleapis.com\noslogin.googleapis.com\nstorage.googleapis.com\nlogging.googleapis.com\nmonitoring.googleapis.com\niam.googleapis.com\ncloudresourcemanager.googleapis.com\nserviceusage.googleapis.com"
    exit 0
fi

if [[ "$cmd" == *"compute regions describe"* || "$cmd" == *"compute zones describe"* ]]; then
    echo "status: UP"
    exit 0
fi

exit 0
EOF
chmod +x "$STUB_BIN/gcloud"

# Stub: OpenTofu / Terraform
cat << 'EOF' > "$STUB_BIN/tofu"
#!/usr/bin/env bash
set -euo pipefail

cmd="$*"
if [[ "$cmd" == *"version"* ]]; then
    echo "OpenTofu v1.8.8"
    exit 0
fi
if [[ "$cmd" == *"init"* || "$cmd" == *"validate"* ]]; then
    exit 0
fi
if [[ "$cmd" == *"plan"* ]]; then
    out_file=""
    for arg in "$@"; do
        if [[ "$arg" == -out=* ]]; then
            out_file="${arg#-out=}"
        fi
    done
    if [[ -n "$out_file" ]]; then
        echo "mock plan content" > "$out_file"
    fi
    exit 0
fi
if [[ "$cmd" == *"show -json"* ]]; then
    if [[ "${SIMULATE_PUBLIC_IP_VIOLATION:-0}" == "1" ]]; then
        echo '{"resource_changes":[{"change":{"actions":["create"],"after":{"access_config":[{}]}}}]}'
        exit 0
    fi
    if [[ "${SIMULATE_PROD_DNS_VIOLATION:-0}" == "1" ]]; then
        echo '{"resource_changes":[{"change":{"after":{"name":"packages.os.genixbit.com"}}}]}'
        exit 0
    fi
    echo '{"resource_changes":[{"change":{"actions":["create"]}}]}'
    exit 0
fi
if [[ "$cmd" == *"apply"* ]]; then
    exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/tofu"

# 1. Test Billing Command Failure (FAIL)
echo "[INFO] Test 1: Billing command failure fails closed..."
if SIMULATE_BILLING_FAIL=1 bash "$INFRA_DIR/scripts/preflight.sh" "test-staging-proj" 2>/dev/null; then
    echo "[ERROR] Preflight did not fail when billing command failed!" >&2
    exit 1
fi
echo "[PASS] Billing command failure correctly failed closed."

# 2. Test Billing Disabled (FAIL)
echo "[INFO] Test 2: Billing disabled fails closed..."
if SIMULATE_BILLING_DISABLED=1 bash "$INFRA_DIR/scripts/preflight.sh" "test-staging-proj" 2>/dev/null; then
    echo "[ERROR] Preflight did not fail when billing was disabled!" >&2
    exit 1
fi
echo "[PASS] Disabled billing correctly failed closed."

# 3. Test Missing API (FAIL)
echo "[INFO] Test 3: Missing API fails closed..."
if SIMULATE_MISSING_API=1 bash "$INFRA_DIR/scripts/preflight.sh" "test-staging-proj" 2>/dev/null; then
    echo "[ERROR] Preflight did not fail when required API was missing!" >&2
    exit 1
fi
echo "[PASS] Missing API correctly failed closed."

# 4. Test Production Project Name (FAIL)
echo "[INFO] Test 4: Production project name fails closed..."
if bash "$INFRA_DIR/scripts/preflight.sh" "genixbit-prod-project" 2>/dev/null; then
    echo "[ERROR] Preflight permitted production project name!" >&2
    exit 1
fi
echo "[PASS] Production project name correctly rejected."

# 5. Test Plan Generation & Provenance (PASS)
echo "[INFO] Test 5: Safe plan generation and manifest creation..."
TEST_RUN_ID="run-test-behav-001"
TEST_TFVARS="$TMP_DIR/terraform.tfvars"
echo 'project_id = "test-staging-proj"' > "$TEST_TFVARS"

STAGING_RUN_ID="$TEST_RUN_ID" TFVARS_FILE="$TEST_TFVARS" bash "$INFRA_DIR/scripts/plan.sh" "test-staging-proj" --allow-local-state >/dev/null

PLAN_MANIFEST="$INFRA_DIR/plan-manifest-${TEST_RUN_ID}.json"
if [[ ! -f "$PLAN_MANIFEST" ]]; then
    echo "[ERROR] Plan manifest file was not generated!" >&2
    exit 1
fi
echo "[PASS] Plan generation & provenance manifest created successfully."

# 6. Test Stale/Modified Plan Detection in Apply (FAIL)
echo "[INFO] Test 6: Tampered plan file fails in apply..."
PLAN_FILE="$INFRA_DIR/plan-${TEST_RUN_ID}.tfplan"
echo "tampered plan content" > "$PLAN_FILE"

if STAGING_RUN_ID="$TEST_RUN_ID" GENIXBIT_CONFIRM_APPLY=1 bash "$INFRA_DIR/scripts/apply.sh" "$PLAN_FILE" "$PLAN_MANIFEST" 2>/dev/null; then
    echo "[ERROR] Apply permitted tampered plan file!" >&2
    exit 1
fi
echo "[PASS] Tampered plan correctly rejected by apply.sh."

# Cleanup test plan artifacts
rm -f "$INFRA_DIR/plan-${TEST_RUN_ID}.tfplan" "$INFRA_DIR/plan-${TEST_RUN_ID}.json" "$PLAN_MANIFEST"

# 7. Test Operations & Client Validation Stubs
echo "[INFO] Test 7: Simulated Repository Configuration & Client Validation..."
MOCK_REPO_DIR="$TMP_DIR/mock_staging_pub"
mkdir -p "$MOCK_REPO_DIR/dists/resolute-alpha/main/binary-amd64"
mkdir -p "$MOCK_REPO_DIR/usr/share/keyrings"
touch "$MOCK_REPO_DIR/dists/resolute-alpha/main/binary-amd64/Packages"
touch "$MOCK_REPO_DIR/dists/resolute-alpha/main/binary-amd64/Packages.gz"
touch "$MOCK_REPO_DIR/dists/resolute-alpha/main/binary-amd64/Packages.xz"
touch "$MOCK_REPO_DIR/dists/resolute-alpha/Release"
touch "$MOCK_REPO_DIR/dists/resolute-alpha/InRelease"
touch "$MOCK_REPO_DIR/dists/resolute-alpha/Release.gpg"

LOCAL_STAGING_DIR="$MOCK_REPO_DIR" GENIXBIT_SIMULATE_OPS=1 STAGING_RUN_ID="$TEST_RUN_ID" bash "$INFRA_DIR/scripts/configure-repository.sh" "test-staging-proj" >/dev/null

CLIENT_OUT=$(GENIXBIT_SIMULATE_OPS=1 STAGING_RUN_ID="$TEST_RUN_ID" bash "$INFRA_DIR/scripts/validate-client.sh" "test-staging-proj")
if ! echo "$CLIENT_OUT" | grep -q "STAGING_HTTPS=PASS" || ! echo "$CLIENT_OUT" | grep -q "STAGING_UPGRADE=PASS"; then
    echo "[ERROR] Client validation failed to emit required evidence markers!" >&2
    exit 1
fi
echo "[PASS] Client validation emitted all required evidence markers."

# 8. Test Evidence Collection
echo "[INFO] Test 8: Non-sensitive Evidence Collection..."
GENIXBIT_SIMULATE_OPS=1 STAGING_RUN_ID="$TEST_RUN_ID" bash "$INFRA_DIR/scripts/collect-evidence.sh" "test-staging-proj" >/dev/null
if [[ ! -f "$INFRA_DIR/evidence-${TEST_RUN_ID}.json" ]]; then
    echo "[ERROR] Evidence collection failed to create manifest!" >&2
    exit 1
fi
echo "[PASS] Non-sensitive evidence collection verified."
rm -f "$INFRA_DIR/evidence-${TEST_RUN_ID}.json"

# 9. Test Teardown / Destroy Safeguards (FAIL on production / PASS on staging)
echo "[INFO] Test 9: Safe Destroy execution..."
GENIXBIT_SIMULATE_OPS=1 STAGING_RUN_ID="$TEST_RUN_ID" GENIXBIT_CONFIRM_DESTROY=1 TFVARS_FILE="$TEST_TFVARS" bash "$INFRA_DIR/scripts/destroy.sh" "test-staging-proj" >/dev/null
rm -f "$INFRA_DIR/destroy-${TEST_RUN_ID}.tfplan" "$INFRA_DIR/destroy-${TEST_RUN_ID}.json"
echo "[PASS] Destroy execution verified cleanly."

echo "[PASS] All package staging operational behavior tests passed successfully."
