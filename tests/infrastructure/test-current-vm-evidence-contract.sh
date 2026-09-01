#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
INSTALLER="$ROOT_DIR/tools/vm/install-current-iso.sh"
DISK_VERIFY="$ROOT_DIR/tools/vm/verify-disk-structure.sh"
LIVE_SMOKE="$ROOT_DIR/tools/vm/smoke-current-live-iso.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

for file in "$INSTALLER" "$DISK_VERIFY" "$LIVE_SMOKE"; do
    [[ -f "$file" ]] || fail "Missing VM validation file: $file"
    bash -n "$file"
done

# Installed-system validation must fail closed while native Calamares has no
# auditable unattended test profile. The removed implementation generated host-
# produced completion tokens and synthetic SSH logs.
grep -q 'Native Calamares installed-system automation is not yet implemented' "$INSTALLER" || \
    fail 'Current installer validation does not document its fail-closed Calamares blocker.'

for forbidden in \
    'generate_guest_validation_log' \
    'Authenticated Guest Command Output (ssh)' \
    'PRETTY_NAME="GenixBit OS 0.3.0-alpha' \
    'echo "$INSTALL_TOKEN" >> "$serial_log"'; do
    if grep -Fq "$forbidden" "$INSTALLER"; then
        fail "Synthetic installed-system evidence pattern remains: $forbidden"
    fi
done

# Disk evidence must be derived from actual libguestfs inspection. Reject the
# former static disk layout/kernel/bootloader claims.
grep -q 'guestfish' "$DISK_VERIFY" || fail 'Disk verifier must use libguestfs.'
grep -q 'inspect-os' "$DISK_VERIFY" || fail 'Disk verifier must discover an installed root.'
grep -q 'list-partitions' "$DISK_VERIFY" || fail 'Disk verifier must observe partitions.'
grep -q 'list-filesystems' "$DISK_VERIFY" || fail 'Disk verifier must observe filesystems.'
grep -q 'OBSERVED_TOKEN' "$DISK_VERIFY" || fail 'Disk verifier must read the completion token from disk.'

for forbidden in \
    "vmlinuz-6.8.0-generic" \
    "initrd.img-6.8.0-generic" \
    "parts = ['/dev/vda1', '/dev/vda2']" \
    "'bootloader_valid': True"; do
    if grep -Fq "$forbidden" "$DISK_VERIFY"; then
        fail "Static disk evidence pattern remains: $forbidden"
    fi
done

# Live runtime smoke must use three independent real observations: QMP process
# readiness, serial graphical-session evidence, and an actual QMP framebuffer.
grep -q 'query-active-status' "$LIVE_SMOKE" || fail 'Live smoke lacks QMP readiness evidence.'
grep -Eq 'Graphical Interface|graphical\\.target' "$LIVE_SMOKE" || fail 'Live smoke lacks graphical-target evidence.'
grep -q 'Light Display Manager' "$LIVE_SMOKE" || fail 'Live smoke lacks LightDM evidence.'
grep -q 'capture-screenshot.sh' "$LIVE_SMOKE" || fail 'Live smoke lacks real framebuffer capture.'
grep -q 'Framebuffer is uniform' "$LIVE_SMOKE" || fail 'Live smoke does not reject a uniform framebuffer.'

if grep -q 'autoinstall' "$LIVE_SMOKE"; then
    fail 'Non-destructive live smoke must not invoke unattended installation.'
fi

if grep -Eq 'echo .*PASS.*>|status.*PASS.*cat' "$LIVE_SMOKE"; then
    fail 'Live smoke contains suspicious unconditional PASS evidence generation.'
fi

echo '[PASS] Current VM evidence contract rejects synthetic install evidence and requires observed runtime evidence.'
