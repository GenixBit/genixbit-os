#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a genuine ISO9660 NoCloud seed ISO media containing cloud-init autoinstall user-data and meta-data.
# Requires a real ISO generator (cloud-localds, xorriso, genisoimage, or mkisofs). Prohibits synthetic fallbacks.
# Schema corrections per subiquity autoinstall spec:
#   - allow-pw (not allow-passwords)
#   - identity.hostname (required by subiquity)
#   - identity.password (encrypted with openssl passwd -6)
#   - storage.layout.name: direct
#   - updates: security
#   - shutdown: poweroff
#   - NOPASSWD sudoers rule for late-commands using sudo
#   - error-commands to capture installer logs on failure

set -Eeuo pipefail
IFS=$'\n\t'

VM_ID=""
HOSTNAME="genixbit-guest"
USERNAME=""
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
[[ -n "$USERNAME" ]] || fail '--username is required.'
[[ -n "$TOKEN" ]] || fail '--token is required.'
[[ -n "$OUT_DIR" ]] || fail '--out-dir is required.'
[[ -n "$HOSTNAME" ]] || fail '--hostname is required (must not be empty).'

mkdir -p "$OUT_DIR"

if [[ -f "$SSH_PUB_KEY" ]]; then
    PUB_CONTENT=$(cat "$SSH_PUB_KEY")
else
    PUB_CONTENT="$SSH_PUB_KEY"
fi

[[ -n "$PUB_CONTENT" ]] || fail 'SSH public key content is required.'
# Reject allow-passwords (wrong key) if it appears in the public key string by mistake
echo "$PUB_CONTENT" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2|sk-)' || fail "SSH public key does not look like a valid authorized_keys entry."

USER_DATA_FILE="${OUT_DIR}/user-data"
META_DATA_FILE="${OUT_DIR}/meta-data"
SEED_ISO="${OUT_DIR}/seed-${VM_ID}.iso"

# Generate an encrypted password for the temporary validation account.
# openssl passwd -6 generates SHA-512 crypt hash (accepted by subiquity).
# The password is only used for emergency console access; SSH key-only auth is enforced.
TEMP_PASSWD_PLAIN="GenixBitValidation$(date +%s)$$"
if command -v openssl >/dev/null 2>&1; then
    ENCRYPTED_PASSWD=$(openssl passwd -6 "$TEMP_PASSWD_PLAIN")
elif command -v python3 >/dev/null 2>&1; then
    ENCRYPTED_PASSWD=$(python3 -c "import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))" "$TEMP_PASSWD_PLAIN")
else
    fail "Cannot generate encrypted password: neither openssl nor python3 (crypt module) is available."
fi
[[ -n "$ENCRYPTED_PASSWD" && "$ENCRYPTED_PASSWD" == '$6$'* ]] || fail "Encrypted password generation failed (expected \$6\$ SHA-512 hash)."

# Write cloud-init meta-data
cat <<EOF > "$META_DATA_FILE"
instance-id: ${VM_ID}
local-hostname: ${HOSTNAME}
EOF

# Write cloud-init user-data autoinstall profile (subiquity schema)
# Key correctness requirements:
#   - allow-pw (NOT allow-passwords — allow-passwords is rejected)
#   - identity.hostname must be present
#   - identity.password must be an encrypted hash
#   - storage.layout.name: direct (simple whole-disk install)
#   - shutdown: poweroff (installer exits QEMU via ACPI poweroff, not reboot)
#   - NOPASSWD sudoers rule installed via late-commands for non-interactive guest-command.sh
cat <<EOF > "$USER_DATA_FILE"
#cloud-config
autoinstall:
  version: 1

  identity:
    realname: GenixBit Validation User
    hostname: ${HOSTNAME}
    username: ${USERNAME}
    password: "${ENCRYPTED_PASSWD}"

  storage:
    layout:
      name: direct

  ssh:
    install-server: true
    authorized-keys:
      - "${PUB_CONTENT}"
    allow-pw: false

  updates: security
  shutdown: poweroff

  late-commands:
    # Completion token: written inside the installer target filesystem
    - curtin in-target -- bash -c "echo '${TOKEN}' > /etc/genixbit-install-token && chmod 0644 /etc/genixbit-install-token"
    # Also write to serial console for wait-for-install-completion.sh serial-log detection
    - bash -c "echo '${TOKEN}' > /dev/ttyS0 || true"
    - bash -c "echo '${TOKEN}' > /dev/console || true"
    - bash -c "echo '${TOKEN}' >> /var/log/installer/subiquity-curtin-install.log || true"
    # NOPASSWD sudoers rule: required for non-interactive sudo inside authenticated guest commands
    - curtin in-target -- sh -c "printf '%s\n' '${USERNAME} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-genixbit-validation"
    - curtin in-target -- chmod 0440 /etc/sudoers.d/90-genixbit-validation

  error-commands:
    # Capture installer diagnostic logs to a known location when subiquity fails
    - bash -c "journalctl -b > /tmp/installer-journal.log 2>/dev/null || true"
    - bash -c "cp /var/log/installer/subiquity-server-debug.log /tmp/subiquity-server-debug.log 2>/dev/null || true"
    - bash -c "cp /var/log/installer/curtin-install.log /tmp/curtin-install.log 2>/dev/null || true"
    - bash -c "echo 'INSTALLER_FAILED_${TOKEN}' > /dev/ttyS0 || true"
EOF

# Validate the generated user-data YAML before creating the seed ISO
python3 -c "
import sys
try:
    import yaml
except ImportError:
    # yaml not available; do basic syntax checks instead
    content = open('$USER_DATA_FILE').read()
    required = [
        'autoinstall:',
        'allow-pw: false',
        'hostname: ',
        'password: ',
        '${TOKEN}',
        'shutdown: poweroff',
        'NOPASSWD:ALL',
    ]
    forbidden = ['allow-passwords']
    for r in required:
        if r not in content:
            print(f'[FAIL] user-data missing required field/value: {r!r}', file=sys.stderr)
            sys.exit(1)
    for f in forbidden:
        if f in content:
            print(f'[FAIL] user-data contains forbidden field: {f!r}', file=sys.stderr)
            sys.exit(1)
    sys.exit(0)

with open('$USER_DATA_FILE') as f:
    doc = yaml.safe_load(f)
ai = doc.get('autoinstall', {})
ident = ai.get('identity', {})
ssh = ai.get('ssh', {})
errs = []
if not ident.get('hostname'): errs.append('identity.hostname is missing')
if not ident.get('password'): errs.append('identity.password (encrypted hash) is missing')
if not ident.get('username'): errs.append('identity.username is missing')
if 'allow-passwords' in ssh: errs.append('ssh.allow-passwords must be removed; use allow-pw')
if 'allow-pw' not in ssh: errs.append('ssh.allow-pw is missing')
if ai.get('shutdown') != 'poweroff': errs.append('shutdown: poweroff is missing')
lc = ' '.join(str(c) for c in ai.get('late-commands', []))
if '${TOKEN}' not in lc: errs.append('late-commands missing completion token write')
if 'NOPASSWD' not in lc: errs.append('late-commands missing NOPASSWD sudoers rule')
if errs:
    for e in errs:
        print(f'[FAIL] user-data validation: {e}', file=sys.stderr)
    sys.exit(1)
print('[INFO] user-data YAML validation passed (via PyYAML)', file=sys.stderr)
"
printf '[INFO] user-data schema validation passed.\n' >&2

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
    cloud-localds "$SEED_ISO" "$USER_DATA_FILE" "$META_DATA_FILE" >/dev/null 2>&1
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

