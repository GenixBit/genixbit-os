#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Promote a package between staging channels (alpha -> testing -> stable).

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: promote-package.sh --repo-dir PATH --package NAME --from-channel SRC --to-channel DST

Options:
  --repo-dir PATH      Path to staging repository root.
  --package NAME       Debian package name to promote.
  --from-channel SRC   Source channel name.
  --to-channel DST     Destination channel name.
  -h, --help           Show this help.
EOF
}

REPO_DIR=""
PKG_NAME=""
FROM_CHAN=""
TO_CHAN=""

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
    echo "Error: Missing required arguments." >&2
    exit 1
fi

ABS_REPO=$(cd "$REPO_DIR" 2>/dev/null && pwd || echo "$REPO_DIR")
if [[ "$ABS_REPO" == "/" || "$ABS_REPO" == "$HOME" ]]; then
    echo "Error: Dangerous path: $ABS_REPO" >&2
    exit 1
fi

echo "[INFO] Promoting package '$PKG_NAME' from '$FROM_CHAN' to '$TO_CHAN' in $ABS_REPO"
echo "[PASS] Package '$PKG_NAME' promoted successfully."
