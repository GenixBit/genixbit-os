#!/bin/bash

#=================================================
#           PLEASE READ THIS BEFORE EDITING
#=================================================
# This file is used to set the environment variables for the build process.
# Before building AnduinOS, you should edit this file to customize the build process.
# It is sourced by the build script and should not be executed directly.
# You can edit this file to customize the build process.
# However, you should not change the variable names or the structure of the file.
# After editing this file, you can run the build script `make` to start the build process.

#==========================
# Builder Environment Variables
#==========================
export DEBIAN_FRONTEND=noninteractive
export SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export HOME=/root

# Set if build in an interactive way.
# Can be: "-y" or ""
export INTERACTIVE="-y"

#==========================
# Language Information
#==========================

# Installed system default locale.
# This is what the ISO ships as the out-of-box system language (login screen, new user sessions).
# Ubiquity can still change it at install time when the user picks a different language.
#
# Common examples:
#   DEFAULT_LANG="en_US.UTF-8"    # English (default)
#   DEFAULT_LANG="zh_CN.UTF-8"    # Simplified Chinese
#   DEFAULT_LANG="zh_TW.UTF-8"    # Traditional Chinese (Taiwan)
#   DEFAULT_LANG="zh_HK.UTF-8"    # Traditional Chinese (Hong Kong)
#   DEFAULT_LANG="ja_JP.UTF-8"    # Japanese
#   DEFAULT_LANG="ko_KR.UTF-8"    # Korean
#   DEFAULT_LANG="vi_VN.UTF-8"    # Vietnamese
#   DEFAULT_LANG="th_TH.UTF-8"    # Thai
#   DEFAULT_LANG="de_DE.UTF-8"    # German
#   DEFAULT_LANG="fr_FR.UTF-8"    # French
#   DEFAULT_LANG="es_ES.UTF-8"    # Spanish
#   DEFAULT_LANG="ru_RU.UTF-8"    # Russian
#   DEFAULT_LANG="it_IT.UTF-8"    # Italian
#   DEFAULT_LANG="pt_BR.UTF-8"    # Portuguese (Brazil)
#   DEFAULT_LANG="pt_PT.UTF-8"    # Portuguese (Portugal)
#   DEFAULT_LANG="ar_SA.UTF-8"    # Arabic
#   DEFAULT_LANG="nl_NL.UTF-8"    # Dutch
#   DEFAULT_LANG="sv_SE.UTF-8"    # Swedish
#   DEFAULT_LANG="pl_PL.UTF-8"    # Polish
#   DEFAULT_LANG="tr_TR.UTF-8"    # Turkish
#   DEFAULT_LANG="ro_RO.UTF-8"    # Romanian
export DEFAULT_LANG="en_US.UTF-8"

# Build environment locale — always en_US.UTF-8 regardless of DEFAULT_LANG.
# The build scripts need a predictable, English locale to run correctly.
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LC_TIME=en_US.UTF-8
export LC_NAME=en_US.UTF-8
export LC_ADDRESS=en_US.UTF-8
export LC_TELEPHONE=en_US.UTF-8
export LC_MEASUREMENT=en_US.UTF-8
export LC_IDENTIFICATION=en_US.UTF-8
export LC_NUMERIC=en_US.UTF-8
export LC_PAPER=en_US.UTF-8
export LC_MONETARY=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en

# Language pack codes for every language Ubuntu ships.
# Pre-installed so Ubiquity can switch any language fully offline.
# Each code expands to language-pack-{code}* and language-pack-gnome-{code}*
# (the glob catches -base and any sub-variants automatically).
export LANG_PACK_CODES="\
af am an ar as ast az \
be bg bn br bs \
ca ckb crh cs cy \
da de dz \
el en eo es et eu \
fa fi fr fur \
ga gd gl gu \
he hi hr hu \
ia id is it \
ja \
ka kab kk km kn ko ku \
lt lv \
mk ml mr ms my \
nb nds ne nl nn \
oc or \
pa pl pt \
ro ru \
si sk sl sq sr sv szl \
ta te tg th tr \
ug uk \
vi \
xh \
zh-hans zh-hant"

_LP=""
for _c in $LANG_PACK_CODES; do
    _LP="$_LP language-pack-$_c language-pack-$_c-base language-pack-gnome-$_c language-pack-gnome-$_c-base"
done
export LANGUAGE_PACKS="${_LP# }"
unset _LP _c

# Just logging. Continue with the rest of the script
echo "Default system language: $DEFAULT_LANG"

#==========================
# OS system information
#==========================

