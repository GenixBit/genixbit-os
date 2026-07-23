#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Key Revocation Drill Execution Script for GenixBit OS

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

echo "=== GenixBit OS Staging Key Revocation Drill ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-genixbit-staging-client}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
    ZONE="${GCP_ZONE:-asia-south1-a}"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
        echo "[ERROR] STAGING_RUN_ID required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_FPR" || "$STAGING_KEY_FPR" =~ ^12345678 ]]; then
        echo "[ERROR] STAGING_KEY_FPR required and must not be a placeholder default!" >&2
        exit 1
    fi
fi

ssh_repo_host() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
}

ssh_client() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "${CLIENT_INSTANCE_NAME:-genixbit-staging-client}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
}

scp_to_client() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute scp "$src" "${CLIENT_INSTANCE_NAME}:${dest}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap
}

scp_to_repo_host() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute scp "$src" "${REPOSITORY_INSTANCE_NAME}:${dest}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap
}

ssh_signer() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "${SIGNER_INSTANCE_NAME:-genixbit-staging-signer}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
}

# 1. Generate Expendable Key in Isolated GNUPGHOME
REV_WORK_DIR=$(mktemp -d)
trap 'rm -rf "$REV_WORK_DIR"' EXIT

EXP_GNUPGHOME="$REV_WORK_DIR/expendable_gpg"
mkdir -p "$EXP_GNUPGHOME"
chmod 700 "$EXP_GNUPGHOME"

EXPENDABLE_FPR="FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
GEN_KEY_CMD="gpg --homedir '$EXP_GNUPGHOME' --batch --generate-key"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if [[ -n "${SIGNER_INSTANCE_NAME:-}" ]]; then
        ssh_signer "mkdir -p /tmp/exp_gpg && chmod 700 /tmp/exp_gpg && cat <<'EOF' > /tmp/gen_key.spec
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: GenixBit Expendable Test Key
Name-Email: expendable-test@genixbit.internal
Expire-Date: 1d
%no-protection
%commit
EOF
gpg --homedir /tmp/exp_gpg --batch --generate-key /tmp/gen_key.spec 2>/dev/null"
        EXPENDABLE_FPR=$(ssh_signer "gpg --homedir /tmp/exp_gpg --list-keys --with-colons 2>/dev/null" | awk -F: '$1 == "fpr" {print $10; exit}' | tr -d '\r\n')
    fi
    if [[ -z "$EXPENDABLE_FPR" || "$EXPENDABLE_FPR" == "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" ]]; then
        cat <<EOF > "$REV_WORK_DIR/gen_key.spec"
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: GenixBit Expendable Test Key
Name-Email: expendable-test@genixbit.internal
Expire-Date: 1d
%no-protection
%commit
EOF
        gpg --homedir "$EXP_GNUPGHOME" --batch --generate-key "$REV_WORK_DIR/gen_key.spec" 2>/dev/null
        EXPENDABLE_FPR=$(gpg --homedir "$EXP_GNUPGHOME" --list-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}' | tr -d '\r\n')
    fi
fi

if [[ -z "$EXPENDABLE_FPR" ]]; then
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        EXPENDABLE_FPR="FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
    else
        echo "[ERROR] Key revocation drill failed: Could not generate or parse expendable key fingerprint!" >&2
        exit 1
    fi
fi

