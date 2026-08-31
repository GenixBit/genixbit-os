#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
LIVE_INSTALLER="$ROOT_DIR/mods/05-live-kernel-apps-installer/install.sh"
NATIVE_INSTALLER="$ROOT_DIR/mods/06-install-genixbit-branding-mod/install.sh"
DESKTOP_CONTROL="$ROOT_DIR/packages/genixbit-os-desktop/debian/control"
ARGS_FILE="$ROOT_DIR/args.sh"
BUILD_FILE="$ROOT_DIR/build.sh"
SWAP_INSTALLER="$ROOT_DIR/mods/01-install-swap-packages-mod/install.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

for file in "$LIVE_INSTALLER" "$NATIVE_INSTALLER" "$DESKTOP_CONTROL" "$ARGS_FILE" "$BUILD_FILE" "$SWAP_INSTALLER"; do
    [[ -f "$file" ]] || fail "Missing required file: $file"
done

bash -n "$LIVE_INSTALLER"
bash -n "$NATIVE_INSTALLER"
bash -n "$ARGS_FILE"
bash -n "$BUILD_FILE"
bash -n "$SWAP_INSTALLER"

grep -q 'xfce4' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must depend on XFCE"
grep -q 'lightdm' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must include a display manager"
grep -q 'pipewire-audio' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must include desktop audio"
grep -q 'genixbit-os-icons' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must include native icons"

if grep -q '^Provides:' "$DESKTOP_CONTROL"; then
    fail "genixbit-os-desktop must not falsely provide removed upstream applications"
fi

# The default local build may use Ubuntu packages and local GenixBit packages only.
# Any AnduinOS package, repository, keyring, or installer reintroduced here is a
# regression in distribution ownership.
if grep -qi 'anduinos' "$LIVE_INSTALLER"; then
    fail "Local live bootstrap still references AnduinOS"
fi
if grep -qi 'anduinos' "$SWAP_INSTALLER"; then
    fail "Early local package bootstrap still references AnduinOS"
fi
if grep -qi 'packages\.anduinos\.com\|anduinos\.sources\|anduinos-archive-keyring' "$BUILD_FILE"; then
    fail "Local image builder still configures the AnduinOS repository"
fi

grep -q 'PACKAGE_SOURCE_MODE:-local' "$LIVE_INSTALLER" || fail "Live bootstrap must default to local mode"
grep -q 'PACKAGE_SOURCE_MODE:-local' "$SWAP_INSTALLER" || fail "Early bootstrap must default to local mode"
grep -q 'PACKAGE_SOURCE_MODE:-local' "$BUILD_FILE" || fail "Image builder must default to local mode"
grep -q 'PACKAGE_SOURCE_MODE:-local' "$ARGS_FILE" || fail "Build configuration must default to local mode"

native_packages="$(sed -n '/^packages=(/,/^)/p' "$NATIVE_INSTALLER")"
grep -q 'genixbit-os-desktop' <<<"$native_packages" || fail "Native desktop package is not installed"
grep -q 'genixbit-os-icons' <<<"$native_packages" || fail "Native icon package is not installed"
grep -q 'genixbit-os-installer-config' <<<"$native_packages" || fail "Native installer package is not installed"

if grep -q 'Before building AnduinOS' "$ARGS_FILE"; then
    fail "Stale upstream developer guidance remains in args.sh"
fi

echo "[PASS] Native GenixBit desktop bootstrap contract is enforced."
