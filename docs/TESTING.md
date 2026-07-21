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

## Frozen Validation Candidate

`main` is a moving development branch. The validation build uses the immutable candidate branch created according to [`VALIDATION-CANDIDATE.md`](VALIDATION-CANDIDATE.md).

**Active validation cycle:**

| Field | Value |
| --- | --- |
| Candidate branch | `validation/0.1.0-alpha-candidate` |
| Candidate SHA (full 40-char) | `90fef31a4ede0728ef9fbcbff1c226de4327a1b8` |
| Original evidence branch | `test/validate-0.1.0-alpha-candidate` |
| Blocked-attempt evidence PR | #17, merged 2026-07-21 |
| Cycle started | 2026-07-21 |

| Field | Status | Requirement / Evidence |
| --- | :---: | --- |
| Candidate branch created | **PASS** | `validation/0.1.0-alpha-candidate` exists at SHA `90fef31a4ede0728ef9fbcbff1c226de4327a1b8` |
| Full candidate SHA recorded | **PASS** | `90fef31a4ede0728ef9fbcbff1c226de4327a1b8` verified with `git rev-parse HEAD` |
| Candidate checkout clean | **PASS** | `git status --porcelain --untracked-files=normal` returned empty during candidate selection |
| Evidence branch created | **PASS** | `test/validate-0.1.0-alpha-candidate` branched from the frozen candidate SHA |
| First host attempt | **FAIL** | The attempt used macOS `arm64` (`Darwin 25F84`); `tools/vm/setup-host.sh` reported 13 failures. This is a blocked-host record, not candidate validation. |
| Blocked-attempt evidence recorded | **PASS** | PR #17 merged the factual unsupported-host result; it did not build or validate a candidate ISO |
| Clean ISO built from candidate | **NOT TESTED** | Requires Ubuntu 26.04 `resolute` `amd64` build host |
| Candidate ISO filename, size, and SHA-256 recorded | **NOT TESTED** | Do not reuse historical artifact values |
| Generated checksum independently matched | **NOT TESTED** | Calculated digest must match the generated checksum file |
| BIOS/UEFI metadata inspected | **NOT TESTED** | Requires `verify-runtime.sh` on the approved build host |
| EFI fallback image verified | **NOT TESTED** | Confirm `EFI/BOOT/BOOTX64.EFI` inside `/isolinux/efiboot.img` |
| Candidate artifact used for every runtime test | **NOT TESTED** | BIOS, UEFI, installer, and installed-system tests must use one recorded artifact |

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
| Validation host helper exists | **PASS** | `tools/vm/setup-host.sh` is present; runtime execution remains required |
| Candidate build/preflight orchestrator exists | **PASS** | `tools/vm/verify-runtime.sh` enforces an expected SHA and records private preflight evidence |
| Machine-readable release status exists | **PASS** | `docs/VALIDATION-STATUS.env` records current candidate gate values |
| Candidate release-evidence CI enforcement exists | **PASS** | `tools/validation/check-release-evidence.sh` blocks incomplete `test/validate-*` pull requests |
| Complete candidate ISO filesystem secret scan | **NOT TESTED** | Candidate artifact does not yet exist |
| Second same-candidate clean build performed | **NOT TESTED** | No second candidate build is recorded |
| Reproducibility comparison performed | **NOT TESTED** | No same-candidate comparison exists |

A QEMU dry run is not boot evidence. Script presence and Bash syntax validation are not proof that the host or guest validation succeeded.

## Candidate Boot and Live-Session Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| UEFI boot path | **NOT TESTED** | Candidate ISO must reach the live desktop through OVMF |
| Legacy BIOS boot path | **NOT TESTED** | Candidate ISO must reach the live desktop through SeaBIOS |
| GRUB menu displayed interactively | **NOT TESTED** | Direct display evidence required |
| Kernel completed boot | **NOT TESTED** | Direct console or graphical evidence required |
| Live desktop reached | **NOT TESTED** | Direct graphical evidence required |
| Keyboard and locale worked | **NOT TESTED** | Direct interaction required |
| Display and graphics worked | **NOT TESTED** | Direct interaction required |
| Network and DNS worked | **NOT TESTED** | Live connectivity result required |
| Audio worked | **NOT TESTED** | Playback or documented hypervisor limitation required |
| Shutdown and restart worked | **NOT TESTED** | Runtime result required |
| User-facing identity visually confirmed | **NOT TESTED** | Record GenixBit identity and remaining upstream branding |

