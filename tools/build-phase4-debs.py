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
        "files": [
            ("packages/genixbit-os-base-files/usr/bin/genixbit-fetch", "usr/bin/genixbit-fetch", 0o755),
            ("packages/genixbit-os-base-files/usr/bin/genixbit-zram", "usr/bin/genixbit-zram", 0o755),
            ("packages/genixbit-os-base-files/usr/lib/systemd/system/genixbit-zram.service", "usr/lib/systemd/system/genixbit-zram.service", 0o644),
            ("packages/genixbit-os-base-files/etc/profile.d/99-genixbit-shell.sh", "etc/profile.d/99-genixbit-shell.sh", 0o644),
            ("packages/genixbit-os-base-files/etc/sysctl.d/99-genixbit-ai.conf", "etc/sysctl.d/99-genixbit-ai.conf", 0o644),
            ("packages/genixbit-os-base-files/etc/security/limits.d/99-genixbit-ai.conf", "etc/security/limits.d/99-genixbit-ai.conf", 0o644)
        ]
    },
    {
        "name": "genixbit-os-desktop",
        "version": VERSION,
        "section": "metapackages",
        "depends": "genixbit-os-base-files, genixbit-os-theme, genixbit-os-wallpapers",
        "description": "GenixBit OS desktop environment metapackage\n Metapackage pulling in core desktop session and AI workspace defaults.",
        "files": [
            ("packages/genixbit-os-desktop/bin/genixbit-desktop-setup", "usr/bin/genixbit-desktop-setup", 0o755),
            ("packages/genixbit-os-desktop/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml", "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml", 0o644),
            ("packages/genixbit-os-desktop/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml", "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml", 0o644),
            ("packages/genixbit-os-desktop/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml", "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml", 0o644),
            ("packages/genixbit-os-desktop/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml", "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml", 0o644),
            ("packages/genixbit-os-desktop/etc/skel/.config/autostart/genixbit-desktop-setup.desktop", "etc/skel/.config/autostart/genixbit-desktop-setup.desktop", 0o644)
        ]
    },
    {
        "name": "genixbit-os-theme",
        "version": VERSION,
        "section": "x11",
        "depends": "genixbit-os-base-files",
        "description": "GenixBit OS desktop and boot splash theme\n Plymouth boot splash, GTK, icon theme, and desktop styling.",
        "files": [
            ("packages/genixbit-os-theme/usr/share/glib-2.0/schemas/99_genixbit-os.gschema.override", "usr/share/glib-2.0/schemas/99_genixbit-os.gschema.override", 0o644),
            ("packages/genixbit-os-theme/usr/share/themes/GenixBit-Dark/gnome-shell/gnome-shell.css", "usr/share/themes/GenixBit-Dark/gnome-shell/gnome-shell.css", 0o644),
            ("packages/genixbit-os-theme/usr/share/themes/GenixBit-Dark/gtk-3.0/gtk.css", "usr/share/themes/GenixBit-Dark/gtk-3.0/gtk.css", 0o644),
            ("packages/genixbit-os-theme/usr/share/themes/GenixBit-Dark/gtk-4.0/gtk.css", "usr/share/themes/GenixBit-Dark/gtk-4.0/gtk.css", 0o644),
            ("packages/genixbit-os-theme/usr/share/sounds/genixbit/index.theme", "usr/share/sounds/genixbit/index.theme", 0o644),
            ("packages/genixbit-os-theme/usr/share/icons/hicolor/scalable/apps/genixbit-ai-center.svg", "usr/share/icons/hicolor/scalable/apps/genixbit-ai-center.svg", 0o644),
            ("packages/genixbit-os-theme/usr/share/icons/hicolor/scalable/apps/genixbit-agent.svg", "usr/share/icons/hicolor/scalable/apps/genixbit-agent.svg", 0o644),
            ("packages/genixbit-os-theme/usr/share/icons/hicolor/scalable/apps/genixbit-store.svg", "usr/share/icons/hicolor/scalable/apps/genixbit-store.svg", 0o644),
            ("packages/genixbit-os-theme/usr/share/icons/hicolor/scalable/apps/genixbit-top.svg", "usr/share/icons/hicolor/scalable/apps/genixbit-top.svg", 0o644),
            ("packages/genixbit-os-theme/usr/share/icons/hicolor/scalable/apps/genixbit-gpu-diag.svg", "usr/share/icons/hicolor/scalable/apps/genixbit-gpu-diag.svg", 0o644),
            ("packages/genixbit-os-theme/usr/share/icons/hicolor/scalable/apps/genixbit-dev-setup.svg", "usr/share/icons/hicolor/scalable/apps/genixbit-dev-setup.svg", 0o644)
        ]
    },
    {
        "name": "genixbit-os-wallpapers",
        "version": VERSION,
        "section": "x11",
        "depends": "genixbit-os-base-files",
        "description": "GenixBit OS workstation wallpapers\n Official background wallpaper artwork collection.",
        "files": [
            ("packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.png", "usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.png", 0o644),
            ("packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-light.png", "usr/share/backgrounds/genixbit/genixbit-wallpaper-light.png", 0o644),
            ("packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-1920x1080.png", "usr/share/backgrounds/genixbit/genixbit-wallpaper-1920x1080.png", 0o644),
            ("packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg", "usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg", 0o644)
        ]
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
            ("packages/genixbit-os-developer-profile/bin/genixbit-pipeline", "usr/bin/genixbit-pipeline", 0o755),
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
            ("packages/genixbit-os-gpu-diagnostics/bin/genixbit-monitor-gui", "usr/bin/genixbit-monitor-gui", 0o755),
            ("packages/genixbit-os-gpu-diagnostics/usr/share/applications/genixbit-gpu-diag.desktop", "usr/share/applications/genixbit-gpu-diag.desktop", 0o644),
            ("packages/genixbit-os-gpu-diagnostics/usr/share/applications/genixbit-top.desktop", "usr/share/applications/genixbit-top.desktop", 0o644),
            ("packages/genixbit-os-gpu-diagnostics/usr/share/applications/genixbit-monitor.desktop", "usr/share/applications/genixbit-monitor.desktop", 0o644)
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
            ("packages/genixbit-os-ai-runtime/bin/genixbit-mesh", "usr/bin/genixbit-mesh", 0o755),
            ("packages/genixbit-os-ai-runtime/bin/genixbit-tunnel", "usr/bin/genixbit-tunnel", 0o755),
            ("packages/genixbit-os-ai-runtime/bin/genixbit-hybrid", "usr/bin/genixbit-hybrid", 0o755),
            ("packages/genixbit-os-ai-runtime/bin/genixbit-rag", "usr/bin/genixbit-rag", 0o755),
            ("packages/genixbit-os-ai-runtime/usr/share/genixbit-os/models/catalog.json", "usr/share/genixbit-os/models/catalog.json", 0o644),
            ("packages/genixbit-os-ai-runtime/usr/lib/systemd/system/genixbit-ai-proxy.service", "usr/lib/systemd/system/genixbit-ai-proxy.service", 0o644),
            ("packages/genixbit-os-ai-runtime/usr/lib/systemd/system/genixbit-mesh.service", "usr/lib/systemd/system/genixbit-mesh.service", 0o644)
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
            ("packages/genixbit-os-ai-center/bin/genixbit-ai-center-gui", "usr/bin/genixbit-ai-center-gui", 0o755),
            ("packages/genixbit-os-ai-center/bin/genixbit-voice", "usr/bin/genixbit-voice", 0o755),
            ("packages/genixbit-os-ai-center/bin/genixbit-quant", "usr/bin/genixbit-quant", 0o755),
            ("packages/genixbit-os-ai-center/bin/genixbit-vision", "usr/bin/genixbit-vision", 0o755),
            ("packages/genixbit-os-ai-center/usr/share/applications/genixbit-ai-center.desktop", "usr/share/applications/genixbit-ai-center.desktop", 0o644),
            ("packages/genixbit-os-ai-center/usr/share/applications/genixbit-voice.desktop", "usr/share/applications/genixbit-voice.desktop", 0o644)
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
            ("packages/genixbit-os-agents/bin/genixbit-agent-studio", "usr/bin/genixbit-agent-studio", 0o755),
            ("packages/genixbit-os-agents/bin/genixbit-guard", "usr/bin/genixbit-guard", 0o755),
            ("packages/genixbit-os-agents/bin/genixbit-sandbox", "usr/bin/genixbit-sandbox", 0o755),
            ("packages/genixbit-os-agents/bin/genixbit-microvm", "usr/bin/genixbit-microvm", 0o755),
            ("packages/genixbit-os-agents/bin/genixbit-swarm", "usr/bin/genixbit-swarm", 0o755),
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
            ("packages/genixbit-os-store/bin/genixbit-store-gui", "usr/bin/genixbit-store-gui", 0o755),
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
