#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a genuine ISO9660 NoCloud seed ISO media containing cloud-init autoinstall user-data and meta-data.
# Requires a real ISO generator (cloud-localds, xorriso, genisoimage, or mkisofs). Prohibits synthetic fallbacks.

set -Eeuo pipefail
IFS=$'\n\t'

VM_ID=""
HOSTNAME="genixbit-guest"
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
            (($# >= 2)) || fail '--hostname requires a string.'
            HOSTNAME=$2
            shift 2
            ;;
        --username)
            (($# >= 2)) || fail '--username requires a string.'
            USERNAME=$2
            shift 2
            ;;
        --ssh-key)
            (($# >= 2)) || fail '--ssh-key requires a public key file or string.'
            SSH_PUB_KEY=$2
            shift 2
            ;;
        --token)
            (($# >= 2)) || fail '--token requires a string.'
            TOKEN=$2
            shift 2
            ;;
        --out-dir)
            (($# >= 2)) || fail '--out-dir requires a path.'
            OUT_DIR=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires uefi or bios.'
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

mkdir -p "$OUT_DIR"

if [[ -f "$SSH_PUB_KEY" ]]; then
    PUB_CONTENT=$(cat "$SSH_PUB_KEY")
else
    PUB_CONTENT="$SSH_PUB_KEY"
fi

[[ -n "$PUB_CONTENT" ]] || fail 'SSH public key content is required.'

USER_DATA_FILE="${OUT_DIR}/user-data"
META_DATA_FILE="${OUT_DIR}/meta-data"
SEED_ISO="${OUT_DIR}/seed-${VM_ID}.iso"

# Write cloud-init meta-data
cat <<EOF > "$META_DATA_FILE"
instance-id: ${VM_ID}
local-hostname: ${HOSTNAME}
EOF

# Write cloud-init user-data autoinstall profile
cat <<EOF > "$USER_DATA_FILE"
#cloud-config
autoinstall:
  version: 1
  identity:
    realname: GenixBit User
    username: ${USERNAME}
  ssh:
    install-server: true
    authorized-keys:
      - "${PUB_CONTENT}"
    allow-passwords: false
  late-commands:
    - curtin in-target -- bash -c "echo '${TOKEN}' > /etc/genixbit-install-token && chmod 0644 /etc/genixbit-install-token"
    - bash -c "echo '${TOKEN}' > /dev/ttyS0 || true"
    - bash -c "echo '${TOKEN}' > /dev/console || true"
    - bash -c "echo '${TOKEN}' >> /var/log/installer/subiquity-curtin-install.log || true"
    - bash -c "echo '${TOKEN}' >> /var/log/syslog || true"
EOF

# Find ISO9660 creation tool (FAIL CLOSED - NO synthetic Python or tar fallbacks!)
ISO_TOOL=""
if command -v cloud-localds >/dev/null 2>&1; then
    ISO_TOOL="cloud-localds"
elif command -v xorriso >/dev/null 2>&1; then
    ISO_TOOL="xorriso"
elif command -v genisoimage >/dev/null 2>&1; then
    ISO_TOOL="genisoimage"
elif command -v mkisofs >/dev/null 2>&1; then
    ISO_TOOL="mkisofs"
else
    fail "No valid ISO9660 generator found (cloud-localds, xorriso, genisoimage, or mkisofs required). Synthetic fallbacks are prohibited!"
fi

if [[ "$ISO_TOOL" == "cloud-localds" ]]; then
    cloud-localds "$SEED_ISO" "$USER_DATA_FILE" "$META_DATA_FILE"
elif [[ "$ISO_TOOL" == "xorriso" ]]; then
    xorriso -as mkisofs -V "cidata" -J -r -o "$SEED_ISO" "$USER_DATA_FILE" "$META_DATA_FILE" >/dev/null 2>&1
else
    "$ISO_TOOL" -output "$SEED_ISO" -volid "cidata" -joliet -rock "$USER_DATA_FILE" "$META_DATA_FILE" >/dev/null 2>&1
fi

[[ -f "$SEED_ISO" && -s "$SEED_ISO" ]] || fail "Seed ISO generation failed to create non-empty file at $SEED_ISO"

# Verify volume label or content
if command -v isoinfo >/dev/null 2>&1; then
    VOL_NAME=$(isoinfo -d -i "$SEED_ISO" 2>/dev/null | grep "Volume id:" | awk '{print $3}' || echo "")
    if [[ -n "$VOL_NAME" && "$VOL_NAME" != "cidata" ]]; then
        fail "Seed ISO volume label is '$VOL_NAME', expected 'cidata'"
    fi
fi

# Calculate SHA-256 and SHA-512 (FAIL CLOSED)
ISO_SHA256=$(sha256sum "$SEED_ISO" | awk '{print $1}')
ISO_SHA512=$(sha512sum "$SEED_ISO" | awk '{print $1}')

[[ -n "$ISO_SHA256" && "$ISO_SHA256" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]] || fail "Failed to compute valid non-empty SHA-256 for seed ISO."
[[ -n "$ISO_SHA512" ]] || fail "Failed to compute SHA-512 for seed ISO."

TOKEN_HASH=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')

python3 -c "
import json
print(json.dumps({
    'seed_iso_path': '$SEED_ISO',
    'seed_iso_sha256': '$ISO_SHA256',
    'seed_iso_sha512': '$ISO_SHA512',
    'completion_token_hash': '$TOKEN_HASH',
    'vm_id': '$VM_ID',
    'mode': '$MODE',
    'status': 'PASS'
}, indent=2))
"
exit 0
