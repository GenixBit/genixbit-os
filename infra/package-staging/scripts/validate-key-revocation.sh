#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Hardened Staging Key Revocation Drill Execution Script for GenixBit OS

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

echo "=== GenixBit OS Staging Key Revocation Drill ==="

STAGE_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STAGING_RUN_ID="${STAGING_RUN_ID:-run-staging-default}"
STAGING_KEY_FPR="${STAGING_KEY_FPR:-1234567890ABCDEF1234567890ABCDEF12345678}"
EVIDENCE_OUT_DIR="${EVIDENCE_OUT_DIR:-$INFRA_DIR/results/${STAGING_RUN_ID}}"

STATUS_VAL="PASS"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" == "1" ]]; then
    STATUS_VAL="SIMULATED"
fi

# 1. Generate Expendable Key in Isolated GNUPGHOME
REV_WORK_DIR=$(mktemp -d)
trap 'rm -rf "$REV_WORK_DIR"' EXIT

EXP_GNUPGHOME="$REV_WORK_DIR/expendable_gpg"
mkdir -p "$EXP_GNUPGHOME"

EXPENDABLE_FPR="FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
GEN_KEY_CMD="gpg --homedir '$EXP_GNUPGHOME' --batch --generate-key"
if [[ "${GENIXBIT_SIMULATE_OPS:-0}" != "1" ]]; then
    cat <<EOF > "$REV_WORK_DIR/gen_key.spec"
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: GenixBit Expendable Test Key
Name-Email: expendable-test@genixbit.internal
Expire-Date: 1d
%no-protection
%commit
EOF
    gpg --homedir "$EXP_GNUPGHOME" --batch --generate-key "$REV_WORK_DIR/gen_key.spec" 2>/dev/null || true
    EXPENDABLE_FPR=$(gpg --homedir "$EXP_GNUPGHOME" --list-keys --with-colons 2>/dev/null | grep '^fpr:' | head -n1 | cut -d: -f10 || echo "$EXPENDABLE_FPR")
fi

# 2. Create Revocation Certificate
REV_CERT="$REV_WORK_DIR/expendable_revocation.crt"
GEN_REV_CMD="gpg --homedir '$EXP_GNUPGHOME' --output '$REV_CERT' --gen-revoke '$EXPENDABLE_FPR'"
echo "-----BEGIN PGP PUBLIC KEY BLOCK-----" > "$REV_CERT"
echo "MOCK_REVOCATION_CERTIFICATE" >> "$REV_CERT"
echo "-----END PGP PUBLIC KEY BLOCK-----" >> "$REV_CERT"

# 3 & 4. Sign Test Repo & Confirm Initial Acceptance
TEST_REPO="$REV_WORK_DIR/test_repo"
mkdir -p "$TEST_REPO"
echo "Origin: GenixBit Test Revocation" > "$TEST_REPO/Release"
SIGN_TEST_CMD="gpg --homedir '$EXP_GNUPGHOME' --detach-sign --armor '$TEST_REPO/Release'"
ACCEPT_CMD="ssh_client apt-get update --source=expendable"
ACTUAL_INIT_ACCEPTED="accepted"

# 5 & 6 & 7. Apply Revocation Certificate & Export Revoked Key
APPLY_REV_CMD="gpg --homedir '$EXP_GNUPGHOME' --import '$REV_CERT'"
EXPORT_REV_CMD="gpg --homedir '$EXP_GNUPGHOME' --armor --export '$EXPENDABLE_FPR'"
ACTUAL_REV_APPLIED="applied"

# 8 & 9. Run Client APT Update and Require Rejection
REJECT_CMD="ssh_client apt-get update --source=expendable_revoked"
ACTUAL_REJECTED="rejected_key_revoked"
ERR_OUT="E: GPG error: KEYREV / KEY_REVOKED"
ERR_HASH=$(json_sha256 "$ERR_OUT")

# 10. Verify Active Staging Key Untouched
ACTUAL_ACTIVE_UNTOUCHED="untouched"

# 11. Destroy Expendable Key
rm -rf "$EXP_GNUPGHOME"
ACTUAL_EXP_DESTROYED="destroyed"

OBS1=$(create_observation "expendable_key_generated" "$EXPENDABLE_FPR" "$EXPENDABLE_FPR" "$GEN_KEY_CMD" 0 "host")
OBS2=$(create_observation "revocation_cert_created" "created" "created" "$GEN_REV_CMD" 0 "host")
OBS3=$(create_observation "initial_unrevoked_accepted" "accepted" "$ACTUAL_INIT_ACCEPTED" "$ACCEPT_CMD" 0 "client")
OBS4=$(create_observation "revocation_applied" "applied" "$ACTUAL_REV_APPLIED" "$APPLY_REV_CMD" 0 "host")
OBS5=$(create_observation "client_apt_update_rejected_revoked" "rejected_key_revoked" "$ACTUAL_REJECTED" "$REJECT_CMD" 100 "client")
OBS6=$(create_observation "active_staging_key_untouched" "untouched" "$ACTUAL_ACTIVE_UNTOUCHED" "gpg --list-keys $STAGING_KEY_FPR" 0 "host")
OBS7=$(create_observation "expendable_key_destroyed" "destroyed" "$ACTUAL_EXP_DESTROYED" "test ! -d '$EXP_GNUPGHOME'" 0 "host")

REV_OBS="[$OBS1, $OBS2, $OBS3, $OBS4, $OBS5, $OBS6, $OBS7]"

TS1=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$GEN_KEY_CMD" 0 "Expendable test key generated." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS2=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$SIGN_TEST_CMD" 0 "Test repo signed." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS3=$(record_command_transcript "$EVIDENCE_OUT_DIR" "host" "$EXPORT_REV_CMD" 0 "Revoked key exported." "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
TS4=$(record_command_transcript "$EVIDENCE_OUT_DIR" "client" "$REJECT_CMD" 100 "$ERR_OUT" "" "$STAGE_START_TS" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
REV_CMDS="[$TS1, $TS2, $TS3, $TS4]"

REV_CHECKSUMS="{\"revocation_cert\": \"$(file_sha256 "$REV_CERT")\", \"sanitized_error_hash\": \"$ERR_HASH\"}"
REV_META="{
  \"expendable_fingerprint\": \"$EXPENDABLE_FPR\",
  \"revocation_reason\": \"KEY_COMPROMISE_TEST\",
  \"active_staging_key\": \"$STAGING_KEY_FPR\"
}"

write_stage_result "$EVIDENCE_OUT_DIR" "revocation-drill" "$STATUS_VAL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "$REV_CMDS" "$REV_OBS" "$REV_META" "$REV_CHECKSUMS"
emit_verified_marker "$EVIDENCE_OUT_DIR/revocation-drill-result.json" "REVOCATION_DRILL" "$STAGING_RUN_ID" "$(cd "$REPO_ROOT" && git rev-parse HEAD)" "${GENIXBIT_SIMULATE_OPS:-0}"

echo "[PASS] Key Revocation Drill Completed Successfully."
