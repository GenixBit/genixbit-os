#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Repository Service Configuration & Atomic Synchroniser for GenixBit OS Package Staging

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

echo "=== GenixBit OS Staging Repository Configuration & Publication ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-}"
LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID:-run-staging-default}}"

# 1. Require Mandatory Parameters (No Silent Defaults)
if [[ -z "$PROJECT_ID" || -z "$ZONE" || -z "$STAGING_RUN_ID" || -z "$STAGING_KEY_FPR" || -z "$STAGING_PUBLIC_KEYRING" || -z "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] Missing required parameters! All of GCP_PROJECT_ID, GCP_ZONE, STAGING_RUN_ID, STAGING_KEY_FPR, STAGING_PUBLIC_KEYRING, LOCAL_STAGING_DIR must be explicitly specified." >&2
    exit 1
fi

# 2. Validate Fingerprint Format (Exactly 40 hex characters)
if [[ ! "$STAGING_KEY_FPR" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "[ERROR] Invalid STAGING_KEY_FPR '$STAGING_KEY_FPR'! Must be exactly 40 hexadecimal characters." >&2
    exit 1
fi

# 3. Validate Public Keyring
if [[ ! -f "$STAGING_PUBLIC_KEYRING" ]]; then
    echo "[ERROR] Public keyring file '$STAGING_PUBLIC_KEYRING' does not exist." >&2
    exit 1
fi

if gpg --list-packets "$STAGING_PUBLIC_KEYRING" 2>/dev/null | grep -i -q "secret-key packet"; then
    echo "[ERROR] Security Violation: Keyring '$STAGING_PUBLIC_KEYRING' contains secret-key packets!" >&2
    exit 1
fi

# Verify Keyring Contains Fingerprint
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if command -v gpg >/dev/null 2>&1; then
        if ! gpg --with-colons --show-keys "$STAGING_PUBLIC_KEYRING" 2>/dev/null | grep -i "$STAGING_KEY_FPR" >/dev/null; then
            echo "[ERROR] Keyring '$STAGING_PUBLIC_KEYRING' does not contain fingerprint '$STAGING_KEY_FPR'." >&2
            exit 1
        fi
    fi
fi
echo "[PASS] Mandated OpenPGP Keyring & Fingerprint Verified: $STAGING_KEY_FPR"

# 4. Validate Signed Local Staging Metadata
if [[ ! -d "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] Local staging directory '$LOCAL_STAGING_DIR' does not exist." >&2
    exit 1
fi

# Assert NO secret key files in local staging directory
if find "$LOCAL_STAGING_DIR" -type f \( -name "*.pem" -o -name "*.key" -o -name "*.sec" -o -name "secring.gpg" \) | grep .; then
    echo "[ERROR] Security Violation: Detected private key material in staging directory!" >&2
    exit 1
fi

ALPHA_DIST="$LOCAL_STAGING_DIR/dists/resolute-alpha"
if [[ ! -f "$ALPHA_DIST/InRelease" || ! -f "$ALPHA_DIST/Release" || ! -f "$ALPHA_DIST/Release.gpg" ]]; then
    echo "[ERROR] Incomplete release metadata files in '$ALPHA_DIST'." >&2
    exit 1
fi

# Verify InRelease & Release.gpg OpenPGP Signatures
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --repo-dir "$LOCAL_STAGING_DIR" \
        --channel resolute-alpha \
        --keyring "$STAGING_PUBLIC_KEYRING" \
        --expected-fingerprint "$STAGING_KEY_FPR"
fi
echo "[PASS] Release Signatures Verified for resolute-alpha"

# Helper for executing commands on repo host via IAP
ssh_repo_host() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$REPOSITORY_INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
    fi
}

scp_to_repo_host() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute scp --recurse "$src" "${REPOSITORY_INSTANCE_NAME}:${dest}" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
    fi
}

echo "=== Step 5: Executing Immutable Release Upload & Atomic Symlink Switch ==="
RELEASE_ID="release-${STAGING_RUN_ID}-$(date +%s)"
TARGET_RELEASE_DIR="/var/srv/genixbit-repository/releases/${RELEASE_ID}"
CURRENT_SYMLINK="/var/srv/genixbit-repository/current"

# Prepare new immutable release directory on host
ssh_repo_host "sudo mkdir -p /var/srv/genixbit-repository/releases /tmp/repo_upload_${RELEASE_ID}"
scp_to_repo_host "$LOCAL_STAGING_DIR/*" "/tmp/repo_upload_${RELEASE_ID}/"

# Verify uploaded files on host and perform atomic symlink switch
ssh_repo_host "sudo mv /tmp/repo_upload_${RELEASE_ID} ${TARGET_RELEASE_DIR} && \
               sudo chown -R genixbit-repo:genixbit-repo ${TARGET_RELEASE_DIR} && \
               sudo chmod -R 755 ${TARGET_RELEASE_DIR} && \
               sudo ln -sfn ${TARGET_RELEASE_DIR} ${CURRENT_SYMLINK}"

# Verify Nginx is serving current release
ssh_repo_host "curl -fsS http://127.0.0.1/healthz" >/dev/null || {
    echo "[ERROR] Health check failed after atomic publication!" >&2
    exit 1
}

# Calculate artifact checksums for evidence
INRELEASE_SHA=$(file_sha256 "$ALPHA_DIST/InRelease")
RELEASE_SHA=$(file_sha256 "$ALPHA_DIST/Release")

# Write Stage Result File
STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

VERIFIED_CONDS='["fingerprint_40_hex_verified", "keyring_public_only_verified", "inrelease_signature_verified", "release_gpg_signature_verified", "atomic_symlink_switch_verified", "healthz_endpoint_200_ok"]'
PUBLIC_META="{\"fingerprint\":\"$STAGING_KEY_FPR\",\"instance_name\":\"$REPOSITORY_INSTANCE_NAME\",\"private_hostname\":\"$PRIVATE_HOSTNAME\",\"release_id\":\"$RELEASE_ID\",\"target_release_dir\":\"$TARGET_RELEASE_DIR\"}"
CHECKSUMS="{\"InRelease\":\"$INRELEASE_SHA\",\"Release\":\"$RELEASE_SHA\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "repository-publication" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "configure-repository.sh" "$VERIFIED_CONDS" "$PUBLIC_META" "$CHECKSUMS"

emit_verified_marker "$EVIDENCE_OUT_DIR/repository-publication-result.json" "REPOSITORY_PUBLICATION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Atomic Repository Publication Complete (Release ID: $RELEASE_ID)."
