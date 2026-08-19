# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit System Abstraction API (GenixSystem)
import os
import platform
import subprocess
import sys

class GenixSystem:
    """
    GenixSystem provides a decoupled interface to system-level attributes,
    hardware metadata, and execution primitives, abstracting underlying kernel details.
    """
    @staticmethod
    def get_os_release():
        return {
            "name": "GenixBit OS",
            "version": "1.0.0 LTS",
            "id": "genixbit",
            "architecture": platform.machine(),
            "kernel": platform.release(),
            "python": platform.python_version()
        }

    @staticmethod
    def get_hostname():
        return platform.node()

    @staticmethod
    def is_ai_runtime_available():
        import urllib.request
        try:
            req = urllib.request.Request("http://127.0.0.1:11434/health", headers={"User-Agent": "GenixSystem"})
            with urllib.request.urlopen(req, timeout=1.0) as resp:
                return resp.status == 200
        except Exception:
            return False

    @staticmethod
    def get_active_theme():
        config_p = os.path.expanduser("~/.config/genixbit/appearance.json")
        if os.path.exists(config_p):
            try:
                import json
                with open(config_p, "r", encoding="utf-8") as f:
                    return json.load(f).get("theme_mode", "dark")
            except Exception:
                pass
        return "dark"
