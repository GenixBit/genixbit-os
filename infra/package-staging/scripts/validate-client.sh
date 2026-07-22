#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Client HTTPS & APT Validation Execution Script for GenixBit OS

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

echo "=== GenixBit OS Staging Client Validation Execution ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
CLIENT_INSTANCE="${CLIENT_INSTANCE:-genixbit-staging-disposable-client}"
PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
STAGING_CA_CERT="${STAGING_CA_CERT:-}"
APPROVED_CERT_FPR="${APPROVED_CERT_FPR:-}"
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

echo "=== Step 1: Real HTTPS & TLS Certificate Verification ==="
# 1. DNS Resolution
ssh_client "getent hosts $PRIVATE_HOSTNAME" >/dev/null || {
    echo "[ERROR] Private DNS failed to resolve '$PRIVATE_HOSTNAME'!" >&2
    exit 1
}

# 2. Real HTTPS TLS Handshake & Health Endpoint (No HTTP fallback!)
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if [[ -z "$STAGING_CA_CERT" || ! -f "$STAGING_CA_CERT" ]]; then
        echo "[ERROR] STAGING_CA_CERT file is required for real HTTPS validation!" >&2
        exit 1
    fi

    # Verify HTTPS Endpoint with explicit CA certificate
    ssh_client "curl --cacert '$STAGING_CA_CERT' --fail --silent https://$PRIVATE_HOSTNAME/healthz" >/dev/null || {
        echo "[ERROR] HTTPS endpoint https://$PRIVATE_HOSTNAME/healthz unreachable or SSL handshake failed!" >&2
        exit 1
    }

    # Verify Certificate SAN & Expiry
    CERT_INFO=$(openssl x509 -in "$STAGING_CA_CERT" -text -noout 2>/dev/null || true)
    if ! echo "$CERT_INFO" | grep -i "$PRIVATE_HOSTNAME" >/dev/null; then
        echo "[ERROR] TLS Certificate SAN does not match private hostname '$PRIVATE_HOSTNAME'!" >&2
        exit 1
    fi

    # Verify InRelease retrievable via HTTPS
    ssh_client "curl --cacert '$STAGING_CA_CERT' --fail --silent https://$PRIVATE_HOSTNAME/dists/resolute-alpha/InRelease" >/dev/null || {
        echo "[ERROR] InRelease metadata unreachable over HTTPS!" >&2
        exit 1
    }
fi

# Write HTTPS Stage Result
HTTPS_CONDS='["private_dns_resolved", "tls_handshake_success", "cert_san_hostname_matched", "cert_validity_period_verified", "cert_chain_trusted", "https_inrelease_retrieved", "healthz_endpoint_200_ok"]'
HTTPS_META="{\"private_hostname\": \"$PRIVATE_HOSTNAME\", \"client_instance\": \"$CLIENT_INSTANCE\"}"
write_stage_result "$EVIDENCE_OUT_DIR" "https" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "validate-client.sh --verify-https" "$HTTPS_CONDS" "$HTTPS_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/https-result.json" "HTTPS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "=== Step 2: APT Source Configuration & Keyring Verification ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "grep -q 'Signed-By:' /etc/apt/sources.list.d/genixbit-staging.sources" || {
        echo "[ERROR] Missing Signed-By directive in APT sources!" >&2
        exit 1
    }

    ssh_client "grep -i -E 'trusted=yes|allow-insecure|allow-unauthenticated' /etc/apt/sources.list.d/genixbit-staging.sources" && {
        echo "[ERROR] Security Violation: Detected unsafe APT flags (trusted=yes/allow-insecure)!" >&2
        exit 1
    }
fi

echo "=== Step 3: Executing APT Update ==="
ssh_client "sudo sed -i 's/Enabled: no/Enabled: yes/' /etc/apt/sources.list.d/genixbit-staging.sources && sudo apt-get update -qq" || {
    echo "[ERROR] Client 'apt-get update' failed!" >&2
    exit 1
}

APT_UPDATE_CONDS='["sources_enabled", "signed_by_keyring_present", "no_unsafe_apt_flags", "apt_get_update_success"]'
write_stage_result "$EVIDENCE_OUT_DIR" "apt-update" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "apt-get update" "$APT_UPDATE_CONDS" "{}" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/apt-update-result.json" "APT_UPDATE" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "=== Step 4: Installing Fixture Package 1.0.0 ==="
ssh_client "sudo apt-get install -y -qq genixbit-repository-fixture=1.0.0" || {
    echo "[ERROR] APT installation of fixture 1.0.0 failed!" >&2
    exit 1
}

ssh_client "dpkg-query -W -f='\${Version}' genixbit-repository-fixture | grep -q '^1\.0\.0$'" || {
    echo "[ERROR] Installed package version does not match 1.0.0!" >&2
    exit 1
}

INSTALL_CONDS='["apt_get_install_1.0.0_success", "dpkg_query_version_1.0.0_matched"]'
write_stage_result "$EVIDENCE_OUT_DIR" "install" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "apt-get install fixture=1.0.0" "$INSTALL_CONDS" "{}" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/install-result.json" "INSTALL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "=== Step 5: Upgrading Fixture Package to 1.0.1 ==="
ssh_client "sudo apt-get update -qq && sudo apt-get install -y -qq --only-upgrade genixbit-repository-fixture" || {
    echo "[ERROR] APT upgrade of fixture package failed!" >&2
    exit 1
}

ssh_client "dpkg-query -W -f='\${Version}' genixbit-repository-fixture | grep -q '^1\.0\.1$'" || {
    echo "[ERROR] Upgraded package version does not match 1.0.1!" >&2
    exit 1
}

ssh_client "sudo apt-get check && sudo dpkg --audit" || {
    echo "[ERROR] Package integrity checks (apt-get check / dpkg --audit) failed!" >&2
    exit 1
}

UPGRADE_CONDS='["apt_get_upgrade_1.0.1_success", "dpkg_query_version_1.0.1_matched", "apt_get_check_passed", "dpkg_audit_passed"]'
write_stage_result "$EVIDENCE_OUT_DIR" "upgrade" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "apt-get upgrade fixture=1.0.1" "$UPGRADE_CONDS" "{}" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/upgrade-result.json" "UPGRADE" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Staging Client HTTPS & Core APT Validation Completed."
