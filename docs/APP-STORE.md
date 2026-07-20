# GenixBit Store

## Vision

The **GenixBit Store** is the planned application and AI discovery experience for GenixBit OS.

It should help developers, server managers, creators, learners, and general users find trusted software without turning GenixBit OS into a closed ecosystem.

## Product Principles

- GenixBit Store is a curated installer and catalog, not a claim of ownership over third-party applications.
- Prefer official application sources and verified publishers.
- Show license, source, permissions, install method, update method, disk usage, architecture, and support status before installation.
- Use sandboxed formats where practical.
- Do not silently add third-party repositories or background services.
- Do not repackage proprietary software without permission.
- Make every installation removable and auditable.
- Separate application catalog metadata from package-signing infrastructure.

## Catalog Categories

### Development

IDEs, editors, terminals, Git tools, databases, API clients, containers, Kubernetes tools, language toolchains, testing utilities, and observability tools.

### AI and Models

GenixBit AI Center, approved local runtimes, model catalog entries, embedding services, vector databases, transcription tools, image workflows, evaluation tools, and GenixBit Agents integrations.

### Server and Operations

SSH tools, monitoring, backup, firewall management, container management, web servers, database administration, log analysis, and remote-access utilities.

### Creator

Video editing, audio editing, 3D design, image editing, streaming, screen recording, captioning, transcription, media conversion, and asset-management tools.

### Productivity and Communication

Browsers, office tools, note-taking, collaboration, messaging, password managers, file synchronization, and accessibility tools.

### Learning

GenixBit Academy, coding exercises, Linux guides, AI starter projects, notebooks, datasets, and development templates.

## Supported Installation Backends

### GenixBit APT Repository

For GenixBit-owned system components, signed OS packages, themes, installer configuration, AI Center, Store application, agent integration, and tightly integrated desktop components.

### Ubuntu APT Repositories

For packages inherited from the Ubuntu base. The Store should show the actual package source.

### Flatpak and Flathub

For sandboxed desktop applications where publisher verification, permissions, and update behavior are suitable. Flathub should be treated as an external source and clearly labelled.

### Official Vendor Repositories

Only after a user confirms the repository addition and the Store displays the vendor, signing method, update channel, and removal instructions.

### AppImage or Direct Downloads

Only for applications that do not provide a safer managed channel. Downloads should be checksum-verified where upstream publishes a digest or signature.

### AI Model Sources

Model files remain separate from normal application packages. The AI Center should manage model metadata, license acceptance, disk usage, runtime compatibility, and removal. See [`AI-MODEL-CATALOG.md`](AI-MODEL-CATALOG.md).

## Store Metadata

Each application entry should include:

```yaml
id: reverse.dns.identifier
name: Application Name
summary: Short factual description
publisher: Verified publisher name
homepage: Official homepage
source_code: Optional official source URL
license: SPDX or proprietary label
install_backend: genixbit-apt | ubuntu-apt | flatpak | vendor-apt | appimage
package_id: Backend-specific identifier
architectures:
  - amd64
categories:
  - development
permissions:
  - network
update_method: apt | flatpak | vendor | manual
verified_by_genixbit: false
last_reviewed: YYYY-MM-DD
```

## Trust Levels

- **GenixBit System Component**: built, signed, and maintained by GenixBit.
- **Verified Upstream**: official publisher source reviewed by GenixBit.
- **Community Source**: useful but not officially maintained by GenixBit.
- **Experimental**: testing-only entry with visible warning.
- **Blocked**: known security, licensing, malware, abandonment, or compatibility concern.

## Security Requirements

- Catalog metadata must be signed or integrity-verified.
- Package signatures must be validated by the native package manager.
- Flatpak permissions must be displayed before installation.
- Direct downloads must not execute automatically.
- Post-install scripts require review for GenixBit-owned packages.
- Store processes should run without root until the system package manager requests authorization.
- No payment or account credentials should be stored before a reviewed security design exists.
- Remote catalog compromise must not allow arbitrary root command execution.

## App Publishing Roadmap

### Stage 1: Curated Links and Install Recipes

Static catalog with verified official sources and human-reviewed install instructions.

### Stage 2: Native Store Client

Search, category browsing, source display, installation, removal, update status, and permission review.

### Stage 3: GenixBit Publisher Portal

GenixBit-controlled submission and review workflow for approved publishers. This is not open self-publication during early alpha.

### Stage 4: Application Build and Signing Pipeline

Reproducible builds, security scanning, package signing, release promotion, rollback, and audit records.

### Stage 5: Commercial Capabilities

Only after legal, tax, billing, refund, regional compliance, content moderation, security, and publisher agreements are complete.

## Naming

The user-facing name should be **GenixBit Store**. Internal package and service identifiers should use stable lowercase names such as `genixbit-os-appstore` and `store.os.genixbit.com` if that domain is approved later.
