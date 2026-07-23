#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fail-closed automated check for release evidence integrity & checksum consistency.

set -Eeuo pipefail

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

EVIDENCE_FILE="docs/releases/0.2.0-alpha-distribution-verification.json"

[[ -f "$EVIDENCE_FILE" ]] || fail "Evidence file missing: $EVIDENCE_FILE"

get_json_val() {
    local key=$1
    python3 -c "import json; data=json.load(open('$EVIDENCE_FILE')); print(data.get('$key', ''))" 2>/dev/null || echo ""
}

get_json_nested() {
    local p1=$1
    local p2=$2
    python3 -c "import json; data=json.load(open('$EVIDENCE_FILE')); print(data.get('$p1', {}).get('$p2', ''))" 2>/dev/null || echo ""
}

downloaded_hash=$(get_json_val "downloaded_file_sha256")
manifest_hash=$(get_json_val "manifest_sha256")
checksum_file_hash=$(get_json_val "checksum_file_sha256")
expected_hash=$(get_json_val "expected_release_sha256")
overall_status=$(get_json_val "overall_verification_status")
hash_match=$(get_json_val "hash_match")
downloaded_bytes=$(get_json_nested "audit_environment_details" "downloaded_bytes")
object_bytes=$(get_json_nested "gcp_storage_details" "object_size_bytes")

echo "=== 1. Checking Hash Field Presence ==="
[[ -n "$downloaded_hash" ]] || fail "downloaded_file_sha256 is absent!"
[[ -n "$manifest_hash" ]] || fail "manifest_sha256 is absent!"
[[ -n "$checksum_file_hash" ]] || fail "checksum_file_sha256 is absent!"
[[ -n "$expected_hash" ]] || fail "expected_release_sha256 is absent!"
pass "All required SHA-256 fields are present."

echo "=== 2. Checking Evidence Placeholder & Value Safety ==="
if [[ "$downloaded_hash" == *"TODO"* || "$manifest_hash" == *"PLACEHOLDER"* ]]; then
    fail "Evidence contains unpopulated placeholder text!"
fi
pass "Evidence contains no placeholder values."

echo "=== 3. Fail-Closed Checksum Equality Rule ==="
if [[ "$downloaded_hash" != "$manifest_hash" ]]; then
    if [[ "$overall_status" == "PASS" ]]; then
        fail "CRITICAL INTEGRITY FAILURE: overall_verification_status is PASS but downloaded_file_sha256 ($downloaded_hash) != manifest_sha256 ($manifest_hash)!"
    fi
    if [[ "$hash_match" == "true" ]]; then
        fail "CRITICAL INTEGRITY FAILURE: hash_match is true but hashes differ!"
    fi
    pass "Fail-closed check passed: Evidence correctly set to status '$overall_status' and hash_match '$hash_match' when hashes mismatch."
else
    if [[ "$hash_match" != "true" || "$overall_status" != "PASS" ]]; then
        fail "Inconsistent status when hashes match: hash_match=$hash_match, overall_status=$overall_status"
    fi
    pass "Checksums match identically ($manifest_hash) and overall status is PASS."
fi

echo "=== 4. Size Invariant Check ==="
if [[ "$downloaded_bytes" != "2540554240" || "$object_bytes" != "2540554240" ]]; then
    fail "Object or downloaded byte size mismatch (expected 2540554240, got downloaded=$downloaded_bytes, object=$object_bytes)!"
fi
pass "Object and downloaded byte sizes match exact manifest 2,540,554,240 bytes."

echo ""
pass "Release evidence integrity validation complete!"