## Installer Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Candidate installer content inspected | **NOT TESTED** | Inspect the newly built candidate artifact |
| Separate clean BIOS and UEFI virtual disks prepared | **NOT TESTED** | Candidate test disks must be created outside Git |
| Installer launched interactively | **NOT TESTED** | Direct installer session required |
| Language, keyboard, and timezone selection worked | **NOT TESTED** | Direct interaction required |
| Partitioning completed | **NOT TESTED** | Completed target-disk operation required |
| Installation completed | **NOT TESTED** | Completion evidence required |
| Bootloader installed to target disk | **NOT TESTED** | Target-disk boot required |
| User account creation and login worked | **NOT TESTED** | Installed-system login required |

## Installed-System Validation

| Test | Status | Missing evidence |
| --- | :---: | --- |
| Installed BIOS system booted from virtual disk | **NOT TESTED** | Post-install BIOS boot required |
| Installed UEFI system booted from virtual disk | **NOT TESTED** | Post-install UEFI boot required |
| Desktop session started | **NOT TESTED** | Direct graphical evidence required |
| `sudo apt update` succeeded | **NOT TESTED** | Installed-system output required |
| No broken installed packages | **NOT TESTED** | `apt-get check` and `dpkg --audit` required |
| Network and DNS worked | **NOT TESTED** | Installed-system result required |
| Display and audio worked | **NOT TESTED** | Installed-system interaction required |
| Shutdown and restart worked | **NOT TESTED** | Runtime result required |
| Critical boot logs reviewed | **NOT TESTED** | `journalctl -p 3 -b` summary required |
| GenixBit base-files package installed correctly | **NOT TESTED** | Package scaffolding exists, but candidate build/install evidence is required |

## Evidence Retained

- Successful historical Ubuntu 26.04 `resolute` amd64 ISO compilation from commit `2ed584c`.
- Historical ISO filename, exact byte size, and matching SHA-256.
- Historical hybrid BIOS/UEFI structure record.
- Repository validation, QEMU launcher, host-readiness helper, candidate preflight tooling, and blocked macOS-host attempt.

Large artifacts, raw build logs, VM disks, screenshots containing private details, and cloud access information must remain outside Git. A private evidence bundle should retain the candidate ISO, checksum, metadata reports, relevant logs, screenshots, VM configuration, and test-operator notes.

## Known Issues and Limitations

- The historical ISO predates current build-pipeline and identity-package work.
- Temporary AnduinOS package dependencies remain in the alpha build.
- `genixbit-os-base-files` currently has scaffolding and templates; candidate build, package installation, upgrade, and rollback evidence is pending.
- Complete user-facing GenixBit branding is not implemented.
- No frozen candidate ISO is recorded.
- No direct evidence is recorded for reaching the candidate live desktop.
- No direct evidence is recorded for completing candidate installation or booting the installed system.
- No second same-candidate clean build has established reproducibility.
- The alpha ISO must not be publicly released based on the current record.

## Final Decision

- **Historical ISO compilation and checksum:** **PASS**
- **Frozen candidate branch and SHA verification:** **PASS**
- **First validation host attempt:** **FAIL** — macOS `arm64` was correctly rejected; this does not retire the candidate
- **Blocked-attempt evidence record:** **PASS** — PR #17 merged the blocker only, not successful candidate validation
- **Candidate clean build and preflight:** **NOT TESTED** — awaiting Ubuntu 26.04 `resolute` amd64 build host
- **Candidate live desktop (BIOS):** **NOT TESTED** — awaiting approved host with KVM
- **Candidate live desktop (UEFI):** **NOT TESTED** — awaiting approved host with KVM
- **Candidate installer (UEFI then BIOS):** **NOT TESTED** — awaiting candidate live session
- **Candidate installed system:** **NOT TESTED** — awaiting completed installation
- **Candidate APT and package health:** **NOT TESTED** — awaiting installed system
- **GenixBit base-files package status:** **PARTIAL** — source scaffolding and templates exist, but package integration and ownership remain untested
- **Second same-candidate build:** **NOT TESTED** — awaiting approved build host
- **Candidate reproducibility comparison:** **NOT TESTED** — awaiting both builds
- **Overall release-validation status:** **PARTIAL**

**Decision:** GenixBit OS `0.1.0-alpha` has a frozen candidate at `90fef31a4ede0728ef9fbcbff1c226de4327a1b8`, but no candidate ISO has been produced. PR #17 records only that the macOS `arm64` execution environment was unsupported. The next attempt must use a clean checkout of the same frozen candidate on Ubuntu 26.04 `resolute` `amd64` with KVM. All direct runtime and reproducibility gates remain pending, and the ISO must not be published.
