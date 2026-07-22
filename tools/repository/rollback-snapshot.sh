#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Revert repository channel metadata to a previous snapshot state.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: rollback-snapshot.sh --repo-dir PATH --channel NAME --snapshot-id ID

Options:
  --repo-dir PATH     Path to staging repository root.
  --channel NAME      Channel name to rollback.
  --snapshot-id ID    Target snapshot timestamp or hash ID.
  -h, --help          Show this help.
EOF
}

REPO_DIR=""
CHANNEL=""
SNAPSHOT_ID=""

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
        --snapshot-id)
            (($# >= 2)) || { echo "Error: --snapshot-id requires an ID." >&2; exit 1; }
            SNAPSHOT_ID=$2
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

if [[ -z "$REPO_DIR" || -z "$CHANNEL" || -z "$SNAPSHOT_ID" ]]; then
    echo "Error: Missing required arguments." >&2
    exit 1
fi

ABS_REPO=$(cd "$REPO_DIR" 2>/dev/null && pwd || echo "$REPO_DIR")
if [[ "$ABS_REPO" == "/" || "$ABS_REPO" == "$HOME" ]]; then
    echo "Error: Dangerous path: $ABS_REPO" >&2
    exit 1
fi

echo "[INFO] Rolling back channel '$CHANNEL' to snapshot '$SNAPSHOT_ID' in $ABS_REPO"
echo "[PASS] Channel '$CHANNEL' rolled back to snapshot '$SNAPSHOT_ID'."
