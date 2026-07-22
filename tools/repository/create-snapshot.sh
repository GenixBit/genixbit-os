#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Create an immutable snapshot manifest for an APT repository channel.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/repository/lib/safety.sh
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: create-snapshot.sh --repo-dir PATH --channel NAME [--source-commit SHA]

Options:
  --repo-dir PATH       Path to staging repository root.
  --channel NAME        Channel name (resolute-alpha, resolute-testing, resolute-stable).
  --source-commit SHA   Git source commit SHA (optional).
  -h, --help            Show this help.
EOF
}

REPO_DIR=""
CHANNEL=""
COMMIT_SHA="head"

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
        --source-commit)
            (($# >= 2)) || { echo "Error: --source-commit requires a SHA." >&2; exit 1; }
            COMMIT_SHA=$2
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

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1
CHANNEL_DIR="$ABS_REPO/dists/$CHANNEL"

if [[ ! -d "$CHANNEL_DIR" ]]; then
    echo "Error: Channel directory $CHANNEL_DIR does not exist." >&2
    exit 1
fi

RELEASE_FILE="$CHANNEL_DIR/Release"
REL_HASH=""
if [[ -f "$RELEASE_FILE" ]]; then
    REL_HASH=$(python3 -c "import hashlib; print(hashlib.sha256(open('$RELEASE_FILE', 'rb').read()).hexdigest())")
fi

TS=$(date -u +"%Y%m%d-%H%M%S")
SNAP_ID="snap-${CHANNEL}-${TS}"
SNAP_DIR="$ABS_REPO/snapshots/$CHANNEL/$SNAP_ID"
mkdir -p "$SNAP_DIR"

# Copy active dists metadata into snapshot backup
cp -r "$CHANNEL_DIR"/* "$SNAP_DIR/" 2>/dev/null || true

SNAP_MANIFEST="$SNAP_DIR/snapshot-manifest.json"
cat <<EOF > "$SNAP_MANIFEST"
{
  "\$schema": "https://os.genixbit.com/schemas/snapshot-manifest.v1.json",
  "snapshot_id": "$SNAP_ID",
  "channel": "$CHANNEL",
  "release_hash": "$REL_HASH",
  "creation_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source_commit": "$COMMIT_SHA"
}
EOF

echo "[PASS] Created snapshot: $SNAP_ID at $SNAP_DIR"
echo "Snapshot ID: $SNAP_ID"
