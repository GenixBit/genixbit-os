#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Safely remove transient ISO-build workspaces created inside this repository.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

unmount_if_needed() {
    local target="$1"

    # umount returns non-zero for paths that are not mounted; that is harmless during
    # cleanup. Keep the target quoted so repositories with spaces in their path work.
    sudo umount -- "$target" 2>/dev/null || \
        sudo umount -lf -- "$target" 2>/dev/null || true
}

remove_build_tree() {
    local target="$1"

    # This script is allowed to recursively remove only descendants of the checkout.
    # Fail closed if a future edit accidentally passes an external or empty path.
    case "$target" in
        "$SCRIPT_DIR"/*)
            sudo rm -rf -- "$target"
            ;;
        *)
            echo "[ERROR] Refusing to remove path outside repository: $target" >&2
            return 1
            ;;
    esac
}

clean_all() {
    echo "Cleaning generated GenixBit OS build workspace..."

    unmount_if_needed "$SCRIPT_DIR/new_building_os/sys"
    unmount_if_needed "$SCRIPT_DIR/new_building_os/proc"
    unmount_if_needed "$SCRIPT_DIR/new_building_os/dev"
    unmount_if_needed "$SCRIPT_DIR/new_building_os/run"
    unmount_if_needed "$SCRIPT_DIR/image/isolinux/efi"

    remove_build_tree "$SCRIPT_DIR/new_building_os"
    remove_build_tree "$SCRIPT_DIR/image"

    rm -f -- "$SCRIPT_DIR"/*.iso
    echo "Cleanup complete."
}

clean_all
