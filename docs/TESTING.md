# GenixBit OS Baseline Testing Record

This document records the evidence available for the first `0.1.0-alpha` ISO build. A status is marked `PASS` only when the repository contains a clear record that the specific activity was performed. Package presence, configuration files, manifests, or bootloader files do not by themselves prove that a live desktop, installer, or installed system worked interactively.

## Status Vocabulary

- **PASS** — directly performed and recorded.
- **PARTIAL** — some relevant evidence exists, but the complete user-visible test is not recorded.
- **FAIL** — performed and failed.
- **NOT TESTED** — no direct execution evidence is recorded.

## Build Information

| Field | Value |
| --- | --- |
| Build date | 2026-07-20 |
| Source commit used for build | `2ed584c` |
| Build-host Ubuntu version | Ubuntu 26.04 LTS (`resolute`) |
| Build-host architecture | `amd64` / `x86_64` |
| Recorded host capacity | 1 vCPU, 2 GB RAM and 8 GB swap |
| Build result | **PASS** |
| ISO filename | `GenixBitOS-0.1.0-alpha-2607201328.iso` |
| ISO size | 2,525,634,560 bytes |
| SHA-256 | `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b` |
| Recorded build duration | Approximately 48 minutes |

Cloud resource identifiers, public build-host addresses, SSH access details, and administrator paths belong in a private GenixBit operations record and must not be committed here.

## Build and Artifact Validation

| Test | Status | Recorded evidence |
| --- | :---: | --- |
| Host codename and architecture matched the target | **PASS** | Ubuntu 26.04 `resolute`, `x86_64` recorded |
| `make bootstrap` completed | **PASS** | Recorded in merged PR #8 |
| `make` completed | **PASS** | ISO artifact was produced |
| ISO created under `dist/` | **PASS** | Filename and byte size recorded |
| Checksum file created | **PASS** | `.sha256` filename recorded |
| SHA-256 independently matched | **PASS** | Digest recorded above |
| Hybrid BIOS/UEFI structures included | **PASS** | OVMF/SeaBIOS and hybrid ISO structures recorded |
| Repository changes contained no committed ISO or private key | **PASS** | Repository Quality workflow passed |
| Complete ISO filesystem secret scan | **NOT TESTED** | No scan report is committed |
| Second clean build performed | **NOT TESTED** | Only one completed build is recorded |
| Reproducibility comparison performed | **NOT TESTED** | No second-build comparison exists |

## Boot and Live-Session Validation

| Test | Status | Recorded evidence or missing evidence |
| --- | :---: | --- |
| UEFI boot path | **PARTIAL** | OVMF bootloader validation is recorded; evidence that the live desktop was reached is not recorded |
| Legacy BIOS boot path | **PARTIAL** | SeaBIOS/hybrid bootloader validation is recorded; evidence that the live desktop was reached is not recorded |
| GRUB menu displayed interactively | **NOT TESTED** | `grub.cfg` existence is not an interactive display test |
| Kernel completed boot | **NOT TESTED** | No console or screenshot evidence is recorded |
| Live desktop reached | **NOT TESTED** | SquashFS and manifests prove content, not successful desktop startup |
| Keyboard and locale worked in live session | **NOT TESTED** | Locale packages are present, but interaction is not recorded |
| Display and graphics worked | **NOT TESTED** | Package integration is not a display test |
| Network and DNS worked in live session | **NOT TESTED** | Network configuration is present, but live connectivity is not recorded |
| Audio worked | **NOT TESTED** | Audio packages are present, but playback/device testing is not recorded |
| Shutdown and restart worked | **NOT TESTED** | Script presence is not runtime evidence |
| User-facing GenixBit identity was visually confirmed | **NOT TESTED** | Configuration values exist; screenshots or runtime output are not recorded |

## Installer Validation

| Test | Status | Recorded evidence or missing evidence |
| --- | :---: | --- |
| Installer packages and slideshow assets present | **PASS** | Ubiquity-related content was recorded in the built image |
| Blank virtual disk created | **PASS** | A 20 GB QCOW2 disk was recorded |
| Installer launched interactively | **NOT TESTED** | No installer session evidence is recorded |
| Language, keyboard and timezone selection worked | **NOT TESTED** | No interactive evidence is recorded |
| Partitioning completed | **NOT TESTED** | Script presence is not a completed partitioning run |
| Installation completed | **NOT TESTED** | No completed installation log or screenshot is recorded |
| Bootloader installed to the target disk | **NOT TESTED** | Configuration is present, but target-disk installation is not recorded |
| User account creation and login worked | **NOT TESTED** | No installed-system evidence is recorded |

## Installed-System Validation

| Test | Status | Recorded evidence or missing evidence |
| --- | :---: | --- |
| Installed system booted from virtual disk | **NOT TESTED** | No post-install boot evidence is recorded |
| Desktop session started | **NOT TESTED** | Configuration presence is not runtime evidence |
| `sudo apt update` succeeded inside installed system | **NOT TESTED** | Build-time repository access is not installed-system validation |
| No broken installed packages | **NOT TESTED** | Build manifest inspection is not an installed-system package-health check |
| Network and DNS worked | **NOT TESTED** | No installed-system command output is recorded |
| Display and audio worked | **NOT TESTED** | No installed-system interaction is recorded |
| Shutdown and restart worked | **NOT TESTED** | No runtime evidence is recorded |
| Critical boot logs were reviewed | **NOT TESTED** | No `journalctl` evidence is recorded |

## Evidence Retained

- Successful Ubuntu 26.04 `resolute` amd64 ISO compilation.
- ISO filename and exact byte size.
- Matching SHA-256 checksum.
- Hybrid BIOS/UEFI ISO structure and bootloader-path validation.
- Repository Quality workflow success for the merged changes.

Large artifacts, raw build logs, VM disks, screenshots containing private details, and cloud access information must remain outside Git. A private GenixBit evidence bundle should retain the ISO, checksum file, relevant logs, screenshots, VM configuration, and test operator notes.

## Known Issues and Limitations

- Temporary AnduinOS package dependencies remain in the alpha build.
- Complete user-facing GenixBit branding is not yet implemented.
- No second clean build has established reproducibility.
- No direct evidence is recorded for reaching the live desktop.
- No direct evidence is recorded for completing installation or booting the installed system.
- The alpha ISO must not be presented as production ready or publicly released based only on the current record.

## Final Decision

- **ISO compilation and checksum status:** **PASS**
- **Bootloader-path validation:** **PARTIAL**
- **Live desktop validation:** **NOT TESTED**
- **Installer validation:** **NOT TESTED**
- **Installed-system validation:** **NOT TESTED**
- **Reproducibility validation:** **NOT TESTED**
- **Overall release-validation status:** **PARTIAL**

**Decision:** GenixBit OS `0.1.0-alpha` has a successfully compiled ISO with a verified checksum and recorded hybrid boot structures. Interactive live-session, installation, installed-system, hardware-function and reproducibility testing must be completed before the ISO is published or Phase 1 is declared fully complete.
