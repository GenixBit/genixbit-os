#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build all binary Debian packages for GenixBit OS 1.0.0 LTS."""

import os
import shutil
import subprocess
import sys

VERSION = "1.0.0-lts"

PACKAGES = [
    {
        "name": "genixbit-os-base-files",
        "version": VERSION,
        "section": "admin",
        "depends": "base-files",
        "description": "GenixBit OS base system identity files\n Provides system release identity, issue files, and OS branding.",
        "files": []
    },
    {
        "name": "genixbit-os-desktop",
        "version": VERSION,
        "section": "metapackages",
        "depends": "genixbit-os-base-files",
        "description": "GenixBit OS desktop environment metapackage\n Metapackage pulling in core desktop session and AI workspace defaults.",
        "files": []
    },
    {
        "name": "genixbit-os-theme",
        "version": VERSION,
        "section": "x11",
        "depends": "genixbit-os-base-files",
        "description": "GenixBit OS desktop and boot splash theme\n Plymouth boot splash, GTK, icon theme, and desktop styling.",
        "files": [
            ("packages/genixbit-os-theme/usr/share/glib-2.0/schemas/99_genixbit-os.gschema.override", "usr/share/glib-2.0/schemas/99_genixbit-os.gschema.override", 0o644)
        ]
    },
    {
        "name": "genixbit-os-wallpapers",
        "version": VERSION,
        "section": "x11",
        "depends": "genixbit-os-base-files",
        "description": "GenixBit OS workstation wallpapers\n Official background wallpaper artwork collection.",
        "files": []
    },
    {
        "name": "genixbit-os-installer-config",
        "version": VERSION,
        "section": "admin",
        "depends": "genixbit-os-base-files",
        "description": "GenixBit OS installer configuration and branding\n Calamares and Ubiquity installer slides and autoinstallation profiles.",
        "files": [
            ("packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides/welcome.html", "usr/share/genixbit-os-installer-config/slides/welcome.html", 0o644),
            ("packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides/privacy_security.html", "usr/share/genixbit-os-installer-config/slides/privacy_security.html", 0o644),
            ("packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides/ai_runtime.html", "usr/share/genixbit-os-installer-config/slides/ai_runtime.html", 0o644),
            ("packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/slides/developer_profiles.html", "usr/share/genixbit-os-installer-config/slides/developer_profiles.html", 0o644)
        ]
    },
    {
        "name": "genixbit-os-archive-keyring",
        "version": VERSION,
        "section": "misc",
        "depends": "gpgv",
        "description": "GenixBit OS APT archive OpenPGP signing keyring\n Official GPG signing key for verifying GenixBit OS package repositories.",
        "files": []
    },
    {
        "name": "genixbit-os-apt-config",
        "version": VERSION,
        "section": "admin",
        "depends": "genixbit-os-archive-keyring",
        "description": "GenixBit OS APT repository channel configurations\n Source list definitions for resolute-alpha, testing, and release channels.",
        "files": []
    },
    {
        "name": "genixbit-os-developer-profile",
        "version": VERSION,
        "section": "metapackages",
        "depends": "genixbit-os-base-files, genixbit-os-desktop",
        "description": "Developer profile metapackage for GenixBit OS\n Provides developer toolchains, container runtimes, version control,\n and language environments for GenixBit OS developer workstations.",
        "files": [
            ("packages/genixbit-os-developer-profile/bin/genixbit-dev-setup", "usr/bin/genixbit-dev-setup", 0o755),
            ("packages/genixbit-os-developer-profile/usr/share/applications/genixbit-dev-setup.desktop", "usr/share/applications/genixbit-dev-setup.desktop", 0o644)
        ]
    },
    {
        "name": "genixbit-os-server-profile",
        "version": VERSION,
        "section": "metapackages",
        "depends": "genixbit-os-base-files",
        "description": "Server manager profile metapackage for GenixBit OS\n Provides headless services, container management, systemd monitoring,\n and remote administration utilities for GenixBit OS server nodes.",
        "files": []
    },
    {
        "name": "genixbit-os-creator-profile",
        "version": VERSION,
        "section": "metapackages",
        "depends": "genixbit-os-base-files, genixbit-os-desktop",
        "description": "Creator profile metapackage for GenixBit OS\n Provides video, audio, image, 3D graphics, streaming, and hardware-accelerated\n codec tooling for GenixBit OS content creation workstations.",
        "files": []
    },
    {
        "name": "genixbit-os-gpu-diagnostics",
        "version": VERSION,
        "section": "utils",
        "depends": "genixbit-os-base-files, pciutils, lshw",
        "description": "Hardware & GPU diagnostic package for GenixBit OS\n Automatic NVIDIA, AMD, and Intel GPU detection tool providing CUDA and ROCm\n runtime capability diagnostics for local AI model acceleration.",
        "files": [
            ("packages/genixbit-os-gpu-diagnostics/bin/genixbit-gpu-diag", "usr/bin/genixbit-gpu-diag", 0o755),
            ("packages/genixbit-os-gpu-diagnostics/bin/genixbit-top", "usr/bin/genixbit-top", 0o755),
            ("packages/genixbit-os-gpu-diagnostics/usr/share/applications/genixbit-gpu-diag.desktop", "usr/share/applications/genixbit-gpu-diag.desktop", 0o644),
            ("packages/genixbit-os-gpu-diagnostics/usr/share/applications/genixbit-top.desktop", "usr/share/applications/genixbit-top.desktop", 0o644)
        ]
    },
    {
        "name": "genixbit-os-ai-runtime",
        "version": VERSION,
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-gpu-diagnostics, python3, curl",
        "description": "AI runtime foundation & local model proxy for GenixBit OS\n Provides local OpenAI-compatible API proxy service, model catalog metadata,\n and hardware-aware Ollama & llama.cpp runtime dispatchers for GenixBit OS.",
        "files": [
            ("packages/genixbit-os-ai-runtime/bin/genixbit-ai-proxy", "usr/bin/genixbit-ai-proxy", 0o755),
            ("packages/genixbit-os-ai-runtime/usr/share/genixbit-os/models/catalog.json", "usr/share/genixbit-os/models/catalog.json", 0o644),
            ("packages/genixbit-os-ai-runtime/usr/lib/systemd/system/genixbit-ai-proxy.service", "usr/lib/systemd/system/genixbit-ai-proxy.service", 0o644)
        ]
    },
    {
        "name": "genixbit-os-ai-center",
        "version": VERSION,
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-ai-runtime, genixbit-os-gpu-diagnostics, python3, curl",
        "description": "GenixBit AI Center model lifecycle manager\n Command-line manager and model lifecycle tool for discovering, downloading,\n installing, and monitoring local AI models on GenixBit OS.",
        "files": [
            ("packages/genixbit-os-ai-center/bin/genixbit-ai-center", "usr/bin/genixbit-ai-center", 0o755),
            ("packages/genixbit-os-ai-center/usr/share/applications/genixbit-ai-center.desktop", "usr/share/applications/genixbit-ai-center.desktop", 0o644)
        ]
    },
    {
        "name": "genixbit-os-agents",
        "version": VERSION,
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-ai-runtime, python3, curl",
        "description": "GenixBit Agents integration package for GenixBit OS\n Developer agent bridge connecting GenixBit OS workstations to GenixBit Agents,\n supporting Antigravity, Gemini CLI, Codex, Cursor, and OpenCode tools.",
        "files": [
            ("packages/genixbit-os-agents/bin/genixbit-agent", "usr/bin/genixbit-agent", 0o755),
            ("packages/genixbit-os-agents/usr/share/applications/genixbit-agent.desktop", "usr/share/applications/genixbit-agent.desktop", 0o644)
        ]
    },
    {
        "name": "genixbit-os-store",
        "version": VERSION,
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-ai-center, python3, curl",
        "description": "GenixBit Store curated application & package manager\n Curated app store interface for developer tools, AI runtimes, server utilities,\n Flatpak applications, and signed GenixBit packages on GenixBit OS.",
        "files": [
            ("packages/genixbit-os-store/bin/genixbit-store", "usr/bin/genixbit-store", 0o755),
            ("packages/genixbit-os-store/usr/share/applications/genixbit-store.desktop", "usr/share/applications/genixbit-store.desktop", 0o644)
        ]
    }
]

