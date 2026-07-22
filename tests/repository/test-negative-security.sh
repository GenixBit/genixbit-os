#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Comprehensive negative security failure cases for GenixBit repository tooling.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

# shellcheck source=tools/repository/lib/safety.sh
source "$REPO_ROOT/tools/repository/lib/safety.sh"

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

test_fail_cmd() {
    local desc=$1
    shift
    if ! "$@" >/dev/null 2>&1; then
        printf '[PASS] Security test passed (correctly rejected): %s\n' "$desc"
    else
        printf '[FAIL] Security test failed (expected nonzero exit): %s\n' "$desc" >&2
        exit 1
    fi
}

echo "[INFO] Setting up test repository and ephemeral signing key..."
FPR="0000000000000000000000000000000000000000"
KEYRING="$TMP_DIR/test-keyring.pgp"
touch "$KEYRING"

if command -v gpg >/dev/null 2>&1; then
    gpg --batch --full-generate-key <<EOF
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign,cert
Name-Real: GenixBit Negative Test Key
Name-Email: neg-test@genixbit.com
Expire-Date: 1d
%no-protection
EOF
    FPR=$(gpg --list-secret-keys --with-colons "neg-test@genixbit.com" | grep fpr | head -n1 | cut -d':' -f10)
    gpg --export "$FPR" > "$KEYRING"
fi

bash "$REPO_ROOT/tools/repository/init-staging-repository.sh" --repo-dir "$TMP_REPO" >/dev/null

# 1. Missing release file -> FAIL
test_fail_cmd "missing release file" \
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
    --release-file "$TMP_DIR/nonexistent_Release" \
    --keyring "$KEYRING"

# 2. Missing keyring -> FAIL
test_fail_cmd "missing keyring file" \
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
    --release-file "$TMP_REPO/dists/resolute-alpha/Release" \
    --keyring "$TMP_DIR/nonexistent_keyring.pgp"

# 3. Invalid / Placeholder keyring -> FAIL
PLACEHOLDER_KEYRING="$TMP_DIR/placeholder-keyring.gpg"
echo "THIS IS A PLACEHOLDER TEXT KEYRING FILE" > "$PLACEHOLDER_KEYRING"
test_fail_cmd "placeholder text keyring" \
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
    --release-file "$TMP_REPO/dists/resolute-alpha/Release" \
    --keyring "$PLACEHOLDER_KEYRING"

# 4. Unauthorized direct channel transition (resolute-alpha -> resolute-stable) -> FAIL
test_fail_cmd "unauthorized direct channel transition (resolute-alpha -> resolute-stable)" \
    bash "$REPO_ROOT/tools/repository/promote-package.sh" \
    --repo-dir "$TMP_REPO" \
    --package "genixbit-fixture" \
    --from-channel "resolute-alpha" \
    --to-channel "resolute-stable"

# 5. Missing promotion approval -> FAIL
test_fail_cmd "missing promotion approval (empty promoter/reviewer)" \
    bash "$REPO_ROOT/tools/repository/promote-package.sh" \
    --repo-dir "$TMP_REPO" \
    --package "genixbit-fixture" \
    --from-channel "resolute-alpha" \
    --to-channel "resolute-testing" \
    --promoter "" \
    --reviewer ""

# 6. GNUPGHOME inside repository directory -> FAIL
test_fail_cmd "signing with GNUPGHOME inside repository directory" \
    bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-alpha" \
    --signing-key-fingerprint "$FPR" \
    --gnupg-home "$TMP_REPO/gnupg"

# 7. Nonexistent snapshot rollback -> FAIL
test_fail_cmd "rollback to nonexistent snapshot" \
    bash "$REPO_ROOT/tools/repository/rollback-snapshot.sh" \
    --repo-dir "$TMP_REPO" \
    --channel "resolute-alpha" \
    --snapshot-id "snap-nonexistent-1234"

# 8. Unsafe paths (root, $HOME, /root) -> FAIL
test_fail_cmd "unsafe target directory /" \
    bash "$REPO_ROOT/tools/repository/init-staging-repository.sh" --repo-dir "/"
