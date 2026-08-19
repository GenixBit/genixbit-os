# GenixBit OS — Update System & Release Channels (GenixUpdate)

## 1. Release Channels & Policies
GenixBit OS supports 4 official release tiers:

1. **LTS (Long Term Support)**: Enterprise stability with guaranteed 5-year security maintenance.
2. **Stable**: Recommended for daily workstation use with monthly feature updates.
3. **Beta**: Early preview for developers and testing teams.
4. **Nightly**: Continuous integration builds directly from `main`.

---

## 2. Update Integrity & Atomic Staging
- **Dual APT & GBX Channels**: System packages updated via signed APT repositories (`packages.os.genixbit.com`), user applications via `.gbx` delta updates.
- **Fail-Closed Verification**: Updates require valid GPG/Ed25519 signatures and SHA-256 hash validation before execution.
- **Automatic Rollback**: If health checks fail post-update, system automatically reverts to previous snapshot.
