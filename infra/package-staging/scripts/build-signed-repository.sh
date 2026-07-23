#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Helper script to construct authentic signed APT repository structure for GCP Staging Execution

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$INFRA_DIR/build"

mkdir -p "$BUILD_DIR/gpg" "$BUILD_DIR/repo/pool/main/g/genixbit-repository-fixture" "$BUILD_DIR/repo/dists/resolute-alpha/main/binary-amd64" "$BUILD_DIR/repo/dists/resolute-testing/main/binary-amd64"
chmod 700 "$BUILD_DIR/gpg"

export GNUPGHOME="$BUILD_DIR/gpg"

# 1. Generate OpenPGP Keypair if not present
KEY_PARAMS="$BUILD_DIR/gpg/key_params"
cat << EOF > "$KEY_PARAMS"
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
EOF

gpg --batch --generate-key "$KEY_PARAMS" >/dev/null 2>&1

KEY_FPR=$(gpg --list-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')

PUBLIC_KEYRING="$BUILD_DIR/keyring.gpg"
gpg --export "$KEY_FPR" > "$PUBLIC_KEYRING"

# Helper to build .deb using ar & tar
build_deb() {
    local version="$1"
    local output_deb="$2"
    local stage_dir="$BUILD_DIR/stage_$version"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir/control" "$stage_dir/data/usr/bin" "$stage_dir/data/usr/share/doc/genixbit-repository-fixture"

    echo "2.0" > "$stage_dir/debian-binary"
    cat << EOF > "$stage_dir/control/control"
Package: genixbit-repository-fixture
Version: $version
Architecture: all
Maintainer: GenixBit OS Core Team <packages@genixbit.internal>
Description: GenixBit OS Staging Validation Package Fixture $version
 Section: utils
 Priority: optional
EOF

    cat << EOF > "$stage_dir/data/usr/bin/genixbit-staging-fixture"
#!/bin/sh
echo "GenixBit Staging Package Fixture Version $version"
EOF
    chmod +x "$stage_dir/data/usr/bin/genixbit-staging-fixture"
    echo "GenixBit Fixture $version" > "$stage_dir/data/usr/share/doc/genixbit-repository-fixture/changelog"

    COPYFILE_DISABLE=1 tar -czf "$stage_dir/control.tar.gz" -C "$stage_dir/control" .
    COPYFILE_DISABLE=1 tar -czf "$stage_dir/data.tar.gz" -C "$stage_dir/data" .

    (cd "$stage_dir" && ar rcs "$output_deb" debian-binary control.tar.gz data.tar.gz)
}

DEB_100="$BUILD_DIR/repo/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.0_all.deb"
DEB_101="$BUILD_DIR/repo/pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.1_all.deb"

build_deb "1.0.0" "$DEB_100"
build_deb "1.0.1" "$DEB_101"

# Function to build dist files
build_dist() {
    local suite="$1"
    local dist_dir="$BUILD_DIR/repo/dists/$suite"
    mkdir -p "$dist_dir/main/binary-amd64" "$dist_dir/main/binary-all"

    local deb_path="pool/main/g/genixbit-repository-fixture/genixbit-repository-fixture_1.0.0_all.deb"
    local full_deb="$BUILD_DIR/repo/$deb_path"
    local deb_size deb_md5 deb_sha256
    deb_size=$(wc -c < "$full_deb" | tr -d ' ')
    deb_md5=$(md5 -q "$full_deb" 2>/dev/null || md5sum "$full_deb" | cut -d' ' -f1)
    deb_sha256=$(shasum -a 256 "$full_deb" 2>/dev/null | cut -d' ' -f1 || sha256sum "$full_deb" | cut -d' ' -f1)

    cat << EOF > "$dist_dir/main/binary-amd64/Packages"
Package: genixbit-repository-fixture
Version: 1.0.0
Architecture: all
Maintainer: GenixBit OS Core Team <packages@genixbit.internal>
Installed-Size: 12
Filename: $deb_path
Size: $deb_size
MD5sum: $deb_md5
SHA256: $deb_sha256
Section: utils
Priority: optional
Description: GenixBit OS Staging Validation Package Fixture 1.0.0
EOF

    gzip -9c "$dist_dir/main/binary-amd64/Packages" > "$dist_dir/main/binary-amd64/Packages.gz"
    gzip -9c "$dist_dir/main/binary-amd64/Packages" > "$dist_dir/main/binary-amd64/Packages.xz"

    local pkgs_size pkgs_sha256 pkgs_gz_size pkgs_gz_sha256
    pkgs_size=$(wc -c < "$dist_dir/main/binary-amd64/Packages" | tr -d ' ')
    pkgs_sha256=$(shasum -a 256 "$dist_dir/main/binary-amd64/Packages" | cut -d' ' -f1 || sha256sum "$dist_dir/main/binary-amd64/Packages" | cut -d' ' -f1)
    pkgs_gz_size=$(wc -c < "$dist_dir/main/binary-amd64/Packages.gz" | tr -d ' ')
    pkgs_gz_sha256=$(shasum -a 256 "$dist_dir/main/binary-amd64/Packages.gz" | cut -d' ' -f1 || sha256sum "$dist_dir/main/binary-amd64/Packages.gz" | cut -d' ' -f1)

    cat << EOF > "$dist_dir/Release"
Origin: GenixBit OS
Label: GenixBit Staging
Suite: $suite
Codename: $suite
Architectures: amd64 all
Components: main
Date: $(date -u +"%a, %d %b %Y %H:%M:%S UTC")
SHA256:
 $pkgs_sha256 $pkgs_size main/binary-amd64/Packages
 $pkgs_gz_sha256 $pkgs_gz_size main/binary-amd64/Packages.gz
EOF

    gpg --batch --yes -u "$KEY_FPR" --clearsign -o "$dist_dir/InRelease" "$dist_dir/Release"
    gpg --batch --yes -u "$KEY_FPR" -abs -o "$dist_dir/Release.gpg" "$dist_dir/Release"
}

build_dist "resolute-alpha"
build_dist "resolute-testing"

echo "STAGING_KEY_FPR=$KEY_FPR"
echo "STAGING_PUBLIC_KEYRING=$PUBLIC_KEYRING"
echo "LOCAL_STAGING_DIR=$BUILD_DIR/repo"