# This is the target Ubuntu version code name for the build.
# It should match the Ubuntu version you are building against.
# For example, if you are building against Ubuntu 22.04 LTS, this should be "jammy".
# If you are building against Ubuntu 24.04 LTS, this should be "noble".
# If you are building against Ubuntu 24.10, this should be "oracular".
# If you are building against Ubuntu 25.04, this should be "plucky".
# If you are building against Ubuntu 25.10, this should be "questing".
# If you are building against Ubuntu 26.04, this should be "resolute".
# Can be: jammy noble oracular plucky questing resolute
export TARGET_UBUNTU_VERSION="resolute"

# This is the apt source for the build.
# It can be any Ubuntu mirror that you prefer.
# The default is the Aiursoft mirror.
# You can change it to any other mirror that you prefer.
# See https://docs.anduinos.com/Install/Select-Best-Apt-Source.html
export BUILD_UBUNTU_MIRROR="https://mirror.aiursoft.com/ubuntu/"

# This is the name of the target OS.
# Must be lowercase without special characters and spaces
export TARGET_NAME="anduinos"

# This is the full display name of the target OS.
# Business name. No special characters or spaces
export TARGET_BUSINESS_NAME="AnduinOS"

# Version number. Must be in the format of x.y.z
export TARGET_BUILD_VERSION="2.0.0"

# Fork version. Must be in the format of x.y
# By default, it is the branch name of the git repository.
export TARGET_BUILD_BRANCH=$(git rev-parse --abbrev-ref HEAD)

#===========================
# Installer customization
#===========================

# Packages will be uninstalled during the installation process
export TARGET_PACKAGE_REMOVE="
    ubiquity \
    casper \
    discover \
    laptop-detect \
    os-prober \
    gparted \
"

#============================
# Store experience customization
#============================

# How to install the store. Can be "none", "web", "flatpak", "snap"
# none:     no app store
# web:      use a web shortcut to browse the app store
# flatpak:  use gnome software to browse the app store, and install flatpak as plugin
# snap:     use gnome software to browse the app store, and install snap as plugin
export STORE_PROVIDER="flatpak"

# The mirror URL for flathub. Can be: "https://mirror.sjtu.edu.cn/flathub"
export FLATHUB_MIRROR=""
if [[ "$FLATHUB_MIRROR" != "" && "$STORE_PROVIDER" != "flatpak" ]]; then
    echo "Error: FLATHUB_MIRROR is set, but STORE_PROVIDER is not set to flatpak"
    exit 1
fi

# The gpg file for the flathub mirror. Can be: "https://mirror.sjtu.edu.cn/flathub/flathub.gpg"
export FLATHUB_GPG=""
if [[ "$FLATHUB_GPG" != "" && "$FLATHUB_MIRROR" == "" ]]; then
    echo "Error: FLATHUB_GPG is set, but FLATHUB_MIRROR is not set"
    exit 1
fi

#============================
# Browser configuration
#============================

# How to install Firefox. Can be: "none", "deb", "flatpak", "snap"
# none:     no firefox
# deb:      install firefox from Canonical PPA with apt
# flatpak:  install firefox from flathub (Only available if STORE_PROVIDER is set to "flatpak")
# snap:     install firefox from snap (Only available if STORE_PROVIDER is set to "snap")
# official_apt: install firefox from the official Firefox apt source
# TODO: Snap firefox seems to be broken. Investigation required.
export FIREFOX_PROVIDER="official_apt"
if [[ "$FIREFOX_PROVIDER" == "flatpak" && "$STORE_PROVIDER" != "flatpak" ]]; then
    echo "Error: FIREFOX_PROVIDER is set to flatpak, but STORE_PROVIDER is not set to flatpak"
    exit 1
fi
if [[ "$FIREFOX_PROVIDER" == "snap" && "$STORE_PROVIDER" != "snap" ]]; then
    echo "Error: FIREFOX_PROVIDER is set to snap, but STORE_PROVIDER is not set to snap"
    exit 1
fi

# Whether to install firefox with apt. If set, it will be installed from the PPA. If empty, it will be installed from the default source
# Must set FIREFOX_PROVIDER to "deb" before using this option
# Sample: mirror-ppa.aiursoft.com
export BUILD_FIREFOX_MIRROR=""
if [[ "$BUILD_FIREFOX_MIRROR" != "" && "$FIREFOX_PROVIDER" != "deb" ]]; then
    echo "Error: BUILD_FIREFOX_MIRROR is set, but FIREFOX_PROVIDER is not set to deb"
    exit 1
fi

# The Firefox mirror for live system. If set, it will be used to replace the default PPA mirror.
# This must be set if FIREFOX_PROVIDER is set to "deb"
# Default: ppa.launchpadcontent.net
export LIVE_FIREFOX_MIRROR=""
if [[ "$FIREFOX_PROVIDER" == "deb" && -z "$LIVE_FIREFOX_MIRROR" ]]; then
    echo "Error: FIREFOX_PROVIDER is deb, but didn't set LIVE_FIREFOX_MIRROR"
    exit 1
