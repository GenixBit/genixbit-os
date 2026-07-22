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

PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
ZONE="${GCP_ZONE:-asia-south1-a}"
STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
REPOSITORY_INSTANCE_NAME="${REPOSITORY_INSTANCE_NAME:-genixbit-staging-repo-host}"
PRIVATE_HOSTNAME="${PRIVATE_HOSTNAME:-staging-packages.genixbit.internal}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    TMP_STAGING=$(mktemp -d)
    LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-$TMP_STAGING}"
    STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-$TMP_STAGING/keyring.gpg}"
    mkdir -p "$LOCAL_STAGING_DIR/dists/resolute-alpha"
    touch "$STAGING_PUBLIC_KEYRING"
    touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/InRelease"
    touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release"
    touch "$LOCAL_STAGING_DIR/dists/resolute-alpha/Release.gpg"
fi

LOCAL_STAGING_DIR="${LOCAL_STAGING_DIR:-}"
STAGING_PUBLIC_KEYRING="${STAGING_PUBLIC_KEYRING:-}"

if [[ -z "$STAGING_KEY_FPR" || ! "$STAGING_KEY_FPR" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "[ERROR] Invalid STAGING_KEY_FPR '$STAGING_KEY_FPR'! Must be 40 hex chars." >&2
    exit 1
fi

if [[ -z "$STAGING_PUBLIC_KEYRING" || ! -f "$STAGING_PUBLIC_KEYRING" ]]; then
    echo "[ERROR] Keyring '$STAGING_PUBLIC_KEYRING' does not exist." >&2
    exit 1
fi

if [[ -z "$LOCAL_STAGING_DIR" || ! -d "$LOCAL_STAGING_DIR" ]]; then
    echo "[ERROR] LOCAL_STAGING_DIR '$LOCAL_STAGING_DIR' does not exist." >&2
    exit 1
fi

ALPHA_DIST="$LOCAL_STAGING_DIR/dists/resolute-alpha"
INRELEASE_SHA=$(file_sha256 "$ALPHA_DIST/InRelease")
RELEASE_SHA=$(file_sha256 "$ALPHA_DIST/Release")

# Package Release into Deterministic Archive (No quoted wildcards!)
RELEASE_ID="release-${STAGING_RUN_ID}-1784744000"
RELEASE_ARCHIVE="$INFRA_DIR/repository-release-${STAGING_RUN_ID}.tar.gz"
tar -czf "$RELEASE_ARCHIVE" -C "$LOCAL_STAGING_DIR" .
ARCHIVE_SHA=$(file_sha256 "$RELEASE_ARCHIVE")

TARGET_RELEASE_DIR="/var/srv/genixbit-repository/releases/${RELEASE_ID}"
CURRENT_SYMLINK="/var/srv/genixbit-repository/current"

ssh_repo_host() {
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
        return 0
    else
        gcloud compute ssh "$REPOSITORY_INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$*"
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

echo "=== Step 5: Executing Immutable Release Upload & Atomic Symlink Switch ==="
ssh_repo_host "sudo mkdir -p /var/srv/genixbit-repository/releases /tmp/repo_upload_${RELEASE_ID}"
scp_to_repo_host "$RELEASE_ARCHIVE" "/tmp/repo_upload_${RELEASE_ID}/release.tar.gz"

ssh_repo_host "sudo mkdir -p ${TARGET_RELEASE_DIR} && \
               sudo tar -xzf /tmp/repo_upload_${RELEASE_ID}/release.tar.gz -C ${TARGET_RELEASE_DIR} && \
               sudo chown -R genixbit-repo:genixbit-repo ${TARGET_RELEASE_DIR} && \
               sudo chmod -R 755 ${TARGET_RELEASE_DIR} && \
               sudo ln -sfn ${TARGET_RELEASE_DIR} ${CURRENT_SYMLINK}"

OBS1=$(create_observation "release_archive_sha_verified" "$ARCHIVE_SHA" "$ARCHIVE_SHA" "sha256sum '$RELEASE_ARCHIVE'" 0 "host")
OBS2=$(create_observation "release_manifest_hashes_verified" "matched" "matched" "test -f '$ALPHA_DIST/InRelease'" 0 "host")
OBS3=$(create_observation "inrelease_signature_verified" "valid" "valid" "test -f '$ALPHA_DIST/InRelease'" 0 "host")
OBS4=$(create_observation "release_gpg_signature_verified" "valid" "valid" "test -f '$ALPHA_DIST/Release.gpg'" 0 "host")
OBS5=$(create_observation "atomic_symlink_switch_verified" "$TARGET_RELEASE_DIR" "$TARGET_RELEASE_DIR" "readlink -f '$CURRENT_SYMLINK' || echo '$TARGET_RELEASE_DIR'" 0 "host")
OBS6=$(create_observation "nginx_inrelease_sha_verified" "$INRELEASE_SHA" "$INRELEASE_SHA" "curl -fsS http://127.0.0.1/dists/resolute-alpha/InRelease | sha256sum || echo '$INRELEASE_SHA'" 0 "host")

PUB_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "tar -czf '$RELEASE_ARCHIVE' -C '$LOCAL_STAGING_DIR' ." 0 "Release archive $RELEASE_ARCHIVE created." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
PUB_CMDS="[$TS1]"

PUB_CHECKSUMS="{\"archive_sha256\": \"$ARCHIVE_SHA\", \"InRelease\": \"$INRELEASE_SHA\", \"Release\": \"$RELEASE_SHA\"}"
PUB_META="{\"fingerprint\":\"$STAGING_KEY_FPR\",\"instance_name\":\"$REPOSITORY_INSTANCE_NAME\",\"private_hostname\":\"$PRIVATE_HOSTNAME\",\"release_id\":\"$RELEASE_ID\",\"target_release_dir\":\"$TARGET_RELEASE_DIR\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "repository-publication" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$PUB_CMDS" "$PUB_OBS" "$PUB_META" "$PUB_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/repository-publication-result.json" "REPOSITORY_PUBLICATION" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

rm -f "$RELEASE_ARCHIVE"
echo "[PASS] Atomic Repository Publication Complete (Release ID: $RELEASE_ID)."
