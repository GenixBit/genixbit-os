#!/bin/bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

print_ok "Building and installing custom GenixBit branding packages..."

# Install build dependencies
apt-get install -y debhelper dpkg-dev --no-install-recommends
judge "Install package build tools"

PACKAGES_DIR="/root/packages"
BUILD_TEMP=$(mktemp -d)
cleanup() {
    rm -rf "$BUILD_TEMP"
}
trap cleanup EXIT

packages=(
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

# Make rules executable
for pkg in "${packages[@]}"; do
    chmod +x "$PACKAGES_DIR/$pkg/debian/rules"
done

# Build packages
for pkg in "${packages[@]}"; do
    print_ok "Building package: $pkg..."
    cp -r "$PACKAGES_DIR/$pkg" "$BUILD_TEMP/"
    (
        cd "$BUILD_TEMP/$pkg"
        dpkg-buildpackage -us -uc -b
    )
    judge "Build package $pkg"
done

# Install built packages
for pkg in "${packages[@]}"; do
    deb_file=$(find "$BUILD_TEMP" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    print_ok "Installing package: $pkg ($deb_file)..."
    dpkg -i "$deb_file"
    judge "Install package $pkg"
done

# Clean up build tools to keep the ISO small
print_ok "Cleaning up package build tools..."
apt-get purge -y debhelper dpkg-dev
apt-get autoremove -y --purge
judge "Clean up package build tools"
