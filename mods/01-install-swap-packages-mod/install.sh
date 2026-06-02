#!/bin/bash

#==========================
# Install AnduinOS swap packages
#==========================
# These packages share names with Ubuntu packages (base-files,
# plymouth-theme-spinner) and use epoch 1: to guarantee version
# comparison wins against Ubuntu.  APT origin priority 1001 (set
# by anduinos-apt-config) ensures AnduinOS packages are always
# preferred regardless of version.
#
# Why swap instead of a separate branding package:
#   plymouth owns ubuntu-logo.png + watermark.png (shared with theme-spinner)
#   plymouth-theme-spinner owns watermark.png + bgrt-fallback.png
#   Both packages ship the same 3 files across noble/questing/resolute,
#   just split differently per suite. A separate branding package would
#   need to Conflict+Replaces both — messy and fragile.
#
#   By publishing as plymouth-theme-spinner with Replaces: plymouth, dpkg
#   lets us overwrite all 3 files cleanly: ours is the NEW package being
#   installed over both plymouth and plymouth-theme-spinner's old files.
#   Epoch 1: guarantees dpkg version comparison beats ubuntu.
#   APT origin priority 1001 (set by anduinos-apt-config) ensures ours
#   wins regardless. No apt-mark hold / apt preferences hack needed.
#
# Installation order matters:
#   anduinos-apt-config (→ Depends → archive-keyring) must be installed
#   FIRST so that APT pinning is active before the other swap packages
#   are resolved.  The keyring is pulled automatically via Depends.

set -e
set -o pipefail

source /root/mods/shared.sh
source /root/mods/args.sh

print_ok "Installing AnduinOS APT configuration..."

# anduinos-apt-config Depends on anduinos-archive-keyring, so one
# apt install pulls both: keyring → trust → sources → pinning.
apt install -y anduinos-apt-config
judge "Install anduinos-apt-config + anduinos-archive-keyring"

print_ok "Installing AnduinOS swap packages..."

apt install -y plymouth-theme-spinner
judge "Install plymouth-theme-spinner (swap)"

apt install -y base-files
judge "Install base-files (swap)"

apt install -y anduinos-templates
judge "Install anduinos-templates"

apt install -y anduinos-dconf-defaults
judge "Install anduinos-dconf-defaults"

apt install -y anduinos-fluent-icon-theme
judge "Install anduinos-fluent-icon-theme"

apt install -y anduinos-fluent-gtk-theme
judge "Install anduinos-fluent-gtk-theme"

print_ok "Base packages installed."
