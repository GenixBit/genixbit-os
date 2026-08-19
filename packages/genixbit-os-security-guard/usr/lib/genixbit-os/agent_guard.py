#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Autonomous Agent Security Guard Policy Monitor
import json
import os
import re
import sys

DANGEROUS_PATTERNS = [
    r"rm\s+-rf\s+/",
    r"mkfs",
    r":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;",
    r">\s*/dev/sd[a-z]",
    r">\s*/dev/nvme",
    r"curl.*\|\s*sh",
    r"wget.*\|\s*sh"
]

SECRET_PATTERNS = [
    r"ghp_[A-Za-z0-9_]{36}",
    r"AIza[0-9A-Za-z-_]{35}",
    r"sk-[A-Za-z0-9]{48}",
    r"BEGIN\s+PRIVATE\s+KEY"
]

def audit_command(command_str):
    for pattern in DANGEROUS_PATTERNS:
        if re.search(pattern, command_str):
            return {
                "allowed": False,
                "risk": "HIGH",
                "reason": f"Dangerous destructive command pattern matched: {pattern}",
                "command": command_str
            }
    return {
        "allowed": True,
        "risk": "LOW",
        "reason": "Command passed security policy inspection.",
        "command": command_str
    }

def scan_for_secrets(text):
    found = []
    for pattern in SECRET_PATTERNS:
        if re.search(pattern, text):
            found.append(pattern)
    return {
        "has_secrets": len(found) > 0,
        "matched_rules": len(found),
        "status": "BLOCKED" if found else "CLEAN"
    }

if __name__ == "__main__":
    res = audit_command("ls -la")
    print(json.dumps(res, indent=2))
