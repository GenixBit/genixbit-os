# GenixBit OS Package Signing Policy

## Non-Negotiable Rules

1. **No Private Keys in Git**: Secret keys must never be committed to repository branches or stored in source archives.
2. **No Private Keys in CI**: GitHub Actions workflows must never hold production private signing keys.
3. **No Unsigned Production Repository Metadata**: No repository channel index (`InRelease`, `Release.gpg`) may be published to `resolute-stable` without valid GPG signatures.
4. **Mandatory Passphrase Protection**: `%no-protection` is strictly prohibited for production keys. Secret keys must be passphrase-protected or hardware-token-backed.

## Standard Approved Cryptographic Profile

- **Master Key Algorithm**: RSA 4096-bit (`cert` usage)
- **Master Key Expiry**: 2 years (`2y`)
- **Subkey Algorithm**: RSA 4096-bit (`sign` usage)
- **Subkey Expiry**: 1 year (`1y`)
- **Key Rotation Window**: 30 days prior to expiration
- **Digest Algorithm**: SHA-512 / SHA-256 (MD5 and SHA-1 signatures are prohibited)

## Standard APT Authentication Model

APT security relies on signed repository metadata (`InRelease` or `Release` + `Release.gpg`). Packages inside the repository are verified through cryptographic hash checksums (`SHA-256`, `SHA-512`) embedded within the signed index files.

## Operator Approval Requirements

- **Alpha Channel**: Requires successful automated linting and unit checks.
- **Testing Channel**: Requires passing disposable container package lifecycle tests.
- **Stable Channel**: Requires complete candidate ISO release validation, two independent maintainer sign-offs, fingerprint verification, and private audit log registration.
