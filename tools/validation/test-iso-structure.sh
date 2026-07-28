#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
CHECKER="$REPO_ROOT/tools/validation/check-iso-structure.sh"
TMP_DIR=$(mktemp -d)
TOTAL=0
PASS=0

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_tool() {
    command -v "$1" >/dev/null 2>&1 || {
        printf '[FAIL] Required test tool missing: %s\n' "$1" >&2
        exit 1
    }
}

run_expect_pass() {
    local name="$1"
    local log_name
    log_name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9_.-' '_')
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" > "$TMP_DIR/${log_name}.stdout" 2> "$TMP_DIR/${log_name}.stderr"; then
        PASS=$((PASS + 1))
        printf '[PASS] %s\n' "$name"
    else
        printf '[FAIL] %s unexpectedly failed\n' "$name" >&2
        sed -n '1,120p' "$TMP_DIR/${log_name}.stderr" >&2
        exit 1
    fi
}

run_expect_fail() {
    local name="$1"
    local log_name
    log_name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9_.-' '_')
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" > "$TMP_DIR/${log_name}.stdout" 2> "$TMP_DIR/${log_name}.stderr"; then
        printf '[FAIL] %s unexpectedly passed\n' "$name" >&2
        sed -n '1,120p' "$TMP_DIR/${log_name}.stdout" >&2
        exit 1
    else
        PASS=$((PASS + 1))
        printf '[PASS] %s\n' "$name"
    fi
}

make_efi_image() {
    local image="$1"
    local efi_bin="$TMP_DIR/BOOTX64.EFI"
    printf 'synthetic EFI executable\n' > "$efi_bin"
    dd if=/dev/zero of="$image" bs=1M count=4 status=none
    mformat -i "$image" ::
    mmd -i "$image" ::/EFI ::/EFI/BOOT
    mcopy -i "$image" "$efi_bin" ::/EFI/BOOT/BOOTX64.EFI
}

make_iso() {
    local iso="$1"
    local variant="${2:-complete}"
    local root="$TMP_DIR/root-${variant}-$(basename "$iso")"
    local squash_root="$TMP_DIR/squash-${variant}-$(basename "$iso")"
    mkdir -p "$root/casper" "$root/isolinux" "$squash_root/etc"

    printf 'synthetic kernel\n' > "$root/casper/vmlinuz"
    printf 'synthetic initrd\n' > "$root/casper/initrd"
    printf 'NAME=GenixBit Synthetic\n' > "$squash_root/etc/os-release"
    mksquashfs "$squash_root" "$root/casper/filesystem.squashfs" -noappend -quiet >/dev/null
    make_efi_image "$root/isolinux/efiboot.img"

    case "$variant" in
        missing-vmlinuz)
            rm -f "$root/casper/vmlinuz"
            ;;
        missing-initrd)
            rm -f "$root/casper/initrd"
            ;;
        missing-squashfs)
            rm -f "$root/casper/filesystem.squashfs"
            ;;
        invalid-squashfs)
            printf 'not a squashfs\n' > "$root/casper/filesystem.squashfs"
            ;;
        no-efi)
            rm -f "$root/isolinux/efiboot.img"
            ;;
        complete)
            ;;
        *)
            printf '[FAIL] Unknown ISO variant: %s\n' "$variant" >&2
            exit 1
            ;;
    esac

    if [[ "$variant" == "no-efi" ]]; then
        xorriso -as mkisofs -quiet -o "$iso" -V GENIXBIT_TEST -J -r "$root"
    else
        xorriso -as mkisofs -quiet -o "$iso" -V GENIXBIT_TEST -J -r \
            -eltorito-alt-boot -e isolinux/efiboot.img -no-emul-boot "$root"
    fi
}

for tool in python3 xorriso mksquashfs unsquashfs mformat mmd mcopy dd; do
    require_tool "$tool"
done

run_expect_fail "missing ISO path fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER"
run_expect_fail "nonexistent ISO path fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/does-not-exist.iso"

dd if=/dev/zero of="$TMP_DIR/undersized.iso" bs=1024 count=1 status=none
run_expect_fail "undersized file fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/undersized.iso"

dd if=/dev/zero of="$TMP_DIR/zero-large.iso" bs=1M count=2 status=none
run_expect_fail "sparse zero-filled file larger than minimum fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/zero-large.iso"

dd if=/dev/urandom of="$TMP_DIR/random-large.iso" bs=1M count=2 status=none
run_expect_fail "sufficiently large random file fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/random-large.iso"

python3 - "$TMP_DIR/forged-cd001.iso" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "wb") as f:
    f.truncate(2 * 1024 * 1024)
    f.seek(16 * 2048)
    f.write(b"\x01CD001")
PYEOF
run_expect_fail "forged CD001 without ISO filesystem fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/forged-cd001.iso"

make_iso "$TMP_DIR/valid.iso" complete
run_expect_pass "structurally valid synthetic ISO passes" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/valid.iso"

cp "$TMP_DIR/valid.iso" "$TMP_DIR/valid-padded.iso"
dd if=/dev/zero bs=1M count=8 status=none >> "$TMP_DIR/valid-padded.iso"
run_expect_pass "structurally valid ISO with zero padding passes" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/valid-padded.iso"

make_iso "$TMP_DIR/missing-vmlinuz.iso" missing-vmlinuz
run_expect_fail "valid ISO missing /casper/vmlinuz fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/missing-vmlinuz.iso"

make_iso "$TMP_DIR/missing-initrd.iso" missing-initrd
run_expect_fail "valid ISO missing /casper/initrd fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/missing-initrd.iso"

make_iso "$TMP_DIR/missing-squashfs.iso" missing-squashfs
run_expect_fail "valid ISO missing /casper/filesystem.squashfs fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/missing-squashfs.iso"

make_iso "$TMP_DIR/invalid-squashfs.iso" invalid-squashfs
run_expect_fail "valid ISO with invalid SquashFS fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/invalid-squashfs.iso"

make_iso "$TMP_DIR/no-efi.iso" no-efi
run_expect_fail "ISO without valid EFI boot image fails" env MIN_ISO_SIZE_MB=1 bash "$CHECKER" --iso "$TMP_DIR/no-efi.iso"

printf '[PASS] ISO structure validation tests passed: %s/%s\n' "$PASS" "$TOTAL"
