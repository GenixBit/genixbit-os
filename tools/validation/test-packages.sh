#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Automate building and validating GenixBit OS branding packages.

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

# Ensure we are running on a Debian/Ubuntu system
if ! command -v dpkg-buildpackage &>/dev/null; then
    info "Installing build dependencies..."
    apt-get update
    apt-get install -y debhelper dpkg-dev apt-utils
fi

PACKAGES_DIR="packages"
BUILD_TEMP=$(mktemp -d)
cleanup() {
    rm -rf "$BUILD_TEMP"
}
trap cleanup EXIT

# 1. BUILD PACKAGES
info "Building packages..."
packages=(
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

# Set debian/rules files to executable first
for pkg in "${packages[@]}"; do
    chmod +x "$PACKAGES_DIR/$pkg/debian/rules"
done

for pkg in "${packages[@]}"; do
    info "Building $pkg..."
    # Copy source to temp build dir to avoid polluting workspace
    cp -r "$PACKAGES_DIR/$pkg" "$BUILD_TEMP/"
    (
        cd "$BUILD_TEMP/$pkg"
        dpkg-buildpackage -us -uc -b
    )
    pass "Successfully built $pkg"
done

# Check that .deb files are present in the parent directory of temp build dir
ls -l "$BUILD_TEMP"

# 2. VERIFY INSTALLATION
info "Verifying installation..."
for pkg in "${packages[@]}"; do
    deb_file=$(find "$BUILD_TEMP" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    [[ -n "$deb_file" ]] || fail "Could not find built .deb file for $pkg"
    info "Installing $deb_file..."
    dpkg -i "$deb_file"
done

# Verify file existence and branded contents on the system
grep -q 'NAME="GenixBit OS"' /etc/os-release || fail "/etc/os-release does not contain GenixBit OS branding"
[[ -f "/usr/share/pixmaps/genixbit-mark.svg" ]] || fail "/usr/share/pixmaps/genixbit-mark.svg was not installed"
[[ -f "/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg" ]] || fail "Wallpaper was not installed"
[[ -f "/usr/share/genixbit-os-installer-config/slides/welcome.html" ]] || fail "Installer slide was not installed"

pass "All files installed and verified successfully in the correct locations."

# 3. VERIFY UPGRADE
info "Verifying package upgrade..."
# We will simulate an upgrade by rebuilding with a higher version
# We edit changelog of genixbit-os-base-files in the temp directory to add a new version
pkg="genixbit-os-base-files"
ch_path="$BUILD_TEMP/$pkg/debian/changelog"
# Prepend a new changelog entry
cat - "$ch_path" <<'EOF' > "$BUILD_TEMP/new_changelog"
genixbit-os-base-files (0.1.0-alpha-2) resolute; urgency=medium

  * Simulated upgrade entry.

 -- GenixBit Labs Private Limited <maintainers@genixbit.com>  Tue, 21 Jul 2026 02:40:00 +0530

EOF
mv "$BUILD_TEMP/new_changelog" "$ch_path"

(
    cd "$BUILD_TEMP/$pkg"
    dpkg-buildpackage -us -uc -b
)

new_deb=$(find "$BUILD_TEMP" -maxdepth 1 -name "${pkg}_0.1.0-alpha-2_*.deb" | head -n 1)
[[ -n "$new_deb" ]] || fail "Could not find upgraded .deb for $pkg"
info "Upgrading with $new_deb..."
dpkg -i "$new_deb"

# Check version
installed_ver=$(dpkg-query -W -f='${Version}' "$pkg")
if [[ "$installed_ver" != "0.1.0-alpha-2" ]]; then
    fail "Upgrade failed: installed version is $installed_ver, expected 0.1.0-alpha-2"
fi
pass "Package upgrade verified successfully."

# 4. VERIFY ROLLBACK (DOWNGRADE)
info "Verifying package rollback..."
old_deb=$(find "$BUILD_TEMP" -maxdepth 1 -name "${pkg}_0.1.0-alpha-1_*.deb" | head -n 1)
[[ -n "$old_deb" ]] || fail "Could not find older .deb for rollback"
info "Rolling back to $old_deb..."
dpkg -i "$old_deb"

rolled_ver=$(dpkg-query -W -f='${Version}' "$pkg")
if [[ "$rolled_ver" != "0.1.0-alpha-1" ]]; then
    fail "Rollback failed: installed version is $rolled_ver, expected 0.1.0-alpha-1"
fi
pass "Package rollback verified successfully."

# 5. VERIFY REMOVAL
info "Verifying package removal..."
for pkg in "${packages[@]}"; do
    info "Purging $pkg..."
    dpkg -P "$pkg"
done

# Verify file cleanup
[[ ! -f "/etc/os-release" ]] || fail "/etc/os-release was not cleaned up after purge"
[[ ! -f "/usr/share/pixmaps/genixbit-mark.svg" ]] || fail "/usr/share/pixmaps/genixbit-mark.svg was not cleaned up after purge"
[[ ! -f "/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg" ]] || fail "Wallpaper was not cleaned up after purge"
[[ ! -f "/usr/share/genixbit-os-installer-config/slides/welcome.html" ]] || fail "Installer slide was not cleaned up after purge"

pass "All packages removed and cleaned up successfully."
