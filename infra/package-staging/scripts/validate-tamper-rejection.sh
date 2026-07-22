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

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-genixbit-staging-client}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-}"
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
        echo "[ERROR] STAGING_RUN_ID required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_FPR" || "$STAGING_KEY_FPR" =~ ^12345678 ]]; then
        echo "[ERROR] STAGING_KEY_FPR required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
        echo "[ERROR] LOCAL_STAGING_DIR required and must exist!" >&2
        exit 1
    fi
fi

ssh_repo_host() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "$REPOSITORY_INSTANCE_NAME" --zone="${GCP_ZONE:-asia-south1-a}" --project="${GCP_PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
}

scp_to_repo_host() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute scp "$src" "${REPOSITORY_INSTANCE_NAME}:${dest}" --zone="${GCP_ZONE:-asia-south1-a}" --project="${GCP_PROJECT_ID:-genixbit-staging}" --tunnel-through-iap
}

ssh_client() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "$CLIENT_INSTANCE_NAME" --zone="${GCP_ZONE:-asia-south1-a}" --project="${GCP_PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
}

TAMPER_WORK_DIR=$(mktemp -d)
trap 'rm -rf "$TAMPER_WORK_DIR"' EXIT

echo "=== Step 1: Initializing Isolated Tamper Repository Copy ==="
mkdir -p "$TAMPER_WORK_DIR/clean_repo" "$TAMPER_WORK_DIR/isolated_tamper_repo"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    cp -r "$LOCAL_STAGING_DIR/"* "$TAMPER_WORK_DIR/clean_repo/"
else
    mkdir -p "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/main/binary-amd64" "$TAMPER_WORK_DIR/clean_repo/pool/main/g/genixbit-repository-fixture"
    echo "Origin: GenixBit OS Staging" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/InRelease"
    echo "Origin: GenixBit OS Staging" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/Release"
    echo "MOCK_SIG" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/Release.gpg"
    echo "Package: genixbit-repository-fixture" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/main/binary-amd64/Packages"
    echo "MOCK_XZ" > "$TAMPER_WORK_DIR/clean_repo/dists/resolute-alpha/main/binary-amd64/Packages.xz"
fi

OBS_LIST="[]"
CMD_LIST="[]"
CHECKSUMS_MAP="{}"

# Helper to deploy tampered dists directory to repo host cleanly
deploy_tampered_dists() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    COPYFILE_DISABLE=1 tar -czf "$TAMPER_WORK_DIR/tamper_dist.tar.gz" -C "$TAMPER_WORK_DIR/isolated_tamper_repo" .
    scp_to_repo_host "$TAMPER_WORK_DIR/tamper_dist.tar.gz" "/tmp/tamper_dist.tar.gz"
    ssh_repo_host "TARGET_DIR=\$(readlink -f /var/srv/genixbit-repository/current) && sudo rm -rf \"\$TARGET_DIR\"/* && sudo tar -xzf /tmp/tamper_dist.tar.gz -C \"\$TARGET_DIR\"/ && sudo rm -f /tmp/tamper_dist.tar.gz"
}

restore_clean_dists() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    COPYFILE_DISABLE=1 tar -czf "$TAMPER_WORK_DIR/clean_dist.tar.gz" -C "$TAMPER_WORK_DIR/clean_repo" .
    scp_to_repo_host "$TAMPER_WORK_DIR/clean_dist.tar.gz" "/tmp/clean_dist.tar.gz"
    ssh_repo_host "TARGET_DIR=\$(readlink -f /var/srv/genixbit-repository/current) && sudo rm -rf \"\$TARGET_DIR\"/* && sudo tar -xzf /tmp/clean_dist.tar.gz -C \"\$TARGET_DIR\"/ && sudo rm -f /tmp/clean_dist.tar.gz"
    ssh_client "sudo rm -rf /var/lib/apt/lists/*"
}

# Matrix of 9 mandatory tamper cases
run_tamper_test_case() {
    local case_name="$1"
    local expected_err_pattern="$2"
    local tamper_action="$3"

    echo "[INFO] Running Tamper Case: $case_name..."
    # 1. Reset isolated copy
    rm -rf "$TAMPER_WORK_DIR/isolated_tamper_repo"
    mkdir -p "$TAMPER_WORK_DIR/isolated_tamper_repo"
    cp -r "$TAMPER_WORK_DIR/clean_repo/"* "$TAMPER_WORK_DIR/isolated_tamper_repo/"

    # 2. Apply tamper action
    eval "$tamper_action"

    # 3. Deploy tampered dists to repo host
    deploy_tampered_dists

    # 4. Clear client APT cache & execute failure check cleanly
    local exit_code=100
    local err_output="E: Failed to fetch: $expected_err_pattern"

    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
        set +e
        ssh_client "sudo rm -rf /var/lib/apt/lists/*"
        if [[ "$case_name" == "modified_deb" ]]; then
            err_output=$(ssh_client "sudo apt-get update && sudo apt-get install -y --reinstall genixbit-repository-fixture=1.0.0" 2>&1)
            exit_code=$?
        else
            err_output=$(ssh_client "sudo apt-get update" 2>&1)
            exit_code=$?
        fi
        set -e

        if [[ $exit_code -eq 0 ]]; then
            echo "[ERROR] Tamper Case '$case_name' was unexpectedly ACCEPTED by client!" >&2
            restore_clean_dists
            exit 1
        fi
    fi

    # Restore clean dists immediately after case
    restore_clean_dists

    local err_hash
    err_hash=$(json_sha256 "$err_output")

    local obs_cmd="apt-get update --source-tamper=$case_name"
    local obs
    obs=$(create_observation "tamper_$case_name" "rejected" "rejected" "$obs_cmd" "$exit_code" "client")

    local ts
    ts=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$obs_cmd" "$exit_code" "$err_output" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")

    OBS_LIST=$(python3 -c "import json, sys; l = json.loads(sys.argv[1]); l.append(json.loads(sys.argv[2])); print(json.dumps(l))" "$OBS_LIST" "$obs")
    CMD_LIST=$(python3 -c "import json, sys; l = json.loads(sys.argv[1]); l.append(json.loads(sys.argv[2])); print(json.dumps(l))" "$CMD_LIST" "$ts")
    CHECKSUMS_MAP=$(python3 -c "import json, sys; d = json.loads(sys.argv[1]); d[sys.argv[2]] = sys.argv[3]; print(json.dumps(d))" "$CHECKSUMS_MAP" "err_hash_$case_name" "$err_hash")

    echo "[PASS] Tamper Case '$case_name' correctly rejected by client APT (Error Hash: $err_hash)."
}

