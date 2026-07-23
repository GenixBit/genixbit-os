#!/bin/bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error
#==========================
# Install AnduinOS swap packages
#==========================

print_ok "Installing GenixBit OS APT configuration and keyring packages..."
apt install $INTERACTIVE \
    $APT_CONFIG_PACKAGE \
    genixbit-os-archive-keyring \
    base-files
judge "Install GenixBit OS basic packages"




