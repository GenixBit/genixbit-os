# GenixBit OS Package Signing Policy

## Non-Negotiable Rules

1. **No Private Keys in Git**: Secret keys must never be committed to repository branches or stored in source archives.
2. **No Private Keys in CI**: GitHub Actions workflows must never hold production private signing keys.
3. **No Unsigned Production Releases**: No Debian package may be promoted to `resolute-stable` without valid GPG signatures.

## Key Cryptography Standards

- **Primary Algorithm**: RSA 4096-bit or Ed25519 (EdDSA).
- **Hash Function**: SHA-512 / SHA-256 (SHA-1 and MD5 signature algorithms are strictly prohibited).
- **Master Key Expiration**: 2 years from generation.
- **Subkey Expiration**: 12 months from issuance.

## Operator Approval Requirements

- **Alpha Channel**: Requires successful automated unit and lint tests.
- **Testing Channel**: Requires passing disposable container package lifecycle tests.
- **Stable Channel**: Requires complete candidate ISO release validation, two independent maintainer sign-offs, and clean audit validation.
