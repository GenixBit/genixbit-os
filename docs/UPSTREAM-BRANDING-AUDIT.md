# GenixBit OS Upstream Branding & Dependency Audit

## Overview

This audit records every upstream reference to **AnduinOS**, **Ubuntu**, **Canonical**, and **Aiursoft** within the repository codebase, documentation, build pipeline, Debian package dependencies, and runtime infrastructure.

Each entry is classified into exactly one approved audit category:

1. `LEGAL_ATTRIBUTION` — Mandatory copyright notices, license texts, and upstream attribution.
2. `TECHNICAL_DEPENDENCY` — Package names, repository URLs, or technical dependencies required for build/runtime until signed GenixBit replacements are ready.
3. `BUILD_SYSTEM_COMMENT` — Developer comments or build script notes explaining build ancestry or upstream mechanisms.
4. `USER_VISIBLE_MIGRATION_DEFECT` — User-facing text on boot, live desktop, installer, or settings that displays upstream branding instead of GenixBit OS.
5. `APPROVED_BASE_OS_REFERENCE` — Factual technical references to the underlying Ubuntu 26.04 (`resolute`) base distribution, kernel, or upstream Debian/Ubuntu infrastructure.
6. `FALSE_POSITIVE` — Variable names, diversion suffix paths, or unrelated strings that matched search patterns.

---

## Complete Audit Register

### 1. Legal Attribution & Copyright Notices

| Surface / Path | Current Text | Classification | Reason | Action Required | Target Phase | Replacement Dependency | Validation Needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `UPSTREAM.md:L1` | `AnduinOS` upstream attribution & history | `LEGAL_ATTRIBUTION` | Mandatory GPL-3.0 attribution for upstream project foundation. | Keep unchanged. | N/A | None | Legal review |
| `LICENSE:L1-340` | GNU General Public License v3.0 | `LEGAL_ATTRIBUTION` | Core open-source license governing covered source files. | Keep unchanged. | N/A | None | License audit |
| `OSS.md:L1-50` | Open Source Software inventory & Ubuntu / AnduinOS references | `LEGAL_ATTRIBUTION` | Upstream software inventory disclosure. | Keep updated with new packages. | Ongoing | None | Inventory check |
| `GOVERNANCE.md:L25` | Attribution notes referencing `AiursoftWeb/AnduinOS-2` | `LEGAL_ATTRIBUTION` | Governance policy referencing original upstream fork ancestry. | Keep unchanged. | N/A | None | Policy review |

---

### 2. Technical Package & Repository Dependencies

| Surface / Path | Current Text | Classification | Reason | Action Required | Target Phase | Replacement Dependency | Validation Needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `args.sh:L13` | `export APT_SERVER="packages.anduinos.com"` | `TECHNICAL_DEPENDENCY` | Active APT server URL for pre-built desktop and kernel packages. | Migrate to `packages.os.genixbit.com` after signed repository deployment. | Phase 3 | `genixbit-os-apt-config` | Clean install & upgrade test |
| `mods/01-install-swap-packages-mod/install.sh:L12` | `anduinos-archive-keyring` | `TECHNICAL_DEPENDENCY` | Upstream APT GPG keyring package required for `packages.anduinos.com`. | Replace with `genixbit-os-archive-keyring`. | Phase 3 | `genixbit-os-archive-keyring` | APT signature test |
| `mods/01-install-swap-packages-mod/install.sh:L13` | `anduinos-apt-config` | `TECHNICAL_DEPENDENCY` | Upstream APT sources list configuration package. | Replace with `genixbit-os-apt-config`. | Phase 3 | `genixbit-os-apt-config` | Repository update test |
| `mods/05-live-kernel-apps-installer/install.sh:L26-44` | `anduinos-desktop`, `anduinos-theme`, `anduinos-wallpapers`, `firefox-anduinos`, `plymouth-anduinos` | `TECHNICAL_DEPENDENCY` | Upstream desktop metapackages and desktop asset packages. | Build, sign, and replace with `genixbit-os-desktop`, `genixbit-os-theme`, `genixbit-os-wallpapers`. | Phase 3 / Phase 4 | `genixbit-os-*` packages | Package upgrade & rollback test |
| `mods/05-live-kernel-apps-installer/install.sh:L50` | `anduinos-installer-config` | `TECHNICAL_DEPENDENCY` | Installer slideshow and branding configuration package. | Replace with `genixbit-os-installer-config`. | Phase 2 (Completed candidate) | `genixbit-os-installer-config` | Installer slideshow test |
| `packages/genixbit-os-base-files/debian/preinst:L8` | `--divert /usr/lib/os-release.ubuntu` | `TECHNICAL_DEPENDENCY` | `dpkg-divert` target path for backing up original Ubuntu os-release file. | Keep diversion target suffix for safe package cleanup. | Ongoing | None | Package purge & restore test |

