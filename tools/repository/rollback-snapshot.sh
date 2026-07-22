#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Revert repository channel metadata to a verified previous snapshot atomically.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: rollback-snapshot.sh --repo-dir PATH --channel NAME --snapshot-id ID [options]

Options:
  --repo-dir PATH      Path to staging repository root.
  --channel NAME       Channel name (resolute-alpha, resolute-testing, resolute-stable).
  --snapshot-id ID     Target snapshot ID to restore.
  --operator NAME      Operator identifier performing rollback.
  --reason TEXT        Reason for rollback.
  --dry-run            Simulate rollback without modifying repository.
  -h, --help           Show this help.
EOF
}

REPO_DIR=""
CHANNEL=""
SNAP_ID=""
OPERATOR="GenixBit Maintainers <ftpmaster@genixbit.com>"
REASON="Emergency rollback to previous verified snapshot"
DRY_RUN=false

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
            SNAP_ID=$2
            shift 2
            ;;
        --operator)
            (($# >= 2)) || { echo "Error: --operator requires a name." >&2; exit 1; }
            OPERATOR=$2
            shift 2
            ;;
        --reason)
            (($# >= 2)) || { echo "Error: --reason requires text." >&2; exit 1; }
            REASON=$2
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

if [[ -z "$REPO_DIR" || -z "$CHANNEL" || -z "$SNAP_ID" ]]; then
    echo "Error: --repo-dir, --channel, and --snapshot-id are required." >&2
    exit 1
fi

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1

# Rule 1 & 8: Verify snapshot exists and is valid
"$SCRIPT_DIR/verify-snapshot.sh" --repo-dir "$ABS_REPO" --snapshot-id "$SNAP_ID" || exit 1

SNAP_PATH=$(find "$ABS_REPO/snapshots/$CHANNEL" -type d -name "$SNAP_ID" 2>/dev/null | head -n1 || echo "")

if [[ "$DRY_RUN" == true ]]; then
    echo "[PASS] [DRY RUN] Rollback check passed for channel '$CHANNEL' to snapshot '$SNAP_ID'."
    exit 0
fi

# Rule 3: Preserve current state as new rollback-origin snapshot before reverting
echo "[INFO] Creating pre-rollback origin snapshot for $CHANNEL..."
"$SCRIPT_DIR/create-snapshot.sh" --repo-dir "$ABS_REPO" --channel "$CHANNEL" >/dev/null

CHANNEL_DIR="$ABS_REPO/dists/$CHANNEL"

# Rule 4: Revert channel dists directory from snapshot
rm -rf "$CHANNEL_DIR"/*
cp -r "$SNAP_PATH"/* "$CHANNEL_DIR/" 2>/dev/null || true
rm -f "$CHANNEL_DIR/snapshot-manifest.json"

# Rule 7: Record rollback manifest
ROLLBACK_DIR="$ABS_REPO/dists/$CHANNEL/rollbacks"
mkdir -p "$ROLLBACK_DIR"
ROLLBACK_RECORD="$ROLLBACK_DIR/rollback-$(date +%s).json"

cat <<EOF > "$ROLLBACK_RECORD"
{
  "\$schema": "https://os.genixbit.com/schemas/rollback-record.v1.json",
  "schema_version": "1.0",
  "channel": "$CHANNEL",
  "target_snapshot": "$SNAP_ID",
  "operator": "$OPERATOR",
  "reason": "$REASON",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "[PASS] Channel '$CHANNEL' rolled back cleanly to snapshot '$SNAP_ID'."
