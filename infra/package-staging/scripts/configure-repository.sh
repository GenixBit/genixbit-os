#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Repository Service Configuration & Synchroniser for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$INFRA_DIR/.." && pwd)

echo "=== GenixBit OS Staging Repository Configuration & Publication ==="

PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
ZONE="${GCP_ZONE:-asia-south1-a}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260722-001}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-/tmp/genixbit-staging-pub-${STAGING_RUN_ID}}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == --* ]]; then
    echo "[ERROR] GCP Project ID is required as first parameter or GCP_PROJECT_ID." >&2
    exit 1
fi

INSTANCE_NAME="genixbit-staging-repo-host"
PRIVATE_HOSTNAME="staging-packages.genixbit.internal"
echo "[INFO] Target Private Hostname: $PRIVATE_HOSTNAME"

# Helper for executing commands on repo host via IAP
ssh_repo_host() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
    fi
}

scp_to_repo_host() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute scp --recurse "$src" "${INSTANCE_NAME}:${dest}" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
    fi
}

echo "=== Step 1: Verifying Repository Host Identity & Bootstrap Status ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    # Verify Instance Status & Private IP
    REPO_IP=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(networkInterfaces[0].networkIP)")
    if [[ -z "$REPO_IP" ]]; then
        echo "[ERROR] Repository Host instance '$INSTANCE_NAME' not found or missing private IP." >&2
        exit 1
    fi
    echo "[PASS] Verified Repo Host Private IP: $REPO_IP"
fi

# Verify Startup Bootstrap
ssh_repo_host "test -d /var/srv/genixbit-repository && systemctl is-active --quiet nginx" || {
    echo "[ERROR] Repository Host bootstrap incomplete or Nginx is not running!" >&2
    exit 1
}
echo "[PASS] Bootstrap Directory & Nginx Service Active"

# Verify Nginx Health Endpoint
ssh_repo_host "curl -fsS http://127.0.0.1/healthz" >/dev/null || {
    echo "[ERROR] Health endpoint http://127.0.0.1/healthz failed!" >&2
    exit 1
}
echo "[PASS] Nginx Health Endpoint Verified (200 OK)"

echo "=== Step 2: Verifying Local Signed Repository Package Artifacts ==="
if [[ ! -d "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] Local staging repository directory '$LOCAL_STAGING_DIR' does not exist." >&2
    echo "Generate and sign staging release metadata locally before running configuration." >&2
    exit 1
fi

# Assert NO private keys in local staging directory
if find "$LOCAL_STAGING_DIR" -type f \( -name "*.pem" -o -name "*.key" -o -name "*.sec" -o -name "secring.gpg" \) | grep .; then
    echo "[ERROR] Security Violation: Detected private key material in staging directory!" >&2
    exit 1
fi

# Verify Required Metadata Files
ALPHA_DIST="$LOCAL_STAGING_DIR/dists/resolute-alpha"
if [[ ! -f "$ALPHA_DIST/main/binary-amd64/Packages" ]] || \
   [[ ! -f "$ALPHA_DIST/main/binary-amd64/Packages.gz" ]] || \
   [[ ! -f "$ALPHA_DIST/main/binary-amd64/Packages.xz" ]] || \
   [[ ! -f "$ALPHA_DIST/Release" ]] || \
   [[ ! -f "$ALPHA_DIST/InRelease" ]] || \
   [[ ! -f "$ALPHA_DIST/Release.gpg" ]]; then
    echo "[ERROR] Staging metadata files incomplete in '$ALPHA_DIST'." >&2
    echo "Required: Packages, Packages.gz, Packages.xz, Release, InRelease, Release.gpg" >&2
    exit 1
fi
echo "[PASS] Signed Staging Release Metadata Complete"

# Verify OpenPGP Signature with Expected Key Fingerprint
if [[ -n "$STAGING_KEY_FPR" ]]; then
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --repo-dir "$LOCAL_STAGING_DIR" \
        --channel resolute-alpha \
        --keyring "$LOCAL_STAGING_DIR/usr/share/keyrings/genixbit-os-archive-keyring.gpg" \
        --expected-fingerprint "$STAGING_KEY_FPR"
    echo "[PASS] OpenPGP Signature Verified against Fingerprint: $STAGING_KEY_FPR"
fi

echo "=== Step 3: Synchronizing Staging Content Atomically to Host ==="
# Transfer content to temporary staging directory on host
ssh_repo_host "mkdir -p /tmp/repo_sync_tmp"
scp_to_repo_host "$LOCAL_STAGING_DIR/*" "/tmp/repo_sync_tmp/"

# Atomic move and permission hardening on repo host
ssh_repo_host "sudo cp -r /tmp/repo_sync_tmp/* /var/srv/genixbit-repository/ && \
               sudo chown -R genixbit-repo:genixbit-repo /var/srv/genixbit-repository && \
               sudo chmod -R 755 /var/srv/genixbit-repository && \
               rm -rf /tmp/repo_sync_tmp"

echo "=== Step 4: Verifying Remote Host Repository Serving ==="
ssh_repo_host "curl -fsS http://127.0.0.1/dists/resolute-alpha/InRelease" >/dev/null || {
    echo "[ERROR] Remote verification failed: InRelease metadata unreachable via Nginx." >&2
    exit 1
}

echo "[PASS] Staging Repository Host Configuration & Publication Complete."
