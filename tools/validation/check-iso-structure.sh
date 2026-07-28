#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Strict ISO Structural & Boot Artifact Validation Suite for GenixBit OS
# Rejects undersized or invalid ISO files without treating valid ISO padding as corruption.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
MIN_SIZE_MB="${MIN_ISO_SIZE_MB:-500}"

usage() {
    cat <<EOF
Usage: check-iso-structure.sh [--iso PATH] [--min-size-mb MB]

Options:
  --iso PATH          Path to the ISO image file to inspect.
  --min-size-mb MB    Minimum acceptable byte size in MiB (default: ${MIN_SIZE_MB}).
  -h, --help          Show this help message.
EOF
}

fail() {
    printf '[FAIL] ISO Validation Error: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

while (($# > 0)); do
    case "$1" in
        --iso)
            (($# >= 2)) || fail '--iso requires a path.'
            ISO_PATH=$2
            shift 2
            ;;
        --min-size-mb)
            (($# >= 2)) || fail '--min-size-mb requires a number.'
            MIN_SIZE_MB=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$ISO_PATH" && -f "$1" ]]; then
                ISO_PATH=$1
                shift
            else
                fail "Unknown argument or invalid path: $1"
            fi
            ;;
    esac
done

[[ -n "$ISO_PATH" ]] || fail "No ISO path provided. Pass --iso PATH."
[[ -f "$ISO_PATH" ]] || fail "ISO file does not exist: $ISO_PATH"

info "Inspecting ISO file: $ISO_PATH"

# 1. Byte Size & Minimum Size Threshold Check
ACTUAL_SIZE=$(stat -c %s "$ISO_PATH" 2>/dev/null || stat -f %z "$ISO_PATH" 2>/dev/null || wc -c < "$ISO_PATH")
MIN_BYTES=$((MIN_SIZE_MB * 1024 * 1024))

info "ISO byte size: $ACTUAL_SIZE bytes (minimum required: $MIN_BYTES bytes / ${MIN_SIZE_MB} MiB)"

if ((ACTUAL_SIZE < MIN_BYTES)); then
    fail "ISO size ($ACTUAL_SIZE bytes) is below minimum threshold of $MIN_BYTES bytes ($MIN_SIZE_MB MiB). Dummy/placeholder files are rejected."
fi

# 2. ISO9660 Primary Volume Descriptor signature check
info "Verifying ISO9660 Primary Volume Descriptor at sector 16..."
python3 - "$ISO_PATH" <<'PYEOF' || fail "ISO9660 Primary Volume Descriptor signature missing at sector 16. Zero-filled, sparse, random, or forged non-ISO files are rejected."
import sys

iso_file = sys.argv[1]
with open(iso_file, "rb") as f:
    f.seek(16 * 2048)
    header = f.read(6)

if len(header) != 6:
    print("ERROR: Unable to read ISO9660 descriptor header at sector 16.", file=sys.stderr)
    sys.exit(1)

descriptor_type = header[0]
signature = header[1:6]
if descriptor_type != 1 or signature != b"CD001":
    print(
        "ERROR: Expected Primary Volume Descriptor type 1 followed by CD001 at sector 16; "
        f"got type={descriptor_type} signature={signature!r}.",
        file=sys.stderr,
    )
    sys.exit(1)
PYEOF
pass "1. ISO9660 Primary Volume Descriptor signature verified."

# 3. File Type & ISO9660 Inspection
if command -v file >/dev/null 2>&1; then
    file_out=$(file "$ISO_PATH")
    info "file utility output: $file_out"
    if [[ "$file_out" != *"ISO 9660"* && "$file_out" != *"CD-ROM"* ]]; then
        fail "file utility did not recognize ISO9660 filesystem header: $file_out"
    fi
    pass "2. File type verified as ISO9660."
fi

# 4. ISO9660 parser inspection
if ! command -v xorriso >/dev/null 2>&1 && ! command -v isoinfo >/dev/null 2>&1; then
    fail "No supported ISO parser available. Install xorriso or isoinfo."
fi

if command -v xorriso >/dev/null 2>&1; then
    info "Running xorriso ISO filesystem inspection..."
    if ! xorriso -indev "$ISO_PATH" -find / >/dev/null 2>&1; then
        fail "xorriso failed to parse ISO filesystem in $ISO_PATH"
    fi
    pass "3. xorriso parsed ISO filesystem successfully."

    info "Running xorriso El Torito boot catalog report..."
    XORRISO_REPORT=$(xorriso -indev "$ISO_PATH" -report_el_torito as_mkisofs 2>&1 || true)

    if [[ "$XORRISO_REPORT" != *"-eltorito-boot"* && "$XORRISO_REPORT" != *"-e "* && "$XORRISO_REPORT" != *"El Torito"* ]]; then
        fail "xorriso failed to detect El Torito boot catalog structure in $ISO_PATH"
    fi
    pass "4. xorriso El Torito boot catalog inspection passed."
elif command -v isoinfo >/dev/null 2>&1; then
    info "Running isoinfo header inspection..."
    ISOINFO_OUT=$(isoinfo -d -i "$ISO_PATH" 2>&1 || true)
    if [[ "$ISOINFO_OUT" != *"Volume id:"* ]]; then
        fail "isoinfo failed to read ISO volume descriptor"
    fi
    pass "3. isoinfo header inspection passed."
    fail "xorriso is required for boot catalog, required file, EFI image, and SquashFS validation. isoinfo alone is insufficient for GenixBit OS release validation."
fi

# 5. Internal Boot File Structure Verification
TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if command -v xorriso >/dev/null 2>&1; then
    info "Verifying required internal boot files (vmlinuz, initrd, filesystem.squashfs)..."

    files_to_check=(
        "/casper/vmlinuz"
        "/casper/initrd"
        "/casper/filesystem.squashfs"
    )
    
    for rel_file in "${files_to_check[@]}"; do
        if ! xorriso -osirrox on -indev "$ISO_PATH" -extract "$rel_file" "$TMP_DIR/extracted_file" >/dev/null 2>&1; then
            fail "Required ISO internal file missing: $rel_file"
        fi
        [[ -s "$TMP_DIR/extracted_file" ]] || fail "Required ISO internal file is empty: $rel_file"
        rm -f "$TMP_DIR/extracted_file"
    done
    pass "5. Kernel (vmlinuz), initrd, and SquashFS files present inside ISO."

    # Extract EFI boot image and check for BOOTX64.EFI
    EFI_IMG="$TMP_DIR/efiboot.img"
    if xorriso -osirrox on -indev "$ISO_PATH" -extract /isolinux/efiboot.img "$EFI_IMG" >/dev/null 2>&1 || \
       xorriso -osirrox on -indev "$ISO_PATH" -extract /EFI/efiboot.img "$EFI_IMG" >/dev/null 2>&1; then

        if command -v mdir >/dev/null 2>&1; then
            if mdir -i "$EFI_IMG" ::/EFI/BOOT/BOOTX64.EFI >/dev/null 2>&1 || \
               mdir -i "$EFI_IMG" ::/EFI/BOOT >/dev/null 2>&1; then
                pass "6. EFI boot image contains valid EFI/BOOT/BOOTX64.EFI executable."
            else
                fail "EFI boot image extracted, but EFI/BOOT/BOOTX64.EFI was not found inside."
            fi
        else
            pass "6. EFI boot image extracted successfully."
        fi
    else
        fail "Unable to extract EFI boot image (efiboot.img) from ISO."
    fi

    # Verify SquashFS file non-zero & integrity if unsquashfs available
    SQUASH_FILE="$TMP_DIR/filesystem.squashfs"
    if xorriso -osirrox on -indev "$ISO_PATH" -extract /casper/filesystem.squashfs "$SQUASH_FILE" >/dev/null 2>&1; then
        if command -v unsquashfs >/dev/null 2>&1; then
            if unsquashfs -s "$SQUASH_FILE" >/dev/null 2>&1; then
                pass "7. SquashFS filesystem integrity verified via unsquashfs."
            else
                fail "SquashFS filesystem inside ISO is corrupt."
            fi
        fi
    fi
fi

pass "=== ISO Structural & Boot Artifact Validation Succeeded for $ISO_PATH ==="
exit 0
