# GenixBit OS Package Infrastructure Migration & Staging Validation Evidence

## Executive Summary

- **Branch**: `test/validate-genixbit-package-migration`
- **PR Title**: `test: validate GenixBit package migration`
- **Validation Date**: July 23, 2026
- **Status**: **PASS**
- **Production Repository Status**: **NOT DEPLOYED** (Production APT source `APKG_SERVER="https://packages.anduinos.com"` remains unchanged until explicitly approved)
- **Pinned Ref Integrity**: `v0.2.0-alpha` and `validation/0.2.0-alpha-candidate-2` remain pinned to `88a1550a9129a80ffd2c4cf73838122020a782cb`.

---

## 1. Replacement Packages & Metadata

| Package Name | Built Version | Dependencies | Replaces / Conflicts / Provides | License |
| :--- | :--- | :--- | :--- | :--- |
| `genixbit-os-archive-keyring` | `0.2.0-alpha-1` | `${misc:Depends}` | `anduinos-archive-keyring` | GPL-3.0-or-later |
| `genixbit-os-apt-config` | `0.2.0-alpha-1` | `genixbit-os-archive-keyring` | `anduinos-apt-config` | GPL-3.0-or-later |
| `genixbit-os-base-files` | `0.2.0-alpha-1` | `${misc:Depends}` | `base-files` (dpkg-divert) | GPL-3.0-or-later |
| `genixbit-os-desktop` | `0.2.0-alpha-1` | `genixbit-os-base-files`, `genixbit-os-apt-config`, `genixbit-os-theme`, `genixbit-os-wallpapers` | `anduinos-desktop` & related desktop dependencies | GPL-3.0-or-later |
| `genixbit-os-theme` | `0.2.0-alpha-1` | `${misc:Depends}` | `anduinos-theme`, `plymouth-anduinos` | GPL-3.0-or-later |
| `genixbit-os-wallpapers` | `0.2.0-alpha-1` | `${misc:Depends}` | `anduinos-wallpapers` | GPL-3.0-or-later |
| `genixbit-os-installer-config` | `0.2.0-alpha-1` | `${misc:Depends}` | `anduinos-installer-config` | GPL-3.0-or-later |

---

## 2. Upstream Dependency Mapping

| Legacy Upstream Dependency | GenixBit Replacement Package | Migration Strategy & Action |
| :--- | :--- | :--- |
| `anduinos-archive-keyring` | `genixbit-os-archive-keyring` | Provides GPG verification keys (`/usr/share/keyrings/genixbit-os-archive-keyring.pgp`). Replaces legacy keyring package. |
| `anduinos-apt-config` | `genixbit-os-apt-config` | Provides signed deb822 sources (`/etc/apt/sources.list.d/genixbit-os.sources`) with `Enabled: no` in initial staging state. |
| `anduinos-desktop` | `genixbit-os-desktop` | Metapackage providing full desktop environment dependencies and replacing upstream metapackages (`anduinos-desktop-apps`, `firefox-anduinos`, etc.). |
| `anduinos-theme` / `plymouth-anduinos` | `genixbit-os-theme` | Replaces upstream desktop and plymouth themes. Provides Plymouth boot theme at `/usr/share/plymouth/themes/genixbit/`. |
| `anduinos-wallpapers` | `genixbit-os-wallpapers` | Replaces upstream wallpaper package with GenixBit high-resolution vector and bitmap wallpapers. |
| `anduinos-installer-config` | `genixbit-os-installer-config` | Replaces Calamares / Ubiquity installer slides and branding configurations with GenixBit OS identity and alpha warnings. |

---

## 3. Signing Workstation & Staging Suite Verification

- **Signing Key Isolation**: Ephemeral RSA-2048 signing keys generated in isolated `GNUPGHOME` outside repository tree. No private key material committed or stored.
- **Staging Suites Created**:
  - `resolute-alpha`
  - `resolute-testing`
- **Metadata Signatures**: Verified `InRelease` (clearsigned) and `Release.gpg` (detached signature).
- **Tamper Protection Tests**:
  - Tampered `Release` metadata SHA-256 mismatch -> **REJECTED (PASS)**
  - Tampered package binary hash mismatch -> **REJECTED (PASS)**
  - Unknown GPG signing key -> **REJECTED (PASS)**
  - Expired / revoked key -> **REJECTED (PASS)**

---

## 4. 20-Point Migration Validation Results

| # | Validation Scenario | Status | Result Summary |
| :-: | :--- | :-: | :--- |
| 1 | Clean installation of replacement packages | **PASS** | Every package installs without conflicts on clean base system. |
| 2 | Upgrade from Candidate 2 dependencies | **PASS** | Package manager resolves `Replaces:`, `Provides:`, `Conflicts:` metadata cleanly. |
| 3 | Replacement of `anduinos-archive-keyring` | **PASS** | `genixbit-os-archive-keyring` replaces legacy keyring. |
| 4 | Replacement of `anduinos-apt-config` | **PASS** | `genixbit-os-apt-config` replaces legacy APT config. |
| 5 | APT source migration without duplicate sources | **PASS** | Sources list configured without duplicate entries. |
| 6 | No unsigned or `trusted=yes` configuration | **PASS** | Enforced `Signed-By` keyring requirement; zero `trusted=yes` present. |
| 7 | Desktop metapackage dependency resolution | **PASS** | `genixbit-os-desktop` resolves all core theme, wallpaper, and base dependencies. |
| 8 | Theme and wallpaper installation | **PASS** | Desktop icons, pixmaps, and background wallpapers installed correctly. |
| 9 | Plymouth branding | **PASS** | Plymouth theme (`/usr/share/plymouth/themes/genixbit/`) installed. |
| 10 | Installer slideshow displays GenixBit OS | **PASS** | Slideshow displays GenixBit logo, product name, alpha warnings, zero "Welcome to AnduinOS". |
| 11 | Package removal and purge | **PASS** | Clean package removal without leaving stray configuration artifacts. |
| 12 | `dpkg-divert` restoration | **PASS** | Original Ubuntu os-release and issue files restored upon package purge. |
| 13 | Interrupted upgrade recovery | **PASS** | System handles interrupted package upgrades cleanly via `dpkg --configure -a`. |
| 14 | Snapshot creation | **PASS** | Created staging repository snapshot `snap-resolute-alpha-*`. |
| 15 | Rollback to previous validated state | **PASS** | Rollback script successfully restores repository state from snapshot. |
| 16 | Re-upgrade after rollback | **PASS** | Clean re-upgrade path verified after rollback. |
| 17 | `apt-get update` | **PASS** | APT repository index fetch and signature verification succeed. |
| 18 | `apt-get check` | **PASS** | APT dependency graph integrity check passes with zero errors. |
| 19 | `dpkg --audit` | **PASS** | Dpkg audit passes cleanly with no unconfigured or broken packages. |
| 20 | Dependency loop prevention | **PASS** | No broken packages or held dependency loops detected. |

---

## 5. CI & Security Enforcement

- **Fail-Closed CI Test Suite**: `tools/validation/check-package-migration-ci.sh` added to `.github/workflows/quality.yml`.
- **Secret & Key Protection**: No `.key`, `.pem`, `.sec`, or private key files tracked in git.
- **Upstream Legal Attribution**: `LICENSE`, `UPSTREAM.md`, and `OSS.md` preserved intact.
