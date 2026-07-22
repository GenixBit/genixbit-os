# GenixBit OS Package Repository Layout & Promotion Policy

## Overview

The GenixBit OS package repository hosted at `packages.os.genixbit.com` manages distribution of GenixBit-owned Debian packages, desktop configurations, core identity files, and platform applications.

## Distribution Channels

```text
┌─────────────────────────────────────────────────────────────┐
│                      alpha channel                          │
│     (Bleeding-edge builds, developer testing, CI targets)   │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Automated validation PASS)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     testing channel                         │
│     (Staging candidate validation, VM integration tests)    │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Release validation PASS)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                      stable channel                         │
│       (Production release channels, end-user updates)       │
└─────────────────────────────────────────────────────────────┘
```

| Channel | Codename Pattern | Target Audience | Promotion Criteria |
| --- | --- | --- | --- |
| `alpha` | `resolute-alpha` | Developers, internal CI | Package build + Docker installation tests PASS |
| `testing` | `resolute-testing` | QA, Release Engineers | Complete disposable package test suite PASS |
| `stable` | `resolute-stable` | End users, production | Candidate ISO release validation PASS |

## Repository Architecture & Directory Structure

```text
dists/
├── resolute-alpha/
│   ├── Release
│   ├── Release.gpg
│   ├── InRelease
│   └── main/
│       └── binary-amd64/
│           ├── Packages
│           ├── Packages.gz
│           └── Release
├── resolute-testing/
│   └── ...
└── resolute-stable/
    └── ...
pool/
└── main/
    ├── g/
    │   ├── genixbit-os-archive-keyring/
    │   ├── genixbit-os-apt-config/
    │   └── genixbit-os-base-files/
    └── ...
```

## Package Promotion & Rollback Metadata

1. **Promotion Workflow**:
   - Packages are uploaded to `pool/main/g/<package>/` with unique debian version strings (`<version>-genixbit<build>`).
   - Repository index files (`dists/<channel>/main/binary-amd64/Packages`) link to immutable `.deb` files in the pool.
   - Promoting a package from `testing` to `stable` involves updating index references and re-signing `InRelease` without mutating the underlying `.deb` file.

2. **Rollback Procedures**:
   - Previous versions remain preserved in `pool/` to allow instant rollback by updating channel manifests.
   - In emergency regressions, `apt-pinning` metadata or higher epoch versions (`1:<version>`) are deployed to force downgrade on installed client systems.
