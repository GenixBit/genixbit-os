# GenixBit OS Development Roadmap

> [!NOTE]
> All milestones are provisional. A feature is complete only after implementation, documentation, direct testing, security review and GenixBit maintainer approval. File presence, package manifests or configuration inspection must not be treated as proof of successful interactive runtime behavior.

## Phase 1 — `0.1.x`: Baseline Build and Release Validation *(Current Gate)*

### Repository and Build Preparation

- [x] Preserve upstream history and GPL-3.0 licensing.
- [x] Establish GenixBit identity variables and repository governance.
- [x] Add repository-quality CI and baseline test documentation.
- [x] Confirm macOS ARM is unsuitable for the full ISO build.
- [x] Provision an Ubuntu 26.04 `resolute` `amd64` build machine.
- [x] Run `make bootstrap` successfully.
- [x] Complete the first ISO compilation.
- [x] Record ISO filename and exact byte size.
- [x] Create and independently verify the SHA-256 checksum.
- [x] Record hybrid BIOS/UEFI boot structures.
- [x] Add host setup readiness check (`tools/vm/setup-host.sh`) and verify QEMU harness dry-run (`tools/vm/run-qemu.sh`).

### Direct Runtime Validation Still Required

- [ ] Boot the ISO through UEFI and record evidence that the live desktop was reached.
- [ ] Boot the ISO through Legacy BIOS and record evidence that the live desktop was reached.
- [ ] Confirm the GRUB menu displays correctly.
- [ ] Validate keyboard, locale, display, networking, DNS, audio, shutdown and restart in the live session.
- [ ] Launch the installer interactively.
- [ ] Complete installation to a clean virtual disk.
- [ ] Confirm partitioning and target-disk bootloader installation.
- [ ] Remove the ISO and boot the installed system from the virtual disk.
- [ ] Confirm account creation, login and desktop startup.
- [ ] Run `sudo apt update` inside the installed system.
- [ ] Check installed package health and critical boot logs.
- [ ] Confirm user-facing GenixBit identity and record remaining upstream branding.
- [ ] Perform a second clean build.
- [ ] Compare the second ISO with the first and document expected/non-deterministic differences.
- [ ] Store non-sensitive evidence summaries in `docs/TESTING.md`.

Phase 1 is not complete until the direct runtime tests above are recorded. The current ISO compilation result is valid, but it is not yet a release-ready validation.

## Phase 2 — `0.2.x`: Complete GenixBit Identity

Phase 2 design and package scaffolding may begin after the Phase 1 evidence correction, but branded release claims require a validated live and installed system.

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
- [x] Provision a GenixBit-controlled web server.
- [x] Deploy the product website preview.
- [x] Deploy the documentation preview.
- [x] Deploy the package-service status page.
- [ ] Attach and verify a stable public endpoint such as an Elastic IP or approved load balancer.
- [ ] Confirm SSH is restricted to approved administrators or Systems Manager.
- [ ] Configure multi-region uptime and TLS-expiry monitoring.
- [ ] Configure backup, log retention and tested DNS rollback.
- [ ] Publish versioned documentation.
- [ ] Add service health and incident procedures.
- [ ] Keep the package domain status-only until signed APT infrastructure is approved.

See [`docs/PLATFORM-SERVICES.md`](docs/PLATFORM-SERVICES.md), [`docs/DEPLOYMENT-STATUS.md`](docs/DEPLOYMENT-STATUS.md) and [`deploy/README.md`](deploy/README.md).

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
