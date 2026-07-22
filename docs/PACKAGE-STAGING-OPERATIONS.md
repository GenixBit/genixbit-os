# GenixBit OS Package Staging Operations & Lifecycle Procedures

This document records administrative workflows for package publication, promotion, snapshot management, rollback, key recovery, and key revocation in the **GenixBit OS Package Staging Environment**.

---

## 1. Package Publication Flow

1. **Build Packages**: Compile `.deb` packages with proper `DEBIAN/control` metadata.
2. **Add to Staging Pool**: Place deb files in `$REPO/pool/main/<p>/<pkg>/`.
3. **Index Generation**: Execute `tools/repository/build-package-index.sh --repo-dir $REPO --channel resolute-alpha`.
4. **Sign Release Metadata**: Execute `tools/repository/sign-release-metadata.sh --repo-dir $REPO --channel resolute-alpha --signing-key-fingerprint $FPR`.
5. **Sync Metadata**: Atomic update of dists metadata files (`Packages`, `Release`, `InRelease`).

---

## 2. Channel Promotion Workflow

```bash
# 1. Promote verified package from resolute-alpha to resolute-testing
bash tools/repository/promote-package.sh \
  --repo-dir /path/to/staging/repo \
  --package genixbit-repository-fixture \
  --version 1.0.1 \
  --from-channel resolute-alpha \
  --to-channel resolute-testing \
  --promoter "qa-lead@genixbit.com" \
  --reviewer "sec-lead@genixbit.com"

# 2. Re-sign target testing channel metadata
bash tools/repository/sign-release-metadata.sh \
  --repo-dir /path/to/staging/repo \
  --channel resolute-testing \
  --signing-key-fingerprint $STAGING_FPR
```

---

## 3. Snapshot Creation & Rollback Workflow

```bash
# 1. Create immutable snapshot of resolute-testing channel
bash tools/repository/create-snapshot.sh \
  --repo-dir /path/to/staging/repo \
  --channel resolute-testing

# 2. Rollback channel to earlier snapshot if defect detected
bash tools/repository/rollback-snapshot.sh \
  --repo-dir /path/to/staging/repo \
  --channel resolute-testing \
  --snapshot-id snap-resolute-testing-20260722-120000

# 3. Re-sign restored metadata
bash tools/repository/sign-release-metadata.sh \
  --repo-dir /path/to/staging/repo \
  --channel resolute-testing \
  --signing-key-fingerprint $STAGING_FPR
```

---

## 4. Key Recovery & Revocation Drills

### Key Recovery Drill
1. Export GPG private key backup to encrypted offline storage.
2. Simulate active keyring corruption by purging `$GNUPGHOME`.
3. Import GPG private key backup into isolated environment.
4. Verify fingerprint matches expected staging fingerprint.
5. Re-sign test `Release` file and confirm client signature verification passes cleanly.

### Key Revocation Drill
1. Import pre-generated GPG revocation certificate.
2. Publish updated public keyring containing revocation signature.
3. Validate client `apt-get update` rejects repository signed by revoked key.
