#!/bin/bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

print_ok "Installing pre-compiled GenixBit branding packages..."

packages=(
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

DEBS_DIR="/root/debs"

for pkg in "${packages[@]}"; do
    deb_file=$(find "$DEBS_DIR" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    if [[ -z "$deb_file" ]]; then
        print_error "Could not find built deb for $pkg"
        exit 1
    fi
    print_ok "Installing package: $pkg ($deb_file)..."
    dpkg -i --force-confnew "$deb_file"
    judge "Install package $pkg"
done

# Perform sanity audit checks inside the target system
print_ok "Verifying package manager states..."
dpkg --audit
judge "Verify dpkg audit"

apt-get check
judge "Verify apt check"

print_ok "GenixBit branding packages installed successfully."

