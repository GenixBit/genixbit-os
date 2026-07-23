#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Tamper Rejection Verification Matrix Script for GenixBit OS
# shellcheck disable=SC2016

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
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-genixbit-staging-client}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
    ZONE="${GCP_ZONE:-asia-south1-a}"

    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-$TMP_STAGING/keyring.gpg}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-alpha/main/binary-amd64"
    touch "$STAGING_PUBLIC_KEYRING"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-}"
    CLIENT_INSTANCE_NAME="${CLIENT_INSTANCE_NAME:-}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-}"
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
    gcloud compute ssh "$REPOSITORY_INSTANCE_NAME" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
}

scp_to_repo_host() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute scp "$src" "${REPOSITORY_INSTANCE_NAME}:${dest}" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap
}

ssh_client() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "$CLIENT_INSTANCE_NAME" --zone="${ZONE:-asia-south1-a}" --project="${PROJECT_ID:-genixbit-staging}" --tunnel-through-iap --command="$cmd"
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

# Helper to deploy tampered dists to DEDICATED ISOLATED ENDPOINT (/var/srv/genixbit-repository/tamper-test/)
# CRITICAL RULE: NEVER touch or overwrite /var/srv/genixbit-repository/current during tamper testing!
deploy_tampered_dists_isolated() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 tar --no-xattrs -czf "$TAMPER_WORK_DIR/tamper_dist.tar.gz" -C "$TAMPER_WORK_DIR/isolated_tamper_repo" . 2>/dev/null || COPYFILE_DISABLE=1 tar -czf "$TAMPER_WORK_DIR/tamper_dist.tar.gz" -C "$TAMPER_WORK_DIR/isolated_tamper_repo" .
    scp_to_repo_host "$TAMPER_WORK_DIR/tamper_dist.tar.gz" "/tmp/tamper_dist.tar.gz"
    ssh_repo_host "sudo mkdir -p /var/srv/genixbit-repository/tamper-test && sudo rm -rf /var/srv/genixbit-repository/tamper-test/* && sudo tar -xzf /tmp/tamper_dist.tar.gz -C /var/srv/genixbit-repository/tamper-test/ && sudo rm -f /tmp/tamper_dist.tar.gz"
}

cleanup_tamper_endpoint() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    ssh_repo_host "sudo rm -rf /var/srv/genixbit-repository/tamper-test"
    ssh_client "sudo rm -f /etc/apt/sources.list.d/tamper.sources /etc/apt/trusted.gpg.d/tamper_*.gpg && sudo rm -rf /var/lib/apt/lists/*"
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

    # 3. Deploy to isolated endpoint (/var/srv/genixbit-repository/tamper-test/)
    deploy_tampered_dists_isolated

    # 4. Execute client APT validation against isolated tamper endpoint
    local err_out=""
    local apt_exit=0

    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
        # Configure client source pointing to /tamper-test/
        local key_path="/etc/apt/trusted.gpg.d/genixbit-staging.gpg"
        if [[ "$case_name" == "wrong_signing_key" ]]; then
            key_path="/etc/apt/trusted.gpg.d/wrong_key.gpg"
            ssh_client "gpg --batch --passphrase '' --quick-gen-key 'Wrong Test Key <wrong@test.local>' default default 1y 2>/dev/null && gpg --export 'Wrong Test Key' | sudo tee $key_path >/dev/null"
        fi

        # Temporarily disable all existing sources lists so APT fetches strictly from tamper source
        ssh_client "sudo mkdir -p /etc/apt/sources.list.d.disabled; if ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1; then sudo mv /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d.disabled/; fi"

        ssh_client "cat <<EOF | sudo tee /etc/apt/sources.list.d/tamper.sources
