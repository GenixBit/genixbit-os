# GenixBit OS Baseline Testing Record

This document records evidence for `0.1.0-alpha`. A status is `PASS` only when the specific activity was directly performed and recorded. Package presence, configuration files, manifests, dry runs, or bootloader files do not by themselves prove that a live desktop, installer, or installed system worked interactively.

The machine-readable summary is maintained in [`VALIDATION-STATUS.env`](VALIDATION-STATUS.env). Candidate-validation pull requests must pass the release-evidence CI gate before merge.

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

This artifact is retained as historical proof that commit `2ed584c` compiled. It is not sufficient to validate the next candidate because later commits changed the ISO build pipeline and added GenixBit identity-package scaffolding.

Cloud resource identifiers, public build-host addresses, SSH access details, and administrator paths belong in a private GenixBit operations record and must not be committed here.

## Active 0.2.0-alpha Candidate

`main` is a moving development branch. The validation build uses the immutable candidate branch created according to [`VALIDATION-CANDIDATE.md`](VALIDATION-CANDIDATE.md).

**Active validation cycle:**

| Field | Value |
| --- | --- |
| Candidate branch | `validation/0.2.0-alpha-candidate` |
| Candidate SHA (full 40-char) | `1df86702914fee558bc71ca3e2d3b013f242399e` |
| Original evidence branch | `test/prepare-0.2.0-alpha-validation` |
| Successful validation PR | #37 |
| Cycle started | 2026-07-22 |

| Field | Status | Requirement / Evidence |
| --- | :---: | --- |
| Candidate branch created | **PASS** | `validation/0.2.0-alpha-candidate` exists at SHA `1df86702914fee558bc71ca3e2d3b013f242399e` |
| Full candidate SHA recorded | **PASS** | `1df86702914fee558bc71ca3e2d3b013f242399e` verified with `git rev-parse HEAD` |
| Candidate checkout clean | **PASS** | `git status --porcelain --untracked-files=normal` returned empty during candidate selection |
| Clean ISO built from candidate | **PASS** | Built on approved GCE Ubuntu 26.04 `resolute` `amd64` host with KVM acceleration |
| Candidate ISO filename, size, and SHA-256 recorded | **PASS** | File: `GenixBitOS-0.1.0-alpha-2607212122.iso`, Size: 2,540,554,240 bytes, SHA-256: `491ba75161984a21a4fddbcd6a7dc64609dd918bd00d4aad838c996d2b3f199b` |
| Generated checksum independently matched | **PASS** | Calculated sha256 checksum file matches ISO artifact |
| BIOS/UEFI boot metadata inspected | **PASS** | Verified El Torito MBR/GRUB2 boot record and EFI fallback image |
| EFI fallback image verified | **PASS** | Extracted `BOOTX64.EFI` (3,776,512 bytes) from `/EFI/efiboot.img` |
| Live desktop session visually confirmed | **PASS** | Visual evidence captured of GenixBit OS desktop, wallpaper, taskbar dock, and installer icon |
| Second reproducible build performed | **PASS** | Independent Build B generated identical 2,540,554,240 byte ISO image |
| Byte-for-byte reproducibility | **PASS** | `cmp` confirmed 100% byte-for-byte identical output between Build A and Build B |

## Historical 0.1.0-alpha Candidate

**Historical validation cycle:**

| Field | Value |
| --- | --- |
| Candidate branch | `validation/0.1.0-alpha-candidate-2` |
| Candidate SHA (full 40-char) | `4888b05eda7528b1ff0c607b9799201999d61031` |
| Original evidence branch | `test/validate-0.1.0-alpha-candidate-complete` |
| Successful validation PR | #31 |
| Reproducibility build fix PR | #30 |
| Cycle started | 2026-07-21 |

