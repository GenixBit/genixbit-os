# GenixBit OS Baseline ISO Build Validation Log

This document serves as the standardized QA test matrix and validation log template for testing baseline **GenixBit OS** ISO builds.

---

## 1. Build Metadata

- **Build Date**: `Not tested`
- **Commit SHA**: `Not tested`
- **Host Ubuntu Version & Codename**: `Ubuntu 26.04 LTS (resolute)`
- **Host Architecture**: `amd64`
- **Build Orchestrator Command**: `make bootstrap && make`
- **Build Result**: `[ ] Pending First Human Validation`

---

## 2. Image Verification

- **ISO Filename**: `GenixBitOS-0.1.0-alpha-YYMMDDHHMM.iso`
- **ISO File Size**: `Not tested`
- **SHA-256 Checksum**: `Not tested`
- **Media Integrity Verification (`md5sum.txt`)**: `[ ] Not tested`

---

## 3. Environment & Boot Testing

| Test Case | Target Environment | Status | Notes |
| :--- | :--- | :---: | :--- |
| **UEFI Boot Test** | QEMU / KVM (OVMF UEFI) | [ ] Not tested | Verify GRUB boot menu and kernel boot parameter loading |
| **Legacy BIOS Boot Test** | QEMU / KVM (SeaBIOS) | [ ] Not tested | Verify legacy BIOS boot loader and isolinux fallback |
| **Live-Session Desktop** | QEMU / Bare Metal | [ ] Not tested | Verify GNOME Shell desktop, display manager, and live user initialization |
| **Installer Launch** | Ubiquity / Live Environment | [ ] Not tested | Launch installer from live desktop icon / terminal |
| **Disk Installation** | QEMU / KVM 30GB Virtual Disk | [ ] Not tested | Complete clean partition formatting and target disk extraction |
| **Installed-System Reboot** | Installed Target System | [ ] Not tested | Reboot installed OS, verify bootloader removal of live casper medium |

---

## 4. Hardware & Subsystem Validation

| Subsystem | Test Description | Status | Notes |
| :--- | :--- | :---: | :--- |
| **Networking** | NetworkManager interface up, DHCP acquisition, `ping 1.1.1.1` | [ ] Not tested | |
| **Audio** | PipeWire / ALSA audio output device recognition | [ ] Not tested | |
| **Display & Graphics** | Wayland compositor rendering, resolution switching, multi-monitor | [ ] Not tested | |
| **APT Update** | `sudo apt update` against configured repositories | [ ] Not tested | |
| **Package Validation** | Dependency resolution of installed base packages | [ ] Not tested | |

---

## 5. Known Issues & Observations

*(Record any build warnings, kernel trace logs, missing drivers, or unexpected behavior observed during validation)*

- None recorded yet (Validation Pending).

---

## 6. Final Assessment

- **Overall Result**: `[ ] PASS` / `[ ] FAIL` / `[x] VALIDATION PENDING`
- **Evaluator**: `Pending Human Validation on Ubuntu 26.04 amd64 Host`
- **Date**: `Pending`
