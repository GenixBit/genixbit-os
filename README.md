# GenixBit OS

> [!WARNING]
> **Early Alpha Preview**: GenixBit OS is currently under active early-stage development (`0.1.0-alpha`). It is **not yet suitable for production environments, primary workstations, or critical systems**.

---

## Overview

GenixBit OS is an AI-first, developer-focused Ubuntu-based Linux distribution being developed by **GenixBit Labs Private Limited**. It is currently based on AnduinOS 2 and is being extended with GenixBit branding, developer tooling, AI capabilities, productivity features, security controls, and a future GenixBit package ecosystem.

---

## Technical Foundation & Upstream Relationship

GenixBit OS is currently built upon:
* **Base OS**: Ubuntu Linux (`resolute` / 26.04 base)
* **Build System & Layout**: Derived from [AnduinOS 2](https://github.com/AiursoftWeb/AnduinOS-2)

We acknowledge and thank the maintainers of Ubuntu and AnduinOS 2 for providing the foundational build infrastructure upon which GenixBit OS is being developed. For complete attribution details, see [`UPSTREAM.md`](UPSTREAM.md).

---

## Project Goals

* **Developer First**: Out-of-the-box pre-configured environments for modern software engineering, containerization, systems programming, and cloud-native workflows.
* **AI Native Integration**: Optional local and cloud-assisted AI helper tooling designed for developer productivity, shell automation, and contextual assistance.
* **Security & Hardening**: Strict default security boundaries, clean non-telemetry base, and verifiable package distribution.
* **Modern Desktop Experience**: Polished, performant, and clutter-free desktop UI optimized for multi-monitor developer setups.

---

## Feature Status

| Feature Area | Status | Notes |
| :--- | :---: | :--- |
| ISO Build Pipeline | **Validation Pending** | Upstream build system is present; the first GenixBit OS ISO build has not yet been verified |
| Basic OS Identity & Branding | **Work in Progress** | Core identity variables established; custom artwork pending |
| GenixBit Package Infrastructure | **Planned** | `packages.os.genixbit.com` repository and signing pipeline |
| AI Assistant Integration | **Planned** | Context-aware developer assistant and CLI integration |
| Custom System Installer & Updater | **Planned** | Dedicated installation framework and update manager |

---

## Development Roadmap

* **0.1.0-alpha**: Initial build-system setup, baseline identity, repository hygiene, and build-validation preparation *(Current Phase)*
* **0.2.0**: GenixBit OS desktop visual identity, themes, fonts, wallpapers, and branding assets
* **0.3.0**: GenixBit package repository (`packages.os.genixbit.com`), GPG signing keyring, and `genixbit-os-apt-config`
* **0.4.0**: Developer toolchains, pre-configured environments, and optional AI assistance components
* **0.5.0**: Update manager, enhanced privacy controls, and security hardening defaults
* **1.0.0**: First stable release candidate

See [`ROADMAP.md`](ROADMAP.md) for detailed milestone tracking.

---

## Build Requirements

Building GenixBit OS requires an **Ubuntu Linux host environment**:

* **Host OS**: Ubuntu Linux matching the target release codename (currently `resolute` / 26.04)
* **Host Architecture**: `amd64` (x86_64)
* **Privileges**: User account with `sudo` access (do not run `make` directly as root)
* **Disk Space**: At least 30 GB free disk space
* **RAM**: 8 GB minimum (16 GB recommended)
* **Required Host Tools**: `binutils`, `curl`, `debootstrap`, `gnupg`, `squashfs-tools`, `xorriso`, `grub-pc-bin`, `grub-efi-amd64`, `grub2-common`, `mtools`, `dosfstools`

> [!NOTE]
> Building directly on macOS or Windows hosts is not supported natively. Use an Ubuntu virtual machine or server matching the target version and architecture.

---

## How to Build

1. **Bootstrap dependencies and validate build host**:
   ```bash
   make bootstrap
   ```

2. **Configure build options (optional TUI)**:
   ```bash
   make menuconfig
   ```

3. **Start the build process**:
   ```bash
   make
   ```

Upon completion, the generated bootable ISO image and SHA-256 checksum will be located in the `dist/` directory:

```text
dist/GenixBitOS-0.1.0-alpha-YYMMDDHHMM.iso
dist/GenixBitOS-0.1.0-alpha-YYMMDDHHMM.sha256
```

Record build and virtual-machine test results in [`docs/TESTING.md`](docs/TESTING.md).

---

## Repository Structure

```text
├── args.sh                   # Central build configuration and identity variables
├── build.sh                  # Core ISO build pipeline
├── makefile                  # Build orchestrator and environment validator
├── menuconfig.sh             # Terminal build configuration interface
├── clean_all.sh              # Cleanup utility
├── shared.sh                 # Shared logging helpers
├── mods/                     # Modular chroot installation scripts
├── docs/                     # Technical and testing documentation
│   ├── ARCHITECTURE.md       # Architectural overview
│   ├── BUILDING.md           # Step-by-step build guide
│   ├── BRANDING.md           # Visual identity guidelines
│   ├── TESTING.md            # Baseline ISO validation record
│   ├── UPSTREAM-SYNC.md      # Synchronization workflow with upstream
│   └── PACKAGE-ROADMAP.md    # Package repository migration plan
├── CHANGELOG.md              # Project history and release notes
├── CONTRIBUTING.md           # Contribution guidelines
├── LICENSE                   # GNU General Public License v3.0
├── OSS.md                    # Third-party open-source software inventory
├── ROADMAP.md                # Development roadmap
├── SECURITY.md               # Vulnerability reporting policy
└── UPSTREAM.md               # Upstream attribution and credits
```

---

## Governance & Documentation

* **Architecture**: See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
* **Building Guide**: See [`docs/BUILDING.md`](docs/BUILDING.md)
* **Testing Record**: See [`docs/TESTING.md`](docs/TESTING.md)
* **Package Migration Roadmap**: See [`docs/PACKAGE-ROADMAP.md`](docs/PACKAGE-ROADMAP.md)
* **Upstream Synchronization**: See [`docs/UPSTREAM-SYNC.md`](docs/UPSTREAM-SYNC.md)
* **Security Policy**: See [`SECURITY.md`](SECURITY.md)
* **Contribution Guidelines**: See [`CONTRIBUTING.md`](CONTRIBUTING.md)
* **Code of Conduct**: See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)

