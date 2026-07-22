#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Real Non-Simulated Local Integration Harness for GenixBit OS Package Staging
# Uses disposable Docker containers and a gcloud shim to validate real operations cleanly.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))
INFRA_DIR="$REPO_ROOT/infra/package-staging"

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$INFRA_DIR/scripts/lib/evidence.sh"

echo "=== GenixBit OS Real Non-Simulated Local Integration Harness ==="

if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker is required to execute real-mode local integration tests!" >&2
    exit 1
fi

TMP_TEST_DIR=$(mktemp -d)
SHIM_BIN_DIR="$TMP_TEST_DIR/bin"
mkdir -p "$SHIM_BIN_DIR" "$TMP_TEST_DIR/gpg"
chmod 700 "$TMP_TEST_DIR/gpg"

HOST_CONTAINER="genixbit-staging-repo-host"
CLIENT_CONTAINER="genixbit-staging-client"

cleanup() {
    echo "[INFO] Cleaning up test containers and temp directory..."
    docker rm -f "$HOST_CONTAINER" "$CLIENT_CONTAINER" 2>/dev/null || true
    rm -rf "$TMP_TEST_DIR"
}
trap cleanup EXIT

# 1. Create Local gcloud Shim
cat << 'EOF' > "$SHIM_BIN_DIR/gcloud"
#!/usr/bin/env bash
set -euo pipefail

subcmd="${1:-}"
if [[ "$subcmd" == "compute" ]]; then
    action="${2:-}"
    if [[ "$action" == "ssh" ]]; then
        target="${3:-}"
        cmd=""
        shift 3
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --command=*) cmd="${1#*=}"; shift ;;
                --command) cmd="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        exec docker exec -i "$target" bash -c "$cmd"
    elif [[ "$action" == "scp" ]]; then
        shift 2
        src=""
        dest=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --*) shift ;;
                *) if [[ -z "$src" ]]; then src="$1"; else dest="$1"; fi; shift ;;
            esac
        done
        if [[ "$src" =~ ^([^:]+):(.*)$ ]]; then
            c="${BASH_REMATCH[1]}"
            p="${BASH_REMATCH[2]}"
            exec docker cp "$c:$p" "$dest"
        elif [[ "$dest" =~ ^([^:]+):(.*)$ ]]; then
            c="${BASH_REMATCH[1]}"
            p="${BASH_REMATCH[2]}"
            exec docker cp "$src" "$c:$p"
        else
            exec cp "$src" "$dest"
        fi
    elif [[ "$action" == "instances" ]]; then
        exec echo "10.0.1.10"
    fi
elif [[ "$subcmd" == "auth" ]]; then
    exec echo "active-operator@genixbit.internal"
elif [[ "$subcmd" == "projects" ]]; then
    exec echo "genixbit-real-staging-project"
fi
exec echo "gcloud shim success"
EOF
chmod +x "$SHIM_BIN_DIR/gcloud"

export PATH="$SHIM_BIN_DIR:$PATH"

# 2. Launch Host Container (nginx + tools + sudo)
echo "[INFO] Launching repository host container ($HOST_CONTAINER)..."
docker rm -f "$HOST_CONTAINER" 2>/dev/null || true
docker run -d --name "$HOST_CONTAINER" --hostname "staging-packages.genixbit.internal" \
    ubuntu:24.04 sleep infinity

# Install dependencies inside host container including sudo
docker exec "$HOST_CONTAINER" bash -c "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y nginx gpg dpkg-dev apt-utils tar curl openssl ca-certificates sudo >/dev/null
useradd -r -s /bin/false genixbit-repo 2>/dev/null || true
mkdir -p /var/srv/genixbit-repository/releases /var/srv/genixbit-repository/keyring /etc/nginx/ssl
"

# 3. Create TLS Certificate & Key inside host container
HOST_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$HOST_CONTAINER")
if [[ -z "$HOST_IP" ]]; then
    HOST_IP="10.0.1.10"
