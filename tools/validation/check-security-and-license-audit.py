#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""GenixBit OS 1.0.0 Stable LTS Security & Production Readiness Audit Tool."""

import os
import pathlib
import sys

REQUIRED_PACKAGES = [
    "genixbit-os-base-files",
    "genixbit-os-desktop",
    "genixbit-os-theme",
    "genixbit-os-wallpapers",
    "genixbit-os-installer-config",
    "genixbit-os-archive-keyring",
    "genixbit-os-apt-config",
    "genixbit-os-developer-profile",
    "genixbit-os-server-profile",
    "genixbit-os-creator-profile",
    "genixbit-os-gpu-diagnostics",
    "genixbit-os-ai-runtime",
    "genixbit-os-ai-center",
    "genixbit-os-agents",
    "genixbit-os-store",
    "genixbit-os-indic-llm",
    "genixbit-os-security-guard",
    "genixbit-os-microvm",
    "genixbit-os-vision-rag",
    "genixbit-os-swarm",
    "genixbit-os-control-center",
    "genixbit-os-quick-launcher",
    "genixbit-os-icons",
]

def main():
    root = pathlib.Path.cwd().resolve()
    print("============================================================")
    print("      GenixBit OS 1.0.0 LTS Production Readiness Audit       ")
    print("============================================================")

    failures = []

    # Check 1: Package control integrity
    print("[INFO] Audit Step 1: Verifying package control metadata...")
    for pkg in REQUIRED_PACKAGES:
        control_path = root / "packages" / pkg / "debian" / "control"
        if not control_path.exists():
            failures.append(f"Missing control file for package: {pkg}")
        else:
            content = control_path.read_text(encoding="utf-8")
            if f"Package: {pkg}" not in content:
                failures.append(f"Package mismatch in {control_path}")

    if not failures:
        print(f"[PASS] All {len(REQUIRED_PACKAGES)} production packages verified.")

    # Check 2: License attribution files
    print("[INFO] Audit Step 2: Verifying legal attribution files...")
    for legal in ["LICENSE", "UPSTREAM.md", "OSS.md", "GOVERNANCE.md"]:
        if not (root / legal).exists():
            failures.append(f"Missing legal attribution file: {legal}")
    if not failures:
        print("[PASS] Legal attribution & governance documents verified.")

    # Summary
    if failures:
        print("\n[FAIL] Audit failed with the following errors:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print("\n[PASS] GenixBit OS 1.0.0 LTS Production Readiness Audit PASSED cleanly!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
