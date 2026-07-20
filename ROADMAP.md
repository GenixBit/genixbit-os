# GenixBit OS Development Roadmap

> [!NOTE]
> All target dates, feature assignments, and release timelines listed in this document are **provisional** and subject to revision as development progresses.

---

## Release Milestones

### 🟢 Phase 1: 0.1.0 – Reproducible Upstream-Based Build *(Current)*
- [x] Establish Git repository structure with upstream history preservation
- [x] Audit branding, technical dependencies, and third-party software licensing
- [x] Update baseline identity variables (`args.sh`, ISO README generation)
- [x] Add project governance files, developer documentation, and issue templates
- [ ] Verify reproducible ISO image generation on target Ubuntu host

### 🔵 Phase 2: 0.2.0 – GenixBit Branding & Desktop Identity
- [ ] Design official GenixBit OS logos, icons, Plymouth boot splash screen, and wallpapers
- [ ] Package initial `genixbit-os-theme` and `genixbit-os-wallpapers` packages
- [ ] Configure custom GNOME desktop layout, fonts, and dark mode defaults
- [ ] Replace upstream visual branding assets across live session and installer environments

### 🟡 Phase 3: 0.3.0 – GenixBit Package Repository & Signing System
- [ ] Provision production APT repository infrastructure (`packages.os.genixbit.com`)
- [ ] Generate and publish official GenixBit repository GPG signing keyring (`genixbit-os-archive-keyring`)
- [ ] Build and release `genixbit-os-apt-config` and `genixbit-os-base-files` packages
- [ ] Migrate build configuration (`args.sh`, `build.sh`, `mods/`) from upstream APKG server to GenixBit infrastructure

### 🟣 Phase 4: 0.4.0 – Developer Tools & Optional AI Assistant
- [ ] Pre-configure developer toolchains (Docker/Podman, Git, Rust, Python, Go, Node.js)
- [ ] Integrate optional CLI developer assistant tooling
- [ ] Implement AI assistant shell integration for command line help and workflow automation
- [ ] Create developer quick-start environment profiles

### 🟠 Phase 5: 0.5.0 – Update Manager, Privacy Controls & Hardening
- [ ] Implement system update manager for smooth background package updates
- [ ] Enforce telemetry-free system defaults and enhanced privacy settings
- [ ] Apply system hardening policies (firewall defaults, sandboxing rules, secure kernel parameters)
- [ ] Provide system diagnostics and health monitoring tools

### 🚀 Phase 6: 1.0.0 – First Stable Release
- [ ] Finalize production-ready ISO build pipeline
- [ ] Conduct comprehensive security, performance, and hardware compatibility testing
- [ ] Publish official documentation on `docs.os.genixbit.com`
- [ ] Launch GenixBit OS 1.0.0 General Availability
