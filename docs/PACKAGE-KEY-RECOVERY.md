# GenixBit OS Key Recovery & Backup Policy

## Emergency Key Recovery Procedure

This policy governs the physical and cryptographic recovery of GenixBit OS archive signing keys in the event of hardware failure, disaster, or maintainer unavailability.

## Encrypted Backup Requirements

1. **Hardware Media**: Primary secret keys are backed up onto at least two passphrase-protected, LUKS-encrypted USB hardware tokens (Token Alpha and Token Beta).
2. **Geographic Separation**:
   - Token Alpha is stored in a secure fireproof vault at Primary Operations Center (Location A).
   - Token Beta is stored in a secure vault at Secondary Operations Center (Location B).
3. **Passphrase Secret Sharing**: Encryption passphrases for backup tokens use a 2-of-3 threshold secret sharing scheme among authorized GenixBit Maintainers.

## Recovery Ceremony & Dual Approval

1. A minimum of two authorized maintainers must meet in person at Location A or Location B.
2. Verify token integrity and hardware hashes against published recovery manifests.
3. Decrypt LUKS volume on an isolated air-gapped machine running clean booted RAM OS.
4. Import secret keys to replacement hardware tokens (YubiKey / HSM).
5. Verify key fingerprint against published release configuration.
6. Record all recovery steps in the private operations audit log.
