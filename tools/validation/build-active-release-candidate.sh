#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
TARGET_VERSION="0.3.0-alpha"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

candidate_branch=""
candidate_sha=""
output_dir=""
build_label=""

fail() { printf '[FAIL] build-active-release-candidate.sh: %s\n' "$*" >&2; exit 1; }
info() { printf '[INFO] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: build-active-release-candidate.sh --candidate-branch BRANCH --candidate-sha SHA --output-dir DIR --build-label LABEL
EOF
}

workflow_run_id="${WORKFLOW_RUN_ID:-${GITHUB_RUN_ID:-unknown}}"
workflow_run_attempt="${WORKFLOW_RUN_ATTEMPT:-${GITHUB_RUN_ATTEMPT:-unknown}}"

while (($# > 0)); do
    case "$1" in
        --repo-root) REPO_ROOT="$2"; shift 2 ;;
        --candidate-branch) candidate_branch="$2"; shift 2 ;;
        --candidate-sha) candidate_sha="$2"; shift 2 ;;
        --output-dir) output_dir="$2"; shift 2 ;;
        --build-label) build_label="$2"; shift 2 ;;
        --workflow-run-id) workflow_run_id="$2"; shift 2 ;;
        --workflow-run-attempt) workflow_run_attempt="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
done

[[ "$candidate_branch" =~ ^validation/0\.3\.0-alpha-candidate-[1-9][0-9]*$ ]] || fail "unexpected candidate branch: $candidate_branch"
[[ "$candidate_sha" =~ ^[0-9a-f]{40}$ ]] || fail "candidate SHA must be a full 40-character lowercase SHA"
[[ -n "$output_dir" ]] || fail "--output-dir is required"
[[ -n "$build_label" ]] || fail "--build-label is required"

for var in $(compgen -v GENIXBIT_FAKE || true); do
    fail "fake build environment variable detected: $var"
done

if env | grep -qE '^GENIXBIT_FAKE'; then
    fail "fake build environment variables are prohibited"
fi

remote_sha=$(git -C "$REPO_ROOT" rev-parse "origin/$candidate_branch" 2>/dev/null || true)
[[ "$remote_sha" == "$candidate_sha" ]] || fail "origin/$candidate_branch resolves to ${remote_sha:-missing}, expected $candidate_sha"
git -C "$REPO_ROOT" cat-file -e "$candidate_sha^{commit}" || fail "candidate SHA is not a commit: $candidate_sha"

mkdir -p "$output_dir"
worktree="$output_dir/worktree-$build_label"
sudo rm -rf "$worktree" 2>/dev/null || rm -rf "$worktree" 2>/dev/null || true
git -C "$REPO_ROOT" worktree add --detach "$worktree" "$candidate_sha" >/dev/null
cleanup() {
    sudo umount "$worktree/new_building_os/sys" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/sys" 2>/dev/null || true
    sudo umount "$worktree/new_building_os/proc" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/proc" 2>/dev/null || true
    sudo umount "$worktree/new_building_os/dev" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/dev" 2>/dev/null || true
    sudo umount "$worktree/new_building_os/run" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/run" 2>/dev/null || true
    sudo rm -rf "$worktree/new_building_os" "$worktree/image" 2>/dev/null || true
    git -C "$REPO_ROOT" worktree remove --force "$worktree" >/dev/null 2>&1 || sudo rm -rf "$worktree" 2>/dev/null || rm -rf "$worktree" 2>/dev/null || true
}
trap cleanup EXIT

head_sha=$(git -C "$worktree" rev-parse HEAD)
[[ "$head_sha" == "$candidate_sha" ]] || fail "worktree HEAD moved: $head_sha"
build_version=$(grep -E '^export TARGET_BUILD_VERSION=' "$worktree/args.sh" | cut -d'"' -f2)
[[ "$build_version" == "$TARGET_VERSION" ]] || fail "TARGET_BUILD_VERSION is $build_version, expected $TARGET_VERSION"
[[ -z "$(git -C "$worktree" status --porcelain)" ]] || fail "candidate checkout is dirty before build"

sudo rm -rf "$worktree/dist" "$worktree/new_building_os" "$worktree/image" 2>/dev/null || rm -rf "$worktree/dist" "$worktree/new_building_os" "$worktree/image" 2>/dev/null || true
mkdir -p "$worktree/dist"
before_manifest="$output_dir/$build_label-before.txt"
find "$worktree/dist" -maxdepth 1 -type f -name "GenixBitOS-$TARGET_VERSION-*.iso" -print | sort > "$before_manifest"

start_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
stdout_log="$output_dir/$build_label-build.stdout.log"
stderr_log="$output_dir/$build_label-build.stderr.log"

info "Executing real build for $build_label from $candidate_sha"
build_rc=0
(
    cd "$worktree"
    SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    PACKAGE_SOURCE_MODE=genixbit-staging \
    GENIXBIT_STAGING_SERVER="${GENIXBIT_STAGING_SERVER:-}" \
    GENIXBIT_STAGING_KEYRING="${GENIXBIT_STAGING_KEYRING:-}" \
    bash ./build.sh
) > "$stdout_log" 2> "$stderr_log" || build_rc=$?

completion_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
(( build_rc == 0 )) || fail "real build.sh failed with exit code $build_rc"

matches=()
while IFS= read -r line; do
    [[ -n "$line" ]] && matches+=("$line")
