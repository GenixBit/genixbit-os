#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# End-to-end disposable APT client container test for GenixBit repository.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

# shellcheck source=tools/repository/lib/safety.sh
source "$REPO_ROOT/tools/repository/lib/safety.sh"

TMP_DIR=$(mktemp -d)
TMP_GPG="$TMP_DIR/gpg"
TMP_REPO="$TMP_DIR/repo"

cleanup() {
    chmod -R 777 "$TMP_DIR" 2>/dev/null || true
    rm -rf "$TMP_DIR" 2>/dev/null || docker run --rm -v "$TMP_DIR:$TMP_DIR" "$DOCKER_IMG" rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$TMP_GPG" "$TMP_REPO"
chmod 700 "$TMP_GPG"

if ! command -v docker >/dev/null 2>&1; then
    echo "[WARN] Docker not available; skipping containerized APT client validation."
    exit 0
fi

if ! docker ps >/dev/null 2>&1; then
    echo "[WARN] Docker daemon not running; skipping containerized APT client validation."
    exit 0
fi

DOCKER_IMG="ubuntu:latest"

cat <<EOF > "$TMP_DIR/ephemeral_genkey.conf"
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign,cert
Name-Real: GenixBit TEST ONLY Signing Key
Name-Email: test-only@genixbit.com
Expire-Date: 1d
%no-protection
EOF

TEST_CONTAINER_SCRIPT="$TMP_DIR/run_disposable_apt_test.sh"

cat << 'INNER_EOF' > "$TEST_CONTAINER_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$1"
REPO_ROOT="$2"

TMP_GPG="$TMP_DIR/gpg"
TMP_REPO="$TMP_DIR/repo"

export GNUPGHOME="$TMP_GPG"
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Installing required APT & GnuPG dependencies in container..."
apt-get update -qq
apt-get install -y -qq gnupg gpgv dpkg-dev ca-certificates python3 >/dev/null

echo "[INFO] 1. Generating ephemeral TEST ONLY GPG signing key..."
gpg --batch --generate-key "$TMP_DIR/ephemeral_genkey.conf"
FPR=$(gpg --list-secret-keys --with-colons "test-only@genixbit.com" | grep fpr | head -n1 | cut -d':' -f10)

PUB_KEYRING="/usr/share/keyrings/genixbit-os-archive-keyring.pgp"
mkdir -p /usr/share/keyrings
gpg --export "$FPR" > "$PUB_KEYRING"
echo "[PASS] Ephemeral signing key generated: $FPR"

echo "[INFO] 2. Building minimal test deb fixtures 1.0.0 and 1.0.1..."
LOCAL_BUILD_100="/tmp/fixture_build_100"
mkdir -p "$LOCAL_BUILD_100/DEBIAN" "$LOCAL_BUILD_100/usr/share/genixbit-repository-fixture"
printf "Package: genixbit-repository-fixture\nVersion: 1.0.0\nArchitecture: all\nMaintainer: GenixBit OS Maintainers <ftpmaster@genixbit.com>\nDescription: GenixBit Repository Fixture Package 1.0.0\n" > "$LOCAL_BUILD_100/DEBIAN/control"
echo "1.0.0" > "$LOCAL_BUILD_100/usr/share/genixbit-repository-fixture/version"
DEB_100="/tmp/genixbit-repository-fixture_1.0.0_all.deb"
dpkg-deb --build "$LOCAL_BUILD_100" "$DEB_100" >/dev/null

LOCAL_BUILD_101="/tmp/fixture_build_101"
mkdir -p "$LOCAL_BUILD_101/DEBIAN" "$LOCAL_BUILD_101/usr/share/genixbit-repository-fixture"
printf "Package: genixbit-repository-fixture\nVersion: 1.0.1\nArchitecture: all\nMaintainer: GenixBit OS Maintainers <ftpmaster@genixbit.com>\nDescription: GenixBit Repository Fixture Package 1.0.1\n" > "$LOCAL_BUILD_101/DEBIAN/control"
echo "1.0.1" > "$LOCAL_BUILD_101/usr/share/genixbit-repository-fixture/version"
DEB_101="/tmp/genixbit-repository-fixture_1.0.1_all.deb"
dpkg-deb --build "$LOCAL_BUILD_101" "$DEB_101" >/dev/null

echo "[INFO] 3. Initializing staging repository and adding version 1.0.0..."
bash "$REPO_ROOT/tools/repository/init-staging-repository.sh" --repo-dir "$TMP_REPO" >/dev/null
mkdir -p "$TMP_REPO/pool/main/g/genixbit-repository-fixture"
cp "$DEB_100" "$TMP_REPO/pool/main/g/genixbit-repository-fixture/"

echo "[INFO] 4. Building package index and signing resolute-alpha..."
bash "$REPO_ROOT/tools/repository/build-package-index.sh" --repo-dir "$TMP_REPO" --channel "resolute-alpha" >/dev/null
bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-alpha" \
    --signing-key-fingerprint "$FPR" \
    --gnupg-home "$TMP_GPG" >/dev/null

echo "[INFO] 5. Starting isolated HTTP server inside container..."
PORT=$(python3 -c "import socket; s = socket.socket(); s.bind(('', 0)); print(s.getsockname()[1]); s.close()")
python3 -m http.server "$PORT" --directory "$TMP_REPO" >/dev/null 2>&1 &
HTTP_PID=$!
sleep 1

cleanup_http() {
    if kill -0 "$HTTP_PID" 2>/dev/null; then
        kill "$HTTP_PID" 2>/dev/null || true
    fi
}
trap cleanup_http EXIT

echo "[INFO] 6. Disposable client APT update + install 1.0.0..."
mkdir -p /etc/apt/sources.list.d
printf "Types: deb\nURIs: http://127.0.0.1:%s/\nSuites: resolute-alpha\nComponents: main\nArchitectures: all amd64 arm64\nSigned-By: %s\nEnabled: yes\n" "$PORT" "$PUB_KEYRING" > /etc/apt/sources.list.d/genixbit-os.sources

apt-get update
echo "DISPOSABLE_APT_UPDATE=PASS"

apt-get install -y --no-install-recommends genixbit-repository-fixture
echo "DISPOSABLE_APT_INSTALL=PASS"

grep -q "1.0.0" /usr/share/genixbit-repository-fixture/version

echo "[INFO] 7. Publishing version 1.0.1 to resolute-alpha and testing upgrade..."
cp "$DEB_101" "$TMP_REPO/pool/main/g/genixbit-repository-fixture/"
bash "$REPO_ROOT/tools/repository/build-package-index.sh" --repo-dir "$TMP_REPO" --channel "resolute-alpha" >/dev/null
bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-alpha" \
    --signing-key-fingerprint "$FPR" \
    --gnupg-home "$TMP_GPG" >/dev/null

apt-get update
apt-get install -y --only-upgrade genixbit-repository-fixture
echo "DISPOSABLE_APT_UPGRADE=PASS"

grep -q "1.0.1" /usr/share/genixbit-repository-fixture/version
apt-get check
dpkg --audit

echo "[INFO] 8. Promoting version 1.0.1 to resolute-testing and validating channel switch..."
bash "$REPO_ROOT/tools/repository/promote-package.sh" \
    --repo-dir "$TMP_REPO" \
    --package "genixbit-repository-fixture" \
    --version "1.0.1" \
    --from-channel "resolute-alpha" \
    --to-channel "resolute-testing" >/dev/null

bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-testing" \
    --signing-key-fingerprint "$FPR" \
    --gnupg-home "$TMP_GPG" >/dev/null

bash "$REPO_ROOT/tools/repository/set-channel.sh" testing \
    --sources-file "/etc/apt/sources.list.d/genixbit-os.sources" \
    --keyring-file "$PUB_KEYRING" \
    --skip-network-check

POLICY_OUT=$(apt-cache policy genixbit-repository-fixture)
echo "$POLICY_OUT" | grep -q "resolute-testing"
apt-get install -y --reinstall genixbit-repository-fixture
echo "PROMOTION_APT_VALIDATION=PASS"

echo "[INFO] 9. Testing snapshot creation, rollback, and APT validation..."
SNAP_OUT=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$TMP_REPO" --channel "resolute-testing")
SNAP_ID=$(echo "$SNAP_OUT" | grep "Snapshot ID:" | awk '{print $NF}')
echo "SNAPSHOT_VALIDATION=PASS"

bash "$REPO_ROOT/tools/repository/rollback-snapshot.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-testing" \
    --snapshot-id "$SNAP_ID" >/dev/null

bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-testing" \
    --signing-key-fingerprint "$FPR" \
    --gnupg-home "$TMP_GPG" >/dev/null

apt-get update
POLICY_OUT=$(apt-cache policy genixbit-repository-fixture)
echo "$POLICY_OUT" | grep -q "resolute-testing"
echo "ROLLBACK_APT_VALIDATION=PASS"

echo "[PASS] Containerized APT client validation suite passed successfully."
INNER_EOF

chmod +x "$TEST_CONTAINER_SCRIPT"

echo "[INFO] Running disposable APT client test in Ubuntu Docker container..."
docker run --rm \
    --net=host \
    -v "$TMP_DIR:$TMP_DIR" \
    -v "$REPO_ROOT:$REPO_ROOT" \
    "$DOCKER_IMG" bash "$TEST_CONTAINER_SCRIPT" "$TMP_DIR" "$REPO_ROOT"
