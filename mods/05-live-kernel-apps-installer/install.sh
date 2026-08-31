#!/usr/bin/env bash
set -e                  # exit on error

set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

wait_network

print_ok "Installing casper (live-boot)..."
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
    print_ok "Installing Ubuntu XFCE desktop foundation for GenixBit OS..."
    apt install $INTERACTIVE \
        xfce4 \
        xfce4-goodies \
        xfce4-terminal \
        lightdm \
        lightdm-gtk-greeter \
        network-manager \
        network-manager-gnome \
        plank \
        pavucontrol \
        gvfs-backends \
        udisks2 \
        xorg \
        dbus-x11 \
        pipewire-audio \
        wireplumber \
        alsa-ucm-conf \
        firmware-sof-signed \
        initramfs-tools \
        --install-recommends
    judge "Install native XFCE desktop foundation"

    # The native GenixBit Calamares configuration is not complete yet. Keep the
    # upstream installer engine/config as a narrow compatibility dependency only;
    # do not pull in the upstream desktop, app store, themes, session, or browser.
    print_ok "Installing temporary installer compatibility package..."
    apt install $INTERACTIVE anduinos-installer-config --no-install-recommends
    judge "Install temporary installer compatibility package"

elif [[ "$mode" == "genixbit-staging" ]]; then
    print_ok "Installing genixbit-os-desktop (full GenixBit OS desktop metapackage)..."
    apt install $INTERACTIVE \
        genixbit-os-desktop \
        genixbit-os-theme \
        genixbit-os-wallpapers \
        genixbit-os-developer-profile \
        genixbit-os-server-profile \
        genixbit-os-creator-profile \
        genixbit-os-gpu-diagnostics \
        genixbit-os-ai-runtime \
        genixbit-os-ai-center \
        genixbit-os-agents \
        genixbit-os-store \
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
