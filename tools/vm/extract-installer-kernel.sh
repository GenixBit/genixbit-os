#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Extracts /casper/vmlinuz and /casper/initrd from a verified Candidate 2 ISO.
# Uses xorriso -osirrox for real ISO extraction. Fails closed on any missing or empty result.
# Records SHA-256 and SHA-512 of both files and emits a JSON evidence record.
#
# Usage:
#   bash extract-installer-kernel.sh \
#     --iso        /path/to/verified.iso \
#     --out-dir    /path/to/output/dir \
#     --out-json   /path/to/kernel-extraction.json   # optional

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
OUT_DIR=""
OUT_JSON=""

fail() {
    printf '[FAIL] extract-installer-kernel.sh: %s\n' "$*" >&2
    exit 1
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
        --out-dir)
            (($# >= 2)) || fail '--out-dir requires a path.'
            OUT_DIR=$2
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

[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || fail '--iso must point to an existing file.'
[[ -n "$OUT_DIR" ]] || fail '--out-dir is required.'
[[ -n "$OUT_JSON" ]] || OUT_JSON="${OUT_DIR}/kernel-extraction.json"

mkdir -p "$OUT_DIR"

# Require xorriso — no synthetic fallback permitted
command -v xorriso >/dev/null 2>&1 || fail 'xorriso not found. Install xorriso to extract installer kernel and initrd.'

VMLINUZ_OUT="${OUT_DIR}/vmlinuz"
INITRD_OUT="${OUT_DIR}/initrd"

# Record the verified source ISO SHA-256 and SHA-512
info "Computing SHA-256/SHA-512 of source ISO before extraction..."
SOURCE_ISO_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
SOURCE_ISO_SHA512=$(sha512sum "$ISO_PATH" | awk '{print $1}')
info "Source ISO SHA-256: $SOURCE_ISO_SHA256"
info "Source ISO SHA-512: ${SOURCE_ISO_SHA512:0:16}..."

# Extract /casper/vmlinuz
info "Extracting /casper/vmlinuz from ISO..."
rm -f "$VMLINUZ_OUT"
xorriso -osirrox on \
    -indev "$ISO_PATH" \
    -extract /casper/vmlinuz "$VMLINUZ_OUT" 2>/dev/null \
|| xorriso -osirrox on \
    -indev "$ISO_PATH" \
    -extract /install/vmlinuz "$VMLINUZ_OUT" 2>/dev/null \
|| fail "xorriso failed to extract /casper/vmlinuz (and /install/vmlinuz) from ISO."

[[ -f "$VMLINUZ_OUT" ]] || fail "vmlinuz not found at $VMLINUZ_OUT after extraction."
[[ -s "$VMLINUZ_OUT" ]] || fail "Extracted vmlinuz is empty — ISO does not contain a valid kernel."
VMLINUZ_SIZE=$(stat -c%s "$VMLINUZ_OUT" 2>/dev/null || stat -f%z "$VMLINUZ_OUT")
(( VMLINUZ_SIZE > 100000 )) || fail "Extracted vmlinuz ($VMLINUZ_SIZE bytes) is suspiciously small — extraction may have failed."

VMLINUZ_SHA256=$(sha256sum "$VMLINUZ_OUT" | awk '{print $1}')
VMLINUZ_SHA512=$(sha512sum "$VMLINUZ_OUT" | awk '{print $1}')
info "vmlinuz extracted: size=${VMLINUZ_SIZE} sha256=${VMLINUZ_SHA256}"

# Extract /casper/initrd
info "Extracting /casper/initrd from ISO..."
rm -f "$INITRD_OUT"
xorriso -osirrox on \
    -indev "$ISO_PATH" \
    -extract /casper/initrd "$INITRD_OUT" 2>/dev/null \
|| xorriso -osirrox on \
    -indev "$ISO_PATH" \
    -extract /casper/initrd.lz "$INITRD_OUT" 2>/dev/null \
|| xorriso -osirrox on \
    -indev "$ISO_PATH" \
    -extract /install/initrd.gz "$INITRD_OUT" 2>/dev/null \
|| fail "xorriso failed to extract /casper/initrd (or /casper/initrd.lz, /install/initrd.gz) from ISO."

[[ -f "$INITRD_OUT" ]] || fail "initrd not found at $INITRD_OUT after extraction."
[[ -s "$INITRD_OUT" ]] || fail "Extracted initrd is empty — ISO does not contain a valid initrd."
INITRD_SIZE=$(stat -c%s "$INITRD_OUT" 2>/dev/null || stat -f%z "$INITRD_OUT")
(( INITRD_SIZE > 1000000 )) || fail "Extracted initrd ($INITRD_SIZE bytes) is suspiciously small — extraction may have failed."

INITRD_SHA256=$(sha256sum "$INITRD_OUT" | awk '{print $1}')
INITRD_SHA512=$(sha512sum "$INITRD_OUT" | awk '{print $1}')
info "initrd extracted: size=${INITRD_SIZE} sha256=${INITRD_SHA256}"

EXTRACTION_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c "
import json
result = {
    'status': 'PASS',
    'extraction_timestamp': '$EXTRACTION_TIMESTAMP',
    'source_iso_path': '$ISO_PATH',
    'source_iso_sha256': '$SOURCE_ISO_SHA256',
    'source_iso_sha512': '$SOURCE_ISO_SHA512',
    'vmlinuz_path': '$VMLINUZ_OUT',
    'vmlinuz_sha256': '$VMLINUZ_SHA256',
    'vmlinuz_sha512': '$VMLINUZ_SHA512',
    'vmlinuz_size_bytes': $VMLINUZ_SIZE,
    'initrd_path': '$INITRD_OUT',
    'initrd_sha256': '$INITRD_SHA256',
    'initrd_sha512': '$INITRD_SHA512',
    'initrd_size_bytes': $INITRD_SIZE,
}
with open('$OUT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
"

printf '[PASS] extract-installer-kernel.sh: vmlinuz and initrd extracted and verified from canonical Candidate 2 ISO.\n'
printf 'KERNEL_EXTRACTION_JSON=%s\n' "$OUT_JSON"
exit 0
