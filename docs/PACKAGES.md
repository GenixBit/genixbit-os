# GenixBit OS — Native Package System (gbx & .gbx)

## 1. Package Format Specification
The `.gbx` package is a compressed, cryptographically signed tarball containing:
1. `manifest.json`: Metadata, publisher identity, entrypoint, architecture, and permissions.
2. `src/` / binaries: Application source code or compiled executables.
3. Assets: SVG squircle icons and resources.

---

## 2. CLI Command Suite
- `gbx install <file.gbx>`: Installs application into `~/.local/share/genixbit/apps/` with sandboxing.
- `gbx remove <pkg_id>`: Removes application and unlinks desktop shortcuts.
- `gbx list`: Lists installed `.gbx` packages.
- `gbx info <pkg_id>`: Displays detailed package information.
- `gbx verify <file.gbx>`: Verifies SHA256 integrity and digital signatures.
- `gbx audit`: Audits installed packages for vulnerabilities and missing files.
- `gbx doctor`: Evaluates system runtime health.
- `gbx rollback <pkg_id>`: Restores previous package snapshot.
- `gbx create <name>`: Scaffolds a new project directory.
- `gbx build [dir]`: Compiles project into a `.gbx` package.
