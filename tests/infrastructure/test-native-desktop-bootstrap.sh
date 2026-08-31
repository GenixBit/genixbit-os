#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
LIVE_INSTALLER="$ROOT_DIR/mods/05-live-kernel-apps-installer/install.sh"
NATIVE_INSTALLER="$ROOT_DIR/mods/06-install-genixbit-branding-mod/install.sh"
DESKTOP_CONTROL="$ROOT_DIR/packages/genixbit-os-desktop/debian/control"
ARGS_FILE="$ROOT_DIR/args.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

for file in "$LIVE_INSTALLER" "$NATIVE_INSTALLER" "$DESKTOP_CONTROL" "$ARGS_FILE"; do
    [[ -f "$file" ]] || fail "Missing required file: $file"
done

bash -n "$LIVE_INSTALLER"
bash -n "$NATIVE_INSTALLER"
bash -n "$ARGS_FILE"

grep -q 'xfce4' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must depend on XFCE"
grep -q 'lightdm' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must include a display manager"
grep -q 'pipewire-audio' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must include desktop audio"
grep -q 'genixbit-os-icons' "$DESKTOP_CONTROL" || fail "genixbit-os-desktop must include native icons"

if grep -q '^Provides:' "$DESKTOP_CONTROL"; then
    fail "genixbit-os-desktop must not falsely provide removed upstream applications"
fi

# Local/upstream-compatible builds may temporarily retain only the installer
# compatibility package. The inherited desktop/app/theme/session stack must stay out.
if grep -Eq '^[[:space:]]+(anduinos-desktop|anduinos-desktop-apps|anduinos-gnome-extensions|anduinos-appstore|anduinos-theme|anduinos-wallpapers|anduinos-fonts|anduinos-session|firefox-anduinos)([[:space:]\\]|$)' "$LIVE_INSTALLER"; then
    fail "Live bootstrap still installs an inherited AnduinOS desktop/application package"
fi

grep -q 'anduinos-installer-config' "$LIVE_INSTALLER" || \
    fail "Temporary installer compatibility dependency disappeared before native Calamares replacement"

native_packages="$(sed -n '/^packages=(/,/^)/p' "$NATIVE_INSTALLER")"
grep -q 'genixbit-os-desktop' <<<"$native_packages" || fail "Native desktop package is not installed"
grep -q 'genixbit-os-icons' <<<"$native_packages" || fail "Native icon package is not installed"
if grep -q 'genixbit-os-installer-config' <<<"$native_packages"; then
    fail "Incomplete native installer config must not replace the compatibility installer yet"
fi

if grep -q 'Before building AnduinOS' "$ARGS_FILE"; then
    fail "Stale upstream developer guidance remains in args.sh"
fi

echo "[PASS] Native GenixBit desktop bootstrap contract is enforced."
