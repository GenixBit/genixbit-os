#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Manage active GenixBit OS package update channel safely.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: set-channel.sh CHANNEL [options]

Channels:
  disabled  Disable GenixBit OS package repository.
  alpha     Enable resolute-alpha staging channel.
  testing   Enable resolute-testing candidate channel.
  stable    Enable resolute-stable production channel.

Options:
  --sources-file PATH    Path to sources file (default: /etc/apt/sources.list.d/genixbit-os.sources).
  --keyring-file PATH    Path to keyring file (default: /usr/share/keyrings/genixbit-os-archive-keyring.pgp).
  --skip-root-check      Skip EUID==0 root check (for non-root testing).
  --skip-network-check   Skip HTTPS connectivity check (for local test servers).
  --skip-apt-update      Skip apt-get update step (for offline/dry-run testing).
  -h, --help             Show this help.
EOF
}

CHANNEL=""
SOURCES_FILE="/etc/apt/sources.list.d/genixbit-os.sources"
KEYRING_FILE="/usr/share/keyrings/genixbit-os-archive-keyring.pgp"
SKIP_ROOT=false
SKIP_NETWORK=false
SKIP_APT=false

while (($# > 0)); do
    case "$1" in
        disabled|alpha|testing|stable)
            CHANNEL=$1
            shift
            ;;
        --sources-file)
            (($# >= 2)) || { echo "Error: --sources-file requires a path." >&2; exit 1; }
            SOURCES_FILE=$2
            shift 2
            ;;
        --keyring-file)
            (($# >= 2)) || { echo "Error: --keyring-file requires a path." >&2; exit 1; }
            KEYRING_FILE=$2
            shift 2
            ;;
        --skip-root-check)
            SKIP_ROOT=true
            shift
            ;;
        --skip-network-check)
            SKIP_NETWORK=true
            shift
            ;;
        --skip-apt-update)
            SKIP_APT=true
            shift
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

if [[ -z "$CHANNEL" ]]; then
    echo "Error: Channel argument (disabled|alpha|testing|stable) is required." >&2
    exit 1
fi

# EUID root check
if [[ "$SKIP_ROOT" == false && "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Error: Switching repository channels requires root privileges." >&2
    exit 1
fi

if [[ ! -f "$SOURCES_FILE" ]]; then
    echo "Error: Target sources file does not exist: $SOURCES_FILE" >&2
    exit 1
fi

# Detect current channel
CURRENT_ENABLED=$(grep -i "^Enabled:" "$SOURCES_FILE" | awk '{print $2}' || echo "no")
CURRENT_SUITE=$(grep -i "^Suites:" "$SOURCES_FILE" | awk '{print $2}' || echo "unknown")

if [[ "$CURRENT_ENABLED" == "no" ]]; then
    PREV_STATE="disabled"
else
    PREV_STATE="$CURRENT_SUITE"
fi

echo "[INFO] Current channel state: $PREV_STATE"

# Backup sources file for rollback
BACKUP_FILE="${SOURCES_FILE}.bak.$(date +%s)"
cp "$SOURCES_FILE" "$BACKUP_FILE"

restore_backup() {
    echo "[WARN] Restoring previous configuration..." >&2
    cp "$BACKUP_FILE" "$SOURCES_FILE"
    rm -f "$BACKUP_FILE"
}

if [[ "$CHANNEL" == "disabled" ]]; then
    sed -i.tmp 's/^Enabled:.*/Enabled: no/' "$SOURCES_FILE"
    rm -f "${SOURCES_FILE}.tmp"
    echo "[PASS] GenixBit OS package repository disabled."
    rm -f "$BACKUP_FILE"
    exit 0
fi

# Validate public keyring
if [[ ! -f "$KEYRING_FILE" ]]; then
    echo "Error: Public archive keyring file missing: $KEYRING_FILE" >&2
    restore_backup
    exit 1
fi

if command -v gpg >/dev/null 2>&1; then
    if ! gpg --show-keys "$KEYRING_FILE" >/dev/null 2>&1 && ! gpg --with-colons --show-keys "$KEYRING_FILE" >/dev/null 2>&1; then
        echo "Error: Keyring file $KEYRING_FILE is invalid or empty." >&2
        restore_backup
        exit 1
    fi
fi

# Validate HTTPS repository availability
TARGET_URI=$(grep -i "^URIs:" "$SOURCES_FILE" | awk '{print $2}' || echo "https://packages.os.genixbit.com/")
if [[ "$SKIP_NETWORK" == false ]]; then
    echo "[INFO] Testing HTTPS repository reachability: $TARGET_URI"
    if ! curl -sfI --connect-timeout 5 "$TARGET_URI" >/dev/null 2>&1; then
        echo "Error: Repository $TARGET_URI is not reachable." >&2
        restore_backup
        exit 1
    fi
fi

# Enable requested channel
TARGET_SUITE="resolute-${CHANNEL}"
sed -i.tmp "s/^Suites:.*/Suites: ${TARGET_SUITE}/" "$SOURCES_FILE"
sed -i.tmp 's/^Enabled:.*/Enabled: yes/' "$SOURCES_FILE"
rm -f "${SOURCES_FILE}.tmp"

if [[ "$SKIP_APT" == false ]]; then
    echo "[INFO] Running apt-get update..."
    if ! apt-get update -o Dir::Etc::sourcelist="$SOURCES_FILE" >/dev/null 2>&1; then
        echo "Error: apt-get update failed." >&2
        restore_backup
        exit 1
    fi
fi

rm -f "$BACKUP_FILE"
echo "[PASS] Switched channel from '$PREV_STATE' to '$CHANNEL' (Suite: $TARGET_SUITE)."
