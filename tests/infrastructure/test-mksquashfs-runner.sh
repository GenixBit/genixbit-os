#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verifies runner mksquashfs compatibility and SOURCE_DATE_EPOCH reproducibility.

set -Eeuo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR:?}"' EXIT

mkdir -p "$TEST_DIR/root"
printf 'GenixBit squashfs preflight\n' > "$TEST_DIR/root/test.txt"

export SOURCE_DATE_EPOCH=1700000000

printf '[INFO] mksquashfs version:\n'
mksquashfs -version
printf '[INFO] SOURCE_DATE_EPOCH=%s\n' "$SOURCE_DATE_EPOCH"

env SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
mksquashfs \
    "$TEST_DIR/root" \
    "$TEST_DIR/test-one.squashfs" \
    -noappend \
    -no-duplicates \
    -no-recovery \
    -comp zstd \
    -Xcompression-level 19

[[ -s "$TEST_DIR/test-one.squashfs" ]]
unsquashfs -s "$TEST_DIR/test-one.squashfs"

env SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
mksquashfs \
    "$TEST_DIR/root" \
    "$TEST_DIR/test-two.squashfs" \
    -noappend \
    -no-duplicates \
    -no-recovery \
    -comp zstd \
    -Xcompression-level 19

[[ -s "$TEST_DIR/test-two.squashfs" ]]

sha_one=$(sha256sum "$TEST_DIR/test-one.squashfs" | awk '{print $1}')
sha_two=$(sha256sum "$TEST_DIR/test-two.squashfs" | awk '{print $1}')

printf '[INFO] first image SHA-256: %s\n' "$sha_one"
printf '[INFO] second image SHA-256: %s\n' "$sha_two"

[[ "$sha_one" == "$sha_two" ]]

printf '[PASS] mksquashfs runner compatibility passed\n'
printf '[PASS] two squashfs outputs had matching SHA-256\n'
printf 'MKSQUASHFS_SOURCE_DATE_EPOCH=%s\n' "$SOURCE_DATE_EPOCH"
printf 'MKSQUASHFS_SHA_ONE=%s\n' "$sha_one"
printf 'MKSQUASHFS_SHA_TWO=%s\n' "$sha_two"
printf 'MKSQUASHFS_REPRODUCIBILITY=PASS\n'
