# GenixBit Package Infrastructure Migration Roadmap

This document outlines the planned migration path from upstream AnduinOS package infrastructure to dedicated **GenixBit OS** package repository infrastructure.

---

## Migration Principle

> [!CAUTION]
> **No Premature Dependency Breakage**: Upstream AnduinOS package infrastructure references (`packages.anduinos.com`, `anduinos-apt-config`, `anduinos-archive-keyring`) must remain active in build scripts until the GenixBit package server (`packages.os.genixbit.com`) is fully provisioned, signed, tested, and verified.

---

## Infrastructure Mapping

| Subsystem | Temporary Upstream Dependency | Planned GenixBit Infrastructure |
| :--- | :--- | :--- |
| **Package Server Domain** | `https://packages.anduinos.com` | `https://packages.os.genixbit.com` |
| **Archive Keyring Package** | `anduinos-archive-keyring` | `genixbit-os-archive-keyring` |
| **Archive GPG Key Name** | `anduinos` | `genixbit-os` |
| **APT Configuration Package** | `anduinos-apt-config` | `genixbit-os-apt-config` |
| **Base Files Package** | `base-files` (upstream overlay) | `genixbit-os-base-files` |
| **Installer Configuration** | `anduinos-installer-config` | `genixbit-os-installer-config` |
| **Desktop Metapackage** | `anduinos-desktop` | `genixbit-os-desktop` |

---

## Migration Prerequisites

Before updating repository URLs and package names in `args.sh`, `build.sh`, and `mods/`, the following prerequisites must be met:

1. **Package Server Provisioning**: Production APT repository host running at `packages.os.genixbit.com` serving Debian archive metadata over HTTPS.
2. **GPG Key Management**: Secure generation and publication of the official GenixBit OS archive signing GPG key pair (`genixbit-os-archive-keyring.gpg`).
3. **Package Building & Mirroring**: Successful compilation and signing of core overlay packages (`genixbit-os-apt-config`, `genixbit-os-archive-keyring`, `genixbit-os-base-files`, `genixbit-os-desktop`).
4. **Integration Verification**: Testing debootstrap and chroot APT resolution against `packages.os.genixbit.com` on a test build runner.
