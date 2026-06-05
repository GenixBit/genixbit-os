#!/bin/bash
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

# anduinos-desktop pulls in the full AnduinOS identity:
#   anduinos-theme (icons, GTK theme, extensions, dconf, plymouth-anduinos),
#   anduinos-templates, firmware-sof-anduinos, alsa-ucm-conf-anduinos,
#   anduinos-apt-config (already installed in mod 01),
#   base-files (already installed in mod 01)
print_ok "Installing anduinos-desktop (full AnduinOS desktop metapackage)..."
apt install $INTERACTIVE anduinos-desktop
judge "Install anduinos-desktop"
