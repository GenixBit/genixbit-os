# GenixBit OS

> [!NOTE]
> **Official Pre-Release Available (`0.3.0-alpha`)**: GenixBit OS `0.3.0-alpha` candidate gate validation has achieved **100% PASS (`PASS_ALPHA_FRESH_INSTALL`)** across all 16 candidate validation scenarios. The verified ISO release artifact `GenixBitOS-0.3.0-alpha-2311142213.iso` (1.3 GB, SHA256: `229b3f70f94d0ced3a3d33116a64a0f5a8c2a339070443e1d023938739873ce6`) is published and available on [GitHub Releases](https://github.com/GenixBit/genixbit-os/releases/tag/v0.3.0-alpha).

## Build with AI. Own your environment.

**GenixBit OS** is an AI-first, developer-focused Ubuntu-based Linux distribution developed by **GenixBit Labs Private Limited** for:

- developers and application builders;
- AI learners and first-time model users;
- server managers and DevOps teams;
- video, audio, design and content creators;
- technical teams that want local models, agents, containers and transparent system control.

AI-first means optional, hardware-aware and license-aware access to local or self-hosted AI runtimes, open-weight models, GenixBit Agents, development tooling, creator workflows and future GenixBit applications. It does not mean silently downloading models, forcing a cloud provider or claiming capabilities that have not been implemented.

## Current Foundation

GenixBit OS currently uses:

- **Base OS**: Ubuntu Linux `resolute` / 26.04;
- **Target architecture**: `amd64` / x86_64;
- **Build system and layout**: derived from AnduinOS 2;
- **License**: GPL-3.0 for covered source;
- **Current active version**: `0.3.0-alpha`;
- **Current valid release artifact**: `GenixBitOS-0.3.0-alpha-2311142213.iso` (1.3 GB, SHA256: `229b3f70f94d0ced3a3d33116a64a0f5a8c2a339070443e1d023938739873ce6`);
- **Release gate certification**: `PASS_ALPHA_FRESH_INSTALL` (16/16 Scenarios PASSED);
- **Reproducibility**: 100% Bit-for-bit Build A / Build B deterministic ISO verification.

The source retains mandatory upstream attribution. See [`UPSTREAM.md`](UPSTREAM.md), [`LICENSE`](LICENSE) and [`OSS.md`](OSS.md).

## AI-First Platform

The planned platform includes:

### GenixBit AI Center

A hardware-aware manager for optional local runtimes, model discovery, installation, removal, service status, disk usage, API access, privacy settings and license review.

### GenixBit Agents

Optional integration with [`GenixBit/agency-agents`](https://github.com/GenixBit/agency-agents), which supports Antigravity, Gemini CLI, Codex, Cursor, OpenCode and other developer-agent tools.

### Bharat AI

Connection to [`GenixBit/IndicLLM-Bharat-V1`](https://github.com/GenixBit/IndicLLM-Bharat-V1) after training, evaluation, safety, licensing, packaging and release requirements are met. The current Bharat repository is a development program, not a completed production model.

### Curated Local Models

The initial catalog plan covers families such as Gemma 3, Qwen3, DeepSeek-R1 distilled models, IBM Granite and future verified GenixBit models. Model weights will not be bundled into the ISO by default.

### GenixBit Store

A future curated experience for applications, developer tools, AI runtimes, model integrations, server utilities, creator tools, Flatpak applications and signed GenixBit packages.

Read:

- [`docs/AI-FIRST-PLATFORM.md`](docs/AI-FIRST-PLATFORM.md)
- [`docs/AI-MODEL-CATALOG.md`](docs/AI-MODEL-CATALOG.md)
- [`docs/APP-STORE.md`](docs/APP-STORE.md)

## User Profiles

| Profile | Planned Experience |
| --- | --- |
| Developer | languages, IDEs, terminals, containers, local AI APIs, agents, databases, testing and deployment tools |
| AI learner | guided setup, compact model recommendations, starter applications and GenixBit Academy paths |
| Server manager | headless services, containers, monitoring, backups, secure remote administration and AI serving |
| Creator | video, audio, image, 3D, streaming, transcription, captioning and hardware-aware AI workflows |
| AI workstation | larger local models, RAG, evaluation, multi-agent development and experimental fine-tuning workflows |

## Feature & Release Gate Status

| Feature / Gate Area | Status | Notes |
| --- | --- | --- |
| Release 0.3.0-alpha Candidate Gate | **PASS** | 16/16 candidate validation scenarios passed (`PASS_ALPHA_FRESH_INSTALL`) |
| 0.3.0-alpha ISO Artifact | **PASS** | `GenixBitOS-0.3.0-alpha-2311142213.iso` (1.3 GB) published on GitHub Releases |
| Build A / Build B Reproducibility | **PASS** | Independent build passes compiled bit-for-bit identical installation media |
| QEMU VM Autoinstallation | **PASS** | Boot, live desktop, and systemd autoinstallation verified on UEFI and BIOS |
| OpenPGP Key Isolation | **PASS** | Passphrase-protected 3-role OpenPGP key pair separation verified |
| Repository & Build Preparation | **Complete** | Governance, licensing, CI, documentation and VM tooling active |
| `genixbit-os-base-files` | **PASS** | Identity templates & Debian package metadata verified |
| `genixbit-os-desktop` | **PASS** | GNOME desktop & local AI workspace defaults package verified |
| `genixbit-os-theme` | **PASS** | Plymouth boot splash & desktop artwork package verified |
| `genixbit-os-wallpapers` | **PASS** | High-resolution workstation background wallpapers package verified |
| `genixbit-os-installer-config` | **PASS** | Ubiquity / Calamares installer slides & profiles package verified |
| `genixbit-os-archive-keyring` | **PASS** | OpenPGP public key keyring package verified |
| `genixbit-os-apt-config` | **PASS** | APT repository channel configuration package verified |
| Product Website Portal | **Active** | Live at `https://os.genixbit.com` |
| Documentation Portal | **Active** | Live at `https://docs.os.genixbit.com` |
| Package Status Portal | **Active** | Live at `https://packages.os.genixbit.com` |
| GenixBit AI Center | **Planned** | Runtime and model-management application |
| GenixBit Agents Integration | **Planned** | Optional connection to `GenixBit/agency-agents` |
| GenixBit Store | **Planned** | Curated applications, packages, runtimes and model integrations |

## Branding & Package Scaffolding

Every user-facing boot, live-session, installer, desktop, settings, support, server and update surface displays **GenixBit OS**.

Packages published:
- `genixbit-os-base-files_0.3.0-alpha-1_all.deb`
- `genixbit-os-desktop_0.3.0-alpha-1_all.deb`
- `genixbit-os-theme_0.3.0-alpha-1_all.deb`
- `genixbit-os-wallpapers_0.3.0-alpha-1_all.deb`
- `genixbit-os-installer-config_0.3.0-alpha-1_all.deb`
- `genixbit-os-archive-keyring_0.3.0-alpha-1_all.deb`
- `genixbit-os-apt-config_0.3.0-alpha-1_all.deb`

See [`docs/BRANDING-MIGRATION.md`](docs/BRANDING-MIGRATION.md).

## Official Services

| Service | URL | Status |
| --- | --- | --- |
| Operating System Portal | `https://os.genixbit.com` | **Active & Live** |
| Documentation | `https://docs.os.genixbit.com` | **Active & Live** |
| Package Status | `https://packages.os.genixbit.com` | **Active & Live** |
| GitHub Source & Releases | `https://github.com/GenixBit/genixbit-os` | **Active & Live** |

## Quick Start Installation Commands

### 1. Checksum Verification

```bash
sha256sum GenixBitOS-0.3.0-alpha-2311142213.iso
# Expected: 229b3f70f94d0ced3a3d33116a64a0f5a8c2a339070443e1d023938739873ce6
```

### 2. Write to USB Flash Drive

```bash
sudo dd if=GenixBitOS-0.3.0-alpha-2311142213.iso of=/dev/sdX bs=4M status=progress conv=fdatasync
```

### 3. Run under QEMU / KVM Virtual Machine

```bash
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm -cdrom GenixBitOS-0.3.0-alpha-2311142213.iso
```

## Governance

GenixBit OS is developed and maintained by **GenixBit Labs Private Limited**:

- Authorized GenixBit team members publish official releases;
- External users may report bugs, suggest features, submit compatibility results and exercise GPL rights;
- Unsolicited external code pull requests are not accepted unless invited by a GenixBit maintainer.

See [`GOVERNANCE.md`](GOVERNANCE.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Security

Early builds are not suitable for production or sensitive systems. Never commit credentials, tokens, model-provider keys, private signing keys, ISO images or generated build directories.

See [`SECURITY.md`](SECURITY.md).

## Official Links

- **Company**: https://www.genixbit.com
- **Operating System**: https://os.genixbit.com
- **Documentation**: https://docs.os.genixbit.com
- **Package Status**: https://packages.os.genixbit.com
- **GitHub Source & Releases**: https://github.com/GenixBit/genixbit-os
