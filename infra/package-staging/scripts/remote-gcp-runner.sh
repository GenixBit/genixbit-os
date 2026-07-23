#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Remote GCP Execution & Validation Runner for GenixBit OS Package Staging

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

PROJECT_ID="${GCP_PROJECT_ID:-genixbit-growth-os}"
ZONE="${GCP_ZONE:-asia-south1-a}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-20260723-001}"
REPO_HOST="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
CLIENT_HOST="${CLIENT_INSTANCE_NAME:-genixbit-staging-disposable-client}"
PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
EVIDENCE_OUT_DIR="$INFRA_DIR/results/${STAGING_RUN_ID}"

mkdir -p "$EVIDENCE_OUT_DIR"

echo "=== Executing GCP Remote Staging Repository Setup & Key Generation ==="

ssh_repo() {
    gcloud compute ssh "$REPO_HOST" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$1"
}

ssh_client() {
    gcloud compute ssh "$CLIENT_HOST" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$1"
}

scp_from_repo() {
    gcloud compute scp "${REPO_HOST}:$1" "$2" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
}

scp_from_client() {
    gcloud compute scp "${CLIENT_HOST}:$1" "$2" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
}

# 1. Setup GPG Key & Build Signed Repository on Repo Host
REMOTE_SETUP_SCRIPT=$(cat << 'EOF'
set -euo pipefail

sudo apt-get update -qq && sudo apt-get install -y -qq gpg dpkg-dev nginx curl xz-utils >/dev/null 2>&1

BUILD_DIR="/tmp/genixbit_repo_build"
sudo rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gpg" "$BUILD_DIR/repo/pool/main/g/genixbit-repository-fixture" "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64" "$BUILD_DIR/repo/dists/resolute-testing/main/binary-amd64"
chmod 700 "$BUILD_DIR/gpg"

export GNUPGHOME="$BUILD_DIR/gpg"

cat << 'KEYEOF' > "$BUILD_DIR/gpg/key_params"
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: sign
Name-Real: GenixBit Staging Authority
Name-Email: staging-key@genixbit.internal
Expire-Date: 30d
KEYEOF

gpg --batch --generate-key "$BUILD_DIR/gpg/key_params" >/dev/null 2>&1 || true

KEY_FPR=$(gpg --list-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
echo "$KEY_FPR" > "$BUILD_DIR/key_fpr.txt"

gpg --export "$KEY_FPR" > "$BUILD_DIR/keyring.gpg"

# Build Package 1.0.0
PKG1_DIR="$BUILD_DIR/pkg100"
mkdir -p "$PKG1_DIR/DEBIAN" "$PKG1_DIR/usr/bin" "$PKG1_DIR/usr/share/doc/genixbit-repository-fixture"
cat << 'CEOF' > "$PKG1_DIR/DEBIAN/control"
Package: genixbit-repository-fixture
Version: 1.0.0
Architecture: all
Maintainer: GenixBit OS Core Team <packages@genixbit.internal>
Description: GenixBit OS Staging Validation Package Fixture 1.0.0
 Section: utils
 Priority: optional
CEOF

cat << 'FEOF' > "$PKG1_DIR/usr/bin/genixbit-staging-fixture"
#!/bin/sh
echo "GenixBit Staging Package Fixture Version 1.0.0"
FEOF
chmod +x "$PKG1_DIR/usr/bin/genixbit-staging-fixture"
echo "GenixBit Fixture 1.0.0" > "$PKG1_DIR/usr/share/doc/genixbit-repository-fixture/changelog"

dpkg-deb --build --root-owner-group "$PKG1_DIR" "$BUILD_DIR/repo/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.0_all.deb" >/dev/null

# Build Package 1.0.1
PKG2_DIR="$BUILD_DIR/pkg101"
mkdir -p "$PKG2_DIR/DEBIAN" "$PKG2_DIR/usr/bin" "$PKG2_DIR/usr/share/doc/genixbit-repository-fixture"
cat << 'CEOF' > "$PKG2_DIR/DEBIAN/control"
Package: genixbit-repository-fixture
Version: 1.0.1
Architecture: all
Maintainer: GenixBit OS Core Team <packages@genixbit.internal>
Description: GenixBit OS Staging Validation Package Fixture 1.0.1
 Section: utils
 Priority: optional
CEOF

cat << 'FEOF' > "$PKG2_DIR/usr/bin/genixbit-staging-fixture"
#!/bin/sh
echo "GenixBit Staging Package Fixture Version 1.0.1"
FEOF
chmod +x "$PKG2_DIR/usr/bin/genixbit-staging-fixture"
echo "GenixBit Fixture 1.0.1" > "$PKG2_DIR/usr/share/doc/genixbit-repository-fixture/changelog"

dpkg-deb --build --root-owner-group "$PKG2_DIR" "$BUILD_DIR/repo/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.1_all.deb" >/dev/null

# Generate Packages & Release files for resolute-alpha
(cd "$BUILD_DIR/repo" && dpkg-scanpackages pool/main/g/genixbit-repository-fixture > dists/resolute-alpha/main/binary-amd64/Packages)
gzip -9c "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64/Packages" > "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64/Packages.gz"
xz -9c "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64/Packages" > "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64/Packages.xz"

# Generate resolute-testing packages
cp -a "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64/"* "$BUILD_DIR/repo/dists/resolute-testing/main/binary-amd64/"

build_release() {
    local suite="$1"
    local rdir="$BUILD_DIR/repo/dists/$suite"
    local psize=$(wc -c < "$rdir/main/binary-amd64/Packages" | tr -d ' ')
    local psha=$(sha256sum "$rdir/main/binary-amd64/Packages" | awk '{print $1}')
    local pgsize=$(wc -c < "$rdir/main/binary-amd64/Packages.gz" | tr -d ' ')
    local pgsha=$(sha256sum "$rdir/main/binary-amd64/Packages.gz" | awk '{print $1}')

    cat << RELEASEEOF > "$rdir/Release"
Origin: GenixBit OS
Label: GenixBit Staging
Suite: $suite
Codename: $suite
Architectures: amd64 all
Components: main
Date: $(date -u +"%a, %d %b %Y %H:%M:%S UTC")
SHA256:
 $psha $psize main/binary-amd64/Packages
 $pgsha $pgsize main/binary-amd64/Packages.gz
RELEASEEOF

    gpg --batch --yes -u "$KEY_FPR" --clearsign -o "$rdir/InRelease" "$rdir/Release"
    gpg --batch --yes -u "$KEY_FPR" -abs -o "$rdir/Release.gpg" "$rdir/Release"
}

build_release "resolute-alpha"
build_release "resolute-testing"

# Deploy to Nginx web root
sudo mkdir -p /var/srv/genixbit-repository/releases/release-initial
sudo cp -a "$BUILD_DIR/repo/"* /var/srv/genixbit-repository/releases/release-initial/
sudo chown -R www-data:www-data /var/srv/genixbit-repository
sudo chmod -R 755 /var/srv/genixbit-repository
sudo ln -sfn /var/srv/genixbit-repository/releases/release-initial /var/srv/genixbit-repository/current

echo "SETUP_SUCCESS:$KEY_FPR"
EOF
)

ssh_repo "$REMOTE_SETUP_SCRIPT"

KEY_FPR=$(ssh_repo "cat /tmp/genixbit_repo_build/key_fpr.txt" | tr -d '\r\n')
echo "[PASS] GCP Staging Repository & Key Setup Complete. Fingerprint: $KEY_FPR"

# Download keyring from repo host to local build dir
LOCAL_KEYRING="$INFRA_DIR/build/keyring.gpg"
LOCAL_STAGING="$INFRA_DIR/build/repo"
mkdir -p "$INFRA_DIR/build"
scp_from_repo "/tmp/genixbit_repo_build/keyring.gpg" "$LOCAL_KEYRING"
gcloud compute scp --recurse "${REPO_HOST}:/tmp/genixbit_repo_build/repo" "$LOCAL_STAGING" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap

echo "[PASS] Downloaded staging repository and keyring to local workspace."
