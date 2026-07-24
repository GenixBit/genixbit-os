#!/usr/bin/env bash
set -e                  # exit on error

set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

wait_network

print_ok "Installing capser (live-boot)..."
apt install $INTERACTIVE \
    casper \
    discover \
    laptop-detect \
    os-prober \
    keyutils \
    --no-install-recommends
judge "Install live-boot"

print_ok "Installing kernel..."
apt install $INTERACTIVE \
    linux-image-generic-hwe-26.04 \
    linux-headers-generic-hwe-26.04 \
    --no-install-recommends
judge "Install kernel"

mode="${PACKAGE_SOURCE_MODE:-upstream}"

if [[ "$mode" == "upstream" ]]; then
    print_ok "Installing anduinos-desktop (full Upstream AnduinOS desktop metapackage)..."
    apt install $INTERACTIVE \
        anduinos-desktop \
        anduinos-desktop-apps \
        anduinos-gnome-extensions \
        anduinos-appstore \
        anduinos-theme \
        anduinos-wallpapers \
        anduinos-fonts \
        anduinos-no-snapd \
        anduinos-session \
        anduinos-software-properties-common \
        anduinos-software-properties-gtk \
        anduinos-system-tweaks \
        firefox-anduinos \
        gnome-shell-extension-appindicator-anduinos \
        gnome-shell-extension-dash-to-panel-anduinos \
        gnome-shell-extension-desktop-icons-ng-anduinos \
        plymouth-anduinos \
        alsa-ucm-conf-anduinos \
        firmware-sof-anduinos \
        initramfs-tools \
        --install-recommends
    judge "Install anduinos-desktop"

    print_ok "Installing AnduinOS installer config..."
    apt install $INTERACTIVE anduinos-installer-config --no-install-recommends
    judge "Install anduinos-installer-config"

elif [[ "$mode" == "genixbit-staging" ]]; then
    print_ok "Installing genixbit-os-desktop (full GenixBit OS desktop metapackage)..."
    apt install $INTERACTIVE \
        genixbit-os-desktop \
        genixbit-os-theme \
        genixbit-os-wallpapers \
        initramfs-tools \
        --install-recommends
    judge "Install genixbit-os-desktop"

    print_ok "Installing GenixBit OS installer config..."
    apt install $INTERACTIVE genixbit-os-installer-config --no-install-recommends
    judge "Install genixbit-os-installer-config"
else
    echo "Error: Invalid PACKAGE_SOURCE_MODE: $mode" >&2
    exit 1
fi


