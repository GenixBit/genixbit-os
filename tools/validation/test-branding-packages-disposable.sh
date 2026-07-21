#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS branding packages lifecycle and diversion validator.

set -Eeuo pipefail
IFS=$'\n\t'

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

# 1. SETUP BUILD PREREQUISITES INSIDE CONTAINER
info "Setting up test environment inside container..."
apt-get update -y
apt-get install -y debhelper dpkg-dev apt-utils --no-install-recommends

DEBS_DIR="/workspace/packages/build-debs"
[[ -d "$DEBS_DIR" ]] || fail "Build directory $DEBS_DIR does not exist"

packages=(
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

# Keep track of original Ubuntu base identity contents
orig_os_release=$(cat /etc/os-release)
orig_issue=$(cat /etc/issue)

# Verify no custom files are currently installed
if grep -q "GenixBit" /etc/os-release 2>/dev/null; then
    fail "System already has GenixBit identity before tests"
fi

# Run initial sanity checks
dpkg --audit
apt-get check

# 2. VERIFY CLEAN INSTALLATION
info "Performing clean installation of branding packages..."
for pkg in "${packages[@]}"; do
    deb_file=$(find "$DEBS_DIR" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    [[ -n "$deb_file" ]] || fail "Missing deb file for $pkg"
    info "Installing $deb_file..."
    dpkg -i --force-confnew "$deb_file"
    
    # Run audit checks
    dpkg --audit
    apt-get check
done

pass "All packages installed cleanly."

# 3. VERIFY FILE OWNERSHIP AND DIVERSIONS
info "Verifying file ownership and dpkg-divert states..."
diverted_files=(
    "/usr/lib/os-release"
    "/etc/lsb-release"
    "/etc/issue"
    "/etc/issue.net"
)

for f in "${diverted_files[@]}"; do
    # Check that dpkg-divert output shows our package holds the diversion
    dpkg-divert --list "$f" | grep -q "genixbit-os-base-files" || fail "$f is not diverted by genixbit-os-base-files"
    
    # Verify that dpkg reports our package owns the active file
    dpkg -S "$f" | grep -q "genixbit-os-base-files" || fail "$f is not owned by genixbit-os-base-files in dpkg database"
done

pass "File ownership and diversions verified."

# 4. VERIFY IDENTITY CONTENTS
info "Validating branding identity contents..."
grep -q 'NAME="GenixBit OS"' /etc/os-release || fail "NAME was not updated in /etc/os-release"
grep -q 'VERSION="0.2.0-alpha"' /etc/os-release || fail "VERSION was not updated in /etc/os-release"
grep -q 'VERSION_ID="0.2.0-alpha"' /etc/os-release || fail "VERSION_ID was not updated in /etc/os-release"

# Check icon paths
[[ -f "/usr/share/pixmaps/genixbit-mark.svg" ]] || fail "Theme icon is missing"
[[ -f "/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg" ]] || fail "Dark wallpaper is missing"
[[ -f "/usr/share/genixbit-os-installer-config/slides/welcome.html" ]] || fail "Welcome slide is missing"

pass "Identity contents verified."

# 5. VERIFY UPGRADE
info "Verifying package upgrade cycle..."
# Prepare upgrade deb package by copying base-files source, changing version to 0.2.0-alpha-2
UPGRADE_TEMP=$(mktemp -d)
cp -r /workspace/packages/genixbit-os-base-files "$UPGRADE_TEMP/"
ch_path="$UPGRADE_TEMP/genixbit-os-base-files/debian/changelog"

# Prepend entry
cat - "$ch_path" <<'EOF' > "$UPGRADE_TEMP/new_changelog"
genixbit-os-base-files (0.2.0-alpha-2) resolute; urgency=medium

  * Simulated upgrade build.

 -- GenixBit Labs Private Limited <maintainers@genixbit.com>  Wed, 22 Jul 2026 03:00:00 +0530

EOF
mv "$UPGRADE_TEMP/new_changelog" "$ch_path"

(
    cd "$UPGRADE_TEMP/genixbit-os-base-files"
    chmod +x debian/rules
    dpkg-buildpackage -us -uc -b
)

upgrade_deb=$(find "$UPGRADE_TEMP" -maxdepth 1 -name "genixbit-os-base-files_0.2.0-alpha-2_*.deb" | head -n 1)
[[ -n "$upgrade_deb" ]] || fail "Failed to build upgrade deb package"

info "Upgrading package with $upgrade_deb..."
dpkg -i --force-confnew "$upgrade_deb"

# Check active version and integrity
installed_ver=$(dpkg-query -W -f='${Version}' genixbit-os-base-files)
if [[ "$installed_ver" != "0.2.0-alpha-2" ]]; then
    fail "Upgrade failed: version is $installed_ver, expected 0.2.0-alpha-2"
fi

# Audit checks
dpkg --audit
apt-get check
pass "Package upgrade verified."

# 6. VERIFY ROLLBACK / DOWNGRADE
info "Verifying package rollback (downgrade) cycle..."
old_deb=$(find "$DEBS_DIR" -maxdepth 1 -name "genixbit-os-base-files_0.2.0-alpha-1_*.deb" | head -n 1)
[[ -n "$old_deb" ]] || fail "Could not find old package for rollback"

info "Downgrading to version 0.2.0-alpha-1 using $old_deb..."
dpkg -i --force-confnew "$old_deb"

# Check active version and integrity
rolled_ver=$(dpkg-query -W -f='${Version}' genixbit-os-base-files)
if [[ "$rolled_ver" != "0.2.0-alpha-1" ]]; then
    fail "Rollback failed: version is $rolled_ver, expected 0.2.0-alpha-1"
fi

# Audit checks
dpkg --audit
apt-get check
pass "Package rollback verified."

# 7. VERIFY REMOVAL & PURGE (BASE IDENTITY RESTORATION)
info "Verifying package removal, purge, and identity restoration..."
for pkg in "${packages[@]}"; do
    info "Purging package: $pkg..."
    dpkg -P "$pkg"
    
    # Audit checks
    dpkg --audit
    apt-get check
done

# Confirm original files are restored
if grep -q "GenixBit" /etc/os-release 2>/dev/null; then
    fail "/etc/os-release was not restored to original state"
fi

# Compare the exact content of restored files
restored_os_release=$(cat /etc/os-release)
if [[ "$restored_os_release" != "$orig_os_release" ]]; then
    fail "Restored /etc/os-release contents do not match original"
fi

restored_issue=$(cat /etc/issue)
if [[ "$restored_issue" != "$orig_issue" ]]; then
    fail "Restored /etc/issue contents do not match original"
fi

# Verify no file is left missing
for f in "${diverted_files[@]}"; do
    [[ -f "$f" ]] || fail "Diverted file $f is missing after package purge"
done

# Clean up temp build dirs
rm -rf "$UPGRADE_TEMP"

pass "Package removal and identity restoration verified successfully!"
info "All lifecycle tests PASSED."
exit 0
