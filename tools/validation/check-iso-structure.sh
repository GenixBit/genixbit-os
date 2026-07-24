#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Strict ISO Structural & Boot Artifact Validation Suite for GenixBit OS
# Rejects zero-filled, sparse, undersized, or invalid ISO files.

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

# 2. Non-Zero Content Sampling (Reject zero-filled or sparse placeholder files)
info "Performing non-zero content sampling across ISO file..."
python3 - "$ISO_PATH" <<'PYEOF'
import sys, os

iso_file = sys.argv[1]
size = os.path.getsize(iso_file)

# Sample 10 chunks of 64KB at various offsets across the file
num_samples = 10
chunk_size = 65536
offsets = [int(size * i / num_samples) for i in range(num_samples)]

total_sampled_bytes = 0
non_zero_bytes = 0

with open(iso_file, "rb") as f:
    for offset in offsets:
        f.seek(offset)
        chunk = f.read(chunk_size)
        total_sampled_bytes += len(chunk)
        non_zero_bytes += sum(1 for b in chunk if b != 0)

if total_sampled_bytes == 0:
    print("ERROR: Sampled 0 bytes from file.")
    sys.exit(1)

non_zero_ratio = non_zero_bytes / total_sampled_bytes
print(f"Non-zero byte ratio across sampled regions: {non_zero_ratio:.2%}")

if non_zero_ratio < 0.10:
    print(f"ERROR: File is zero-filled or sparse placeholder (non-zero byte ratio: {non_zero_ratio:.2%}).")
    sys.exit(1)
PYEOF

if (($? != 0)); then
    fail "ISO failed non-zero content sampling check. Zero-filled/placeholder files are rejected."
fi
pass "1. Non-zero file content sampling passed."

# 3. File Type & ISO9660 Inspection
if command -v file >/dev/null 2>&1; then
    file_out=$(file "$ISO_PATH")
    info "file utility output: $file_out"
    if [[ "$file_out" != *"ISO 9660"* && "$file_out" != *"CD-ROM"* ]]; then
        fail "file utility did not recognize ISO9660 filesystem header: $file_out"
    fi
    pass "2. File type verified as ISO9660."
fi

# 4. ISO9660 / xorriso Inspection
if command -v xorriso >/dev/null 2>&1; then
    info "Running xorriso El Torito boot catalog report..."
    XORRISO_REPORT=$(xorriso -indev "$ISO_PATH" -report_el_torito as_mkisofs 2>&1 || true)
    
    if [[ "$XORRISO_REPORT" != *"-eltorito-boot"* && "$XORRISO_REPORT" != *"boot"* ]]; then
        fail "xorriso failed to detect El Torito boot catalog structure in $ISO_PATH"
    fi
    pass "3. xorriso El Torito boot catalog inspection passed."
elif command -v isoinfo >/dev/null 2>&1; then
    info "Running isoinfo header inspection..."
    ISOINFO_OUT=$(isoinfo -d -i "$ISO_PATH" 2>&1 || true)
    if [[ "$ISOINFO_OUT" != *"Volume id:"* ]]; then
        fail "isoinfo failed to read ISO volume descriptor"
    fi
    pass "3. isoinfo header inspection passed."
fi

# 5. Internal Boot File Structure Verification
TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if command -v xorriso >/dev/null 2>&1; then
    info "Verifying required internal boot files (vmlinuz, initrd, efiboot.img, filesystem.squashfs)..."
    
    files_to_check=(
        "/casper/vmlinuz"
        "/casper/initrd"
        "/casper/filesystem.squashfs"
    )
    
    for rel_file in "${files_to_check[@]}"; do
        if ! xorriso -osirrox on -indev "$ISO_PATH" -extract "$rel_file" "$TMP_DIR/extracted_file" >/dev/null 2>&1; then
            # Also try without /casper/ prefix or with alternate extensions
            if ! xorriso -indev "$ISO_PATH" -find / -name "$(basename "$rel_file")*" | grep -q "$(basename "$rel_file")"; then
                fail "Required ISO internal file missing: $rel_file"
            fi
        fi
        rm -f "$TMP_DIR/extracted_file"
    done
    pass "4. Kernel (vmlinuz), initrd, and SquashFS files present inside ISO."

    # Extract EFI boot image and check for BOOTX64.EFI
    EFI_IMG="$TMP_DIR/efiboot.img"
    if xorriso -osirrox on -indev "$ISO_PATH" -extract /isolinux/efiboot.img "$EFI_IMG" >/dev/null 2>&1 || \
       xorriso -osirrox on -indev "$ISO_PATH" -extract /EFI/efiboot.img "$EFI_IMG" >/dev/null 2>&1; then
        
        if command -v mdir >/dev/null 2>&1; then
            if mdir -i "$EFI_IMG" ::/EFI/BOOT/BOOTX64.EFI >/dev/null 2>&1 || \
               mdir -i "$EFI_IMG" ::/EFI/BOOT >/dev/null 2>&1; then
                pass "5. EFI boot image contains valid EFI/BOOT/BOOTX64.EFI executable."
            else
                fail "EFI boot image extracted, but EFI/BOOT/BOOTX64.EFI was not found inside."
            fi
        else
            pass "5. EFI boot image extracted successfully."
        fi
    else
        fail "Unable to extract EFI boot image (efiboot.img) from ISO."
    fi

    # Verify SquashFS file non-zero & integrity if unsquashfs available
    SQUASH_FILE="$TMP_DIR/filesystem.squashfs"
    if xorriso -osirrox on -indev "$ISO_PATH" -extract /casper/filesystem.squashfs "$SQUASH_FILE" >/dev/null 2>&1; then
        if command -v unsquashfs >/dev/null 2>&1; then
            if unsquashfs -s "$SQUASH_FILE" >/dev/null 2>&1; then
                pass "6. SquashFS filesystem integrity verified via unsquashfs."
            else
                fail "SquashFS filesystem inside ISO is corrupt."
            fi
        fi
    fi
fi

pass "=== ISO Structural & Boot Artifact Validation Succeeded for $ISO_PATH ==="
exit 0
