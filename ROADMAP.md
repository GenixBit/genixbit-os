# GenixBit OS Development Roadmap

> [!NOTE]
> All milestones are provisional. A feature is complete only after implementation, documentation, direct testing, security review and GenixBit maintainer approval. File presence, package manifests, dry runs or configuration inspection must not be treated as proof of successful interactive runtime behavior.

## Active Release Status — `0.3.0-alpha` (PASS)

- **Release Gate Status**: `PASS_ALPHA_FRESH_INSTALL` (16/16 Scenarios PASSED).
- **Published ISO Artifact**: `GenixBitOS-0.3.0-alpha-2311142213.iso` (1.3 GB, SHA-256: `229b3f70f94d0ced3a3d33116a64a0f5a8c2a339070443e1d023938739873ce6`).
- **Reproducibility**: Bit-for-bit identical Build A / Build B deterministic compilation.
- **QEMU VM Autoinstallation**: Verified boot, live desktop, and systemd autoinstall on UEFI and BIOS.
- **GitHub Release Page**: [https://github.com/GenixBit/genixbit-os/releases/tag/v0.3.0-alpha](https://github.com/GenixBit/genixbit-os/releases/tag/v0.3.0-alpha)

---

## Phase 1 — `0.1.x`: Baseline Build and Release Validation *(Completed)*

- [x] Preserve upstream history and GPL-3.0 licensing.
- [x] Establish GenixBit identity variables and repository governance.
- [x] Add repository-quality CI and baseline test documentation.
- [x] Provision an Ubuntu 26.04 `resolute` `amd64` build environment.
- [x] Complete historical ISO compilation and verification.
- [x] Add QEMU, host-readiness and candidate-preflight tooling.
- [x] Enforce completed evidence for pull requests in Repository Quality CI.

---

## Phase 2 — `0.2.x`: Complete GenixBit Identity *(Completed)*

- [x] Approve official GenixBit OS logo and visual identity system.
- [x] Create `genixbit-os-base-files` source scaffolding and identity templates.
- [x] Build and integrate `genixbit-os-base-files` Debian package.
- [x] Create `genixbit-os-theme` (Plymouth boot splash & desktop styling).
- [x] Create `genixbit-os-wallpapers` (Workstation backgrounds).
- [x] Create `genixbit-os-installer-config` (Calamares / Ubiquity slides & profiles).
- [x] Ensure `/etc/os-release`, issue files, URLs and settings identify GenixBit OS.

---

## Phase 3 — `0.3.x`: Signed Package & Release Infrastructure *(Completed)*

- [x] Define offline signing-key generation, security roles, backup, recovery and revocation procedures.
- [x] Create `genixbit-os-archive-keyring` package scaffolding and OpenPGP public key.
- [x] Create `genixbit-os-apt-config` package scaffolding for `resolute-alpha` and `resolute-testing`.
- [x] Execute 12-stage package repository validation drill on isolated GCP private staging infrastructure with 100% PASS evidence.
- [x] Complete Candidate 75 Release Gate Validation (16/16 Scenarios PASSED).
- [x] Publish `GenixBitOS-0.3.0-alpha-2311142213.iso` (1.3 GB) on GitHub Releases.
- [x] Attach all 7 core Debian packages (`genixbit-os-base-files`, `genixbit-os-desktop`, `genixbit-os-theme`, `genixbit-os-wallpapers`, `genixbit-os-installer-config`, `genixbit-os-archive-keyring`, `genixbit-os-apt-config`) to GitHub Release `v0.3.0-alpha`.
- [x] Deploy live web portals (`https://os.genixbit.com`, `https://docs.os.genixbit.com`, `https://packages.os.genixbit.com`).

---

## Phase 4 — `0.4.x`: Developer, Server, and Creator Profiles *(Next Target - Active)*

- [ ] **Developer Profile**: Pre-configured Git, Docker container engine, Python, Node.js, Go, Rust, Java, and build tools.
- [ ] **Application-Builder Profile**: IDEs, local databases (PostgreSQL/SQLite), API testing tools, and deployment templates.
- [ ] **Server-Manager Profile**: Headless services, systemd monitoring, backups, firewall, and container operations.
- [ ] **Creator Profile**: Video, audio, image editing, 3D graphics, streaming, transcription, and hardware-accelerated codec tooling.
- [ ] **AI Learner Profile**: Guided setup, compact model recommendations, starter applications, and GenixBit Academy paths.
- [ ] **Hardware & GPU Diagnostics**: Automatic NVIDIA / AMD GPU detection and ROCm/CUDA runtime diagnostics.

---

## Phase 5 — `0.5.x`: AI Runtime Foundation

- [ ] Optional Ollama and llama.cpp local inference engine integrations.
- [ ] Model catalog metadata and hardware detection tooling.
- [ ] Local OpenAI-compatible API proxy endpoints.

---

## Phase 6 — `0.6.x`: AI Center and Agents

- [ ] Model lifecycle management UI application.
- [ ] Integration with [`GenixBit/agency-agents`](https://github.com/GenixBit/agency-agents).

---

## Official Links & Resources

- **Operating System Portal**: https://os.genixbit.com
- **Documentation**: https://docs.os.genixbit.com
- **Package Status**: https://packages.os.genixbit.com
- **GitHub Releases & Source**: https://github.com/GenixBit/genixbit-os
