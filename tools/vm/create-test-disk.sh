#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a QCOW2 virtual disk image outside the Git repository.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
DISK_SIZE="40G"

fail() {
    printf '[FAIL] create-test-disk.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --size)
            (($# >= 2)) || fail '--size requires a size (e.g. 40G).'
            DISK_SIZE=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$DISK_PATH" ]] || fail '--disk is required.'

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$repo_root" ]]; then
    disk_dir=$(cd "$(dirname "$DISK_PATH")" 2>/dev/null && pwd -P || true)
    if [[ -n "$disk_dir" ]]; then
        case "${disk_dir}/$(basename "$DISK_PATH")" in
            "$repo_root"/*) fail 'Virtual disks must be stored outside the Git repository.' ;;
        esac
    fi
fi

mkdir -p "$(dirname "$DISK_PATH")"
if [[ -f "$DISK_PATH" ]]; then
    printf '[INFO] Virtual disk already exists: %s\n' "$DISK_PATH"
    exit 0
fi

qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE" >/dev/null
printf '[PASS] Created virtual disk (%s): %s\n' "$DISK_SIZE" "$DISK_PATH"
exit 0
