# Contributing to GenixBit OS

Thank you for your interest in contributing to **GenixBit OS**! We welcome contributions from developers, Linux distribution engineers, designers, security researchers, and technical writers.

---

## Getting Started

1. **Review Project Goals & Roadmap**: Read [`README.md`](README.md), [`UPSTREAM.md`](UPSTREAM.md), and [`ROADMAP.md`](ROADMAP.md) to understand current priorities.
2. **Setup Development Environment**: Review [`docs/BUILDING.md`](docs/BUILDING.md) for host requirements and build instructions.
3. **Check Open Issues**: Before starting new work, search open GitHub issues or create a feature request / bug report to discuss your proposal.

---

## Development Guidelines

### 1. Code & Script Quality
- Write clear, well-commented Bash scripts conforming to strict error handling (`set -euo pipefail`).
- Validate shell script syntax before submitting (`bash -n script.sh`).
- Use descriptive variable names and maintain existing modularity under `mods/`.

### 2. Upstream Compliance & Licensing
- All code contributions must be compatible with the **GNU General Public License v3.0 (GPL-3.0)**.
- Do not remove existing upstream copyright notices, license headers, or legal attributions.
- If introducing third-party components, ensure they are open-source and properly documented in [`OSS.md`](OSS.md).

### 3. Commit Guidelines
- Use clear, descriptive commit messages adhering to conventional commit formatting:
  - `feat:` New features or enhancements
  - `fix:` Bug fixes
  - `docs:` Documentation updates
  - `build:` Build system or script modifications
  - `chore:` Maintenance or refactoring
- Keep pull requests focused on a single logical change.

---

## Pull Request Workflow

1. Fork the repository and create a descriptive feature branch (`git checkout -b feat/my-feature`).
2. Implement and test your changes on a compatible Ubuntu host environment.
3. Ensure no temporary build artifacts, log files, secrets, or generated ISOs are committed.
4. Submit a Pull Request targeting the `main` branch, completing the PR template checklist.

---

## Security Vulnerabilities

Please do **NOT** open public issues for security vulnerabilities. Follow the reporting guidelines in [`SECURITY.md`](SECURITY.md).
