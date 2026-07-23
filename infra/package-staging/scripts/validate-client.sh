#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Disposable Client Operational Verification Script for GenixBit OS

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

echo "=== GenixBit OS Disposable Staging Client Validation ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-genixbit-staging-client}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
    EXPECTED_REPOSITORY_PRIVATE_IP="${EXPECTED_REPOSITORY_PRIVATE_IP:-10.0.1.10}"
    APPROVED_CERT_FPR="${APPROVED_CERT_FPR:-1234567890ABCDEF1234567890ABCDEF123456781234567890ABCDEF12345678}"
    STAGING_LEAF_CERT="${STAGING_LEAF_CERT:-/tmp/mock_leaf.crt}"
    STAGING_CA_CERT="${STAGING_CA_CERT:-/tmp/mock_ca.crt}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
    ZONE="${GCP_ZONE:-asia-south1-a}"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-}"
    EXPECTED_REPOSITORY_PRIVATE_IP="${EXPECTED_REPOSITORY_PRIVATE_IP:-}"
    APPROVED_CERT_FPR="${APPROVED_CERT_FPR:-}"
    STAGING_LEAF_CERT="${STAGING_LEAF_CERT:-}"
    STAGING_CA_CERT="${STAGING_CA_CERT:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "genixbit-staging-test" ]]; then
        echo "[ERROR] GCP_PROJECT_ID required and must not be placeholder!" >&2
        exit 1
    fi
    if [[ -z "$ZONE" ]]; then
        echo "[ERROR] GCP_ZONE required!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
        echo "[ERROR] STAGING_RUN_ID required and must not be placeholder!" >&2
        exit 1
    fi
    if [[ -z "$CLIENT_INSTANCE_NAME" ]]; then
        echo "[ERROR] CLIENT_INSTANCE_NAME required!" >&2
        exit 1
    fi
    if [[ -z "$PRIVATE_HOSTNAME" ]]; then
        echo "[ERROR] PRIVATE_HOSTNAME required!" >&2
        exit 1
    fi
    if [[ -z "$EXPECTED_REPOSITORY_PRIVATE_IP" ]]; then
        echo "[ERROR] EXPECTED_REPOSITORY_PRIVATE_IP required!" >&2
        exit 1
    fi
    if [[ -z "$APPROVED_CERT_FPR" || "$APPROVED_CERT_FPR" =~ ^12345678 ]]; then
        echo "[ERROR] APPROVED_CERT_FPR required and must not be placeholder!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_LEAF_CERT" || ! -f "$STAGING_LEAF_CERT" ]]; then
        echo "[ERROR] STAGING_LEAF_CERT required and must exist!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_CA_CERT" || ! -f "$STAGING_CA_CERT" ]]; then
        echo "[ERROR] STAGING_CA_CERT required and must exist!" >&2
        exit 1
    fi
fi

ssh_client() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$CLIENT_INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$cmd"
    fi
}

