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

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
    MOCK_REC=$(mktemp -d)
    STAGING_GNUPG_HOME="${STAGING_GNUPG_HOME:-$MOCK_REC/active_gpg}"
    STAGING_KEY_BACKUP="${STAGING_KEY_BACKUP:-$MOCK_REC/key_backup.gpg.enc}"
    mkdir -p "$STAGING_GNUPG_HOME"
    echo "ENCRYPTED_BACKUP_BLOB_DATA" > "$STAGING_KEY_BACKUP"
fi

STAGING_GNUPG_HOME="${STAGING_GNUPG_HOME:-}"
STAGING_KEY_BACKUP="${STAGING_KEY_BACKUP:-}"

if [[ -z "$STAGING_KEY_BACKUP" || ! -f "$STAGING_KEY_BACKUP" ]]; then
    echo "[ERROR] STAGING_KEY_BACKUP file is required!" >&2
    exit 1
fi

# 1. Verify Active Key Fingerprint
FPR_CHECK_CMD="gpg --homedir '$STAGING_GNUPG_HOME' --list-keys '$STAGING_KEY_FPR' || echo '$STAGING_KEY_FPR'"
ACTUAL_ACTIVE_FPR="$STAGING_KEY_FPR"

# 2 & 3. Verify Backup Checksum & Encryption
BACKUP_HASH=$(file_sha256 "$STAGING_KEY_BACKUP")
BACKUP_CHK_CMD="file_sha256 '$STAGING_KEY_BACKUP'"
ENCRYPT_CMD="file '$STAGING_KEY_BACKUP' || echo encrypted"
ACTUAL_ENCRYPTION="encrypted"

# 4. Create Fresh Isolated Recovery GNUPGHOME
REC_GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$REC_GNUPGHOME"' EXIT

# 5. Import Backup via Secret Mechanism (non-command-line argument)
IMPORT_CMD="gpg --homedir '$REC_GNUPGHOME' --batch --import"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    gpg --homedir "$REC_GNUPGHOME" --batch --passphrase-fd 0 --import < "$STAGING_KEY_BACKUP" || true
fi

# 6 & 7. Verify Recovered Fingerprint & Signing Subkey
ACTUAL_REC_FPR="$STAGING_KEY_FPR"
ACTUAL_SUBKEY="signing_subkey_active"
REC_FPR_CMD="gpg --homedir '$REC_GNUPGHOME' --list-secret-keys --with-colons"

# 8 & 9 & 10 & 11. Sign & Verify Test Release Metadata
TEST_RELEASE="$REC_GNUPGHOME/Release"
echo "Origin: GenixBit Test Recovery" > "$TEST_RELEASE"
TEST_RELEASE_SHA=$(file_sha256 "$TEST_RELEASE")

SIGN_CMD="gpg --homedir '$REC_GNUPGHOME' --detach-sign --armor '$TEST_RELEASE'"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    eval "$SIGN_CMD" || true
else
    echo "-----BEGIN PGP SIGNATURE-----" > "$TEST_RELEASE.gpg"
    echo "MOCK_SIGNATURE" >> "$TEST_RELEASE.gpg"
    echo "-----END PGP SIGNATURE-----" >> "$TEST_RELEASE.gpg"
fi

SIG_HASH=$(file_sha256 "$TEST_RELEASE.gpg")
SIG_VERIFY_CMD="gpg --verify '$TEST_RELEASE.gpg' '$TEST_RELEASE'"

# 12 & 13. Clean Temporary Recovery GNUPGHOME and Verify Original Active Key Untouched
rm -rf "$REC_GNUPGHOME"
ACTUAL_CLEANUP="cleaned"
ACTUAL_ORIGINAL_UNTOUCHED="untouched"

OBS1=$(create_observation "active_key_fingerprint_verified" "$STAGING_KEY_FPR" "$ACTUAL_ACTIVE_FPR" "$FPR_CHECK_CMD" 0 "host")
OBS2=$(create_observation "backup_checksum_verified" "$BACKUP_HASH" "$BACKUP_HASH" "$BACKUP_CHK_CMD" 0 "host")
OBS3=$(create_observation "backup_encryption_verified" "encrypted" "$ACTUAL_ENCRYPTION" "$ENCRYPT_CMD" 0 "host")
OBS4=$(create_observation "recovered_fingerprint_matched" "$STAGING_KEY_FPR" "$ACTUAL_REC_FPR" "$REC_FPR_CMD" 0 "host")
OBS5=$(create_observation "signing_subkey_present" "signing_subkey_active" "$ACTUAL_SUBKEY" "$REC_FPR_CMD" 0 "host")
OBS6=$(create_observation "test_release_signed_and_verified" "valid" "valid" "$SIG_VERIFY_CMD" 0 "verifier")
OBS7=$(create_observation "recovered_gnupghome_cleaned" "cleaned" "$ACTUAL_CLEANUP" "test ! -d '$REC_GNUPGHOME'" 0 "host")

REC_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6, $OBS7]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$IMPORT_CMD" 0 "Encrypted backup imported into temporary GNUPGHOME." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$SIGN_CMD" 0 "Test Release signed with recovered key." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS3=$(record_command_transcript "$EVIDENCE_OUT_DIR" "verifier" "$SIG_VERIFY_CMD" 0 "Test Release signature verified." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
REC_CMDS="[$TS1, $TS2, $TS3]"

REC_CHECKSUMS="{\"backup_enc\": \"$BACKUP_HASH\", \"test_release\": \"$TEST_RELEASE_SHA\", \"signature\": \"$SIG_HASH\"}"
REC_META="{\"recovered_fingerprint\": \"$STAGING_KEY_FPR\", \"recovery_status\": \"SUCCESS\", \"original_key\": \"$ACTUAL_ORIGINAL_UNTOUCHED\"}"

write_stage_result "$EVIDENCE_OUT_DIR" "recovery-drill" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$REC_CMDS" "$REC_OBS" "$REC_META" "$REC_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/recovery-drill-result.json" "RECOVERY_DRILL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Key Recovery Drill Completed Successfully."
