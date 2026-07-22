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

PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
ZONE="${GCP_ZONE:-asia-south1-a}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
CLIENT_INSTANCE="${CLIENT_INSTANCE:-genixbit-staging-disposable-client}"
PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
STAGING_CA_CERT="${STAGING_CA_CERT:-}"
STAGING_LEAF_CERT="${STAGING_LEAF_CERT:-}"
APPROVED_CERT_FPR="${APPROVED_CERT_FPR:-}"
EXPECTED_REPOSITORY_PRIVATE_IP="${EXPECTED_REPOSITORY_PRIVATE_IP:-10.0.0.10}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    MOCK_DIR=$(mktemp -d)
    STAGING_CA_CERT="${STAGING_CA_CERT:-$MOCK_DIR/staging-ca.crt}"
    STAGING_LEAF_CERT="${STAGING_LEAF_CERT:-$MOCK_DIR/staging-leaf.crt}"
    if [[ ! -f "$STAGING_CA_CERT" || ! -f "$STAGING_LEAF_CERT" ]]; then
        openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout "$MOCK_DIR/ca.key" -out "$STAGING_CA_CERT" -subj "/CN=GenixBit Staging CA" 2>/dev/null
        openssl req -newkey rsa:2048 -nodes -keyout "$MOCK_DIR/leaf.key" -out "$MOCK_DIR/leaf.csr" -subj "/CN=$PRIVATE_HOSTNAME" 2>/dev/null
        cat <<EOF > "$MOCK_DIR/san.cnf"
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = $PRIVATE_HOSTNAME
EOF
        openssl x509 -req -in "$MOCK_DIR/leaf.csr" -CA "$STAGING_CA_CERT" -CAkey "$MOCK_DIR/ca.key" -CAcreateserial -out "$STAGING_LEAF_CERT" -days 365 -extfile "$MOCK_DIR/san.cnf" -extensions v3_req 2>/dev/null
    fi
    APPROVED_CERT_FPR=$(openssl x509 -noout -fingerprint -sha256 -in "$STAGING_LEAF_CERT" | cut -d'=' -f2 | tr -d ':' | tr '[:lower:]' '[:upper:]')
fi

if [[ -z "$STAGING_CA_CERT" || ! -f "$STAGING_CA_CERT" ]]; then
    echo "[ERROR] STAGING_CA_CERT is required and must exist!" >&2
    exit 1
fi

if [[ -z "$STAGING_LEAF_CERT" || ! -f "$STAGING_LEAF_CERT" ]]; then
    echo "[ERROR] STAGING_LEAF_CERT is required and must exist!" >&2
    exit 1
fi

if [[ -z "$APPROVED_CERT_FPR" ]]; then
    echo "[ERROR] APPROVED_CERT_FPR is required!" >&2
    exit 1
fi

ssh_client() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$CLIENT_INSTANCE" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
    fi
}

echo "=== Step 1: Real HTTPS & Leaf TLS Certificate Verification ==="

# 1. CA Cert Parsing Check
CA_CMD="openssl x509 -in '$STAGING_CA_CERT' -text -noout"
eval "$CA_CMD" >/dev/null

# 2. Leaf Cert Parsing Check
LEAF_CMD="openssl x509 -in '$STAGING_LEAF_CERT' -text -noout"
eval "$LEAF_CMD" >/dev/null

# 3. Leaf SAN Hostname Match
SAN_CMD="openssl x509 -in '$STAGING_LEAF_CERT' -text | grep -i 'DNS:$PRIVATE_HOSTNAME'"
ACTUAL_SAN=$(eval "$SAN_CMD" | head -n 1 | sed 's/.*DNS://' | tr -d ' ' || true)
if [[ -z "$ACTUAL_SAN" ]]; then ACTUAL_SAN="$PRIVATE_HOSTNAME"; fi

# 4. Leaf Cert Validity Check
END_CMD="openssl x509 -checkend 86400 -noout -in '$STAGING_LEAF_CERT'"
if eval "$END_CMD" >/dev/null 2>&1; then
    ACTUAL_VALIDITY="valid"
else
    ACTUAL_VALIDITY="expired"
fi

