# GenixBit OS Baseline Testing Record

This document records evidence for `0.1.0-alpha`. A status is `PASS` only when the specific activity was directly performed and recorded. Package presence, configuration files, manifests, dry runs, or bootloader files do not by themselves prove that a live desktop, installer, or installed system worked interactively.

## Status Vocabulary

- **PASS** — directly performed and recorded.
- **PARTIAL** — some relevant evidence exists, but the complete user-visible test is not recorded.
- **FAIL** — performed and failed.
- **NOT TESTED** — no direct execution evidence is recorded.

## Historical First-Build Evidence

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

This artifact is retained as historical proof that commit `2ed584c` compiled. It is not sufficient to validate current `main`, because later commits changed the ISO build pipeline, including EFI image creation.

Cloud resource identifiers, public build-host addresses, SSH access details, and administrator paths belong in a private GenixBit operations record and must not be committed here.

## Current-Main Validation Target

| Field | Status | Requirement / Evidence |
| --- | :---: | --- |
| Exact current `main` commit recorded | **PASS** | `0bce5b14115fa01b4dffa02a726d22c51c732a42` recorded as validation starting commit |
| Clean ISO built from that exact commit | **NOT TESTED** | Requires execution on Ubuntu 26.04 `resolute` `amd64` build host |
| Current ISO filename, size, and SHA-256 recorded | **NOT TESTED** | Do not reuse historical `2ed584c` ISO values |
| Current ISO BIOS/UEFI metadata inspected | **NOT TESTED** | Confirm boot structures of fresh build |
| Current EFI fallback image verified | **NOT TESTED** | Confirm `EFI/BOOT/BOOTX64.EFI` in fresh artifact |
| Current artifact used for every runtime test | **NOT TESTED** | Runtime BIOS, UEFI, installer & target-disk tests pending fresh build |

See [`VM-VALIDATION.md`](VM-VALIDATION.md) for the required sequence.

## Historical Build and Artifact Validation

| Test | Status | Recorded evidence |
| --- | :---: | --- |
| Host codename and architecture matched the target | **PASS** | Ubuntu 26.04 `resolute`, `x86_64` recorded |
| `make bootstrap` completed | **PASS** | Recorded in merged PR #8 |
| `make` completed | **PASS** | Historical ISO artifact was produced |
| ISO filename and byte size recorded | **PASS** | Historical values recorded above |
| Checksum file created | **PASS** | Historical `.sha256` filename recorded |
| SHA-256 independently matched | **PASS** | Historical digest recorded above |
| Hybrid BIOS/UEFI structures included | **PASS** | Historical ISO structures recorded |
| Repository changes contained no committed ISO or private key | **PASS** | Repository Quality workflow passed |
| VM host readiness helper | **PASS** | `tools/vm/setup-host.sh` implemented and checked |
| VM QEMU harness dry run | **PASS** | BIOS and UEFI command construction checked only |
| Complete ISO filesystem secret scan | **NOT TESTED** | No scan report is recorded |
| Second clean build performed | **NOT TESTED** | No same-commit second build is recorded |
| Reproducibility comparison performed | **NOT TESTED** | No second-build comparison exists |

A QEMU dry run is not boot evidence.

## Current Boot and Live-Session Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Current-main UEFI boot path | **NOT TESTED** | A fresh current-main ISO must reach the live desktop through OVMF |
| Current-main Legacy BIOS boot path | **NOT TESTED** | A fresh current-main ISO must reach the live desktop through SeaBIOS |
| GRUB menu displayed interactively | **NOT TESTED** | Direct display evidence required |
| Kernel completed boot | **NOT TESTED** | Console or screenshot evidence required |
| Live desktop reached | **NOT TESTED** | Direct graphical evidence required |
| Keyboard and locale worked | **NOT TESTED** | Direct interaction required |
| Display and graphics worked | **NOT TESTED** | Direct interaction required |
| Network and DNS worked | **NOT TESTED** | Live connectivity result required |
| Audio worked | **NOT TESTED** | Playback/device result required |
| Shutdown and restart worked | **NOT TESTED** | Runtime result required |
| User-facing identity visually confirmed | **NOT TESTED** | Record GenixBit and remaining upstream branding |

## Installer Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Installer packages and slideshow assets present | **PASS** | Recorded for the historical image only |
| Separate clean virtual disks prepared | **NOT TESTED** | Prepare fresh BIOS and UEFI disks for the current artifact |
| Installer launched interactively | **NOT TESTED** | Direct installer session required |
| Language, keyboard, and timezone selection worked | **NOT TESTED** | Direct interaction required |
| Partitioning completed | **NOT TESTED** | Completed target-disk operation required |
| Installation completed | **NOT TESTED** | Completion log or screenshot summary required |
| Bootloader installed to the target disk | **NOT TESTED** | Target-disk boot required |
| User account creation and login worked | **NOT TESTED** | Installed-system login required |

## Installed-System Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Installed system booted from virtual disk | **NOT TESTED** | Post-install boot required |
| Desktop session started | **NOT TESTED** | Direct graphical evidence required |
| `sudo apt update` succeeded | **NOT TESTED** | Installed-system output required |
| No broken installed packages | **NOT TESTED** | `apt-get check` and `dpkg --audit` required |
| Network and DNS worked | **NOT TESTED** | Installed-system result required |
| Display and audio worked | **NOT TESTED** | Installed-system interaction required |
| Shutdown and restart worked | **NOT TESTED** | Runtime result required |
| Critical boot logs reviewed | **NOT TESTED** | `journalctl -p 3 -b` summary required |

## Evidence Retained

- Successful historical Ubuntu 26.04 `resolute` amd64 ISO compilation from commit `2ed584c`.
- Historical ISO filename, exact byte size, and matching SHA-256.
- Historical hybrid BIOS/UEFI structure record.
- QEMU harness and host-readiness tooling.
- Repository Quality workflow success for merged changes.

Large artifacts, raw build logs, VM disks, screenshots containing private details, and cloud access information must remain outside Git. A private evidence bundle should retain the current validation ISO, checksum, relevant logs, screenshots, VM configuration, and test-operator notes.

## Known Issues and Limitations

- The historical ISO predates current `main` build-pipeline changes.
- Temporary AnduinOS package dependencies remain in the alpha build.
- Complete user-facing GenixBit branding is not implemented.
- No fresh current-main validation ISO is recorded.
- No direct evidence is recorded for reaching the live desktop.
- No direct evidence is recorded for completing installation or booting the installed system.
- No second same-commit clean build has established reproducibility.
- The alpha ISO must not be publicly released based on the current record.

## Final Decision

- **Historical ISO compilation and checksum:** **PASS**
- **Current-main clean validation build:** **NOT TESTED**
- **Current-main live desktop:** **NOT TESTED**
- **Current-main installer:** **NOT TESTED**
- **Current-main installed system:** **NOT TESTED**
- **Current-main reproducibility:** **NOT TESTED**
- **Overall release-validation status:** **PARTIAL**

**Decision:** GenixBit OS `0.1.0-alpha` has a valid historical compilation record. Because the build pipeline changed afterward, a fresh ISO must be built from the exact current `main` commit and used for all direct runtime and reproducibility tests before Phase 1 is complete or an ISO is published.
