#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build Phase 4 binary Debian packages for GenixBit OS."""

import os
import shutil
import subprocess
import sys

PACKAGES = [
    {
        "name": "genixbit-os-developer-profile",
        "version": "0.4.0-alpha-1",
        "section": "metapackages",
        "depends": "genixbit-os-base-files, genixbit-os-desktop",
        "description": "Developer profile metapackage for GenixBit OS\n Provides developer toolchains, container runtimes, version control,\n and language environments for GenixBit OS developer workstations.",
        "files": []
    },
    {
        "name": "genixbit-os-server-profile",
        "version": "0.4.0-alpha-1",
        "section": "metapackages",
        "depends": "genixbit-os-base-files",
        "description": "Server manager profile metapackage for GenixBit OS\n Provides headless services, container management, systemd monitoring,\n and remote administration utilities for GenixBit OS server nodes.",
        "files": []
    },
    {
        "name": "genixbit-os-creator-profile",
        "version": "0.4.0-alpha-1",
        "section": "metapackages",
        "depends": "genixbit-os-base-files, genixbit-os-desktop",
        "description": "Creator profile metapackage for GenixBit OS\n Provides video, audio, image, 3D graphics, streaming, and hardware-accelerated\n codec tooling for GenixBit OS content creation workstations.",
        "files": []
    },
    {
        "name": "genixbit-os-gpu-diagnostics",
        "version": "0.4.0-alpha-1",
        "section": "utils",
        "depends": "genixbit-os-base-files, pciutils, lshw",
        "description": "Hardware & GPU diagnostic package for GenixBit OS\n Automatic NVIDIA, AMD, and Intel GPU detection tool providing CUDA and ROCm\n runtime capability diagnostics for local AI model acceleration.",
        "files": [("packages/genixbit-os-gpu-diagnostics/bin/genixbit-gpu-diag", "usr/bin/genixbit-gpu-diag", 0o755)]
    },
    {
        "name": "genixbit-os-ai-runtime",
        "version": "0.5.0-alpha-1",
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-gpu-diagnostics, python3, curl",
        "description": "AI runtime foundation & local model proxy for GenixBit OS\n Provides local OpenAI-compatible API proxy service, model catalog metadata,\n and hardware-aware Ollama & llama.cpp runtime dispatchers for GenixBit OS.",
        "files": [
            ("packages/genixbit-os-ai-runtime/bin/genixbit-ai-proxy", "usr/bin/genixbit-ai-proxy", 0o755),
            ("packages/genixbit-os-ai-runtime/usr/share/genixbit-os/models/catalog.json", "usr/share/genixbit-os/models/catalog.json", 0o644)
        ]
    },
    {
        "name": "genixbit-os-ai-center",
        "version": "0.6.0-alpha-1",
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-ai-runtime, genixbit-os-gpu-diagnostics, python3, curl",
        "description": "GenixBit AI Center model lifecycle manager\n Command-line manager and model lifecycle tool for discovering, downloading,\n installing, and monitoring local AI models on GenixBit OS.",
        "files": [
            ("packages/genixbit-os-ai-center/bin/genixbit-ai-center", "usr/bin/genixbit-ai-center", 0o755)
        ]
    },
    {
        "name": "genixbit-os-agents",
        "version": "0.6.0-alpha-1",
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-ai-runtime, python3, curl",
        "description": "GenixBit Agents integration package for GenixBit OS\n Developer agent bridge connecting GenixBit OS workstations to GenixBit Agents,\n supporting Antigravity, Gemini CLI, Codex, Cursor, and OpenCode tools.",
        "files": [
            ("packages/genixbit-os-agents/bin/genixbit-agent", "usr/bin/genixbit-agent", 0o755)
        ]
    },
    {
        "name": "genixbit-os-store",
        "version": "0.7.0-alpha-1",
        "section": "utils",
        "depends": "genixbit-os-base-files, genixbit-os-ai-center, python3, curl",
        "description": "GenixBit Store curated application & package manager\n Curated app store interface for developer tools, AI runtimes, server utilities,\n Flatpak applications, and signed GenixBit packages on GenixBit OS.",
        "files": [
            ("packages/genixbit-os-store/bin/genixbit-store", "usr/bin/genixbit-store", 0o755)
        ]
    }
]

def main():
    out_dir = os.path.abspath("packages/build-debs")
    os.makedirs(out_dir, exist_ok=True)

    for pkg in PACKAGES:
        tmp_dir = os.path.abspath(f"/tmp/pkg-build-{pkg['name']}")
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
        print(f"[PASS] Built {deb_filename} ({os.path.getsize(deb_path)} bytes)")
        shutil.rmtree(tmp_dir)

if __name__ == "__main__":
    main()
