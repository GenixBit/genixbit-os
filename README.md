# GenixBit OS

> [!WARNING]
> **Early Alpha Preview (`0.1.0-alpha`)**: the baseline ISO has not yet been built and validated on the required Ubuntu 26.04 `amd64` host. GenixBit OS is not ready for production systems, primary workstations, critical infrastructure, or sensitive environments.

## Build with AI. Own your environment.

**GenixBit OS** is an AI-first, developer-focused Ubuntu-based Linux distribution being developed by **GenixBit Labs Private Limited** for:

- developers and application builders;
- AI learners and first-time model users;
- server managers and DevOps teams;
- video, audio, design, and content creators;
- technical teams that want local models, agents, containers, and transparent system control.

AI-first means optional, hardware-aware and license-aware access to local or self-hosted AI runtimes, open-weight models, GenixBit Agents, development tooling, creator workflows, and future GenixBit applications. It does not mean silently downloading models, forcing a cloud provider, or claiming capabilities that have not been implemented.

## Current Foundation

GenixBit OS currently uses:

- **Base OS**: Ubuntu Linux `resolute` / 26.04;
- **Target architecture**: `amd64` / x86_64;
- **Build system and layout**: derived from AnduinOS 2;
- **License**: GPL-3.0 for covered source;
- **Current version**: `0.1.0-alpha`;
- **Current release state**: baseline build validation pending.

The source retains mandatory upstream attribution. See [`UPSTREAM.md`](UPSTREAM.md), [`LICENSE`](LICENSE), and [`OSS.md`](OSS.md).

## AI-First Platform

The planned platform includes:

### GenixBit AI Center

A hardware-aware manager for optional local runtimes, model discovery, installation, removal, service status, disk usage, API access, privacy settings, and license review.

### GenixBit Agents

