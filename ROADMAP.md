# GenixBit OS Development Roadmap

> [!NOTE]
> All milestones are provisional. A feature is complete only after implementation, documentation, direct testing, security review and GenixBit maintainer approval. File presence, package manifests, dry runs or configuration inspection must not be treated as proof of successful interactive runtime behavior.

## Phase 1 — `0.1.x`: Baseline Build and Release Validation *(Current Gate)*

### Repository and Historical Build Preparation

- [x] Preserve upstream history and GPL-3.0 licensing.
- [x] Establish GenixBit identity variables and repository governance.
- [x] Add repository-quality CI and baseline test documentation.
- [x] Confirm macOS ARM is unsuitable for the full ISO build.
- [x] Provision an Ubuntu 26.04 `resolute` `amd64` build machine for the historical build.
- [x] Run `make bootstrap` successfully for the historical build.
- [x] Complete the first historical ISO compilation from commit `2ed584c`.
- [x] Record the historical ISO filename, size and SHA-256.
- [x] Record historical hybrid BIOS/UEFI boot structures.
- [x] Add QEMU, host-readiness and candidate-preflight tooling.
- [x] Correct the host-readiness counter behavior under `set -e`.
- [x] Require a clean checkout and exact expected SHA in `verify-runtime.sh`.
- [x] Define the frozen candidate process in `docs/VALIDATION-CANDIDATE.md`.
- [x] Add `docs/VALIDATION-STATUS.env` as the machine-readable release record.
- [x] Enforce completed evidence for `test/validate-*` pull requests in Repository Quality CI.

The first ISO remains valid historical evidence. It is not the next release candidate because later commits changed the build pipeline and added GenixBit identity-package scaffolding.

### Frozen Candidate Build Gate

- [x] Create `validation/0.1.0-alpha-candidate-2` from the approved post-gate `main` commit.
- [x] Record its full 40-character SHA: `4888b05eda7528b1ff0c607b9799201999d61031`.
- [x] Keep the candidate branch immutable during validation. Do not add commits after validation starts.
- [x] Create evidence branch `test/validate-0.1.0-alpha-candidate-complete` from the frozen candidate SHA.
- [x] Record the first blocked attempt: macOS `arm64` failed host readiness and produced no candidate ISO.
- [x] Run `tools/vm/verify-runtime.sh --expected-commit 4888b05eda7528b1ff0c607b9799201999d61031` on Ubuntu 26.04 `resolute` amd64.
- [x] Perform a clean ISO build from the candidate SHA.
- [x] Record the candidate ISO filename, exact size and SHA-256.
- [x] Verify the generated checksum independently.
- [x] Inspect BIOS and UEFI boot metadata.
- [x] Verify `/isolinux/efiboot.img` contains `EFI/BOOT/BOOTX64.EFI`.
- [x] Retain the candidate artifact and private reports outside Git.
- [x] Use that one candidate artifact for every direct runtime test.

### Direct Runtime Validation Complete

- [x] Boot the candidate ISO through UEFI and reach the live desktop.
- [x] Boot the candidate ISO through Legacy BIOS and reach the live desktop.
- [x] Confirm the GRUB menu displays correctly.
- [x] Validate keyboard, locale, display, networking, DNS, audio, shutdown and restart.
- [x] Launch the installer interactively.
- [x] Complete installation to clean UEFI and BIOS virtual disks.
- [x] Confirm partitioning and target-disk bootloader installation.
- [x] Boot each installed system without the ISO.
- [x] Confirm account creation, login and desktop startup.
- [x] Run `sudo apt update` inside the installed system.
- [x] Check installed package health and critical boot logs.
- [x] Confirm GenixBit identity and record remaining upstream branding.
- [x] Confirm `genixbit-os-base-files` status remains PARTIAL / SCAFFOLDED.
- [x] Perform a second clean build from the same candidate SHA in a separate checkout.
- [x] Compare both candidate ISOs and document expected or nondeterministic differences.
- [x] Store non-sensitive summaries in `docs/TESTING.md` and update `docs/VALIDATION-STATUS.env`.

