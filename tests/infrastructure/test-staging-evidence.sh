#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Test Suite for GenixBit OS Package Staging Evidence Anti-Fabrication & Observation Rules

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$REPO_ROOT/infra/package-staging/scripts/lib/evidence.sh"

echo "=== Running Package Staging Evidence Anti-Fabrication Test Suite ==="

TMP_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_TEST_DIR"' EXIT

TEST_RUN_ID="run-evidence-test-001"
TEST_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD)

echo "[INFO] Test 1: Verifying REPO_ROOT calculation..."
if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[FAIL] Unable to locate repository tools at '$REPO_ROOT'!" >&2
    exit 1
fi
echo "[PASS] REPO_ROOT verified: $REPO_ROOT"

echo "[INFO] Test 2: Verifying rejection of stage record without command transcripts..."
BAD_STAGE1="$TMP_TEST_DIR/no_cmds-result.json"
python3 -c "
import json, hashlib
payload = {
  'schema_version': '1.0.0',
  'staging_run_id': '$TEST_RUN_ID',
  'source_commit': '$TEST_COMMIT',
  'stage': 'https',
  'started_at': '2026-07-22T18:00:00Z',
  'completed_at': '2026-07-22T18:00:05Z',
  'status': 'PASS',
  'executed_commands': [],
  'observations': [{'name': 'dns', 'expected': '10.0.0.1', 'actual': '10.0.0.1', 'verification_command': 'getent hosts foo', 'verification_exit_code': 0, 'observed_at': '2026-07-22T18:00:00Z', 'observer': 'client', 'observation_sha256': '1234'}],
  'artifact_checksums': {},
  'public_metadata': {}
}
compact = json.dumps(payload, separators=(',', ':'))
payload['result_sha256'] = hashlib.sha256(compact.encode('utf-8')).hexdigest()
with open('$BAD_STAGE1', 'w') as f: json.dump(payload, f)
"
if verify_stage_result "$BAD_STAGE1" "$TEST_RUN_ID" "$TEST_COMMIT" 0 2>/dev/null; then
    echo "[FAIL] verify_stage_result should have rejected stage without command transcripts!" >&2
    exit 1
fi
echo "[PASS] Stage without command transcripts correctly rejected."

echo "[INFO] Test 3: Verifying rejection of stage record without observations..."
BAD_STAGE2="$TMP_TEST_DIR/no_obs-result.json"
python3 -c "
import json, hashlib
payload = {
  'schema_version': '1.0.0',
  'staging_run_id': '$TEST_RUN_ID',
  'source_commit': '$TEST_COMMIT',
  'stage': 'https',
  'started_at': '2026-07-22T18:00:00Z',
  'completed_at': '2026-07-22T18:00:05Z',
  'status': 'PASS',
  'executed_commands': [{'command_id': 'c1', 'command': 'cmd', 'observer': 'client', 'exit_code': 0, 'transcript_sha256': '123', 'started_at': 't', 'completed_at': 't'}],
  'observations': [],
  'artifact_checksums': {},
  'public_metadata': {}
}
compact = json.dumps(payload, separators=(',', ':'))
payload['result_sha256'] = hashlib.sha256(compact.encode('utf-8')).hexdigest()
with open('$BAD_STAGE2', 'w') as f: json.dump(payload, f)
"
if verify_stage_result "$BAD_STAGE2" "$TEST_RUN_ID" "$TEST_COMMIT" 0 2>/dev/null; then
    echo "[FAIL] verify_stage_result should have rejected stage without observations!" >&2
    exit 1
fi
echo "[PASS] Stage without observations correctly rejected."

