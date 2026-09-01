#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Supported developer entry point for building the current GenixBit OS image.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ARGS_FILE="$ROOT_DIR/args.sh"

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == "Linux" ]] || fail "ISO builds are supported only on the target Ubuntu Linux release. Use 'make vm' to boot an existing ISO on other hosts."
[[ "$(uname -m)" == "x86_64" || "$(uname -m)" == "amd64" ]] || fail "The current ISO builder targets amd64/x86_64."
[[ -r /etc/os-release ]] || fail '/etc/os-release is required to validate the build host.'
[[ -f "$ARGS_FILE" ]] || fail "Missing build configuration: $ARGS_FILE"

TARGET_CODENAME=$(sed -n 's/^export TARGET_UBUNTU_VERSION="\([^"]*\)"/\1/p' "$ARGS_FILE" | head -n 1)
[[ -n "$TARGET_CODENAME" ]] || fail 'Could not read TARGET_UBUNTU_VERSION from args.sh.'

# shellcheck disable=SC1091
source /etc/os-release
HOST_ID="${ID:-}"
HOST_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

[[ "$HOST_ID" == "ubuntu" ]] || fail "Build host must be Ubuntu; detected ID='${HOST_ID:-unknown}'."
[[ "$HOST_CODENAME" == "$TARGET_CODENAME" ]] || fail "Build host codename '$HOST_CODENAME' does not match target '$TARGET_CODENAME'."

if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || fail 'sudo is required for debootstrap, chroot, mounts, and ISO assembly.'
    sudo -v
    SUDO=(sudo)
fi

command -v apt-get >/dev/null 2>&1 || fail 'apt-get is required on the supported Ubuntu build host.'

BUILD_DEPS=(
    ca-certificates
    curl
    gnupg
    git
    python3
    rsync
    file
    wget
    debootstrap
    dpkg-dev
    debhelper
    fakeroot
    build-essential
    squashfs-tools
    xorriso
    dosfstools
    mtools
    grub-common
    grub-pc-bin
    grub-efi-amd64-bin
)

printf '[BUILD] Validated Ubuntu %s (%s) amd64 build host.\n' "$TARGET_CODENAME" "${VERSION_ID:-unknown}"
printf '[BUILD] Ensuring required host packages are installed...\n'
"${SUDO[@]}" apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${BUILD_DEPS[@]}"

required_commands=(
    debootstrap
    dpkg-buildpackage
    mksquashfs
    unsquashfs
    xorriso
    mkfs.vfat
    mcopy
    grub-mkstandalone
)
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Required build command is unavailable after dependency installation: $command_name"
done

cd "$ROOT_DIR"
printf '[BUILD] Starting native GenixBit package + ISO build...\n'
exec bash "$ROOT_DIR/build.sh"
