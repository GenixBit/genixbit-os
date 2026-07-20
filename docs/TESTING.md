# GenixBit OS Baseline Testing Record

Use this document to record the first `0.1.0-alpha` build and virtual-machine validation. Do not mark a test as passed until it has been performed and evidence has been recorded.

## Build Information

| Field | Value |
| --- | --- |
| Build date | Pending Host Execution |
| Commit SHA | `532d83c` |
| Host Ubuntu version | Ubuntu 26.04 LTS (Required) |
| Host codename | `resolute` (Required) |
| Host architecture | `amd64` / `x86_64` (Required) |
| CPU and RAM | 8 GB minimum (16 GB recommended) |
| Build result | Awaiting Ubuntu `amd64` Host Build |
| ISO filename | `GenixBitOS-0.1.0-alpha-YYMMDDHHMM.iso` |
| ISO size | Pending |
| SHA-256 | Pending |
| Build duration | Pending |

## Environment Audit

- [x] Identity variables verified in `args.sh` (`genixbitos` / `GenixBitOS` / `0.1.0-alpha` / `resolute`)
- [x] Temporary upstream repository dependencies preserved (`packages.anduinos.com` / `anduinos-apt-config`)
- [x] Syntax validation (`bash -n`) passed for all 17 tracked shell scripts
- [x] Repository Quality CI workflow (`.github/workflows/quality.yml`) active
- [!] **Host Architecture Audit**: Executed on macOS `arm64` (`Darwin`). **Full ISO build halted** per distribution engineering rules (requires Ubuntu 26.04 `resolute` `amd64` host).

## Build Validation

- [ ] `make bootstrap` completed successfully
- [ ] `make` completed successfully
- [ ] ISO was created under `dist/`
- [ ] SHA-256 checksum file was created
- [ ] ISO checksum was independently verified
- [ ] No secrets, private keys, credentials, or local developer files were included
- [ ] A second clean build was completed for reproducibility comparison
- [ ] Repeated-build differences were reviewed and documented

## Boot and Live-Session Validation

- [ ] UEFI boot
- [ ] Legacy BIOS boot
- [ ] GRUB menu displayed correctly
- [ ] Live session reached the desktop
- [ ] Correct GenixBit OS name appeared in user-facing locations
- [ ] Live hostname was correct
- [ ] Keyboard and locale selection worked
- [ ] Display resolution and graphics worked
- [ ] Wired networking worked
- [ ] Wireless networking worked or was recorded as unavailable in the test VM
- [ ] Audio worked or was recorded as unavailable in the test VM
- [ ] Shutdown worked
- [ ] Restart worked

## Installer Validation

- [ ] Installer launched successfully
- [ ] Installation completed on a blank virtual disk
- [ ] Partitioning completed successfully
- [ ] Bootloader installed successfully
- [ ] System rebooted into the installed OS
- [ ] User account creation worked
- [ ] Login worked after installation

## Installed-System Validation

- [ ] Desktop session started successfully
- [ ] `apt update` completed successfully
- [ ] Upstream AnduinOS package dependencies resolved successfully
- [ ] No broken packages were reported
- [ ] Network connectivity worked
- [ ] Audio and display worked
- [ ] Shutdown and restart worked
- [ ] System logs were reviewed for critical boot errors

## Test Environment

| Component | Value |
| --- | --- |
| Hypervisor | QEMU / KVM / VirtualBox (Target) |
| Firmware mode | UEFI (OVMF) & Legacy BIOS (SeaBIOS) |
| Virtual CPUs | 2-4 cores |
| Memory | 4-8 GB |
| Virtual disk size | 30 GB minimum |
| Graphics adapter | VirtIO / stdvga |
| Network adapter | VirtIO / e1000 |

## Known Issues

- Full ISO compilation (`debootstrap`, `chroot` mount, `mksquashfs`, `xorriso`) cannot run natively on macOS `arm64` host.
- A compatible Ubuntu 26.04 `amd64` build environment is required to execute `make bootstrap && make`.

## Evidence

- Local host environment check: `arm64 Darwin` (macOS 15/16).
- Script syntax verification: All 17 tracked shell scripts passed `bash -n`.
- Identity verification: `args.sh` correctly configured for `GenixBitOS` version `0.1.0-alpha`.

## Final Decision

**Status:** Awaiting Execution on Compatible Host

**Decision:** The `0.1.0-alpha` build validation framework is fully prepared. The actual ISO compilation and VM testing must be executed on an Ubuntu 26.04 `resolute` `amd64` host before releasing.