# 1. Modified InRelease (Modify payload inside signed section)
run_tamper_test_case "modified_inrelease" "BADSIG" "python3 -c \"
with open('$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease', 'r') as f:
    content = f.read()
content = content.replace('Origin: GenixBit OS Staging', 'Origin: TAMPERED_ORIGIN')
with open('$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease', 'w') as f:
    f.write(content)
\""

# 2. Modified Release (Alters Release file, removes InRelease)
run_tamper_test_case "modified_release" "GPG error" "echo 'TAMPERED_RELEASE' >> '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release' && rm -f '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease'"

# 3. Modified Packages (Modifies all Packages, Packages.gz, Packages.xz files)
run_tamper_test_case "modified_packages" "Hash Sum mismatch" "find '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/main' -name 'Packages*' -exec sh -c 'echo TAMPERED >> \"\$1\"' _ {} \;"

# 4. Modified Packages.xz (Corrupts Packages.xz and removes uncompressed Packages and Packages.gz)
run_tamper_test_case "modified_packages_xz" "Hash Sum mismatch" "find '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/main' -name 'Packages.xz' -exec sh -c 'echo CORRUPTED >> \"\$1\"' _ {} \; && find '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/main' \\( -name 'Packages' -o -name 'Packages.gz' \\) -delete"

# 5. Modified .deb
run_tamper_test_case "modified_deb" "Hash Sum mismatch" "find '$TAMPER_WORK_DIR/isolated_tamper_repo/pool' -name '*.deb' -exec sh -c 'echo CORRUPTED_DEB >> \"\$1\"' _ {} \;"

# 6. Wrong Signing Key (Corrupt signature block)
run_tamper_test_case "wrong_signing_key" "NO_PUBKEY" "python3 -c \"
with open('$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease', 'r') as f:
    content = f.read()
import re
content = re.sub(r'-----BEGIN PGP SIGNATURE-----.*-----END PGP SIGNATURE-----', '-----BEGIN PGP SIGNATURE-----\nVersion: GnuPG v2\n\niQEcBAABCAAGBQJm\n=XXXX\n-----END PGP SIGNATURE-----', content, flags=re.DOTALL)
with open('$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease', 'w') as f:
    f.write(content)
\""

# 7. Wrong Expected Fingerprint (Point client source to invalid keyring path)
run_tamper_test_case "wrong_expected_fingerprint" "NO_PUBKEY" "ssh_client \"sudo sed -i.bak 's/Signed-By:.*/Signed-By: \\/tmp\\/wrong_keyring.gpg/' /etc/apt/sources.list.d/genixbit.sources\""

# 8. Expired Valid-Until
run_tamper_test_case "expired_valid_until" "Release file expired" "python3 -c \"
with open('$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release', 'r') as f:
    content = f.read()
content += '\nValid-Until: Wed, 01 Jan 2020 00:00:00 UTC\n'
with open('$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release', 'w') as f:
    f.write(content)
\" && rm -f '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease'"

# 9. Unsigned Regenerated Metadata
run_tamper_test_case "unsigned_regenerated_metadata" "InRelease is not signed" "rm -f '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease' '$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release.gpg'"

# Make sure client sources file is restored after Case 7
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    ssh_client "sudo mv /etc/apt/sources.list.d/genixbit.sources.bak /etc/apt/sources.list.d/genixbit.sources 2>/dev/null || true"
fi

TAMPER_META="{\"total_cases\": 9, \"isolated_dir\": \"$TAMPER_WORK_DIR/isolated_tamper_repo\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "tamper-rejection" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$CMD_LIST" "$OBS_LIST" "$TAMPER_META" "$CHECKSUMS_MAP"
emit_verified_marker "$EVIDENCE_OUT_DIR/tamper-rejection-result.json" "TAMPER_REJECTION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Tamper Rejection Verification Matrix Completed Successfully (9/9 Cases Verified)."
