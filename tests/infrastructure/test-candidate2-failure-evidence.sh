#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Execute install-candidate2.sh early-failure paths and require durable failure evidence.

set -Eeuo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s\n' "$*"; }
fail_test() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '[FAIL] %s\n' "$*" >&2; }
info() { printf '[INFO] %s\n' "$*"; }

REPO_TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SCRIPT="$REPO_TOP/tools/vm/install-candidate2.sh"
TEST_DIR=$(mktemp -d)
SOURCE_COMMIT="failure-evidence-test-source-commit"

cleanup() {
    rm -rf "${TEST_DIR:?}"
}
trap cleanup EXIT

assert_failure_summary() {
    local name="$1"
    local evidence_dir="$2"
    local expected_phase="$3"
    local stderr_log="$4"
    local summary="$evidence_dir/failure-summary.json"

    if [[ ! -s "$summary" ]]; then
        fail_test "$name: failure-summary.json missing or empty"
        return
    fi
    pass "$name: failure-summary.json exists and is nonempty"

    if python3 -m json.tool "$summary" >/dev/null; then
        pass "$name: failure-summary.json is valid JSON"
    else
        fail_test "$name: failure-summary.json is invalid JSON"
        return
    fi

    if python3 - "$summary" "$expected_phase" "$SOURCE_COMMIT" <<'PYEOF'
import json
import sys

path, expected_phase, expected_commit = sys.argv[1:4]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

errors = []
if data.get("status") != "FAIL":
    errors.append(f"status={data.get('status')!r}")
if int(data.get("functional_exit_code", 0)) == 0:
    errors.append("functional_exit_code is zero")
if int(data.get("final_exit_code", 0)) == 0:
    errors.append("final_exit_code is zero")
if data.get("phase") != expected_phase:
    errors.append(f"phase={data.get('phase')!r}, expected {expected_phase!r}")
if data.get("source_commit") != expected_commit:
    errors.append(f"source_commit={data.get('source_commit')!r}")

if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        pass "$name: failure summary fields validated"
    else
        fail_test "$name: failure summary fields invalid"
    fi

    if grep -E 'on_exit: command not found|cleanup_exit: command not found|unbound variable|Traceback' "$stderr_log" >/dev/null; then
        fail_test "$name: stderr contains forbidden early-failure runtime error"
    else
        pass "$name: forbidden stderr errors absent"
    fi
}

run_case() {
    local name="$1"
    local expected_phase="$2"
    shift 2

    local evidence_dir="$TEST_DIR/evidence-$name"
    local stdout_log="$TEST_DIR/$name.stdout.log"
    local stderr_log="$TEST_DIR/$name.stderr.log"
    mkdir -p "$evidence_dir"

    info "$name: executing production install-candidate2.sh"
    local rc=0
    set +e
    bash "$INSTALL_SCRIPT" \
        --runtime-evidence-dir "$evidence_dir" \
        --source-commit "$SOURCE_COMMIT" \
        "$@" >"$stdout_log" 2>"$stderr_log"
    rc=$?
    set -e

    if (( rc != 0 )); then
        pass "$name: process exit code is nonzero ($rc)"
    else
        fail_test "$name: process exit code unexpectedly zero"
    fi

    assert_failure_summary "$name" "$evidence_dir" "$expected_phase" "$stderr_log"
}

EMPTY_ISO="$TEST_DIR/empty.iso"
BAD_SHA_ISO="$TEST_DIR/bad-sha.iso"
touch "$EMPTY_ISO"
printf 'not the canonical Candidate 2 ISO\n' > "$BAD_SHA_ISO"

run_case "missing-iso" "validation_iso_path" \
    --iso "$TEST_DIR/missing.iso" \
    --disk "$TEST_DIR/missing-iso.qcow2" \
    --mode uefi

run_case "missing-disk" "validation_disk_arg" \
    --iso "$EMPTY_ISO" \
    --mode uefi

run_case "invalid-mode" "validation_mode" \
    --iso "$TEST_DIR/missing-for-mode.iso" \
    --disk "$TEST_DIR/invalid-mode.qcow2" \
    --mode invalid

run_case "empty-iso" "validation_iso_nonempty" \
    --iso "$EMPTY_ISO" \
    --disk "$TEST_DIR/empty-iso.qcow2" \
    --mode uefi

run_case "incorrect-sha" "validation_iso_checksum" \
    --iso "$BAD_SHA_ISO" \
    --disk "$TEST_DIR/bad-sha.qcow2" \
    --mode uefi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf '\n=== Candidate 2 Early Failure Evidence Test Results ===\n'
printf '  Passed: %d / %d\n' "$PASS_COUNT" "$TOTAL"
printf '  Failed: %d / %d\n' "$FAIL_COUNT" "$TOTAL"

if (( FAIL_COUNT > 0 )); then
    exit 1
fi

pass "missing ISO produced failure-summary.json"
pass "invalid mode produced failure-summary.json"
pass "undefined EXIT-handler error absent"
exit 0