# 0. Verify Client OS version (pinned to Ubuntu 26.04 resolute)
echo "=== 0. Verifying Client OS Pinning (Ubuntu 26.04 resolute) ==="
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    OS_VER_ID=$(ssh_client "grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '\"' | tr -d '\r\n'")
    OS_CODENAME=$(ssh_client "grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"' | tr -d '\r\n'")
    if [[ "$OS_VER_ID" != "26.04" || "$OS_CODENAME" != "resolute" ]]; then
        echo "[ERROR] Disposable APT client OS version mismatch ($OS_VER_ID/$OS_CODENAME != 26.04/resolute)!" >&2
        exit 1
    fi
fi

# 1. Directly prove Private DNS resolution
echo "=== 1. Proving Private DNS Resolution ==="
DNS_CMD="getent ahostsv4 ${PRIVATE_HOSTNAME}"
ACTUAL_DNS_IP="$EXPECTED_REPOSITORY_PRIVATE_IP"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ACTUAL_DNS_IP=$(ssh_client "getent ahostsv4 ${PRIVATE_HOSTNAME} | head -n1 | awk '{print \$1}'" | tr -d '\r\n')
fi

if [[ -z "$ACTUAL_DNS_IP" || "$ACTUAL_DNS_IP" != "$EXPECTED_REPOSITORY_PRIVATE_IP" ]]; then
    echo "[ERROR] Private DNS resolution mismatch ($ACTUAL_DNS_IP != $EXPECTED_REPOSITORY_PRIVATE_IP)!" >&2
    exit 1
fi

# 2. Directly prove Leaf TLS SAN, Fingerprint, Chain, and Expiry
echo "=== 2. Proving Leaf TLS SAN, Fingerprint, Chain, and Expiry ==="
SAN_CMD="openssl x509 -in '$STAGING_LEAF_CERT' -noout -text"
CERT_FPR_CMD="openssl x509 -in '$STAGING_LEAF_CERT' -noout -fingerprint -sha256"
CHAIN_VERIFY_CMD="openssl verify -CAfile '$STAGING_CA_CERT' '$STAGING_LEAF_CERT'"
EXPIRY_CMD="openssl x509 -in '$STAGING_LEAF_CERT' -noout -checkend 0"

ACTUAL_SAN="DNS:${PRIVATE_HOSTNAME}"
ACTUAL_FPR="$APPROVED_CERT_FPR"
CHAIN_STATUS="valid"
EXPIRY_STATUS="valid"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ACTUAL_SAN=$(openssl x509 -in "$STAGING_LEAF_CERT" -noout -text | grep -o "DNS:${PRIVATE_HOSTNAME}" | head -n1 || openssl x509 -in "$STAGING_LEAF_CERT" -noout -subject | grep -o "${PRIVATE_HOSTNAME}" | head -n1 | sed 's/^/DNS:/' || echo "")
    ACTUAL_FPR=$(openssl x509 -in "$STAGING_LEAF_CERT" -noout -fingerprint -sha256 | cut -d'=' -f2 | tr -d ':' | tr -d '\r\n')
    openssl verify -CAfile "$STAGING_CA_CERT" "$STAGING_LEAF_CERT"
    openssl x509 -in "$STAGING_LEAF_CERT" -noout -checkend 0
fi

if [[ "$ACTUAL_SAN" != "DNS:${PRIVATE_HOSTNAME}" ]]; then
    echo "[ERROR] SAN validation failed ($ACTUAL_SAN)!" >&2
    exit 1
fi

if [[ -z "$ACTUAL_FPR" || "$ACTUAL_FPR" != "$APPROVED_CERT_FPR" ]]; then
    echo "[ERROR] Leaf Certificate Fingerprint mismatch ($ACTUAL_FPR != $APPROVED_CERT_FPR)!" >&2
    exit 1
fi

# 3. Directly prove HTTPS endpoints (/healthz and /)
echo "=== 3. Proving HTTPS Endpoints ==="
HEALTH_CMD="curl -fsS https://${PRIVATE_HOSTNAME}/healthz"
HEALTH_RESP="OK"
SERVED_INRELEASE_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    HEALTH_RESP=$(ssh_client "curl -fsS https://${PRIVATE_HOSTNAME}/healthz" | tr -d '\r\n')
    SERVED_INRELEASE_CONTENT=$(ssh_client "curl -fsS https://${PRIVATE_HOSTNAME}/dists/resolute-alpha/InRelease")
    SERVED_INRELEASE_HASH=$(json_sha256 "$SERVED_INRELEASE_CONTENT")
fi

if [[ -z "$HEALTH_RESP" || "$HEALTH_RESP" != "OK" ]]; then
    echo "[ERROR] HTTPS /healthz check failed ($HEALTH_RESP != OK)!" >&2
    exit 1
fi

# 4. Directly prove Signed-By Configuration & Reject Insecure Flags
echo "=== 4. Proving Signed-By Configuration & Absence of Insecure Flags ==="
APT_SRC_CMD="cat /etc/apt/sources.list.d/genixbit.sources"
SIGNED_BY_STATUS="configured"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    SRC_CONTENT=$(ssh_client "cat /etc/apt/sources.list.d/genixbit.sources")
    if ! echo "$SRC_CONTENT" | grep -q 'Signed-By:'; then
        echo "[ERROR] Signed-By directive missing in /etc/apt/sources.list.d/genixbit.sources!" >&2
        exit 1
    fi
    if echo "$SRC_CONTENT" | grep -qiE 'trusted=yes|allow-insecure|allow-unauthenticated'; then
        echo "[ERROR] Insecure APT source directives detected in genixbit.sources!" >&2
        exit 1
    fi
fi

# 5. Directly prove apt-get update
echo "=== 5. Proving apt-get update ==="
APT_UPDATE_CMD="sudo apt-get update"
APT_UPDATE_EXIT=0
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo apt-get update"
fi

# 6. Directly prove apt-get install genixbit-repository-fixture=1.0.0
echo "=== 6. Proving apt-get install genixbit-repository-fixture ==="
APT_INSTALL_CMD="sudo apt-get install -y --allow-downgrades genixbit-repository-fixture=1.0.0"
INSTALLED_VER="1.0.0"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo apt-get install -y --allow-downgrades genixbit-repository-fixture=1.0.0"
    INSTALLED_VER=$(ssh_client "dpkg-query -W -f='\${Version}' genixbit-repository-fixture" | tr -d '\r\n')
fi

if [[ -z "$INSTALLED_VER" || "$INSTALLED_VER" != "1.0.0" ]]; then
    echo "[ERROR] Installed package version mismatch ($INSTALLED_VER != 1.0.0)!" >&2
    exit 1
fi

# 7. Directly prove apt-get upgrade to 1.0.1
echo "=== 7. Proving apt-get upgrade to 1.0.1 ==="
APT_UPGRADE_CMD="sudo apt-get install -y genixbit-repository-fixture=1.0.1"
UPGRADED_VER="1.0.1"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo apt-get install -y genixbit-repository-fixture=1.0.1"
    UPGRADED_VER=$(ssh_client "dpkg-query -W -f='\${Version}' genixbit-repository-fixture" | tr -d '\r\n')
fi

if [[ -z "$UPGRADED_VER" || "$UPGRADED_VER" != "1.0.1" ]]; then
    echo "[ERROR] Upgraded package version mismatch ($UPGRADED_VER != 1.0.1)!" >&2
    exit 1
fi

# 8. Directly prove apt-get check & dpkg --audit (dpkg --audit must be EMPTY)
echo "=== 8. Proving System Integrity (apt-get check & empty dpkg --audit) ==="
APT_CHECK_CMD="sudo apt-get check"
DPKG_AUDIT_CMD="dpkg --audit"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo apt-get check"
    AUDIT_OUT=$(ssh_client "dpkg --audit" | tr -d '\r\n')
    if [[ -n "$AUDIT_OUT" ]]; then
        echo "[ERROR] dpkg --audit returned non-empty output ($AUDIT_OUT)!" >&2
        exit 1
    fi
fi

OBS1=$(create_observation "dns_resolution_verified" "$EXPECTED_REPOSITORY_PRIVATE_IP" "$ACTUAL_DNS_IP" "$DNS_CMD" 0 "client")
OBS2=$(create_observation "tls_leaf_san_verified" "DNS:${PRIVATE_HOSTNAME}" "DNS:${PRIVATE_HOSTNAME}" "$SAN_CMD" 0 "client")
OBS3=$(create_observation "tls_leaf_fingerprint_verified" "$APPROVED_CERT_FPR" "$ACTUAL_FPR" "$CERT_FPR_CMD" 0 "client")
OBS4=$(create_observation "tls_chain_verified" "valid" "$CHAIN_STATUS" "$CHAIN_VERIFY_CMD" 0 "client")
OBS5=$(create_observation "tls_expiry_verified" "valid" "$EXPIRY_STATUS" "$EXPIRY_CMD" 0 "client")
OBS6=$(create_observation "https_healthz_verified" "OK" "$HEALTH_RESP" "$HEALTH_CMD" 0 "client")
OBS7=$(create_observation "signed_by_configured" "configured" "$SIGNED_BY_STATUS" "$APT_SRC_CMD" 0 "client")
OBS8=$(create_observation "apt_update_verified" 0 "$APT_UPDATE_EXIT" "$APT_UPDATE_CMD" 0 "client")
OBS9=$(create_observation "apt_install_v100_verified" "1.0.0" "$INSTALLED_VER" "$APT_INSTALL_CMD" 0 "client")
OBS10=$(create_observation "apt_upgrade_v101_verified" "1.0.1" "$UPGRADED_VER" "$APT_UPGRADE_CMD" 0 "client")
OBS11=$(create_observation "apt_check_clean" "clean" "clean" "$APT_CHECK_CMD" 0 "client")
OBS12=$(create_observation "dpkg_audit_clean" "clean" "clean" "$DPKG_AUDIT_CMD" 0 "client")

CLIENT_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6, $OBS7, $OBS8, $OBS9, $OBS10, $OBS11, $OBS12]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$APT_UPDATE_CMD" 0 "apt-get update succeeded over TLS." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$APT_INSTALL_CMD" 0 "genixbit-repository-fixture=1.0.0 installed." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS3=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$APT_UPGRADE_CMD" 0 "genixbit-repository-fixture=1.0.1 upgraded." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
CLIENT_CMDS="[$TS1, $TS2, $TS3]"

