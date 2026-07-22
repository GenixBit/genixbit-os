#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared Evidence Verification & Provenance Helper Library for GenixBit OS Package Staging

set -euo pipefail

# Calculate Repository Root from this script location (3 levels up: scripts/lib -> scripts -> package-staging -> infra -> REPO_ROOT)
LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$LIB_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$LIB_DIR/../../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Evidence Library: Unable to verify repository root path at '$REPO_ROOT'!" >&2
    exit 1
fi

export REPO_ROOT

# Calculate canonical SHA256 of string
json_sha256() {
    local json_input="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        echo -n "$json_input" | sha256sum | cut -d' ' -f1
    else
        echo -n "$json_input" | shasum -a 256 | cut -d' ' -f1
    fi
}

# Calculate portable SHA256 of file
file_sha256() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        echo "0000000000000000000000000000000000000000000000000000000000000000"
        return 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file_path" | cut -d' ' -f1
    else
        shasum -a 256 "$file_path" | cut -d' ' -f1
    fi
}

# Write a verified stage-result file
write_stage_result() {
    local out_dir="$1"
    local stage="$2"
    local status="$3"
    local run_id="$4"
    local commit_sha="$5"
    local cmd_summary="$6"
    local verified_conditions_json="$7"
    local public_metadata_json="${8:-}"
    local artifact_checksums_json="${9:-}"

    if [[ -z "$public_metadata_json" ]]; then public_metadata_json="{}"; fi
    if [[ -z "$artifact_checksums_json" ]]; then artifact_checksums_json="{}"; fi

    mkdir -p "$out_dir"
    local result_file="$out_dir/${stage}-result.json"

    local start_ts="${STAGE_START_TS:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
    local end_ts
    end_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Reject forbidden secret material in metadata
    if echo "$verified_conditions_json $public_metadata_json $artifact_checksums_json" | grep -i -E 'private_key|token|password|passphrase|secret|secring' >/dev/null; then
        echo "[ERROR] Evidence Library: Detected forbidden secret material in stage result!" >&2
        exit 1
    fi

    python3 -c "
import json, sys, hashlib
res_file, stage, status, run_id, commit_sha, cmd, conds_str, meta_str, checksums_str, start_ts, end_ts = sys.argv[1:]
conds = json.loads(conds_str)
meta = json.loads(meta_str)
checksums = json.loads(checksums_str)

payload_dict = {
    'schema_version': '1.0.0',
    'staging_run_id': run_id,
    'source_commit': commit_sha,
    'stage': stage,
    'started_at': start_ts,
    'completed_at': end_ts,
    'status': status,
    'command_summary': cmd,
    'verified_conditions': conds,
    'public_metadata': meta,
    'artifact_checksums': checksums
}

compact_json = json.dumps(payload_dict, separators=(',', ':'))
payload_hash = hashlib.sha256(compact_json.encode('utf-8')).hexdigest()

payload_dict['result_sha256'] = payload_hash

with open(res_file, 'w') as f:
    json.dump(payload_dict, f, indent=2)
" "$result_file" "$stage" "$status" "$run_id" "$commit_sha" "$cmd_summary" "$verified_conditions_json" "$public_metadata_json" "$artifact_checksums_json" "$start_ts" "$end_ts"

    local res_hash
    res_hash=$(jq -r '.result_sha256' "$result_file")
    echo "[PASS] Stage result recorded: $result_file (SHA: $res_hash)"
}

# Verify an existing stage-result file
verify_stage_result() {
    local result_file="$1"
    local expected_run_id="$2"
    local expected_commit="$3"
    local allow_simulated="${4:-0}"

    if [[ ! -f "$result_file" ]]; then
        echo "[ERROR] Missing stage result file: $result_file" >&2
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "[ERROR] jq is required for stage result verification." >&2
        return 1
    fi

    local run_id commit_sha status stage res_hash
    run_id=$(jq -r '.staging_run_id // ""' "$result_file")
    commit_sha=$(jq -r '.source_commit // ""' "$result_file")
    status=$(jq -r '.status // ""' "$result_file")
    stage=$(jq -r '.stage // ""' "$result_file")
    res_hash=$(jq -r '.result_sha256 // ""' "$result_file")

    if [[ -z "$run_id" || -z "$commit_sha" || -z "$status" || -z "$res_hash" ]]; then
        echo "[ERROR] Stage result file '$result_file' is missing required fields." >&2
        return 1
    fi

    if [[ "$run_id" != "$expected_run_id" ]]; then
        echo "[ERROR] Stage result run ID mismatch ($run_id != $expected_run_id) in $result_file" >&2
        return 1
    fi

    if [[ "$commit_sha" != "$expected_commit" ]]; then
        echo "[ERROR] Stage result source commit mismatch ($commit_sha != $expected_commit) in $result_file" >&2
        return 1
    fi

    if [[ "$status" == "SIMULATED" || "$status" == "MOCK" || "$status" == "SKIPPED" ]]; then
        if [[ "$allow_simulated" -ne 1 ]]; then
            echo "[ERROR] Rejected simulated stage result '$result_file' for real evidence collection!" >&2
            return 1
        fi
    elif [[ "$status" != "PASS" ]]; then
        echo "[ERROR] Stage status is not PASS ($status) in $result_file" >&2
        return 1
    fi

    # Verify Payload SHA256 Integrity via Python json module
    local calculated_hash
    calculated_hash=$(python3 -c "
import json, sys, hashlib
with open(sys.argv[1]) as f:
    d = json.load(f)
d.pop('result_sha256', None)
compact = json.dumps(d, separators=(',', ':'))
print(hashlib.sha256(compact.encode('utf-8')).hexdigest())
" "$result_file")

    if [[ "$calculated_hash" != "$res_hash" ]]; then
        echo "[ERROR] Stage result hash integrity failure in $result_file!" >&2
        echo "Expected: $res_hash" >&2
        echo "Calculated: $calculated_hash" >&2
        return 1
    fi

    return 0
}

# Emit verified marker only after verifying stage result
emit_verified_marker() {
    local result_file="$1"
    local stage_upper="$2"
    local expected_run_id="$3"
    local expected_commit="$4"
    local allow_simulated="${5:-0}"

    if verify_stage_result "$result_file" "$expected_run_id" "$expected_commit" "$allow_simulated"; then
        local status
        status=$(jq -r '.status' "$result_file")
        if [[ "$status" == "SIMULATED" ]]; then
            echo "STAGING_${stage_upper}=SIMULATED"
        else
            echo "STAGING_${stage_upper}=PASS"
        fi
    else
        echo "STAGING_${stage_upper}=FAILED"
        return 1
    fi
}
