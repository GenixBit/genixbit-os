# GenixBit OS Interactive VM Validation

This runbook completes the runtime gates for `0.1.0-alpha` using one immutable candidate artifact.

## Historical Baseline

The first successful ISO remains historical evidence:

| Field | Value |
| --- | --- |
| Source commit | `2ed584c` |
| ISO | `GenixBitOS-0.1.0-alpha-2607201328.iso` |
| Size | 2,525,634,560 bytes |
| SHA-256 | `067e38239a9a9c8bda2a085a03ae9c885719e3e92ac58f3a89ff6918e2e65f3b` |
| Compilation | `PASS` |
| Interactive runtime validation | `NOT TESTED` |

This artifact must not approve the next release candidate because later commits changed the build pipeline and added GenixBit package scaffolding.

## Freeze the Candidate

Follow [`VALIDATION-CANDIDATE.md`](VALIDATION-CANDIDATE.md).

After the validation-gate changes are merged, create:

```bash
git switch main
git pull origin main

git switch -c validation/0.1.0-alpha-candidate
git push -u origin validation/0.1.0-alpha-candidate

CANDIDATE_SHA=$(git rev-parse HEAD)
printf 'Candidate SHA: %s\n' "$CANDIDATE_SHA"
```

Do not add commits, merge, rebase, or force-push the candidate branch after validation starts.

When a source fix is required, merge it through a normal reviewed branch, retire the current candidate and start a new numbered candidate.

## Evidence Branch

Use a separate evidence branch created from the same candidate SHA:

```bash
git switch -c test/validate-0.1.0-alpha-candidate "$CANDIDATE_SHA"
```

Recommended pull request:

```text
Title: test: validate GenixBit OS 0.1.0-alpha candidate
Base: main
Head: test/validate-0.1.0-alpha-candidate
Squash commit: test: validate GenixBit OS 0.1.0-alpha candidate
```

The evidence branch may contain documentation and minimal confirmed fixes, but a source fix invalidates the candidate artifact and requires a new candidate cycle.

## Host Requirements

Use an approved host with:

- Ubuntu 26.04 `resolute`;
- x86_64 architecture;
- four CPU threads or more;
- 16 GB RAM recommended;
- 100 GB free disk recommended;
- approved passwordless sudo for the controlled validation account;
- accessible KVM, unless slow software emulation is explicitly approved;
- a local graphical desktop, secure remote desktop or loopback-only VNC tunnel.

The helper installs or checks:

- QEMU system and image tools;
- OVMF;
- `xorriso` and `isoinfo`;
- SquashFS tools;
- `diffoscope`;
- `mtools`;
- `curl` and `file`.

Audit without installing:

```bash
tools/vm/setup-host.sh --skip-install
```

Permit software emulation only when approved:

```bash
tools/vm/setup-host.sh --skip-install --allow-software-emulation
```

## Build and Preflight

Start from a clean checkout at the candidate SHA:

```bash
test "$(git rev-parse HEAD)" = "$CANDIDATE_SHA"
test -z "$(git status --porcelain --untracked-files=normal)"
```

Run:

```bash
tools/vm/verify-runtime.sh --expected-commit "$CANDIDATE_SHA"
```

The orchestrator must:

1. reject a dirty or mismatched checkout;
2. verify the host;
3. run `make clean`, `make bootstrap` and `make`;
4. record the ISO filename, size and SHA-256;
5. compare the calculated digest with the generated checksum file;
6. record ISO and El Torito metadata outside Git;
7. extract `/isolinux/efiboot.img`;
8. verify `EFI/BOOT/BOOTX64.EFI` through `mtools`;
9. write a private manifest outside Git;
10. perform BIOS and UEFI QEMU dry runs;
11. print the direct interactive commands.

A successful orchestrator run proves only candidate build and preflight results. It does not prove live desktop, installer, installed system or reproducibility.

Load the private manifest or record these values securely:

```text
VALIDATION_COMMIT
VALIDATION_ISO
VALIDATION_ISO_SIZE
VALIDATION_SHA256
```

For the commands below:

```bash
export GENIXBIT_ISO="<candidate ISO path>"
export GENIXBIT_SHA256="<candidate SHA-256>"
export GENIXBIT_VM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/genixbit-os-validation/vm"
```

## BIOS Live Session

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --state-dir "$GENIXBIT_VM_STATE" \
  --create-disk
