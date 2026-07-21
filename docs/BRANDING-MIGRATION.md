# GenixBit OS Branding Migration

## Objective

Every user-facing surface in an official GenixBit OS release should present **GenixBit OS** as the operating-system product name and **GenixBit Labs Private Limited** as the official maintainer.

This must be completed without removing legally required upstream attribution or breaking temporary package dependencies inherited from AnduinOS 2.

## Non-Negotiable Rules

1. Do not perform a blind global replacement of `AnduinOS`, `anduinos`, `Aiursoft`, or upstream URLs.
2. Preserve `LICENSE`, `UPSTREAM.md`, `OSS.md`, copyright notices, package licenses, and source attribution.
3. Replace user-facing branding only through GenixBit-controlled files and packages.
4. Keep temporary upstream package names and repository identifiers until verified GenixBit replacements exist.
5. Never imply that inherited upstream code was originally authored solely by GenixBit.
6. Official GenixBit logos and trademarks must not be copied from upstream artwork.

## User-Facing Surfaces to Replace

### Boot and Installation

- ISO filename and volume label;
- GRUB menu titles;
- live-session name and hostname;
- Plymouth boot splash;
- installer launcher name and icon;
- installer slideshow, welcome text, URLs, and artwork;
- `.disk/info` and ISO-root documentation;
- recovery and integrity-check screens.

### Installed System Identity

- `/etc/os-release`;
- `/etc/lsb-release`;
- `/etc/issue` and `/etc/issue.net`;
- system hostname defaults;
- support, privacy, documentation, bug-report, and home URLs;
- About/System Information branding;
- terminal welcome and MOTD where used;
- default browser home page;
- package-origin and update-channel labels.

### Desktop Experience

- application-menu logo;
- GNOME shell theme and extensions;
- wallpapers and lock screens;
- icons, cursors, accent colors, and fonts;
- default favorites and desktop shortcuts;
- software-store launcher;
- AI Center and GenixBit Store launchers;
- help and documentation shortcuts.

### Server and CLI Experience

- login banner;
- SSH issue text;
- system diagnostics output;
- update and repair command names;
- package-source descriptions;
- service documentation and support links.

## Required GenixBit Packages

The complete migration should be implemented with separately versioned packages:

| Package | Purpose |
| --- | --- |
| `genixbit-os-base-files` | `/etc/os-release`, issue files, URLs, core identity |
| `genixbit-os-apt-config` | signed GenixBit APT source configuration |
| `genixbit-os-archive-keyring` | public verification keyring only |
| `genixbit-os-desktop` | desktop metapackage and default application set |
| `genixbit-os-theme` | GNOME, shell, GTK, icons, cursors, and appearance |
| `genixbit-os-wallpapers` | official light/dark wallpapers and lock-screen assets |
| `genixbit-os-installer-config` | installer identity, slideshow, links, and defaults |
| `genixbit-os-appstore` | GenixBit Store desktop application |
| `genixbit-os-ai-center` | local AI runtime and model manager |
| `genixbit-os-agent-integration` | optional GenixBit Agents integration |
| `genixbit-os-release` | version/channel metadata and release configuration |

## Temporary Upstream Dependencies

The following references may remain temporarily because they are technical dependencies rather than desired branding:

- `packages.anduinos.com`;
- `anduinos-apt-config`;
- `anduinos-archive-keyring`;
- `anduinos-installer-config`;
- `anduinos-bwrap-hack`;
- other upstream package names installed by the current build pipeline.

These dependencies must be clearly documented and replaced only after the GenixBit package repository, signing key, replacement packages, rollback plan, and clean-install tests are ready.

## Branding Audit Method

For every reference, classify it as:

1. **Legal attribution — keep**
2. **Technical dependency — keep temporarily**
3. **User-facing brand — replace through a GenixBit package**
4. **Documentation/history — keep with context**
5. **Unknown — manual review required**

Recommended audit commands on a local clone:

```bash
git grep -nEi 'AnduinOS|anduinos|Aiursoft|anduin'
```

After building an ISO, inspect the mounted image and installed VM:

```bash
grep -RInE 'AnduinOS|anduinos|Aiursoft|anduin' /etc /usr/share 2>/dev/null
```

Do not treat search output as an automatic deletion list.

## Release Acceptance Criteria

A release may be described as fully GenixBit-branded only when:

- the boot menu, live session, installer, installed system, desktop, settings, support links, and update channels show GenixBit OS;
- no upstream logo or user-facing upstream product name remains unintentionally;
- mandatory attribution remains available in source and legal documentation;
- all replacement packages come from signed GenixBit infrastructure;
- clean install, upgrade, removal, rollback, and offline boot tests pass;
- screenshots are taken from an actual validated GenixBit OS build.

## Hardening Cycle 0.2.0-alpha (Completed July 2026)

The branding package integration was fully hardened for the `0.2.0-alpha` release cycle with the following implementations:

1. **Asset Generation & Preserving Geometry**:
   - Dynamic asset creation via PIL (`tools/validation/generate-branding-assets.py`) to process the official GenixBit GB monogram and horizontal lockup.
   - All vector outputs (`.svg` files) embed the high-resolution PNG/JPG files via base64 data URIs to guarantee 100% exact design geometry with zero manual tracing distortion.
   - Wallpaper renders scaled and cropped to `1920x1080`, `2560x1440`, and `3840x2160` without distortion.
2. **Safe dpkg-divert Implementation**:
   - Avoided blind overwriting of the essential `/etc/os-release`, `/usr/lib/os-release`, `/etc/lsb-release`, `/etc/issue`, and `/etc/issue.net` files.
   - Registered diversions using `dpkg-divert --add --rename` in the `preinst` maintainer script of `genixbit-os-base-files`.
   - Restored original files using `dpkg-divert --remove --rename` in the `postrm` script during removal and purge.
   - Dynamically generated `/etc/` overlay files in the `postinst` script to completely bypass any conffile prompts or conflicts and prevent accidental file deletion during purge operations.
3. **Disposable Container-Based Lifecycle Testing**:
   - Created a validation pipeline (`tools/validation/test-packages.sh` and `test-branding-packages-disposable.sh`) executed inside a disposable `ubuntu:26.04` Docker container.
   - Verified clean installs, package upgrades, rollback (downgrades), remove, and purge lifecycles.
   - Successfully validated that the original Ubuntu identity files are completely restored upon package purge, and the OS release file is never left missing.

## GenixBit Branding Foundation Status

- Branding package source: PASS
- Transparent asset generation: PASS
- Package build: PASS
- Install: PASS
- Upgrade: PASS
- Rollback: PASS
- Purge: PASS
- Identity restoration: PASS
- ISO integration: NOT_TESTED
- BIOS branding: NOT_TESTED
- UEFI branding: NOT_TESTED
- Installer branding: NOT_TESTED
- Installed-system branding: NOT_TESTED