Optional integration with [`GenixBit/agency-agents`](https://github.com/GenixBit/agency-agents), which supports Antigravity, Gemini CLI, Codex, Cursor, OpenCode, and other developer-agent tools.

### Bharat AI

Connection to [`GenixBit/IndicLLM-Bharat-V1`](https://github.com/GenixBit/IndicLLM-Bharat-V1) after training, evaluation, safety, licensing, packaging, and release requirements are met. The current Bharat repository is a development program, not a completed production model.

### Curated Local Models

The initial catalog plan covers families such as Gemma 3, Qwen3, DeepSeek-R1 distilled models, IBM Granite, and future verified GenixBit models. Model weights will not be bundled into the ISO by default.

### GenixBit Store

A future curated experience for applications, developer tools, AI runtimes, model integrations, server utilities, creator tools, Flatpak applications, and signed GenixBit packages.

Read:

- [`docs/AI-FIRST-PLATFORM.md`](docs/AI-FIRST-PLATFORM.md)
- [`docs/AI-MODEL-CATALOG.md`](docs/AI-MODEL-CATALOG.md)
- [`docs/APP-STORE.md`](docs/APP-STORE.md)

## User Profiles

| Profile | Planned Experience |
| --- | --- |
| Developer | languages, IDEs, terminals, containers, local AI APIs, agents, databases, testing and deployment tools |
| AI learner | guided setup, compact model recommendations, starter applications, GenixBit Academy paths |
| Server manager | headless services, containers, monitoring, backups, secure remote administration and AI serving |
| Creator | video, audio, image, 3D, streaming, transcription, captioning and hardware-aware AI workflows |
| AI workstation | larger local models, RAG, evaluation, multi-agent development and experimental fine-tuning workflows |

## Feature Status

| Feature Area | Status | Notes |
| --- | --- | --- |
| Repository and build preparation | **Complete** | governance, licensing, CI, documentation and validation framework are present |
| Baseline ISO build | **Blocked pending compatible host** | requires Ubuntu 26.04 `resolute` on `amd64`; macOS ARM is not supported for the full build |
| Complete GenixBit runtime branding | **Planned** | requires GenixBit replacement packages; user-visible upstream branding may remain until migration |
| Product website preview | **Available in source** | original static preview under `website/os/`; public deployment and DNS remain pending |
| Documentation preview | **Available in source** | static preview under `website/docs/`; public deployment remains pending |
| Package repository | **Not active** | signing, snapshots, promotion, rollback and replacement packages are required first |
| GenixBit AI Center | **Planned** | runtime and model-management application |
| GenixBit Agents integration | **Planned** | optional connection to `GenixBit/agency-agents` |
| GenixBit Store | **Planned** | curated applications, packages, runtimes and model integrations |
| Bharat AI production checkpoint | **Not available** | development work exists; production training and evaluation remain incomplete |

## Branding Migration

The official goal is for every user-facing boot, live-session, installer, desktop, settings, support, server and update surface to show **GenixBit OS**.

Technical names such as `anduinos-apt-config`, `anduinos-archive-keyring`, installer packages and `packages.anduinos.com` remain temporary upstream dependencies. They must not be renamed until GenixBit’s signed replacements exist and pass clean-install, upgrade and rollback tests.

See [`docs/BRANDING-MIGRATION.md`](docs/BRANDING-MIGRATION.md).

## Official Service Plan

| Service | URL | Status |
| --- | --- | --- |
| Operating system website | `https://os.genixbit.com` | DNS/deployment pending |
| Documentation | `https://docs.os.genixbit.com` | DNS/deployment pending |
| Package repository | `https://packages.os.genixbit.com` | infrastructure and signing pending |
| Source code | `https://github.com/GenixBit/genixbit-os` | active |

An original preview site and a containerized deployment stack are included under [`website/`](website/) and [`deploy/`](deploy/). The website is structurally inspired by good Linux product websites but does not copy AnduinOS content, artwork, reviews or proprietary web assets.

See [`docs/PLATFORM-SERVICES.md`](docs/PLATFORM-SERVICES.md) and [`deploy/README.md`](deploy/README.md).

## Development Roadmap

1. **0.1.x — Baseline validation**: produce, boot, install and test the first ISO on Ubuntu 26.04 amd64.
2. **0.2.x — GenixBit identity**: create owned branding packages, desktop identity, installer assets and system metadata.
3. **0.3.x — Signed package infrastructure**: launch GenixBit APT packages, keyring, snapshots, promotion and rollback.
4. **0.4.x — Developer and creator profiles**: toolchains, containers, server utilities and creator applications.
5. **0.5.x — AI runtime foundation**: optional Ollama/llama.cpp integrations, catalog metadata and hardware detection.
6. **0.6.x — AI Center and Agents**: model lifecycle management and GenixBit Agents integration.
7. **0.7.x — GenixBit Store**: curated apps, packages, AI tools and model integrations.
8. **1.0.0 — Stable release**: production-quality build, upgrades, security, documentation and support lifecycle.

See [`ROADMAP.md`](ROADMAP.md).

## Build Requirements

The current build requires:

- Ubuntu Linux matching target codename `resolute`;
- `amd64` / x86_64 host;
- standard user with sudo access;
- at least 30 GB free space;
- at least 8 GB RAM, with 16 GB recommended;
- build dependencies validated through `make bootstrap`.

Do not run the full build directly on macOS, Windows or ARM64.

## Build

```bash
make bootstrap
make
```

Expected output after a successful build:

```text
dist/GenixBitOS-0.1.0-alpha-YYMMDDHHMM.iso
dist/GenixBitOS-0.1.0-alpha-YYMMDDHHMM.sha256
```

Record actual results in [`docs/TESTING.md`](docs/TESTING.md). Do not publish or claim a successful ISO until UEFI, BIOS, live-session, installer, installed-system and APT tests pass.

## Repository Structure

```text
├── args.sh                       # Build configuration and identity
├── build.sh                      # ISO build pipeline
├── makefile                      # Build orchestration and environment checks
├── mods/                         # Ordered chroot customization modules
├── docs/                         # Architecture, AI, branding, packages, testing and services
├── website/                      # Original OS, docs and package-status previews
├── deploy/                       # Containerized static preview deployment
├── .github/CODEOWNERS            # GenixBit-controlled ownership
├── GOVERNANCE.md                 # Official maintainer and release policy
├── CONTRIBUTING.md               # Closed-maintainer alpha workflow
├── ROADMAP.md                    # Product milestones
├── SECURITY.md                   # Private vulnerability reporting
├── UPSTREAM.md                   # Upstream attribution
├── OSS.md                        # Third-party software inventory
└── LICENSE                       # GPL-3.0
```

## Governance

GenixBit OS uses a closed maintainer model during early alpha:

- only authorized GenixBit team members may merge official changes or publish official releases;
- external users may report bugs, suggest features, submit compatibility results and exercise GPL rights;
- unsolicited external code pull requests are not accepted unless invited by a GenixBit maintainer.

This governance policy does not remove GPL rights or upstream attribution obligations. See [`GOVERNANCE.md`](GOVERNANCE.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Security

Early builds are not suitable for production or sensitive systems. Never commit credentials, tokens, model-provider keys, private signing keys, ISO images or generated build directories.

See [`SECURITY.md`](SECURITY.md).

## Official Links

- **Company**: https://www.genixbit.com
- **Operating System**: https://os.genixbit.com
- **Documentation**: https://docs.os.genixbit.com
- **Package Repository**: https://packages.os.genixbit.com
- **Source Code**: https://github.com/GenixBit/genixbit-os
