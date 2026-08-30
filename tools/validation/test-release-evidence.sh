#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise the release-evidence checker with complete and incomplete fixtures.

set -Eeuo pipefail
IFS=$'\n\t'

REPO_ROOT=$(git rev-parse --show-toplevel)
CHECKER="$REPO_ROOT/tools/validation/check-release-evidence.sh"
TMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

write_fixture() {
    local path=$1
    local host_status=$2
    local build_status=$3
    local overall_status=$4

    cat >"$path" <<EOF
VALIDATION_VERSION=0.1.0-alpha
CANDIDATE_BRANCH=validation/0.1.0-alpha-test-fixture
CANDIDATE_SHA=1111111111111111111111111111111111111111
CANDIDATE_SELECTION_STATUS=PASS
HOST_STATUS=$host_status
BUILD_STATUS=$build_status
CHECKSUM_STATUS=PASS
BIOS_STATUS=PASS
UEFI_STATUS=PASS
LIVE_SESSION_STATUS=PASS
INSTALLER_STATUS=PASS
INSTALLED_SYSTEM_STATUS=PASS
APT_STATUS=PASS
PACKAGE_HEALTH_STATUS=PASS
SECOND_BUILD_STATUS=PASS
REPRODUCIBILITY_STATUS=PASS
OVERALL_RELEASE_STATUS=$overall_status
EOF
}

complete_fixture="$TMP_DIR/complete.env"
incomplete_fixture="$TMP_DIR/incomplete.env"

write_fixture "$complete_fixture" PASS PASS PASS
write_fixture "$incomplete_fixture" FAIL NOT_TESTED PARTIAL

"$BASH" "$CHECKER" --require-complete --status-file "$complete_fixture"

if "$BASH" "$CHECKER" --require-complete --status-file "$incomplete_fixture"; then
    printf '[FAIL] Incomplete release evidence unexpectedly passed.\n' >&2
    exit 1
fi

printf '[PASS] Release-evidence checker accepts complete legacy evidence and rejects incomplete evidence.\n'

write_active_fixture() {
    local path=$1
    local iso_size=$2
    local iso_sha=$3
    local source_commit=$4

    cat >"$path" <<EOF
VALIDATION_VERSION=1.0.0-lts
ACTIVE_RELEASE_VERSION=1.0.0-lts
ACTIVE_RELEASE_MODE=fresh-install-and-upgrade
ACTIVE_RELEASE_PROVENANCE=docs/releases/1.0.0-lts-artifact.json
ISO_FILENAME=dist/GenixBitOS-1.0.0-lts-test.iso
ISO_URL=https://example.invalid/GenixBitOS-1.0.0-lts-test.iso
ISO_SHA256=$iso_sha
ISO_SIZE_BYTES=$iso_size
SOURCE_COMMIT=$source_commit
HOST_PREP_STATUS=PASS
FRESH_INSTALL_AMD64_STATUS=PASS
UPGRADE_PATH_STATUS=PASS
BRANDING_SUITE_STATUS=PASS
PACKAGE_SUITE_STATUS=PASS
SECURITY_SUITE_STATUS=PASS
CANDIDATE_BRANCH=main
CANDIDATE_SHA=1111111111111111111111111111111111111111
LAST_REHEARSAL_AT_UTC=2026-08-17T12:00:00Z
LAST_REHEARSAL_WORKFLOW=https://github.com/GenixBit/genixbit-os/actions/workflows/release-gate.yml
EOF
}

active_pending="$TMP_DIR/active-pending.env"
active_complete="$TMP_DIR/active-complete.env"
write_active_fixture "$active_pending" 0 "" "2222222222222222222222222222222222222222"
write_active_fixture "$active_complete" 1024 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "2222222222222222222222222222222222222222"

"$BASH" "$CHECKER" --status-file "$active_pending"
if "$BASH" "$CHECKER" --require-complete --status-file "$active_pending"; then
    printf '[FAIL] Incomplete active-release evidence unexpectedly passed --require-complete.\n' >&2
    exit 1
fi
"$BASH" "$CHECKER" --require-complete --status-file "$active_complete"
printf '[PASS] Active-release evidence supports pending publication and enforces completeness when requested.\n'

# Git-reference validation tests for legacy candidate records.
ACTUAL_CANDIDATE_SHA="4888b05eda7528b1ff0c607b9799201999d61031"

write_git_fixture() {
    local path=$1
    local branch=$2
    local sha=$3

    cat >"$path" <<EOF
VALIDATION_VERSION=0.1.0-alpha
CANDIDATE_BRANCH=$branch
CANDIDATE_SHA=$sha
CANDIDATE_SELECTION_STATUS=PASS
HOST_STATUS=PASS
BUILD_STATUS=PASS
CHECKSUM_STATUS=PASS
BIOS_STATUS=PASS
UEFI_STATUS=PASS
LIVE_SESSION_STATUS=PASS
INSTALLER_STATUS=PASS
INSTALLED_SYSTEM_STATUS=PASS
APT_STATUS=PASS
PACKAGE_HEALTH_STATUS=PASS
SECOND_BUILD_STATUS=PASS
REPRODUCIBILITY_STATUS=PASS
OVERALL_RELEASE_STATUS=PASS
EOF
}

git_pass_fixture="$TMP_DIR/git_pass.env"
write_git_fixture "$git_pass_fixture" "validation/0.1.0-alpha-candidate-2" "$ACTUAL_CANDIDATE_SHA"
"$BASH" "$CHECKER" --verify-git-candidate --status-file "$git_pass_fixture"
printf '[PASS] Git-reference validation: existing matching candidate passed.\n'

git_fail_sha_fixture="$TMP_DIR/git_fail_sha.env"
write_git_fixture "$git_fail_sha_fixture" "validation/0.1.0-alpha-candidate-2" "2222222222222222222222222222222222222222"
if "$BASH" "$CHECKER" --verify-git-candidate --status-file "$git_fail_sha_fixture" 2>/dev/null; then
    printf '[FAIL] Git-reference validation: nonexistent SHA unexpectedly passed.\n' >&2
    exit 1
fi
printf '[PASS] Git-reference validation: nonexistent SHA failed as expected.\n'

git_mismatch_fixture="$TMP_DIR/git_mismatch.env"
MAIN_SHA=$(git rev-parse HEAD)
write_git_fixture "$git_mismatch_fixture" "validation/0.1.0-alpha-candidate-2" "$MAIN_SHA"
if "$BASH" "$CHECKER" --verify-git-candidate --status-file "$git_mismatch_fixture" 2>/dev/null; then
    printf '[FAIL] Git-reference validation: branch/SHA mismatch unexpectedly passed.\n' >&2
    exit 1
fi
printf '[PASS] Git-reference validation: branch/SHA mismatch failed as expected.\n'

git_missing_branch_fixture="$TMP_DIR/git_missing_branch.env"
write_git_fixture "$git_missing_branch_fixture" "validation/does-not-exist-at-all" "$ACTUAL_CANDIDATE_SHA"
if "$BASH" "$CHECKER" --verify-git-candidate --status-file "$git_missing_branch_fixture" 2>/dev/null; then
    printf '[FAIL] Git-reference validation: missing candidate branch unexpectedly passed.\n' >&2
    exit 1
fi
printf '[PASS] Git-reference validation: missing candidate branch failed as expected.\n'