fi

docker exec "$HOST_CONTAINER" bash -c "
set -euo pipefail
openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/nginx/ssl/ca.key -out /etc/nginx/ssl/ca.crt -subj '/CN=GenixBit Staging Local CA' -days 7 >/dev/null 2>&1
cat <<'CEOF' > /etc/nginx/ssl/ext.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = staging-packages.genixbit.internal
IP.1 = ${HOST_IP}
CEOF

openssl req -newkey rsa:2048 -nodes -keyout /etc/nginx/ssl/server.key -out /etc/nginx/ssl/server.csr -subj '/CN=staging-packages.genixbit.internal' >/dev/null 2>&1
openssl x509 -req -in /etc/nginx/ssl/server.csr -CA /etc/nginx/ssl/ca.crt -CAkey /etc/nginx/ssl/ca.key -CAcreateserial -out /etc/nginx/ssl/server.crt -days 7 -extfile /etc/nginx/ssl/ext.cnf -extensions v3_req >/dev/null 2>&1

cat <<'NEOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    server_name staging-packages.genixbit.internal;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    location /healthz {
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    location / {
        root /var/srv/genixbit-repository/current;
        autoindex on;
    }
}
NEOF

nginx -t >/dev/null 2>&1
service nginx restart >/dev/null 2>&1
"

# Copy certificates out to local temp directory
docker cp "$HOST_CONTAINER:/etc/nginx/ssl/ca.crt" "$TMP_TEST_DIR/staging-ca.crt"
docker cp "$HOST_CONTAINER:/etc/nginx/ssl/server.crt" "$TMP_TEST_DIR/staging-leaf.crt"

APPROVED_CERT_FPR=$(openssl x509 -in "$TMP_TEST_DIR/staging-leaf.crt" -noout -fingerprint -sha256 | cut -d'=' -f2 | tr -d ':')

# 4. Generate GPG Key Pair inside host container
docker exec "$HOST_CONTAINER" bash -c "
set -euo pipefail
cat <<'GEOF' > /tmp/key.spec
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: GenixBit Staging Authority
Name-Email: staging-key@genixbit.internal
Expire-Date: 7d
%no-protection
%commit
GEOF
gpg --batch --generate-key /tmp/key.spec >/dev/null 2>&1
FPR=\$(gpg --list-keys --with-colons | grep '^fpr:' | head -n1 | cut -d: -f10)
gpg --export \"\$FPR\" > /var/srv/genixbit-repository/keyring/keyring.gpg
echo \"\$FPR\" > /tmp/key_fpr.txt
"

STAGING_KEY_FPR=$(docker exec "$HOST_CONTAINER" cat /tmp/key_fpr.txt | tr -d '\r\n')
docker cp "$HOST_CONTAINER:/var/srv/genixbit-repository/keyring/keyring.gpg" "$TMP_TEST_DIR/staging-keyring.gpg"

# 5. Launch Client Container
echo "[INFO] Launching disposable APT client container ($CLIENT_CONTAINER)..."
docker rm -f "$CLIENT_CONTAINER" 2>/dev/null || true
docker run -d --name "$CLIENT_CONTAINER" ubuntu:24.04 sleep infinity

docker cp "$TMP_TEST_DIR/staging-ca.crt" "$CLIENT_CONTAINER:/usr/local/share/ca-certificates/staging-ca.crt"
docker cp "$TMP_TEST_DIR/staging-keyring.gpg" "$CLIENT_CONTAINER:/etc/apt/trusted.gpg.d/genixbit-staging.gpg"

docker exec "$CLIENT_CONTAINER" bash -c "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y curl ca-certificates gpg sudo >/dev/null
echo '${HOST_IP} staging-packages.genixbit.internal' >> /etc/hosts
update-ca-certificates >/dev/null 2>&1

