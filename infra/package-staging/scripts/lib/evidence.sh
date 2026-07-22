#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared Evidence Verification, Command Transcripts & Provenance Helper Library for GenixBit OS Package Staging

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

# Redact sensitive material from command output/text
redact_secrets() {
    local text="$1"
    python3 -c "
import sys, re
t = sys.stdin.read()
# Redact PGP private key blocks
t = re.sub(r'-----BEGIN PGP PRIVATE KEY BLOCK-----[\s\S]*?-----END PGP PRIVATE KEY BLOCK-----', '[REDACTED_PGP_PRIVATE_KEY]', t)
# Redact explicit secret patterns
t = re.sub(r'(?i)(private_key|passphrase|password|token|secret|secring)\s*[:=]\s*\S+', r'\1: [REDACTED]', t)
sys.stdout.write(t)
" <<< "$text"
}

# Record a command transcript safely
record_command_transcript() {
    local out_dir="$1"
    local observer="$2"
    local cmd_str="$3"
    local exit_code="$4"
    local stdout_text="$5"
    local stderr_text="$6"
    local start_ts="$7"
    local end_ts="$8"

    local transcripts_dir="$out_dir/transcripts"
    mkdir -p "$transcripts_dir"

    python3 -c "
import json, sys, hashlib, re

out_dir, observer, cmd_str, exit_code_str, stdout_raw, stderr_raw, start_ts, end_ts = sys.argv[1:]

# Check for unrecoverable secret exposure
combined = stdout_raw + '\n' + stderr_raw
if '-----BEGIN PGP PRIVATE KEY BLOCK-----' in combined or 'PRIVATE KEY-----' in combined:
    # Perform strict redaction
    stdout_redacted = re.sub(r'-----BEGIN PGP PRIVATE KEY BLOCK-----[\s\S]*?-----END PGP PRIVATE KEY BLOCK-----', '[REDACTED_PGP_PRIVATE_KEY]', stdout_raw)
    stderr_redacted = re.sub(r'-----BEGIN PGP PRIVATE KEY BLOCK-----[\s\S]*?-----END PGP PRIVATE KEY BLOCK-----', '[REDACTED_PGP_PRIVATE_KEY]', stderr_raw)
else:
    stdout_redacted = re.sub(r'(?i)(passphrase|password|secret|token)\s*[:=]\s*\S+', r'\1: [REDACTED]', stdout_raw)
    stderr_redacted = re.sub(r'(?i)(passphrase|password|secret|token)\s*[:=]\s*\S+', r'\1: [REDACTED]', stderr_raw)

# Ensure no raw passphrase leak
if 'RECOVERY_PASSPHRASE' in combined or 'PASSPHRASE' in combined:
    stdout_redacted = re.sub(r'--passphrase\s+\S+', '--passphrase [REDACTED]', stdout_redacted)
    stderr_redacted = re.sub(r'--passphrase\s+\S+', '--passphrase [REDACTED]', stderr_redacted)

cmd_clean = re.sub(r'--passphrase\s+\S+', '--passphrase [REDACTED]', cmd_str)

transcript_payload = {
    'command': cmd_clean,
    'observer': observer,
    'exit_code': int(exit_code_str),
    'stdout': stdout_redacted,
    'stderr': stderr_redacted,
    'started_at': start_ts,
    'completed_at': end_ts
}

compact_t = json.dumps(transcript_payload, separators=(',', ':'))
t_hash = hashlib.sha256(compact_t.encode('utf-8')).hexdigest()
cmd_id = f'cmd-{t_hash[:12]}'
transcript_payload['command_id'] = cmd_id
transcript_payload['transcript_sha256'] = t_hash

t_file = f'{out_dir}/transcripts/{cmd_id}.json'
with open(t_file, 'w') as f:
    json.dump(transcript_payload, f, indent=2)

# Print execution summary JSON for stage record
summary = {
    'command_id': cmd_id,
    'command': cmd_clean[:200],
    'observer': observer,
    'exit_code': int(exit_code_str),
    'transcript_sha256': t_hash,
    'started_at': start_ts,
    'completed_at': end_ts
}
print(json.dumps(summary))
" "$out_dir" "$observer" "$cmd_str" "$exit_code" "$stdout_text" "$stderr_text" "$start_ts" "$end_ts"
}

