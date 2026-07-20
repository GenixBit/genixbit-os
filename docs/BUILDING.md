# Building GenixBit OS

This guide details host environment requirements, dependency setup, configuration options, build commands, and troubleshooting for **GenixBit OS**.

---

## Host Requirements

> [!IMPORTANT]
> **Host OS Matching Requirement**: The build system requires an **Ubuntu Linux host environment** running the exact release codename as the target distribution (currently `resolute` / Ubuntu 26.04).

* **Supported Host Operating System**: Ubuntu Linux (matching target codename `resolute`)
* **Target Architecture**: `amd64` (x86_64)
* **Required RAM**: Minimum 8 GB (16 GB recommended for faster squashfs compression)
* **Required Storage**: 30 GB free space on a POSIX-compliant filesystem with Linux file permissions
* **Privileges**: Standard user account with passwordless `sudo` privileges

> [!WARNING]
> **macOS & Windows Hosts**: Do NOT attempt to build GenixBit OS directly on macOS or Windows filesystems. macOS APFS and Windows NTFS do not support Linux device nodes, ext4 filesystem flags, or root chroot permissions. Use an Ubuntu `amd64` virtual machine or bare-metal host.

---

## Required Dependencies

Install build dependencies on your Ubuntu host:

```bash
sudo apt-get update
sudo apt-get install -y \
  binutils \
  curl \
  debootstrap \
  gnupg \
  squashfs-tools \
  xorriso \
  grub-pc-bin \
  grub-efi-amd64 \
  grub2-common \
  mtools \
  dosfstools
```

Alternatively, run `make bootstrap` to automatically verify and install missing packages.

---

## Step-by-Step Build Instructions

### 1. Environment Bootstrap & Validation
Verify host OS compatibility and missing dependency packages:
```bash
make bootstrap
```

### 2. Configure Build Parameters (Optional)
Use the interactive Terminal User Interface (TUI) to inspect or adjust build parameters in `args.sh`:
```bash
make menuconfig
```

### 3. Execute the Build
Start the automated build pipeline:
```bash
make
```

The build pipeline will:
1. Clean previous build artifacts (`new_building_os/`, `image/`).
2. Run `debootstrap` to download the baseline Ubuntu system.
3. Mount host virtual filesystems (`/dev`, `/run`, `/proc`, `/sys`).
4. Execute `mods/install_all_mods.sh` inside the chroot environment.
5. Compress the root filesystem into `filesystem.squashfs` using `zstd`.
6. Generate GRUB UEFI/BIOS bootloaders and assemble the ISO image.

---

## Build Output

Upon successful completion, output artifacts are placed under `dist/`:

```text
dist/GenixBitOS-0.1.0-YYMMDDHHMM.iso      # Bootable ISO image
dist/GenixBitOS-0.1.0-YYMMDDHHMM.sha256   # SHA-256 checksum file
```

---

## Testing the Generated ISO

### Virtual Machine Testing (QEMU / KVM)
Test the generated ISO in QEMU:
```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -smp 4 \
  -cdrom dist/GenixBitOS-0.1.0-*.iso \
  -boot d
```

### USB Flash Drive Deployment
Write the ISO to a USB flash drive (replace `/dev/sdX` with your target USB device path):
```bash
sudo dd if=dist/GenixBitOS-0.1.0-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## Cleaning Up Build Artifacts

To unmount chroot filesystems and clean up build workspace directories:
```bash
make clean
```

Or execute the cleanup script directly:
```bash
./clean_all.sh
```