---

## Upstream Attribution & Licensing

GenixBit OS is open-source software released under the **[GNU General Public License v3.0 (GPL-3.0)](LICENSE)**.

* **Original Upstream Project**: [AnduinOS 2](https://github.com/AiursoftWeb/AnduinOS-2) (GPL-3.0)
* **Upstream Ownership**: Copyright © AnduinXue & Aiursoft Web Development Team.
* **GenixBit Modifications**: Copyright © GenixBit Labs Private Limited.

Full attribution details and licensing terms are available in [`UPSTREAM.md`](UPSTREAM.md) and [`LICENSE`](LICENSE). Third-party package licensing information is documented in [`OSS.md`](OSS.md).

---

## Security & Disclaimer

**Disclaimer**: GenixBit OS is currently under active early-stage development (`0.1.0-alpha`). It is provided "AS IS" without warranty of any kind. Do not install or run early alpha builds on production hardware, mission-critical systems, or environments containing sensitive data.

For security concerns, please refer to [`SECURITY.md`](SECURITY.md).

---

## Official Links

* **Company**: [GenixBit Labs Private Limited](https://www.genixbit.com)
* **Operating System**: [https://os.genixbit.com](https://os.genixbit.com)
* **Documentation**: [https://docs.os.genixbit.com](https://docs.os.genixbit.com)
* **Package Repository**: [https://packages.os.genixbit.com](https://packages.os.genixbit.com)
* **Source Code**: [https://github.com/GenixBit/genixbit-os](https://github.com/GenixBit/genixbit-os)
