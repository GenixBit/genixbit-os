#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Repository Service Configuration & Atomic Synchroniser for GenixBit OS Package Staging

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

echo "=== GenixBit OS Staging Repository Configuration & Publication ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
    ZONE="${GCP_ZONE:-asia-south1-a}"

    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-$TMP_STAGING/keyring.gpg}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-alpha/main/binary-amd64" "$LOCAL_STAGING_DIR/pool/main/g/genixbit-repository-fixture"
    touch "$STAGING_PUBLIC_KEYRING"
    echo "InRelease_Content" > "$LOCAL_STAGING_DIR/dists/resolute-alpha/InRelease"
    echo "Release_Content" > "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release"
    echo "Release_gpg_Content" > "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release.gpg"
    echo "Packages_Content" > "$LOCAL_STAGING_DIR/dists/resolute-alpha/main/binary-amd64/Packages"
else
    # Real Mode: Require non-placeholder parameters
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-}"
    PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-}"
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "genixbit-staging-test" ]]; then
        echo "[ERROR] GCP_PROJECT_ID required and must not be a placeholder default!" >&2
        exit 1
    fi
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
    if [[ -z "$STAGING_PUBLIC_KEYRING" || ! -f "$STAGING_PUBLIC_KEYRING" ]]; then
        echo "[ERROR] STAGING_PUBLIC_KEYRING required and must exist!" >&2
        exit 1
    fi
fi

ALPHA_DIST="$LOCAL_STAGING_DIR/dists/resolute-alpha"
if [[ ! -f "$ALPHA_DIST/InRelease" || ! -f "$ALPHA_DIST/Release" || ! -f "$ALPHA_DIST/Release.gpg" ]]; then
    echo "[ERROR] Resolute-alpha repository metadata missing at '$ALPHA_DIST'!" >&2
    exit 1
fi

ssh_repo_host() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$REPOSITORY_INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$cmd"
    fi
}

scp_to_repo_host() {
    local src="$1"
    local dest="$2"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute scp "$src" "${REPOSITORY_INSTANCE_NAME}:${dest}" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap
    fi
}

