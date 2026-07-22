# GenixBit OS APT Signing Key Management Policy

## Overview

GenixBit OS uses OpenPGP signatures to verify the integrity and authenticity of Debian repository metadata (`InRelease`, `Release.gpg`) distributed via `packages.os.genixbit.com`.

Standard APT security relies on signed repository metadata (`InRelease` or `Release` + `Release.gpg`). Individual `.deb` package files are authenticated via cryptographic hash checksums (`SHA-256`, `SHA-512`) recorded directly inside the signed repository index files.

To maintain software supply-chain security, all primary signing keys are generated, stored, and managed in secure, air-gapped offline environments. No private signing keys are ever stored in GitHub repositories or CI/CD pipelines.

## Approved Cryptographic Profile

GenixBit OS uses a single, standardized, conservative OpenPGP profile for guaranteed compatibility across GnuPG and Ubuntu 26.04 APT:

- **Primary Master Key Algorithm**: RSA 4096-bit
- **Primary Master Key Usage**: Certification only (`cert`)
- **Primary Master Key Expiry**: 2 years (`2y`)
- **Subkey Algorithm**: RSA 4096-bit
- **Subkey Usage**: Signing only (`sign`)
- **Subkey Expiry**: 1 year (`1y`)
- **Key Rotation Window**: 30 days prior to subkey expiration

## Key Hierarchy Architecture

```text
┌─────────────────────────────────────────────────────────┐
│              Master Offline Certification Key           │
│        (RSA 4096-bit, Passphrase + Hardware Token)      │
└────────────────────────────┬────────────────────────────┘
                             │ (Issues Subkeys)
                             ▼
┌─────────────────────────────────────────────────────────┐
│            Repository Metadata Signing Subkey           │
│              (RSA 4096-bit, Signing Only)               │
└─────────────────────────────────────────────────────────┘
```

1. **Master Certification Key**: Used exclusively for certifying subkeys and issuing revocation certificates. Stored offline on passphrase-protected encrypted hardware tokens (e.g. YubiKey / HSM). Passphrases are mandatory.
2. **Repository Metadata Subkey**: Used by the repository builder to sign APT repository index files (`InRelease` / `Release`).

## Offline Key Generation Procedure

Execute the following commands on an isolated, air-gapped live system booted without network interfaces:

```bash
# 1. Set secure umask and GNUPGHOME
umask 077
export GNUPGHOME="$(mktemp -d /tmp/genixbit-gpg-XXXXXX)"

# 2. Generate Master Certification Key with mandatory passphrase protection
gpg --batch --full-generate-key <<EOF
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Name-Real: GenixBit OS Archive Automatic Signing Key
Name-Email: ftpmaster@genixbit.com
Expire-Date: 2y
EOF

# 3. Get Key ID & Fingerprint
KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "ftpmaster@genixbit.com" | grep sec | awk '{print $2}' | cut -d'/' -f2)
FINGERPRINT=$(gpg --list-secret-keys --with-colons "ftpmaster@genixbit.com" | grep fpr | head -n1 | cut -d':' -f10)

# 4. Generate RSA 4096 Signing Subkey
gpg --batch --quick-add-key "$FINGERPRINT" rsa4096 sign 1y

# 5. Generate Revocation Certificate
gpg --output "$GNUPGHOME/genixbit-archive-keyring-revocation.asc" --gen-revoke "$FINGERPRINT"

# 6. Export Public Key Minimal Block
gpg --armor --export "$FINGERPRINT" > "$GNUPGHOME/genixbit-os-archive-keyring.pgp"
```

## Backup & Recovery Requirements

1. **Encrypted Backups**: Primary secret keys must be exported to at least two separate, encrypted hardware tokens (LUKS-encrypted USB/YubiKey).
2. **Geographic Separation**: Backup tokens must be stored in separate physical security vaults in geographically distinct locations.
3. **Dual-Maintainer Sign-Off**: Decryption passphrases require 2-of-3 threshold maintainer authorization.
4. **Revocation Certificate**: The revocation certificate must be generated at key creation time and stored in a sealed physical vault.
5. **Private Audit Log**: All key ceremonies, rotations, and access logs are recorded in a physical, private audit log.
