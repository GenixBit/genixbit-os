#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — test-host setup and readiness check for interactive VM validation.
#
# Run this script on the approved x86_64 Ubuntu 26.04 test host before
# executing verify-runtime.sh or run-qemu.sh.
#
# Usage:
#   tools/vm/setup-host.sh [options]
#
# Options:
#   --iso PATH                    Optional GenixBit OS ISO to inspect.
#   --sha256 DIGEST               Expected ISO SHA-256; requires --iso.
#   --skip-install                Audit only; do not install packages.
#   --allow-software-emulation    Permit a host without accessible KVM.
#   -h, --help                    Show this help.
#
# Copyright (C) 2026 GenixBit Labs Private Limited

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
ISO_PATH=""
EXPECTED_SHA256=""
SKIP_INSTALL=false
ALLOW_SOFTWARE_EMULATION=false

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SUDO_READY=false

increment() {
    local variable_name=$1
    printf -v "$variable_name" '%d' "$(( ${!variable_name} + 1 ))"
}

pass() {
    printf '[PASS] %s\n' "$*"
    increment PASS_COUNT
}

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    increment FAIL_COUNT
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
    increment WARN_COUNT
}

info() {
    printf '[INFO] %s\n' "$*"
}

usage() {
    cat <<EOF
Usage: ${PROGRAM} [options]

Options:
  --iso PATH                    Optional GenixBit OS ISO to inspect.
  --sha256 DIGEST               Expected ISO SHA-256; requires --iso.
  --skip-install                Audit only; do not install packages.
  --allow-software-emulation    Permit a host without accessible KVM.
  -h, --help                    Show this help.
EOF
}

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
        --allow-software-emulation)
            ALLOW_SOFTWARE_EMULATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -n "$EXPECTED_SHA256" && -z "$ISO_PATH" ]]; then
    printf 'Error: --sha256 requires --iso.\n' >&2
    exit 1
fi