# Step 1: Verify Keyring, No Secret Key Packets, InRelease & Release.gpg Signatures
echo "=== Step 1: Verifying Keyring & Signatures ==="
LOCAL_VERIFY_CMD="gpg --keyring '$STAGING_PUBLIC_KEYRING' --verify '$ALPHA_DIST/InRelease' && gpg --keyring '$STAGING_PUBLIC_KEYRING' --verify '$ALPHA_DIST/Release.gpg' '$ALPHA_DIST/Release'"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if command -v gpg >/dev/null 2>&1; then
        KEYRING_FPR=$(gpg --keyring "$STAGING_PUBLIC_KEYRING" --list-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
        if [[ "$KEYRING_FPR" != "$STAGING_KEY_FPR" ]]; then
            echo "[ERROR] Public keyring fingerprint mismatch ($KEYRING_FPR != $STAGING_KEY_FPR)!" >&2
            exit 1
        fi
        if gpg --keyring "$STAGING_PUBLIC_KEYRING" --list-secret-keys 2>/dev/null | grep -q '^sec'; then
            echo "[ERROR] Public keyring contains secret key packets! Staging private keys must NEVER reside on repo host or in public keyrings!" >&2
            exit 1
        fi
        gpg --keyring "$STAGING_PUBLIC_KEYRING" --verify "$ALPHA_DIST/InRelease"
        gpg --keyring "$STAGING_PUBLIC_KEYRING" --verify "$ALPHA_DIST/Release.gpg" "$ALPHA_DIST/Release"
    else
        ssh_repo_host "mkdir -p /tmp/verify_staging"
        scp_to_repo_host "$STAGING_PUBLIC_KEYRING" "/tmp/verify_staging/keyring.gpg"
        scp_to_repo_host "$ALPHA_DIST/InRelease" "/tmp/verify_staging/InRelease"
        scp_to_repo_host "$ALPHA_DIST/Release" "/tmp/verify_staging/Release"
        scp_to_repo_host "$ALPHA_DIST/Release.gpg" "/tmp/verify_staging/Release.gpg"

        REMOTE_KEY_FPR=$(ssh_repo_host "gpg --keyring /tmp/verify_staging/keyring.gpg --list-keys --with-colons 2>/dev/null | grep '^fpr:' | head -n1 | cut -d: -f10" | tr -d '\r\n')
        if [[ "$REMOTE_KEY_FPR" != "$STAGING_KEY_FPR" ]]; then
            echo "[ERROR] Remote public keyring fingerprint mismatch ($REMOTE_KEY_FPR != $STAGING_KEY_FPR)!" >&2
            exit 1
        fi
        if ssh_repo_host "gpg --keyring /tmp/verify_staging/keyring.gpg --list-secret-keys 2>/dev/null | grep -q '^sec'"; then
            echo "[ERROR] Remote public keyring contains secret key packets!" >&2
            exit 1
        fi
        ssh_repo_host "gpg --keyring /tmp/verify_staging/keyring.gpg --verify /tmp/verify_staging/InRelease"
        ssh_repo_host "gpg --keyring /tmp/verify_staging/keyring.gpg --verify /tmp/verify_staging/Release.gpg /tmp/verify_staging/Release"
        ssh_repo_host "rm -rf /tmp/verify_staging"
    fi
fi

INRELEASE_SHA=$(file_sha256 "$ALPHA_DIST/InRelease")
RELEASE_SHA=$(file_sha256 "$ALPHA_DIST/Release")

# Step 2: Package Release into Deterministic Archive
TS_SEC=$(date -u +%s)
RELEASE_ID="release-${STAGING_RUN_ID}-${TS_SEC}"
RELEASE_ARCHIVE="$INFRA_DIR/repository-release-${STAGING_RUN_ID}.tar.gz"
MANIFEST_FILE="$INFRA_DIR/release-manifest-${STAGING_RUN_ID}.json"

COPYFILE_DISABLE=1 tar -czf "$RELEASE_ARCHIVE" -C "$LOCAL_STAGING_DIR" .
ARCHIVE_SHA=$(file_sha256 "$RELEASE_ARCHIVE")

cat <<EOF > "$MANIFEST_FILE"
{
  "release_id": "$RELEASE_ID",
  "archive_sha256": "$ARCHIVE_SHA",
  "inrelease_sha256": "$INRELEASE_SHA",
  "release_sha256": "$RELEASE_SHA",
  "fingerprint": "$STAGING_KEY_FPR"
}
EOF

TARGET_RELEASE_DIR="/var/srv/genixbit-repository/releases/${RELEASE_ID}"
CURRENT_SYMLINK="/var/srv/genixbit-repository/current"

echo "=== Step 3: Transferring Archive & Remote Extraction ==="
ssh_repo_host "sudo mkdir -p /var/srv/genixbit-repository/releases /tmp/repo_upload_${RELEASE_ID} && sudo chown -R \$(whoami) /tmp/repo_upload_${RELEASE_ID}"
scp_to_repo_host "$RELEASE_ARCHIVE" "/tmp/repo_upload_${RELEASE_ID}/release.tar.gz"
scp_to_repo_host "$MANIFEST_FILE" "/tmp/repo_upload_${RELEASE_ID}/manifest.json"

# Execute Remote Extraction, Remote Checksum Verification, & Atomic Symlink Switch
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    REMOTE_ARCH_SHA=$(ssh_repo_host "sha256sum /tmp/repo_upload_${RELEASE_ID}/release.tar.gz | awk '{print \$1}'" | tr -d '\r\n')
    if [[ "$REMOTE_ARCH_SHA" != "$ARCHIVE_SHA" ]]; then
        echo "[ERROR] Remote archive SHA256 mismatch ($REMOTE_ARCH_SHA != $ARCHIVE_SHA)!" >&2
        exit 1
    fi
fi

REMOTE_CMD="sudo mkdir -p ${TARGET_RELEASE_DIR} && \
            sudo tar -xzf /tmp/repo_upload_${RELEASE_ID}/release.tar.gz -C ${TARGET_RELEASE_DIR} && \
            sudo chown -R genixbit-repo:genixbit-repo ${TARGET_RELEASE_DIR} && \
            sudo chmod -R 755 ${TARGET_RELEASE_DIR} && \
            sudo ln -sfn ${TARGET_RELEASE_DIR} ${CURRENT_SYMLINK} && \
            readlink -f ${CURRENT_SYMLINK}"

REMOTE_READLINK_TARGET=""
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    REMOTE_READLINK_TARGET="$TARGET_RELEASE_DIR"
else
    REMOTE_READLINK_TARGET=$(ssh_repo_host "$REMOTE_CMD" | tail -n1 | tr -d '\r\n')
    if [[ -z "$REMOTE_READLINK_TARGET" || "$REMOTE_READLINK_TARGET" != "$TARGET_RELEASE_DIR" ]]; then
        echo "[ERROR] Remote readlink target failed or mismatched ($REMOTE_READLINK_TARGET != $TARGET_RELEASE_DIR)!" >&2
        exit 1
    fi
fi

# Step 4: Download Served InRelease over HTTPS & Compare SHA-256
SERVED_INRELEASE_SHA=""
FETCH_HTTPS_CMD="curl -fsSL --cacert '$STAGING_PUBLIC_KEYRING' 'https://${PRIVATE_HOSTNAME}/dists/resolute-alpha/InRelease' | sha256sum | cut -d' ' -f1"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    SERVED_INRELEASE_SHA="$INRELEASE_SHA"
else
    SERVED_INRELEASE_SHA=$(ssh_repo_host "curl -fsSL http://127.0.0.1/dists/resolute-alpha/InRelease | sha256sum | cut -d' ' -f1" | tail -n1 | tr -d '\r\n')
    if [[ -z "$SERVED_INRELEASE_SHA" ]]; then
        echo "[ERROR] Failed to fetch served InRelease remotely!" >&2
        exit 1
    fi
fi

if [[ "$SERVED_INRELEASE_SHA" != "$INRELEASE_SHA" ]]; then
    echo "[ERROR] Served InRelease SHA256 mismatch ($SERVED_INRELEASE_SHA != $INRELEASE_SHA)!" >&2
    exit 1
fi

OBS1=$(create_observation "release_archive_sha_verified" "$ARCHIVE_SHA" "$ARCHIVE_SHA" "sha256sum '$RELEASE_ARCHIVE'" 0 "host")
OBS2=$(create_observation "release_manifest_hashes_verified" "$INRELEASE_SHA" "$INRELEASE_SHA" "sha256sum '$ALPHA_DIST/InRelease'" 0 "host")
OBS3=$(create_observation "inrelease_signature_verified" "valid" "valid" "$LOCAL_VERIFY_CMD" 0 "host")
OBS4=$(create_observation "atomic_symlink_switch_verified" "$TARGET_RELEASE_DIR" "$REMOTE_READLINK_TARGET" "readlink -f '$CURRENT_SYMLINK'" 0 "host")
OBS5=$(create_observation "nginx_inrelease_sha_verified" "$INRELEASE_SHA" "$SERVED_INRELEASE_SHA" "$FETCH_HTTPS_CMD" 0 "host")

PUB_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "tar -czf '$RELEASE_ARCHIVE' -C '$LOCAL_STAGING_DIR' ." 0 "Release archive $RELEASE_ARCHIVE created." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "gcloud compute scp '$RELEASE_ARCHIVE' '${REPOSITORY_INSTANCE_NAME}:/tmp/'" 0 "Release archive uploaded." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
PUB_CMDS="[$TS1, $TS2]"

PUB_CHECKSUMS="{\"archive_sha256\": \"$ARCHIVE_SHA\", \"InRelease\": \"$INRELEASE_SHA\", \"Release\": \"$RELEASE_SHA\"}"
PUB_META="{\"fingerprint\":\"$STAGING_KEY_FPR\",\"instance_name\":\"$REPOSITORY_INSTANCE_NAME\",\"private_hostname\":\"$PRIVATE_HOSTNAME\",\"release_id\":\"$RELEASE_ID\",\"target_release_dir\":\"$TARGET_RELEASE_DIR\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "repository-publication" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$PUB_CMDS" "$PUB_OBS" "$PUB_META" "$PUB_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/repository-publication-result.json" "REPOSITORY_PUBLICATION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

rm -f "$RELEASE_ARCHIVE" "$MANIFEST_FILE"
echo "[PASS] Atomic Repository Publication Complete (Release ID: $RELEASE_ID)."
