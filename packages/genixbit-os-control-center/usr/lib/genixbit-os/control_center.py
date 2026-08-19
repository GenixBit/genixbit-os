#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Control Center & Appearance Management Engine
import json
import os
import subprocess
import sys
import tempfile

ACCENT_COLORS = {
    "cyan": {"name": "Cyber Cyan", "hex": "#52d9ff", "rgb": "82,217,255"},
    "indigo": {"name": "Royal Indigo", "hex": "#6366f1", "rgb": "99,102,241"},
    "teal": {"name": "Emerald Teal", "hex": "#10b981", "rgb": "16,185,129"},
    "orange": {"name": "Sunset Orange", "hex": "#f97316", "rgb": "249,115,22"},
    "ruby": {"name": "Ruby Red", "hex": "#f43f5e", "rgb": "244,63,94"},
    "purple": {"name": "Cosmic Purple", "hex": "#a855f7", "rgb": "168,85,247"}
}

def get_config_file():
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config:
        base = os.path.join(xdg_config, "genixbit")
    else:
        base = os.path.expanduser("~/.config/genixbit")
    return os.path.join(base, "appearance.json")

def get_current_settings():
    default_settings = {
        "theme_mode": "dark",
        "gtk_theme": "GenixBit-Dark",
        "icon_theme": "GenixBit-Icons",
        "accent_color": "cyan",
        "accent_hex": "#52d9ff",
        "dock_theme": "GenixBit-Glass",
        "dock_position": "bottom",
        "dock_zoom": True,
        "dock_size": 48,
        "wallpaper": "genixbit-workstation-cyber-dark.png",
        "font_family": "Inter",
        "font_size": 10,
        "monospace_font": "JetBrains Mono"
    }
    settings_file = get_config_file()
    if os.path.exists(settings_file):
        try:
            with open(settings_file, "r", encoding="utf-8") as f:
                saved = json.load(f)
                default_settings.update(saved)
        except Exception:
            pass
    return default_settings

def apply_settings(settings):
    settings_file = get_config_file()
    config_dir = os.path.dirname(settings_file)
    try:
        os.makedirs(config_dir, exist_ok=True)
        with open(settings_file, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
    except Exception:
        # Fallback in sandboxed/restricted runtime
        pass

    theme = "GenixBit-Dark" if settings.get("theme_mode") == "dark" else "GenixBit-Light"
    
    # Apply to XFCE / GTK environment if available
    try:
        subprocess.run(["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName", "-s", theme], capture_output=True)
        subprocess.run(["xfconf-query", "-c", "xsettings", "-p", "/Net/IconThemeName", "-s", "GenixBit-Icons"], capture_output=True)
        subprocess.run(["xfconf-query", "-c", "xfwm4", "-p", "/general/theme", "-s", theme], capture_output=True)
    except Exception:
        pass

    return {"status": "success", "applied_settings": settings}

def set_theme_mode(mode):
    if mode not in ["dark", "light"]:
        raise ValueError("Mode must be 'dark' or 'light'")
    cur = get_current_settings()
    cur["theme_mode"] = mode
    cur["gtk_theme"] = "GenixBit-Dark" if mode == "dark" else "GenixBit-Light"
    return apply_settings(cur)

def set_accent_color(accent_key):
    accent_key = accent_key.lower()
    if accent_key not in ACCENT_COLORS:
        raise ValueError(f"Unknown accent '{accent_key}'. Available: {list(ACCENT_COLORS.keys())}")
    cur = get_current_settings()
    cur["accent_color"] = accent_key
    cur["accent_hex"] = ACCENT_COLORS[accent_key]["hex"]
    return apply_settings(cur)

def get_master_spec():
    spec_path = "/etc/genixbit/master-spec.txt"
    if os.path.exists(spec_path):
        try:
            with open(spec_path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception:
            pass
    return """============================================================
GENIXBIT OS — MASTER OPERATING SYSTEM BUILD PROMPT
============================================================
GenixBit OS is a complete, secure, AI-native, local-first,
enterprise-capable desktop operating system platform.
"""

def toggle_theme():
    settings = get_current_settings()
    current = settings.get("theme_mode", "dark")
    settings["theme_mode"] = "light" if current == "dark" else "dark"
    apply_settings(settings)
    print(f"Switched GenixBit OS theme to: {settings['theme_mode'].upper()}")
    return 0

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "--toggle-theme":
            toggle_theme()
            sys.exit(0)
        elif sys.argv[1] in ("--spec", "--architecture", "--info"):
            print(get_master_spec())
            sys.exit(0)
    print(json.dumps(get_current_settings(), indent=2))