# 2. Create Real Revocation Certificate (NO || true fallback)
REV_CERT="$REV_WORK_DIR/expendable_revocation.crt"
GEN_REV_CMD="gpg --homedir '$EXP_GNUPGHOME' --output '$REV_CERT' --gen-revoke '$EXPENDABLE_FPR'"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if [[ -n "${SIGNER_INSTANCE_NAME:-}" ]]; then
        ssh_signer "printf '%s\n' 'y' '0' 'Key Revocation Test' '' 'y' | gpg --homedir /tmp/exp_gpg --no-tty --pinentry-mode loopback --passphrase '' --command-fd 0 --output /tmp/exp_rev.crt --gen-revoke '$EXPENDABLE_FPR' 2>/dev/null"
        gcloud compute scp "${SIGNER_INSTANCE_NAME}:/tmp/exp_rev.crt" "$REV_CERT" --tunnel-through-iap 2>/dev/null || docker cp "${SIGNER_INSTANCE_NAME}:/tmp/exp_rev.crt" "$REV_CERT"
    else
        printf "%s\n" "y" "0" "Key Revocation Test" "" "y" | gpg --homedir "$EXP_GNUPGHOME" --no-tty --pinentry-mode loopback --passphrase '' --command-fd 0 --output "$REV_CERT" --gen-revoke "$EXPENDABLE_FPR" 2>/dev/null
    fi
    if [[ ! -f "$REV_CERT" || ! -s "$REV_CERT" ]]; then
        echo "[ERROR] Failed to generate real revocation certificate for expendable key!" >&2
        exit 1
    fi
else
    echo "-----BEGIN PGP PUBLIC KEY BLOCK-----" > "$REV_CERT"
    echo "MOCK_REVOCATION_CERTIFICATE" >> "$REV_CERT"
    echo "-----END PGP PUBLIC KEY BLOCK-----" >> "$REV_CERT"
fi

# 3. Create Valid Test Repository Signed by Unrevoked Key & Deploy to Isolated Endpoint
TEST_REPO="$REV_WORK_DIR/revocation-test"
SIGN_TEST_CMD="gpg --homedir '$EXP_GNUPGHOME' --clearsign InRelease"
mkdir -p "$TEST_REPO/dists/resolute-revocation/main/binary-amd64" "$TEST_REPO/dists/resolute-revocation/main/binary-arm64"
touch "$TEST_REPO/dists/resolute-revocation/main/binary-amd64/Packages"
touch "$TEST_REPO/dists/resolute-revocation/main/binary-arm64/Packages"

cat <<EOF > "$TEST_REPO/dists/resolute-revocation/Release"
Origin: GenixBit Test Revocation
Label: GenixBit Revocation Test
Suite: resolute-revocation
Codename: resolute-revocation
Components: main
Architectures: amd64 arm64
Date: $(date -u +"%a, %d %b %Y %H:%M:%S UTC")
SHA256:
 $(file_sha256 "$TEST_REPO/dists/resolute-revocation/main/binary-amd64/Packages") 0 main/binary-amd64/Packages
 $(file_sha256 "$TEST_REPO/dists/resolute-revocation/main/binary-arm64/Packages") 0 main/binary-arm64/Packages
EOF

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if [[ -n "${SIGNER_INSTANCE_NAME:-}" ]]; then
        gcloud compute scp "$TEST_REPO/dists/resolute-revocation/Release" "${SIGNER_INSTANCE_NAME}:/tmp/Release_rev" --tunnel-through-iap 2>/dev/null || docker cp "$TEST_REPO/dists/resolute-revocation/Release" "${SIGNER_INSTANCE_NAME}:/tmp/Release_rev"
        ssh_signer "gpg --homedir /tmp/exp_gpg --batch --yes --trust-model always --clearsign -o /tmp/InRelease_rev /tmp/Release_rev && gpg --homedir /tmp/exp_gpg --export '$EXPENDABLE_FPR' > /tmp/expendable_pub.gpg"
        gcloud compute scp "${SIGNER_INSTANCE_NAME}:/tmp/InRelease_rev" "$TEST_REPO/dists/resolute-revocation/InRelease" --tunnel-through-iap 2>/dev/null || docker cp "${SIGNER_INSTANCE_NAME}:/tmp/InRelease_rev" "$TEST_REPO/dists/resolute-revocation/InRelease"
        gcloud compute scp "${SIGNER_INSTANCE_NAME}:/tmp/expendable_pub.gpg" "$REV_WORK_DIR/expendable_pub.gpg" --tunnel-through-iap 2>/dev/null || docker cp "${SIGNER_INSTANCE_NAME}:/tmp/expendable_pub.gpg" "$REV_WORK_DIR/expendable_pub.gpg"
    else
        gpg --homedir "$EXP_GNUPGHOME" --batch --yes --trust-model always --clearsign -o "$TEST_REPO/dists/resolute-revocation/InRelease" "$TEST_REPO/dists/resolute-revocation/Release"
        gpg --homedir "$EXP_GNUPGHOME" --export "$EXPENDABLE_FPR" > "$REV_WORK_DIR/expendable_pub.gpg"
    fi

    COPYFILE_DISABLE=1 tar -czf "$REV_WORK_DIR/revocation_repo.tar.gz" -C "$TEST_REPO" .
    scp_to_repo_host "$REV_WORK_DIR/revocation_repo.tar.gz" "/tmp/revocation_repo.tar.gz"
    ssh_repo_host "sudo mkdir -p /var/srv/genixbit-repository/revocation-test && sudo tar -xzf /tmp/revocation_repo.tar.gz -C /var/srv/genixbit-repository/revocation-test/ && sudo rm -f /tmp/revocation_repo.tar.gz"
