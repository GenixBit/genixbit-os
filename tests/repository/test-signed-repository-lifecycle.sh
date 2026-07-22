#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# End-to-end repository lifecycle & ephemeral signing test.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

TMP_DIR=$(mktemp -d)
TMP_GPG="$TMP_DIR/gpg"
TMP_REPO="$TMP_DIR/repo"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_GPG" "$TMP_REPO"
chmod 700 "$TMP_GPG"
export GNUPGHOME="$TMP_GPG"

if command -v gpg >/dev/null 2>&1; then
    echo "[INFO] 1. Generating ephemeral TEST ONLY GPG signing key..."
    gpg --batch --full-generate-key <<EOF
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign,cert
Name-Real: GenixBit TEST ONLY Signing Key
Name-Email: test-only@genixbit.com
Expire-Date: 1d
%no-protection
EOF

    FPR=$(gpg --list-secret-keys --with-colons "test-only@genixbit.com" | grep fpr | head -n1 | cut -d':' -f10)
    PUB_KEYRING="$TMP_DIR/genixbit-os-archive-keyring.pgp"
    gpg --armor --export "$FPR" > "$PUB_KEYRING"
    echo "[PASS] Generated ephemeral GPG key: $FPR"
else
    echo "[INFO] GPG not installed on host; skipping GPG key generation in local test mode."
    PUB_KEYRING="$TMP_DIR/genixbit-os-archive-keyring.pgp"
    touch "$PUB_KEYRING"
    FPR="0000000000000000000000000000000000000000"
fi

echo "[INFO] 2. Building minimal test deb fixtures..."
PKG_DIR_100="$TMP_DIR/genixbit-fixture-1.0.0"
mkdir -p "$PKG_DIR_100/DEBIAN" "$PKG_DIR_100/usr/share/doc/genixbit-fixture"
cat <<EOF > "$PKG_DIR_100/DEBIAN/control"
Package: genixbit-repository-fixture
Version: 1.0.0
Architecture: amd64
Maintainer: GenixBit OS Maintainers <ftpmaster@genixbit.com>
Description: GenixBit Repository Fixture Package 1.0.0
EOF
echo "Fixture 1.0.0" > "$PKG_DIR_100/usr/share/doc/genixbit-fixture/changelog"

DEB_100="$TMP_DIR/genixbit-repository-fixture_1.0.0_amd64.deb"
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --build "$PKG_DIR_100" "$DEB_100" >/dev/null
else
    # Minimal mock deb file if dpkg-deb absent
    touch "$DEB_100"
    echo "mock deb content v1.0.0" > "$DEB_100"
fi

echo "[INFO] 3. Initializing staging repository and adding fixture package..."
bash "$REPO_ROOT/tools/repository/init-staging-repository.sh" --repo-dir "$TMP_REPO" >/dev/null
mkdir -p "$TMP_REPO/pool/main/g/genixbit-repository-fixture"
cp "$DEB_100" "$TMP_REPO/pool/main/g/genixbit-repository-fixture/"

echo "[INFO] 4. Building real package index..."
bash "$REPO_ROOT/tools/repository/build-package-index.sh" --repo-dir "$TMP_REPO" --channel "resolute-alpha" >/dev/null

if command -v gpg >/dev/null 2>&1; then
    echo "[INFO] 5. Signing Release metadata with ephemeral key..."
    bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
        --repo-dir "$TMP_REPO" \
        --channel "resolute-alpha" \
        --signing-key-fingerprint "$FPR" \
        --gnupg-home "$TMP_GPG" >/dev/null

    echo "[INFO] 6. Verifying signed Release metadata..."
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO/dists/resolute-alpha/InRelease" \
        --keyring "$PUB_KEYRING" \
        --expected-fingerprint "$FPR" >/dev/null

    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO/dists/resolute-alpha/Release.gpg" \
        --keyring "$PUB_KEYRING" \
        --expected-fingerprint "$FPR" >/dev/null
else
    echo "[INFO] GPG not installed on host; skipping signature creation and verification steps."
fi

echo "[INFO] 7. Testing channel switching, promotion, and snapshots..."
bash "$REPO_ROOT/tools/repository/promote-package.sh" \
    --repo-dir "$TMP_REPO" \
    --package "genixbit-repository-fixture" \
    --version "1.0.0" \
    --from-channel "resolute-alpha" \
    --to-channel "resolute-testing" >/dev/null

SNAP_OUT=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$TMP_REPO" --channel "resolute-testing")
SNAP_ID=$(echo "$SNAP_OUT" | grep "Snapshot ID:" | awk '{print $NF}')

bash "$REPO_ROOT/tools/repository/verify-snapshot.sh" --repo-dir "$TMP_REPO" --snapshot-id "$SNAP_ID" >/dev/null

bash "$REPO_ROOT/tools/repository/rollback-snapshot.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-testing" \
    --snapshot-id "$SNAP_ID" >/dev/null

# Test channel switcher set-channel.sh
MOCK_SOURCES="$TMP_DIR/genixbit-os.sources"
cat <<EOF > "$MOCK_SOURCES"
Types: deb
URIs: file://$TMP_REPO/
Suites: resolute-alpha
Components: main
Architectures: amd64
Signed-By: $PUB_KEYRING
Enabled: no
EOF

bash "$REPO_ROOT/tools/repository/set-channel.sh" testing \
    --sources-file "$MOCK_SOURCES" \
    --keyring-file "$PUB_KEYRING" \
    --skip-root-check \
    --skip-network-check \
    --skip-apt-update >/dev/null

grep -q "Suites: resolute-testing" "$MOCK_SOURCES"
grep -q "Enabled: yes" "$MOCK_SOURCES"

printf '[PASS] End-to-end repository lifecycle & ephemeral signing test completed successfully.\n'