# Create a single observation JSON object string
create_observation() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    local verification_command="$4"
    local verification_exit_code="$5"
    local observer="${6:-verifier}"

    python3 -c "
import json, sys, hashlib, re

name, expected, actual, cmd, exit_code_str, observer, ts = sys.argv[1:8]

placeholders = {'placeholder', 'dummy', 'todo', 'tbd', 'none', 'null', 'test_value', '0000000000000000000000000000000000000000'}

if not name or name.lower() in placeholders:
    sys.stderr.write(f'[ERROR] Invalid observation name: {name}\n')
    sys.exit(1)

if not expected or expected.lower() in placeholders:
    sys.stderr.write(f'[ERROR] Invalid expected value: {expected}\n')
    sys.exit(1)

if not actual or actual.lower() in placeholders:
    sys.stderr.write(f'[ERROR] Invalid actual value: {actual}\n')
    sys.exit(1)

cmd_strip = cmd.strip()
if not cmd_strip or cmd_strip in {'true', 'echo', ':', 'exit 0'} or cmd_strip.startswith('echo ') or cmd_strip.startswith('true '):
    sys.stderr.write(f'[ERROR] Trivial or empty verification command forbidden: {cmd}\n')
    sys.exit(1)

obs_str = f'{name}:{expected}:{actual}:{cmd}:{exit_code_str}:{observer}'
obs_hash = hashlib.sha256(obs_str.encode('utf-8')).hexdigest()

ts = sys.argv[7] if len(sys.argv) > 7 else '2026-07-22T18:00:00Z'

obs_obj = {
    'name': name,
    'expected': expected,
    'actual': actual,
    'verification_command': cmd,
    'verification_exit_code': int(exit_code_str),
    'observed_at': ts,
    'observer': observer,
    'observation_sha256': obs_hash
}
print(json.dumps(obs_obj))
" "$name" "$expected" "$actual" "$verification_command" "$verification_exit_code" "$observer" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

