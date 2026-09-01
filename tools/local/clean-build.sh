#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Remove only reproducible/generated build outputs inside the repository.
# Persistent local VM disks under .local-artifacts/ are intentionally preserved.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

safe_repo_path() {
    local path=$1
    case "$path" in
        "$ROOT_DIR"/*) return 0 ;;
        *) fail "Refusing cleanup outside repository: $path" ;;
    esac
}

BUILD_ROOT="$ROOT_DIR/new_building_os"
IMAGE_ROOT="$ROOT_DIR/image"
DEBS_ROOT="$ROOT_DIR/packages/build-debs"
DIST_ROOT="$ROOT_DIR/dist"
LEGACY_ISO="$ROOT_DIR/genixbitos.iso"

for path in "$BUILD_ROOT" "$IMAGE_ROOT" "$DEBS_ROOT" "$DIST_ROOT" "$LEGACY_ISO"; do
    safe_repo_path "$path"
done

# Interrupted builds may leave only these known bind/pseudo-filesystem mounts.
# Never recurse through or unmount arbitrary paths.
if command -v mountpoint >/dev/null 2>&1; then
    SUDO=()
    if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
        SUDO=(sudo)
    fi
    for mount_path in \
        "$BUILD_ROOT/dev/pts" \
        "$BUILD_ROOT/proc" \
        "$BUILD_ROOT/sys" \
        "$BUILD_ROOT/dev" \
        "$BUILD_ROOT/run"; do
        if [[ -e "$mount_path" ]] && mountpoint -q "$mount_path"; then
            ((${#SUDO[@]} > 0)) || [[ $EUID -eq 0 ]] || fail "Build mount remains at $mount_path; sudo is required to unmount it safely."
            "${SUDO[@]}" umount "$mount_path" || "${SUDO[@]}" umount -lf "$mount_path"
        fi
    done
fi

rm -rf -- "$IMAGE_ROOT" "$DEBS_ROOT" "$DIST_ROOT"
rm -f -- "$LEGACY_ISO"

# The debootstrap tree is normally root-owned.
if [[ -e "$BUILD_ROOT" ]]; then
    if [[ -w "$BUILD_ROOT" && -w "$(dirname "$BUILD_ROOT")" ]]; then
        rm -rf -- "$BUILD_ROOT"
    else
        command -v sudo >/dev/null 2>&1 || fail "sudo is required to remove root-owned build tree: $BUILD_ROOT"
        sudo rm -rf -- "$BUILD_ROOT"
    fi
fi

printf '[CLEAN] Removed generated package, ISO, chroot, and assembly outputs.\n'
printf '[CLEAN] Preserved persistent VM state under %s/.local-artifacts/.\n' "$ROOT_DIR"
