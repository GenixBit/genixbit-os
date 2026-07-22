# GenixBit OS Package Repository Architecture

## Overview

The GenixBit OS package update architecture (`packages.os.genixbit.com`) is designed around strict separation of duties, offline master key isolation, automated package staging, and zero trust release verification.

Standard APT security relies on signed repository metadata (`InRelease` or `Release` + `Release.gpg`). Individual `.deb` package files are authenticated via cryptographic hash checksums (`SHA-256`, `SHA-512`) recorded directly inside the signed repository index files.

## Repository Component Layout

```text
packages.os.genixbit.com/
├── dists/
│   ├── resolute-alpha/       # Unstable channel for automated CI and nightly builds
│   ├── resolute-testing/     # Staging channel for release candidate QA
│   └── resolute-stable/      # Official production release channel
└── pool/
    ├── main/                 # Core GenixBit system packages and applications
    └── restricted/           # Third-party firmware or optional drivers
```

## Security Roles & Separation of Duties

| Role | Key / Secret Access | Responsibilities | Authorization Required |
| --- | --- | --- | --- |
| **Offline Root Key Holder** | Passphrase-protected Master RSA 4096 Key | Subkey generation, revocation certificate management | Dual maintainer sign-off |
| **Release Promoter** | Repository Metadata Subkey passphrase | Promoting candidate builds from `alpha`/`testing` to `stable` | Quality gate PASS + Maintainer approval |
| **Package Builder** | Ephemeral GPG build key (non-root) | Compiling `.deb` packages in isolated build chroots | Automated CI / Signed commit |
| **Package Reviewer** | None | Auditing package changelogs, dependencies, and license metadata | Codeowner approval |
| **Repository Publisher** | Remote SSH deploy key | Synchronizing signed `dists/` and `pool/` to public CDN | Automated post-signature workflow |
| **Audit Reviewer** | None | Periodic audit of promotion logs, signature chains, and private audit log | Monthly security audit |

## Verification Guarantee

- APT metadata (`InRelease`, `Release.gpg`) must be signed using the active Repository Metadata Subkey.
- Client systems verify signatures using `genixbit-os-archive-keyring` installed at `/usr/share/keyrings/genixbit-os-archive-keyring.pgp`.
