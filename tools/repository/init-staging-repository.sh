#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Initialize a local APT staging repository directory structure safely.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: init-staging-repository.sh --repo-dir PATH

Options:
  --repo-dir PATH  Absolute or relative path to target repository root.
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

# Safety path validation (Rule 9, 10, 11)
ABS_REPO=$(cd "$REPO_DIR" 2>/dev/null && pwd || echo "$REPO_DIR")
if [[ "$ABS_REPO" == "/" || "$ABS_REPO" == "$HOME" || "$ABS_REPO" == "/root" ]]; then
    echo "Error: Refusing to initialize repository at root or home directory: $ABS_REPO" >&2
    exit 1
fi

echo "[INFO] Initializing staging repository structure at: $ABS_REPO"

channels=("resolute-alpha" "resolute-testing" "resolute-stable")
components=("main" "restricted")
archs=("binary-amd64")

for channel in "${channels[@]}"; do
    for comp in "${components[@]}"; do
        for arch in "${archs[@]}"; do
            mkdir -p "$ABS_REPO/dists/$channel/$comp/$arch"
        done
    done
done

mkdir -p "$ABS_REPO/pool/main" "$ABS_REPO/pool/restricted"

echo "[PASS] Staging repository initialized successfully at: $ABS_REPO"
