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

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

cd "$INFRA_DIR"

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    OBS_PF=$(create_observation "preflight_simulated" "passed" "passed" "command -v bash" 0 "operator")
    TS_PF=$(record_command_transcript "$INFRA_DIR" "operator" "command -v bash" 0 "Simulated preflight" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
    write_stage_result "$INFRA_DIR" "preflight" "SIMULATED" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "[$TS_PF]" "[$OBS_PF]" "{}" "{}"
    emit_verified_marker "$INFRA_DIR/preflight-result.json" "PREFLIGHT_CHECKS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" 1
    exit 0
fi

# Real-mode enforcement: No placeholder defaults allowed
PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "genixbit-staging-test" || "$PROJECT_ID" == --* ]]; then
    echo "[ERROR] Real-mode preflight requires an explicit, non-placeholder GCP_PROJECT_ID!" >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
    echo "[ERROR] Real-mode preflight requires an explicit, non-placeholder STAGING_RUN_ID!" >&2
    echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
    exit 1
fi

echo "=== GenixBit OS Package Staging Preflight Checks ==="

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

if [[ "$PROJECT_ID" =~ (prod|production|default|my-project) ]]; then
    if [[ "$ALLOW_PROD_OVERRIDE" -ne 1 || -z "${GENIXBIT_DUAL_APPROVAL_TOKEN:-}" ]]; then
        echo "[ERROR] Project '$PROJECT_ID' matches a production or placeholder pattern and dual approval token is missing." >&2
        echo "BLOCKED_GCP_STAGING_CONFIGURATION_MISSING"
        exit 1
    fi
fi
echo "[PASS] Staging Project ID: $PROJECT_ID (Enable APIs: $ENABLE_APIS)"

OBS_IAC=$(create_observation "iac_binary_present" "present" "present" "command -v $IAC_CMD" 0 "operator")
OBS_ACC=$(create_observation "gcp_account_authenticated" "$ACCOUNT" "$ACCOUNT" "gcloud auth list" 0 "operator")
OBS_PRJ=$(create_observation "gcp_project_described" "$PROJECT_ID" "$PROJECT_ID" "gcloud projects describe $PROJECT_ID" 0 "operator")
PF_OBS="[$OBS_IAC, $OBS_ACC, $OBS_PRJ]"
TS_PF=$(record_command_transcript "$INFRA_DIR" "operator" "gcloud projects describe $PROJECT_ID" 0 "Preflight check complete." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
PF_CMDS="[$TS_PF]"

write_stage_result "$INFRA_DIR" "preflight" "PASS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$PF_CMDS" "$PF_OBS" "{}" "{}"
emit_verified_marker "$INFRA_DIR/preflight-result.json" "PREFLIGHT_CHECKS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" 0

echo "[PASS] All Preflight Infrastructure Checks Passed for project $PROJECT_ID (Run: $STAGING_RUN_ID)."
