# GenixBit OS Package Staging Evidence & Anti-Fabrication Policy

## 1. Overview & Core Anti-Fabrication Mandate

This policy defines the strict, machine-verifiable requirements for evidence collection, command transcripts, and operational state verification in GenixBit OS package staging.

> [!IMPORTANT]
> **Anti-Fabrication Rule**: A `PASS` status marker MUST NEVER be printed or assigned unconditionally. Status markers (`STAGING_<STAGE>=PASS`) may ONLY be emitted after:
> 1. The underlying command executes on the target environment (or verified local test path).
> 2. The command returns a zero exit code (or expected non-zero code for negative tests).
> 3. Observed outputs match expected values exactly (`expected == actual`).
> 4. A stage-result JSON file (`<stage>-result.json`) is recorded with command transcripts and checksummed observations.
> 5. The stage-result file is verified against its `result_sha256` payload hash and schema.

---

## 2. Stage Result Manifest Model

Each of the **11 operational stages** must produce an immutable, checksummed `<stage>-result.json` file in `$EVIDENCE_OUT_DIR`:

1. `repository-publication-result.json`
2. `https-result.json`
3. `apt-update-result.json`
4. `install-result.json`
5. `upgrade-result.json`
6. `promotion-result.json`
7. `snapshot-result.json`
8. `rollback-result.json`
9. `tamper-rejection-result.json`
10. `recovery-drill-result.json`
11. `revocation-drill-result.json`

### Terminal Cleanup Record
In addition to the 11 operational validation stages, infrastructure teardown produces a separate mandatory terminal record:
- `cleanup-result.json`

Final run closure is `PASS` **only when** both the 11-stage operational validation manifest AND the cleanup terminal manifest pass.

---

## 3. Required Fields in Stage Result Records

Every `<stage>-result.json` object MUST contain:

- `schema_version`: `"1.0.0"`
- `staging_run_id`: Matching active `$STAGING_RUN_ID`
- `source_commit`: 40-character hex commit SHA
- `stage`: Stage identifier string
- `started_at` & `completed_at`: ISO 8601 UTC timestamps
- `status`: `"PASS"`, `"SIMULATED"`, or `"FAILED"`
- `executed_commands`: Array of command transcript summary objects
- `observations`: Non-empty array of observation objects
- `artifact_checksums`: Object mapping artifact paths/names to SHA-256 hex strings
- `public_metadata`: Object containing public metadata (strictly non-sensitive)
- `result_sha256`: SHA-256 hash of compact JSON payload (calculated without `result_sha256`)

---

## 4. Observation Structure & Verification Rules

Each object in `observations` MUST satisfy:

- `name`: Non-empty string; MUST NOT be a placeholder (`placeholder`, `dummy`, `todo`, `tbd`, `none`, `null`, `test_value`, `0000000000000000000000000000000000000000`).
- `expected` & `actual`: Must be non-empty, non-placeholder, and MUST match (`expected == actual`).
- `verification_command`: Non-empty command string used to make the observation; MUST NOT be a trivial command (`echo`, `true`, `:`, `exit 0`).
- `verification_exit_code`: Integer exit code.
- `observed_at`: ISO 8601 timestamp.
- `observer`: Host role (`host`, `client`, `verifier`, `operator`).
- `observation_sha256`: SHA-256 hash of `name:expected:actual:verification_command:verification_exit_code:observer`.

---

## 5. Command Transcript Integrity

Command execution helpers capture and redact command transcripts into `$EVIDENCE_OUT_DIR/transcripts/<cmd_id>.json`:
- Full stdout/stderr captured.
- PGP private keys, passphrases, tokens, and secrets redacted automatically.
- Unrecoverable secret exposure triggers immediate execution abort.
- Transcripts are referenced by SHA-256 in the `executed_commands` array.
- Transcripts are excluded from Git version control via `.gitignore`.

---

## 6. Simulation Mode Safeguards

When `GENIXBIT_SIMULATE_OPS=1` is set:
- Operations are executed in simulated test environments.
- Status is emitted as `STAGING_<STAGE>=SIMULATED`.
- Evidence manifests record `status: "SIMULATED"` and `overall_status: "OPERATIONS_IMPLEMENTED_NOT_DEPLOYED"`.
- Simulated manifests are strictly rejected during production evidence collection (`GENIXBIT_SIMULATE_OPS=0`).
