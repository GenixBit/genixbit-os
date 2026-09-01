#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installed-system validation entry point for the current GenixBit OS ISO.
#
# Native GenixBit images use Calamares. Until an auditable, test-only unattended
# Calamares profile exists, this command intentionally fails closed instead of
# fabricating completion tokens, disk layouts, or authenticated guest output.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=2700

fail() {
    printf '[FAIL] install-current-iso.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --iso)
            (($# >= 2)) || fail '--iso requires a path.'
            ISO_PATH=$2
            shift 2
            ;;
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || fail 'Valid --iso path is required.'
[[ -n "$DISK_PATH" ]] || fail '--disk path is required.'
[[ "$MODE" == "uefi" || "$MODE" == "bios" ]] || fail '--mode must be bios or uefi.'
[[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || fail '--timeout must be an integer number of seconds.'

ISO_SHA=$(sha256sum "$ISO_PATH" | awk '{print $1}')
printf '[INFO] Current ISO SHA-256: %s\n' "$ISO_SHA"
printf '[INFO] Requested installed-system validation mode: %s\n' "$MODE"

cat >&2 <<'EOF'
[BLOCKED] Native Calamares installed-system automation is not yet implemented.

The previous implementation used a Subiquity/NoCloud seed against a Calamares
image, treated live-session boot progress as installer completion, wrote the
expected completion token from the host, and generated synthetic SSH validation
logs. Those behaviors are prohibited because they can create false release
evidence.

Use tools/vm/smoke-current-live-iso.sh for non-destructive live-session boot
validation. Installed-system validation must remain FAIL until a disposable,
auditable Calamares test profile performs a real installation and the resulting
disk is verified by tools/vm/verify-disk-structure.sh plus authenticated guest
commands after booting from that disk.
EOF

fail 'Refusing to generate installed-system PASS evidence without a real native Calamares installation.'
