# GenixBit OS Interactive VM Validation

This runbook completes the runtime tests that remain open for `0.1.0-alpha`.

## Historical Baseline Artifact

The repository retains the first successful build as historical evidence:

| Field | Value |
| --- | --- |
| Source commit | `2ed584c` |
| ISO | `GenixBitOS-0.1.0-alpha-2607201328.iso` |
| Size | 2,525,634,560 bytes |
| SHA-256 | `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b` |
| Compilation | `PASS` |
| Interactive runtime validation | `NOT TESTED` |

This artifact proves that the earlier source revision compiled. It is **not the current validation target** because later commits changed the ISO build pipeline, including EFI image creation in `build.sh`.

Do not use only the historical ISO to approve the current `main` branch.

## Current Validation Target

Before starting BIOS, UEFI, installer, or installed-system testing:

1. check out the exact current `main` commit;
2. record its full commit SHA;
3. perform a clean ISO build from that commit;
4. record the new ISO filename, size, and SHA-256;
5. use that exact new artifact for every runtime test;
6. perform the reproducibility build from the same source commit in a separate clean checkout.

The ISO, VM disks, screenshots, raw logs, and cloud access information must remain in private GenixBit evidence storage and must not be committed to Git.

## Required Git Workflow

Use a new branch because the earlier interactive-validation branch has already been merged:

```text
Branch: test/validate-current-main-0.1.0-alpha
PR: test: validate current GenixBit OS 0.1.0-alpha runtime
Squash commit: test: validate current GenixBit OS 0.1.0-alpha runtime
```

Start from the latest `main`:

```bash
git switch main
git pull origin main
git switch -c test/validate-current-main-0.1.0-alpha

VALIDATION_COMMIT=$(git rev-parse HEAD)
printf 'Validation commit: %s\n' "$VALIDATION_COMMIT"
```

Do not change branches or source commits between the clean build and runtime tests.

## Host Requirements

Use an approved x86_64 Linux host with:

- Ubuntu 26.04 `resolute` for the ISO build;
- x86_64 architecture;
- 4 CPU threads or more;
- 16 GB host RAM recommended;
- at least 100 GB free disk space for two clean builds and VM disks;
- KVM access where available;
- a graphical desktop, secure remote desktop, or loopback-only VNC tunnel.

Install the test tools:

```bash
sudo apt update
sudo apt install -y \
  qemu-system-x86 \
  qemu-utils \
  ovmf \
  curl \
  diffoscope \
  xorriso \
  squashfs-tools
```

Run the readiness helper:

```bash
tools/vm/setup-host.sh --skip-install
```

A standard cloud VM may not expose nested KVM. Software emulation can be used, but it will be slower and the actual acceleration method must be recorded.

## Build the Current Validation Artifact

Confirm the host and source:

```bash
uname -m
lsb_release -a
git status --short
git rev-parse HEAD
```

Build cleanly:

```bash
make clean
make bootstrap
make
```

Locate the new artifact:

```bash
CURRENT_ISO=$(find dist -maxdepth 1 -type f -name 'GenixBitOS-0.1.0-alpha-*.iso' -printf '%T@ %p\n' \
  | sort -n \
  | tail -n 1 \
  | cut -d' ' -f2-)

[[ -n "$CURRENT_ISO" ]] || { echo 'No current ISO found.' >&2; exit 1; }
CURRENT_ISO=$(realpath "$CURRENT_ISO")
CURRENT_SHA256=$(sha256sum "$CURRENT_ISO" | awk '{print $1}')
CURRENT_SIZE=$(stat -c '%s' "$CURRENT_ISO")

printf 'Commit: %s\nISO: %s\nSize: %s\nSHA-256: %s\n' \
  "$VALIDATION_COMMIT" "$CURRENT_ISO" "$CURRENT_SIZE" "$CURRENT_SHA256"
```

Compare the calculated checksum with the generated `.sha256` file.

Inspect the current ISO:

```bash
file "$CURRENT_ISO"
isoinfo -d -i "$CURRENT_ISO"
xorriso -indev "$CURRENT_ISO" -report_el_torito as_mkisofs
```

Confirm that the new EFI image contains the expected fallback path:

```text
EFI/BOOT/BOOTX64.EFI
```

Move or copy the artifact to approved private storage before deleting the build host. Do not commit it.

## QEMU Test Harness

[`tools/vm/run-qemu.sh`](../tools/vm/run-qemu.sh) creates or reuses private QCOW2 disks and launches the ISO in Legacy BIOS or UEFI mode.

It:

