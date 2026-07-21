#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS branding packages build orchestrator.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
DEBS_OUTPUT_DIR="$WORKSPACE_DIR/packages/build-debs"

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

# Setup build environment
mkdir -p "$DEBS_OUTPUT_DIR"
rm -f "$DEBS_OUTPUT_DIR"/*.deb

# Install build prerequisites if missing
if ! command -v dpkg-buildpackage &>/dev/null; then
    info "Installing build prerequisites..."
    apt-get update -y
    apt-get install -y build-essential debhelper dpkg-dev apt-utils --no-install-recommends
fi

# Use stable timestamp for reproducibility
export SOURCE_DATE_EPOCH=1784617200

packages=(
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

# Temporarily build in a dedicated clean environment
BUILD_TEMP=$(mktemp -d)
cleanup() {
    rm -rf "$BUILD_TEMP"
}
trap cleanup EXIT

for pkg in "${packages[@]}"; do
    info "Building package: $pkg..."
    
    # Check debian/rules executable flag
    chmod +x "$WORKSPACE_DIR/packages/$pkg/debian/rules"
    
    # Copy package source to temp build dir
    cp -r "$WORKSPACE_DIR/packages/$pkg" "$BUILD_TEMP/"
    
    (
        cd "$BUILD_TEMP/$pkg"
        # Run package build
        dpkg-buildpackage -us -uc -b
    )
    
    # Locate built deb
    deb_file=$(find "$BUILD_TEMP" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    if [[ -z "$deb_file" ]]; then
        fail "Could not find built deb for $pkg"
    fi
    
    # Quality control inspections
    info "Running quality checks for $pkg..."
    
    # 1. dpkg-deb --info
    info "--- dpkg-deb --info ($pkg) ---"
    dpkg-deb --info "$deb_file"
    
    # 2. dpkg-deb --contents
    info "--- dpkg-deb --contents ($pkg) ---"
    dpkg-deb --contents "$deb_file"
    
    # 3. Verify version (should be 0.2.0-alpha-1)
    version=$(dpkg-deb --info "$deb_file" | grep -i "Version:" | awk '{print $2}')
    if [[ "$version" != "0.2.0-alpha-1" ]]; then
        fail "Package version is $version, expected 0.2.0-alpha-1"
    fi
    
    # 4. Verify architecture
    arch=$(dpkg-deb --info "$deb_file" | grep -i "Architecture:" | awk '{print $2}')
    if [[ "$arch" != "all" ]]; then
        fail "Package architecture is $arch, expected all"
    fi
    
    # 5. Run lintian if available
    if command -v lintian &>/dev/null; then
        info "Running lintian..."
        lintian "$deb_file" || true
    else
        info "lintian not available, skipping lintian check."
    fi
    
    # Record and save built package
    target_deb="$DEBS_OUTPUT_DIR/$(basename "$deb_file")"
    cp "$deb_file" "$target_deb"
    
    # Record SHA-256
    sha256=$(sha256sum "$target_deb" | awk '{print $1}')
    info "Generated: $(basename "$target_deb")"
    info "SHA-256: $sha256"
    pass "$pkg build and checks completed successfully."
done

# Output summary
info "List of built packages:"
ls -lh "$DEBS_OUTPUT_DIR"
pass "All branding packages built and validated successfully."