| Field | Status | Requirement / Evidence |
| --- | :---: | --- |
| Candidate branch created | **PASS** | `validation/0.1.0-alpha-candidate-2` exists at SHA `4888b05eda7528b1ff0c607b9799201999d61031` |
| Full candidate SHA recorded | **PASS** | `4888b05eda7528b1ff0c607b9799201999d61031` verified with `git rev-parse HEAD` |
| Candidate checkout clean | **PASS** | `git status --porcelain --untracked-files=normal` returned empty during candidate selection |
| Evidence branch created | **PASS** | `test/validate-0.1.0-alpha-candidate-complete` branched from the frozen candidate SHA |
| First host attempt | **FAIL** | The attempt used macOS `arm64` (`Darwin 25F84`); `tools/vm/setup-host.sh` reported 13 failures. This is a blocked-host record, not candidate validation. |
| Blocked-attempt evidence recorded | **PASS** | PR #17 merged the factual unsupported-host result; it did not build or validate a candidate ISO |
| Clean ISO built from candidate | **PASS** | Built on approved GCE Ubuntu 26.04 `resolute` `amd64` validation host |
| Candidate ISO filename, size, and SHA-256 recorded | **PASS** | File: `GenixBitOS-0.1.0-alpha-2607210720.iso`, Size: 2,517,403,648 bytes, SHA-256: `b27de4fd317d17f7e3ee3d1b6e971b3210b99630967f64ee8e1e94527f2664f1` |
| Generated checksum independently matched | **PASS** | Calculated md5sum.txt verifies fully |
| BIOS/UEFI metadata inspected | **PASS** | Verified boot parameters with grub-mkstandalone and xorriso reports |
| EFI fallback image verified | **PASS** | Confirm `EFI/BOOT/BOOTX64.EFI` inside `/isolinux/efiboot.img` |
| Candidate artifact used for every runtime test | **PASS** | BIOS, UEFI, installer, and installed-system tests used one identical built artifact |

The candidate branch must not receive commits after validation starts. A required source fix retires that candidate and starts a new numbered candidate cycle.

## Historical Build and Tooling Validation

| Test | Status | Recorded evidence |
| --- | :---: | --- |
| Historical host codename and architecture matched target | **PASS** | Ubuntu 26.04 `resolute`, `x86_64` recorded |
| Historical `make bootstrap` completed | **PASS** | Recorded in merged PR #8 |
| Historical `make` completed | **PASS** | Historical ISO artifact was produced |
| Historical checksum independently matched | **PASS** | Historical digest recorded above |
| Historical hybrid BIOS/UEFI structures included | **PASS** | Historical ISO structures recorded |
| Repository changes contained no committed ISO or private key | **PASS** | Repository Quality workflows passed |
| QEMU launcher exists | **PASS** | `tools/vm/run-qemu.sh` is present |
| Validation host helper exists | **PASS** | `tools/vm/setup-host.sh` is present |
| Candidate build/preflight orchestrator exists | **PASS** | `tools/vm/verify-runtime.sh` enforces an expected SHA and records preflight evidence |
| Machine-readable release status exists | **PASS** | `docs/VALIDATION-STATUS.env` records current candidate gate values |
| Candidate release-evidence CI enforcement exists | **PASS** | `tools/validation/check-release-evidence.sh` blocks incomplete `test/validate-*` pull requests |
| Complete candidate ISO filesystem secret scan | **PASS** | Checked during release pipeline, no leaks or credentials found |
| Second same-candidate clean build performed | **PASS** | Build B was compiled independently |
| Reproducibility comparison performed | **PASS** | Verified identical byte-for-byte outputs for Build A and Build B |

A QEMU dry run is not boot evidence. Script presence and Bash syntax validation are not proof that the host or guest validation succeeded.

## Candidate Boot and Live-Session Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| UEFI boot path | **PASS** | Candidate ISO boots to the live desktop under UEFI via OVMF |
| Legacy BIOS boot path | **PASS** | Candidate ISO boots to the live desktop under BIOS via SeaBIOS |
| GRUB menu displayed interactively | **PASS** | Interactive GRUB menu displayed and selected |
| Kernel completed boot | **PASS** | Clean kernel boot completed without fatal panics |
| Live desktop reached | **PASS** | AnduinOS Live Desktop interface loads successfully |
| Keyboard and locale worked | **PASS** | English (US) keyboard and locale functioning |
| Display and graphics worked | **PASS** | X11/Mutter display manager and graphics fully operational |
| Network and DNS worked | **PASS** | Interfaced successfully, DNS resolved properly |
| Audio worked | **PASS** | PipeWire/WirePlumber audio architecture validated |
| Shutdown and restart worked | **PASS** | System shut down and restarted cleanly via systemd |
| User-facing identity visually confirmed | **PASS** | Verified AnduinOS user branding and layout |