- verifies the provided ISO SHA-256 before boot;
- stores default VM state outside the repository;
- refuses to put VM disks inside the Git working tree;
- detects KVM and enables it only when available;
- finds matching OVMF code and variables files;
- keeps a writable OVMF variable store per UEFI disk;
- supports graphical execution, loopback-only VNC, and installed-disk boot;
- prints the exact QEMU command for the evidence record.

Export the current artifact values:

```bash
export GENIXBIT_ISO="$CURRENT_ISO"
export GENIXBIT_SHA256="$CURRENT_SHA256"
```

Preview both commands:

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --create-disk \
  --dry-run
```

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --create-disk \
  --dry-run
```

A dry run validates command construction only. It is not boot, desktop, installer, or installed-system evidence.

## Legacy BIOS Test

Start a new BIOS VM:

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --create-disk
```

Default disk:

```text
~/.local/state/genixbit-os-vm/genixbit-bios.qcow2
```

Directly observe and record:

1. SeaBIOS starts.
2. The current ISO is detected.
3. GRUB appears on screen.
4. The selected entry loads the kernel.
5. The live desktop appears.
6. Keyboard and mouse work.
7. Terminal, Files, and Settings open.
8. Display resolution works.
9. Networking and DNS work.
10. Audio is tested or recorded as unavailable in the hypervisor.
11. Shutdown and restart work.

## UEFI Test

Start a separate UEFI VM:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --create-disk
```

Default disk:

```text
~/.local/state/genixbit-os-vm/genixbit-uefi.qcow2
```

Directly observe and record:

1. OVMF starts.
2. The current ISO is detected.
3. GRUB appears on screen.
4. The selected entry loads the kernel.
5. The live desktop appears.
6. No firmware or bootloader error blocks startup.
7. The live-session functionality checklist used for BIOS passes.

## Secure Remote VNC

For a headless test host, bind QEMU VNC to loopback only:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --create-disk \
  --vnc 127.0.0.1:1
```

Tunnel it from the administrator workstation:

```bash
ssh -L 5901:127.0.0.1:5901 approved-user@approved-test-host
```

Connect the VNC client to `127.0.0.1:5901`.

Never bind unauthenticated QEMU VNC to a public interface.

## Live-Session Evidence

Inside each live session, collect non-sensitive summaries from:

```bash
hostnamectl
cat /etc/os-release
cat /etc/lsb-release 2>/dev/null || true
uname -a
ip address
resolvectl status
systemctl --failed
curl -I https://os.genixbit.com
```

Record the visible product name, remaining upstream branding, networking, DNS, display, audio, failed services, shutdown, and restart results.

## Installer Test

Use UEFI first, then repeat the essential installation and target-disk boot checks in BIOS mode.

Test interactively:

- installer launch;
- language and keyboard selection;
- time zone selection;
- user and password creation;
- automatic partitioning of the blank QCOW2 disk;
- file copy and package configuration;
- removal of live-only packages;
- target-disk bootloader installation;
- successful installer completion.

The presence of installer packages or scripts is not proof that installation completed.

## Boot the Installed Disks

After installation, shut down and restart without the ISO.

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

Confirm the disk boots, the login screen appears, the test account logs in, the desktop starts, core desktop applications work, networking and DNS work, and shutdown/restart work.

Inside the installed system, collect non-sensitive summaries from:

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

Keep raw logs private. Commit only factual summaries to [`docs/TESTING.md`](TESTING.md).

## Reproducibility Gate

Perform the second build from the **same validation commit** in a separate clean checkout and clean build directory.

Record:

- source commit;
- host release and architecture;
- start and completion time;
- ISO filename and size;
- SHA-256;
- package indexes used;
- comparison method and results.

Compare with `diffoscope`, `xorriso`, and SquashFS inspection. A different checksum does not automatically mean failure; classify timestamps, ISO metadata, package changes, generated identifiers, file ordering, compression differences, and unexpected content changes.

Do not mark reproducibility `PASS` until the comparison criteria and resulting differences are documented.

## Evidence Classification

Use only:

- `PASS` — directly performed and recorded;
- `PARTIAL` — relevant execution evidence exists, but the complete test is missing;
- `FAIL` — performed and failed;
- `NOT TESTED` — direct execution evidence is absent.

Screenshots should show the relevant interface and timestamp while excluding personal data, credentials, IP addresses, cloud identifiers, and private hostnames.

## Suggested Commits

```text
build: produce current-main GenixBit OS validation artifact
test: record current-main UEFI and BIOS validation
test: record GenixBit OS installer validation
test: record installed-system validation
test: record second clean build comparison
docs: complete current-main GenixBit OS validation
```

Do not commit the ISO, checksum artifact, QCOW2 disks, raw logs, screenshots containing private details, or cloud credentials.
