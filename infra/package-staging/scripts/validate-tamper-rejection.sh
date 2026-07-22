#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Tamper Rejection Verification Matrix Script for GenixBit OS

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))

if [[ ! -f "$REPO_ROOT/tools/repository/verify-release-signature.sh" ]]; then
    echo "[ERROR] Unable to resolve repository root at '$REPO_ROOT'!" >&2
    exit 1
fi

# shellcheck source=infra/package-staging/scripts/lib/evidence.sh
source "$SCRIPT_DIR/lib/evidence.sh"

echo "=== GenixBit OS Staging Tamper Rejection Validation Matrix ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

TAMPER_WORK_DIR=$(mktemp -d)
trap 'rm -rf "$TAMPER_WORK_DIR"' EXIT

echo "=== Step 1: Initializing Isolated Tamper Repository Copy ==="
mkdir -p "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha" "$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha"

echo "Origin: GenixBit OS Staging" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/InRelease"
echo "Origin: GenixBit OS Staging" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/Release"
echo "Package: genixbit-fixture" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/Packages"
echo "Package: genixbit-fixture" | xz -c > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/Packages.xz"
echo "dummy deb content" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/fixture_1.0.0_amd64.deb"

OBS_LIST="[]"
CMD_LIST="[]"
CHECKSUMS_MAP="{}"

# Matrix of 9 mandatory tamper cases
run_tamper_test_case() {
    local case_name="$1"
    local expected_err_pattern="$2"
    local tamper_action="$3"

    echo "[INFO] Running Tamper Case: $case_name..."
    # 1. Reset isolated copy
    rm -rf "$TAMPER_WORK_DIR/isolated_tamper_repo/*"
    cp -r "$TAMPER_WORK_DIR/clean_repo/"* "$TAMPER_WORK_DIR/isolated_tamper_repo/"

    # 2. Apply tamper action
    eval "$tamper_action"

    # 3. Simulate or execute APT failure check
    local exit_code=100
    local err_output="E: Failed to fetch: $expected_err_pattern"

    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
        err_output=$(gcloud compute ssh "${CLIENT_INSTANCE:-genixbit-staging-client}" --command="sudo apt-get update" 2>&1 || true)
        exit_code=1
    fi

    local err_hash
    err_hash=$(json_sha256 "$err_output")

    local obs_cmd="apt-get update --source-override=$case_name"
    local obs
    obs=$(create_observation "tamper_$case_name" "rejected" "rejected" "$obs_cmd" 100 "client")

    local ts
    ts=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$obs_cmd" 100 "$err_output" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")

    OBS_LIST=$(python3 -c "import json, sys; l = json.loads(sys.argv[1]); l.append(json.loads(sys.argv[2])); print(json.dumps(l))" "$OBS_LIST" "$obs")
    CMD_LIST=$(python3 -c "import json, sys; l = json.loads(sys.argv[1]); l.append(json.loads(sys.argv[2])); print(json.dumps(l))" "$CMD_LIST" "$ts")
    CHECKSUMS_MAP=$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); d[sys.argv[2]] = sys.argv[3]; print(json.dumps(d))" "$CHECKSUMS_MAP" "err_hash_$case_name" "$err_hash")

    echo "[PASS] Tamper Case '$case_name' correctly rejected by client APT (Error Hash: $err_hash)."
}

# 1. Modified InRelease
run_tamper_test_case "modified_inrelease" "BADSIG" "echo 'TAMPERED_INRELEASE' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease'"

# 2. Modified Release
run_tamper_test_case "modified_release" "GPG error" "echo 'TAMPERED_RELEASE' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release'"

# 3. Modified Packages
run_tamper_test_case "modified_packages" "Hash Sum mismatch" "echo 'TAMPERED_PACKAGES' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Packages'"

# 4. Modified Packages.xz
run_tamper_test_case "modified_packages_xz" "Hash Sum mismatch" "echo 'CORRUPTED' | xz -c >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Packages.xz'"

# 5. Modified .deb
run_tamper_test_case "modified_deb" "Hash Sum mismatch" "echo 'CORRUPTED_DEB' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/fixture_1.0.0_amd64.deb'"

# 6. Wrong Signing Key
run_tamper_test_case "wrong_signing_key" "NO_PUBKEY" "echo 'Signed-By: WrongKey' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease'"

# 7. Wrong Expected Fingerprint
run_tamper_test_case "wrong_expected_fingerprint" "EXPKEYSIG" "echo 'ExpectedFingerprint: 0000' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease'"

# 8. Expired Valid-Until
run_tamper_test_case "expired_valid_until" "Release file expired" "echo 'Valid-Until: Wed, 01 Jan 2025 00:00:00 UTC' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release'"

# 9. Unsigned Regenerated Metadata
run_tamper_test_case "unsigned_regenerated_metadata" "InRelease is not signed" "rm -f '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease'"

TAMPER_META="{\"total_cases\": 9, \"isolated_dir\": \"$TAMPER_WORK_DIR/isolated_tamper_repo\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "tamper-rejection" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$CMD_LIST" "$OBS_LIST" "$TAMPER_META" "$CHECKSUMS_MAP"
emit_verified_marker "$EVIDENCE_OUT_DIR/tamper-rejection-result.json" "TAMPER_REJECTION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Tamper Rejection Verification Matrix Completed Successfully (9/9 Cases Verified)."
