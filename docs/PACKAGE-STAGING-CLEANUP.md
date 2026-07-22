# GenixBit OS Package Staging Decommissioning & Cleanup Plan

This document outlines automated and manual cleanup procedures to ensure all temporary compute, storage, keys, evidence, and logs created during staging exercises are fully decommissioned.

---

## 1. Automated Resource Expiry

All GCP resources created by `infra/package-staging/` carry mandatory tracking labels:

```hcl
labels = {
  environment = "staging"
  disposable  = "true"
  expiry_days = "30"
}
```

- **Cloud Storage Evidence**: Objects in `genixbit-staging-evidence-*` automatically expire and purge after 30 days via bucket lifecycle rules.
- **Compute Instances**: Disposable instances carry `disposable = "true"` and are purged at the end of staging validation runs.

---

## 2. Infrastructure Teardown Command

To manually destroy all staging cloud resources:

```bash
cd infra/package-staging
tofu destroy || terraform destroy
```

---

## 3. Ephemeral Key Deletion

Following completion of staging validation:

1. Delete staging private key files from `$GNUPGHOME`.
2. Securely overwrite temporary GPG working directories (`shred -u` or `rm -rf`).
3. Revoke/delete temporary GCP Secret Manager secret versions.