if [[ -n "$EXPECTED_SHA256" && ! "$EXPECTED_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
    printf 'Error: --sha256 must contain exactly 64 hexadecimal characters.\n' >&2
    exit 1
fi

info "GenixBit OS — interactive VM validation host setup"
info "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '\n'

info "Checking host architecture..."
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    pass "Host architecture: $ARCH"
else
    fail "Host architecture is $ARCH; x86_64 is required."
fi

info "Checking host operating system..."
if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    HOST_CODENAME=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
    if [[ ${ID:-} == "ubuntu" && "$HOST_CODENAME" == "resolute" ]]; then
        pass "Host OS: ${PRETTY_NAME:-Ubuntu} (${HOST_CODENAME})"
    else
        fail "Host must be Ubuntu 26.04 'resolute'; detected ${PRETTY_NAME:-unknown} (${HOST_CODENAME:-unknown})."
    fi
else
    fail "Cannot read /etc/os-release."
fi

info "Checking CPU core count..."
CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0)
if ((CORES >= 4)); then
    pass "CPU cores: $CORES"
elif ((CORES >= 2)); then
    warn "CPU cores: $CORES; four or more are recommended."
else
    fail "CPU cores: $CORES; at least two are required."
fi

info "Checking available RAM..."
TOTAL_KB=$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
TOTAL_GB=$((TOTAL_KB / 1024 / 1024))
if ((TOTAL_GB >= 12)); then
    pass "Host RAM: ${TOTAL_GB} GB"
elif ((TOTAL_GB >= 8)); then
    warn "Host RAM: ${TOTAL_GB} GB; 12 GB or more is recommended."
else
    fail "Host RAM: ${TOTAL_GB} GB; at least 8 GB is required."
fi

info "Checking free disk space..."
FREE_KB=$(df --output=avail "${HOME}" 2>/dev/null | tail -1 || echo 0)
FREE_GB=$((FREE_KB / 1024 / 1024))
if ((FREE_GB >= 100)); then
    pass "Free disk space: ${FREE_GB} GB"
elif ((FREE_GB >= 60)); then
    warn "Free disk space: ${FREE_GB} GB; 100 GB is recommended for two builds and VM disks."
else
    fail "Free disk space: ${FREE_GB} GB; at least 60 GB is required."
fi

info "Checking non-interactive sudo access..."
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    SUDO_READY=true
    pass "Approved non-interactive sudo access is available."
else
    fail "The validation account requires approved passwordless sudo for build and package operations."
fi

info "Checking KVM availability..."
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    pass "KVM is readable and writable."
elif [[ "$ALLOW_SOFTWARE_EMULATION" == true ]]; then
    warn "KVM is unavailable; explicitly permitted software emulation will be slow."
else
    fail "KVM is unavailable. Use --allow-software-emulation only for an explicitly approved slow test."
fi

REQUIRED_PACKAGES=(
    qemu-system-x86
    qemu-utils
    ovmf
    curl
    diffoscope
    xorriso
    squashfs-tools
    genisoimage
    mtools
    file
)

if [[ "$SKIP_INSTALL" == false ]]; then
    info "Installing validation packages..."
    if ! command -v apt-get >/dev/null 2>&1; then
        fail "apt-get is unavailable."
    elif [[ "$SUDO_READY" != true ]]; then
        fail "Cannot install packages because approved sudo access is unavailable."
    elif sudo apt-get update -qq && sudo apt-get install -y "${REQUIRED_PACKAGES[@]}"; then
        pass "Validation package installation completed."
    else
        fail "Validation package installation failed."
    fi
fi

info "Checking required commands..."
for cmd in git make qemu-system-x86_64 qemu-img sha256sum curl diffoscope xorriso unsquashfs isoinfo mdir file realpath; do
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "Command available: $cmd"
    else
        fail "Command not found: $cmd"
    fi
done

if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    QEMU_VERSION=$(qemu-system-x86_64 --version | head -1)
    pass "QEMU version: $QEMU_VERSION"
fi

info "Checking OVMF firmware files..."
OVMF_FOUND=false
OVMF_CANDIDATES=(
    '/usr/share/OVMF/OVMF_CODE_4M.fd|/usr/share/OVMF/OVMF_VARS_4M.fd'
    '/usr/share/OVMF/OVMF_CODE.fd|/usr/share/OVMF/OVMF_VARS.fd'
    '/usr/share/edk2/ovmf/OVMF_CODE.fd|/usr/share/edk2/ovmf/OVMF_VARS.fd'
    '/usr/share/qemu/OVMF_CODE.fd|/usr/share/qemu/OVMF_VARS.fd'
)
for pair in "${OVMF_CANDIDATES[@]}"; do
    IFS='|' read -r code vars <<<"$pair"
    if [[ -r "$code" && -r "$vars" ]]; then
        pass "OVMF found: code=$code vars=$vars"
        OVMF_FOUND=true
        break
    fi
done
if [[ "$OVMF_FOUND" == false ]]; then
    fail "No matching OVMF code and variables pair was found."
fi

if [[ -n "$ISO_PATH" ]]; then
    info "Verifying ISO: $ISO_PATH"
    if [[ ! -f "$ISO_PATH" ]]; then
        fail "ISO file not found: $ISO_PATH"
    else
        ISO_SIZE=$(stat -c '%s' "$ISO_PATH" 2>/dev/null || echo unknown)
        info "ISO size: $ISO_SIZE bytes"
        ACTUAL_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
        if [[ -n "$EXPECTED_SHA256" ]]; then
            if [[ "${ACTUAL_SHA256,,}" == "${EXPECTED_SHA256,,}" ]]; then
                pass "ISO SHA-256 matched: $ACTUAL_SHA256"
            else
                fail "ISO SHA-256 mismatch. Expected $EXPECTED_SHA256; received $ACTUAL_SHA256."
            fi
        else
            info "ISO SHA-256: $ACTUAL_SHA256"
        fi
    fi
fi

STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/genixbit-os-vm"
info "VM state directory: $STATE_DIR"
if mkdir -p "$STATE_DIR"; then
    pass "State directory exists or was created."
else
    fail "Unable to create state directory: $STATE_DIR"
fi

printf '\n'
printf '═══════════════════════════════════════════════════════\n'
printf '  GenixBit OS VM validation host readiness summary\n'
printf '═══════════════════════════════════════════════════════\n'
printf '  PASS: %d\n' "$PASS_COUNT"
printf '  WARN: %d\n' "$WARN_COUNT"
printf '  FAIL: %d\n' "$FAIL_COUNT"
printf '═══════════════════════════════════════════════════════\n'

if ((FAIL_COUNT > 0)); then
    printf '[RESULT] Host is NOT ready. Resolve the failures above before validation.\n' >&2
    exit 1
elif ((WARN_COUNT > 0)); then
    printf '[RESULT] Host is ready with warnings that require review.\n'
else
    printf '[RESULT] Host is ready for GenixBit OS interactive VM validation.\n'
fi
