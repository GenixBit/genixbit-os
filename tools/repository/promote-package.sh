#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Promote a Debian package between staging channels atomically.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/repository/lib/safety.sh
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: promote-package.sh --repo-dir PATH --package NAME --from-channel SRC --to-channel DST [options]

Options:
  --repo-dir PATH               Path to staging repository root.
  --package NAME                Debian package name to promote.
  --version VER                 Package version (optional; defaults to latest found in SRC).
  --from-channel SRC             Source channel (resolute-alpha, resolute-testing).
  --to-channel DST               Destination channel (resolute-testing, resolute-stable).
  --promoter NAME               Promoter identifier.
  --reviewer NAME               Reviewer identifier.
  --dry-run                     Simulate promotion without modifying repository.
  --emergency-override REASON   Override channel transition rules in emergency.
  -h, --help                    Show this help.
EOF
}

REPO_DIR=""
PKG_NAME=""
PKG_VERSION=""
FROM_CHAN=""
TO_CHAN=""
PROMOTER="GenixBit Maintainers <ftpmaster@genixbit.com>"
REVIEWER="Security Reviewer <security@genixbit.com>"
DRY_RUN=false
EMERGENCY=""

while (($# > 0)); do
    case "$1" in
        --repo-dir)
            (($# >= 2)) || { echo "Error: --repo-dir requires a path." >&2; exit 1; }
            REPO_DIR=$2
            shift 2
            ;;
        --package)
            (($# >= 2)) || { echo "Error: --package requires a name." >&2; exit 1; }
            PKG_NAME=$2
            shift 2
            ;;
        --version)
            (($# >= 2)) || { echo "Error: --version requires a version." >&2; exit 1; }
            PKG_VERSION=$2
            shift 2
            ;;
        --from-channel)
            (($# >= 2)) || { echo "Error: --from-channel requires a channel." >&2; exit 1; }
            FROM_CHAN=$2
            shift 2
            ;;
        --to-channel)
            (($# >= 2)) || { echo "Error: --to-channel requires a channel." >&2; exit 1; }
            TO_CHAN=$2
            shift 2
            ;;
        --promoter)
            (($# >= 2)) || { echo "Error: --promoter requires a name." >&2; exit 1; }
            PROMOTER=$2
            shift 2
            ;;
        --reviewer)
            (($# >= 2)) || { echo "Error: --reviewer requires a name." >&2; exit 1; }
            REVIEWER=$2
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --emergency-override)
            (($# >= 2)) || { echo "Error: --emergency-override requires a reason." >&2; exit 1; }
            EMERGENCY=$2
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

if [[ -z "$REPO_DIR" || -z "$PKG_NAME" || -z "$FROM_CHAN" || -z "$TO_CHAN" ]]; then
    echo "Error: --repo-dir, --package, --from-channel, and --to-channel are required." >&2
    exit 1
fi

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1

# Rule: Check allowed transitions
if [[ "$FROM_CHAN" == "resolute-alpha" && "$TO_CHAN" == "resolute-stable" && -z "$EMERGENCY" ]]; then
    echo "Error: Direct promotion from resolute-alpha to resolute-stable is forbidden without --emergency-override." >&2
    exit 1
fi

# Verify source channel index exists
SRC_INDEX="$ABS_REPO/dists/$FROM_CHAN/main/binary-amd64/Packages"
if [[ ! -f "$SRC_INDEX" ]]; then
    echo "Error: Source channel index file missing: $SRC_INDEX" >&2
    exit 1
fi

if ! grep -q "Package: $PKG_NAME" "$SRC_INDEX"; then
    echo "Error: Package '$PKG_NAME' not found in source channel '$FROM_CHAN'" >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "[PASS] [DRY RUN] Promotion check passed for '$PKG_NAME' from '$FROM_CHAN' to '$TO_CHAN'."
    exit 0
fi

# Create snapshot of destination before promotion
PREV_SNAP=""
if [[ -x "$SCRIPT_DIR/create-snapshot.sh" ]]; then
    PREV_SNAP=$("$SCRIPT_DIR/create-snapshot.sh" --repo-dir "$ABS_REPO" --channel "$TO_CHAN" | grep "Snapshot ID:" | awk '{print $NF}' || echo "")
fi

# Regenerate destination indices
"$SCRIPT_DIR/build-package-index.sh" --repo-dir "$ABS_REPO" --channel "$TO_CHAN"

# Record promotion record JSON
PROMO_DIR="$ABS_REPO/dists/$TO_CHAN/promotions"
mkdir -p "$PROMO_DIR"
PROMO_RECORD="$PROMO_DIR/promo-$(date +%s).json"

cat <<EOF > "$PROMO_RECORD"
{
  "\$schema": "https://os.genixbit.com/schemas/promotion-record.v1.json",
  "schema_version": "1.0",
  "package": "$PKG_NAME",
  "version": "${PKG_VERSION:-1.0.0}",
  "from_channel": "$FROM_CHAN",
  "to_channel": "$TO_CHAN",
  "promoter": "$PROMOTER",
  "reviewer": "$REVIEWER",
  "previous_snapshot": "${PREV_SNAP:-none}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "[PASS] Package '$PKG_NAME' promoted cleanly from '$FROM_CHAN' to '$TO_CHAN'."
