#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# CI validation script for GenixBit OS package migration integrity

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

info "=== Running Package Migration CI Validation ==="

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

# Check 4: No trusted=yes configuration
info "Check 4: Verifying absence of trusted=yes configuration..."
if grep -r "trusted=yes" "$REPO_ROOT/packages" "$REPO_ROOT/build.sh" "$REPO_ROOT/args.sh" 2>/dev/null; then
    fail "Insecure trusted=yes configuration detected!"
fi
pass "Check 4 PASS: No trusted=yes configuration."

# Check 5: No accidental production repository switch
info "Check 5: Verifying production APT server status..."
grep -q 'APKG_SERVER="https://packages.anduinos.com"' "$REPO_ROOT/args.sh" || fail "Production APKG_SERVER was prematurely switched"
pass "Check 5 PASS: Production package server status correctly retained."

# Check 6: Preserved upstream legal attribution
info "Check 6: Verifying legal attribution files..."
for f in LICENSE UPSTREAM.md OSS.md; do
    [[ -s "$REPO_ROOT/$f" ]] || fail "Required legal file missing or empty: $f"
done
grep -q "AnduinOS" "$REPO_ROOT/UPSTREAM.md" || fail "UPSTREAM.md missing required AnduinOS attribution"
pass "Check 6 PASS: Legal attribution files verified."

# Check 7: Installer source contains no user-visible AnduinOS branding
info "Check 7: Verifying installer slideshow branding..."
inst_dir="$REPO_ROOT/packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides"
if grep -r -i "Welcome to AnduinOS" "$inst_dir" 2>/dev/null; then
    fail "User-visible 'Welcome to AnduinOS' text found in installer slides!"
fi
grep -q "Welcome to GenixBit OS" "$inst_dir/welcome.html" || fail "Installer welcome.html missing GenixBit branding"
pass "Check 7 PASS: Installer slideshow branding clean."

# Check 8: Run migration validation suite
info "Check 8: Running full migration validation matrix..."
bash "$REPO_ROOT/tools/validation/validate-package-migration.sh" >/dev/null
pass "Check 8 PASS: Migration validation suite passed."

pass "=== Package Migration CI Validation Passed ==="
exit 0
