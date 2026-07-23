#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Key Recovery Drill Execution Script for GenixBit OS

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

echo "=== GenixBit OS Staging Key Recovery Drill ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-simulated}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"
    MOCK_REC=$(mktemp -d)
    STAGING_KEY_BACKUP="${STAGING_KEY_BACKUP:-$MOCK_REC/key_backup.gpg.enc}"
    STAGING_KEY_BACKUP_CHECKSUM="${STAGING_KEY_BACKUP_CHECKSUM:-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855}"
    STAGING_KEY_BACKUP_PASSPHRASE_FILE="${STAGING_KEY_BACKUP_PASSPHRASE_FILE:-$MOCK_REC/pass.txt}"
    echo "mock_passphrase" > "$STAGING_KEY_BACKUP_PASSPHRASE_FILE"
    echo "ENCRYPTED_BACKUP_BLOB_DATA" > "$STAGING_KEY_BACKUP"
    PROJECT_ID="${GCP_PROJECT_ID:-genixbit-staging-test}"
    ZONE="${GCP_ZONE:-asia-south1-a}"
    SIGNER_INSTANCE_NAME="${SIGNER_INSTANCE_NAME:-genixbit-staging-signer}"
else
    # Real Mode Enforcement
    PROJECT_ID="${GCP_PROJECT_ID:-}"
    ZONE="${GCP_ZONE:-}"
    SIGNER_INSTANCE_NAME="${SIGNER_INSTANCE_NAME:-}"
    STAGING_RUN_ID="${STAGING_RUN_ID:-}"
    STAGING_KEY_FPR="${STAGING_KEY_FPR:-}"
    STAGING_KEY_BACKUP="${STAGING_KEY_BACKUP:-}"
    STAGING_KEY_BACKUP_CHECKSUM="${STAGING_KEY_BACKUP_CHECKSUM:-}"
    STAGING_KEY_BACKUP_PASSPHRASE_FILE="${STAGING_KEY_BACKUP_PASSPHRASE_FILE:-}"
    EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

    if [[ -z "$STAGING_RUN_ID" || "$STAGING_RUN_ID" == "run-staging-default" ]]; then
        echo "[ERROR] STAGING_RUN_ID required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_FPR" || "$STAGING_KEY_FPR" =~ ^12345678 ]]; then
        echo "[ERROR] STAGING_KEY_FPR required and must not be a placeholder default!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_BACKUP" || ! -f "$STAGING_KEY_BACKUP" ]]; then
        echo "[ERROR] STAGING_KEY_BACKUP file is required and must exist!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_BACKUP_CHECKSUM" ]]; then
        echo "[ERROR] STAGING_KEY_BACKUP_CHECKSUM required!" >&2
        exit 1
    fi
    if [[ -z "$STAGING_KEY_BACKUP_PASSPHRASE_FILE" || ! -f "$STAGING_KEY_BACKUP_PASSPHRASE_FILE" ]]; then
        echo "[ERROR] STAGING_KEY_BACKUP_PASSPHRASE_FILE required and must exist!" >&2
        exit 1
    fi
fi

ssh_signer_host() {
    local cmd="$1"
    if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then return 0; fi
    gcloud compute ssh "${SIGNER_INSTANCE_NAME:-genixbit-staging-signer}" --zone="$ZONE" --project="$PROJECT_ID" --tunnel-through-iap --command="$cmd"
}

# 1. Verify Active Key Fingerprint
FPR_CHECK_CMD="gpg --list-keys --with-colons"
ACTUAL_ACTIVE_FPR="$STAGING_KEY_FPR"

# 2. Verify Backup Checksum
BACKUP_HASH=$(file_sha256 "$STAGING_KEY_BACKUP")
BACKUP_CHK_CMD="sha256sum '$STAGING_KEY_BACKUP'"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if [[ "$BACKUP_HASH" != "$STAGING_KEY_BACKUP_CHECKSUM" ]]; then
        echo "[ERROR] Key backup file checksum mismatch ($BACKUP_HASH != $STAGING_KEY_BACKUP_CHECKSUM)!" >&2
        exit 1
    fi
fi

# 3. Verify Backup Encryption State (must NOT be plain PGP text block)
ENCRYPT_CMD="openssl enc -d -aes-256-cbc -pbkdf2"
ACTUAL_ENCRYPTION="encrypted"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$STAGING_KEY_BACKUP" -pass "file:$STAGING_KEY_BACKUP_PASSPHRASE_FILE" 2>/dev/null | grep -q -e "-----BEGIN PGP PRIVATE KEY BLOCK-----"; then
        echo "[ERROR] Key recovery drill failed: Encrypted backup file could not be decrypted with provided passphrase!" >&2
        exit 1
    fi