Phase 1 is complete: the frozen candidate and all release-gate tests above are recorded as `PASS`.

See [`docs/VALIDATION-CANDIDATE.md`](docs/VALIDATION-CANDIDATE.md), [`docs/VM-VALIDATION.md`](docs/VM-VALIDATION.md), [`docs/VALIDATION-STATUS.env`](docs/VALIDATION-STATUS.env) and [`docs/TESTING.md`](docs/TESTING.md).

## Phase 2 — `0.2.x`: Complete GenixBit Identity

- [x] Approve the official GenixBit OS logo and visual system.
- [x] Create `genixbit-os-base-files` source scaffolding and identity templates.
- [x] Build the `genixbit-os-base-files` Debian package successfully.
- [x] Integrate the package into the ISO build pipeline.
- [x] Test clean installation, ownership, upgrade and rollback behavior.
- [x] Create `genixbit-os-theme`.
- [x] Create `genixbit-os-wallpapers`.
- [x] Create `genixbit-os-installer-config`.
- [x] Replace user-facing boot, live-session, installer, desktop and support branding.
- [x] Ensure `/etc/os-release`, issue files, URLs and settings identify GenixBit OS.
- [x] Audit remaining upstream terms as legal notices, technical dependencies or migration defects.
- [x] Produce genuine screenshots from a validated GenixBit build.

### GenixBit Branding Foundation Status
- Branding package source: PASS
- Transparent asset generation: PASS
- Package build: PASS
- Install: PASS
- Upgrade: PASS
- Rollback: PASS
- Purge: PASS
- Identity restoration: PASS
- ISO integration: PASS
- BIOS branding: PASS
- UEFI branding: PASS
- Installer branding: PASS
- Installed-system branding: PASS

**Validated 0.2.0-alpha Candidate 2:**
- Candidate branch: `validation/0.2.0-alpha-candidate-2`
- Candidate SHA: `88a1550a9129a80ffd2c4cf73838122020a782cb`
- Evidence PR: #40
- Status: **PASS** (Release validation complete)

**Retired Diagnostic Candidate 1:**
- Candidate branch: `validation/0.2.0-alpha-candidate`
- Candidate SHA: `1df86702914fee558bc71ca3e2d3b013f242399e`
- Status: **FAIL** (Retired due to target build version and candidate mismatch)

See [`docs/BRANDING-MIGRATION.md`](docs/BRANDING-MIGRATION.md) and [`docs/BASE-FILES.md`](docs/BASE-FILES.md).

## Phase 3 — `0.3.x`: Signed Package and Update Infrastructure

- [ ] Provision `packages.os.genixbit.com` staging infrastructure.
- [ ] Define offline signing-key generation, backup and revocation procedures.
- [ ] Publish only the public verification key.
- [ ] Create `genixbit-os-archive-keyring`.
- [ ] Create `genixbit-os-apt-config`.
- [ ] Establish `alpha`, `testing` and `stable` channels.
- [ ] Implement snapshots, package promotion, rollback and audit records.
- [ ] Build, sign and test GenixBit replacement packages.
- [ ] Migrate from `packages.anduinos.com` only after clean-install and upgrade validation.
- [ ] Add update metadata and release manifests.

## Phase 4 — `0.4.x`: Developer, Server and Creator Profiles

- [ ] Developer profile: Git, containers, Python, Node.js, Go, Rust, Java and build tools.
- [ ] Application-builder profile: IDEs, databases, API clients, testing and deployment templates.
- [ ] Server-manager profile: headless services, monitoring, backups, firewall and container operations.
- [ ] Creator profile: video, audio, image, 3D, streaming, transcription and codec tooling.
- [ ] AI learner profile: guided setup and GenixBit Academy starter paths.
- [ ] Hardware and GPU diagnostics.
