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

bash "$CHECKER" --require-complete --status-file "$complete_fixture"

if bash "$CHECKER" --require-complete --status-file "$incomplete_fixture"; then
    printf '[FAIL] Incomplete release evidence unexpectedly passed.\n' >&2
    exit 1
fi

printf '[PASS] Release-evidence checker accepts complete evidence and rejects incomplete evidence.\n'