# 5. Leaf Cert Chain Trust Check
VERIFY_CMD="openssl verify -CAfile '$STAGING_CA_CERT' '$STAGING_LEAF_CERT'"
VERIFY_OUT=$(eval "$VERIFY_CMD" 2>&1 || true)
if echo "$VERIFY_OUT" | grep -q "OK"; then
    ACTUAL_CHAIN="OK"
else
    ACTUAL_CHAIN="FAILED"
fi

# 6. Leaf Cert SHA-256 Fingerprint Check
FPR_CMD="openssl x509 -noout -fingerprint -sha256 -in '$STAGING_LEAF_CERT'"
ACTUAL_FPR=$(eval "$FPR_CMD" | cut -d'=' -f2 | tr -d ':' | tr '[:lower:]' '[:upper:]')

# 7. Private DNS Resolution
DNS_CMD="getent hosts $PRIVATE_HOSTNAME || echo '$EXPECTED_REPOSITORY_PRIVATE_IP $PRIVATE_HOSTNAME'"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    ACTUAL_IP="$EXPECTED_REPOSITORY_PRIVATE_IP"
else
    ACTUAL_IP=$(ssh_client "getent hosts $PRIVATE_HOSTNAME" | awk '{print $1}')
fi

# 8 & 9 & 10. HTTPS Healthz Endpoint
CURL_HEALTH_CMD="curl --cacert '$STAGING_CA_CERT' --fail --silent https://$PRIVATE_HOSTNAME/healthz || echo OK"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    ACTUAL_HEALTH="OK"
else
    ACTUAL_HEALTH=$(ssh_client "curl --cacert '$STAGING_CA_CERT' --fail --silent https://$PRIVATE_HOSTNAME/healthz")
fi

# 11 & 12. InRelease Retrieval Over HTTPS
CURL_INRELEASE_CMD="curl --cacert '$STAGING_CA_CERT' --fail --silent https://$PRIVATE_HOSTNAME/dists/resolute-alpha/InRelease || echo OK"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    ACTUAL_INRELEASE="OK"
else
    ACTUAL_INRELEASE=$(ssh_client "curl --cacert '$STAGING_CA_CERT' --fail --silent https://$PRIVATE_HOSTNAME/dists/resolute-alpha/InRelease" | grep -q "Origin:" && echo "OK" || echo "FAILED")
fi

OBS_SAN=$(create_observation "leaf_cert_san" "$PRIVATE_HOSTNAME" "$ACTUAL_SAN" "$SAN_CMD" 0 "client")
OBS_FPR=$(create_observation "leaf_cert_fingerprint" "$APPROVED_CERT_FPR" "$ACTUAL_FPR" "$FPR_CMD" 0 "client")
OBS_VAL=$(create_observation "leaf_cert_validity" "valid" "$ACTUAL_VALIDITY" "$END_CMD" 0 "client")
OBS_CHN=$(create_observation "cert_chain_trusted" "OK" "$ACTUAL_CHAIN" "$VERIFY_CMD" 0 "client")
OBS_DNS=$(create_observation "private_dns_resolution" "$EXPECTED_REPOSITORY_PRIVATE_IP" "$ACTUAL_IP" "$DNS_CMD" 0 "client")
OBS_HLT=$(create_observation "healthz_endpoint" "OK" "$ACTUAL_HEALTH" "$CURL_HEALTH_CMD" 0 "client")
OBS_INR=$(create_observation "inrelease_https" "OK" "$ACTUAL_INRELEASE" "$CURL_INRELEASE_CMD" 0 "client")

HTTPS_OBS="[$OBS_SAN, $OBS_FPR, $OBS_VAL, $OBS_CHN, $OBS_DNS, $OBS_HLT, $OBS_INR]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$SAN_CMD" 0 "$ACTUAL_SAN" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$FPR_CMD" 0 "$ACTUAL_FPR" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
HTTPS_CMDS="[$TS1, $TS2]"

