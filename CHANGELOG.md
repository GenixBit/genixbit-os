# Changelog

All notable changes to the **GenixBit OS** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows Semantic Versioning for release identifiers.

## [Unreleased] — Phase 3 Signed Package & Update Infrastructure Bootstrap (2026-07-22)

- Defined offline GPG signing key management, backup, recovery, revocation, promotion, and rollback policies (`docs/PACKAGE-*.md`).
- Scaffolded `genixbit-os-archive-keyring` and `genixbit-os-apt-config` Debian package structures under `packages/`.
- Established `resolute-alpha`, `resolute-testing`, and `resolute-stable` APT repository channel layout standards (`docs/PACKAGE-REPOSITORY-LAYOUT.md`).
- Created staging repository management scripts (`tools/repository/init-staging-repository.sh`, `build-package-index.sh`, `validate-repository-layout.sh`, `verify-release-signature.sh`, `promote-package.sh`, `rollback-snapshot.sh`, `create-release-manifest.sh`).
- Defined JSON schemas for package manifests, promotion records, and rollback records (`docs/schemas/`).
- Added Package Infrastructure CI workflow `.github/workflows/package-infrastructure.yml`.

## [0.2.0-alpha-candidate-2] — Candidate Validation Successful (2026-07-22)

- Target build version set to `0.2.0-alpha`.
- Added release version consistency validation script `tools/validation/check-release-version-consistency.sh` and test suite.
- Added release manifest schema `docs/releases/0.2.0-alpha.env`, validator `tools/validation/check-release-manifest.sh`, and test suite `tools/validation/test-release-manifest.sh`.
- Integrated release manifest checks into Repository Quality CI workflow `.github/workflows/quality.yml`.
- Completed comprehensive upstream branding audit `docs/UPSTREAM-BRANDING-AUDIT.md` and audit validation tools.
- Published genuine Candidate 2 release screenshots gallery `docs/RELEASE-SCREENSHOTS-0.2.0-alpha.md` and WebP assets under `docs/assets/releases/0.2.0-alpha/`.
- Frozen validation candidate `validation/0.2.0-alpha-candidate-2` at SHA `88a1550a9129a80ffd2c4cf73838122020a782cb` created, built, and fully validated (Evidence PR #40).

### Validation Artifact Details

- Artifact ISO: `GenixBitOS-0.2.0-alpha-2607220558.iso`
- ISO Size: `2,540,554,240` bytes
- SHA-256: `d9aa0d2e850fdbcfb87beeaecb1ea2762a4d9522aa48d3bc6aa2bd0c6ee6f228`
- Build Host: GCP Ubuntu 26.04 `resolute` `amd64` / KVM host

### Validation Gate Results (PR #40)

- **BIOS & UEFI Live Sessions**: Booted cleanly to live desktop in both UEFI (OVMF) and Legacy BIOS (SeaBIOS) modes.
- **Installer Execution**: Ubiquity installer successfully executed, partitioned disk, configured user `genixbit`, and completed installation.
- **Installed System Boot**: Target disk booted cleanly in both BIOS and UEFI modes.
- **APT & Package Health**: `sudo apt update`, `apt-get check` (0 broken packages), `dpkg --audit` (0 unconfigured packages), and `journalctl -p 3 -b` (0 critical errors) passed.
- **Reproducibility**: Second clean build (`Build B`) compiled independently; `cmp` confirmed 100% byte-for-byte identical outputs.

### Branding Foundation Validation Status

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

## [0.1.0-alpha] — Candidate Validation Successful (2026-07-21)

### Added

- Frozen validation candidate `validation/0.1.0-alpha-candidate-2` at SHA `4888b05eda7528b1ff0c607b9799201999d61031` created, built, and verified.
- Machine-readable validation status in `docs/VALIDATION-STATUS.env`.
- Release-evidence validator at `tools/validation/check-release-evidence.sh`.
- Repository Quality enforcement requiring all candidate release gates to be `PASS` for `test/validate-*` pull requests.
- Clamped file, folder, and symlink timestamps inside the host image directory before ISO build to achieve bit-for-bit reproducible ISO generation.

### Validation Cycle Status (2026-07-21)

| Test | Status |
| --- | :---: |
| Candidate branch `validation/0.1.0-alpha-candidate-2` created | **PASS** |
| Candidate SHA `4888b05eda7528b1ff0c607b9799201999d61031` verified | **PASS** |
| Candidate checkout clean | **PASS** |
| First host attempt | **FAIL** — macOS `arm64` was correctly rejected; it was not a supported validation host |
| PR #17 blocked-attempt evidence record | **PASS** — merged as documentation of the blocker only, not successful candidate validation |
| ISO build from candidate SHA | **PASS** |
| BIOS live-session (SeaBIOS → GRUB → live desktop) | **PASS** |
| UEFI live-session (OVMF → BOOTX64.EFI → GRUB → live desktop) | **PASS** |
| Installer validation (UEFI then BIOS) | **PASS** |
| Installed-system boot and health | **PASS** |
| APT and package-health checks | **PASS** |
| `genixbit-os-base-files` package status | **PARTIAL / SCAFFOLDED** |
| Second clean build from same candidate SHA | **PASS** |
| Reproducibility comparison (`diffoscope`) | **PASS** — Build A and Build B are 100% bit-for-bit identical |

All runtime and reproducibility tests successfully completed on the approved Ubuntu 26.04 `resolute` amd64 GCE validation host. The release candidate has been fully validated.

## [Unreleased] — Tooling and Candidate Process

### Added

- `GOVERNANCE.md` defining the GenixBit-controlled official maintainer and release model.
- `.github/CODEOWNERS` assigning official repository ownership to `@GenixBit`.
- AI-first platform, model catalog, branding migration, Store and platform-service architecture documentation.
- Original GenixBit product, documentation and package-status previews.
- Containerized Caddy preview deployment and non-sensitive deployment-status documentation.
- QEMU launcher, validation-host helper and candidate build/preflight tooling under `tools/vm/`.
- `docs/VALIDATION-CANDIDATE.md` defining an immutable release-validation branch and SHA process.
- `genixbit-os-base-files` source scaffolding, identity templates and package documentation.

### Changed

- Repositioned the README around developers, AI learners, server managers, creators, local AI, GenixBit Agents, Bharat AI and the future GenixBit Store.
- Expanded the roadmap through branding, package signing, user profiles, AI runtimes, AI Center, Agents, Store, websites, security and stable release.
- Changed the contribution policy to an early-alpha closed maintainer model while preserving external GPL rights, bug reports, security reports, feature suggestions and compatibility feedback.
- Corrected baseline terminology so historical ISO compilation is not confused with current release validation.
- Replaced the moving "current main" target with a frozen candidate branch and exact-SHA requirement.
- Hardened `verify-runtime.sh` to reject dirty or mismatched checkouts, verify generated checksums, record BIOS/UEFI metadata and confirm `EFI/BOOT/BOOTX64.EFI`.
- Corrected `setup-host.sh` counters so `set -e` does not terminate the script on the first pass, warning or failure count.
- Required Ubuntu 26.04 `resolute`, x86_64, approved sudo, explicit KVM handling and complete validation commands for the candidate host.
- Corrected the merged PR #17 wording so it is treated as a blocked unsupported-host attempt, not completed candidate validation.
- Updated website and documentation service status while keeping the package domain status-only and non-APT.
- Removed public cloud resource identifiers and administrator-specific SSH details from deployment documentation.
- Clarified that model downloads remain optional and that open weights, open source and free access are different licensing concepts.

### Preserved

- GPL-3.0 licensing and mandatory upstream attribution.
- Temporary AnduinOS package names and repository dependencies required by the current build pipeline.
- The rule that no ISO or production feature may be claimed before direct validation.

## [0.1.0-alpha] - 2026-07-20

### Added

- First ISO compilation completed on an Ubuntu 26.04 `resolute` `amd64` build host.
- ISO image `GenixBitOS-0.1.0-alpha-2607201328.iso` generated with a recorded size of 2,525,634,560 bytes.
- SHA-256 checksum artifact independently matched digest `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b`.
- Historical hybrid BIOS/UEFI boot structures recorded.
- Baseline build evidence documented in `docs/TESTING.md`.
- Initial governance, security, contribution, roadmap, build, branding, package, architecture, upstream-sync and testing documentation.
- GitHub issue and pull-request templates.
- Repository-quality checks for shell syntax, generated artifacts, private material, local paths, identity values, required legal files and obvious credential patterns.

### Validation Limits

- The first ISO was built from historical commit `2ed584c` and predates later build-pipeline and identity-package changes.
- No frozen release-validation candidate ISO is yet recorded.
- Reaching the live desktop in UEFI and Legacy BIOS is not directly evidenced.
- Interactive installer completion and installed-system boot are not recorded.
- Installed-system `apt update`, package-health and critical-log review are not recorded.
- A second same-candidate clean build and reproducibility comparison are not recorded.
- The alpha ISO is not approved for public release or production use.

### Changed

- Configured identity variables in `args.sh`:
  - `TARGET_NAME="genixbitos"`
  - `TARGET_BUSINESS_NAME="GenixBitOS"`
  - `TARGET_BUILD_VERSION="0.1.0-alpha"`
- Updated generated ISO documentation to reflect GenixBit OS identity and its Ubuntu / AnduinOS 2 foundation.
- Updated `makefile` and `menuconfig.sh` for GenixBit OS identity while preserving host compatibility.
- Rewrote the root README with early-alpha status, feature status, roadmap, build instructions, testing status and official services.
- Annotated temporary upstream package dependencies.

### Preserved

- Original upstream Git history from `AiursoftWeb/AnduinOS-2`.
- GNU General Public License v3.0 (`LICENSE`) and third-party software inventory (`OSS.md`).
- Existing AnduinOS package infrastructure references required for current ISO builds before GenixBit replacement packages are ready.
