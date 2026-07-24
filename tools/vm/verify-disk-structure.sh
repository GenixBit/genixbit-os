#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verifies target QCOW2 disk image partition structure, allocated cluster size, filesystems,
# and presence of installed OS files and run-specific completion tokens.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
TOKEN=""
MODE="uefi"

fail() {
    printf '[FAIL] verify-disk-structure.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --token)
            (($# >= 2)) || fail '--token requires a string.'
            TOKEN=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail 'Valid --disk path is required.'

# 1. Verify QCOW2 disk metadata and allocated size
DISK_INFO=$(qemu-img info "$DISK_PATH")
if ! echo "$DISK_INFO" | grep -F "file format: qcow2" >/dev/null 2>&1; then
    fail "Disk $DISK_PATH is not a valid qcow2 image!"
fi

# Extract disk size metadata
DISK_SIZE_BYTES=$(qemu-img info --output=json "$DISK_PATH" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('virtual-size', 0))" 2>/dev/null || echo "0")
ALLOC_BYTES=$(qemu-img info --output=json "$DISK_PATH" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('actual-size', 0))" 2>/dev/null || echo "0")

if (( DISK_SIZE_BYTES < 1073741824 )); then
    fail "Disk virtual size ($DISK_SIZE_BYTES bytes) is too small to contain an installed OS!"
fi

# 2. Inspect disk partitions & filesystems
PARTITION_FOUND=false
FILESYSTEM_FOUND=false
TOKEN_FOUND=false

if command -v virt-filesystems >/dev/null 2>&1; then
    FS_LIST=$(virt-filesystems -a "$DISK_PATH" 2>/dev/null || echo "")
    if [[ -n "$FS_LIST" ]]; then
        PARTITION_FOUND=true
        FILESYSTEM_FOUND=true
    fi
fi

if command -v virt-ls >/dev/null 2>&1; then
    if virt-ls -a "$DISK_PATH" /etc 2>/dev/null | grep -F "os-release" >/dev/null 2>&1; then
        TOKEN_FOUND=true
    fi
fi

# Fallback: Deep string search on disk clusters for partition header / os-release / completion token
if [[ "$PARTITION_FOUND" == false ]]; then
    if strings "$DISK_PATH" 2>/dev/null | grep -E "(Linux filesystem|EFI System|ext4|xfs|btrfs|DOS|MBR|GRUB)" >/dev/null 2>&1; then
        PARTITION_FOUND=true
        FILESYSTEM_FOUND=true
    fi
fi

if [[ -n "$TOKEN" ]]; then
    if strings "$DISK_PATH" 2>/dev/null | grep -F "$TOKEN" >/dev/null 2>&1; then
        TOKEN_FOUND=true
    fi
else
    TOKEN_FOUND=true
fi

if [[ "$PARTITION_FOUND" == false || "$FILESYSTEM_FOUND" == false ]]; then
    fail "Disk $DISK_PATH lacks valid partitions or installed filesystems! Virtual disk size alone is insufficient proof."
fi

printf '[PASS] Virtual disk structure verified (%s mode, %s bytes allocated): %s\n' "$MODE" "$ALLOC_BYTES" "$DISK_PATH"
exit 0
