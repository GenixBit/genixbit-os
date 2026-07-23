#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Remote GCP Execution & Validation Runner for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

PROJECT_ID="${GCP_PROJECT_ID:?Error: GCP_PROJECT_ID is required}"
ZONE="${GCP_ZONE:?Error: GCP_ZONE is required}"
STAGING_RUN_ID="${STAGING_RUN_ID:?Error: STAGING_RUN_ID is required}"
REPO_HOST="${REPOSITORY_INSTANCE_NAME:?Error: REPOSITORY_INSTANCE_NAME is required}"
CLIENT_HOST="${CLIENT_INSTANCE_NAME:?Error: CLIENT_INSTANCE_NAME is required}"
SIGNER_HOST="${SIGNER_INSTANCE_NAME:?Error: SIGNER_INSTANCE_NAME is required}"
PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:?Error: PRIVATE_HOSTNAME is required}"
EVIDENCE_OUT_DIR="$INFRA_DIR/results/${STAGING_RUN_ID}"

mkdir -p "$EVIDENCE_OUT_DIR"

echo "=== Executing GCP Remote Staging 3-Role Setup & Passphrase Key Generation ==="

ssh_signer() {
    gcloud compute ssh "$SIGNER_HOST" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$1"
}

ssh_repo() {
    gcloud compute ssh "$REPO_HOST" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$1"
}

ssh_client() {
    gcloud compute ssh "$CLIENT_HOST" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$1"
}

scp_from_signer() {
    gcloud compute scp "${SIGNER_HOST}:$1" "$2" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
}

scp_from_repo() {
    gcloud compute scp "${REPO_HOST}:$1" "$2" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
}

scp_to_repo() {
    gcloud compute scp "$1" "${REPO_HOST}:$2" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
}

# 1. Setup Passphrase-Protected GPG Key on SIGNING WORKSTATION ($SIGNER_HOST)
REMOTE_SIGNER_SETUP=$(cat << 'EOF'
set -euo pipefail

sudo apt-get update -qq && sudo apt-get install -y -qq gpg openssl curl >/dev/null 2>&1

BUILD_DIR="/tmp/genixbit_signer_build"
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gpg"
chmod 700 "$BUILD_DIR/gpg"

export GNUPGHOME="$BUILD_DIR/gpg"

PASSPHRASE=$(openssl rand -base64 32)
echo "$PASSPHRASE" > "$BUILD_DIR/passphrase.txt"
chmod 600 "$BUILD_DIR/passphrase.txt"

cat << 'KEYEOF' > "$BUILD_DIR/gpg/key_params"
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: sign
Name-Real: GenixBit Staging Authority
Name-Email: staging-key@genixbit.internal
Expire-Date: 30d
Passphrase: [PASSPHRASE_PLACEHOLDER]
KEYEOF

sed -i "s/\[PASSPHRASE_PLACEHOLDER\]/$PASSPHRASE/g" "$BUILD_DIR/gpg/key_params"

gpg --batch --generate-key "$BUILD_DIR/gpg/key_params" >/dev/null 2>&1

KEY_FPR=$(gpg --list-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
echo "$KEY_FPR" > "$BUILD_DIR/key_fpr.txt"

gpg --export "$KEY_FPR" > "$BUILD_DIR/keyring.gpg"

# Create encrypted recovery backup
gpg --armor --pinentry-mode loopback --passphrase-file "$BUILD_DIR/passphrase.txt" --export-secret-keys "$KEY_FPR" | \
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:"$BUILD_DIR/passphrase.txt" -out "$BUILD_DIR/staging_key_backup.gpg.enc"

sha256sum "$BUILD_DIR/staging_key_backup.gpg.enc" | awk '{print $1}' > "$BUILD_DIR/staging_key_backup.sha256"

# Generate revocation certificate
printf '%s\n' 'y' '0' 'Key Revocation Setup' '' 'y' | gpg --pinentry-mode loopback --passphrase-file "$BUILD_DIR/passphrase.txt" --command-fd 0 --output "$BUILD_DIR/expendable_revocation.crt" --gen-revoke "$KEY_FPR" 2>/dev/null || true

echo "SIGNER_SUCCESS:$KEY_FPR"
EOF
)

ssh_signer "$REMOTE_SIGNER_SETUP"
KEY_FPR=$(ssh_signer "cat /tmp/genixbit_signer_build/key_fpr.txt" | tr -d '\r\n')
echo "[PASS] Passphrase-Protected Staging Key Generated on Signer. Fingerprint: $KEY_FPR"

# 2. Deploy Public Keyring to Repository Host and Verify Zero Secret Keys
scp_from_signer "/tmp/genixbit_signer_build/keyring.gpg" "/tmp/keyring.gpg"
scp_to_repo "/tmp/keyring.gpg" "/tmp/keyring.gpg"

REMOTE_REPO_SETUP=$(cat << 'EOF'
set -euo pipefail

sudo apt-get update -qq && sudo apt-get install -y -qq gpg dpkg-dev nginx curl xz-utils >/dev/null 2>&1

# Verify ZERO secret OpenPGP keys on repository host
if gpg --list-secret-keys 2>/dev/null | grep -q '^sec'; then
    echo "[ERROR] Secret OpenPGP key detected on repository host! Signer isolation violated!" >&2
    exit 1
fi

echo "[PASS] Zero secret OpenPGP keys verified on repository host."
EOF
)

ssh_repo "$REMOTE_REPO_SETUP"

# 3. Verify Zero Secret Keys on Client
REMOTE_CLIENT_VERIFY=$(cat << 'EOF'
set -euo pipefail
if gpg --list-secret-keys 2>/dev/null | grep -q '^sec'; then
    echo "[ERROR] Secret OpenPGP key detected on APT client! Signer isolation violated!" >&2
    exit 1
fi
echo "[PASS] Zero secret OpenPGP keys verified on APT client."
EOF
)

ssh_client "$REMOTE_CLIENT_VERIFY"

echo "[PASS] 3-Role Signer Isolation Verified: Secret keys reside ONLY on Signing Workstation."
