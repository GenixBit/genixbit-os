# GenixBit OS Package Staging Evidence Policy

This document defines the strict evidence integrity requirements for GenixBit OS Package Staging verification.

---

## 1. Core Evidence Rule

A **`PASS`** status marker or stage evidence record may be generated **only after**:
1. The corresponding stage command executed;
2. The command returned zero (success exit code);
3. Expected output state was independently verified by assertion;
4. A machine-readable, checksummed stage-result record was created;
5. The result record passed JSON schema validation and checksum verification;
6. The evidence collector verified that all required stage-result records exist and match the current `STAGING_RUN_ID` and Git `source_commit`.

**Unconditional, simulated, or hardcoded PASS statuses in production operational scripts are strictly prohibited.**

---

## 2. Required Stage Results

Every staging run must generate twelve separate, machine-readable stage-result JSON records:

| Stage Name | Result File Name | Verification Criteria |
| :--- | :--- | :--- |
| **repository_publication** | `repository-publication-result.json` | Atomic symlink switch to `/var/srv/genixbit-repository/releases/<release-id>/` verified. |
| **https** | `https-validation-result.json` | TLS handshake, cert SAN, CA chain, and `https://` endpoint verified. |
| **apt_update** | `apt-update-result.json` | `apt-get update` against `InRelease` returned 0 without trust errors. |
| **install** | `install-result.json` | Package `1.0.0` installed and installed version verified via `dpkg-query`. |
| **upgrade** | `upgrade-result.json` | Package `1.0.1` upgraded via APT and verified via `dpkg-query` & `apt-get check`. |
| **promotion** | `promotion-result.json` | Package promoted to `resolute-testing`, signed, and client policy verified. |
| **snapshot** | `snapshot-result.json` | Snapshot created, manifest verified, package/index checksums matched. |
| **rollback** | `rollback-result.json` | Restored snapshot published, signed, and client policy matched. |
| **tamper_rejection** | `tamper-result.json` | Tampered metadata rejected by client APT with explicit trust failure. |
| **recovery_drill** | `recovery-result.json` | Signing key recovered from encrypted backup into fresh GNUPGHOME. |
| **revocation_drill** | `revocation-result.json` | Revoked key published, and client APT rejected metadata signed by revoked key. |
| **cleanup** | `cleanup-result.json` | Saved destroy plan executed and run-specific resources verified absent. |

---

## 3. Mandatory Stage Record Schema

Every stage-result record MUST contain:
- `schema_version`: `"1.0.0"`
- `staging_run_id`: Matching active run ID
- `source_commit`: Matching Git HEAD commit SHA (40 hex chars)
- `stage`: Stage identifier string
- `started_at`: ISO 8601 UTC timestamp
- `completed_at`: ISO 8601 UTC timestamp
- `status`: `"PASS"` (or `"SIMULATED"` in unit test mode)
- `command_summary`: Execution command string
- `verified_conditions`: Array of verified assertion strings
- `public_metadata`: Non-sensitive key/cert fingerprints
- `artifact_checksums`: Map of filenames to SHA-256 hashes
- `result_sha256`: SHA-256 hash of record fields

---

## 4. Forbidden Data Fields

Under NO circumstances may any evidence file contain:
- Private keys (`.pem`, `.key`, `.sec`, OpenPGP secret packets)
- Key passphrases or authorization tokens
- Raw Terraform state files
- SSH private keys
- GCP Secret Manager secret values
- Personal usernames or billing account numbers
