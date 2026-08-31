#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build native GenixBit OS Debian packages into packages/build-debs/."""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile


REQUIRED_DEBIAN_FILES = ("control", "changelog", "rules")


def validate_package_source(pkg_dir: pathlib.Path) -> None:
    debian_dir = pkg_dir / "debian"
    missing = [name for name in REQUIRED_DEBIAN_FILES if not (debian_dir / name).is_file()]
    if missing:
        joined = ", ".join(f"debian/{name}" for name in missing)
        raise RuntimeError(f"{pkg_dir.name}: missing required Debian metadata: {joined}")


def build_package(pkg_dir: pathlib.Path, out_dir: pathlib.Path) -> list[pathlib.Path]:
    """Build one source package using its real Debian packaging metadata."""
    validate_package_source(pkg_dir)

    with tempfile.TemporaryDirectory(prefix=f"genixbit-{pkg_dir.name}-") as temp_dir:
        temp_root = pathlib.Path(temp_dir)
        source_copy = temp_root / pkg_dir.name

        # Preserve package symlinks as symlinks. Debian tooling will apply the package's
        # own install rules, relationship fields, maintainer scripts, and substvars.
        shutil.copytree(pkg_dir, source_copy, symlinks=True)

        # -b builds binary packages only; -us/-uc keep local developer builds unsigned.
        # Official release signing remains a separate release-governance operation.
        subprocess.run(
            ["dpkg-buildpackage", "-b", "-us", "-uc"],
            cwd=source_copy,
            check=True,
        )

        generated = sorted(temp_root.glob("*.deb"))
        if not generated:
            raise RuntimeError(f"{pkg_dir.name}: dpkg-buildpackage produced no .deb files")

        outputs: list[pathlib.Path] = []
        for deb in generated:
            destination = out_dir / deb.name
            shutil.move(str(deb), destination)
            outputs.append(destination)

        return outputs


def clean_generated_output(out_dir: pathlib.Path) -> None:
    """Remove only generated package output while preserving the tracked .gitkeep."""
    for entry in out_dir.iterdir():
        if entry.name == ".gitkeep":
            continue
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    packages_dir = root / "packages"
    out_dir = packages_dir / "build-debs"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Never mix stale binaries or abandoned staging directories with a fresh ISO build.
    clean_generated_output(out_dir)

    print("============================================================")
    print("        GenixBit OS Native Debian Package Builder           ")
    print("============================================================")

    package_sources = [
        pkg_dir
        for pkg_dir in sorted(packages_dir.glob("genixbit-os-*"))
        if pkg_dir.is_dir() and (pkg_dir / "debian" / "control").is_file()
    ]
    if not package_sources:
        raise RuntimeError("No native GenixBit Debian package sources were found")

    built: list[pathlib.Path] = []
    for pkg_dir in package_sources:
        print(f"[BUILD] Packaging {pkg_dir.name} with dpkg-buildpackage...")
        outputs = build_package(pkg_dir, out_dir)
        built.extend(outputs)
        for deb in outputs:
            print(f"  -> Generated: {deb.name} ({deb.stat().st_size} bytes)")

    print(
        f"\n[PASS] Successfully built {len(built)} native Debian binary package(s) "
        "in packages/build-debs/"
    )


if __name__ == "__main__":
    main()
