#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — test host setup and readiness check for interactive VM validation.
#
# Run this script on the x86_64 Ubuntu test host before executing run-qemu.sh.
# It installs required packages and verifies that the host meets minimum requirements.
#
# Usage:
#   bash tools/vm/setup-host.sh [--iso PATH] [--sha256 DIGEST]
#
# Options:
#   --iso PATH       Path to the GenixBit OS ISO to verify. Optional.
#   --sha256 DIGEST  Expected SHA-256 of the ISO. Optional; checked only when --iso is given.
#   --skip-install   Skip package installation (audit only).
#
# Copyright (C) 2026 GenixBit Labs Private Limited
# GPL-3.0-or-later — see LICENSE in the repository root.

set -Eeuo pipefail
IFS=$'
	'

PROGRAM=${0##*/}
ISO_PATH=""
EXPECTED_SHA256=""
SKIP_INSTALL=false

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() { printf '[PASS] %s\n' "$*"; ((PASS_COUNT++)); }
fail() { printf '[FAIL] %s\n' "$*" >&2; ((FAIL_COUNT++)); }
warn() { printf '[WARN] %s\n' "$*" >&2; ((WARN_COUNT++)); }
info() { printf '[INFO] %s\n' "$*"; }

while (($# > 0)); do
    case "$1" in
        --iso)
            (($# >= 2)) || { printf 'Error: --iso requires a path.\n' >&2; exit 1; }
            ISO_PATH=$2
            shift 2
            ;;
        --sha256)
            (($# >= 2)) || { printf 'Error: --sha256 requires a digest.\n' >&2; exit 1; }
            EXPECTED_SHA256=$2
            shift 2
            ;;
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        -h|--help)
            printf 'Usage: %s [--iso PATH] [--sha256 DIGEST] [--skip-install]\n' "$PROGRAM"
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

info "GenixBit OS — interactive VM validation host setup"
info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '\n'

# ── Architecture check ────────────────────────────────────────────────────────
info "Checking host architecture..."
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    pass "Host architecture: $ARCH"
else
    fail "Host architecture is $ARCH; x86_64 is required for KVM validation."
fi

# ── OS version ────────────────────────────────────────────────────────────────
info "Checking host OS..."
if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    pass "Host OS: ${PRETTY_NAME:-unknown}"
else
    warn "Cannot read /etc/os-release."
fi

# ── CPU and core count ────────────────────────────────────────────────────────
info "Checking CPU core count..."
CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0)
if ((CORES >= 4)); then
    pass "CPU cores: $CORES (>= 4 required)"
elif ((CORES >= 2)); then
    warn "CPU cores: $CORES (4+ recommended; 2 may be slow but usable)"
else
    fail "CPU cores: $CORES (at least 2 required)"
fi

# ── RAM ───────────────────────────────────────────────────────────────────────
info "Checking available RAM..."
TOTAL_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
TOTAL_GB=$(( TOTAL_KB / 1024 / 1024 ))
if ((TOTAL_GB >= 12)); then
    pass "Host RAM: ${TOTAL_GB} GB (>= 12 GB recommended)"
elif ((TOTAL_GB >= 8)); then
    warn "Host RAM: ${TOTAL_GB} GB (12+ GB recommended; 8 GB minimum for 8 GB guest)"
else
    fail "Host RAM: ${TOTAL_GB} GB (minimum 8 GB required for 8 GB guest allocation)"
fi

# ── Free disk ─────────────────────────────────────────────────────────────────
info "Checking free disk space..."
FREE_KB=$(df --output=avail / 2>/dev/null | tail -1 || echo 0)
FREE_GB=$(( FREE_KB / 1024 / 1024 ))
if ((FREE_GB >= 100)); then
    pass "Free disk space: ${FREE_GB} GB (>= 100 GB required)"
elif ((FREE_GB >= 60)); then
    warn "Free disk space: ${FREE_GB} GB (100 GB recommended; 60 GB may be sufficient)"
else
    fail "Free disk space: ${FREE_GB} GB (at least 60 GB required for disks, ISO and second build)"
fi

# ── KVM ───────────────────────────────────────────────────────────────────────
info "Checking KVM availability..."
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    pass "KVM: /dev/kvm is readable and writable — hardware acceleration available."
elif [[ -e /dev/kvm ]]; then
    warn "KVM: /dev/kvm exists but is not accessible by current user. Add user to 'kvm' group: sudo usermod -aG kvm \$USER"
else
    warn "KVM: /dev/kvm not present. Tests can run in software emulation but will be very slow."
fi

# ── Package installation ──────────────────────────────────────────────────────
REQUIRED_PACKAGES=(
    qemu-system-x86
    qemu-utils
    ovmf
    curl
    diffoscope
    xorriso
    squashfs-tools
)

if [[ "$SKIP_INSTALL" == false ]]; then
    info "Installing required packages..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y "${REQUIRED_PACKAGES[@]}"
        pass "Package installation: complete."
    else
        warn "apt-get not found. Install manually: ${REQUIRED_PACKAGES[*]}"
    fi
fi

# ── Required commands ─────────────────────────────────────────────────────────
info "Checking required commands..."
for cmd in qemu-system-x86_64 qemu-img sha256sum curl diffoscope xorriso unsquashfs; do
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "Command available: $cmd ($(command -v "$cmd"))"
    else
        fail "Command not found: $cmd"
    fi
done

# ── QEMU version ──────────────────────────────────────────────────────────────
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    QEMU_VERSION=$(qemu-system-x86_64 --version | head -1)
    pass "QEMU version: $QEMU_VERSION"
fi

# ── OVMF firmware ─────────────────────────────────────────────────────────────
info "Checking OVMF firmware files..."
OVMF_FOUND=false
declare -a OVMF_CANDIDATES=(
    '/usr/share/OVMF/OVMF_CODE_4M.fd|/usr/share/OVMF/OVMF_VARS_4M.fd'
    '/usr/share/OVMF/OVMF_CODE.fd|/usr/share/OVMF/OVMF_VARS.fd'
    '/usr/share/edk2/ovmf/OVMF_CODE.fd|/usr/share/edk2/ovmf/OVMF_VARS.fd'
    '/usr/share/qemu/OVMF_CODE.fd|/usr/share/qemu/OVMF_VARS.fd'
)
for pair in "${OVMF_CANDIDATES[@]}"; do
    IFS='|' read -r code vars <<< "$pair"
    if [[ -r "$code" && -r "$vars" ]]; then
        pass "OVMF found: code=$code vars=$vars"
        OVMF_FOUND=true
        break
    fi
done
if [[ "$OVMF_FOUND" == false ]]; then
    fail "No OVMF firmware pair found. Install 'ovmf' package."
fi

# ── ISO verification (optional) ───────────────────────────────────────────────
if [[ -n "$ISO_PATH" ]]; then
    info "Verifying ISO: $ISO_PATH"
    if [[ ! -f "$ISO_PATH" ]]; then
        fail "ISO file not found: $ISO_PATH"
    else
        ISO_SIZE=$(stat -c%s "$ISO_PATH" 2>/dev/null || stat -f%z "$ISO_PATH" 2>/dev/null || echo "unknown")
        info "ISO size: $ISO_SIZE bytes"
        if [[ -n "$EXPECTED_SHA256" ]]; then
            info "Computing SHA-256 (this may take 30–60 seconds)..."
            ACTUAL_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
            if [[ "${ACTUAL_SHA256,,}" == "${EXPECTED_SHA256,,}" ]]; then
                pass "ISO SHA-256 matched: $ACTUAL_SHA256"
            else
                fail "ISO SHA-256 MISMATCH. Expected: $EXPECTED_SHA256 Got: $ACTUAL_SHA256"
            fi
        else
            SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
            info "ISO SHA-256: $SHA256 (no expected value provided for comparison)"
        fi
    fi
fi

# ── State directory ───────────────────────────────────────────────────────────
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/genixbit-os-vm"
info "VM state directory: $STATE_DIR"
mkdir -p "$STATE_DIR"
pass "State directory exists or was created: $STATE_DIR"

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n'
printf '═══════════════════════════════════════════════════════\n'
printf '  GenixBit OS VM validation host readiness summary\n'
printf '═══════════════════════════════════════════════════════\n'
printf '  PASS: %d\n' "$PASS_COUNT"
printf '  WARN: %d\n' "$WARN_COUNT"
printf '  FAIL: %d\n' "$FAIL_COUNT"
printf '═══════════════════════════════════════════════════════\n'

if ((FAIL_COUNT > 0)); then
    printf '[RESULT] Host is NOT ready. Resolve the failures above before running run-qemu.sh.\n' >&2
    exit 1
elif ((WARN_COUNT > 0)); then
    printf '[RESULT] Host has warnings. Review them before proceeding.\n'
    exit 0
else
    printf '[RESULT] Host is ready for GenixBit OS interactive VM validation.\n'
    exit 0
fi
