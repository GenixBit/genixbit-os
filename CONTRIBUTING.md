# Contributing to GenixBit OS

GenixBit OS is developed and officially maintained by **GenixBit Labs Private Limited**.

The source is public under GPL-3.0, but the official repository currently operates under a **closed maintainer model** while the operating system is in early alpha.

## Who Can Merge Official Changes

Only authorized members of the GenixBit team may approve or merge changes into official branches, publish releases, modify package-signing infrastructure, or deploy official services.

See [`GOVERNANCE.md`](GOVERNANCE.md) and [`.github/CODEOWNERS`](.github/CODEOWNERS).

## External Users

External users are welcome to:

- report reproducible bugs;
- propose features through GitHub issues;
- provide hardware and compatibility test results;
- submit security findings privately as described in [`SECURITY.md`](SECURITY.md);
- inspect, fork, modify, and redistribute GPL-covered source code in compliance with GPL-3.0.

Unsolicited external code pull requests are not accepted during the early-alpha closed-maintainer period unless a GenixBit maintainer explicitly invites the work. Uninvited pull requests may be closed without review.

## GenixBit Team Development Workflow

1. Start from the latest `main` branch.
2. Create a focused feature, fix, documentation, test, release, or infrastructure branch.
3. Make small and reviewable commits.
4. Run repository-quality checks and any component-specific tests.
5. Open a pull request targeting `main`.
6. Obtain GenixBit maintainer approval.
7. Merge only after required checks pass.
8. Prefer squash merge for a clean official history unless a release maintainer decides otherwise.

## Development Requirements

- Preserve GPL-3.0 licensing and upstream attribution.
- Do not remove upstream copyright notices.
- Do not rename temporary upstream package dependencies until verified GenixBit replacements exist.
- Do not commit ISO images, generated build directories, credentials, tokens, private keys, signing keys, or production secrets.
- Do not claim a feature, model, package service, website, or release is available before it has been verified.
- Document all third-party packages, model licenses, and material dependencies.
- Keep local and cloud AI features optional, transparent, and user controlled.

## Commit Prefixes

- `feat:` product or platform capability
- `fix:` defect correction
- `build:` ISO or package build change
- `ci:` automation and repository checks
- `docs:` documentation and governance
- `test:` validation evidence
- `infra:` website, server, DNS, deployment, or package infrastructure
- `chore:` maintenance

## Security

Do not open a public issue containing exploit details, credentials, private keys, or sensitive system information. Follow [`SECURITY.md`](SECURITY.md).
