#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Staging Package Promotion Orchestrator & Evidence Verification Script for GenixBit OS

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

echo "=== GenixBit OS Staging Promotion Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
CLIENT_INSTANCE="${CLIENT_INSTANCE:-genixbit-staging-disposable-client}"
LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
STAGING_GNUPG_HOME="${STAGING_GNUPG_HOME:-}"
STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID:-run-staging-default}}"

if [[ -z "$PROJECT_ID" || -z "$ZONE" || -z "$STAGING_RUN_ID" ]]; then
    echo "[ERROR] GCP_PROJECT_ID, GCP_ZONE, STAGING_RUN_ID are required!" >&2
    exit 1
fi

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

ssh_client() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$CLIENT_INSTANCE" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
    fi
}

echo "=== Step 1: Promoting Package 1.0.1 from resolute-alpha to resolute-testing ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    bash "$REPO_ROOT/tools/repository/promote-package.sh" \
        --repo-dir "$LOCAL_STAGING_DIR" \
        --package "genixbit-repository-fixture" \
        --version "1.0.1" \
        --from-channel "resolute-alpha" \
        --to-channel "resolute-testing" >/dev/null

    bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
        --repo-dir "$LOCAL_STAGING_DIR" \
        --channel "resolute-testing" \
        --signing-key-fingerprint "$STAGING_KEY_FPR" \
        --gnupg-home "$STAGING_GNUPG_HOME" >/dev/null

    # Publish updated repository to host
    bash "$SCRIPT_DIR/configure-repository.sh" >/dev/null
fi

echo "=== Step 2: Switching Client Channel & Validating APT Policy ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo bash -c 'sed -i \"s/Suites: resolute-alpha/Suites: resolute-testing/\" /etc/apt/sources.list.d/genixbit-staging.sources && apt-get update -qq'"

    POLICY_OUT=$(ssh_client "apt-cache policy genixbit-repository-fixture" 2>/dev/null || echo "")
    if ! echo "$POLICY_OUT" | grep -q "resolute-testing"; then
        echo "[ERROR] Client apt-cache policy does not contain 'resolute-testing' channel!" >&2
        exit 1
    fi
fi

PROMOTION_CONDS='["alpha_and_testing_snapshots_recorded", "package_1.0.1_promoted", "package_sha256_verified", "testing_metadata_rebuilt", "testing_metadata_signed_externally", "testing_channel_published_atomically", "client_sources_switched_to_testing", "apt_cache_policy_resolute_testing_matched"]'
PUBLIC_META="{\"promoted_package\": \"genixbit-repository-fixture\", \"promoted_version\": \"1.0.1\", \"from_channel\": \"resolute-alpha\", \"to_channel\": \"resolute-testing\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "promotion" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "validate-promotion.sh" "$PROMOTION_CONDS" "$PUBLIC_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/promotion-result.json" "PROMOTION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Package Promotion Validation Completed."
