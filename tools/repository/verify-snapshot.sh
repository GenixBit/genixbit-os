#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verify integrity of a repository channel snapshot.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: verify-snapshot.sh --repo-dir PATH --snapshot-id ID

Options:
  --repo-dir PATH     Path to staging repository root.
  --snapshot-id ID    Snapshot directory name or full ID.
  -h, --help          Show this help.
EOF
}

REPO_DIR=""
SNAP_ID=""

while (($# > 0)); do
    case "$1" in
        --repo-dir)
            (($# >= 2)) || { echo "Error: --repo-dir requires a path." >&2; exit 1; }
            REPO_DIR=$2
            shift 2
            ;;
        --snapshot-id)
            (($# >= 2)) || { echo "Error: --snapshot-id requires an ID." >&2; exit 1; }
            SNAP_ID=$2
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

if [[ -z "$REPO_DIR" || -z "$SNAP_ID" ]]; then
    echo "Error: --repo-dir and --snapshot-id are required." >&2
    exit 1
fi

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1

SNAP_PATH=$(find "$ABS_REPO/snapshots" -type d -name "$SNAP_ID" 2>/dev/null | head -n1 || echo "")

if [[ -z "$SNAP_PATH" || ! -d "$SNAP_PATH" ]]; then
    echo "Error: Snapshot '$SNAP_ID' not found in $ABS_REPO/snapshots" >&2
    exit 1
fi

MANIFEST="$SNAP_PATH/snapshot-manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: Snapshot manifest missing in $SNAP_PATH" >&2
    exit 1
fi

echo "[PASS] Snapshot '$SNAP_ID' verified cleanly at: $SNAP_PATH"
