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

print_ok "Installing genixbit-os-desktop (full GenixBit OS desktop metapackage)..."
apt install $INTERACTIVE \
    genixbit-os-desktop \
    genixbit-os-theme \
    genixbit-os-wallpapers \
    initramfs-tools \
    --install-recommends
judge "Install genixbit-os-desktop"

print_ok "Installing GenixBit OS installer (Ubiquity + wrapper + slides + bwrap compat)..."
apt install $INTERACTIVE genixbit-os-installer-config --no-install-recommends
judge "Install genixbit-os-installer-config"

