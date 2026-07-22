#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate layout integrity of a local APT staging repository.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: validate-repository-layout.sh --repo-dir PATH

Options:
  --repo-dir PATH  Path to staging repository root.
  -h, --help       Show this help.
EOF
}

REPO_DIR=""

while (($# > 0)); do
    case "$1" in
        --repo-dir)
            (($# >= 2)) || { echo "Error: --repo-dir requires a path." >&2; exit 1; }
            REPO_DIR=$2
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

ABS_REPO=$(cd "$REPO_DIR" 2>/dev/null && pwd || echo "$REPO_DIR")
if [[ "$ABS_REPO" == "/" || "$ABS_REPO" == "$HOME" ]]; then
    echo "Error: Dangerous path: $ABS_REPO" >&2
    exit 1
fi

echo "[INFO] Validating repository layout at: $ABS_REPO"

[[ -d "$ABS_REPO/dists" ]] || { echo "[FAIL] Missing dists/ directory" >&2; exit 1; }
[[ -d "$ABS_REPO/pool" ]] || { echo "[FAIL] Missing pool/ directory" >&2; exit 1; }

for channel in resolute-alpha resolute-testing resolute-stable; do
    [[ -d "$ABS_REPO/dists/$channel" ]] || { echo "[FAIL] Missing channel $channel" >&2; exit 1; }
done

echo "[PASS] Staging repository layout is valid."
