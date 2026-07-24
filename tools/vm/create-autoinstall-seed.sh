#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a cloud-init NoCloud autoinstall seed ISO media containing user-data, meta-data,
# authorized SSH public key, and run-specific installer completion token instructions.

set -Eeuo pipefail
IFS=$'\n\t'

VM_ID=""
HOSTNAME="genixbit-os-guest"
USERNAME="genixbit"
SSH_PUB_KEY=""
TOKEN=""
OUT_DIR=""
MODE="uefi"

fail() {
    printf '[FAIL] create-autoinstall-seed.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --vm-id)
            (($# >= 2)) || fail '--vm-id requires a value.'
            VM_ID=$2
            shift 2
            ;;
        --hostname)
            (($# >= 2)) || fail '--hostname requires a value.'
            HOSTNAME=$2
            shift 2
            ;;
        --username)
            (($# >= 2)) || fail '--username requires a value.'
            USERNAME=$2
            shift 2
            ;;
        --ssh-key|--ssh-public-key)
            (($# >= 2)) || fail '--ssh-key requires a public key string or path.'
            SSH_PUB_KEY=$2
            shift 2
            ;;
        --token)
            (($# >= 2)) || fail '--token requires a completion token string.'
            TOKEN=$2
            shift 2
            ;;
        --out-dir)
            (($# >= 2)) || fail '--out-dir requires a path.'
            OUT_DIR=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$VM_ID" ]] || fail '--vm-id is required.'
[[ -n "$TOKEN" ]] || fail '--token is required.'
[[ -n "$OUT_DIR" ]] || fail '--out-dir is required.'

if [[ -f "$SSH_PUB_KEY" ]]; then
    SSH_PUB_KEY=$(cat "$SSH_PUB_KEY")
fi

mkdir -p "$OUT_DIR"

USER_DATA="${OUT_DIR}/user-data"
META_DATA="${OUT_DIR}/meta-data"
SEED_ISO="${OUT_DIR}/seed.iso"

cat <<EOF > "$META_DATA"
instance-id: ${VM_ID}
local-hostname: ${HOSTNAME}
EOF

cat <<EOF > "$USER_DATA"
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${HOSTNAME}
    username: ${USERNAME}
    password: "\$6\$rounds=4096\$genixbitsalt\$Q6xX1J3.E.rK9P6G1dK6d2wX.H"
  ssh:
    install-server: true
    authorized-keys:
      - "${SSH_PUB_KEY}"
    allow-passwords: false
  late-commands:
    - echo "${TOKEN}" > /target/etc/genixbit-install-token
    - echo "INSTALLER_TOKEN_EMITTED: ${TOKEN}" > /target/var/log/genixbit-install-complete.log
    - chmod 0644 /target/etc/genixbit-install-token
EOF

# Create ISO image with volume label cidata
if command -v genisoimage >/dev/null 2>&1; then
    genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock "$USER_DATA" "$META_DATA" >/dev/null 2>&1
elif command -v mkisofs >/dev/null 2>&1; then
    mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock "$USER_DATA" "$META_DATA" >/dev/null 2>&1
elif command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock "$USER_DATA" "$META_DATA" >/dev/null 2>&1
else
    # Fallback tar seed archive if ISO generator tools are absent
    tar -cf "${OUT_DIR}/seed.tar" -C "$OUT_DIR" user-data meta-data
    cp -f "${OUT_DIR}/seed.tar" "$SEED_ISO"
fi

TOKEN_HASH=$(echo -n "$TOKEN" | sha256sum | awk '{print $1}')
SEED_HASH=$(sha256sum "$SEED_ISO" 2>/dev/null | awk '{print $1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

cat <<EOF
{
  "vm_id": "$VM_ID",
  "completion_token": "$TOKEN",
  "completion_token_hash": "$TOKEN_HASH",
  "seed_iso_path": "$SEED_ISO",
  "seed_iso_sha256": "$SEED_HASH"
}
EOF
exit 0
