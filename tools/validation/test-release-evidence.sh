#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise the release-evidence checker with historical and active-release fixtures.

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
    printf '[FAIL] Incomplete historical evidence unexpectedly passed.\n' >&2
    exit 1
fi

printf '[PASS] Release-evidence checker accepts complete historical evidence and rejects incomplete evidence.\n'

write_active_fixture() {
    local path=$1
    local artifact_status=$2
    local overall_status=$3
    local provenance="${path%.env}-artifact.json"
    local source_commit="2222222222222222222222222222222222222222"

    cat >"$provenance" <<EOF
{
  "release_version": "1.0.0-lts",
  "candidate_branch": "feat/test-release-source",
  "candidate_sha": "$source_commit",
  "iso_filename": "GenixBitOS-1.0.0-lts-test.iso",
  "iso_size_bytes": 1024,
  "iso_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "validation_status": "PASS"
}
EOF

    cat >"$path" <<EOF
VALIDATION_VERSION=1.0.0-lts
ACTIVE_RELEASE_VERSION=1.0.0-lts
ACTIVE_RELEASE_MODE=fresh-install-and-upgrade
ACTIVE_RELEASE_PROVENANCE_FILE=$provenance
ACTIVE_RELEASE_ISO_LOCAL=dist/GenixBitOS-1.0.0-lts-test.iso
ACTIVE_RELEASE_ISO_URL=https://example.invalid/GenixBitOS-1.0.0-lts-test.iso
ACTIVE_RELEASE_SOURCE_COMMIT=$source_commit
CANDIDATE_BRANCH=main
CANDIDATE_SHA=1111111111111111111111111111111111111111
CANDIDATE_SELECTION_STATUS=PASS
HOST_STATUS=PASS
BUILD_STATUS=PASS
CHECKSUM_STATUS=PASS
SECURE_BOOT_STATUS=PASS
HYPERV_STATUS=PASS
PROXMOX_STATUS=PASS
LIVE_ENVIRONMENT_STATUS=PASS
CALAMARES_INSTALL_STATUS=PASS
OFFLINE_INSTALL_STATUS=PASS
INSTALLED_BOOT_STATUS=PASS
GPU_DRIVERS_STATUS=PASS
NETWORK_STACK_STATUS=PASS
AUDIO_STATUS=PASS
PACKAGE_ECOSYSTEM_STATUS=PASS
DESKTOP_UI_STATUS=PASS
UPSTREAM_PARITY_STATUS=PASS
RELEASE_ARTIFACT_STATUS=$artifact_status
AUTOMATED_EVIDENCE_STATUS=PASS
VALIDATION_WORKFLOW_STATUS=PASS
EVIDENCE_PR_STATUS=PASS
OVERALL_VALIDATION_STATUS=$overall_status
EOF
}

active_partial="$TMP_DIR/active-partial.env"
active_complete="$TMP_DIR/active-complete.env"
write_active_fixture "$active_partial" PENDING PARTIAL
write_active_fixture "$active_complete" PASS PASS

"$BASH" "$CHECKER" --status-file "$active_partial"
if "$BASH" "$CHECKER" --require-complete --status-file "$active_partial"; then
    printf '[FAIL] Incomplete active-release evidence unexpectedly passed --require-complete.\n' >&2
    exit 1
fi
"$BASH" "$CHECKER" --require-complete --status-file "$active_complete"
printf '[PASS] Active-release evidence accepts in-progress status and enforces completeness when requested.\n'

# Git-reference validation tests for historical candidate records.
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
