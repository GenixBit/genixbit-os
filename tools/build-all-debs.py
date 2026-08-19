#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build all 20 native GenixBit OS Debian packages (.deb) into packages/build-debs."""

import os
import pathlib
import shutil
import subprocess
import sys

def build_package(pkg_dir, out_dir):
    pkg_name = pkg_dir.name
    control_file = pkg_dir / "debian" / "control"
    install_file = pkg_dir / "debian" / "install"

    if not control_file.exists():
        return None

    # Parse control
    control_text = control_file.read_text(encoding="utf-8")
    pkg_meta = {}
    for line in control_text.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            pkg_meta[k.strip()] = v.strip()

    version = "1.0.0-lts-1"
    arch = pkg_meta.get("Architecture", "all")
    deb_filename = f"{pkg_name}_{version}_{arch}.deb"

    stage_dir = out_dir / f"{pkg_name}_stage"
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    
    debian_dir = stage_dir / "DEBIAN"
    debian_dir.mkdir(parents=True, exist_ok=True)

    # Write control
    stage_control = f"""Package: {pkg_name}
Version: {version}
Section: {pkg_meta.get('Section', 'utils')}
Priority: {pkg_meta.get('Priority', 'optional')}
Architecture: {arch}
Maintainer: {pkg_meta.get('Maintainer', 'GenixBit Labs Private Limited <maintainers@genixbit.com>')}
Description: {pkg_meta.get('Description', pkg_name)}
"""
    (debian_dir / "control").write_text(stage_control, encoding="utf-8")

    # Install files based on debian/install
    if install_file.exists():
        for line in install_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                src_pattern = parts[0]
                tgt_dir = parts[1].lstrip("/")
                src_path = pkg_dir / src_pattern
                dest_dir = stage_dir / tgt_dir
                dest_dir.mkdir(parents=True, exist_ok=True)
                if src_path.is_file():
                    shutil.copy2(src_path, dest_dir / src_path.name)
                elif src_path.is_dir():
                    shutil.copytree(src_path, dest_dir / src_path.name, dirs_exist_ok=True)

    # Also copy usr/ and bin/ directly if present
    for d in ["bin", "usr", "etc"]:
        src_d = pkg_dir / d
        if src_d.exists():
            if d == "bin":
                dest_d = stage_dir / "usr" / "bin"
            else:
                dest_d = stage_dir / d
            dest_d.mkdir(parents=True, exist_ok=True)
            for item in src_d.glob("**/*"):
                if item.is_file():
                    rel = item.relative_to(src_d)
                    target_file = dest_d / rel
                    target_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, target_file)

    # Set permissions
    for root, dirs, files in os.walk(stage_dir):
        for f in files:
            fp = os.path.join(root, f)
            if "/bin/" in fp or "/usr/bin/" in fp:
                os.chmod(fp, 0o755)
            else:
                os.chmod(fp, 0o644)

    # Build deb
    out_deb = out_dir / deb_filename
    subprocess.run(["dpkg-deb", "--build", str(stage_dir), str(out_deb)], check=True, capture_output=True)
    shutil.rmtree(stage_dir)
    return out_deb

def main():
    root = pathlib.Path.cwd().resolve()
    packages_dir = root / "packages"
    out_dir = packages_dir / "build-debs"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("============================================================")
    print("      GenixBit OS 20-Package Native Debian Builder          ")
    print("============================================================")

    built = []
    for pkg_dir in sorted(packages_dir.glob("genixbit-os-*")):
        if pkg_dir.is_dir():
            print(f"[BUILD] Packaging {pkg_dir.name}...")
            deb = build_package(pkg_dir, out_dir)
            if deb:
                built.append(deb)
                print(f"  -> Generated: {deb.name} ({deb.stat().st_size} bytes)")

    print(f"\n[PASS] Successfully built all {len(built)} native Debian packages in packages/build-debs/")

if __name__ == "__main__":
    main()
