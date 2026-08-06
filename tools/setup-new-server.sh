#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Automated setup script for deploying GenixBit OS 1.0.0-lts environment on any Linux server.

set -Eeuo pipefail

echo "============================================================"
echo "    GenixBit OS 1.0.0 LTS Automated Server Setup Utility    "
echo "============================================================"

ISO_URL="https://github.com/GenixBit/genixbit-os/releases/download/v1.0.0-lts/GenixBitOS-1.0.0-lts-2311142213.iso"
EXPECTED_SHA256="229b3f70f94d0ced3a3d33116a64a0f5a8c2a339070443e1d023938739873ce6"
ISO_NAME="GenixBitOS-1.0.0-lts-2311142213.iso"

# 1. Update and install required packages
echo "[1/4] Installing system virtualization and utility packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  qemu-system-x86 \
  qemu-utils \
  ovmf \
  xorriso \
  curl \
  sha256sum \
  git \
  python3

# 2. Download Official Release ISO
echo "[2/4] Downloading GenixBit OS 1.0.0 LTS ISO (1.3 GB)..."
if [[ ! -f "$ISO_NAME" ]]; then
    curl -L -o "$ISO_NAME" "$ISO_URL"
fi

# 3. Verify SHA-256 Checksum
echo "[3/4] Verifying ISO SHA-256 Checksum..."
CALCULATED_SHA=$(sha256sum "$ISO_NAME" | awk '{print $1}')
if [[ "$CALCULATED_SHA" == "$EXPECTED_SHA256" ]]; then
    echo "[PASS] ISO Checksum Verified Successfully ($CALCULATED_SHA)"
else
    echo "[FAIL] Checksum mismatch! Expected $EXPECTED_SHA256 but got $CALCULATED_SHA" >&2
    exit 1
fi

# 4. Clone repository & install native packages if on host
echo "[4/4] Setting up GenixBit OS 1.0.0 LTS test environment..."
if [[ ! -d "genixbit-os" ]]; then
    git clone https://github.com/GenixBit/genixbit-os.git
fi

cd genixbit-os
sudo dpkg -i packages/build-debs/*_1.0.0-lts_all.deb 2>/dev/null || sudo apt-get install -f -y -qq

echo "============================================================"
echo "[SUCCESS] GenixBit OS 1.0.0 LTS Server Setup Complete!"
echo "ISO Location: $(pwd)/../$ISO_NAME"
echo "Native Tools Active: genixbit-gpu-diag, genixbit-ai-proxy, genixbit-ai-center, genixbit-agent, genixbit-store"
echo "============================================================"