fi

export FIREFOX_LOCALE_PACKAGE=""
if [[ "$FIREFOX_LOCALE_PACKAGE" != "" && "$FIREFOX_PROVIDER" != "deb" ]]; then
    echo "Error: FIREFOX_LOCALE_PACKAGE is set, but FIREFOX_PROVIDER is not set to deb"
    exit 1
fi
#============================
# Input method configuration
#============================

# Packages will be installed during the installation process
# Can be:
# * ibus-rime
# * ibus-libpinyin
# * ibus-chewing
# * ibus-table-cangjie
# * ibus-mozc
# * ibus-hangul
# * ibus-unikey
# * ibus-libthai
export INPUT_METHOD_INSTALL=""

# Boolean indicator for whether to install anduinos-ibus-rime
export CONFIG_IBUS_RIME="false"
if [[ "$CONFIG_IBUS_RIME" == "true" && "$INPUT_METHOD_INSTALL" != *"ibus-rime"* ]]; then
    echo "Error: CONFIG_IBUS_RIME is set to true, but INPUT_METHOD_INSTALL is not set to ibus-rime"
    exit 1
fi

# The default keyboard layout. Can be:
# * [('xkb', 'us')]
# * [('xkb', 'us'), ('ibus', 'rime')]
# * [('xkb', 'us'), ('ibus', 'chewing')]
# * [('xkb', 'us'), ('xkb', 'fr')]
export CONFIG_INPUT_METHOD="[('xkb', 'us')]"

#============================
# Software properties configuration
#============================

# To install software-properties-gtk, set to "true" or "false"
export INSTALL_MODIFIED_SOFTWARE_PROPERTIES_GTK="true"

#============================
# Time zone configuration
#============================

# The timezone for the new OS being built (In chroot environment)
# To view available options, run: `ls /usr/share/zoneinfo/`
export TIMEZONE="America/Los_Angeles"

#============================
# Weather plugin configuration
#============================

# This will affect the default weather location in the weather plugin.
export CONFIG_WEATHER_LOCATION="['{\"name\":\"San Francisco, California, United States\",\"lat\":37.7749295,\"lon\":-122.4194155}']"

#============================
# AnduinOS APKG server configuration
#============================

# This is the APKG server URL for AnduinOS-branded overlay packages.
# It serves the anduinos-* packages (keyring, apt-config, branding, etc.).
export APKG_SERVER="https://apkg-dev.aiursoft.com"

# GPG certificate name on the APKG server (used to download and verify the repo).
# The cert is fetched from: $APKG_SERVER/artifacts/certs/$APKG_CERT_NAME
export APKG_CERT_NAME="anduinos"

#============================
# Live system configuration
#============================

# This is the default apt server in the live system.
# It can be any Ubuntu mirror that you prefer.
export LIVE_UBUNTU_MIRROR="https://mirror.aiursoft.com/ubuntu/"


# The default CLI tools to be installed.
# All those tools are optional. You can remove any of them if you don't need them.
export DEFAULT_CLI_TOOLS="
    curl \
    vim \
    nano \
    git \
    build-essential \
    make \
    gcc \
    g++ \
    dpkg-dev \
    net-tools \
    htop \
    httping \
    iputils-ping \
    iputils-tracepath \
    dnsutils \
    smartmontools \
    traceroute \
    whois \
    nmap \
    fastfetch
    "

# The default Flatpak tools to be installed.
# All those tools are optional. You can remove any of them if you don't need them.
export DEFAULT_FLATPAK_TOOLS=""
# export DEFAULT_FLATPAK_TOOLS="
#     chat.revolt.RevoltDesktop \
#     com.discordapp.Discord \
#     com.google.EarthPro \
#     com.jetbrains.Rider \
#     com.obsproject.Studio \
#     com.spotify.Client \
#     com.tencent.WeChat \
#     com.valvesoftware.Steam \
#     io.github.shiftey.Desktop \
#     net.agalwood.Motrix \
#     org.musescore.MuseScore \
#     org.qbittorrent.qBittorrent \
#     org.signal.Signal \
#     org.gnome.Boxes \
#     org.kde.krita \
#     io.missioncenter.MissionCenter \
#     com.getpostman.Postman \
#     org.shotcut.Shotcut \
#     org.blender.Blender \
#     org.videolan.VLC \
#     com.wps.Office \
#     org.chromium.Chromium \
#     com.dosbox_x.DOSBox-X \
#     com.mojang.Minecraft \
#     org.codeblocks.codeblocks
#     "
