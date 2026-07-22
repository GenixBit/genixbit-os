#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Test negative security failure cases for repository tooling.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

# 1. Missing release file -> FAIL
test_fail_cmd "verify signature with missing release file" \
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
    --release-file "$TMP_DIR/nonexistent_Release" \
    --keyring "$TMP_DIR/keyring.pgp"

# 2. Invalid keyring -> FAIL
touch "$TMP_DIR/bad_keyring.pgp"
echo "not a gpg key" > "$TMP_DIR/bad_keyring.pgp"
test_fail_cmd "verify signature with invalid keyring" \
    bash "$REPO_ROOT/tools/repository/verify-release-signature.sh" \
    --release-file "$TMP_DIR/nonexistent_Release" \
    --keyring "$TMP_DIR/bad_keyring.pgp"

# 3. Direct unauthorized channel transition (alpha -> stable without emergency override) -> FAIL
REPO_DIR="$TMP_DIR/repo"
bash "$REPO_ROOT/tools/repository/init-staging-repository.sh" --repo-dir "$REPO_DIR" >/dev/null
test_fail_cmd "unauthorized direct channel transition (resolute-alpha -> resolute-stable)" \
    bash "$REPO_ROOT/tools/repository/promote-package.sh" \
    --repo-dir "$REPO_DIR" \
    --package "genixbit-test" \
    --from-channel "resolute-alpha" \
    --to-channel "resolute-stable"

# 4. GNUPGHOME inside repository directory -> FAIL
test_fail_cmd "signing with GNUPGHOME inside repository directory" \
    bash "$REPO_ROOT/tools/repository/sign-release-metadata.sh" \
    --repo-dir "$REPO_DIR" \
    --channel "resolute-alpha" \
    --signing-key-fingerprint "0000000000000000000000000000000000000000" \
    --gnupg-home "$REPO_DIR/gnupg"

# 5. Nonexistent snapshot rollback -> FAIL
test_fail_cmd "rollback to nonexistent snapshot" \
    bash "$REPO_ROOT/tools/repository/rollback-snapshot.sh" \
    --repo-dir "$REPO_DIR" \
    --channel "resolute-alpha" \
    --snapshot-id "snap-nonexistent-1234"

printf '[PASS] All negative security tests passed successfully.\n'
