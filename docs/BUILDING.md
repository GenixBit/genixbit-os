# Building GenixBit OS

This guide details host environment requirements, dependency setup, configuration options, build commands, and troubleshooting for **GenixBit OS**.

---

## Host Requirements

> [!IMPORTANT]
> **Host OS Matching Requirement**: The build system requires an **Ubuntu Linux host environment** running the exact release codename as the target distribution (currently `resolute` / Ubuntu 26.04).

* **Supported Host Operating System**: Ubuntu Linux matching target codename `resolute`
* **Target Architecture**: `amd64` (x86_64)
* **Required RAM**: Minimum 8 GB; 16 GB recommended for faster SquashFS compression
* **Required Storage**: At least 30 GB free on a Linux filesystem
* **Privileges**: Standard user account with `sudo` privileges

> [!WARNING]
> **macOS and Windows Hosts**: Do not attempt to build GenixBit OS directly on macOS or Windows filesystems. Use an Ubuntu `amd64` virtual machine, cloud server, or bare-metal host matching the target release.

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

Alternatively, run `make bootstrap` to validate the environment and install missing packages.

---

## Step-by-Step Build Instructions

### 1. Environment Bootstrap and Validation

```bash
make bootstrap
```

### 2. Configure Build Parameters

Use the optional terminal interface to inspect or adjust `args.sh`:

```bash
make menuconfig
```

Confirm the alpha version before building:

```bash
grep '^export TARGET_BUILD_VERSION=' args.sh
```

Expected value:

```text
export TARGET_BUILD_VERSION="0.1.0-alpha"
```

### 3. Execute the Build

```bash
make 2>&1 | tee build-0.1.0-alpha.log
```

The build pipeline will:

1. Clean previous build artifacts from `new_building_os/` and `image/`.
2. Run `debootstrap` to download the Ubuntu base system.
3. Mount `/dev`, `/run`, `/proc`, `/sys`, and `/dev/pts` into the chroot.
4. Execute `mods/install_all_mods.sh` inside the chroot environment.
5. Compress the root filesystem into `filesystem.squashfs` using Zstandard.
6. Generate GRUB UEFI and BIOS boot components.
7. Assemble the bootable ISO and checksum under `dist/`.

---

## Build Output

Expected output naming:

```text
dist/GenixBitOS-0.1.0-alpha-YYMMDDHHMM.iso
dist/GenixBitOS-0.1.0-alpha-YYMMDDHHMM.sha256
```

Inspect the generated artifacts:

```bash
ls -lh dist/
sha256sum dist/*.iso
```

Do not commit generated ISO files, checksums, build directories, or logs to Git.

---

## Testing the Generated ISO

Record every test result in [`TESTING.md`](TESTING.md).

### QEMU/KVM

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -cpu host \
  -smp 4 \
  -cdrom dist/GenixBitOS-0.1.0-alpha-*.iso \
  -boot d
```

Validate at minimum:

* UEFI boot
* Legacy BIOS boot
* Live-session startup
* Installer launch
* Installation to a virtual disk
* Reboot into the installed system
* Networking, audio, display, shutdown, and restart
* `apt update` and upstream package dependency resolution

### USB Flash Drive Deployment

> [!CAUTION]
> Confirm the target device path carefully. This command permanently overwrites the selected device.

```bash
sudo dd if=dist/GenixBitOS-0.1.0-alpha-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## Cleaning Up Build Artifacts

```bash
make clean
```

Or run:

```bash
./clean_all.sh
```
