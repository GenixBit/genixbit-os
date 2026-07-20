# GenixBit OS Development Roadmap

> [!NOTE]
> All milestones are provisional. A feature is complete only after implementation, documentation, testing, security review, and GenixBit maintainer approval.

## Phase 1 — `0.1.x`: Baseline Build and Release Validation

- [x] Preserve upstream history and GPL-3.0 licensing.
- [x] Establish GenixBit identity variables and repository governance.
- [x] Add repository-quality CI and baseline test documentation.
- [x] Record that the macOS ARM host is unsuitable for the full ISO build.
- [x] Provision an Ubuntu 26.04 `resolute` `amd64` build machine.
- [x] Run `make bootstrap` and complete the first ISO build.
- [x] Verify checksum and ISO metadata.
- [x] Test UEFI boot.
- [x] Test Legacy BIOS boot.
- [x] Test live-session desktop.
- [x] Complete a clean virtual-disk installation.
- [x] Boot and validate the installed system.
- [x] Verify `sudo apt update` and temporary upstream dependency resolution.
- [x] Record all evidence in `docs/TESTING.md`.

## Phase 2 — `0.2.x`: Complete GenixBit Identity

- [ ] Approve official GenixBit OS logo and visual system.
- [ ] Create `genixbit-os-base-files`.
- [ ] Create `genixbit-os-theme`.
- [ ] Create `genixbit-os-wallpapers`.
- [ ] Create `genixbit-os-installer-config`.
- [ ] Replace user-facing boot, live-session, installer, desktop and support branding.
- [ ] Ensure `/etc/os-release`, issue files, URLs and settings identify GenixBit OS.
- [ ] Audit remaining upstream terms as legal notices, technical dependencies or migration defects.
- [ ] Produce genuine screenshots from a validated GenixBit build.

See [`docs/BRANDING-MIGRATION.md`](docs/BRANDING-MIGRATION.md).

## Phase 3 — `0.3.x`: Signed Package and Update Infrastructure

- [ ] Provision `packages.os.genixbit.com` staging infrastructure.
- [ ] Define offline signing-key generation, backup and revocation procedures.
- [ ] Publish only the public verification key.
- [ ] Create `genixbit-os-archive-keyring`.
- [ ] Create `genixbit-os-apt-config`.
- [ ] Establish `alpha`, `testing` and `stable` channels.
- [ ] Implement snapshots, package promotion, rollback and audit records.
- [ ] Build, sign and test GenixBit replacement packages.
- [ ] Migrate from `packages.anduinos.com` only after clean-install and upgrade validation.
- [ ] Add update metadata and release manifests.

## Phase 4 — `0.4.x`: Developer, Server and Creator Profiles

- [ ] Developer profile: Git, containers, Python, Node.js, Go, Rust, Java and build tools.
- [ ] Application-builder profile: IDEs, databases, API clients, testing and deployment templates.
- [ ] Server-manager profile: headless services, monitoring, backups, firewall and container operations.
- [ ] Creator profile: video, audio, image, 3D, streaming, transcription and codec tooling.
- [ ] AI learner profile: guided setup and GenixBit Academy starter paths.
- [ ] Hardware and GPU diagnostics.
- [ ] Profile installation must remain optional and reversible.

## Phase 5 — `0.5.x`: AI Runtime Foundation

- [ ] Define runtime adapter interface.
- [ ] Package optional Ollama integration.
- [ ] Package optional llama.cpp-compatible integration.
- [ ] Evaluate vLLM/container serving for suitable server hardware.
- [ ] Detect RAM, VRAM, GPU, CPU architecture and free disk space.
- [ ] Create signed model-catalog metadata.
- [ ] Show model source, terms, size, checksum and hardware tier before download.
- [ ] Bind local model APIs to loopback by default.
- [ ] Add clean uninstall and model-data removal.

See [`docs/AI-FIRST-PLATFORM.md`](docs/AI-FIRST-PLATFORM.md) and [`docs/AI-MODEL-CATALOG.md`](docs/AI-MODEL-CATALOG.md).

## Phase 6 — `0.6.x`: GenixBit AI Center and Agents

- [ ] Build `genixbit-os-ai-center`.
- [ ] Browse and filter approved model metadata.
- [ ] Install, start, stop, inspect and remove model runtimes.
- [ ] Display local API endpoints and resource usage.
- [ ] Add explicit privacy and cloud-provider controls.
- [ ] Integrate `GenixBit/agency-agents` as an optional component.
- [ ] Support Antigravity, Gemini CLI, Codex, Cursor, OpenCode and other validated tools.
- [ ] Show file changes and require approval before modifying external tool configuration.
- [ ] Never display an agent backend as active when it is not configured.

## Phase 7 — `0.7.x`: GenixBit Store

- [ ] Build the native GenixBit Store client.
- [ ] Support signed GenixBit APT packages.
- [ ] Display Ubuntu package sources accurately.
- [ ] Integrate reviewed Flatpak/Flathub entries.
- [ ] Add official vendor repository adapters with user confirmation.
- [ ] Add AI runtime and model catalog integration.
- [ ] Display publisher, license, permissions, architecture and update method.
- [ ] Create a GenixBit-controlled publisher review workflow.
- [ ] Add application security scanning and rollback procedures.

See [`docs/APP-STORE.md`](docs/APP-STORE.md).

## Phase 8 — `0.8.x`: Websites, Documentation and Operations

- [x] Add original product, documentation and package-status preview pages.
- [x] Add containerized Caddy preview configuration.
- [ ] Provision the new GenixBit-controlled web server and public IP.
- [ ] Point `os.genixbit.com` to the server.
- [ ] Point `docs.os.genixbit.com` to the server.
- [ ] Point `packages.os.genixbit.com` to the server only when package security is ready.
- [ ] Configure TLS, firewall, monitoring, backups and restricted deployment access.
- [ ] Publish versioned documentation.
- [ ] Publish release status without fake download links.
- [ ] Add service health and incident procedures.

See [`docs/PLATFORM-SERVICES.md`](docs/PLATFORM-SERVICES.md) and [`deploy/README.md`](deploy/README.md).

## Phase 9 — `0.9.x`: Security, Updates and Release Candidate

- [ ] Security hardening baseline.
- [ ] Update manager and rollback experience.
- [ ] Package and catalog signature verification.
- [ ] Privacy controls and transparent service settings.
- [ ] Hardware compatibility matrix.
- [ ] Upgrade testing between supported releases.
- [ ] Disaster recovery and signing-key revocation exercises.
- [ ] Documentation freeze and release audit.

## Phase 10 — `1.0.0`: First Stable GenixBit OS Release

- [ ] Production-ready ISO build and signed release artifacts.
- [ ] Complete GenixBit user-facing branding.
- [ ] Signed GenixBit package channels.
- [ ] Stable update and rollback process.
- [ ] Validated developer, server and creator profiles.
- [ ] Optional AI runtime foundation.
- [ ] Public product and documentation websites.
- [ ] Security and support lifecycle published.
- [ ] General availability approved by GenixBit Labs Private Limited.
