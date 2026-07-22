#!/usr/bin/env bash
set -Eeuo pipefail

# Find repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CHECKER_SCRIPT="$REPO_ROOT/tools/validation/check-release-version-consistency.sh"

TEST_DIR=$(mktemp -d -t test-version-consistency-XXXXXX)
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Helper to run the checker in a mocked environment
run_test_env() {
    local env_dir="$1"
    shift
    # Run the checker in the mocked repository structure
    (cd "$env_dir" && bash "$CHECKER_SCRIPT" "$@")
}

# Helper to set up the default mock directory
setup_mock_env() {
    local env_dir="$1"
    mkdir -p "$env_dir/docs"
    mkdir -p "$env_dir/packages/genixbit-os-base-files/usr/lib"
    mkdir -p "$env_dir/packages/genixbit-os-theme/debian"

    # Write default matching 0.2.0-alpha values
    cat <<EOF > "$env_dir/args.sh"
export TARGET_BUILD_VERSION="0.2.0-alpha"
EOF

    cat <<EOF > "$env_dir/docs/VALIDATION-STATUS.env"
VALIDATION_VERSION=0.2.0-alpha
EOF

    cat <<EOF > "$env_dir/packages/genixbit-os-base-files/usr/lib/os-release"
NAME="GenixBit OS"
VERSION="0.2.0-alpha"
VERSION_ID="0.2.0-alpha"
PRETTY_NAME="GenixBit OS 0.2.0-alpha"
EOF

    cat <<EOF > "$env_dir/packages/genixbit-os-theme/debian/changelog"
genixbit-os-theme (0.2.0-alpha-1) resolute; urgency=medium
EOF
}

echo "=== Running Version Consistency Behavioral Tests ==="

# Test case 1: Matching 0.2.0-alpha values (PASS)
TC1="$TEST_DIR/tc1"
setup_mock_env "$TC1"
if run_test_env "$TC1"; then
    echo "[PASS] Test 1: Matching 0.2.0-alpha values passed as expected."
else
    echo "[FAIL] Test 1: Matching 0.2.0-alpha values failed."
    exit 1
fi

# Test case 2: TARGET_BUILD_VERSION mismatch (FAIL)
TC2="$TEST_DIR/tc2"
setup_mock_env "$TC2"
cat <<EOF > "$TC2/args.sh"
export TARGET_BUILD_VERSION="0.1.0-alpha"
EOF
if run_test_env "$TC2" >/dev/null 2>&1; then
    echo "[FAIL] Test 2: TARGET_BUILD_VERSION mismatch passed but should have failed."
    exit 1
else
    echo "[PASS] Test 2: TARGET_BUILD_VERSION mismatch failed as expected."
fi

# Test case 3: os-release VERSION_ID mismatch (FAIL)
TC3="$TEST_DIR/tc3"
setup_mock_env "$TC3"
cat <<EOF > "$TC3/packages/genixbit-os-base-files/usr/lib/os-release"
NAME="GenixBit OS"
VERSION="0.2.0-alpha"
VERSION_ID="0.1.0-alpha"
PRETTY_NAME="GenixBit OS 0.2.0-alpha"
EOF
if run_test_env "$TC3" >/dev/null 2>&1; then
    echo "[FAIL] Test 3: os-release VERSION_ID mismatch passed but should have failed."
    exit 1
else
    echo "[PASS] Test 3: os-release VERSION_ID mismatch failed as expected."
fi

# Test case 4: Wrong ISO filename (FAIL)
TC4="$TEST_DIR/tc4"
setup_mock_env "$TC4"
if run_test_env "$TC4" --iso "/tmp/GenixBitOS-0.1.0-alpha-2607212122.iso" >/dev/null 2>&1; then
    echo "[FAIL] Test 4: Wrong ISO filename passed but should have failed."
    exit 1
else
    echo "[PASS] Test 4: Wrong ISO filename failed as expected."
fi

# Test case 4b: Correct ISO filename (PASS)
if run_test_env "$TC4" --iso "/tmp/GenixBitOS-0.2.0-alpha-2607212122.iso" >/dev/null 2>&1; then
    echo "[PASS] Test 4b: Correct ISO filename passed as expected."
else
    echo "[FAIL] Test 4b: Correct ISO filename failed."
    exit 1
fi

# Test case 5: Missing version field in args.sh (FAIL)
TC5="$TEST_DIR/tc5"
setup_mock_env "$TC5"
cat <<EOF > "$TC5/args.sh"
export TARGET_NAME="genixbitos"
EOF
if run_test_env "$TC5" >/dev/null 2>&1; then
    echo "[FAIL] Test 5: Missing version field passed but should have failed."
    exit 1
else
    echo "[PASS] Test 5: Missing version field failed as expected."
fi

echo "[ALL PASS] Release version consistency check behaves correctly."
exit 0
