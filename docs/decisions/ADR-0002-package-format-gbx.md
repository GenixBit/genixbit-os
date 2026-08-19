# ADR-0002: Native Package Format (.gbx) and Package Manager (gbx)

## Status
Accepted

## Context
Traditional system package managers (APT, DNF) lack native capability-based sandboxing, developer self-containment, and atomic rollbacks per application. Container-only formats (Flatpak, Snap) often have high runtime overhead or complex permission renegotiation for local AI engines.

## Decision
Create the **`.gbx` (GenixBit eXecutable Bundle)** package format and the **`gbx`** CLI package manager:
- Package format: Tarball archive containing `manifest.json`, signature file `signature.sig`, data payload, icons, and desktop metadata.
- Cryptographic verification: Ed25519 and SHA-256 integrity checks prior to unpacking.
- Sandboxing metadata: Explicit permission declarations (`files`, `network`, `camera`, `ai_runtime`, `gpu`).
- Atomic rollbacks: Automatic snapshotting before package upgrades.

## Consequences
- Clean, auditable application distribution for the GenixBit Store.
- Zero root privileges required for sandboxed user applications.
- Seamless CLI developer workflow (`gbx create`, `gbx build`, `gbx publish`).