---

### 3. Build System Comments & Scripts

| Surface / Path | Current Text | Classification | Reason | Action Required | Target Phase | Replacement Dependency | Validation Needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `build.sh:L1` | Developer header comments mentioning AnduinOS build architecture | `BUILD_SYSTEM_COMMENT` | Factual developer documentation regarding ISO build layout. | Keep for maintainer context. | N/A | None | Code audit |
| `mods/01-install-swap-packages-mod/install.sh:L9` | `print_ok "Installing AnduinOS APT configuration..."` | `BUILD_SYSTEM_COMMENT` | Build mod console log output during package swap. | Update log string when GenixBit packages replace upstream packages. | Phase 3 | `genixbit-os-apt-config` | ISO compilation test |
| `mods/78-ensure-no-junk/install.sh:L48` | `# Ubuntu GNOME extensions (AnduinOS ships own versions)` | `BUILD_SYSTEM_COMMENT` | Build script comment documenting package exclusion rationale. | Retain comment. | N/A | None | Code audit |
| `makefile:L1` | Build system comment referencing derived layout | `BUILD_SYSTEM_COMMENT` | Build orchestration comment. | Retain comment. | N/A | None | Makefile check |

---

### 4. Approved Base OS References

| Surface / Path | Current Text | Classification | Reason | Action Required | Target Phase | Replacement Dependency | Validation Needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `packages/genixbit-os-base-files/usr/lib/os-release:L4` | `ID_LIKE="ubuntu debian"` | `APPROVED_BASE_OS_REFERENCE` | Standard freedesktop.org os-release property indicating Ubuntu/Debian compatibility. | Keep unchanged. | Ongoing | None | App compatibility test |
| `packages/genixbit-os-base-files/usr/lib/os-release:L11` | `UBUNTU_CODENAME=resolute` | `APPROVED_BASE_OS_REFERENCE` | Standard Ubuntu base release codename (26.04). | Keep unchanged. | Ongoing | None | APT sources compatibility |
| `args.sh:L9` | `export TARGET_UBUNTU_VERSION="resolute"` | `APPROVED_BASE_OS_REFERENCE` | Build configuration variable for target base OS codename. | Keep unchanged. | Ongoing | None | Build bootstrap check |
| `tools/validation/test-packages.sh:L11` | `docker run ... ubuntu:26.04` | `APPROVED_BASE_OS_REFERENCE` | Test container base image specification. | Keep unchanged. | Ongoing | None | CI execution test |
| `website/os/index.html:L6` | `"GenixBit OS is an AI-first Ubuntu-based Linux distribution..."` | `APPROVED_BASE_OS_REFERENCE` | Factual public positioning description. | Keep unchanged. | Ongoing | None | Web preview check |

---

### 5. User-Visible Migration Defects

| Surface / Path | Current Text | Classification | Reason | Action Required | Target Phase | Replacement Dependency | Validation Needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Live Desktop Slideshow (Observed in Candidate 2 installer) | Ubiquity installer slideshow title text `Welcome to AnduinOS` | `USER_VISIBLE_MIGRATION_DEFECT` | Upstream Ubiquity installer slideshow deb package retains hardcoded banner image/text. | Package and deploy `genixbit-os-installer-config` to replace installer slides. | Phase 3 / Phase 4 | `genixbit-os-installer-config` | Visual installer test |
