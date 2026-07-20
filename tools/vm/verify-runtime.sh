#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — validation-candidate build and VM preflight orchestrator.
#
# This script builds one fresh ISO from an explicitly approved commit, records
# the artifact outside Git, verifies BIOS/UEFI metadata and EFI fallback files,
# and prints the commands required for direct interactive testing.
#
# It does not claim that live-desktop, installer, installed-system or
# reproducibility validation has passed.
#
# Copyright (C) 2026 GenixBit Labs Private Limited

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
EXPECTED_COMMIT=""
SKIP_HOST_INSTALL=false
ALLOW_SOFTWARE_EMULATION=false
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/genixbit-os-validation"

info() { printf '[INFO] %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; }
die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: ${PROGRAM} --expected-commit SHA [options]

Required:
  --expected-commit SHA          Full 40-character validation-candidate SHA.

Options:
  --skip-host-install            Audit host packages without installing them.
  --allow-software-emulation     Permit validation without accessible KVM.
  --state-dir PATH               Private evidence/state directory.
  -h, --help                     Show this help.
EOF
}

while (($# > 0)); do
    case "$1" in
        --expected-commit)
            (($# >= 2)) || die '--expected-commit requires a SHA.'
            EXPECTED_COMMIT=$2
            shift 2
            ;;
        --skip-host-install)
            SKIP_HOST_INSTALL=true
            shift
            ;;
        --allow-software-emulation)
            ALLOW_SOFTWARE_EMULATION=true
            shift
            ;;
        --state-dir)
            (($# >= 2)) || die '--state-dir requires a path.'
            STATE_DIR=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

[[ "$EXPECTED_COMMIT" =~ ^[[:xdigit:]]{40}$ ]] || die '--expected-commit must be a full 40-character SHA.'

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die 'Run this script from a GenixBit OS Git checkout.'
cd "$REPO_ROOT"

ACTUAL_COMMIT=$(git rev-parse HEAD)
[[ "${ACTUAL_COMMIT,,}" == "${EXPECTED_COMMIT,,}" ]] || die "Checkout mismatch. Expected $EXPECTED_COMMIT; found $ACTUAL_COMMIT."

if [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
    git status --short >&2
    die 'The validation checkout must be clean before building.'
fi

mkdir -p "$STATE_DIR"
STATE_DIR=$(realpath "$STATE_DIR")

case "$STATE_DIR" in
    "$REPO_ROOT"|"$REPO_ROOT"/*)
        die 'The validation state directory must be outside the Git repository.'
        ;;
esac

umask 077
STARTED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
SHORT_COMMIT=${ACTUAL_COMMIT:0:12}
MANIFEST="$STATE_DIR/validation-${SHORT_COMMIT}.env"
BOOT_REPORT="$STATE_DIR/boot-metadata-${SHORT_COMMIT}.txt"

info "GenixBit OS validation-candidate build"
info "Commit: $ACTUAL_COMMIT"
info "Private state directory: $STATE_DIR"

HOST_ARGS=()
if [[ "$SKIP_HOST_INSTALL" == true ]]; then
    HOST_ARGS+=(--skip-install)
fi
if [[ "$ALLOW_SOFTWARE_EMULATION" == true ]]; then
    HOST_ARGS+=(--allow-software-emulation)
fi

tools/vm/setup-host.sh "${HOST_ARGS[@]}" || die 'Host readiness check failed.'

info 'Building a clean validation ISO...'
make clean
make bootstrap
make

ISO_PATH=$(find dist -maxdepth 1 -type f -name 'GenixBitOS-0.1.0-alpha-*.iso' -printf '%T@ %p\n' \
    | sort -n \
    | tail -n 1 \
    | cut -d' ' -f2-)
[[ -n "$ISO_PATH" ]] || die 'No ISO artifact was generated in dist/.'
ISO_PATH=$(realpath "$ISO_PATH")

ISO_SIZE=$(stat -c '%s' "$ISO_PATH")
SHA256_DIGEST=$(sha256sum "$ISO_PATH" | awk '{print $1}')
CHECKSUM_FILE="${ISO_PATH%.iso}.sha256"

if [[ -f "$CHECKSUM_FILE" ]]; then
    RECORDED_DIGEST=$(awk 'NF {print $1; exit}' "$CHECKSUM_FILE")
    [[ "${RECORDED_DIGEST,,}" == "${SHA256_DIGEST,,}" ]] \
        || die "Generated checksum mismatch. File records $RECORDED_DIGEST; calculated $SHA256_DIGEST."
    pass 'Generated checksum file matches the ISO.'
else
    die "Expected checksum file was not generated: $CHECKSUM_FILE"
fi

file "$ISO_PATH" | tee "$STATE_DIR/file-${SHORT_COMMIT}.txt"
isoinfo -d -i "$ISO_PATH" >"$STATE_DIR/isoinfo-${SHORT_COMMIT}.txt"
xorriso -indev "$ISO_PATH" -report_el_torito as_mkisofs >"$BOOT_REPORT" 2>&1
pass 'ISO metadata and El Torito boot report were recorded privately.'

TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

EFI_IMAGE="$TMP_DIR/efiboot.img"
if xorriso -osirrox on -indev "$ISO_PATH" -extract /isolinux/efiboot.img "$EFI_IMAGE" \
    >"$STATE_DIR/efi-extract-${SHORT_COMMIT}.txt" 2>&1; then
    if mdir -i "$EFI_IMAGE" ::/EFI/BOOT/BOOTX64.EFI \
        >"$STATE_DIR/efi-directory-${SHORT_COMMIT}.txt" 2>&1; then
        pass 'EFI fallback image contains EFI/BOOT/BOOTX64.EFI.'
    else
        die 'EFI image exists but EFI/BOOT/BOOTX64.EFI was not found.'
    fi
else
    die 'Unable to extract /isolinux/efiboot.img from the validation ISO.'
fi

FINISHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
cat >"$MANIFEST" <<EOF
VALIDATION_COMMIT=$ACTUAL_COMMIT
VALIDATION_STARTED_AT=$STARTED_AT
VALIDATION_BUILD_FINISHED_AT=$FINISHED_AT
VALIDATION_ISO=$ISO_PATH
VALIDATION_ISO_SIZE=$ISO_SIZE
VALIDATION_SHA256=$SHA256_DIGEST
VALIDATION_CHECKSUM_FILE=$CHECKSUM_FILE
VALIDATION_BOOT_REPORT=$BOOT_REPORT
RUNTIME_BIOS_STATUS=NOT_TESTED
RUNTIME_UEFI_STATUS=NOT_TESTED
INSTALLER_STATUS=NOT_TESTED
INSTALLED_SYSTEM_STATUS=NOT_TESTED
REPRODUCIBILITY_STATUS=NOT_TESTED
EOF
chmod 600 "$MANIFEST"
pass "Private validation manifest written: $MANIFEST"

VM_STATE_DIR="$STATE_DIR/vm"
mkdir -p "$VM_STATE_DIR"

tools/vm/run-qemu.sh \
    --mode bios \
    --iso "$ISO_PATH" \
    --sha256 "$SHA256_DIGEST" \
    --state-dir "$VM_STATE_DIR" \
    --create-disk \
    --dry-run

tools/vm/run-qemu.sh \
    --mode uefi \
    --iso "$ISO_PATH" \
    --sha256 "$SHA256_DIGEST" \
    --state-dir "$VM_STATE_DIR" \
    --create-disk \
    --dry-run

printf '\n'
printf '═══════════════════════════════════════════════════════\n'
printf '  Current GenixBit OS validation artifact\n'
printf '═══════════════════════════════════════════════════════\n'
printf '  Commit:  %s\n' "$ACTUAL_COMMIT"
printf '  ISO:     %s\n' "$ISO_PATH"
printf '  Size:    %s bytes\n' "$ISO_SIZE"
printf '  SHA-256: %s\n' "$SHA256_DIGEST"
printf '  Manifest:%s\n' "$MANIFEST"
printf '═══════════════════════════════════════════════════════\n'
printf '\n'

info 'Run the following commands and directly observe the graphical sessions.'
printf 'BIOS live session:\n'
printf '  tools/vm/run-qemu.sh --mode bios --iso %q --sha256 %q --state-dir %q --create-disk\n' \
    "$ISO_PATH" "$SHA256_DIGEST" "$VM_STATE_DIR"
printf '\nUEFI live session and installer:\n'
printf '  tools/vm/run-qemu.sh --mode uefi --iso %q --sha256 %q --state-dir %q --create-disk\n' \
    "$ISO_PATH" "$SHA256_DIGEST" "$VM_STATE_DIR"
printf '\nBoot installed UEFI disk:\n'
printf '  tools/vm/run-qemu.sh --mode uefi --installed --state-dir %q --disk %q\n' \
    "$VM_STATE_DIR" "$VM_STATE_DIR/genixbit-uefi.qcow2"
printf '\nBoot installed BIOS disk:\n'
printf '  tools/vm/run-qemu.sh --mode bios --installed --state-dir %q --disk %q\n' \
    "$VM_STATE_DIR" "$VM_STATE_DIR/genixbit-bios.qcow2"
printf '\n'

info 'This script completed build and preflight validation only.'
info 'Live desktop, installer, installed-system and second-build comparison remain NOT TESTED until directly performed and recorded.'
