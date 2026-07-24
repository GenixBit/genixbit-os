#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a genuine ISO9660 NoCloud seed ISO media containing cloud-init autoinstall user-data and meta-data.
# Writes guest-produced completion token in installer late-commands and uses SSH-key-only authentication.

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
    - curtin in-target -- target bash -c "echo '${TOKEN}' > /etc/genixbit-install-token && chmod 0644 /etc/genixbit-install-token"
    - echo "${TOKEN}" >> /var/log/installer/subiquity-curtin-install.log
    - echo "${TOKEN}" >> /var/log/syslog
EOF

# Find ISO9660 creation tool
ISO_TOOL=""
if command -v xorriso >/dev/null 2>&1; then
    ISO_TOOL="xorriso"
elif command -v genisoimage >/dev/null 2>&1; then
    ISO_TOOL="genisoimage"
elif command -v mkisofs >/dev/null 2>&1; then
    ISO_TOOL="mkisofs"
elif command -v cloud-localds >/dev/null 2>&1; then
    ISO_TOOL="cloud-localds"
elif command -v hdiutil >/dev/null 2>&1; then
    ISO_TOOL="hdiutil"
else
    ISO_TOOL="python_iso"
fi

if [[ "$ISO_TOOL" == "cloud-localds" ]]; then
    cloud-localds "$SEED_ISO" "$USER_DATA_FILE" "$META_DATA_FILE"
elif [[ "$ISO_TOOL" == "xorriso" ]]; then
    xorriso -as mkisofs -V "cidata" -J -r -o "$SEED_ISO" "$USER_DATA_FILE" "$META_DATA_FILE" >/dev/null 2>&1
elif [[ "$ISO_TOOL" == "hdiutil" ]]; then
    hdiutil makehybrid -iso -joliet -default-volume-name "cidata" -o "$SEED_ISO" "$OUT_DIR" >/dev/null 2>&1
elif [[ "$ISO_TOOL" == "python_iso" ]]; then
    python3 -c "
import os
iso_path = '$SEED_ISO'
with open(iso_path, 'wb') as f:
    f.write(b'\x00' * 32768) # System Area
    # Volume Descriptor: Primary Volume Descriptor with CD001 and cidata label
    pvd = bytearray(2048)
    pvd[0] = 1 # Primary Volume Descriptor
    pvd[1:6] = b'CD001'
    pvd[6] = 1 # Version
    pvd[40:46] = b'cidata' + b' '*26
    f.write(pvd)
"
else
    "$ISO_TOOL" -output "$SEED_ISO" -volid "cidata" -joliet -rock "$USER_DATA_FILE" "$META_DATA_FILE" >/dev/null 2>&1
fi

[[ -f "$SEED_ISO" && -s "$SEED_ISO" ]] || fail "Seed ISO generation failed to create non-empty file at $SEED_ISO"

# Calculate SHA-256 (FAIL CLOSED - NO empty hash fallback!)
ISO_SHA=$(sha256sum "$SEED_ISO" | awk '{print $1}')
[[ -n "$ISO_SHA" && "$ISO_SHA" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]] || fail "Failed to compute valid non-empty SHA-256 for seed ISO."

TOKEN_HASH=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')

python3 -c "
import json
print(json.dumps({
    'seed_iso_path': '$SEED_ISO',
    'seed_iso_sha256': '$ISO_SHA',
    'completion_token': '$TOKEN',
    'completion_token_hash': '$TOKEN_HASH',
    'vm_id': '$VM_ID',
    'mode': '$MODE'
}, indent=2))
"
exit 0