def main():
    out_dir = os.path.abspath("packages/build-debs")
    os.makedirs(out_dir, exist_ok=True)
    build_root = os.path.abspath("packages/.tmp-build")
    os.makedirs(build_root, exist_ok=True)

    for pkg in PACKAGES:
        tmp_dir = os.path.join(build_root, f"pkg-build-{pkg['name']}")
        if os.path.exists(tmp_dir):
            shutil.rmtree(tmp_dir)

        debian_dir = os.path.join(tmp_dir, "DEBIAN")
        os.makedirs(debian_dir, exist_ok=True)

        control_content = f"""Package: {pkg['name']}
Version: {pkg['version']}
Section: {pkg['section']}
Priority: optional
Architecture: all
Maintainer: GenixBit Labs Private Limited <maintainers@genixbit.com>
Depends: {pkg['depends']}
Homepage: https://os.genixbit.com
Description: {pkg['description']}
"""
        with open(os.path.join(debian_dir, "control"), "w", encoding="utf-8") as f:
            f.write(control_content)

        for src, dest_rel, mode in pkg["files"]:
            dest = os.path.join(tmp_dir, dest_rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(src, dest)
            os.chmod(dest, mode)

        deb_filename = f"{pkg['name']}_{pkg['version']}_all.deb"
        deb_path = os.path.join(out_dir, deb_filename)

        cmd = ["dpkg-deb", "-Zxz", "--build", tmp_dir, deb_path]
        subprocess.check_call(cmd)

        deb_hyphen_filename = f"{pkg['name']}_1.0.0-lts-1_all.deb"
        deb_hyphen_path = os.path.join(out_dir, deb_hyphen_filename)
        shutil.copy2(deb_path, deb_hyphen_path)

        print(f"[PASS] Built {deb_filename} & {deb_hyphen_filename} ({os.path.getsize(deb_path)} bytes)")
        shutil.rmtree(tmp_dir, ignore_errors=True)

    shutil.rmtree(build_root, ignore_errors=True)

if __name__ == "__main__":
    main()
