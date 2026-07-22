#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generate real APT package indices and Release metadata for a repository channel.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/safety.sh"

usage() {
    cat <<'EOF'
Usage: build-package-index.sh --repo-dir PATH --channel NAME

Options:
  --repo-dir PATH  Path to staging repository root.
  --channel NAME   Channel name (resolute-alpha, resolute-testing, resolute-stable).
  -h, --help       Show this help.
EOF
}

REPO_DIR=""
CHANNEL=""

while (($# > 0)); do
    case "$1" in
        --repo-dir)
            (($# >= 2)) || { echo "Error: --repo-dir requires a path." >&2; exit 1; }
            REPO_DIR=$2
            shift 2
            ;;
        --channel)
            (($# >= 2)) || { echo "Error: --channel requires a name." >&2; exit 1; }
            CHANNEL=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$REPO_DIR" || -z "$CHANNEL" ]]; then
    echo "Error: --repo-dir and --channel are required." >&2
    exit 1
fi

ABS_REPO=$(validate_repository_path "$REPO_DIR" "--repo-dir") || exit 1

CHANNEL_DIR="$ABS_REPO/dists/$CHANNEL"
mkdir -p "$CHANNEL_DIR"

echo "[INFO] Building package indices for channel '$CHANNEL' at: $ABS_REPO"

python3 - << EOF
import os
import sys
import glob
import hashlib
import gzip
import lzma
import subprocess
from datetime import datetime, timezone, timedelta

repo_dir = "$ABS_REPO"
channel = "$CHANNEL"
channel_dir = os.path.join(repo_dir, "dists", channel)
pool_dir = os.path.join(repo_dir, "pool")

components = ["main", "restricted"]
seen_tuples = set()

def get_deb_metadata(deb_path):
    # Get control metadata using dpkg-deb or python tar extract
    pkg_meta = {}
    if os.path.getsize(deb_path) == 0:
        raise ValueError(f"Zero-byte package detected: {deb_path}")
    
    rel_path = os.path.relpath(deb_path, repo_dir)
    file_size = os.path.getsize(deb_path)
    
    with open(deb_path, "rb") as f:
        content = f.read()
        sha256_hash = hashlib.sha256(content).hexdigest()
        sha512_hash = hashlib.sha512(content).hexdigest()
    
    # Run dpkg-deb -f if available, else extract control fields
    try:
        res = subprocess.run(["dpkg-deb", "-f", deb_path], capture_output=True, text=True, check=True)
        for line in res.stdout.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                pkg_meta[k.strip()] = v.strip()
    except Exception:
        # Minimal metadata fallback for fixture debs when dpkg-deb is not present
        base = os.path.basename(deb_path).replace(".deb", "")
        parts = base.split("_")
        pkg_meta["Package"] = parts[0] if len(parts) > 0 else "unknown"
        pkg_meta["Version"] = parts[1] if len(parts) > 1 else "1.0.0"
        pkg_meta["Architecture"] = parts[2] if len(parts) > 2 else "all"
        pkg_meta["Maintainer"] = "GenixBit OS Maintainers <ftpmaster@genixbit.com>"
        pkg_meta["Description"] = "GenixBit OS Package Fixture"

    pkg_name = pkg_meta.get("Package", "")
    version = pkg_meta.get("Version", "")
    arch = pkg_meta.get("Architecture", "")

    if not pkg_name:
        raise ValueError(f"Empty package name in {deb_path}")

    tup = (pkg_name, version, arch)
    if tup in seen_tuples:
        raise ValueError(f"Duplicate package/version/arch tuple: {tup}")
    seen_tuples.add(tup)

    entry = []
    entry.append(f"Package: {pkg_name}")
    entry.append(f"Version: {version}")
    entry.append(f"Architecture: {arch}")
    entry.append(f"Maintainer: {pkg_meta.get('Maintainer', 'GenixBit Maintainers')}")
    entry.append(f"Filename: {rel_path}")
    entry.append(f"Size: {file_size}")
    entry.append(f"SHA256: {sha256_hash}")
    entry.append(f"SHA512: {sha512_hash}")
    if "Description" in pkg_meta:
        entry.append(f"Description: {pkg_meta['Description']}")
    entry.append("")
    return "\n".join(entry)

for comp in components:
    comp_arch_dir = os.path.join(channel_dir, comp, "binary-amd64")
    by_hash_dir = os.path.join(comp_arch_dir, "by-hash", "SHA256")
    os.makedirs(comp_arch_dir, exist_ok=True)
    os.makedirs(by_hash_dir, exist_ok=True)

    comp_pool_dir = os.path.join(pool_dir, comp)
    deb_files = glob.glob(os.path.join(comp_pool_dir, "**", "*.deb"), recursive=True) if os.path.exists(comp_pool_dir) else []

    pkgs_content = []
    for deb in sorted(deb_files):
        pkgs_content.append(get_deb_metadata(deb))

    pkgs_str = "\n".join(pkgs_content)
    pkgs_file = os.path.join(comp_arch_dir, "Packages")
    with open(pkgs_file, "w") as f:
        f.write(pkgs_str)

    # Gzip -9
    gz_file = os.path.join(comp_arch_dir, "Packages.gz")
    with gzip.open(gz_file, "wb", compresslevel=9) as f:
        f.write(pkgs_str.encode("utf-8"))

    # XZ -9
    xz_file = os.path.join(comp_arch_dir, "Packages.xz")
    with lzma.open(xz_file, "wb", preset=9) as f:
        f.write(pkgs_str.encode("utf-8"))

    # Create by-hash symlink for Packages
    pkgs_hash = hashlib.sha256(pkgs_str.encode("utf-8")).hexdigest()
    hash_link = os.path.join(by_hash_dir, pkgs_hash)
    if os.path.exists(hash_link) or os.path.islink(hash_link):
        os.remove(hash_link)
    os.symlink("../Packages", hash_link)

# Build Release file
now = datetime.now(timezone.utc)
valid_until = now + timedelta(days=7)

release_lines = [
    "Origin: GenixBit OS",
    "Label: GenixBit",
    f"Suite: {channel}",
    f"Codename: {channel}",
    f"Date: {now.strftime('%a, %d %b %Y %H:%M:%S UTC')}",
    f"Valid-Until: {valid_until.strftime('%a, %d %b %Y %H:%M:%S UTC')}",
    "Architectures: amd64",
    "Components: main restricted",
    f"Description: GenixBit OS {channel} package repository",
    "Acquire-By-Hash: yes",
    "SHA256:"
]

for comp in components:
    for f_name in ["Packages", "Packages.gz", "Packages.xz"]:
        f_path = os.path.join(channel_dir, comp, "binary-amd64", f_name)
        if os.path.exists(f_path):
            with open(f_path, "rb") as f:
                c = f.read()
                h_sha256 = hashlib.sha256(c).hexdigest()
                size = len(c)
                rel_f_path = os.path.relpath(f_path, channel_dir)
                release_lines.append(f" {h_sha256} {size} {rel_f_path}")

release_str = "\n".join(release_lines) + "\n"
release_file = os.path.join(channel_dir, "Release")
with open(release_file, "w") as f:
    f.write(release_str)

EOF

echo "[PASS] Built real package index and Release metadata for $CHANNEL."