done < <(find "$worktree/dist" -maxdepth 1 -type f -name "GenixBitOS-$TARGET_VERSION-*.iso" -print | sort)
(( ${#matches[@]} == 1 )) || fail "expected exactly one timestamped $TARGET_VERSION ISO after build, found ${#matches[@]}"
iso_path="${matches[0]}"
filename=$(basename "$iso_path")
[[ "$filename" == *"$TARGET_VERSION"* ]] || fail "ISO filename does not include $TARGET_VERSION: $filename"
if grep -Fxq "$iso_path" "$before_manifest"; then
    fail "ISO existed before current build: $iso_path"
fi

preserved_iso="$output_dir/$build_label-$filename"
cp "$iso_path" "$preserved_iso"
iso_path="$preserved_iso"

sudo umount "$worktree/new_building_os/sys" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/sys" 2>/dev/null || true
sudo umount "$worktree/new_building_os/proc" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/proc" 2>/dev/null || true
sudo umount "$worktree/new_building_os/dev" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/dev" 2>/dev/null || true
sudo umount "$worktree/new_building_os/run" 2>/dev/null || sudo umount -lf "$worktree/new_building_os/run" 2>/dev/null || true
sudo rm -rf "$worktree/new_building_os" "$worktree/image" 2>/dev/null || true

STRUCTURE_CHECKER="$REPO_ROOT/tools/validation/check-iso-structure.sh"
[[ -x "$STRUCTURE_CHECKER" || -f "$STRUCTURE_CHECKER" ]] || fail "required ISO structure checker is missing: $STRUCTURE_CHECKER"

bash "$STRUCTURE_CHECKER" --iso "$iso_path" \
    > "$output_dir/$build_label-iso-structure.stdout.log" \
    2> "$output_dir/$build_label-iso-structure.stderr.log"

size_bytes=$(wc -c < "$iso_path" | tr -d ' ')
if command -v sha256sum >/dev/null 2>&1; then
    sha256=$(sha256sum "$iso_path" | awk '{print $1}')
else
    sha256=$(shasum -a 256 "$iso_path" | awk '{print $1}')
fi

if command -v sha512sum >/dev/null 2>&1; then
    sha512=$(sha512sum "$iso_path" | awk '{print $1}')
else
    sha512=$(shasum -a 512 "$iso_path" | awk '{print $1}')
fi

metadata="$output_dir/$build_label-build.json"
structure_json="$output_dir/$build_label-iso-structure.json"

BUILD_LABEL="$build_label" CANDIDATE_BRANCH="$candidate_branch" CANDIDATE_SHA="$candidate_sha" WORKFLOW_RUN_ID="$workflow_run_id" WORKFLOW_RUN_ATTEMPT="$workflow_run_attempt" WORKTREE_DIR="$worktree" OUTPUT_DIR="$output_dir" ISO_PATH="$iso_path" FILENAME="$filename" SIZE_BYTES="$size_bytes" SHA256="$sha256" SHA512="$sha512" SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" START_TS="$start_ts" COMPLETION_TS="$completion_ts" STDOUT_LOG="$stdout_log" STDERR_LOG="$stderr_log" METADATA="$metadata" STRUCTURE_JSON="$structure_json" python3 - <<'PY'
import json, os, sys

start_ts = os.environ.get("START_TS", "")
comp_ts = os.environ.get("COMPLETION_TS", "")
if not start_ts or not comp_ts:
    sys.exit("Start or completion timestamp missing")
if comp_ts < start_ts:
    sys.exit(f"Completion timestamp {comp_ts} is before start timestamp {start_ts}")

data = {
  "build_label": os.environ["BUILD_LABEL"],
  "candidate_branch": os.environ["CANDIDATE_BRANCH"],
  "source_commit": os.environ["CANDIDATE_SHA"],
  "target_version": "0.3.0-alpha",
  "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
  "workflow_run_attempt": os.environ["WORKFLOW_RUN_ATTEMPT"],
  "worktree_dir": os.environ["WORKTREE_DIR"],
  "output_dir": os.environ["OUTPUT_DIR"],
  "source_date_epoch": os.environ["SOURCE_DATE_EPOCH"],
  "command": "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH PACKAGE_SOURCE_MODE=genixbit-staging ./build.sh",
  "execution_mode": "REAL_BUILD",
  "build_script": "./build.sh",
  "build_exit_code": 0,
  "exit_code": 0,
  "start_timestamp": start_ts,
  "completion_timestamp": comp_ts,
  "iso_path": os.environ["ISO_PATH"],
  "filename": os.environ["FILENAME"],
  "size_bytes": int(os.environ["SIZE_BYTES"]),
  "sha256": os.environ["SHA256"],
  "sha512": os.environ["SHA512"],
  "stdout_path": os.environ["STDOUT_LOG"],
  "stderr_path": os.environ["STDERR_LOG"],
  "status": "PASS"
}

with open(os.environ["METADATA"], "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

struct_data = {
  "source_commit": os.environ["CANDIDATE_SHA"],
  "candidate_branch": os.environ["CANDIDATE_BRANCH"],
  "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
  "workflow_run_attempt": os.environ["WORKFLOW_RUN_ATTEMPT"],
  "iso_path": os.environ["ISO_PATH"],
  "iso_sha256": os.environ["SHA256"],
  "iso_sha512": os.environ["SHA512"],
  "command": f"tools/validation/check-iso-structure.sh --iso {os.environ['ISO_PATH']}",
  "exit_code": 0,
  "status": "PASS"
}

with open(os.environ["STRUCTURE_JSON"], "w", encoding="utf-8") as f:
    json.dump(struct_data, f, indent=2)
    f.write("\n")
PY

printf 'ISO_PATH=%s\n' "$iso_path"
printf 'METADATA=%s\n' "$metadata"
printf 'STRUCTURE_JSON=%s\n' "$structure_json"
printf 'SHA256=%s\n' "$sha256"
printf 'SHA512=%s\n' "$sha512"
printf 'SIZE_BYTES=%s\n' "$size_bytes"
