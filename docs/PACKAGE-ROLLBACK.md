# GenixBit OS Package Rollback Policy

## Rollback Mechanisms

If a regression is identified in a published package in `resolute-stable`:

1. **Manifest Rollback**:
   - Revert the `Packages` and `InRelease` indices to reference the previous known-good `.deb` file version in `pool/`.
   - Re-sign `InRelease` and update public CDN cache.

2. **Epoch / Emergency Upgrade Rollback**:
   - If clients have already fetched the problematic version, issue a new build with incremented epoch (`1:<version>`) containing the reverted codebase to force automatic APT upgrades.
