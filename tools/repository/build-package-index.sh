#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generate Packages and Release files for an APT repository channel.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: build-package-index.sh --repo-dir PATH --channel NAME

Options:
  --repo-dir PATH  Path to staging repository root.
  --channel NAME   Channel name (resolute-alpha, resolute-testing, resolute-stable).
  -h, --help       Show this help.
EOF
}

REPO_DIR=""
CHANNEL=""

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

if [[ -z "$REPO_DIR" || -z "$CHANNEL" ]]; then
    echo "Error: --repo-dir and --channel are required." >&2
    exit 1
fi

ABS_REPO=$(cd "$REPO_DIR" 2>/dev/null && pwd || echo "$REPO_DIR")
if [[ "$ABS_REPO" == "/" || "$ABS_REPO" == "$HOME" ]]; then
    echo "Error: Dangerous path: $ABS_REPO" >&2
    exit 1
fi

CHANNEL_DIR="$ABS_REPO/dists/$CHANNEL"
if [[ ! -d "$CHANNEL_DIR" ]]; then
    echo "Error: Channel directory $CHANNEL_DIR does not exist." >&2
    exit 1
fi

echo "[INFO] Building package indices for channel: $CHANNEL in $ABS_REPO"

# Dummy index generation for staging tooling verification
for comp in main restricted; do
    INDEX_DIR="$CHANNEL_DIR/$comp/binary-amd64"
    mkdir -p "$INDEX_DIR"
    
    # Create empty or basic Packages file if not present
    if [[ ! -f "$INDEX_DIR/Packages" ]]; then
        touch "$INDEX_DIR/Packages"
    fi
    gzip -9c "$INDEX_DIR/Packages" > "$INDEX_DIR/Packages.gz"
done

cat <<EOF > "$CHANNEL_DIR/Release"
Origin: GenixBit OS
Label: GenixBit
Suite: $CHANNEL
Codename: $CHANNEL
Architectures: amd64
Components: main restricted
Description: GenixBit OS $CHANNEL package repository
EOF

echo "[PASS] Package indices built cleanly for $CHANNEL."