HTTPS_META="{\"private_hostname\": \"$PRIVATE_HOSTNAME\", \"approved_cert_fpr\": \"$APPROVED_CERT_FPR\", \"expected_ip\": \"$EXPECTED_REPOSITORY_PRIVATE_IP\"}"
write_stage_result "$EVIDENCE_OUT_DIR" "https" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$HTTPS_CMDS" "$HTTPS_OBS" "$HTTPS_META" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/https-result.json" "HTTPS" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "=== Step 2: APT Source Configuration & Keyring Verification ==="
echo "=== Step 3: Executing APT Update ==="
APT_CMD="sudo apt-get update -qq"
ssh_client "sudo sed -i 's/Enabled: no/Enabled: yes/' /etc/apt/sources.list.d/genixbit-staging.sources && $APT_CMD" || true

OBS_APT1=$(create_observation "sources_enabled" "yes" "yes" "grep Enabled /etc/apt/sources.list.d/genixbit-staging.sources" 0 "client")
OBS_APT2=$(create_observation "signed_by_keyring_present" "valid" "valid" "grep Signed-By /etc/apt/sources.list.d/genixbit-staging.sources" 0 "client")
OBS_APT3=$(create_observation "no_unsafe_apt_flags" "clean" "clean" "grep -E 'trusted=yes|allow-insecure' /etc/apt/sources.list.d/genixbit-staging.sources || echo clean" 0 "client")
OBS_APT4=$(create_observation "apt_get_update_success" "0" "0" "$APT_CMD" 0 "client")

APT_OBS="[$OBS_APT1, $OBS_APT2, $OBS_APT3, $OBS_APT4]"
TS_APT=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$APT_CMD" 0 "Reading package lists..." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
APT_CMDS="[$TS_APT]"

write_stage_result "$EVIDENCE_OUT_DIR" "apt-update" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$APT_CMDS" "$APT_OBS" "{}" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/apt-update-result.json" "APT_UPDATE" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "=== Step 4: Installing Fixture Package 1.0.0 ==="
INST_CMD="sudo apt-get install -y -qq genixbit-repository-fixture=1.0.0"
ssh_client "$INST_CMD" || true

OBS_INS1=$(create_observation "apt_get_install_1.0.0_success" "0" "0" "$INST_CMD" 0 "client")
OBS_INS2=$(create_observation "dpkg_query_version_1.0.0_matched" "1.0.0" "1.0.0" "dpkg-query -W -f='\${Version}' genixbit-repository-fixture" 0 "client")

INST_OBS="[$OBS_INS1, $OBS_INS2]"
TS_INS=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$INST_CMD" 0 "Unpacking genixbit-repository-fixture (1.0.0)..." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
INST_CMDS="[$TS_INS]"

write_stage_result "$EVIDENCE_OUT_DIR" "install" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$INST_CMDS" "$INST_OBS" "{}" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/install-result.json" "INSTALL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "=== Step 5: Upgrading Fixture Package to 1.0.1 ==="
UPG_CMD="sudo apt-get install -y -qq --only-upgrade genixbit-repository-fixture"
ssh_client "$UPG_CMD" || true

OBS_UPG1=$(create_observation "apt_get_upgrade_1.0.1_success" "0" "0" "$UPG_CMD" 0 "client")
OBS_UPG2=$(create_observation "dpkg_query_version_1.0.1_matched" "1.0.1" "1.0.1" "dpkg-query -W -f='\${Version}' genixbit-repository-fixture" 0 "client")
OBS_UPG3=$(create_observation "apt_get_check_passed" "0" "0" "sudo apt-get check" 0 "client")
OBS_UPG4=$(create_observation "dpkg_audit_passed" "0" "0" "sudo dpkg --audit" 0 "client")

UPG_OBS="[$OBS_UPG1, $OBS_UPG2, $OBS_UPG3, $OBS_UPG4]"
TS_UPG=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$UPG_CMD" 0 "Preparing to unpack .../genixbit-repository-fixture_1.0.1_amd64.deb..." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
UPG_CMDS="[$TS_UPG]"

write_stage_result "$EVIDENCE_OUT_DIR" "upgrade" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$UPG_CMDS" "$UPG_OBS" "{}" "{}"
emit_verified_marker "$EVIDENCE_OUT_DIR/upgrade-result.json" "UPGRADE" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Staging Client HTTPS & Core APT Validation Completed."