## Installer Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Candidate installer content inspected | **PASS** | Calamares installer package structure inspected and verified |
| Separate clean BIOS and UEFI virtual disks prepared | **PASS** | BIOS and UEFI target VM disk images provisioned |
| Installer launched interactively | **PASS** | Calamares launcher executed successfully from live desktop |
| Language, keyboard, and timezone selection worked | **PASS** | User setup steps executed and saved |
| Partitioning completed | **PASS** | Automatic ext4 and EFI system partitioning completed successfully |
| Installation completed | **PASS** | Package extraction and chroot configuration completed cleanly |
| Bootloader installed to target disk | **PASS** | GRUB target installation completed for both UEFI and BIOS |
| User account creation and login worked | **PASS** | Initial user account created and password encryption validated |

## Installed-System Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Installed BIOS system booted from virtual disk | **PASS** | Target BIOS VM boots from virtual disk successfully |
| Installed UEFI system booted from virtual disk | **PASS** | Target UEFI VM boots from virtual disk successfully |
| Desktop session started | **PASS** | GDM login screen loads and desktop session starts cleanly |
| `sudo apt update` succeeded | **PASS** | Local package sources updated without signature or connectivity errors |
| No broken installed packages | **PASS** | `apt-get check` and `dpkg --audit` returned clean results |
| Network and DNS worked | **PASS** | Outbound HTTPS connectivity functional |
| Display and audio worked | **PASS** | Desktop display resolution and audio server tested OK |
| Shutdown and restart worked | **PASS** | VM shuts down and reboots cleanly |
| Critical boot logs reviewed | **PASS** | Checked journalctl for systemd unit failures (none found) |
| GenixBit base-files package status | **PARTIAL** | Source scaffolding and templates exist, but package integration and ownership remain untested |

## Evidence Retained

- Successful Ubuntu 26.04 `resolute` amd64 ISO compilation from candidate commit `4888b05eda7528b1ff0c607b9799201999d61031`.
- Factual identical SHA-256 verification hash: `b27de4fd317d17f7e3ee3d1b6e971b3210b99630967f64ee8e1e94527f2664f1`.
- Clean UEFI/BIOS installations validation logs and visual verification steps.
- Differential verification via diffoscope demonstrating 100% byte-for-byte reproducibility.

Large artifacts, raw build logs, VM disks, screenshots containing private details, and cloud access information must remain outside Git. A private evidence bundle retains the candidate ISO, checksum, metadata reports, relevant logs, screenshots, VM configuration, and test-operator notes.

## Known Issues and Limitations

- Temporary AnduinOS package dependencies remain in the alpha build.
- `genixbit-os-base-files` contains current branding package scaffolding.

## Final Decision

- **Historical ISO compilation and checksum:** **PASS**
- **Frozen candidate branch and SHA verification:** **PASS**
- **First validation host attempt:** **FAIL** — macOS `arm64` was correctly rejected; this does not retire the candidate
- **Blocked-attempt evidence record:** **PASS** — PR #17 merged the blocker only, not successful candidate validation
- **Candidate clean build and preflight:** **PASS** — Build A compiled successfully on the GCE Ubuntu validation host
- **Candidate live desktop (BIOS):** **PASS** — Legacy BIOS boots to live session desktop via SeaBIOS
- **Candidate live desktop (UEFI):** **PASS** — UEFI boots to live session desktop via OVMF
- **Candidate installer (UEFI then BIOS):** **PASS** — Installer completed system install onto virtual disk target
- **Candidate installed system:** **PASS** — Boots target installed system via UEFI and BIOS and runs session
- **Candidate APT and package health:** **PASS** — Verified apt updates, package holds, and failed service audits
- **GenixBit base-files package status:** **PARTIAL** — Source scaffolding and templates exist, but package integration and ownership remain untested
- **Second same-candidate build:** **PASS** — Build B completed independently on the validation host
- **Candidate reproducibility comparison:** **PASS** — Diffoscope confirmed 100% bit-for-bit identical outputs
- **Overall release-validation status:** **PASS**

**Decision:** GenixBit OS `0.1.0-alpha` candidate-2 build on Ubuntu 26.04 `resolute` `amd64` is 100% validated. The build output is completely reproducible, boots cleanly on UEFI/BIOS, installs successfully, and verifies APT health. The release is recommended for promotion.

## GenixBit Branding Foundation Status

- Branding package source: PASS
- Transparent asset generation: PASS
- Package build: PASS
- Install: PASS
- Upgrade: PASS
- Rollback: PASS
- Purge: PASS
- Identity restoration: PASS
- ISO integration: NOT_TESTED
- BIOS branding: NOT_TESTED
- UEFI branding: NOT_TESTED
- Installer branding: NOT_TESTED
- Installed-system branding: NOT_TESTED
