#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Execution Apply Script with Plan Verification for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Unable to resolve repository root at '$REPO_ROOT'!" >&2
    exit 1
fi

cd "$INFRA_DIR"

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260722-001}"
PLAN_FILE="${1:-$INFRA_DIR/plan-${STAGING_RUN_ID}.tfplan}"
MANIFEST_FILE="${2:-$INFRA_DIR/plan-manifest-${STAGING_RUN_ID}.json}"

echo "=== GenixBit OS Package Staging Apply Verification ==="

# 1. Require Saved Plan File & Manifest
if [[ ! -f "$PLAN_FILE" ]]; then
    echo "[ERROR] Missing required plan file: $PLAN_FILE" >&2
    echo "Direct 'tofu apply' without a reviewed saved plan is forbidden." >&2
    exit 1
fi

if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "[ERROR] Missing required plan manifest file: $MANIFEST_FILE" >&2
    exit 1
fi

# 2. Verify Plan Hash
ACTUAL_PLAN_HASH=$(sha256sum "$PLAN_FILE" | cut -d' ' -f1)
EXPECTED_PLAN_HASH=$(jq -r '.plan_file_sha256' "$MANIFEST_FILE" 2>/dev/null || echo "")

if [[ "$ACTUAL_PLAN_HASH" != "$EXPECTED_PLAN_HASH" ]]; then
    echo "[ERROR] Plan file hash mismatch! Plan file has been modified since manifest creation." >&2
    echo "Expected: $EXPECTED_PLAN_HASH" >&2
    echo "Actual:   $ACTUAL_PLAN_HASH" >&2
    exit 1
fi
echo "[PASS] Plan Hash Verified: $ACTUAL_PLAN_HASH"

# 3. Verify Source Commit Matching
CURRENT_COMMIT=$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "")
EXPECTED_COMMIT=$(jq -r '.source_commit' "$MANIFEST_FILE" 2>/dev/null || echo "")

if [[ "$CURRENT_COMMIT" != "$EXPECTED_COMMIT" ]]; then
    echo "[ERROR] Git source commit mismatch! Plan was generated from a different commit." >&2
    echo "Expected: $EXPECTED_COMMIT" >&2
    echo "Current:  $CURRENT_COMMIT" >&2
    exit 1
fi
echo "[PASS] Source Commit Verified: $CURRENT_COMMIT"

# 4. Verify Clean Working Tree
if [[ "${ALLOW_DIRTY_TREE:-0}" -ne 1 ]]; then
    if ! git diff --quiet 2>/dev/null; then
        echo "[ERROR] Git working tree is dirty! Commit changes or clean working directory before apply." >&2
        exit 1
    fi
fi
echo "[PASS] Working Tree Clean"

# 5. Verify Project ID & Staging Run ID Matching
EXPECTED_PROJECT=$(jq -r '.project_id' "$MANIFEST_FILE" 2>/dev/null || echo "")
EXPECTED_RUN_ID=$(jq -r '.staging_run_id' "$MANIFEST_FILE" 2>/dev/null || echo "")

if [[ -n "${GCP_PROJECT_ID:-}" && "$GCP_PROJECT_ID" != "$EXPECTED_PROJECT" ]]; then
    echo "[ERROR] GCP_PROJECT_ID mismatch! Plan project: $EXPECTED_PROJECT, Environment project: $GCP_PROJECT_ID" >&2
    exit 1
fi

if [[ "$STAGING_RUN_ID" != "$EXPECTED_RUN_ID" ]]; then
    echo "[ERROR] STAGING_RUN_ID mismatch! Plan run ID: $EXPECTED_RUN_ID, Environment run ID: $STAGING_RUN_ID" >&2
    exit 1
fi
echo "[PASS] Project ID & Staging Run ID Verified: $EXPECTED_PROJECT / $EXPECTED_RUN_ID"

# 6. Verify Plan Age (Max 2 hours / 7200 seconds)
PLAN_TS=$(jq -r '.plan_timestamp' "$MANIFEST_FILE" 2>/dev/null || echo "")
if [[ -n "$PLAN_TS" ]]; then
    PLAN_EPOCH=$(date -u -d "$PLAN_TS" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$PLAN_TS" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date -u +%s)
    AGE=$((NOW_EPOCH - PLAN_EPOCH))
    if [[ $AGE -gt 7200 ]]; then
        echo "[ERROR] Plan is stale! Plan age is ${AGE}s (max 7200s allowed). Regenerate plan." >&2
        exit 1
    fi
    echo "[PASS] Plan Age Verified: ${AGE}s"
fi

# 7. Operator Confirmation Safeguard
if [[ "${GENIXBIT_CONFIRM_APPLY:-0}" != "1" ]]; then
    echo "[WARNING] Explicit operator confirmation required to execute plan."
    read -rp "Type 'DEPLOY-STAGING' to confirm apply execution: " CONFIRM
    if [[ "$CONFIRM" != "DEPLOY-STAGING" ]]; then
        echo "[ABORT] Operator confirmation failed. Aborting apply."
        exit 1
    fi
fi

# 8. Detect IaC Binary
IAC_CMD=""
if command -v tofu >/dev/null 2>&1; then
    IAC_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    IAC_CMD="terraform"
else
    echo "[ERROR] OpenTofu or Terraform binary required." >&2
    exit 1
fi

# 9. Execute Apply
echo "=== Step 5: Executing $IAC_CMD apply $PLAN_FILE ==="
"$IAC_CMD" apply "$PLAN_FILE"

# 10. Record Apply Result Manifest
APPLY_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESULT_MANIFEST="$INFRA_DIR/apply-result-${STAGING_RUN_ID}.json"

cat << EOF > "$RESULT_MANIFEST"
{
  "schema_version": "1.0.0",
  "staging_run_id": "$STAGING_RUN_ID",
  "project_id": "$EXPECTED_PROJECT",
  "source_commit": "$CURRENT_COMMIT",
  "plan_file_sha256": "$ACTUAL_PLAN_HASH",
  "apply_timestamp": "$APPLY_TS",
  "apply_status": "PASS"
}
EOF

echo "[PASS] Staging Infrastructure Apply Completed. Result recorded at: $RESULT_MANIFEST"
