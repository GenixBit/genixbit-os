#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verifies an installed QCOW2 image using real libguestfs observations only.
# No partition, filesystem, kernel, bootloader, token, or PASS result is invented.

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
[[ "$MODE" == "uefi" || "$MODE" == "bios" ]] || fail '--mode must be uefi or bios.'

state_dir="$(dirname "$DISK_PATH")"
[[ -n "$OUT_JSON" ]] || OUT_JSON="${state_dir}/disk-inspection-${MODE}.json"
mkdir -p "$(dirname "$OUT_JSON")"

command -v qemu-img >/dev/null 2>&1 || fail 'qemu-img is required.'
command -v guestfish >/dev/null 2>&1 || fail 'guestfish/libguestfs is required; refusing synthetic disk evidence.'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required.'

IMG_INFO=$(qemu-img info --output=json "$DISK_PATH") || fail 'qemu-img info failed.'
FORMAT=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("format", ""))' <<<"$IMG_INFO")
VSIZE=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("virtual-size", 0))' <<<"$IMG_INFO")
[[ "$FORMAT" == "qcow2" ]] || fail "Disk format is '$FORMAT', expected qcow2."
(( VSIZE > 1073741824 )) || fail "Disk virtual size is too small for an installed OS: $VSIZE bytes."

# libguestfs must be able to boot its appliance and identify an installed OS root.
ROOTS=$(guestfish --ro -a "$DISK_PATH" run : inspect-os 2>/dev/null) || fail 'libguestfs could not inspect the disk.'
ROOT_DEV=$(printf '%s\n' "$ROOTS" | sed '/^[[:space:]]*$/d' | head -n 1)
[[ -n "$ROOT_DEV" ]] || fail 'No installed operating-system root was detected.'

PARTITIONS=$(guestfish --ro -a "$DISK_PATH" run : list-partitions 2>/dev/null) || fail 'Could not list disk partitions.'
FILESYSTEMS=$(guestfish --ro -a "$DISK_PATH" run : list-filesystems 2>/dev/null) || fail 'Could not list filesystems.'
DEVICES=$(guestfish --ro -a "$DISK_PATH" run : list-devices 2>/dev/null) || fail 'Could not list block devices.'
DEVICE=$(printf '%s\n' "$DEVICES" | sed '/^[[:space:]]*$/d' | head -n 1)
[[ -n "$DEVICE" ]] || fail 'No block device was observed by libguestfs.'
PARTITION_TABLE=$(guestfish --ro -a "$DISK_PATH" run : part-get-parttype "$DEVICE" 2>/dev/null || true)
[[ -n "$PARTITION_TABLE" ]] || fail 'Could not observe the partition table type.'

ROOT_FS=$(printf '%s\n' "$FILESYSTEMS" | awk -v root="$ROOT_DEV" '$1 == root ":" {print $2; exit}')
[[ -n "$ROOT_FS" ]] || fail "Could not determine filesystem type for detected root $ROOT_DEV."

read_root_file() {
    local path=$1
    guestfish --ro -a "$DISK_PATH" -m "$ROOT_DEV" cat "$path" 2>/dev/null
}

root_is_file() {
    local path=$1
    [[ "$(guestfish --ro -a "$DISK_PATH" -m "$ROOT_DEV" is-file "$path" 2>/dev/null || true)" == "true" ]]
}

for required in /etc/os-release /etc/passwd /etc/fstab /etc/genixbit-install-token; do
    root_is_file "$required" || fail "Required installed-system file is missing: $required"
done

OBSERVED_TOKEN=$(read_root_file /etc/genixbit-install-token | tr -d '\r\n')
[[ "$OBSERVED_TOKEN" == "$TOKEN" ]] || fail 'Installed-root completion token does not match the expected token.'

OS_RELEASE=$(read_root_file /etc/os-release)
if ! grep -Eq '^NAME="?GenixBit OS"?$|^ID=genixbit$' <<<"$OS_RELEASE"; then
    fail 'Installed /etc/os-release does not identify GenixBit OS.'
fi

