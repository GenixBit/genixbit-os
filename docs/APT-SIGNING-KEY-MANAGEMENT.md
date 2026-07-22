# GenixBit OS APT Signing Key Management Policy

## Overview

GenixBit OS uses GPG signatures to verify the integrity and authenticity of Debian packages (`.deb`) and repository metadata (`InRelease`, `Release.gpg`) distributed via `packages.os.genixbit.com`.

To maintain software supply-chain security, all primary signing keys are generated, stored, and managed in secure, air-gapped offline environments. No private signing keys are ever stored in GitHub repositories or CI/CD pipelines.

## Key Hierarchy Architecture

```text
┌─────────────────────────────────────────────────────────┐
│              Master Offline Certification Key           │
│        (RSA 4096-bit / Ed25519, Offline/Air-gapped)     │
└────────────────────────────┬────────────────────────────┘
                             │ (Issues Subkeys)
        ┌────────────────────┴────────────────────┐
        ▼                                         ▼
┌───────────────────────────────┐ ┌───────────────────────────────┐
│     Release Signing Subkey    │ │   Repository Metadata Subkey  │
│   (RSA 4096-bit / Ed25519)    │ │   (RSA 4096-bit / Ed25519)    │
└───────────────────────────────┘ └───────────────────────────────┘
```

1. **Master Certification Key**: Used exclusively for certifying subkeys and issuing revocation certificates. Stored offline on encrypted hardware tokens (e.g. YubiKey / HSM).
2. **Release Signing Subkey**: Used to sign individual GenixBit Debian packages during official release builds.
3. **Repository Metadata Subkey**: Used by the automated staging repository builder to sign APT repository index files (`InRelease` / `Release`).

## Offline Key Generation Procedure

Execute the following commands on an isolated, air-gapped live system booted without network interfaces:

```bash
# 1. Set secure umask and GNUPGHOME
umask 077
export GNUPGHOME="$(mktemp -d /tmp/genixbit-gpg-XXXXXX)"

# 2. Generate Master Certification Key
gpg --batch --full-generate-key <<EOF
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Name-Real: GenixBit OS Archive Automatic Signing Key
Name-Email: ftpmaster@genixbit.com
Expire-Date: 2y
%no-protection
EOF

# 3. Get Key ID
KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "ftpmaster@genixbit.com" | grep sec | awk '{print $2}' | cut -d'/' -f2)

# 4. Generate Subkeys for Signing
gpg --batch --quick-add-key "$KEY_ID" rsa4096 sign 1y

# 5. Generate Revocation Certificate
gpg --output "$GNUPGHOME/genixbit-archive-keyring-revocation.asc" --gen-revoke "$KEY_ID"

# 6. Export Public Key
gpg --armor --export "$KEY_ID" > "$GNUPGHOME/genixbit-archive-keyring.gpg"
```

## Backup & Recovery Procedures

1. **Encrypted Storage**: Primary secret keys must be exported to two separate, physical hardware tokens (encrypted USB/YubiKey) stored in geographically distinct secure locations.
2. **Revocation Certificate**: The revocation certificate must be generated at key creation time and stored in a sealed physical vault.
3. **Emergency Key Revocation**: If a signing subkey is compromised:
   - Issue the revocation certificate to `packages.os.genixbit.com/genixbit-archive-keyring.gpg.revoked`;
   - Update `genixbit-os-archive-keyring` package with an emergency security update removing the compromised subkey;
   - Re-sign all valid repository manifests using a newly generated subkey certified by the offline master key.

## Key Expiration and Rotation Schedule

- **Subkey Expiration**: 12 months from issuance.
- **Rotation Window**: Subkeys are rotated annually 30 days before expiration.
- **Keyring Updates**: The `genixbit-os-archive-keyring` package is updated quarterly to ensure client systems maintain valid public verification keys without interruption.