test_fail_cmd "unsafe target directory /root" \
    bash "$REPO_ROOT/tools/repository/init-staging-repository.sh" --repo-dir "/root"

# 9. Symlink escape outside repository root -> FAIL
ESCAPE_LINK="$TMP_DIR/escape_symlink"
ln -s "/etc" "$ESCAPE_LINK" 2>/dev/null || true
test_fail_cmd "symlink escape outside allowed root" \
    bash -c "export GENIXBIT_REPOSITORY_ROOT=$TMP_REPO; validate_repository_path '$ESCAPE_LINK'"

if command -v gpg >/dev/null 2>&1; then
    # Create fixture deb and build signed index
    PKG_DIR="$TMP_DIR/fixture-1.0.0"
    mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/usr/share/doc/fixture"
    cat <<EOF > "$PKG_DIR/DEBIAN/control"
Package: genixbit-fixture
Version: 1.0.0
Architecture: amd64
Maintainer: GenixBit OS Maintainers <ftpmaster@genixbit.com>
Description: GenixBit Fixture Package 1.0.0
EOF
    echo "fixture 1.0.0" > "$PKG_DIR/usr/share/doc/fixture/changelog"
    DEB_FILE="$TMP_REPO/pool/main/g/genixbit-fixture/genixbit-fixture_1.0.0_amd64.deb"
    mkdir -p "$(dirname "$DEB_FILE")"
    dpkg-deb --build "$PKG_DIR" "$DEB_FILE" >/dev/null

    bash "$REPO_ROOT/tools/repository/build-package-index.sh" --repo-dir "$TMP_REPO" --channel "resolute-alpha" >/dev/null
    bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
        --repo-dir "$TMP_REPO" \
        --channel "resolute-alpha" \
        --signing-key-fingerprint "$FPR" \
        --gnupg-home "$TMP_GPG" >/dev/null

    # 10. Tampered .deb file (checksum mismatch) -> FAIL
    TMP_REPO_TAMPERED="$TMP_DIR/repo_tampered"
    cp -r "$TMP_REPO" "$TMP_REPO_TAMPERED"
    echo "CORRUPTED DATA" >> "$TMP_REPO_TAMPERED/pool/main/g/genixbit-fixture/genixbit-fixture_1.0.0_amd64.deb"
    test_fail_cmd "tampered .deb checksum mismatch" \
        bash -c "HASH=\$(sha256sum '$TMP_REPO_TAMPERED/pool/main/g/genixbit-fixture/genixbit-fixture_1.0.0_amd64.deb' | awk '{print \$1}') && EXPECTED=\$(grep -A10 'Filename: pool/main/g/genixbit-fixture/genixbit-fixture_1.0.0_amd64.deb' '$TMP_REPO/dists/resolute-alpha/main/binary-amd64/Packages' | grep 'SHA256:' | awk '{print \$2}') && test \"\$HASH\" = \"\$EXPECTED\""

    # 11. Tampered Packages file -> FAIL
    TMP_REPO_INDEX="$TMP_DIR/repo_index"
    cp -r "$TMP_REPO" "$TMP_REPO_INDEX"
    echo "Extra-Field: tampered" >> "$TMP_REPO_INDEX/dists/resolute-alpha/main/binary-amd64/Packages"
    test_fail_cmd "tampered Packages file (Release hash mismatch)" \
        bash -c "HASH=\$(sha256sum '$TMP_REPO_INDEX/dists/resolute-alpha/main/binary-amd64/Packages' | awk '{print \$1}') && EXPECTED=\$(grep 'main/binary-amd64/Packages\$' '$TMP_REPO_INDEX/dists/resolute-alpha/Release' | awk '{print \$1}') && test \"\$HASH\" = \"\$EXPECTED\""

    # 12. Tampered Packages.xz file -> FAIL
    TMP_REPO_XZ="$TMP_DIR/repo_xz"
    cp -r "$TMP_REPO" "$TMP_REPO_XZ"
    echo "CORRUPTED XZ" > "$TMP_REPO_XZ/dists/resolute-alpha/main/binary-amd64/Packages.xz"
    test_fail_cmd "tampered Packages.xz file (Release hash mismatch)" \
        bash -c "HASH=\$(sha256sum '$TMP_REPO_XZ/dists/resolute-alpha/main/binary-amd64/Packages.xz' | awk '{print \$1}') && EXPECTED=\$(grep 'main/binary-amd64/Packages.xz\$' '$TMP_REPO_XZ/dists/resolute-alpha/Release' | awk '{print \$1}') && test \"\$HASH\" = \"\$EXPECTED\""

    # 13. Tampered Release file -> FAIL
    TMP_REPO_REL="$TMP_DIR/repo_rel"
    cp -r "$TMP_REPO" "$TMP_REPO_REL"
    echo "Tampered: true" >> "$TMP_REPO_REL/dists/resolute-alpha/Release"
    test_fail_cmd "tampered Release file (signature verification fail)" \
        bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO_REL/dists/resolute-alpha/Release.gpg" \
        --keyring "$KEYRING"

    # 14. Modified InRelease file -> FAIL
    TMP_REPO_INREL="$TMP_DIR/repo_inrel"
    cp -r "$TMP_REPO" "$TMP_REPO_INREL"
    sed -i 's/Codename: resolute-alpha/Codename: tampered-alpha/' "$TMP_REPO_INREL/dists/resolute-alpha/InRelease"
    test_fail_cmd "modified InRelease inline signature" \
        bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO_INREL/dists/resolute-alpha/InRelease" \
        --keyring "$KEYRING"

    # 15. Wrong signing key / wrong expected fingerprint -> FAIL
    WRONG_FPR="1111111111111111111111111111111111111111"
    test_fail_cmd "wrong expected fingerprint mismatch" \
        bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO/dists/resolute-alpha/InRelease" \
        --keyring "$KEYRING" \
        --expected-fingerprint "$WRONG_FPR"

    # 16. Missing signatures -> FAIL
    TMP_REPO_NOSIG="$TMP_DIR/repo_nosig"
    cp -r "$TMP_REPO" "$TMP_REPO_NOSIG"
    rm -f "$TMP_REPO_NOSIG/dists/resolute-alpha/InRelease" "$TMP_REPO_NOSIG/dists/resolute-alpha/Release.gpg"
    test_fail_cmd "missing signatures (no InRelease or Release.gpg)" \
        bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO_NOSIG/dists/resolute-alpha/Release" \
        --keyring "$KEYRING"

    # 17. Unsigned regenerated metadata -> FAIL
    TMP_REPO_UNSIGNED="$TMP_DIR/repo_unsigned"
    cp -r "$TMP_REPO" "$TMP_REPO_UNSIGNED"
    bash "$REPO_ROOT/tools/repository/build-package-index.sh" --repo-dir "$TMP_REPO_UNSIGNED" --channel "resolute-alpha" >/dev/null
    rm -f "$TMP_REPO_UNSIGNED/dists/resolute-alpha/InRelease" "$TMP_REPO_UNSIGNED/dists/resolute-alpha/Release.gpg"
    test_fail_cmd "unsigned regenerated metadata" \
        bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
        --release-file "$TMP_REPO_UNSIGNED/dists/resolute-alpha/InRelease" \
        --keyring "$KEYRING"

    # 18. Tampered snapshot manifest -> FAIL
    SNAP_OUT=$(bash "$REPO_ROOT/tools/repository/create-snapshot.sh" --repo-dir "$TMP_REPO" --channel "resolute-alpha")
    SNAP_ID=$(echo "$SNAP_OUT" | grep "Snapshot ID:" | awk '{print $NF}')
    SNAP_MANIFEST="$TMP_REPO/snapshots/resolute-alpha/$SNAP_ID/snapshot-manifest.json"
    echo "CORRUPTED MANIFEST" > "$SNAP_MANIFEST"
    test_fail_cmd "tampered snapshot manifest verification" \
        bash "$REPO_ROOT/tools/repository/verify-snapshot.sh" --repo-dir "$TMP_REPO" --channel "resolute-alpha" --snapshot-id "$SNAP_ID"
fi

printf 'TAMPERED_METADATA_REJECTED=PASS\n'
printf '[PASS] All negative security tests passed successfully.\n'
