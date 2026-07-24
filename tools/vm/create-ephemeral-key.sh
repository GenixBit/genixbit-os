#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generates an ephemeral SSH keypair for guest VM authentication.

set -Eeuo pipefail
IFS=$'\n\t'

VM_ID=""
STATE_DIR=""

fail() {
    printf '[FAIL] create-ephemeral-key.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --vm-id)
            (($# >= 2)) || fail '--vm-id requires a value.'
            VM_ID=$2
            shift 2
            ;;
        --state-dir)
            (($# >= 2)) || fail '--state-dir requires a path.'
            STATE_DIR=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$VM_ID" ]] || fail '--vm-id is required.'
[[ -n "$STATE_DIR" ]] || fail '--state-dir is required.'

KEY_DIR="${STATE_DIR}/credentials/${VM_ID}"
mkdir -p "$KEY_DIR"
chmod 0700 "$KEY_DIR"

PRIV_KEY="${KEY_DIR}/id_ed25519"
PUB_KEY="${KEY_DIR}/id_ed25519.pub"

if [[ ! -f "$PRIV_KEY" ]]; then
    ssh-keygen -t ed25519 -N '' -C "genixbit-release-gate-${VM_ID}" -f "$PRIV_KEY" >/dev/null 2>&1
    chmod 0600 "$PRIV_KEY"
    chmod 0644 "$PUB_KEY"
fi

FINGERPRINT=$(ssh-keygen -lf "$PUB_KEY" | awk '{print $2}')

cat <<EOF
{
  "vm_id": "$VM_ID",
  "private_key_path": "$PRIV_KEY",
  "public_key_path": "$PUB_KEY",
  "public_key_content": "$(cat "$PUB_KEY")",
  "fingerprint": "$FINGERPRINT"
}
EOF
exit 0