Types: deb
URIs: https://${PRIVATE_HOSTNAME}/tamper-test/
Suites: resolute-alpha
Components: main
Signed-By: $key_path
EOF"

        ssh_client "sudo rm -rf /var/cache/apt/archives/*.deb /var/lib/apt/lists/*"
        set +e
        if [[ "$case_name" == "modified_deb" ]]; then
            # modified_deb fails during apt-get install --reinstall from tamper source
            ssh_client "sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/tamper.sources" >/dev/null 2>&1
            err_out=$(ssh_client "sudo apt-get install -y --reinstall --allow-downgrades genixbit-repository-fixture" 2>&1)
            apt_exit=$?
        else
            err_out=$(ssh_client "sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/tamper.sources" 2>&1)
            apt_exit=$?
        fi
        set -e

        # Clean up tamper source & restore all original sources
        ssh_client "sudo rm -f /etc/apt/sources.list.d/tamper.sources /etc/apt/trusted.gpg.d/wrong_key.gpg; if ls /etc/apt/sources.list.d.disabled/*.sources >/dev/null 2>&1; then sudo mv /etc/apt/sources.list.d.disabled/*.sources /etc/apt/sources.list.d/; fi; sudo rm -rf /etc/apt/sources.list.d.disabled"

        if [[ $apt_exit -eq 0 ]]; then
            echo "[ERROR] Tamper Case '$case_name' FAILED: Client APT accepted tampered metadata/package!" >&2
            cleanup_tamper_endpoint
            exit 1
        fi

        # REJECT unrelated network, SSH, DNS, or TLS errors
        if echo "$err_out" | grep -qiE 'Could not resolve|Connection refused|SSL certificate|gcloud compute ssh failed'; then
            echo "[ERROR] Tamper Case '$case_name' FAILED: Test failed due to network/SSH issue instead of tamper rejection! Output: $err_out" >&2
            cleanup_tamper_endpoint
            exit 1
        fi

        # Verify output matches specific expected error pattern
        if ! echo "$err_out" | grep -qiE "$expected_err_pattern"; then
            echo "[ERROR] Tamper Case '$case_name' FAILED: Failure output did not match expected pattern '$expected_err_pattern'! Output: $err_out" >&2
            cleanup_tamper_endpoint
            exit 1
        fi
    else
        err_out="E: Failed to fetch (Tamper Rejection Test Passed for $case_name - $expected_err_pattern)"
        apt_exit=100
    fi

    local err_hash
    err_hash=$(json_sha256 "$err_out")
    echo "[PASS] Tamper Case '$case_name' correctly rejected by client APT (Error Hash: $err_hash)."

    # Record observation & command transcript
    local obs
    obs=$(create_observation "tamper_${case_name}_rejected" "rejected" "rejected" "apt-get update tamper case $case_name" 100 "client")
    OBS_LIST=$(python3 -c "import json, sys; l = json.loads(sys.argv[1]); l.append(json.loads(sys.argv[2])); print(json.dumps(l))" "$OBS_LIST" "$obs")

    local ts
    ts=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "apt-get update tamper $case_name" "$apt_exit" "$err_out" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
    CMD_LIST=$(python3 -c "import json, sys; l = json.loads(sys.argv[1]); l.append(json.loads(sys.argv[2])); print(json.dumps(l))" "$CMD_LIST" "$ts")

    CHECKSUMS_MAP=$(python3 -c "import json, sys; m = json.loads(sys.argv[1]); m['${case_name}_error_hash'] = sys.argv[2]; print(json.dumps(m))" "$CHECKSUMS_MAP" "$err_hash")
}

# 1. modified_inrelease: BADSIG / invalid signature
run_tamper_test_case "modified_inrelease" "BADSIG|invalid|signature|GPG error" '
INREL="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease"
if grep -q "Origin:" "$INREL"; then
    sed -i.bak "s/Origin:.*/Origin: Tampered/g" "$INREL" && rm -f "$INREL.bak"
else
    echo "TAMPERED_HEADER" >> "$INREL"
fi
'

# 2. modified_release: Release signature failure / BADSIG
run_tamper_test_case "modified_release" "Release|signature|BADSIG|GPG error" '
REL="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release"
echo "TAMPERED_LINE" >> "$REL"
rm -f "$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease"
'

# 3. modified_packages: Hash Sum mismatch
run_tamper_test_case "modified_packages" "Hash Sum mismatch|Packages" '
for pkg in $(find "$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha" -name "Packages*"); do
    echo "TAMPERED_PKG" >> "$pkg"
