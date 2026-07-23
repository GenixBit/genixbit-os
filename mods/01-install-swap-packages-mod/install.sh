#!/bin/bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error
#==========================
# Install AnduinOS swap packages
#==========================

mode="${PACKAGE_SOURCE_MODE:-upstream}"

if [[ "$mode" == "upstream" ]]; then
    print_ok "Installing Upstream AnduinOS APT configuration and keyring packages (mode: upstream)..."
    apt install $INTERACTIVE \
        $APT_CONFIG_PACKAGE \
        anduinos-archive-keyring \
        base-files
    judge "Install Upstream basic packages"
elif [[ "$mode" == "genixbit-staging" ]]; then
    print_ok "Installing GenixBit OS APT configuration and keyring packages (mode: genixbit-staging)..."
    apt install $INTERACTIVE \
        $APT_CONFIG_PACKAGE \
        genixbit-os-archive-keyring \
        base-files
    judge "Install GenixBit OS basic packages"
else
    echo "Error: Invalid PACKAGE_SOURCE_MODE: $mode" >&2
    exit 1
fi





