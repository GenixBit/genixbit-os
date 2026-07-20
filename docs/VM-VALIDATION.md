# GenixBit OS Interactive VM Validation

This runbook completes the runtime tests that remain open after the first successful `0.1.0-alpha` ISO compilation.

## Current Verified Artifact

The repository records this first build:

| Field | Value |
| --- | --- |
| ISO | `GenixBitOS-0.1.0-alpha-2607201328.iso` |
| Size | 2,525,634,560 bytes |
| SHA-256 | `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b` |
| Compilation | `PASS` |
| Interactive live desktop | `NOT TESTED` |
| Installer completion | `NOT TESTED` |
| Installed-system boot | `NOT TESTED` |
| Reproducibility | `NOT TESTED` |

The ISO, VM disks, screenshots, raw logs and cloud access information must remain in private GenixBit evidence storage and must not be committed to Git.

## Test Harness

[`tools/vm/run-qemu.sh`](../tools/vm/run-qemu.sh) creates or reuses a private QCOW2 disk and launches the ISO in either Legacy BIOS or UEFI mode.

The script:

- verifies an optional SHA-256 digest before boot;
- stores default VM state outside the repository;
- refuses to place a VM disk inside the Git working tree;
- detects KVM and enables it only when available;
- finds a matching OVMF code and variables pair for UEFI;
- keeps a separate writable OVMF variable store per UEFI disk;
- supports graphical local execution, loopback-only VNC and console-only diagnostics;
- supports booting the installed disk without reattaching the ISO;
- prints the exact QEMU command for the evidence record.

## Host Requirements

Install the required virtualization tools on an approved x86_64 Linux workstation or server:

```bash
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils ovmf
```

Recommended capacity:

- x86_64 host;
- 4 CPU threads or more;
- 8 GB guest memory;
- 40 GB disk per firmware mode;
- KVM access where available;
- a graphical desktop, secure remote desktop or loopback-only VNC tunnel.

A standard cloud VM may not expose nested KVM. Software emulation can test functionality but will be slower.

## Prepare the Artifact

Store the ISO outside the repository, for example:

```text
/srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso
```

Verify it before every test session:

```bash
sha256sum /srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso
```

Expected digest:

```text
067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b
```

## Preview Commands Without Starting QEMU

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --iso /srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso \
  --sha256 067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b \
  --create-disk \
  --dry-run
```

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso /srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso \
  --sha256 067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b \
  --create-disk \
  --dry-run
```

## Legacy BIOS Test

Start a new BIOS VM:

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --iso /srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso \
  --sha256 067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b \
  --create-disk
```

Default disk location:

```text
~/.local/state/genixbit-os-vm/genixbit-bios.qcow2
```

Directly observe and record:

1. SeaBIOS starts.
2. The ISO is detected.
3. GRUB appears on screen.
4. The selected entry loads the kernel.
5. The live desktop appears.
6. Keyboard and mouse work.
7. Terminal, Files and Settings open.
8. Display resolution works.
9. Networking and DNS work.
10. Audio is tested or recorded as unavailable in the hypervisor.
11. Shutdown and restart work.

## UEFI Test

Start a separate UEFI VM:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso /srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso \
  --sha256 067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b \
  --create-disk
```

Default disk location:

```text
~/.local/state/genixbit-os-vm/genixbit-uefi.qcow2
```

Directly observe and record:

1. OVMF starts.
2. The ISO is detected.
3. GRUB appears on screen.
4. The selected entry loads the kernel.
5. The live desktop appears.
6. No firmware, Secure Boot or bootloader error blocks startup.
7. The same live-session functionality checklist used for BIOS passes.

## Secure Remote VNC

For a headless test host, bind QEMU VNC to loopback only:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso /srv/genixbit-private/GenixBitOS-0.1.0-alpha-2607201328.iso \
  --sha256 067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b \
  --create-disk \
  --vnc 127.0.0.1:1
```

Create an SSH tunnel from the administrator workstation:

```bash
ssh -L 5901:127.0.0.1:5901 approved-user@approved-test-host
```

Connect the VNC client to `127.0.0.1:5901`.

Never bind an unauthenticated QEMU VNC display to a public interface.

## Installer Test

Use the UEFI VM first, then repeat the essential installation and disk-boot checks in BIOS mode.

Test interactively:

- installer launch;
- language and keyboard selection;
- time zone selection;
- user and password creation;
- automatic partitioning of the blank QCOW2 disk;
- file copy and package configuration;
- removal of live-only packages;
- bootloader installation;
- successful installer completion.

A package or script existing in the ISO is not proof that the installer completed.

## Boot the Installed Disk

After installation, shut down the VM and restart without the ISO.

UEFI:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --installed \
  --disk ~/.local/state/genixbit-os-vm/genixbit-uefi.qcow2
```

BIOS:

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --installed \
  --disk ~/.local/state/genixbit-os-vm/genixbit-bios.qcow2
```

Confirm:

- the virtual disk boots;
- the login screen appears;
- the test account can log in;
- the desktop starts;
- terminal, Files and Settings work;
- networking and DNS work;
- shutdown and restart work.

Inside the installed system, collect non-sensitive results from:

```bash
hostnamectl
cat /etc/os-release
uname -a
ip address
resolvectl status
systemctl --failed
sudo apt update
sudo apt-get check
dpkg --audit
apt-mark showhold
journalctl -p 3 -b
```

Keep raw logs private. Commit only a factual summary to [`docs/TESTING.md`](TESTING.md).

## Evidence Classification

Use these statuses exactly:

- `PASS` — the action was directly performed and the outcome was recorded.
- `PARTIAL` — some relevant execution evidence exists, but the complete test is missing.
- `FAIL` — the action was performed and failed.
- `NOT TESTED` — direct execution evidence is absent.

Screenshots should show the relevant UI and timestamp while excluding personal data, credentials, IP addresses, cloud identifiers and private hostnames.

## Reproducibility Gate

A second clean build is a separate requirement.

Record the second build’s:

- source commit;
- host release and architecture;
- start and completion time;
- ISO filename and size;
- SHA-256;
- package indexes used;
- comparison method and results.

A different checksum does not automatically mean failure. Review timestamps, ISO metadata, package updates, generated identifiers, file ordering and SquashFS differences with tools such as `diffoscope` and `xorriso`.

Do not mark reproducibility `PASS` until the comparison criteria and resulting differences are documented.

## Git Workflow

Use:

```text
Branch: test/interactive-vm-validation-0.1.0-alpha
PR: test: complete interactive GenixBit OS 0.1.0-alpha validation
Squash commit: test: complete interactive GenixBit OS 0.1.0-alpha validation
```

Suggested evidence commits:

```text
test: record interactive UEFI and BIOS validation
test: record GenixBit OS installer validation
test: record installed-system validation
test: record second clean build comparison
docs: complete GenixBit OS 0.1.0-alpha validation
```

Do not commit the ISO, checksum artifact, QCOW2 disks, raw logs, screenshots containing private details or cloud credentials.
