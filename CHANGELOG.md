# Changelog

All notable changes to the **GenixBit OS** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows Semantic Versioning for release identifiers.

## [Unreleased]

### Added

- `GOVERNANCE.md` defining the GenixBit-controlled official maintainer and release model.
- `.github/CODEOWNERS` assigning official repository ownership to `@GenixBit`.
- `docs/AI-FIRST-PLATFORM.md` defining the AI-first platform, user profiles, runtime layers, GenixBit Agents integration, and trust principles.
- `docs/AI-MODEL-CATALOG.md` defining hardware-aware and license-aware model catalog requirements.
- `docs/BRANDING-MIGRATION.md` defining safe migration from temporary upstream packages to complete GenixBit user-facing identity.
- `docs/APP-STORE.md` defining the future GenixBit Store architecture and trust levels.
- `docs/PLATFORM-SERVICES.md` defining the website, documentation, package, download, catalog, DNS, and server topology.
- Original GenixBit static previews under `website/os`, `website/docs`, and `website/packages`.
- Containerized Caddy preview deployment under `deploy/`.
- Created `docs/DEPLOYMENT-STATUS.md` documenting platform services deployment status, container security options, security header audit, and server provisioning prerequisites.

### Changed

- Repositioned the README around developers, AI learners, server managers, creators, local AI, GenixBit Agents, Bharat AI, and the future GenixBit Store.
- Expanded the roadmap from baseline ISO validation through branding, package signing, user profiles, AI runtimes, AI Center, Agents, Store, websites, security, and stable release.
- Changed the contribution policy to an early-alpha closed maintainer model while preserving external GPL rights, bug reports, security reports, feature suggestions, and compatibility feedback.
- Clarified that the planned service domains and signed package repository are not yet live.
- Clarified that model downloads remain optional and that open weights, open source, and free access are different licensing concepts.

### Preserved

- GPL-3.0 licensing and mandatory upstream attribution.
- Temporary AnduinOS package names and repository dependencies required by the current build pipeline.
- The rule that no ISO or production feature may be claimed before validation.

## [0.1.0-alpha] - 2026-07-20

### Added

- Created `UPSTREAM.md` establishing attribution to AnduinOS 2 and Ubuntu.
- Created `SECURITY.md` defining security reporting policy for the early-alpha phase.
- Created initial governance, contribution, roadmap, build, branding, package, architecture, upstream-sync, and testing documentation.
- Created GitHub issue and pull-request templates.
- Added repository-quality checks for shell syntax, generated artifacts, private material, local paths, identity values, required legal files, and obvious credential patterns.
- Recorded that the available macOS ARM environment is unsuitable for the full Ubuntu 26.04 amd64 ISO build.

### Changed

- Configured identity variables in `args.sh`:
  - `TARGET_NAME="genixbitos"`
  - `TARGET_BUSINESS_NAME="GenixBitOS"`
  - `TARGET_BUILD_VERSION="0.1.0-alpha"`
- Updated generated ISO documentation to reflect GenixBit OS identity and its Ubuntu / AnduinOS 2 foundation.
- Updated `makefile` and `menuconfig.sh` for GenixBit OS identity while preserving host compatibility.
- Rewrote the root README with an early-alpha warning, feature status, roadmap, build instructions, testing status, and official service plan.
- Annotated temporary upstream package dependencies.

### Preserved

- Original upstream Git history from `AiursoftWeb/AnduinOS-2`.
- GNU General Public License v3.0 (`LICENSE`) and third-party software inventory (`OSS.md`).
- Existing AnduinOS package infrastructure references required for current ISO builds before GenixBit replacement packages are ready.
