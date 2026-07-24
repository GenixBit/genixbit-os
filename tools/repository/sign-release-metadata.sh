#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Sign APT Release metadata producing InRelease and Release.gpg.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/repository/lib/safety.sh
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: sign-release-metadata.sh --repo-dir PATH --channel NAME --signing-key-fingerprint FPR --gnupg-home PATH

Options:
  --repo-dir PATH                 Path to staging repository root.
  --channel NAME                  Channel name (resolute-alpha, resolute-testing, resolute-stable).
  --signing-key-fingerprint FPR   Full OpenPGP fingerprint (40 hex characters).
  --gnupg-home PATH               Path to GNUPGHOME directory.
  -h, --help                      Show this help.
EOF
}

REPO_DIR=""
CHANNEL=""
FINGERPRINT=""
GNUPG_HOME=""

while (($# > 0)); do
    case "$1" in
        --repo-dir)
            (($# >= 2)) || { echo "Error: --repo-dir requires a path." >&2; exit 1; }
            REPO_DIR=$2
            shift 2
            ;;
        --channel)
            (($# >= 2)) || { echo "Error: --channel requires a name." >&2; exit 1; }
            CHANNEL=$2
            shift 2
            ;;
        --signing-key-fingerprint)
            (($# >= 2)) || { echo "Error: --signing-key-fingerprint requires a fingerprint." >&2; exit 1; }
            FINGERPRINT=$2
            shift 2
            ;;
        --gnupg-home)
            (($# >= 2)) || { echo "Error: --gnupg-home requires a path." >&2; exit 1; }
            GNUPG_HOME=$2
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

if [[ -z "$REPO_DIR" || -z "$CHANNEL" || -z "$FINGERPRINT" || -z "$GNUPG_HOME" ]]; then
    echo "Error: --repo-dir, --channel, --signing-key-fingerprint, and --gnupg-home are required." >&2
    exit 1
fi

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1
ABS_GPG_HOME=$(validate_repository_path "$GNUPG_HOME" "--gnupg-home") || exit 1

# Rule 8: Refuse production signing when GNUPGHOME is inside repository
if [[ "$ABS_GPG_HOME" == "$ABS_REPO"* ]]; then
    echo "Error: Safety violation - GNUPGHOME cannot be located inside repository directory: $ABS_GPG_HOME" >&2
    exit 1
fi

# Clean fingerprint (remove spaces)
FINGERPRINT=$(echo "$FINGERPRINT" | tr -d ' ')

if [[ ! "$FINGERPRINT" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo "Error: Invalid fingerprint format. Must be 40 hex characters: $FINGERPRINT" >&2
    exit 1
fi

RELEASE_FILE="$ABS_REPO/dists/$CHANNEL/Release"
if [[ ! -f "$RELEASE_FILE" ]]; then
    echo "Error: Release file does not exist: $RELEASE_FILE" >&2
    exit 1
fi

# Rule 9: Refuse signing when Release metadata is incomplete
if ! grep -q "^Origin:" "$RELEASE_FILE" || ! grep -q "^SHA256:" "$RELEASE_FILE"; then
    echo "Error: Release file is incomplete or invalid: $RELEASE_FILE" >&2
    exit 1
fi

export GNUPGHOME="$ABS_GPG_HOME"

# Confirm fingerprint exists and contains usable secret signing key
if ! gpg --list-secret-keys --with-colons "$FINGERPRINT" >/dev/null 2>&1; then
    echo "Error: Secret signing key fingerprint $FINGERPRINT not found in GNUPGHOME $ABS_GPG_HOME" >&2
    exit 1
fi

INRELEASE_FILE="$ABS_REPO/dists/$CHANNEL/InRelease"
RELEASE_GPG_FILE="$ABS_REPO/dists/$CHANNEL/Release.gpg"

rm -f "$INRELEASE_FILE" "$RELEASE_GPG_FILE"

echo "[INFO] Signing $RELEASE_FILE with key $FINGERPRINT..."

GPG_OPTS=(--batch --no-tty --yes --pinentry-mode loopback --digest-algo SHA512 --local-user "$FINGERPRINT")
if [[ -n "${KEY_PASSPHRASE:-}" ]]; then
    GPG_OPTS+=(--passphrase "$KEY_PASSPHRASE")
elif [[ -n "${GPG_PASSPHRASE:-}" ]]; then
    GPG_OPTS+=(--passphrase "$GPG_PASSPHRASE")
fi

# Generate InRelease (clearsigned)
gpg "${GPG_OPTS[@]}" --clearsign --output "$INRELEASE_FILE" "$RELEASE_FILE"

# Generate Release.gpg (detached signature)
gpg "${GPG_OPTS[@]}" --detach-sign --output "$RELEASE_GPG_FILE" "$RELEASE_FILE"


echo "[PASS] Generated signed InRelease and Release.gpg for channel '$CHANNEL'."
