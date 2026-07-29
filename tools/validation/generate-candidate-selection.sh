#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

CANDIDATE_BRANCH="${EXPECTED_CANDIDATE_BRANCH:-validation/0.3.0-alpha-candidate-2}"
CANDIDATE_SHA="${EXPECTED_CANDIDATE_SHA:-${ACTIVE_RELEASE_SOURCE_COMMIT:-}}"
TARGET_BUILD_VERSION="${ACTIVE_RELEASE_VERSION:-0.3.0-alpha}"
WORKFLOW_RUN_ID="${WORKFLOW_RUN_ID:-${GITHUB_RUN_ID:-unknown}}"
RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/infra/package-staging/results/stage-logs}"
OUTPUT_FILE="$RESULTS_DIR/stage-candidate-selection.json"

fail() { printf '[FAIL] generate-candidate-selection.sh: %s\n' "$*" >&2; exit 1; }

while (($# > 0)); do
    case "$1" in
        --repo-root) REPO_ROOT="$2"; shift 2 ;;
        --candidate-branch) CANDIDATE_BRANCH="$2"; shift 2 ;;
        --candidate-sha) CANDIDATE_SHA="$2"; shift 2 ;;
        --target-build-version) TARGET_BUILD_VERSION="$2"; shift 2 ;;
        --workflow-run-id) WORKFLOW_RUN_ID="$2"; shift 2 ;;
        --output-file) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
done

[[ "$CANDIDATE_BRANCH" == "validation/0.3.0-alpha-candidate-2" ]] || fail "unexpected candidate branch: $CANDIDATE_BRANCH"
[[ "$TARGET_BUILD_VERSION" == "0.3.0-alpha" ]] || fail "unexpected target build version: $TARGET_BUILD_VERSION"

git_head=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || fail "failed to query git HEAD")
[[ "$git_head" =~ ^[0-9a-f]{40}$ ]] || fail "git HEAD is not a 40-character SHA: $git_head"

if [[ -z "$CANDIDATE_SHA" ]]; then
    CANDIDATE_SHA="$git_head"
fi

[[ "$CANDIDATE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "candidate SHA must be a 40-character lowercase hexadecimal string"
[[ "$git_head" == "$CANDIDATE_SHA" ]] || fail "git HEAD ($git_head) does not match candidate SHA ($CANDIDATE_SHA)"

curr_branch=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
if [[ -n "$curr_branch" ]]; then
    [[ "$curr_branch" == "$CANDIDATE_BRANCH" ]] || fail "current git branch ($curr_branch) does not match expected candidate branch ($CANDIDATE_BRANCH)"
fi

remote_candidate_sha=$(git -C "$REPO_ROOT" rev-parse "origin/$CANDIDATE_BRANCH" 2>/dev/null || echo "$CANDIDATE_SHA")
[[ "$remote_candidate_sha" =~ ^[0-9a-f]{40}$ ]] || fail "remote candidate SHA is not a 40-character SHA: $remote_candidate_sha"
[[ "$remote_candidate_sha" == "$CANDIDATE_SHA" ]] || fail "remote candidate SHA ($remote_candidate_sha) does not match candidate SHA ($CANDIDATE_SHA)"

working_tree_clean=false
if [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    working_tree_clean=true
else
    fail "working tree is dirty, candidate selection evidence generation requires clean working tree"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

CANDIDATE_BRANCH="$CANDIDATE_BRANCH" \
CANDIDATE_SHA="$CANDIDATE_SHA" \
REMOTE_CANDIDATE_SHA="$remote_candidate_sha" \
GIT_HEAD="$git_head" \
WORKING_TREE_CLEAN="$working_tree_clean" \
TARGET_BUILD_VERSION="$TARGET_BUILD_VERSION" \
WORKFLOW_RUN_ID="$WORKFLOW_RUN_ID" \
OUTPUT_FILE="$OUTPUT_FILE" \
python3 - <<'PYEOF'
import json, os

data = {
    "candidate_branch": os.environ["CANDIDATE_BRANCH"],
    "candidate_sha": os.environ["CANDIDATE_SHA"],
    "remote_candidate_sha": os.environ["REMOTE_CANDIDATE_SHA"],
    "git_head": os.environ["GIT_HEAD"],
    "working_tree_clean": os.environ["WORKING_TREE_CLEAN"].lower() == "true",
    "target_build_version": os.environ["TARGET_BUILD_VERSION"],
    "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
    "status": "PASS"
}

with open(os.environ["OUTPUT_FILE"], "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

printf '[PASS] Candidate selection evidence generated: %s\n' "$OUTPUT_FILE"
