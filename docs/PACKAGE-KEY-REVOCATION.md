# GenixBit OS Key Revocation Procedure

## Revocation Trigger Conditions

Immediate key revocation is mandatory under any of the following circumstances:
- Physical loss or theft of a signing token/smartcard;
- Suspected unauthorized access to an online repository signing passphrase;
- Cryptographic weakness discovered in active key algorithms;
- Departure of a maintainer with individual key access.

## Execution Steps

1. **Retrieve Pre-Generated Revocation Certificate**: Access the revocation certificate generated during the initial key ceremony.
2. **Publish Revocation**:
   ```bash
   gpg --import genixbit-archive-keyring-revocation.asc
   gpg --keyserver keyserver.ubuntu.com --send-keys $FINGERPRINT
   ```
3. **Emergency Keyring Update**:
   - Issue emergency `genixbit-os-archive-keyring` package update removing the compromised subkey and inserting the new active subkey.
   - Re-sign all `dists/` manifests with the new subkey.
4. **Private Audit Logging**: Record revocation event and dual-maintainer authorization in the private operations audit log.
5. **Notify Users**: Publish security advisory detailing key rotation and verification steps.
