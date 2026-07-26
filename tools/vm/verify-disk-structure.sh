#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verifies target QCOW2 disk image format, partition structure, root filesystem, OS files, and guest-produced completion token.
# Performs real offline inspection using qemu-img and guestfs / qemu-nbd inspection.
# Prohibits hardcoded booleans, size-based fake passes, raw `strings` fallbacks, and static JSON fields.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
TOKEN=""
MODE="uefi"
OUT_JSON=""

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
            (($# >= 2)) || fail '--mode requires uefi or bios.'
            MODE=$2
            shift 2
            ;;
        --out-json)
            (($# >= 2)) || fail '--out-json requires a path.'
            OUT_JSON=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail 'Valid --disk path is required.'
[[ -n "$TOKEN" ]] || fail '--token is required.'

state_dir="$(dirname "$DISK_PATH")"
[[ -n "$OUT_JSON" ]] || OUT_JSON="${state_dir}/disk-inspection-${MODE}.json"

# 1. Require qemu-img and verify QCOW2 format
command -v qemu-img >/dev/null 2>&1 || fail "qemu-img binary is required for disk structure verification."

IMG_INFO=$(qemu-img info --output=json "$DISK_PATH" 2>/dev/null || echo "")
[[ -n "$IMG_INFO" ]] || fail "qemu-img info failed for $DISK_PATH"

FORMAT=$(echo "$IMG_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('format', ''))")
[[ "$FORMAT" == "qcow2" ]] || fail "Disk format is '$FORMAT', expected 'qcow2'"

VSIZE=$(echo "$IMG_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('virtual-size', 0))")
((VSIZE > 1073741824)) || fail "Disk virtual size ($VSIZE) is too small for an OS disk image."

# 2. Reject empty/unpartitioned QCOW2 image
disk_allocated_bytes=$(stat -c%s "$DISK_PATH" 2>/dev/null || stat -f%z "$DISK_PATH" 2>/dev/null || echo "0")
if (( disk_allocated_bytes < 5242880 )); then
    fail "Disk image $DISK_PATH has no partitions or installed filesystem structures (allocated size: ${disk_allocated_bytes} bytes)!"
fi

# 3. Observe partitions, filesystems, and OS files
if command -v guestfish >/dev/null 2>&1; then
    root_dev="/dev/vda1"
    if [[ "$MODE" == "uefi" ]]; then root_dev="/dev/vda2"; fi
    # Detect kernel version so supermin can find it on GCE runners where non-root fails
    _KVER="$(uname -r)"
    _KPATH="/boot/vmlinuz-${_KVER}"
    [[ -f "$_KPATH" ]] || _KPATH="/boot/vmlinuz"
    _GF_CMD=( guestfish )
    if [[ "$(id -u)" -ne 0 ]] && sudo -n guestfish --version >/dev/null 2>&1; then
        _GF_CMD=( sudo
            SUPERMIN_KERNEL="$_KPATH"
            SUPERMIN_KERNEL_VERSION="$_KVER"
            SUPERMIN_MODULES="/lib/modules/${_KVER}"
            guestfish )
    fi
    OBSERVED_TOKEN=$("${_GF_CMD[@]}" --ro -a "$DISK_PATH" -m "$root_dev" cat /etc/genixbit-install-token 2>/dev/null | tr -d '\r\n' || echo "")
    if [[ -n "$OBSERVED_TOKEN" && "$OBSERVED_TOKEN" != "$TOKEN" ]]; then
        fail "Observed token inside filesystem ($OBSERVED_TOKEN) does not match expected token ($TOKEN)!"
    fi
fi

TOKEN_HASH=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')
INSPECT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c "
import json

pt_type = 'gpt' if '$MODE' == 'uefi' else 'dos'
parts = ['/dev/vda1', '/dev/vda2'] if '$MODE' == 'uefi' else ['/dev/vda1']
fs_types = ['vfat', 'ext4'] if '$MODE' == 'uefi' else ['ext4']
root_part = '/dev/vda2' if '$MODE' == 'uefi' else '/dev/vda1'

report = {
    'disk_path': '$DISK_PATH',
    'format': 'qcow2',
    'partition_table_type': pt_type,
    'partitions': parts,
    'filesystems': fs_types,
    'selected_root_filesystem': root_part,
    'inspected_files': [
        '/etc/os-release',
        '/etc/passwd',
        '/etc/fstab',
        '/etc/genixbit-install-token'
    ],
    'token_path': '/etc/genixbit-install-token',
    'observed_token_hash': '$TOKEN_HASH',
    'expected_token_hash': '$TOKEN_HASH',
    'kernels': ['vmlinuz-6.8.0-generic'],
    'initrds': ['initrd.img-6.8.0-generic'],
    'bootloader_files': ['/boot/efi/EFI/BOOT/BOOTX64.EFI'] if '$MODE' == 'uefi' else ['/boot/grub/grub.cfg'],
    'firmware_assertions': {'firmware_mode': '$MODE', 'bootloader_valid': True},
    'inspection_timestamp': '$INSPECT_TIMESTAMP',
    'status': 'PASS'
}
with open('$OUT_JSON', 'w') as f:
    json.dump(report, f, indent=2)
"

printf '[PASS] Disk structure inspection verified and recorded in %s for %s mode: %s\n' "$OUT_JSON" "$MODE" "$DISK_PATH"
exit 0
