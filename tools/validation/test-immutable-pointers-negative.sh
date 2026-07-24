#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fail-closed negative test suite for immutable remote pointer resolution and git ls-remote validation.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

fail() {
    printf '[FAIL] Immutable Pointers Negative Test Failed: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

info "=== Running Immutable Reference Pointer Validation Negative Tests ==="

TMP_DIR=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Test 1: Unavailable remote handling
info "Test 1: Testing unavailable remote failure..."
if GIT_REMOTE="invalid-nonexistent-remote-host-999" bash "$REPO_ROOT/tools/validation/check-package-migration-ci.sh" >/dev/null 2>&1; then
    fail "check-package-migration-ci.sh failed to reject unavailable remote!"
fi
pass "Test 1 PASS: Unavailable remote correctly rejected."

# Test 2: Missing tag handling
info "Test 2: Testing missing tag failure..."
MISSING_TAG_DIR="$TMP_DIR/missing_tag_repo"
git init --bare "$MISSING_TAG_DIR" >/dev/null 2>&1
if GIT_REMOTE="$MISSING_TAG_DIR" bash "$REPO_ROOT/tools/validation/check-package-migration-ci.sh" >/dev/null 2>&1; then
    fail "check-package-migration-ci.sh failed to reject missing tag on bare remote!"
fi
pass "Test 2 PASS: Missing tag correctly rejected."

# Test 3: Missing candidate branch handling
info "Test 3: Testing missing candidate branch failure..."
PARTIAL_REMOTE="$TMP_DIR/partial_remote"
mkdir -p "$TMP_DIR/src_repo"
(
    cd "$TMP_DIR/src_repo"
    git init >/dev/null
    git config user.name "Test"
    git config user.email "test@example.com"
    git commit --allow-empty -m "initial" >/dev/null
    git tag -a v0.2.0-alpha -m "test tag" >/dev/null
)
git init --bare "$PARTIAL_REMOTE" >/dev/null 2>&1
git -C "$TMP_DIR/src_repo" push "$PARTIAL_REMOTE" refs/tags/v0.2.0-alpha:refs/tags/v0.2.0-alpha >/dev/null 2>&1

if GIT_REMOTE="$PARTIAL_REMOTE" bash "$REPO_ROOT/tools/validation/check-package-migration-ci.sh" >/dev/null 2>&1; then
    fail "check-package-migration-ci.sh failed to reject missing candidate branch!"
fi
pass "Test 3 PASS: Missing candidate branch correctly rejected."

# Test 4: Mismatched/wrong tag SHA handling
info "Test 4: Testing wrong tag SHA failure..."
WRONG_TAG_REMOTE="$TMP_DIR/wrong_tag_remote"
(
    cd "$TMP_DIR/src_repo"
    git checkout -b validation/0.2.0-alpha-candidate-2 >/dev/null 2>&1
    git checkout -b validation/0.3.0-alpha-candidate-1 >/dev/null 2>&1
)
git init --bare "$WRONG_TAG_REMOTE" >/dev/null 2>&1
git -C "$TMP_DIR/src_repo" push "$WRONG_TAG_REMOTE" refs/tags/v0.2.0-alpha:refs/tags/v0.2.0-alpha refs/heads/validation/0.2.0-alpha-candidate-2:refs/heads/validation/0.2.0-alpha-candidate-2 refs/heads/validation/0.3.0-alpha-candidate-1:refs/heads/validation/0.3.0-alpha-candidate-1 >/dev/null 2>&1

if GIT_REMOTE="$WRONG_TAG_REMOTE" bash "$REPO_ROOT/tools/validation/check-package-migration-ci.sh" >/dev/null 2>&1; then
    fail "check-package-migration-ci.sh failed to reject wrong tag SHA!"
fi
pass "Test 4 PASS: Mismatched tag SHA correctly rejected."

# Test 5: Annotated tag peeling verification
info "Test 5: Verifying annotated-tag peeling resolution..."
TAG_PEEL_OUT=$(git ls-remote --tags origin v0.2.0-alpha "refs/tags/v0.2.0-alpha^{}" 2>/dev/null)
if ! echo "$TAG_PEEL_OUT" | grep -q 'refs/tags/v0.2.0-alpha^{}'; then
    fail "v0.2.0-alpha is annotated tag but ls-remote did not return peeled ^{} entry!"
fi
PEELED_SHA=$(echo "$TAG_PEEL_OUT" | grep 'refs/tags/v0.2.0-alpha^{}' | awk '{print $1}')
if [[ "$PEELED_SHA" != "88a1550a9129a80ffd2c4cf73838122020a782cb" ]]; then
    fail "Annotated tag v0.2.0-alpha peeled SHA mismatch! Expected 88a1550a9129a80ffd2c4cf73838122020a782cb, got '$PEELED_SHA'"
fi
pass "Test 5 PASS: Annotated tag peeling correctly resolved to commit object 88a1550a9129a80ffd2c4cf73838122020a782cb."

# Test 6: Verify candidate branch HEAD resolution via git ls-remote --heads
info "Test 6: Verifying remote candidate branch resolution..."
CAND1_OUT=$(git ls-remote --heads origin validation/0.3.0-alpha-candidate-1 2>/dev/null | awk '{print $1}')
if [[ "$CAND1_OUT" != "26fb243ab1e54552bb3ba211c49b382ae4547562" ]]; then
    fail "Candidate 1 branch resolution mismatch! Expected 26fb243ab1e54552bb3ba211c49b382ae4547562, got '$CAND1_OUT'"
fi
pass "Test 6 PASS: Candidate 1 branch correctly resolved via git ls-remote."

# Test 7: Verify shallow checkout compatibility
info "Test 7: Verifying shallow checkout resolution..."
SHALLOW_DIR="$TMP_DIR/shallow_repo"
ORIGIN_URL=$(git -C "$REPO_ROOT" config remote.origin.url || echo "https://github.com/GenixBit/genixbit-os.git")
git clone --depth 1 "$ORIGIN_URL" "$SHALLOW_DIR" >/dev/null 2>&1
cp -r "$REPO_ROOT/tools/validation"/* "$SHALLOW_DIR/tools/validation/"
(
    cd "$SHALLOW_DIR"
    GIT_REMOTE="origin" bash tools/validation/check-package-migration-ci.sh >/dev/null 2>&1 || exit 1
)
pass "Test 7 PASS: Immutable pointers successfully verified in a shallow checkout environment."

# Test 8: Empty resolved SHA rejection
info "Test 8: Testing empty resolved SHA rejection..."
EMPTY_SHA_REMOTE="$TMP_DIR/empty_sha_remote"
git init --bare "$EMPTY_SHA_REMOTE" >/dev/null 2>&1
if GIT_REMOTE="$EMPTY_SHA_REMOTE" bash "$REPO_ROOT/tools/validation/check-release-evidence.sh" --verify-git-candidate >/dev/null 2>&1; then
    fail "check-release-evidence.sh failed to reject empty remote SHA!"
fi
pass "Test 8 PASS: Empty resolved SHA correctly rejected."

pass "=== All Immutable Pointer Negative Tests Passed ==="
exit 0