mkdir -p /etc/apt/sources.list.d
cat <<'SEOF' > /etc/apt/sources.list.d/genixbit.sources
Types: deb
URIs: https://staging-packages.genixbit.internal/
Suites: resolute-alpha
Components: main
Signed-By: /etc/apt/trusted.gpg.d/genixbit-staging.gpg
SEOF
"

SYS_ARCH=$(docker exec "$CLIENT_CONTAINER" dpkg --print-architecture | tr -d '\r\n')
if [[ -z "$SYS_ARCH" ]]; then
    SYS_ARCH="amd64"
fi

# 6. Prepare Local Staging Directory with Real Signed Deb Fixture
LOCAL_STAGING_DIR="$TMP_TEST_DIR/local_staging_repo"
mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-alpha/main/binary-${SYS_ARCH}" "$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture"

# Build version 1.0.0 package fixture
PKG1_DIR="$TMP_TEST_DIR/pkg1"
mkdir -p "$PKG1_DIR/DEBIAN" "$PKG1_DIR/usr/share/genixbit-repository-fixture"
cat <<EOF > "$PKG1_DIR/DEBIAN/control"
Package: genixbit-repository-fixture
Version: 1.0.0
Architecture: ${SYS_ARCH}
Maintainer: GenixBit OS Core Team <core@genixbit.org>
Description: GenixBit OS Staging Repository Validation Fixture Package
EOF
echo "1.0.0" > "$PKG1_DIR/usr/share/genixbit-repository-fixture/version"
dpkg-deb --build "$PKG1_DIR" "$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.0_${SYS_ARCH}.deb" >/dev/null

# Build version 1.0.1 package fixture
PKG2_DIR="$TMP_TEST_DIR/pkg2"
mkdir -p "$PKG2_DIR/DEBIAN" "$PKG2_DIR/usr/share/genixbit-repository-fixture"
cat <<EOF > "$PKG2_DIR/DEBIAN/control"
Package: genixbit-repository-fixture
Version: 1.0.1
Architecture: ${SYS_ARCH}
Maintainer: GenixBit OS Core Team <core@genixbit.org>
Description: GenixBit OS Staging Repository Validation Fixture Package
EOF
echo "1.0.1" > "$PKG2_DIR/usr/share/genixbit-repository-fixture/version"
dpkg-deb --build "$PKG2_DIR" "$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.1_${SYS_ARCH}.deb" >/dev/null

# Generate Packages & Release inside local staging directory
(
    cd "$LOCAL_STAGING_DIR"
    dpkg-scanpackages -m pool/main > "dists/resolute-alpha/main/binary-${SYS_ARCH}/Packages"
    gzip -9c "dists/resolute-alpha/main/binary-${SYS_ARCH}/Packages" > "dists/resolute-alpha/main/binary-${SYS_ARCH}/Packages.gz"
    xz -c "dists/resolute-alpha/main/binary-${SYS_ARCH}/Packages" > "dists/resolute-alpha/main/binary-${SYS_ARCH}/Packages.xz"

    if [[ "$SYS_ARCH" != "amd64" ]]; then
        mkdir -p dists/resolute-alpha/main/binary-amd64
        cp -r "dists/resolute-alpha/main/binary-${SYS_ARCH}/"* dists/resolute-alpha/main/binary-amd64/
    fi

    cat <<EOF > dists/resolute-alpha/Release
Origin: GenixBit OS Staging
Label: GenixBit OS
Codename: resolute-alpha
Components: main
Architectures: ${SYS_ARCH} amd64
Date: $(date -u +"%a, %d %b %Y %H:%M:%S UTC")
EOF
    echo "SHA256:" >> dists/resolute-alpha/Release
    for file in main/binary-${SYS_ARCH}/Packages main/binary-${SYS_ARCH}/Packages.gz main/binary-${SYS_ARCH}/Packages.xz; do
        sha=$(file_sha256 "dists/resolute-alpha/$file")
        sz=$(wc -c < "dists/resolute-alpha/$file" | tr -d ' ')
        printf " %s %8d %s\n" "$sha" "$sz" "$file" >> dists/resolute-alpha/Release
    done
)

