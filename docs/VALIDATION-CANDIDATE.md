# GenixBit OS Validation Candidate

## Purpose

`main` is a moving development branch. A build cannot be described as validating “current main” when new commits land after the tested artifact is produced.

For each release-validation cycle, GenixBit must create a **frozen candidate branch** and record its exact commit before building the ISO.

For `0.1.0-alpha`, use:

```text
validation/0.1.0-alpha-candidate
```

The branch must point to one approved commit and must not receive additional commits during that validation cycle.

## Candidate Creation

After the validation-gate fixes are merged and `main` is approved:

```bash
git switch main
git pull origin main

git switch -c validation/0.1.0-alpha-candidate
git push -u origin validation/0.1.0-alpha-candidate
```

Record the exact candidate SHA:

```bash
CANDIDATE_SHA=$(git rev-parse HEAD)
printf '%s\n' "$CANDIDATE_SHA"
```

The operator must use that full 40-character SHA with:

```bash
tools/vm/verify-runtime.sh --expected-commit "$CANDIDATE_SHA"
```

## Immutability Rule

Do not force-push, rebase, merge, or add commits to the frozen candidate branch after validation starts.

When a build or runtime defect requires a source change:

1. fix it through a normal feature or fix branch;
2. merge the reviewed change into `main` after CI passes;
3. retire the previous candidate;
4. create a new candidate branch or versioned candidate name;
5. restart the affected build and runtime tests using the new SHA.

A suggested replacement naming pattern is:

```text
validation/0.1.0-alpha-candidate-2
validation/0.1.0-alpha-candidate-3
```

## Evidence Requirements

The private validation manifest must record:

- candidate branch;
- full candidate commit SHA;
- build-host release and architecture;
- ISO filename and exact byte size;
- SHA-256;
- checksum-file comparison;
- BIOS/UEFI metadata report;
- EFI fallback-path result;
- live BIOS result;
- live UEFI result;
- installer result;
- installed-system result;
- installed-system APT and package-health result;
- second same-commit build result;
- reproducibility comparison;
- cleanup status.

The public machine-readable summary is [`VALIDATION-STATUS.env`](VALIDATION-STATUS.env). Update it only from factual evidence. Keep ISO files, VM disks, raw logs, screenshots with private data, credentials, cloud identifiers, and private host details outside Git.

## Pull-Request Merge Gate

Candidate-validation pull requests use a branch beginning with `test/validate-` and a title beginning with `test: validate `.

Repository Quality runs:

```bash
bash tools/validation/check-release-evidence.sh --require-complete
```

For such a pull request to pass, every required release-gate field in `docs/VALIDATION-STATUS.env` must be `PASS`, including the overall release status. A blocked host attempt, a documentation-only update, a dry run, or an incomplete runtime cycle must use a non-validation title such as `test: record blocked candidate validation attempt` and must not be presented as completed validation.

## Status Rules

- A successful `verify-runtime.sh` run proves only the clean candidate build and VM preflight checks it actually performs.
- A QEMU dry run is not a boot test.
- A visible live desktop is required for live-session `PASS`.
- A completed installer and successful target-disk boot are required for installer `PASS`.
- Installed-system commands must be executed inside the installed system.
- A second clean build and documented comparison are required before reproducibility can be classified.
- The ISO must not be published while the release-validation status remains `PARTIAL`, `FAIL`, or `NOT_TESTED` for a release gate.
