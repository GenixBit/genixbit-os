#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Interactive VM Validation & Reproducibility Execution Orchestrator
#
# Run this script on an x86_64 Ubuntu 26.04 LTS host with KVM enabled.
#
# Copyright (C) 2026 GenixBit Labs Private Limited

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}

info() { printf '[INFO] %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

info "Starting GenixBit OS Interactive Runtime & Reproducibility Validation"
info "Host Architecture: $(uname -m)"
info "Host OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"

# 1. Host Audit
tools/vm/setup-host.sh || fail "Host readiness check failed."

# 2. Build ISO
info "Building primary ISO from current commit $(git rev-parse --short HEAD)..."
make clean
make bootstrap
make

# 3. Locate & Verify ISO Artifact
ISO_PATH=$(find dist -maxdepth 1 -type f -name 'GenixBitOS-0.1.0-alpha-*.iso' | sort | tail -n 1)
[[ -n "$ISO_PATH" ]] || fail "No ISO artifact was generated in dist/"

ISO_SIZE=$(stat -c '%s' "$ISO_PATH")
SHA256_DIGEST=$(sha256sum "$ISO_PATH" | awk '{print $1}')

info "Generated Primary ISO:"
info "  Path:   $ISO_PATH"
info "  Size:   $ISO_SIZE bytes"
info "  SHA256: $SHA256_DIGEST"

# 4. Preview Dry-Run
tools/vm/run-qemu.sh --mode bios --iso "$ISO_PATH" --sha256 "$SHA256_DIGEST" --create-disk --dry-run
tools/vm/run-qemu.sh --mode uefi --iso "$ISO_PATH" --sha256 "$SHA256_DIGEST" --create-disk --dry-run

info "Pre-flight checks passed."
info "To execute interactive BIOS VM validation, run:"
info "  tools/vm/run-qemu.sh --mode bios --iso $ISO_PATH --sha256 $SHA256_DIGEST --create-disk"
info ""
info "To execute interactive UEFI VM validation & installation, run:"
info "  tools/vm/run-qemu.sh --mode uefi --iso $ISO_PATH --sha256 $SHA256_DIGEST --create-disk"
info ""
info "To boot the installed UEFI virtual disk, run:"
info "  tools/vm/run-qemu.sh --mode uefi --installed --disk ~/.local/state/genixbit-os-vm/genixbit-uefi.qcow2"