BOOT_LIST=$(guestfish --ro -a "$DISK_PATH" -m "$ROOT_DEV" ls /boot 2>/dev/null) || fail 'Could not inspect /boot.'
KERNELS=$(printf '%s\n' "$BOOT_LIST" | grep '^vmlinuz-' || true)
INITRDS=$(printf '%s\n' "$BOOT_LIST" | grep '^initrd\.img-' || true)
[[ -n "$KERNELS" ]] || fail 'No installed kernel image was observed under /boot.'
[[ -n "$INITRDS" ]] || fail 'No installed initrd was observed under /boot.'

BOOTLOADER_FILES=""
EFI_DEV=""
if [[ "$MODE" == "uefi" ]]; then
    EFI_DEV=$(printf '%s\n' "$FILESYSTEMS" | awk '$2 ~ /^(vfat|fat)$/ {sub(/:$/, "", $1); print $1; exit}')
    [[ -n "$EFI_DEV" ]] || fail 'UEFI validation requires an observed FAT EFI system partition.'

    EFI_FILES=$(guestfish --ro -a "$DISK_PATH" -m "$EFI_DEV" find /EFI 2>/dev/null || true)
    BOOTLOADER_FILES=$(printf '%s\n' "$EFI_FILES" | grep -Ei '\.efi$' || true)
    [[ -n "$BOOTLOADER_FILES" ]] || fail 'No EFI executable was observed on the EFI system partition.'
else
    root_is_file /boot/grub/grub.cfg || fail 'BIOS validation requires /boot/grub/grub.cfg.'
    BOOTLOADER_FILES='/boot/grub/grub.cfg'
fi

TOKEN_HASH=$(printf '%s' "$OBSERVED_TOKEN" | sha256sum | awk '{print $1}')
INSPECT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

FORMAT="$FORMAT" \
VSIZE="$VSIZE" \
MODE="$MODE" \
ROOT_DEV="$ROOT_DEV" \
ROOT_FS="$ROOT_FS" \
PARTITION_TABLE="$PARTITION_TABLE" \
PARTITIONS="$PARTITIONS" \
FILESYSTEMS="$FILESYSTEMS" \
KERNELS="$KERNELS" \
INITRDS="$INITRDS" \
BOOTLOADER_FILES="$BOOTLOADER_FILES" \
EFI_DEV="$EFI_DEV" \
TOKEN_HASH="$TOKEN_HASH" \
INSPECT_TIMESTAMP="$INSPECT_TIMESTAMP" \
DISK_PATH="$DISK_PATH" \
OUT_JSON="$OUT_JSON" \
python3 - <<'PYEOF'
import json
import os

def lines(name):
    return [line for line in os.environ.get(name, "").splitlines() if line.strip()]

report = {
    "disk_path": os.environ["DISK_PATH"],
    "format": os.environ["FORMAT"],
    "virtual_size_bytes": int(os.environ["VSIZE"]),
    "firmware_mode": os.environ["MODE"],
    "partition_table_type": os.environ["PARTITION_TABLE"],
    "partitions": lines("PARTITIONS"),
    "filesystems": lines("FILESYSTEMS"),
    "selected_root_filesystem": os.environ["ROOT_DEV"],
    "root_fs_type": os.environ["ROOT_FS"],
    "efi_system_partition": os.environ.get("EFI_DEV", ""),
    "inspected_files": [
        "/etc/os-release",
        "/etc/passwd",
        "/etc/fstab",
        "/etc/genixbit-install-token",
    ],
    "token_path": "/etc/genixbit-install-token",
    "observed_token_sha256": os.environ["TOKEN_HASH"],
    "kernels": lines("KERNELS"),
    "initrds": lines("INITRDS"),
    "bootloader_files": lines("BOOTLOADER_FILES"),
    "inspection_timestamp": os.environ["INSPECT_TIMESTAMP"],
    "evidence_source": "libguestfs_read_only_inspection",
    "status": "PASS",
}
with open(os.environ["OUT_JSON"], "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2)
PYEOF

printf '[PASS] Real read-only disk inspection verified %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
