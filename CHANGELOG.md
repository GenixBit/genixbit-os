# Changelog

All notable changes to the **GenixBit OS** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows Semantic Versioning for release identifiers.

## [Unreleased]

### Added

- `GOVERNANCE.md` defining the GenixBit-controlled official maintainer and release model.
- `.github/CODEOWNERS` assigning official repository ownership to `@GenixBit`.
- `docs/AI-FIRST-PLATFORM.md` defining the AI-first platform, user profiles, runtime layers, GenixBit Agents integration and trust principles.
- `docs/AI-MODEL-CATALOG.md` defining hardware-aware and license-aware model catalog requirements.
- `docs/BRANDING-MIGRATION.md` defining safe migration from temporary upstream packages to complete GenixBit user-facing identity.
- `docs/APP-STORE.md` defining the future GenixBit Store architecture and trust levels.
- `docs/PLATFORM-SERVICES.md` defining the website, documentation, package, download, catalog, DNS and server topology.
- Original GenixBit static previews under `website/os`, `website/docs` and `website/packages`.
- Containerized Caddy preview deployment under `deploy/`.
- `docs/DEPLOYMENT-STATUS.md` recording non-sensitive public preview deployment and follow-up hardening requirements.
- `tools/vm/setup-host.sh` host readiness check script for x86_64 KVM test environments.
- `tools/vm/run-qemu.sh` QEMU VM validation test harness for Legacy BIOS and UEFI boot modes.

### Changed

- Repositioned the README around developers, AI learners, server managers, creators, local AI, GenixBit Agents, Bharat AI and the future GenixBit Store.
- Expanded the roadmap through branding, package signing, user profiles, AI runtimes, AI Center, Agents, Store, websites, security and stable release.
- Changed the contribution policy to an early-alpha closed maintainer model while preserving external GPL rights, bug reports, security reports, feature suggestions and compatibility feedback.
- Corrected baseline validation terminology so successful ISO compilation and checksum verification are not confused with live-desktop, installer, installed-system or reproducibility testing.
- Clarified that the first ISO is historical build evidence and cannot validate the current source after later EFI and container-build changes.
- Required a fresh ISO from the exact current `main` commit before BIOS, UEFI, installer, installed-system or reproducibility approval.
- Restored standard interactive `sudo` support in `make bootstrap`; automated hosts may still use approved passwordless sudo.
- Updated website and documentation service status to reflect the recorded public previews while keeping the package domain status-only and non-APT.
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
- SHA-256 checksum artifact `GenixBitOS-0.1.0-alpha-2607201328.sha256` independently matched digest `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b`.
- Hybrid BIOS/UEFI boot structures and QEMU bootloader paths recorded.
- Baseline build evidence documented in `docs/TESTING.md`.
- Created `UPSTREAM.md` establishing attribution to AnduinOS 2 and Ubuntu.
- Created `SECURITY.md` defining security reporting policy for the early-alpha phase.
- Created initial governance, contribution, roadmap, build, branding, package, architecture, upstream-sync and testing documentation.
- Created GitHub issue and pull-request templates.
- Added repository-quality checks for shell syntax, generated artifacts, private material, local paths, identity values, required legal files and obvious credential patterns.

### Validation Limits

- The first ISO was built from commit `2ed584c` and predates later build-pipeline changes.
- Reaching the live desktop in UEFI and Legacy BIOS is not yet directly evidenced in the public testing record.
- Interactive installer completion is not yet recorded.
- Booting and validating an installed system is not yet recorded.
- Installed-system `apt update`, hardware-function and critical-log review are not yet recorded.
- A second same-commit clean build and reproducibility comparison are not yet recorded.
- The alpha ISO is not yet approved for public release or production use.

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
