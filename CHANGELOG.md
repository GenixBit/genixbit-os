# Changelog

All notable changes to the **GenixBit OS** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Official GenixBit OS branding assets (logo, wallpapers, desktop themes, Plymouth splash).
- Dedicated APT package repository at `packages.os.genixbit.com`.
- GenixBit repository GPG archive keyring (`genixbit-os-archive-keyring`).
- Pre-configured developer toolchains and AI assistant integrations.

---

## [0.1.0-alpha] - 2026-07-20

### Added
- Created `UPSTREAM.md` establishing attribution to AnduinOS 2 and Ubuntu.
- Created `SECURITY.md` defining security reporting policy for early-alpha phase.
- Created `ROADMAP.md` outlining provisional milestones from 0.1.0 through 1.0.0.
- Created `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` for project governance.
- Created technical documentation under `docs/`:
  - `docs/ARCHITECTURE.md`
  - `docs/BUILDING.md`
  - `docs/BRANDING.md`
  - `docs/UPSTREAM-SYNC.md`
  - `docs/PACKAGE-ROADMAP.md`
- Created GitHub repository issue templates and pull request template.

### Changed
- Configured identity variables in `args.sh` (`TARGET_NAME="genixbitos"`, `TARGET_BUSINESS_NAME="GenixBitOS"`, `TARGET_BUILD_VERSION="0.1.0"`).
- Updated generated ISO `README.md` text in `build.sh` to reflect GenixBit OS product identity and Ubuntu / AnduinOS 2 foundation.
- Updated `makefile` and `menuconfig.sh` for GenixBit OS identity while preserving host compatibility.
- Rewrote root `README.md` with comprehensive early-alpha warning, positioning, project goals, feature matrix, and build instructions.
- Annotated temporary upstream dependencies in `args.sh` and build documentation.

### Preserved
- Retained original upstream Git history from `AiursoftWeb/AnduinOS-2`.
- Preserved GNU General Public License v3.0 (`LICENSE`) and third-party software log (`OSS.md`).
- Preserved existing AnduinOS package infrastructure references required for current ISO builds prior to package server deployment.
