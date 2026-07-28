#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
TOTAL=0
PASS=0

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    printf '[PASS] %s\n' "$1"
}

expect_fail() {
    local name="$1"
    local text="$2"
    local file="$TMP_DIR/bad-$TOTAL.md"
    TOTAL=$((TOTAL + 1))
    printf '%s\n' "$text" > "$file"
    if python3 "$REPO_ROOT/tools/validation/check-retired-candidate-claims.py" "$file" > "$file.out" 2> "$file.err"; then
        printf '[FAIL] %s accepted forbidden claim\n' "$name" >&2
        exit 1
    fi
    grep -q 'Retired Candidate 2 claim check failed' "$file.err"
    pass "$name"
}

expect_pass() {
    local name="$1"
    local text="$2"
    local file="$TMP_DIR/good-$TOTAL.md"
    TOTAL=$((TOTAL + 1))
    printf '%s\n' "$text" > "$file"
    python3 "$REPO_ROOT/tools/validation/check-retired-candidate-claims.py" "$file" > "$file.out" 2> "$file.err"
    grep -q 'Retired Candidate 2 claim check passed' "$file.out"
    pass "$name"
}

expect_fail "rejects validated release wording" "Validated 0.2.0-alpha release based on Ubuntu 26.04 Resolute."
expect_fail "rejects Candidate 2 validation success" "0.2.0-alpha Candidate 2 validation successful."
expect_fail "rejects release validation complete" "Candidate 2 status: **PASS** (Release validation complete)"
expect_fail "rejects ISO availability" "ISO Distribution: AVAILABLE (0.2.0-alpha)"
expect_fail "rejects verified installation image wording" "The bucket serves verified ISO installation images only."
expect_fail "rejects live desktop boot wording" "Candidate 2: Candidate ISO boots to live desktop under UEFI."
expect_fail "rejects Build A/B ISO reproducibility" "0.2.0-alpha Candidate 2 Build A and Build B ISOs are 100% byte-for-byte identical."

expect_pass "allows retired object classification" "Candidate 2 artifact status: RETIRED_INVALID_ZERO_FILLED. Evidence classification: RETRACTED_UNBOUND_EVIDENCE. Release status: NOT_VALIDATED."
expect_pass "allows historical source pointers" "Candidate branch validation/0.2.0-alpha-candidate-2 at SHA 88a1550a9129a80ffd2c4cf73838122020a782cb is retained for audit only."

TOTAL=$((TOTAL + 1))
python3 "$REPO_ROOT/tools/validation/check-retired-candidate-claims.py"
pass "repository retired Candidate 2 claim scan passes"

printf '[PASS] retired Candidate 2 claim tests passed: %s/%s\n' "$PASS" "$TOTAL"