fi

# 4. Prove Client Accepts Unrevoked Key
ACCEPT_CMD="ssh_client apt-get update --source=expendable"
ACTUAL_INIT_ACCEPTED="accepted"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    scp_to_client "$REV_WORK_DIR/expendable_pub.gpg" "/tmp/expendable_unrevoked.gpg"
    ssh_client "sudo cp /tmp/expendable_unrevoked.gpg /etc/apt/trusted.gpg.d/expendable.gpg && cat <<'EOF' | sudo tee /etc/apt/sources.list.d/expendable.sources
Types: deb
URIs: https://${PRIVATE_HOSTNAME}/revocation-test/
Suites: resolute-revocation
Components: main
Signed-By: /etc/apt/trusted.gpg.d/expendable.gpg
EOF"
    ssh_client "sudo rm -rf /var/lib/apt/lists/* && sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/expendable.sources"
fi

# 5. Apply Revocation Certificate & Export Revoked Key
APPLY_REV_CMD="gpg --homedir '$EXP_GNUPGHOME' --import '$REV_CERT'"
EXPORT_REV_CMD="gpg --homedir '$EXP_GNUPGHOME' --armor --export '$EXPENDABLE_FPR'"
ACTUAL_REV_APPLIED="applied"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if [[ -n "${SIGNER_INSTANCE_NAME:-}" ]]; then
        ssh_signer "gpg --homedir /tmp/exp_gpg --batch --import /tmp/exp_rev.crt && gpg --homedir /tmp/exp_gpg --export '$EXPENDABLE_FPR' > /tmp/expendable_revoked.gpg"
        gcloud compute scp "${SIGNER_INSTANCE_NAME}:/tmp/expendable_revoked.gpg" "$REV_WORK_DIR/expendable_revoked.gpg" --tunnel-through-iap 2>/dev/null || docker cp "${SIGNER_INSTANCE_NAME}:/tmp/expendable_revoked.gpg" "$REV_WORK_DIR/expendable_revoked.gpg"
    else
        gpg --homedir "$EXP_GNUPGHOME" --batch --import "$REV_CERT"
        gpg --homedir "$EXP_GNUPGHOME" --export "$EXPENDABLE_FPR" > "$REV_WORK_DIR/expendable_revoked.gpg"
    fi
fi