```

Directly observe:

1. SeaBIOS starts.
2. The candidate ISO is detected.
3. GRUB is visible and selectable.
4. The kernel completes boot.
5. The live desktop appears.
6. Keyboard and mouse work.
7. Terminal, Files and Settings open.
8. Display resolution works.
9. Networking, DNS and HTTPS work.
10. Audio works or the hypervisor limitation is documented.
11. Shutdown and restart work.

## UEFI Live Session

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --state-dir "$GENIXBIT_VM_STATE" \
  --create-disk
```

Directly observe:

1. OVMF starts.
2. The candidate ISO is detected.
3. `BOOTX64.EFI` reaches GRUB.
4. GRUB is visible and selectable.
5. The kernel completes boot.
6. The live desktop appears.
7. No firmware or bootloader failure blocks startup.
8. The full live-session checklist passes.

## Secure Remote Display

Bind VNC to loopback only:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --iso "$GENIXBIT_ISO" \
  --sha256 "$GENIXBIT_SHA256" \
  --state-dir "$GENIXBIT_VM_STATE" \
  --create-disk \
  --vnc 127.0.0.1:1
```

Tunnel from the administrator workstation:

```bash
ssh -L 5901:127.0.0.1:5901 approved-user@approved-test-host
```

Connect the VNC client to `127.0.0.1:5901`. Never expose unauthenticated QEMU VNC publicly.

## Live-Session Evidence

Inside each live session collect non-sensitive summaries from:

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

Record visible GenixBit identity, remaining upstream branding, network, DNS, display, audio, failed services, shutdown and restart.

## Installer

Use UEFI first and then repeat essential installation and boot checks in BIOS mode.

Directly test:

- installer launch;
- language and keyboard selection;
- time zone selection;
- user and password creation;
- automatic partitioning of the blank QCOW2 disk;
- file copy and package configuration;
- removal of live-only packages;
- target-disk bootloader installation;
- installer completion.

Package or script presence is not proof that installation completed.

## Boot Installed Disks

UEFI:

```bash
tools/vm/run-qemu.sh \
  --mode uefi \
  --installed \
  --state-dir "$GENIXBIT_VM_STATE" \
  --disk "$GENIXBIT_VM_STATE/genixbit-uefi.qcow2"
```

BIOS:

```bash
tools/vm/run-qemu.sh \
  --mode bios \
  --installed \
  --state-dir "$GENIXBIT_VM_STATE" \
  --disk "$GENIXBIT_VM_STATE/genixbit-bios.qcow2"
```

Confirm target-disk boot, login, desktop startup, core applications, networking, DNS, display, audio, shutdown and restart.

Inside each installed system run:

```bash
hostnamectl
cat /etc/os-release
cat /etc/lsb-release 2>/dev/null || true
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

When the candidate includes `genixbit-os-base-files`, verify package ownership, `/etc/os-release`, LSB identity, issue banners, clean installation and upgrade behavior.

## Second Same-Candidate Build

Use a separate clean checkout at the identical candidate SHA:

```bash
git clone https://github.com/GenixBit/genixbit-os.git genixbit-os-second-build
cd genixbit-os-second-build
git checkout "$CANDIDATE_SHA"
test "$(git rev-parse HEAD)" = "$CANDIDATE_SHA"
make clean
make bootstrap
make
```

Record commit, host release, architecture, timestamps, package indexes, filename, size, SHA-256 and duration.

Compare both ISOs with `diffoscope`, `xorriso` and SquashFS inspection. Classify timestamps, volume dates, package updates, generated identifiers, ordering, compression differences and unexpected content changes.

A different checksum does not automatically mean failure. Do not mark reproducibility `PASS` until comparison criteria and results are documented.

## Evidence Classification

Use only:

- `PASS` — directly performed and recorded;
- `PARTIAL` — relevant evidence exists, but the complete test is missing;
- `FAIL` — performed and failed;
- `NOT TESTED` — direct execution evidence is absent.

Keep ISO files, checksum artifacts, QCOW2 disks, raw logs, private screenshots, credentials, cloud identifiers and private host details outside Git.

## Suggested Evidence Commits

```text
build: record GenixBit OS candidate artifact
fix: resolve confirmed candidate build or runtime failure
test: record candidate UEFI and BIOS validation
test: record GenixBit OS installer validation
test: record installed-system validation
test: record second candidate build comparison
docs: complete GenixBit OS candidate validation
```
