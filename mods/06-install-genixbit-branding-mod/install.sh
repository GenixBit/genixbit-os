#!/usr/bin/env bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

print_ok "Installing native GenixBit desktop packages..."

# Keep this list limited to the live desktop foundation. AI/runtime/profile
# packages are installed by their dedicated build paths and should not become
# accidental dependencies of every local desktop image.
packages=(
    "genixbit-os-archive-keyring"
    "genixbit-os-apt-config"
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-icons"
    "genixbit-os-desktop"
)

DEBS_DIR="/root/debs"
deb_files=()

for pkg in "${packages[@]}"; do
    mapfile -t matches < <(find "$DEBS_DIR" -maxdepth 1 -type f -name "${pkg}_*.deb" -print | sort)
    if [[ ${#matches[@]} -ne 1 ]]; then
        print_error "Expected exactly one built deb for $pkg, found ${#matches[@]}"
        printf '  %s\n' "${matches[@]:-}" >&2
        exit 1
    fi
    deb_files+=("${matches[0]}")
done

# Install the native packages together so APT can resolve their Ubuntu runtime
# dependencies atomically instead of leaving a half-configured dpkg state.
apt-get install -y --no-install-recommends "${deb_files[@]}"
judge "Install native GenixBit desktop packages"

# Do not install genixbit-os-installer-config in upstream/local builds yet. The
# current package contains GenixBit branding assets but not a complete native
# Calamares module stack. Replacing the temporary compatibility installer before
# that stack is complete would leave the live image without a dependable installer.

print_ok "Verifying package manager states..."
dpkg --audit
judge "Verify dpkg audit"

apt-get check
judge "Verify apt check"

print_ok "Native GenixBit desktop packages installed successfully."
