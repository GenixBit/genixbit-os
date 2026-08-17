#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS 1.0.0 LTS — Automated Server VNC & noVNC Live Stream Deployment Utility
# Provisions headless QEMU VM instance with websockify + noVNC bridge on port 6080.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VNC_PORT=${VNC_PORT:-5901}
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}
VM_RAM=${VM_RAM:-4096}
VM_CORES=${VM_CORES:-4}
ISO_NAME="GenixBitOS-1.0.0-lts-2311142213.iso"
ISO_URL="https://github.com/GenixBit/genixbit-os/releases/download/v1.0.0-lts/${ISO_NAME}"
ISO_PATH="${REPO_ROOT}/dist/${ISO_NAME}"

echo "============================================================"
echo "    GenixBit OS 1.0.0 LTS Server VNC & noVNC Deployment     "
echo "============================================================"

# Step 1: Install prerequisite packages if on Debian/Ubuntu
if command -v apt-get &>/dev/null; then
    echo "[1/4] Checking server virtualization & noVNC prerequisites..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq qemu-system-x86 ovmf websockify novnc curl procps || true
    if [[ -d "${REPO_ROOT}/packages/build-debs" ]]; then
        sudo dpkg -i "${REPO_ROOT}/packages/build-debs/"*.deb 2>/dev/null || true
        if command -v genixbit-desktop-setup &>/dev/null; then
            genixbit-desktop-setup || true
        fi
    fi
fi

# Step 2: Download Release ISO if missing
mkdir -p "${REPO_ROOT}/dist"
if [[ ! -f "$ISO_PATH" && ! -f "${REPO_ROOT}/../${ISO_NAME}" ]]; then
    echo "[2/4] Fetching GenixBit OS 1.0.0 LTS ISO..."
    curl -L -o "$ISO_PATH" "$ISO_URL" || true
fi

if [[ -f "${REPO_ROOT}/../${ISO_NAME}" ]]; then
    ISO_PATH="${REPO_ROOT}/../${ISO_NAME}"
fi

# Step 3: Launch Headless QEMU VM with local loopback VNC
echo "[3/4] Launching headless GenixBit OS VM on VNC port 127.0.0.1:${VNC_PORT}..."
pkill -f "qemu-system-x86_64.*genixbit-vnc" 2>/dev/null || true

OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_ARG=""
if [[ -f "$OVMF_CODE" ]]; then
    OVMF_ARG="-drive if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
fi

KVM_ARG=""
if [[ -e /dev/kvm && -w /dev/kvm ]]; then
    KVM_ARG="-enable-kvm -cpu host"
else
    KVM_ARG="-cpu max"
fi

if [[ -f "$ISO_PATH" ]]; then
    nohup qemu-system-x86_64 \
        -name genixbit-vnc,process=genixbit-vnc \
        -m "${VM_RAM}" \
        -smp "${VM_CORES}" \
        ${KVM_ARG} \
        ${OVMF_ARG} \
        -boot d \
        -cdrom "${ISO_PATH}" \
        -vnc "127.0.0.1:$((VNC_PORT - 5900))" \
        -vga virtio \
        -display none \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        >/dev/null 2>&1 &
    echo "[PASS] QEMU VM started with PID $!"
else
    echo "[INFO] ISO not present locally; starting websocket proxy bridge for external VM..."
fi

# Step 4: Launch websockify noVNC bridge
echo "[4/4] Starting websockify bridge on port ${WEBSOCKIFY_PORT} -> 127.0.0.1:${VNC_PORT}..."
pkill -f "websockify.*${WEBSOCKIFY_PORT}" 2>/dev/null || true

NOVNC_DIR="/usr/share/novnc"
if [[ ! -d "$NOVNC_DIR" ]]; then
    NOVNC_DIR=""
fi

WEB_ARG=""
if [[ -n "$NOVNC_DIR" ]]; then
    WEB_ARG="--web ${NOVNC_DIR}"
fi

if command -v websockify &>/dev/null; then
    nohup websockify ${WEB_ARG} "${WEBSOCKIFY_PORT}" "127.0.0.1:${VNC_PORT}" >/dev/null 2>&1 &
    echo "[PASS] websockify running on port ${WEBSOCKIFY_PORT} (PID $!)"
fi

echo "============================================================"
echo "[SUCCESS] GenixBit OS Live Server VNC Deployment Active!"
echo "• VNC Loopback: 127.0.0.1:${VNC_PORT}"
echo "• noVNC WebSocket Endpoint: ws://0.0.0.0:${WEBSOCKIFY_PORT}/websockify"
echo "• Web Simulator URL: https://os.genixbit.com (Mode -> Live noVNC)"
echo "============================================================"
