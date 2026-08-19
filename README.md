# GenixBit OS

<div align="center">

![GenixBit OS Logo](logo.svg)

### The Autonomous AI & Next-Generation Workstation Operating System
**Built with AI. Powered by Linux. Designed for Developers, Creators, and Swarms.**

[![CI Release Gate](https://img.shields.io/badge/CI%20Gate-100%25%20PASS-emerald?style=for-the-badge&logo=githubactions)](tools/ci-full-release-gate.sh)
[![Release Version](https://img.shields.io/badge/Release-1.0.0%20LTS%20%2B%201.5.0%20Sutra-indigo?style=for-the-badge&logo=ubuntu)](docs/releases/1.0.0-lts.env)
[![Live Cloud Demo](https://img.shields.io/badge/Live%20Demo-os.genixbit.com-cyan?style=for-the-badge&logo=googlechrome)](https://os.genixbit.com)
[![Packages Catalog](https://img.shields.io/badge/Packages-23%20Native%20.deb-blue?style=for-the-badge&logo=debian)](https://packages.os.genixbit.com)

---

![GenixBit OS Live Modern Desktop](screenshot.png)

</div>

---

## 🚀 Live Cloud Stream & Web Experience

Experience GenixBit OS instantly in your browser without installing anything:
- 🌐 **Interactive Live Desktop**: [**https://os.genixbit.com**](https://os.genixbit.com)
- 📚 **Official Documentation**: [**https://docs.os.genixbit.com**](https://docs.os.genixbit.com)
- 📦 **Package Repository & ISOs**: [**https://packages.os.genixbit.com**](https://packages.os.genixbit.com)

---

## 🎨 Next-Generation Modern UI & Desktop Suite

GenixBit OS features a glassmorphic design system inspired by macOS Sequoia, Windows 11 Fluent, and modern desktop Linux (COSMIC / Deepin).

### 1. 🪟 Full-Width Glassmorphic Top Bar
- **Docked Header**: Docked across 100% display span with `36px` height, subtle border line, and dark glass translucency (`rgba(15, 23, 42, 0.90)`).
- **Left**: GenixBit Application Whisker Menu with instant search & Active Window Tasklist pill.
- **Center**: Bold centered Clock & Date widget (`%a %b %d  %H:%M`).
- **Right**: System status hub, systray notifications, volume mixer, and quick toggles.

### 2. ⚓ `GenixBit-Glass` Bottom Dock
- Frosted translucent glass backing with `18px` rounded corners and glowing dot indicators for active apps.
- Pinned shortcuts: **GenixBit AI Center**, **Control Center**, **Quick Launcher**, **GenixBit Store**, **Terminal**, and **Files**.
- Smooth hover zoom magnification (130%).

### 3. ⚙️ `genixbit-control-center` (Appearance Hub)
- One-click **Dark / Light mode** switcher (`GenixBit-Dark` / `GenixBit-Light`).
- 6 Cyber Accent color palettes: **Cyber Cyan** (`#52d9ff`), **Royal Indigo** (`#6366f1`), **Emerald Teal** (`#10b981`), **Sunset Orange** (`#f97316`), **Ruby Red** (`#f43f5e`), **Cosmic Purple** (`#a855f7`).
- Plank dock customizer (size, zoom factor, position) and real-time AI GPU VRAM monitor.

### 4. 🔍 `genixbit-launcher` (Spotlight HUD Overlay)
- Press **`Super + Space`** to open the instant search overlay.
- Instant fuzzy search across applications, system settings, and files.
- **Inline Local AI Query (`@ai <prompt>`)**: Ask questions directly in the search bar with instant responses from the local `genixbit-ai-proxy` on `127.0.0.1:11434`.

### 5. 🖼️ `GenixBit-Icons` (Modern Vector Suite)
- Pure SVG vector icons for all GenixBit OS native applications and system utilities.

---

## 📦 Complete 23-Package Native Debian Ecosystem

| Category | Package Name | Command / Utility | Key Capabilities |
| :--- | :--- | :--- | :--- |
| **Core Base** | `genixbit-os-base-files` | `/etc/os-release` | System identity, OS release parameters & environment variables |
| **Core Desktop** | `genixbit-os-desktop` | `genixbit-desktop-setup` | XFCE4 top bar, Plank glass dock, compositor & shortcut layout |
| **Theme** | `genixbit-os-theme` | `GenixBit-Dark/Light` | Glassmorphic GTK 3/4 CSS, XFWM4 window theme, Plymouth splash |
| **Wallpapers** | `genixbit-os-wallpapers` | Workstation 4K | Official Cyber Dark and Clean Light workstation backgrounds |
| **Installer** | `genixbit-os-installer-config` | Calamares / Ubiquity | Native autoinstall slides, OEM profiles, and system wizard |
| **Keyring** | `genixbit-os-archive-keyring` | APT GPG Keyring | Signed cryptographic release keyring |
| **APT Config** | `genixbit-os-apt-config` | `genixbit-os.sources` | Resolute production and testing package repositories |
| **Profiles** | `genixbit-os-developer-profile` | `genixbit-dev-setup` | Complete dev toolchain (Docker, Git, Python, Node, Go, Rust) |
| **Profiles** | `genixbit-os-server-profile` | Server Manager | Headless services, firewall, systemd monitoring & AI serving |
| **Profiles** | `genixbit-os-creator-profile` | Creator Studio | Hardware media codecs, OBS Studio, Blender, audio/video tools |
| **Hardware** | `genixbit-os-gpu-diagnostics` | `genixbit-gpu-diag` | Hardware accelerator detection for NVIDIA, AMD ROCm, Intel Arc |
| **AI Runtime** | `genixbit-os-ai-runtime` | `genixbit-ai-proxy` | Local OpenAI/Ollama compatible API proxy on `127.0.0.1:11434` |
| **AI Center** | `genixbit-os-ai-center` | `genixbit-ai-center` | Model lifecycle manager, GGUF puller, quantization engine |
| **Agents** | `genixbit-os-agents` | `genixbit-agent` | Bridge for Antigravity SDK, Gemini CLI, Cursor, and Codex |
| **App Store** | `genixbit-os-store` | `genixbit-store` | Curated app store for Flatpaks, developer tools, and AI runtimes |
| **Indic AI** | `genixbit-os-indic-llm` | `genixbit-bharat`<br>`genixbit-mesh` | 22 Indian language translation & LAN P2P AI compute mesh |
| **Security** | `genixbit-os-security-guard` | `genixbit-guard`<br>`genixbit-sandbox`<br>`genixbit-zram` | Agent policy guard, user namespace sandbox, adaptive LZ4 ZRAM |
| **MicroVM** | `genixbit-os-microvm` | `genixbit-microvm`<br>`genixbit-quant`<br>`genixbit-lora` | Sub-second (&lt;120ms) MicroVM runner, GGUF engine, LoRA swapper |
| **Vision RAG** | `genixbit-os-vision-rag` | `genixbit-vision`<br>`genixbit-rag` | UI hierarchy perception, screen OCR, 1024-D local vector RAG |
| **Swarm** | `genixbit-os-swarm` | `genixbit-swarm`<br>`genixbit-pipeline` | Multi-agent swarm orchestrator & offline AI CI/CD pipeline |
| **Control** | `genixbit-os-control-center` | `genixbit-control-center` | Appearance hub, theme switcher, accent colors & AI monitor |
| **Launcher** | `genixbit-os-quick-launcher` | `genixbit-launcher` | Spotlight HUD search overlay & inline `@ai` prompt runner |
| **Icons** | `genixbit-os-icons` | `GenixBit-Icons` | Scalable vector SVG icon theme for all native apps |

---

## 📥 Verified Production ISO Releases (1.38 GB Each)

All ISOs are built with **Debian/Ubuntu canonical `grub-mkstandalone` standalone EFI bootloaders**, FAT12 `efiboot.img`, and verified on both BIOS and UEFI engines.

| Release | Codename | Size | SHA256 Hash | Direct Download |
| :--- | :--- | :--- | :--- | :--- |
| **1.5.0** | *Sutra* | **1.38 GB** | `d983aececc2cbd6eb9e231dd0b13939ef229ed8bca0c56708b5dd8eafd64c5cf` | [📥 **Download 1.5.0**](https://packages.os.genixbit.com/iso/GenixBitOS-1.5.0-sutra-20260817.iso.zip) |
| **1.4.0** | *Drishti* | **1.38 GB** | `6bac59e3c8cce9611f8196b3efdaeee226d36f2785a0c452489f56a4e1a98f62` | [📥 **Download 1.4.0**](https://packages.os.genixbit.com/iso/GenixBitOS-1.4.0-drishti-20260817.iso.zip) |
| **1.3.0** | *Vayu* | **1.38 GB** | `9df976c53e6ddf717e49bd4ae57d510253146f2f2c3ecaed28a42bff470c73ba` | [📥 **Download 1.3.0**](https://packages.os.genixbit.com/iso/GenixBitOS-1.3.0-vayu-20260817.iso.zip) |
| **1.2.0** | *Kavach* | **1.38 GB** | `438ba579f25b742f2d39ffbf3d0114692647981558b4a3b7bd981e0b2d0f3cb2` | [📥 **Download 1.2.0**](https://packages.os.genixbit.com/iso/GenixBitOS-1.2.0-kavach-20260817.iso.zip) |
| **1.1.0** | *Shakti* | **1.38 GB** | `591e4006c88e11f9a532fb4c0e734e850f381ca515ee98c25e05095c8a6f7098` | [📥 **Download 1.1.0**](https://packages.os.genixbit.com/iso/GenixBitOS-1.1.0-shakti-20260817.iso.zip) |
| **1.0.0 LTS** | *Foundation* | **1.38 GB** | `ee77980f131176f4f42e7bdcea6a7318f7cc13b18921dd6a83e664bcfecb5110` | [📥 **Download 1.0.0 LTS**](https://packages.os.genixbit.com/iso/GenixBitOS-1.0.0-lts-2311142213.iso.zip) |

---

## 💻 Running in Virtual Machines (UTM / VirtualBox / QEMU)

### On Apple Silicon Mac (UTM):
1. Download and extract the `.iso` file.
2. Open **UTM** -> Click **`+`** (Create VM) -> Select **"Emulate"** (*Do not select "Virtualize" on Apple Silicon for x86_64 ISOs*).
3. Select **"Linux"** -> Browse and select the extracted `.iso`.
4. Set **RAM**: `2048 MB` (or `4096 MB`), **CPU**: `2 cores`.
5. Click **Save** -> Click **Play (▶️)** -> Select **"Try or Install GenixBit OS"** in GRUB!

---

## 🧪 Unified Release CI Gate

Run the full automated pre-release test suite:
```bash
bash tools/ci-full-release-gate.sh
```
Executes all 9 release gates with 100% PASS enforcement across shell syntax, Python compilation, 23-package Debian audit, version consistency, upstream compliance, package migration, and AI proxy unit tests.

---

## 📄 License & Governance

- **License**: GNU General Public License v3.0 ([`LICENSE`](LICENSE))
- **Governance**: [`GOVERNANCE.md`](GOVERNANCE.md)
- **Open Source Attribution**: [`OSS.md`](OSS.md) & [`UPSTREAM.md`](UPSTREAM.md)
- **Security Policy**: [`SECURITY.md`](SECURITY.md)
