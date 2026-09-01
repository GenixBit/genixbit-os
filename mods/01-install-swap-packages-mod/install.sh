#!/usr/bin/env bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

mode="${PACKAGE_SOURCE_MODE:-local}"

if [[ "$mode" == "local" ]]; then
    # Keep the early chroot as a clean Ubuntu base. Locally built GenixBit
    # packages are installed together later by mod 06 so APT can resolve their
    # relationships atomically without pulling a derivative distribution stack.
    print_ok "Keeping Ubuntu base packages until native GenixBit package installation."
elif [[ "$mode" == "genixbit-staging" ]]; then
    print_ok "Installing GenixBit OS APT configuration and keyring packages (mode: genixbit-staging)..."
    apt install $INTERACTIVE \
        "$APT_CONFIG_PACKAGE" \
        genixbit-os-archive-keyring \
        genixbit-os-base-files
    judge "Install GenixBit OS basic packages"
else
    echo "Error: Invalid PACKAGE_SOURCE_MODE: $mode" >&2
    exit 1
fi
