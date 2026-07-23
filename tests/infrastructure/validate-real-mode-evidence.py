#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validates local real-mode stage result records against anti-fabrication rules."""

import json
import sys

def main():
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: validate-real-mode-evidence.py <stage_result.json>\n")
        sys.exit(1)

    filepath = sys.argv[1]
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            d = json.load(f)
    except Exception as e:
        sys.stderr.write(f"[ERROR] Unable to parse JSON from {filepath}: {e}\n")
        sys.exit(1)

    if d.get("status") != "PASS":
        sys.stderr.write(f"[ERROR] {filepath} status is not PASS (got '{d.get('status')}')\n")
        sys.exit(1)

    if not d.get("executed_commands"):
        sys.stderr.write(f"[ERROR] {filepath} executed_commands is empty\n")
        sys.exit(1)

    if not d.get("observations"):
        sys.stderr.write(f"[ERROR] {filepath} observations is empty\n")
        sys.exit(1)

    for o in d["observations"]:
        if o.get("expected") != o.get("actual"):
            name = o.get("name", "unknown")
            sys.stderr.write(
                f"[ERROR] {filepath} observation '{name}' mismatch: "
                f"expected='{o.get('expected')}', actual='{o.get('actual')}'\n"
            )
            sys.exit(1)

    s_str = json.dumps(d).lower()
    for b in ["simulated", "mock", "placeholder", "dummy", "todo", "tbd"]:
        if b in s_str:
            sys.stderr.write(f"[ERROR] {filepath} contains forbidden word: '{b}'\n")
            sys.exit(1)

    print(f"[PASS] Verified stage result file: {filepath}")

if __name__ == "__main__":
    main()
