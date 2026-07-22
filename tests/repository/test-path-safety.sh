#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Test path safety library rules.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
source "$REPO_ROOT/tools/repository/lib/safety.sh"

test_pass() {
    local path=$1
    local desc=$2
    if validate_repository_path "$path" "test" >/dev/null 2>&1; then
        printf '[PASS] Safety test passed (allowed): %s\n' "$desc"
    else
        printf '[FAIL] Safety test failed (expected allowed): %s\n' "$desc" >&2
        exit 1
    fi
}

test_fail() {
    local path=$1
    local desc=$2
    if ! validate_repository_path "$path" "test" >/dev/null 2>&1; then
        printf '[PASS] Safety test passed (correctly rejected): %s\n' "$desc"
    else
        printf '[FAIL] Safety test failed (expected rejected): %s\n' "$desc" >&2
        exit 1
    fi
}

# 1. Empty string -> FAIL
test_fail "" "empty path string"

# 2. Whitespace -> FAIL
test_fail "   " "whitespace path"

# 3. Root directory / -> FAIL
test_fail "/" "root directory /"

# 4. Root directory /root -> FAIL
test_fail "/root" "root directory /root"

# 5. User home directory -> FAIL
test_fail "$HOME" "user home directory \$HOME"

# 6. Nonexistent parent path -> FAIL
test_fail "/nonexistent_parent_dir_12345/subdir" "nonexistent parent path"

# 7. Safe temporary directory -> PASS
TMP_SAFE=$(mktemp -d)
test_pass "$TMP_SAFE" "safe temporary directory"
rm -rf "$TMP_SAFE"

# 8. Safe nested staging directory -> PASS
TMP_NESTED=$(mktemp -d)
mkdir -p "$TMP_NESTED/nested/staging"
test_pass "$TMP_NESTED/nested/staging" "safe nested staging directory"
rm -rf "$TMP_NESTED"

# 9. Path outside GENIXBIT_REPOSITORY_ROOT -> FAIL
TMP_ROOT=$(mktemp -d)
TMP_OUTSIDE=$(mktemp -d)
export GENIXBIT_REPOSITORY_ROOT="$TMP_ROOT"
test_fail "$TMP_OUTSIDE" "path outside GENIXBIT_REPOSITORY_ROOT"
unset GENIXBIT_REPOSITORY_ROOT
rm -rf "$TMP_ROOT" "$TMP_OUTSIDE"

printf '[PASS] All path safety tests passed successfully.\n'
