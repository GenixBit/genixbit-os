# GenixBit OS AI-First Platform

## Product Mission

GenixBit OS is being designed as an **AI-first Linux operating system for developers, application builders, server managers, video creators, AI learners, and modern technical teams**.

AI-first does not mean forcing one vendor, one cloud account, or one model onto every user. It means the operating system provides a trusted foundation for discovering, installing, running, building, evaluating, and managing local or cloud-assisted AI tools with clear permissions and user control.

## Core User Groups

### Developers and Application Builders

- language runtimes and toolchains;
- containers and reproducible development environments;
- local model APIs;
- coding agents and repository-aware assistants;
- model evaluation, prompt testing, and app templates;
- integration with IDEs, terminals, MCP servers, and automation tools.

### AI Learners and First-Time Builders

- guided setup profiles;
- hardware-aware model recommendations;
- starter projects for chat, RAG, agents, vision, speech, and coding;
- clear explanations of model size, memory, quantization, privacy, and licensing;
- GenixBit Academy learning paths.

### Server Managers and DevOps Teams

- headless and workstation profiles;
- containerized model serving;
- OpenAI-compatible local endpoints where supported;
- service health, logs, resource limits, firewall guidance, and GPU diagnostics;
- optional remote administration with strong access controls.

### Video and Creative Professionals

- GPU and codec readiness;
- video editing, transcoding, speech-to-text, captioning, image generation, asset search, and workflow automation;
- optional local AI models where hardware permits;
- creator applications distributed through the future GenixBit Store.

## Platform Layers

### 1. GenixBit OS Base

Ubuntu-compatible package base, GNOME desktop, systemd, kernel, drivers, security controls, Flatpak support, container tooling, and the GenixBit visual identity.

### 2. GenixBit AI Runtime Layer

A pluggable runtime abstraction supporting local and self-hosted engines such as:

- Ollama;
- llama.cpp-compatible GGUF runtimes;
- vLLM for suitable server hardware;
- containerized inference services;
- GenixBit Bharat-V1 runtimes when model checkpoints are ready and validated.

No third-party model weight should be bundled into the ISO by default. Model downloads must be optional, license-aware, hardware-aware, checksum-verifiable, and removable.

### 3. GenixBit AI Center

Planned desktop application for:

- detecting CPU, RAM, GPU, VRAM, disk space, and supported acceleration;
- browsing approved model metadata;
- filtering by task, language, license, size, and hardware tier;
- installing or removing runtimes and models;
- starting and stopping local model services;
- displaying disk, memory, and GPU usage;
- exposing local API connection details;
- managing privacy and cloud-access settings;
- viewing model terms before download.

### 4. GenixBit Agents

The existing [`GenixBit/agency-agents`](https://github.com/GenixBit/agency-agents) project supports Antigravity, Gemini CLI, Codex, Cursor, OpenCode, and other agent environments.

GenixBit OS should integrate this project through an optional installer and profile manager, not by duplicating the entire agent repository inside the operating-system source tree.

Planned integration:

- install selected agent divisions;
- discover supported agent tools;
- manage agent configuration paths;
- update agent definitions from signed GenixBit releases;
- show exactly which files will be created or modified;
- require user approval before modifying external tool configuration;
- never simulate an active agent backend when none is configured.

### 5. GenixBit Developer Studio

Planned application-building workspace connecting:

- local models;
- cloud models chosen by the user;
- code editors and terminals;
- containers;
- project templates;
- agents;
- MCP-compatible tools;
- deployment targets;
- testing and evaluation workflows.

### 6. GenixBit Store

A future discovery and installation experience for applications, developer tools, AI runtimes, model integrations, creator tools, server utilities, and GenixBit packages. See [`APP-STORE.md`](APP-STORE.md).

### 7. GenixBit Cloud Services

Optional services may provide documentation, signed packages, update metadata, app catalog metadata, model catalog metadata, release downloads, and account-based features. The operating system must remain usable without mandatory cloud telemetry.

## GenixBit Product Connections

- **GenixBit Agents**: optional multi-agent profiles and tool integrations.
- **Bharat AI / IndicLLM-Bharat-V1**: future Indian-language model family after training, evaluation, safety, and release requirements are met.
- **Genius AI**: potential user-facing AI workspace integration through documented APIs.
- **GenixBit Academy**: guided AI, Linux, development, and deployment learning paths.
- **Space Intelligence**: an example GenixBit product that can be developed and operated on the platform, not a default OS dependency.

## Trust Principles

1. **Local-first where practical**: local processing should be available for compatible models and hardware.
2. **Cloud optional**: users choose whether to configure external providers.
3. **No hidden model downloads**: show size, source, license, checksum, and storage location.
4. **No hidden execution**: users control services, agents, background processes, and network access.
5. **No fake capability**: unavailable backends must be shown as unavailable or not configured.
6. **No default credential collection**: provider keys remain user-managed and must never be committed or placed in system-wide plaintext.
7. **Hardware-aware choices**: avoid recommending models that cannot run acceptably on detected hardware.
8. **License-aware distribution**: open weights, open source, and free access are different concepts and must be labelled accurately.
9. **Reversible installation**: AI runtimes and model files must be removable without damaging the base OS.
10. **Measured claims**: performance and quality claims require recorded tests.

## Proposed Hardware Profiles

| Profile | Typical Hardware | Intended AI Use |
| --- | --- | --- |
| Starter | 8 GB RAM, CPU inference | compact text models, learning, prompt experiments |
| Developer | 16–32 GB RAM, optional 8–12 GB VRAM | coding, RAG, agents, small multimodal models |
| Creator | 32–64 GB RAM, 12–24 GB VRAM | transcription, image/video workflows, larger local models |
| AI Workstation | 64 GB+ RAM, 24 GB+ VRAM | larger models, fine-tuning experiments, multi-service workflows |
| Server | headless amd64, managed GPU/CPU | shared inference, automation, internal APIs, scheduled jobs |

These are planning profiles, not performance guarantees.

## Delivery Sequence

1. Validate the baseline ISO.
2. Replace user-visible upstream branding with GenixBit-controlled packages.
3. Establish the signed GenixBit APT repository.
4. Add developer and creator profiles.
5. Package optional AI runtimes.
6. Launch the model catalog and AI Center.
7. Integrate GenixBit Agents.
8. Launch the GenixBit Store.
9. Add optional cloud and team administration features.

AI features must not block the baseline OS, package migration, security, or update infrastructure work.