# Execute GPG Signing inside host container
docker cp "$LOCAL_STAGING_DIR" "$HOST_CONTAINER:/tmp/repo_build"
docker exec "$HOST_CONTAINER" bash -c "
set -euo pipefail
cd /tmp/repo_build/dists/resolute-alpha
gpg --batch --yes --clearsign --digest-algo SHA256 -o InRelease Release
gpg --batch --yes --detach-sign --armor --digest-algo SHA256 -o Release.gpg Release
"
docker cp "$HOST_CONTAINER:/tmp/repo_build/dists/resolute-alpha/InRelease" "$LOCAL_STAGING_DIR/dists/resolute-alpha/InRelease"
docker cp "$HOST_CONTAINER:/tmp/repo_build/dists/resolute-alpha/Release.gpg" "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release.gpg"

# Export environment variables for non-simulated operational runs
export GENIXBIT_SIMULATE_OPS=0
export GCP_PROJECT_ID="genixbit-real-staging-project"
export GCP_ZONE="asia-south1-a"
export STAGING_RUN_ID="run-real-local-001"
export REPOSITORY_INSTANCE_NAME="$HOST_CONTAINER"
export CLIENT_INSTANCE_NAME="$CLIENT_CONTAINER"
export PRIVATE_HOSTNAME="staging-packages.genixbit.internal"
export EXPECTED_REPOSITORY_PRIVATE_IP="$HOST_IP"
export APPROVED_CERT_FPR="$APPROVED_CERT_FPR"
export STAGING_LEAF_CERT="$TMP_TEST_DIR/staging-leaf.crt"
export STAGING_CA_CERT="$TMP_TEST_DIR/staging-ca.crt"
export LOCAL_STAGING_DIR="$LOCAL_STAGING_DIR"
export STAGING_PUBLIC_KEYRING="$TMP_TEST_DIR/staging-keyring.gpg"
export STAGING_KEY_FPR="$STAGING_KEY_FPR"
export EVIDENCE_OUT_DIR="$INFRA_DIR/results/$STAGING_RUN_ID"

echo "[INFO] Running non-simulated Preflight..."
bash "$INFRA_DIR/scripts/preflight.sh" "$GCP_PROJECT_ID"

echo "[INFO] Running non-simulated Configure Repository..."
bash "$INFRA_DIR/scripts/configure-repository.sh"

echo "[INFO] Running non-simulated Client Validation..."
bash "$INFRA_DIR/scripts/validate-client.sh"

echo "[INFO] Running non-simulated Promotion Validation..."
bash "$INFRA_DIR/scripts/validate-promotion.sh"

echo "[INFO] Running non-simulated Snapshot Validation..."
bash "$INFRA_DIR/scripts/validate-snapshot.sh"

echo "[INFO] Running non-simulated Rollback Validation..."
bash "$INFRA_DIR/scripts/validate-rollback.sh"

echo "[INFO] Running non-simulated Tamper Rejection Matrix..."
bash "$INFRA_DIR/scripts/validate-tamper-rejection.sh"

# Create a key backup for key recovery test
export STAGING_KEY_BACKUP="$TMP_TEST_DIR/staging_key_backup.gpg.enc"
docker exec "$HOST_CONTAINER" bash -c "gpg --armor --export-secret-keys '$STAGING_KEY_FPR'" > "$STAGING_KEY_BACKUP"

echo "[INFO] Running non-simulated Key Recovery Drill..."
bash "$INFRA_DIR/scripts/validate-key-recovery.sh"

echo "[INFO] Running non-simulated Key Revocation Drill..."
bash "$INFRA_DIR/scripts/validate-key-revocation.sh"

echo "[INFO] Running Evidence Collection..."
bash "$INFRA_DIR/scripts/collect-evidence.sh" "$GCP_PROJECT_ID"

echo "[PASS] Real non-simulated local integration test suite executed cleanly!"
