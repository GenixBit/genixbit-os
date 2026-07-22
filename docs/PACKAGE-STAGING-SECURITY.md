# GenixBit OS Package Staging Security & Key Policy

This document details the security controls, signing key lifecycle, access boundaries, and threat model for the **GenixBit OS Package Staging Infrastructure**.

---

## 1. Security Principles

> [!IMPORTANT]
> **Production Key Separation**: The GenixBit OS production archive root key MUST NEVER be generated during staging exercises. Staging uses an independent, short-lived **GenixBit STAGING ONLY Repository Signing Key**.

1. **No Public SSH**: Compute instances do not have external IP addresses or open public SSH ports (`0.0.0.0/0`).
2. **Access Control**: Administrative SSH access is routed strictly through **Google Cloud IAP** (Identity-Aware Proxy).
3. **No Private Key In Git**: Signing keys, passphrases, and secret credentials must never be committed to Git or uploaded to GitHub Actions secret storage.
4. **Fail-Closed Verification**: Client configurations MUST NOT use `trusted=yes`, `allow-insecure=yes`, or `allow-unauthenticated`.
5. **No Production Impact**: Upstream AnduinOS package sources (`packages.anduinos.com`) remain active in system build scripts until production repository migration is fully verified.

---

## 2. Staging Signing Key Requirements

| Attribute | Specification |
| :--- | :--- |
| **Key Identification** | `GenixBit STAGING ONLY Repository Signing Key` |
| **Key Type** | RSA 2048-bit or Ed25519 |
| **Expiration** | Short-lived (30 to 90 days) |
| **Passphrase** | Required (strong random passphrase) |
| **Storage** | Encrypted GCP Secret Manager / Vault (never committed) |
| **Public Keyring** | Installed in `/usr/share/keyrings/genixbit-os-archive-keyring.pgp` |
| **Revocation Certificate** | Generated upon creation and stored in backup vault |
| **Lifecycle Deletion** | Revoked or destroyed immediately following staging exercises |

---

## 3. Staging Key Generation Procedure

```bash
# 1. Prepare ephemeral keygen parameters
cat <<EOF > /tmp/staging_key.conf
Key-Type: RSA
Key-Length: 2048
Key-Usage: sign,cert
Name-Real: GenixBit STAGING ONLY Repository Signing Key
Name-Email: staging-only@genixbit.com
Expire-Date: 60d
%no-protection
EOF

# 2. Generate staging key pair in isolated temp directory
export GNUPGHOME=$(mktemp -d)
chmod 700 "$GNUPGHOME"
gpg --batch --generate-key /tmp/staging_key.conf

# 3. Export public key and revocation certificate
STAGING_FPR=$(gpg --list-secret-keys --with-colons "staging-only@genixbit.com" | grep fpr | head -n1 | cut -d':' -f10)
gpg --export "$STAGING_FPR" > /tmp/genixbit-os-staging-keyring.gpg
gpg --gen-revoke "$STAGING_FPR" > /tmp/genixbit-os-staging-keyring.revoke
```

---

## 4. Tamper Rejection & Negative Security Suite

The staging repository tools validate the rejection of:

- Tampered `.deb` binary archives (SHA-256 hash mismatch).
- Tampered `Packages` or `Packages.xz` index files.
- Modified `Release` or `InRelease` metadata.
- Signatures created by unknown or expired GPG keys.
- Mismatched fingerprint expectations.
- Path traversal or symlink escape attempts outside allowed repository roots.
- Direct unauthorized channel promotions (e.g. `resolute-alpha` directly to `resolute-stable`).
