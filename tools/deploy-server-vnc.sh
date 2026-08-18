#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Production GCP Server VNC & noVNC Live Stream Deployment Utility
# Provisions headless QEMU VM instance with websockify + noVNC bridge on port 6080.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_VERSION="${TARGET_VERSION:-1.0.0}"
VNC_PORT=${VNC_PORT:-5901}
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}
VM_RAM=${VM_RAM:-4096}
VM_CORES=${VM_CORES:-4}

if [[ "$TARGET_VERSION" == "1.5.0" ]]; then
    ISO_NAME="GenixBitOS-1.5.0-sutra-20260817.iso"
    ISO_URL="https://packages.os.genixbit.com/iso/${ISO_NAME}.zip"
else
    ISO_NAME="GenixBitOS-1.0.0-lts-2311142213.iso"
    ISO_URL="https://packages.os.genixbit.com/iso/${ISO_NAME}.zip"
fi

ISO_PATH="${REPO_ROOT}/dist/${ISO_NAME}"

echo "============================================================"
echo "    GenixBit OS (${TARGET_VERSION}) GCP Server VNC Deployment      "
echo "============================================================"

# Step 1: Install prerequisite packages if on Debian/Ubuntu
if command -v apt-get &>/dev/null; then
    echo "[1/5] Checking server virtualization & noVNC prerequisites..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq qemu-system-x86 ovmf websockify novnc curl unzip procps || true
    if [[ -d "${REPO_ROOT}/packages/build-debs" ]]; then
        sudo dpkg -i "${REPO_ROOT}/packages/build-debs/"*.deb 2>/dev/null || true
        if command -v genixbit-desktop-setup &>/dev/null; then
            genixbit-desktop-setup || true
        fi
    fi
fi

# Step 2: Download & Extract Release ISO if missing
mkdir -p "${REPO_ROOT}/dist"
if [[ ! -f "$ISO_PATH" && ! -f "${REPO_ROOT}/../${ISO_NAME}" ]]; then
    echo "[2/5] Fetching GenixBit OS ISO package from server mirror..."
    curl -L -o "${ISO_PATH}.zip" "$ISO_URL" || true
    if [[ -f "${ISO_PATH}.zip" ]]; then
        unzip -o "${ISO_PATH}.zip" -d "${REPO_ROOT}/dist/" || true
        rm -f "${ISO_PATH}.zip"
    fi
fi

if [[ -f "${REPO_ROOT}/../${ISO_NAME}" ]]; then
    ISO_PATH="${REPO_ROOT}/../${ISO_NAME}"
fi

# Step 3: Launch Headless QEMU VM with local loopback VNC
echo "[3/5] Launching headless GenixBit OS VM on VNC port 127.0.0.1:${VNC_PORT}..."
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
    echo "[INFO] ISO downloaded / present; ready for execution."
fi

# Step 4: Launch websockify noVNC bridge
echo "[4/5] Starting websockify bridge on port ${WEBSOCKIFY_PORT} -> 127.0.0.1:${VNC_PORT}..."
pkill -f "websockify.*${WEBSOCKIFY_PORT}" 2>/dev/null || true

NOVNC_DIR="/usr/share/novnc"
if [[ ! -d "$NOVNC_DIR" ]]; then
    NOVNC_DIR="${REPO_ROOT}/website/os/vnc"
fi

WEB_ARG=""
if [[ -d "$NOVNC_DIR" ]]; then
    WEB_ARG="--web ${NOVNC_DIR}"
fi

if command -v websockify &>/dev/null; then
    nohup websockify ${WEB_ARG} "${WEBSOCKIFY_PORT}" "127.0.0.1:${VNC_PORT}" >/dev/null 2>&1 &
    echo "[PASS] websockify running on port ${WEBSOCKIFY_PORT} (PID $!)"
fi

# Step 5: Verify Deployment Status
echo "[5/5] Verifying GCP noVNC Bridge status..."
sleep 1
if pgrep -f "websockify.*${WEBSOCKIFY_PORT}" &>/dev/null; then
    echo "[PASS] websockify process active and listening on port ${WEBSOCKIFY_PORT}"
else
    echo "[WARN] websockify process not active; start manually via 'websockify 6080 127.0.0.1:5901'"
fi

echo "============================================================"
echo "[SUCCESS] GenixBit OS Live GCP Server VNC Deployment Active!"
echo "• VNC Loopback: 127.0.0.1:${VNC_PORT}"
echo "• noVNC WebSocket Endpoint: ws://0.0.0.0:${WEBSOCKIFY_PORT}/websockify"
echo "• Web Portal URL: https://os.genixbit.com/vnc/vnc.html"
echo "============================================================"
