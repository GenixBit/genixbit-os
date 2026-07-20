# GenixBit OS Baseline Testing Record

Use this document to record the first `0.1.0-alpha` build and virtual-machine validation. Do not mark a test as passed until it has been performed and evidence has been recorded.

## Build Information

| Field | Value |
| --- | --- |
| Build date | Not recorded |
| Commit SHA | Not recorded |
| Host Ubuntu version | Not recorded |
| Host codename | Not recorded |
| Host architecture | Not recorded |
| CPU and RAM | Not recorded |
| Build result | Not tested |
| ISO filename | Not recorded |
| ISO size | Not recorded |
| SHA-256 | Not recorded |
| Build duration | Not recorded |

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
| Hypervisor | Not recorded |
| Firmware mode | Not recorded |
| Virtual CPUs | Not recorded |
| Memory | Not recorded |
| Virtual disk size | Not recorded |
| Graphics adapter | Not recorded |
| Network adapter | Not recorded |

## Known Issues

No test results have been recorded yet.

## Evidence

Add links or references to non-sensitive logs, screenshots, checksum output, and test notes. Do not commit credentials, private system data, complete machine identifiers, or private keys.

## Final Decision

**Status:** Not tested

**Decision:** The `0.1.0-alpha` build must not be released until the required build, boot, installer, and installed-system checks above are completed and reviewed.
