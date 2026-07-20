# GenixBit OS Governance

## Official Project Stewardship

**GenixBit OS** is an official product of **GenixBit Labs Private Limited**.

The public source repository remains available under the GNU General Public License v3.0, but the official project, product roadmap, release channels, package-signing infrastructure, websites, trademarks, and distribution decisions are controlled by GenixBit Labs Private Limited.

## Maintainer Model

During the early-alpha stage, GenixBit OS uses a **closed maintainer model**:

- Only authorized members of the GenixBit team may approve or merge changes into official branches.
- Only authorized GenixBit release maintainers may publish ISO images, packages, signing keys, release notes, or official announcements.
- Only GenixBit infrastructure administrators may operate the official websites, documentation service, download service, package repository, update service, and app catalog.
- Repository ownership, branch protection, CODEOWNERS, signing keys, DNS, deployment credentials, and release credentials must remain under GenixBit-controlled accounts.

## External Participation

External users may:

- inspect the source code;
- fork the repository under the terms of GPL-3.0;
- report reproducible bugs;
- submit security reports privately;
- suggest features through GitHub issues;
- share compatibility test results.

Unsolicited external code pull requests are not accepted during the early-alpha closed-maintainer period unless a GenixBit maintainer explicitly invites the contribution.

This policy controls the official GenixBit repository and release process. It does not remove or restrict rights granted by GPL-3.0 to copy, modify, study, fork, or redistribute covered source code in compliance with that license.

## Official Versus Unofficial Builds

A build is official only when it is:

1. produced from a GenixBit-controlled repository and approved commit;
2. built through a GenixBit-controlled release pipeline;
3. signed or checksummed through GenixBit-controlled release infrastructure;
4. published through an official GenixBit domain or GitHub release channel; and
5. listed in official GenixBit release documentation.

Community forks and modified versions must not imply endorsement by GenixBit Labs Private Limited and must not use GenixBit trademarks in a misleading way.

## Licensing and Attribution

- GPL-covered source code remains under GPL-3.0.
- Existing upstream copyright and license notices must remain intact.
- Third-party packages and model files retain their own licenses and usage terms.
- The names **GenixBit**, **GenixBit OS**, **GenixBit Labs**, associated logos, artwork, visual identity, domain names, and official release marks are separate brand assets and are not automatically licensed for unrestricted trademark use by GPL-3.0.

See [`LICENSE`](LICENSE), [`UPSTREAM.md`](UPSTREAM.md), and [`OSS.md`](OSS.md).

## Decision Authority

Final authority for the official project rests with GenixBit Labs Private Limited. Technical decisions should be documented through issues, architecture decision records, pull requests, release notes, and roadmap updates.
