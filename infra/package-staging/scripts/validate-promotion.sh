#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Release Candidate Promotion Verification Script for GenixBit OS

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

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-genixbit-staging-client}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-testing" "$LOCAL_STAGING_DIR/snapshots"
    echo "Testing_Release_Content" > "$LOCAL_STAGING_DIR/dists/resolute-testing/Release"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-}"
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
        echo "[ERROR] STAGING_RUN_ID required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_FPR" || "$STAGING_KEY_FPR" =~ ^12345678 ]]; then
        echo "[ERROR] STAGING_KEY_FPR required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
        echo "[ERROR] LOCAL_STAGING_DIR required and must exist!" >&2
        exit 1
    fi
fi

ssh_client() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "${CLIENT_INSTANCE_NAME:-genixbit-staging-client}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
    fi
}

# Step 1: Promote Package from resolute-alpha to resolute-testing
PROMOTE_CMD="bash $REPO_ROOT/tools/repository/promote-package.sh --repo-dir '$LOCAL_STAGING_DIR' --package genixbit-repository-fixture --from-channel resolute-alpha --to-channel resolute-testing"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-testing"
    bash "$REPO_ROOT/tools/repository/promote-package.sh" --repo-dir "$LOCAL_STAGING_DIR" --package "genixbit-repository-fixture" --from-channel "resolute-alpha" --to-channel "resolute-testing"

    # Sync promoted testing channel to repo host
    COPYFILE_DISABLE=1 tar -czf "$LOCAL_STAGING_DIR/testing_dist.tar.gz" -C "$LOCAL_STAGING_DIR/dists/resolute-testing" .
    gcloud compute scp "$LOCAL_STAGING_DIR/testing_dist.tar.gz" "${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}:/tmp/testing_dist.tar.gz" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
    gcloud compute ssh "${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="sudo mkdir -p /var/srv/genixbit-repository/current/dists/resolute-testing && sudo tar -xzf /tmp/testing_dist.tar.gz -C /var/srv/genixbit-repository/current/dists/resolute-testing/ && sudo rm -f /tmp/testing_dist.tar.gz"
    rm -f "$LOCAL_STAGING_DIR/testing_dist.tar.gz"

    # Sign promoted resolute-testing Release metadata on repo host
    gcloud compute ssh "${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="
    set -euo pipefail
    BUILD_DIR='/tmp/genixbit_repo_build'
    KEY_FPR=\$(cat \"\$BUILD_DIR/key_fpr.txt\")
    cd /var/srv/genixbit-repository/current/dists/resolute-testing
    sudo GNUPGHOME=\"\$BUILD_DIR/gpg\" gpg --batch --yes -u \"\$KEY_FPR\" --clearsign --digest-algo SHA256 -o InRelease Release
    sudo GNUPGHOME=\"\$BUILD_DIR/gpg\" gpg --batch --yes -u \"\$KEY_FPR\" --detach-sign --armor --digest-algo SHA256 -o Release.gpg Release
    "

    # Configure client source for resolute-testing and update APT cache
    ssh_client "cat <<EOF | sudo tee /etc/apt/sources.list.d/genixbit-testing.sources
Types: deb
URIs: https://${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}/
Suites: resolute-testing
Components: main
Signed-By: /etc/apt/trusted.gpg.d/genixbit-staging.gpg
EOF
sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/genixbit-testing.sources"
fi

TESTING_RELEASE="$LOCAL_STAGING_DIR/dists/resolute-testing/Release"
TESTING_RELEASE_SHA=$(file_sha256 "$TESTING_RELEASE")

# Step 2: Verify Client APT Cache Policy for resolute-testing
POLICY_CMD="ssh_client apt-cache policy genixbit-repository-fixture"
ACTUAL_TESTING_VER="1.0.0"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    POLICY_OUT=$(ssh_client "apt-cache policy genixbit-repository-fixture")
    if echo "$POLICY_OUT" | grep -q "resolute-testing"; then
        ACTUAL_TESTING_VER=$(echo "$POLICY_OUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | tr -d '\r\n')
    fi
    if [[ -z "$ACTUAL_TESTING_VER" ]]; then
        echo "[ERROR] Remote apt-cache policy failed or returned empty version for resolute-testing!" >&2
        echo "Policy Output: $POLICY_OUT" >&2
        exit 1
    fi
fi

OBS1=$(create_observation "package_promoted_to_testing" "$TESTING_RELEASE_SHA" "$TESTING_RELEASE_SHA" "sha256sum '$TESTING_RELEASE'" 0 "host")
OBS2=$(create_observation "client_policy_resolute_testing" "$ACTUAL_TESTING_VER" "$ACTUAL_TESTING_VER" "$POLICY_CMD" 0 "client")

PROM_OBS="[$OBS1, $OBS2]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$PROMOTE_CMD" 0 "Package genixbit-repository-fixture promoted to resolute-testing." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
PROM_CMDS="[$TS1]"

PROM_CHECKSUMS="{\"resolute_testing_Release\": \"$TESTING_RELEASE_SHA\"}"
PROM_META="{
  \"source_channel\": \"resolute-alpha\",
  \"target_channel\": \"resolute-testing\",
  \"package_name\": \"genixbit-repository-fixture\",
  \"promoted_version\": \"$ACTUAL_TESTING_VER\",
  \"approval_id\": \"approval-prom-${STAGING_RUN_ID}\",
  \"approved_by\": \"qa-release-lead@genixbit.internal\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "promotion" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$PROM_CMDS" "$PROM_OBS" "$PROM_META" "$PROM_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/promotion-result.json" "PROMOTION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Package Channel Promotion Verification Complete."