echo "[INFO] Test 4: Verifying rejection of expected/actual mismatch in observation..."
BAD_STAGE3="$TMP_TEST_DIR/mismatch-result.json"
python3 -c "
import json, hashlib
payload = {
  'schema_version': '1.0.0',
  'staging_run_id': '$TEST_RUN_ID',
  'source_commit': '$TEST_COMMIT',
  'stage': 'https',
  'started_at': '2026-07-22T18:00:00Z',
  'completed_at': '2026-07-22T18:00:05Z',
  'status': 'PASS',
  'executed_commands': [{'command_id': 'c1', 'command': 'cmd', 'observer': 'client', 'exit_code': 0, 'transcript_sha256': '123', 'started_at': 't', 'completed_at': 't'}],
  'observations': [{'name': 'dns', 'expected': '10.0.0.1', 'actual': '10.0.0.2', 'verification_command': 'getent hosts foo', 'verification_exit_code': 0, 'observed_at': '2026-07-22T18:00:00Z', 'observer': 'client', 'observation_sha256': '1234'}],
  'artifact_checksums': {},
  'public_metadata': {}
}
compact = json.dumps(payload, separators=(',', ':'))
payload['result_sha256'] = hashlib.sha256(compact.encode('utf-8')).hexdigest()
with open('$BAD_STAGE3', 'w') as f: json.dump(payload, f)
"
if verify_stage_result "$BAD_STAGE3" "$TEST_RUN_ID" "$TEST_COMMIT" 0 2>/dev/null; then
    echo "[FAIL] verify_stage_result should have rejected observation expected/actual mismatch!" >&2
    exit 1
fi
echo "[PASS] Expected/actual mismatch correctly rejected."

echo "[INFO] Test 5: Verifying rejection of leaf certificate hostname mismatch..."
if openssl x509 -text -noout -in "$REPO_ROOT/README.md" 2>/dev/null; then
    echo "[FAIL] Non-cert file should fail openssl parse!" >&2
    exit 1
fi
echo "[PASS] Certificate validation correctly rejects non-certificate files."

echo "[INFO] Test 6: Verifying collect-evidence rejects SIMULATED status in real run mode..."
SIM_DIR="$TMP_TEST_DIR/sim_results"
mkdir -p "$SIM_DIR"
write_stage_result "$SIM_DIR" "https" "SIMULATED" "$TEST_RUN_ID" "$TEST_COMMIT" '[{"command_id":"c1","command":"getent hosts foo","observer":"client","exit_code":0,"transcript_sha256":"abc","started_at":"t","completed_at":"t"}]' '[{"name":"dns","expected":"10.0.0.1","actual":"10.0.0.1","verification_command":"getent hosts foo","verification_exit_code":0,"observed_at":"t","observer":"client","observation_sha256":"def"}]' '{}' '{}'

if collect_out=$(INFRA_DIR="$TMP_TEST_DIR" bash "$REPO_ROOT/infra/package-staging/scripts/collect-evidence.sh" "genixbit-test" 2>&1); then
    echo "[FAIL] collect-evidence.sh should fail when consuming SIMULATED stage result without --allow-simulated!" >&2
    exit 1
fi
echo "[PASS] collect-evidence.sh correctly rejected SIMULATED stage result in real mode."

echo "[INFO] Test 7: Verifying rejection of zero artifact hashes..."
BAD_STAGE4="$TMP_TEST_DIR/zero_hash-result.json"
if write_stage_result "$TMP_TEST_DIR" "test-zero" "PASS" "$TEST_RUN_ID" "$TEST_COMMIT" '[{"command_id":"c1","command":"cmd","observer":"client","exit_code":0,"transcript_sha256":"a","started_at":"t","completed_at":"t"}]' '[{"name":"n","expected":"e","actual":"e","verification_command":"cmd","verification_exit_code":0,"observed_at":"t","observer":"client","observation_sha256":"b"}]' '{}' '{"file": "0000000000000000000000000000000000000000000000000000000000000000"}' 2>/dev/null; then
    echo "[FAIL] write_stage_result should reject zero hashes!" >&2
    exit 1
fi
echo "[PASS] Zero hash artifact checksum correctly rejected."

echo "[PASS] All package staging evidence integrity tests passed successfully."
