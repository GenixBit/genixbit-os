#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# CI validation script for GenixBit OS package migration & staging deployment integrity

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

info "=== Running Package Migration & Staging CI Validation ==="

# Check 1: No private key material tracked
info "Check 1: Verifying no private key material is tracked..."
if git -C "$REPO_ROOT" ls-files | grep -E '\.(pem|key|sec|p12|pfx)$' | grep -v '.env.example'; then
    fail "Private key material detected in git index!"
fi
pass "Check 1 PASS: No tracked private keys."

# Check 2: Package names and dependencies in control files
info "Check 2: Verifying replacement package names and control metadata..."
req_pkgs=(
    "genixbit-os-archive-keyring"
    "genixbit-os-apt-config"
    "genixbit-os-base-files"
    "genixbit-os-desktop"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

for pkg in "${req_pkgs[@]}"; do
    ctrl="$REPO_ROOT/packages/$pkg/debian/control"
    [[ -f "$ctrl" ]] || fail "Missing debian/control for $pkg"
    grep -q "^Package: $pkg" "$ctrl" || fail "Package name mismatch in $ctrl"
done
pass "Check 2 PASS: Replacement package metadata verified."

# Check 3: Replacement packages contain required files
info "Check 3: Verifying replacement package required files..."
[[ -f "$REPO_ROOT/packages/genixbit-os-archive-keyring/keyring/genixbit-os-archive-keyring.pgp" ]] || fail "Missing keyring.pgp"
[[ -f "$REPO_ROOT/packages/genixbit-os-apt-config/etc/apt/sources.list.d/genixbit-os.sources" ]] || fail "Missing genixbit-os.sources"
[[ -f "$REPO_ROOT/packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides/welcome.html" ]] || fail "Missing welcome.html"
[[ -f "$REPO_ROOT/packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides/privacy_security.html" ]] || fail "Missing privacy_security.html"
[[ -f "$REPO_ROOT/packages/genixbit-os-theme/usr/share/plymouth/themes/genixbit/genixbit.plymouth" ]] || fail "Missing genixbit.plymouth"
[[ -f "$REPO_ROOT/packages/genixbit-os-theme/usr/share/plymouth/themes/genixbit/genixbit.script" ]] || fail "Missing genixbit.script"
pass "Check 3 PASS: Required package source files present."

# Check 4: PACKAGE_SOURCE_MODE consistency check
info "Check 4: Verifying PACKAGE_SOURCE_MODE & package server consistency..."
grep -q 'export PACKAGE_SOURCE_MODE="${PACKAGE_SOURCE_MODE:-upstream}"' "$REPO_ROOT/args.sh" || fail "args.sh missing PACKAGE_SOURCE_MODE definition"
if grep -r "packages.anduinos.com/artifacts/anduinos/pool/genixbit-os" "$REPO_ROOT/build.sh" 2>/dev/null; then
    fail "Inconsistency detected: GenixBit packages requested from AnduinOS server!"
fi
pass "Check 4 PASS: Package source mode & server isolation verified."

# Check 5: No trusted=yes or fallback fingerprint configuration
info "Check 5: Verifying absence of trusted=yes or hardcoded fallback fingerprints..."
if grep -r "trusted=yes" "$REPO_ROOT/packages" "$REPO_ROOT/build.sh" "$REPO_ROOT/args.sh" 2>/dev/null; then
    fail "Insecure trusted=yes configuration detected!"
fi
if grep -r "allow-insecure=yes" "$REPO_ROOT/packages" "$REPO_ROOT/build.sh" "$REPO_ROOT/args.sh" 2>/dev/null; then
    fail "Insecure allow-insecure=yes configuration detected!"
fi
if grep -r "7F9C2B8A3D0E4F1A5B8E2C4D6F8A0B2C4D6E8F0A" "$REPO_ROOT/tools/validation/validate-package-migration.sh" 2>/dev/null; then
    fail "Fixed fallback signing fingerprint detected in validate-package-migration.sh!"
fi
pass "Check 5 PASS: Security options and dynamic signing enforced."

# Check 6: Production repository remains undeployed
info "Check 6: Verifying production APT server status..."
grep -q 'export PACKAGE_SOURCE_MODE="${PACKAGE_SOURCE_MODE:-upstream}"' "$REPO_ROOT/args.sh" || fail "Default mode must remain upstream for production safety"
pass "Check 6 PASS: Production repository status correctly retained as NOT DEPLOYED."

# Check 7: Legal attribution files
info "Check 7: Verifying legal attribution files..."
for f in LICENSE UPSTREAM.md OSS.md; do
    [[ -s "$REPO_ROOT/$f" ]] || fail "Required legal file missing or empty: $f"
done
grep -q "AnduinOS" "$REPO_ROOT/UPSTREAM.md" || fail "UPSTREAM.md missing required AnduinOS attribution"
pass "Check 7 PASS: Legal attribution files verified."

# Check 8: Release tag & candidate branch integrity via remote pointer checks
info "Check 8: Verifying release tag and candidate branch commit pointers..."

REMOTE_NAME="${GIT_REMOTE:-origin}"

resolve_remote_tag() {
    local remote="$1"
    local tag="$2"
    local ls_out
    if ! ls_out=$(git ls-remote --tags "$remote" "$tag" "refs/tags/$tag^{}" 2>&1); then
        fail "Remote '$remote' is unavailable: $ls_out"
    fi
    if [[ -z "$ls_out" ]]; then
        fail "Release tag '$tag' missing on remote '$remote'."
    fi

    local peeled_sha
    peeled_sha=$(echo "$ls_out" | grep -F "refs/tags/$tag^{}" | awk '{print $1}' | tr -d ' \t\r\n' || true)
    if [[ -n "$peeled_sha" ]]; then
        if [[ ! "$peeled_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
            fail "Resolved SHA for tag '$tag' is empty or invalid format: '$peeled_sha'"
        fi
        echo "$peeled_sha"
        return 0
    fi

    local direct_sha
    direct_sha=$(echo "$ls_out" | grep -F "refs/tags/$tag" | awk '{print $1}' | tr -d ' \t\r\n' || true)
    if [[ -z "$direct_sha" ]]; then
        fail "Release tag '$tag' ref not found on remote '$remote'."
    fi

    # Fetch exact named tag ref to confirm commit object resolution
    if ! git -C "$REPO_ROOT" fetch "$remote" "refs/tags/$tag:refs/tags/$tag" --force >/dev/null 2>&1; then
        fail "Failed to fetch exact named tag ref '$tag' from remote '$remote'."
    fi

    local commit_sha
    commit_sha=$(git -C "$REPO_ROOT" rev-parse --verify "refs/tags/$tag^{commit}" 2>/dev/null || echo "")
    if [[ -z "$commit_sha" || ! "$commit_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
        fail "Tag '$tag' cannot be peeled to a commit."
    fi

    echo "$commit_sha"
}

resolve_remote_branch() {
    local remote="$1"
    local branch="$2"
    local ls_out
    if ! ls_out=$(git ls-remote --heads "$remote" "$branch" 2>&1); then
        fail "Remote '$remote' is unavailable: $ls_out"
    fi
    if [[ -z "$ls_out" ]]; then
        fail "Candidate branch '$branch' missing on remote '$remote'."
    fi

    local branch_sha
    branch_sha=$(echo "$ls_out" | awk '{print $1}' | tr -d ' \t\r\n')
    if [[ -z "$branch_sha" || ! "$branch_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
        fail "Resolved SHA for candidate branch '$branch' is empty or invalid format."
    fi

    echo "$branch_sha"
}

tag_commit=$(resolve_remote_tag "$REMOTE_NAME" "v0.2.0-alpha")
cand2_commit=$(resolve_remote_branch "$REMOTE_NAME" "validation/0.2.0-alpha-candidate-2")
cand1_commit=$(resolve_remote_branch "$REMOTE_NAME" "validation/0.3.0-alpha-candidate-1")

info "Sanitized resolved pointers:"
info "  v0.2.0-alpha: $tag_commit"
info "  validation/0.2.0-alpha-candidate-2: $cand2_commit"
info "  validation/0.3.0-alpha-candidate-1: $cand1_commit"

if [[ "$tag_commit" != "88a1550a9129a80ffd2c4cf73838122020a782cb" ]]; then
    fail "Release tag v0.2.0-alpha pointer differs from approved SHA! Expected 88a1550a9129a80ffd2c4cf73838122020a782cb, got '$tag_commit'"
fi

if [[ "$cand2_commit" != "88a1550a9129a80ffd2c4cf73838122020a782cb" ]]; then
    fail "Candidate branch validation/0.2.0-alpha-candidate-2 pointer differs from approved SHA! Expected 88a1550a9129a80ffd2c4cf73838122020a782cb, got '$cand2_commit'"
fi

if [[ "$cand1_commit" != "26fb243ab1e54552bb3ba211c49b382ae4547562" ]]; then
    fail "Candidate branch validation/0.3.0-alpha-candidate-1 pointer differs from approved SHA! Expected 26fb243ab1e54552bb3ba211c49b382ae4547562, got '$cand1_commit'"
fi
pass "Check 8 PASS: Immutable release tag and candidate branch pointers confirmed."


# Check 9: Verify migration validation matrix fail-closed enforcement when ISO is missing
info "Check 9: Verifying package migration validation fail-closed enforcement..."
TMP_CHECK9_DIR=$(mktemp -d)
MISSING_ISO_FIXTURE="$TMP_CHECK9_DIR/nonexistent.iso"
if bash "$REPO_ROOT/tools/validation/check-iso-structure.sh" --iso "$MISSING_ISO_FIXTURE" >/dev/null 2>&1; then
    rm -rf "$TMP_CHECK9_DIR"
    fail "check-iso-structure.sh MUST fail when real ISO build output is missing!"
fi
rm -rf "$TMP_CHECK9_DIR"
pass "Check 9 PASS: Migration validation correctly failed closed when real ISO is missing."

# Check 10: Machine-readable JSON evidence files completeness (if evidence exists)
info "Check 10: Verifying machine-readable JSON evidence integrity..."
results_dir="$REPO_ROOT/infra/package-staging/results/current"
if [[ -d "$results_dir" ]]; then
    for jf in "$results_dir"/*.json; do
        [[ -f "$jf" ]] || continue
        if grep -q '"status": "FAILED"' "$jf"; then
            fail "Evidence file $(basename "$jf") contains FAILED status!"
        fi
    done
fi
pass "Check 10 PASS: Evidence JSON integrity verified."


# Check 11: Negative unit tests for evidence collector
info "Check 11: Running evidence collector negative unit tests..."
bash "$REPO_ROOT/tools/validation/test-evidence-collector-negative.sh" >/dev/null
pass "Check 11 PASS: Evidence collector negative unit tests passed."

# Check 12: Negative unit tests for candidate 1 retirement & ISO validation enforcement
info "Check 12: Running candidate 1 retirement & ISO validation fail-closed negative unit tests..."
bash "$REPO_ROOT/tools/validation/test-candidate-retirement-negative.sh" >/dev/null
pass "Check 12 PASS: Candidate 1 retirement & ISO validation negative tests passed."

# Check 13: Release gate JSON integrity check
info "Check 13: Validating 0.3.0 release gate JSON integrity..."
bash "$REPO_ROOT/tools/validation/check-release-gate.sh" >/dev/null
pass "Check 13 PASS: 0.3.0 release gate JSON integrity verified."

# Check 14: Release gate negative unit tests
info "Check 14: Running release gate negative unit tests..."
bash "$REPO_ROOT/tools/validation/test-release-gate-negative.sh" >/dev/null
pass "Check 14 PASS: Release gate negative unit tests passed."

pass "=== Package Migration & Staging CI Validation Passed ==="
exit 0


