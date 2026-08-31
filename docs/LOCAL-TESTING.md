# Build and Test GenixBit OS Locally

This guide is the supported developer path for turning a clean checkout into a bootable GenixBit OS ISO and testing that ISO without modifying your host operating system.

## What you need

### To build an ISO

The ISO builder intentionally requires a Linux host whose Ubuntu codename matches `TARGET_UBUNTU_VERSION` in `args.sh`. The current target is Ubuntu 26.04 (`resolute`).

The build needs sudo access for debootstrap, chroot, mounts, and ISO assembly. Run the Makefile as your normal user; it will request sudo credentials when required.

### To boot an existing ISO

The local VM runner supports QEMU on Linux and macOS.

Ubuntu/Debian QEMU packages:

```bash
sudo apt install qemu-system-x86 qemu-utils
```

macOS with Homebrew:

```bash
brew install qemu
```

The current GenixBit OS ISO is x86_64. On Apple Silicon Macs it can still run through QEMU software emulation, but it will be significantly slower than native virtualization.

## 1. Build from a clean checkout

```bash
git clone https://github.com/GenixBit/genixbit-os.git
cd genixbit-os
make current
```

`make current` now performs the complete local sequence:

1. Validates the Ubuntu build host.
2. Requests sudo credentials once.
3. Installs any missing ISO and standard Debian package-build dependencies.
4. Builds every native GenixBit package from its repository `debian/` metadata with `dpkg-buildpackage`.
5. Places only generated `.deb` outputs into `packages/build-debs/`.
6. Runs the OS image builder.
7. Writes the resulting ISO and release-side build artifacts under `dist/`.

Using the real Debian packaging rules preserves runtime dependencies, package relationships, package-specific install manifests, maintainer scripts, and debhelper substitutions. Generated package and ISO outputs are ignored by Git.

## 2. Boot the newest ISO in a local VM

After a successful build, run this as your normal user:

```bash
make vm
```

The VM runner automatically selects a `dist/GenixBitOS-*.iso` and creates a persistent test disk at:

```text
.local-artifacts/genixbit-test.qcow2
```

The default VM has 4 virtual CPUs, 4096 MiB RAM, and a 40 GiB persistent disk. The disk is created only when it does not already exist; the runner never overwrites an existing VM disk.

## Boot a specific ISO

You can test an ISO that was built elsewhere without running the local ISO builder:

```bash
bash tools/local/run-vm.sh --iso /path/to/GenixBitOS.iso
```

This is the recommended path on macOS when the ISO was produced on the supported Ubuntu build host.

## Give the VM more resources

```bash
bash tools/local/run-vm.sh --memory 8192 --cpus 8
```

You can also choose a separate persistent disk:

```bash
bash tools/local/run-vm.sh \
  --disk "$HOME/GenixBitVMs/development.qcow2" \
  --disk-size 64G
```

## Acceleration

The runner selects acceleration conservatively:

- Linux with usable `/dev/kvm`: KVM.
- Intel macOS: HVF.
- Apple Silicon running the current x86_64 ISO: TCG emulation.
- Other hosts: TCG fallback.

## Local smoke-test checklist

After the VM opens, verify at least:

- The ISO reaches the GenixBit boot menu.
- The live desktop reaches a usable session.
- Top bar, dock, launcher, Files, Settings, and Control Center open.
- Keyboard and pointer input work.
- Network access works in the guest.
- Audio devices are visible to the desktop stack.
- The installer detects the VM disk and clearly identifies the destructive target before installation.
- Installation completes to the VM disk.
- A reboot can boot the installed GenixBit OS from the persistent disk.
- GenixAI and privileged actions still enforce their expected permission/confirmation boundaries.

## Cleaning generated build output

```bash
make clean
```

This removes generated ISO/build/package output. Cleanup is restricted to known build directories inside the repository. It intentionally does **not** remove `.local-artifacts/`, so your persistent installed test VM is preserved.

To reset the VM completely, remove its qcow2 disk yourself only when you intentionally want to destroy that local test installation.

## Release safety

Local VM testing is developer validation only. It does not publish a release, update release provenance, create or move tags, sign artifacts, or replace the repository's official release-validation process.
