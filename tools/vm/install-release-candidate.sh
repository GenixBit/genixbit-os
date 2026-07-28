#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generic active release-candidate installer entry point.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

ISO_PATH=""
PROVENANCE_FILE="${ACTIVE_RELEASE_PROVENANCE_FILE:-$REPO_ROOT/docs/releases/0.3.0-alpha-artifact.json}"
SOURCE_COMMIT="${ACTIVE_RELEASE_SOURCE_COMMIT:-}"

args=()
while (($# > 0)); do
    case "$1" in
        --iso)
            (($# >= 2)) || { printf '[FAIL] --iso requires a path.\n' >&2; exit 1; }
            ISO_PATH=$2
            args+=("$1" "$2")
            shift 2
            ;;
        --provenance-file)
            (($# >= 2)) || { printf '[FAIL] --provenance-file requires a path.\n' >&2; exit 1; }
            PROVENANCE_FILE=$2
            shift 2
            ;;
        --source-commit)
            (($# >= 2)) || { printf '[FAIL] --source-commit requires a SHA.\n' >&2; exit 1; }
            SOURCE_COMMIT=$2
            args+=("$1" "$2")
            shift 2
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

[[ -n "$ISO_PATH" ]] || { printf '[FAIL] install-release-candidate.sh: --iso is required.\n' >&2; exit 1; }

python3 "$REPO_ROOT/tools/validation/check-active-release-artifact.py" \
  --repo-root "$REPO_ROOT" \
  --provenance-file "$PROVENANCE_FILE" \
  --release-version "${ACTIVE_RELEASE_VERSION:-0.3.0-alpha}" \
  --mode "${ACTIVE_RELEASE_MODE:-fresh-install-only}" \
  --source-commit "$SOURCE_COMMIT" \
  --iso "$ISO_PATH" \
  --require-pass >/dev/null

exec bash "$SCRIPT_DIR/install-candidate2.sh" "${args[@]}"