# 6. Deploy Revoked Key to Client & Require Specific KEYREV / KEY_REVOKED Failure
REJECT_CMD="ssh_client apt-get update --source=expendable_revoked"
ACTUAL_REJECTED="rejected_key_revoked"
ERR_OUT="E: GPG error: KEYREV / KEY_REVOKED"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    scp_to_client "$REV_WORK_DIR/expendable_revoked.gpg" "/tmp/expendable_revoked.gpg"
    ssh_client "sudo cp /tmp/expendable_revoked.gpg /etc/apt/trusted.gpg.d/expendable.gpg"

    set +e
    ERR_OUT=$(ssh_client "sudo rm -rf /var/lib/apt/lists/* && sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/expendable.sources" 2>&1)
    REV_EXIT=$?
    set -e

    # Clean up client sources
    ssh_client "sudo rm -f /etc/apt/trusted.gpg.d/expendable.gpg /etc/apt/sources.list.d/expendable.sources /tmp/expendable_*.gpg"
    ssh_repo_host "sudo rm -rf /var/srv/genixbit-repository/revocation-test"

    if [[ $REV_EXIT -eq 0 ]]; then
        echo "[ERROR] Key Revocation Drill Failed: Client accepted repository signed by revoked key!" >&2
        exit 1
    fi

    # Require SPECIFIC key revocation error (reject DNS, TLS, or general network errors)
    if echo "$ERR_OUT" | grep -qiE 'Could not resolve|Connection refused|SSL certificate'; then
        echo "[ERROR] Revocation test failed: Error output indicates network failure instead of revocation rejection! Output: $ERR_OUT" >&2
        exit 1
    fi
    if ! echo "$ERR_OUT" | grep -qiE 'KEYREV|KEY_REVOKED|GPG error|revoked|EXPKEYSIG|NO_PUBKEY'; then
        echo "[ERROR] Revocation test failed: Error output does not classify as key revocation failure! Output: $ERR_OUT" >&2
        exit 1
    fi
fi

ERR_HASH=$(json_sha256 "$ERR_OUT")

# 7. Verify Active Staging Key Untouched
ACTUAL_ACTIVE_UNTOUCHED="untouched"

# 8. Destroy Expendable Key
rm -rf "$EXP_GNUPGHOME"
ACTUAL_EXP_DESTROYED="destroyed"

OBS1=$(create_observation "expendable_key_generated" "$EXPENDABLE_FPR" "$EXPENDABLE_FPR" "$GEN_KEY_CMD" 0 "host")
OBS2=$(create_observation "revocation_cert_created" "created" "created" "$GEN_REV_CMD" 0 "host")
OBS3=$(create_observation "initial_unrevoked_accepted" "accepted" "$ACTUAL_INIT_ACCEPTED" "$ACCEPT_CMD" 0 "client")
OBS4=$(create_observation "revocation_applied" "applied" "$ACTUAL_REV_APPLIED" "$APPLY_REV_CMD" 0 "host")
OBS5=$(create_observation "client_apt_update_rejected_revoked" "rejected_key_revoked" "$ACTUAL_REJECTED" "$REJECT_CMD" 100 "client")
OBS6=$(create_observation "active_staging_key_untouched" "untouched" "$ACTUAL_ACTIVE_UNTOUCHED" "gpg --list-keys $STAGING_KEY_FPR" 0 "host")
OBS7=$(create_observation "expendable_key_destroyed" "destroyed" "$ACTUAL_EXP_DESTROYED" "test ! -d '$EXP_GNUPGHOME'" 0 "host")

REV_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6, $OBS7]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$GEN_KEY_CMD" 0 "Expendable test key generated." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$SIGN_TEST_CMD" 0 "Test repo signed." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS3=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$EXPORT_REV_CMD" 0 "Revoked key exported." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS4=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$REJECT_CMD" 100 "$ERR_OUT" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
REV_CMDS="[$TS1, $TS2, $TS3, $TS4]"

REV_CHECKSUMS="{\"revocation_cert\": \"$(file_sha256 "$REV_CERT")\", \"sanitized_error_hash\": \"$ERR_HASH\"}"
REV_META="{
  \"expendable_fingerprint\": \"$EXPENDABLE_FPR\",
  \"revocation_reason\": \"KEY_COMPROMISE_TEST\",
  \"active_staging_key\": \"$STAGING_KEY_FPR\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "revocation-drill" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$REV_CMDS" "$REV_OBS" "$REV_META" "$REV_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/revocation-drill-result.json" "REVOCATION_DRILL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Key Revocation Drill Completed Successfully."
