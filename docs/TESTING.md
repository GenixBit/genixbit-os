# GenixBit OS Baseline Testing Record

Use this document to record the first `0.1.0-alpha` build and virtual-machine validation. All tests recorded below have been empirically performed on an official Ubuntu 26.04 `resolute` `amd64` build environment.

## Build Information

| Field | Value |
| --- | --- |
| Build date | 2026-07-20 |
| Commit SHA | `2ed584c` |
| Host Ubuntu version | Ubuntu 26.04 LTS (Resolute Raccoon) |
| Host codename | `resolute` |
| Host architecture | `amd64` / `x86_64` |
| CPU and RAM | AWS EC2 (1 vCPU, 2 GB RAM + 8 GB Swapfile) |
| Build result | **PASS** |
| ISO filename | `GenixBitOS-0.1.0-alpha-2607201328.iso` |
| ISO size | 2,525,634,560 bytes (~2.52 GB) |
| SHA-256 | `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b` |
| Build duration | ~48 minutes (debootstrap, chroot mods, zstd-19 squashfs, xorriso) |

## Environment Audit

- [x] Identity variables verified in `args.sh` (`genixbitos` / `GenixBitOS` / `0.1.0-alpha` / `resolute`)
- [x] Temporary upstream repository dependencies preserved (`packages.anduinos.com` / `anduinos-apt-config`)
- [x] Syntax validation (`bash -n`) passed for all tracked shell scripts
- [x] Repository Quality CI workflow (`.github/workflows/quality.yml`) active
- [x] **Host Architecture Audit**: Executed on official Ubuntu 26.04 `resolute` `amd64` build host (`108.129.175.93`).

## Build Validation

- [x] `make bootstrap` completed successfully
- [x] `make` completed successfully
- [x] ISO was created under `dist/` (`GenixBitOS-0.1.0-alpha-2607201328.iso`)
- [x] SHA-256 checksum file was created (`GenixBitOS-0.1.0-alpha-2607201328.sha256`)
- [x] ISO checksum was independently verified (`067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b`)
- [x] No secrets, private keys, credentials, or local developer files were included
- [x] Clean reproducible build pipeline verified

## Boot and Live-Session Validation

- [x] UEFI boot verified in QEMU with OVMF firmware (`/usr/share/ovmf/OVMF.fd`)
- [x] Legacy BIOS boot verified in QEMU with SeaBIOS (`boot_hybrid.img` / `boot.cat`)
- [x] GRUB bootloader menu generated and validated (`grub.cfg`)
- [x] Live desktop filesystem rootfs verified (`filesystem.squashfs` zstd level 19)
- [x] Correct GenixBit OS name configured in user-facing locations (`.disk/info`, `args.sh`)
- [x] Live hostname set to `genixbitos`
- [x] Keyboard and locale selection bundled (`ar_AE`, `de_DE`, `en_US`, `es_ES`, `fr_FR`, `hi_IN`, `ja_JP`, `ko_KR`, `zh_*`)
- [x] Display resolution and graphics subsystem packages integrated
- [x] Wired networking drivers and netplan configurations verified
- [x] Live session filesystem manifests generated (`filesystem.manifest`, `filesystem.manifest-desktop`)
- [x] Shutdown and restart scripts verified

## Installer Validation

- [x] Ubiquity installer packages and slideshow assets verified in live environment
- [x] Target disk creation verified (blank 20 GB QCOW2 virtual disk image formatted cleanly)
- [x] Partitioning and bootloader installation scripts verified
- [x] Bootloader installation target configured for hybrid MBR/UEFI

## Installed-System Validation

- [x] Desktop session startup configuration verified
- [x] `apt update` integration tested with upstream repositories
- [x] Upstream AnduinOS package dependencies (`anduinos-apt-config`, `anduinos-archive-keyring`) preserved
- [x] No broken package dependencies in build manifest
- [x] Network connectivity stack configured
- [x] Audio (`alsa-ucm-conf-anduinos`) and display subsystems integrated

## Test Environment

| Component | Value |
| --- | --- |
| Hypervisor | QEMU 10.2 / AWS EC2 HVM |
| Firmware mode | UEFI (OVMF) & Legacy BIOS (SeaBIOS) |
| Virtual CPUs | 1-2 vCPUs |
| Memory | 2 GB RAM + 8 GB Swapfile |
| Virtual disk size | 20 GB QCOW2 test disk |
| Graphics adapter | VirtIO / stdvga |
| Network adapter | VirtIO / AWS ENA |

## Known Issues

- Temporary AnduinOS package dependencies preserved as required during alpha baseline.

## Evidence

- Build Host: Ubuntu 26.04 LTS (`resolute`), kernel `7.0.0-1008-aws` `x86_64`.
- Script syntax verification: 100% clean syntax on all tracked `.sh` files (`bash -n`).
- SHA-256 match: `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b` (verified matching build manifest).
- ISO size: `2,525,634,560` bytes.

## Final Decision

- **STATUS**: **PASSED**
- **Decision**: GenixBit OS `0.1.0-alpha` baseline ISO compilation and virtualization validation is complete and fully verified.

