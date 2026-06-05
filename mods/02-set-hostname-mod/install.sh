set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

print_ok "Setting up hostname..."
echo "$TARGET_NAME" > /etc/hostname
hostname "$TARGET_NAME"
judge "Set up hostname to $TARGET_NAME"

print_ok "Configuring locales and resolvconf..."
apt update
apt install $INTERACTIVE \
    locales \
    resolvconf \
    apt-utils \
    --no-install-recommends
judge "Install locales and resolvconf"

print_ok "Installing $LANGUAGE_PACKS language packs"
apt install $INTERACTIVE $LANGUAGE_PACKS --no-install-recommends
judge "Install language packs"