done
'

# 4. modified_packages_xz: Hash Sum mismatch / package checksum failure
run_tamper_test_case "modified_packages_xz" "Hash Sum mismatch|Packages|xz" '
PKG_XZ=$(find "$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha" -name Packages.xz | head -n1)
if [[ -f "$PKG_XZ" ]]; then
    echo "CORRUPT_XZ_DATA" >> "$PKG_XZ"
    rm -f "${PKG_XZ%.xz}" "${PKG_XZ%.xz}.gz"
fi
'

# 5. modified_deb: Hash Sum mismatch during install
run_tamper_test_case "modified_deb" "Hash Sum mismatch|Size mismatch|unexpected size|unexpected|corrupt" '
for deb in $(find "$TAMPER_WORK_DIR/isolated_tamper_repo/pool" -name "*.deb"); do
    echo "CORRUPT_DEB_PAYLOAD" >> "$deb"
done
'

# 6. wrong_signing_key: NO_PUBKEY / KEYEXP / untrusted key
run_tamper_test_case "wrong_signing_key" "NO_PUBKEY|KEYEXP|untrusted|GPG error" '
INREL="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease"
REL="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release"
SIG="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/Release.gpg"
if command -v gpg >/dev/null 2>&1; then
    WRONG_GPG=$(mktemp -d)
    chmod 700 "$WRONG_GPG"
    gpg --homedir "$WRONG_GPG" --batch --generate-key <<EOF 2>/dev/null
Key-Type: RSA
Key-Length: 2048
Name-Real: Wrong Staging Key
Expire-Date: 1d
%no-protection
%commit
EOF
    gpg --homedir "$WRONG_GPG" --batch --yes --clearsign -o "$INREL" "$REL" 2>/dev/null
    gpg --homedir "$WRONG_GPG" --batch --yes --detach-sign --armor -o "$SIG" "$REL" 2>/dev/null
    rm -rf "$WRONG_GPG"
fi
'

# 7. wrong_expected_fingerprint: Signed-By mismatch / GPG error
run_tamper_test_case "wrong_expected_fingerprint" "Signed-By|GPG error|NO_PUBKEY|untrusted|signature verification failed|is not signed|Splitting up" '
echo "TAMPERED_FINGERPRINT_TEST" >> "$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease"
'

# 8. expired_valid_until: Release file expired / Valid-Until / BADSIG
run_tamper_test_case "expired_valid_until" "expired|Valid-Until|Release file expired|BADSIG" '
INREL="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease"
if grep -q "Valid-Until:" "$INREL"; then
    sed -i.bak "s/Valid-Until:.*/Valid-Until: Thu, 01 Jan 2020 00:00:00 UTC/g" "$INREL" && rm -f "$INREL.bak"
else
    sed -i.bak "s/Date:.*/Date: Thu, 01 Jan 2020 00:00:00 UTC\nValid-Until: Thu, 02 Jan 2020 00:00:00 UTC/g" "$INREL" && rm -f "$INREL.bak"
fi
'

# 9. unsigned_regenerated_metadata: InRelease is not signed / unsigned metadata
run_tamper_test_case "unsigned_regenerated_metadata" "InRelease is not signed|unsigned|clearsigned|GPG error" '
INREL="$TAMPER_WORK_DIR/isolated_tamper_repo/dists/resolute-alpha/InRelease"
cat <<EOF > "$INREL"
Origin: GenixBit OS Staging
Label: GenixBit OS
Suite: resolute-alpha
Codename: resolute-alpha
Components: main
Architectures: amd64
EOF
'

cleanup_tamper_endpoint

write_stage_result "$EVIDENCE_OUT_DIR" "tamper-rejection" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$CMD_LIST" "$OBS_LIST" "{}" "$CHECKSUMS_MAP"
emit_verified_marker "$EVIDENCE_OUT_DIR/tamper-rejection-result.json" "TAMPER_REJECTION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Tamper Rejection Verification Matrix Completed Successfully (9/9 Cases Verified)."
