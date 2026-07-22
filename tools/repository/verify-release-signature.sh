#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verify APT Release metadata signatures failing closed on any error.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: verify-release-signature.sh --release-file PATH --keyring PATH [--expected-fingerprint FPR]

Options:
  --release-file PATH            Path to InRelease or Release file.
  --keyring PATH                 Path to public OpenPGP keyring file (.pgp, .gpg, .asc).
  --expected-fingerprint FPR     Optional expected 40-character hex fingerprint.
  -h, --help                     Show this help.
EOF
}

RELEASE_FILE=""
KEYRING=""
EXPECTED_FPR=""

while (($# > 0)); do
    case "$1" in
        --release-file)
            (($# >= 2)) || { echo "Error: --release-file requires a path." >&2; exit 1; }
            RELEASE_FILE=$2
            shift 2
            ;;
        --keyring)
            (($# >= 2)) || { echo "Error: --keyring requires a path." >&2; exit 1; }
            KEYRING=$2
            shift 2
            ;;
        --expected-fingerprint)
            (($# >= 2)) || { echo "Error: --expected-fingerprint requires a fingerprint." >&2; exit 1; }
            EXPECTED_FPR=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument $1" >&2
            exit 1
            ;;
    esac
done

# Requirement 1: Missing verifier command check
VERIFIER=""
if command -v gpgv >/dev/null 2>&1; then
    VERIFIER="gpgv"
elif command -v gpg >/dev/null 2>&1; then
    VERIFIER="gpg"
else
    echo "Error: Neither gpgv nor gpg is installed." >&2
    exit 1
fi

# Requirement 2: Missing keyring -> FAIL
if [[ -z "$KEYRING" || ! -f "$KEYRING" ]]; then
    echo "Error: Keyring file missing or not specified." >&2
    exit 1
fi

# Requirement 3: Invalid keyring -> FAIL
if command -v gpg >/dev/null 2>&1; then
    if ! gpg --show-keys "$KEYRING" >/dev/null 2>&1 && ! gpg --with-colons --show-keys "$KEYRING" >/dev/null 2>&1; then
        echo "Error: Invalid or unparseable keyring file: $KEYRING" >&2
        exit 1
    fi
fi

# Requirement 4: Missing release file -> FAIL
if [[ -z "$RELEASE_FILE" || ! -f "$RELEASE_FILE" ]]; then
    echo "Error: Release file missing or not specified: $RELEASE_FILE" >&2
    exit 1
fi

echo "[INFO] Verifying signature for $RELEASE_FILE using keyring $KEYRING..."

VERIFY_OUTPUT=""
if [[ "$(basename "$RELEASE_FILE")" == "InRelease" ]]; then
    if [[ "$VERIFIER" == "gpgv" ]]; then
        VERIFY_OUTPUT=$(gpgv --keyring "$KEYRING" "$RELEASE_FILE" 2>&1) || { echo "Error: InRelease signature verification failed!" >&2; exit 1; }
    else
        VERIFY_OUTPUT=$(gpg --no-default-keyring --keyring "$KEYRING" --verify "$RELEASE_FILE" 2>&1) || { echo "Error: InRelease signature verification failed!" >&2; exit 1; }
    fi
elif [[ "$(basename "$RELEASE_FILE")" == "Release.gpg" || "$(basename "$RELEASE_FILE")" == "Release" ]]; then
    RELEASE_DIR=$(dirname "$RELEASE_FILE")
    REL_PATH="$RELEASE_DIR/Release"
    GPG_PATH="$RELEASE_DIR/Release.gpg"
    
    if [[ ! -f "$REL_PATH" || ! -f "$GPG_PATH" ]]; then
        echo "Error: Missing Release ($REL_PATH) or Release.gpg ($GPG_PATH) pair!" >&2
        exit 1
    fi
    
    if [[ "$VERIFIER" == "gpgv" ]]; then
        VERIFY_OUTPUT=$(gpgv --keyring "$KEYRING" "$GPG_PATH" "$REL_PATH" 2>&1) || { echo "Error: Release.gpg signature verification failed!" >&2; exit 1; }
    else
        VERIFY_OUTPUT=$(gpg --no-default-keyring --keyring "$KEYRING" --verify "$GPG_PATH" "$REL_PATH" 2>&1) || { echo "Error: Release.gpg signature verification failed!" >&2; exit 1; }
    fi
else
    echo "Error: Unrecognized release file name: $(basename "$RELEASE_FILE")" >&2
    exit 1
fi

# Requirement 9: Extract verified key fingerprint / key ID
KEY_INFO=$(echo "$VERIFY_OUTPUT" | grep -E "key ID|using [A-Z]+ key" | head -n1 || echo "")
if [[ -n "$EXPECTED_FPR" ]]; then
    EXPECTED_CLEAN=$(echo "$EXPECTED_FPR" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    if ! echo "$VERIFY_OUTPUT" | grep -q -i "${EXPECTED_CLEAN: -8}"; then
        echo "Error: Signature key fingerprint mismatch! Expected: $EXPECTED_FPR" >&2
        exit 1
    fi
fi

echo "[PASS] Signature verified cleanly. $KEY_INFO"