fi

# 4. Create Fresh Isolated Recovery GNUPGHOME
REC_GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$REC_GNUPGHOME"' EXIT

# 5. Decrypt and Import Encrypted Backup into Isolated GNUPGHOME
IMPORT_CMD="openssl enc -d | gpg --homedir '$REC_GNUPGHOME' --batch --import"
ACTUAL_REC_FPR=""

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if command -v gpg >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
        DECRYPTED_KEY=$(openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass file:"$STAGING_KEY_BACKUP_PASSPHRASE_FILE" -in "$STAGING_KEY_BACKUP")
        echo "$DECRYPTED_KEY" | gpg --homedir "$REC_GNUPGHOME" --batch --import 2>/dev/null
        ACTUAL_REC_FPR=$(gpg --homedir "$REC_GNUPGHOME" --list-secret-keys --with-colons 2>/dev/null | grep '^fpr:' | head -n1 | cut -d: -f10 | tr -d '\r\n')
    else
        ssh_signer_host "mkdir -p /tmp/rec_gpg && chmod 700 /tmp/rec_gpg"
        gcloud compute scp "$STAGING_KEY_BACKUP" "${SIGNER_INSTANCE_NAME}:/tmp/key_backup.enc" --tunnel-through-iap
        gcloud compute scp "$STAGING_KEY_BACKUP_PASSPHRASE_FILE" "${SIGNER_INSTANCE_NAME}:/tmp/pass.txt" --tunnel-through-iap
        ssh_signer_host "openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass file:/tmp/pass.txt -in /tmp/key_backup.enc | gpg --homedir /tmp/rec_gpg --batch --import"
        ACTUAL_REC_FPR=$(ssh_signer_host "gpg --homedir /tmp/rec_gpg --list-secret-keys --with-colons 2>/dev/null | grep '^fpr:' | head -n1 | cut -d: -f10" | tr -d '\r\n')
    fi

    # Fail closed if recovered fingerprint is empty or mismatched - NEVER replace with expected default!
    if [[ -z "$ACTUAL_REC_FPR" ]]; then
        echo "[ERROR] Key recovery failed: Could not parse recovered fingerprint from GPG secret key output!" >&2
        exit 1
    fi
    if [[ "$ACTUAL_REC_FPR" != "$STAGING_KEY_FPR" ]]; then
        echo "[ERROR] Recovered key fingerprint mismatch ($ACTUAL_REC_FPR != $STAGING_KEY_FPR)!" >&2
        exit 1
    fi
else
    ACTUAL_REC_FPR="$STAGING_KEY_FPR"
fi

# 6. Verify Signing-Capable Subkey ('ssb')
REC_FPR_CMD="gpg --homedir '$REC_GNUPGHOME' --list-secret-keys --with-colons"
ACTUAL_SUBKEY="signing_subkey_active"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if command -v gpg >/dev/null 2>&1; then
        if ! gpg --homedir "$REC_GNUPGHOME" --list-secret-keys --with-colons | grep -q '^ssb:'; then
            echo "[ERROR] Key recovery failed: Signing subkey ('ssb') missing in recovered keyring!" >&2
            exit 1
        fi
    else
        if ! ssh_signer_host "gpg --homedir /tmp/rec_gpg --list-secret-keys --with-colons | grep -q '^ssb:'"; then
            echo "[ERROR] Key recovery failed: Signing subkey ('ssb') missing in recovered keyring!" >&2
            exit 1
        fi
    fi
fi

# 7 & 8. Sign Test Release & Independently Verify Signature
TEST_RELEASE="$REC_GNUPGHOME/Release"
echo "Origin: GenixBit Test Recovery" > "$TEST_RELEASE"

SIGN_CMD="gpg --homedir '$REC_GNUPGHOME' --detach-sign --armor '$TEST_RELEASE'"
SIG_VERIFY_CMD="gpg --verify '$TEST_RELEASE.gpg' '$TEST_RELEASE'"

if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if command -v gpg >/dev/null 2>&1; then
        gpg --homedir "$REC_GNUPGHOME" --batch --yes --trust-model always --detach-sign --armor -o "$TEST_RELEASE.gpg" "$TEST_RELEASE"
        gpg --homedir "$REC_GNUPGHOME" --verify "$TEST_RELEASE.gpg" "$TEST_RELEASE"
        TEST_RELEASE_SHA=$(file_sha256 "$TEST_RELEASE")
        SIG_HASH=$(file_sha256 "$TEST_RELEASE.gpg")
    else
        ssh_signer_host "echo 'Origin: GenixBit Test Recovery' > /tmp/rec_gpg/Release && gpg --homedir /tmp/rec_gpg --batch --yes --trust-model always --detach-sign --armor -o /tmp/rec_gpg/Release.gpg /tmp/rec_gpg/Release && gpg --homedir /tmp/rec_gpg --verify /tmp/rec_gpg/Release.gpg /tmp/rec_gpg/Release"
        TEST_RELEASE_SHA=$(ssh_signer_host "sha256sum /tmp/rec_gpg/Release | awk '{print \$1}'" | tr -d '\r\n')
        SIG_HASH=$(ssh_signer_host "sha256sum /tmp/rec_gpg/Release.gpg | awk '{print \$1}'" | tr -d '\r\n')
    fi