# Write a verified stage-result file
write_stage_result() {
    local out_dir="$1"
    local stage="$2"
    local status="$3"
    local run_id="$4"
    local commit_sha="$5"
    local executed_commands_json="${6:-}"
    local observations_json="${7:-}"
    local public_metadata_json="${8:-}"
    local artifact_checksums_json="${9:-}"

    if [[ -z "$executed_commands_json" ]]; then executed_commands_json="[]"; fi
    if [[ -z "$observations_json" ]]; then observations_json="[]"; fi
    if [[ -z "$public_metadata_json" ]]; then public_metadata_json="{}"; fi
    if [[ -z "$artifact_checksums_json" ]]; then artifact_checksums_json="{}"; fi

    mkdir -p "$out_dir"
    local result_file="$out_dir/${stage}-result.json"

    local start_ts="${STAGE_START_TS:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
    local end_ts
    end_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Reject forbidden secret material in parameters
    if echo "$executed_commands_json $observations_json $public_metadata_json $artifact_checksums_json" | grep -i -E 'BEGIN (RSA|PGP|EC|OPENSSH) PRIVATE KEY|password=|passphrase=|token=|secring\.gpg' >/dev/null; then
        echo "[ERROR] Evidence Library: Detected forbidden secret material in stage result!" >&2
        exit 1
    fi

    python3 -c "
import json, sys, hashlib, re

res_file, stage, status, run_id, commit_sha, cmds_str, obs_str, meta_str, checksums_str, start_ts, end_ts = sys.argv[1:]
cmds = json.loads(cmds_str)
obs = json.loads(obs_str)
meta = json.loads(meta_str)
checksums = json.loads(checksums_str)

placeholders = {'placeholder', 'dummy', 'todo', 'tbd', 'none', 'null', 'test_value', '0000000000000000000000000000000000000000'}

# 1. Reject empty observations
if not obs:
    sys.stderr.write(f'[ERROR] Stage {stage} has empty observations array!\n')
    sys.exit(1)

# 2. Reject expected/actual mismatches and placeholder values in observations
for o in obs:
    if o['expected'] != o['actual']:
        sys.stderr.write(f'[ERROR] Stage {stage} observation {o[\"name\"]} mismatch: expected {o[\"expected\"]} != actual {o[\"actual\"]}\n')
        sys.exit(1)
    if str(o['expected']).lower() in placeholders or str(o['actual']).lower() in placeholders:
        sys.stderr.write(f'[ERROR] Stage {stage} observation {o[\"name\"]} contains placeholder value!\n')
        sys.exit(1)
    cmd = o.get('verification_command', '').strip()
    if not cmd or cmd in {'true', 'echo', ':', 'exit 0'} or cmd.startswith('echo ') or cmd.startswith('true '):
        sys.stderr.write(f'[ERROR] Stage {stage} observation {o[\"name\"]} contains empty/trivial verification command!\n')
        sys.exit(1)

# 3. Reject zero hashes in checksums
for k, v in checksums.items():
    if v == '0000000000000000000000000000000000000000000000000000000000000000':
        sys.stderr.write(f'[ERROR] Stage {stage} artifact {k} has zero SHA256 hash!\n')
        sys.exit(1)

payload_dict = {
    'schema_version': '1.0.0',
    'staging_run_id': run_id,
    'source_commit': commit_sha,
    'stage': stage,
    'started_at': start_ts,
    'completed_at': end_ts,
    'status': status,
    'executed_commands': cmds,
    'observations': obs,
    'public_metadata': meta,
    'artifact_checksums': checksums
}

compact_json = json.dumps(payload_dict, separators=(',', ':'))
payload_hash = hashlib.sha256(compact_json.encode('utf-8')).hexdigest()

payload_dict['result_sha256'] = payload_hash

with open(res_file, 'w') as f:
    json.dump(payload_dict, f, indent=2)
" "$result_file" "$stage" "$status" "$run_id" "$commit_sha" "$executed_commands_json" "$observations_json" "$public_metadata_json" "$artifact_checksums_json" "$start_ts" "$end_ts" || return 1

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

    # Verify Payload SHA256 Integrity & Observations via Python
    python3 -c "
import json, sys, hashlib

res_file = sys.argv[1]
with open(res_file) as f:
    d = json.load(f)

given_hash = d.get('result_sha256', '')
d_copy = dict(d)
d_copy.pop('result_sha256', None)

compact = json.dumps(d_copy, separators=(',', ':'))
calc_hash = hashlib.sha256(compact.encode('utf-8')).hexdigest()

if calc_hash != given_hash:
    sys.stderr.write(f'[ERROR] Hash integrity failure in {res_file}: calc {calc_hash} != given {given_hash}\n')
    sys.exit(1)

obs = d.get('observations', [])
if not obs:
    sys.stderr.write(f'[ERROR] Empty observations array in {res_file}!\n')
    sys.exit(1)

cmds = d.get('executed_commands', [])
if not cmds:
    sys.stderr.write(f'[ERROR] Empty executed_commands array in {res_file}!\n')
    sys.exit(1)

placeholders = {'placeholder', 'dummy', 'todo', 'tbd', 'none', 'null', 'test_value', '0000000000000000000000000000000000000000'}

for o in obs:
    if o['expected'] != o['actual']:
        sys.stderr.write(f'[ERROR] Observation {o[\"name\"]} mismatch in {res_file}: {o[\"expected\"]} != {o[\"actual\"]}\n')
        sys.exit(1)
    if str(o['expected']).lower() in placeholders or str(o['actual']).lower() in placeholders:
        sys.stderr.write(f'[ERROR] Observation {o[\"name\"]} contains placeholder in {res_file}!\n')
        sys.exit(1)
    cmd = o.get('verification_command', '').strip()
    if not cmd or cmd in {'true', 'echo', ':', 'exit 0'} or cmd.startswith('echo ') or cmd.startswith('true '):
        sys.stderr.write(f'[ERROR] Observation {o[\"name\"]} has trivial verification command in {res_file}!\n')
        sys.exit(1)
" "$result_file"
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
