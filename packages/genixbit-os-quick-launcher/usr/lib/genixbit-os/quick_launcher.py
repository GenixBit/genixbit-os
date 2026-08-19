#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Spotlight HUD Quick Launcher Engine
import json
import os
import subprocess
import sys

DEFAULT_APPS = [
    {"name": "GenixBit AI Center", "exec": "genixbit-ai-center", "icon": "genixbit-ai-center", "category": "AI", "description": "Manage and pull local LLMs"},
    {"name": "GenixBit Control Center", "exec": "genixbit-control-center", "icon": "genixbit-control-center", "category": "Settings", "description": "Themes, accents and system settings"},
    {"name": "GenixBit Store", "exec": "genixbit-store", "icon": "genixbit-store", "category": "System", "description": "App store and package manager"},
    {"name": "GenixBit Agent Swarm", "exec": "genixbit-swarm", "icon": "genixbit-swarm", "category": "AI", "description": "Multi-agent autonomous swarm"},
    {"name": "Terminal", "exec": "xfce4-terminal", "icon": "utilities-terminal", "category": "System", "description": "Command line interface"},
    {"name": "File Manager", "exec": "thunar", "icon": "system-file-manager", "category": "System", "description": "Browse local files and storage"},
    {"name": "Web Browser", "exec": "firefox", "icon": "web-browser", "category": "Network", "description": "Explore the web"},
    {"name": "Code Editor", "exec": "codium", "icon": "text-editor", "category": "Development", "description": "Write and debug code"}
]

def search(query):
    q = query.strip()
    if not q:
        return {"query": "", "mode": "apps", "results": DEFAULT_APPS}

    # Inline AI Query Mode
    if q.startswith("@ai ") or q.startswith("?"):
        prompt = q[4:] if q.startswith("@ai ") else q[1:]
        return {
            "query": q,
            "mode": "ai_inference",
            "prompt": prompt,
            "results": [
                {
                    "name": f"Ask Local AI: '{prompt}'",
                    "exec": f"genixbit-agent run '{prompt}'",
                    "icon": "genixbit-ai-center",
                    "category": "AI Instant Response",
                    "description": "Stream answer from 127.0.0.1:11434"
                }
            ]
        }

    # Standard Fuzzy App & Command Search
    matches = []
    q_lower = q.lower()
    for app in DEFAULT_APPS:
        if q_lower in app["name"].lower() or q_lower in app["category"].lower() or q_lower in app["description"].lower() or q_lower in app["exec"].lower():
            matches.append(app)

    return {
        "query": q,
        "mode": "apps",
        "match_count": len(matches),
        "results": matches
    }

if __name__ == "__main__":
    print(json.dumps(search("ai"), indent=2))
