#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# List available snapshots for a repository channel.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: list-snapshots.sh --repo-dir PATH [--channel NAME]

Options:
  --repo-dir PATH   Path to staging repository root.
  --channel NAME    Channel name (optional).
  -h, --help        Show this help.
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

if [[ -z "$REPO_DIR" ]]; then
    echo "Error: --repo-dir is required." >&2
    exit 1
fi

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1
SNAP_ROOT="$ABS_REPO/snapshots"

if [[ ! -d "$SNAP_ROOT" ]]; then
    echo "[INFO] No snapshots found in $ABS_REPO"
    exit 0
fi

if [[ -n "$CHANNEL" ]]; then
    SEARCH_DIR="$SNAP_ROOT/$CHANNEL"
else
    SEARCH_DIR="$SNAP_ROOT"
fi

if [[ -d "$SEARCH_DIR" ]]; then
    find "$SEARCH_DIR" -name "snapshot-manifest.json" -exec dirname {} \; | sort
fi