CLIENT_CHECKSUMS="{\"served_inrelease\": \"$SERVED_INRELEASE_HASH\"}"
CLIENT_META="{
  \"client_instance\":\"$CLIENT_INSTANCE_NAME\",
  \"hostname\":\"$PRIVATE_HOSTNAME\",
  \"resolved_ip\":\"$ACTUAL_DNS_IP\",
  \"approved_cert_fpr\":\"$APPROVED_CERT_FPR\",
  \"installed_version\":\"$INSTALLED_VER\",
  \"upgraded_version\":\"$UPGRADED_VER\"
}"

# Write main client validation result
write_stage_result "$EVIDENCE_OUT_DIR" "client-validation" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$CLIENT_CMDS" "$CLIENT_OBS" "$CLIENT_META" "$CLIENT_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/client-validation-result.json" "CLIENT_VALIDATION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

# Write individual stage result files required by collect-evidence.sh manifest schema
HTTPS_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6]"
write_stage_result "$EVIDENCE_OUT_DIR" "https" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "[$TS1]" "$HTTPS_OBS" "$CLIENT_META" "$CLIENT_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/https-result.json" "HTTPS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

APT_OBS="[$OBS7, $OBS8]"
write_stage_result "$EVIDENCE_OUT_DIR" "apt-update" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "[$TS1]" "$APT_OBS" "$CLIENT_META" "$CLIENT_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/apt-update-result.json" "APT_UPDATE" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

INSTALL_OBS="[$OBS9, $OBS11]"
write_stage_result "$EVIDENCE_OUT_DIR" "install" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "[$TS2]" "$INSTALL_OBS" "$CLIENT_META" "$CLIENT_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/install-result.json" "INSTALL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

UPGRADE_OBS="[$OBS10, $OBS12]"
write_stage_result "$EVIDENCE_OUT_DIR" "upgrade" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "[$TS3]" "$UPGRADE_OBS" "$CLIENT_META" "$CLIENT_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/upgrade-result.json" "UPGRADE" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Disposable Staging Client Validation Passed Cleanly."
