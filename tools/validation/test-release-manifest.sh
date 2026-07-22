#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Test release manifest validation behavior.

set -Eeuo pipefail
IFS=$'\n\t'

TMP_DIR=""

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

TMP_DIR=$(mktemp -d)

# Setup dummy environment files
DUMMY_ARGS="$TMP_DIR/args.sh"
DUMMY_STATUS="$TMP_DIR/VALIDATION-STATUS.env"
DUMMY_MANIFEST="$TMP_DIR/0.2.0-alpha.env"

cat <<'EOF' > "$DUMMY_ARGS"
export TARGET_BUILD_VERSION="0.2.0-alpha"
EOF

cat <<'EOF' > "$DUMMY_STATUS"
VALIDATION_VERSION=0.2.0-alpha
CANDIDATE_BRANCH=validation/0.2.0-alpha-candidate-2
CANDIDATE_SHA=88a1550a9129a80ffd2c4cf73838122020a782cb
EOF

write_manifest() {
    local version=${1:-"0.2.0-alpha"}
    local branch=${2:-"validation/0.2.0-alpha-candidate-2"}
    local sha=${3:-"88a1550a9129a80ffd2c4cf73838122020a782cb"}
    local iso=${4:-"GenixBitOS-0.2.0-alpha-2607220558.iso"}
    local size=${5:-"2540554240"}
    local checksum=${6:-"d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228"}
    local pr=${7:-"40"}
    local status=${8:-"PASS"}

    cat <<EOF > "$DUMMY_MANIFEST"
RELEASE_VERSION=$version
CANDIDATE_BRANCH=$branch
CANDIDATE_SHA=$sha
ISO_FILENAME=$iso
ISO_SIZE_BYTES=$size
ISO_SHA256=$checksum
BUILD_DATE=2026-07-22
EVIDENCE_PR=$pr
VALIDATION_STATUS=$status
EOF
}

test_pass() {
    local desc=$1
    if bash tools/validation/check-release-manifest.sh \
        --manifest "$DUMMY_MANIFEST" \
        --args-file "$DUMMY_ARGS" \
        --status-file "$DUMMY_STATUS" >/dev/null 2>&1; then
        printf '[PASS] Behavior test passed: %s\n' "$desc"
    else
        printf '[FAIL] Behavior test failed (expected PASS): %s\n' "$desc" >&2
        exit 1
    fi
}

test_fail() {
    local desc=$1
    if ! bash tools/validation/check-release-manifest.sh \
        --manifest "$DUMMY_MANIFEST" \
        --args-file "$DUMMY_ARGS" \
        --status-file "$DUMMY_STATUS" >/dev/null 2>&1; then
        printf '[PASS] Behavior test passed (correctly rejected): %s\n' "$desc"
    else
        printf '[FAIL] Behavior test failed (expected FAIL): %s\n' "$desc" >&2
        exit 1
    fi
}

# 1. Valid manifest -> PASS
write_manifest
test_pass "valid manifest"

# 2. Wrong candidate SHA -> FAIL
write_manifest "0.2.0-alpha" "validation/0.2.0-alpha-candidate-2" "1234567890123456789012345678901234567890"
test_fail "wrong candidate SHA"

# 3. Wrong ISO version -> FAIL
write_manifest "0.2.0-alpha" "validation/0.2.0-alpha-candidate-2" "88a1550a9129a80ffd2c4cf73838122020a782cb" "GenixBitOS-0.1.0-alpha-2607220558.iso"
test_fail "wrong ISO version"

# 4. Invalid size -> FAIL
write_manifest "0.2.0-alpha" "validation/0.2.0-alpha-candidate-2" "88a1550a9129a80ffd2c4cf73838122020a782cb" "GenixBitOS-0.2.0-alpha-2607220558.iso" "2,540,554,240"
test_fail "invalid size"

# 5. Invalid checksum -> FAIL
write_manifest "0.2.0-alpha" "validation/0.2.0-alpha-candidate-2" "88a1550a9129a80ffd2c4cf73838122020a782cb" "GenixBitOS-0.2.0-alpha-2607220558.iso" "2540554240" "INVALIDCHECKSUM"
test_fail "invalid checksum"

# 6. Validation-status mismatch -> FAIL
write_manifest "0.2.0-alpha" "validation/0.2.0-alpha-candidate-2" "88a1550a9129a80ffd2c4cf73838122020a782cb" "GenixBitOS-0.2.0-alpha-2607220558.iso" "2540554240" "d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228" "40" "FAIL"
test_fail "validation-status mismatch"

# 7. Build-version mismatch -> FAIL
write_manifest "0.3.0-alpha" "validation/0.2.0-alpha-candidate-2" "88a1550a9129a80ffd2c4cf73838122020a782cb" "GenixBitOS-0.3.0-alpha-2607220558.iso"
test_fail "build-version mismatch"

printf '[PASS] All release manifest behavior tests passed.\n'