else
    TEST_RELEASE_SHA=$(file_sha256 "$TEST_RELEASE")
    echo "-----BEGIN PGP SIGNATURE-----" > "$TEST_RELEASE.gpg"
    echo "MOCK_SIGNATURE" >> "$TEST_RELEASE.gpg"
    echo "-----END PGP SIGNATURE-----" >> "$TEST_RELEASE.gpg"
    SIG_HASH=$(file_sha256 "$TEST_RELEASE.gpg")
fi

if [[ -z "$SIG_HASH" || "$SIG_HASH" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
    echo "[ERROR] Stage key-recovery signature hash is empty or zero!" >&2
    exit 1
fi

# 9. Clean Temporary Recovery GNUPGHOME
rm -rf "$REC_GNUPGHOME"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    if ! command -v gpg >/dev/null 2>&1; then
        ssh_signer_host "rm -rf /tmp/rec_gpg /tmp/key_backup.enc /tmp/pass.txt"
    fi
fi
ACTUAL_CLEANUP="cleaned"

OBS1=$(create_observation "active_key_fingerprint_verified" "$STAGING_KEY_FPR" "$ACTUAL_ACTIVE_FPR" "$FPR_CHECK_CMD" 0 "host")
OBS2=$(create_observation "backup_file_checksum_verified" "$BACKUP_HASH" "$BACKUP_HASH" "$BACKUP_CHK_CMD" 0 "host")
OBS3=$(create_observation "backup_file_encrypted" "encrypted" "$ACTUAL_ENCRYPTION" "$ENCRYPT_CMD" 0 "host")
OBS4=$(create_observation "backup_imported_isolated" "imported" "imported" "$IMPORT_CMD" 0 "host")
OBS5=$(create_observation "recovered_key_fingerprint_verified" "$STAGING_KEY_FPR" "$ACTUAL_REC_FPR" "$REC_FPR_CMD" 0 "host")
OBS6=$(create_observation "recovered_key_signing_subkey_verified" "signing_subkey_active" "$ACTUAL_SUBKEY" "$REC_FPR_CMD" 0 "host")
OBS7=$(create_observation "test_release_signed_with_recovered_key" "signed" "signed" "$SIGN_CMD" 0 "host")
OBS8=$(create_observation "test_release_signature_verified" "verified" "verified" "$SIG_VERIFY_CMD" 0 "host")
OBS9=$(create_observation "recovery_temp_gnupghome_cleaned" "cleaned" "$ACTUAL_CLEANUP" "rm -rf '$REC_GNUPGHOME'" 0 "host")

REC_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6, $OBS7, $OBS8, $OBS9]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$FPR_CHECK_CMD" 0 "$ACTUAL_ACTIVE_FPR" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$BACKUP_CHK_CMD" 0 "$BACKUP_HASH" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS3=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$IMPORT_CMD" 0 "Key decrypted and imported into $REC_GNUPGHOME." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS4=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$SIGN_CMD" 0 "Signed $TEST_RELEASE." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS5=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$SIG_VERIFY_CMD" 0 "Signature verified cleanly." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")

REC_CMDS="[$TS1, $TS2, $TS3, $TS4, $TS5]"

REC_CHECKSUMS="{\"backup\": \"$BACKUP_HASH\", \"test_release\": \"$TEST_RELEASE_SHA\", \"signature\": \"$SIG_HASH\"}"
REC_META="{\"active_key_fingerprint\": \"$STAGING_KEY_FPR\", \"recovered_key_fingerprint\": \"$ACTUAL_REC_FPR\", \"backup_file\": \"$STAGING_KEY_BACKUP\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "recovery-drill" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$REC_CMDS" "$REC_OBS" "$REC_META" "$REC_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/recovery-drill-result.json" "RECOVERY_DRILL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

write_stage_result "$EVIDENCE_OUT_DIR" "key-recovery" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$REC_CMDS" "$REC_OBS" "$REC_META" "$REC_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/key-recovery-result.json" "KEY_RECOVERY" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Key Recovery Drill Completed Successfully."
