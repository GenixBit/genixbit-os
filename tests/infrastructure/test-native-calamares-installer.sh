#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
PKG="$ROOT_DIR/packages/genixbit-os-installer-config"
CONTROL="$PKG/debian/control"
INSTALL="$PKG/debian/genixbit-os-installer-config.install"
SETTINGS="$PKG/etc/calamares/settings.conf"
MODULES="$PKG/etc/calamares/modules"
BRANDING="$PKG/etc/calamares/branding/genixbit/branding.desc"
LAUNCHER="$PKG/usr/bin/genixbit-os-installer"
DESKTOP="$PKG/usr/share/applications/genixbit-os-installer.desktop"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

required=(
    "$CONTROL"
    "$INSTALL"
    "$SETTINGS"
    "$MODULES/unpackfs.conf"
    "$MODULES/displaymanager.conf"
    "$MODULES/partition.conf"
    "$MODULES/welcome.conf"
    "$MODULES/packages.conf"
    "$BRANDING"
    "$LAUNCHER"
    "$DESKTOP"
)
for file in "${required[@]}"; do
    [[ -f "$file" ]] || fail "Missing native installer file: $file"
done

bash -n "$LAUNCHER"

grep -q 'calamares (>= 3.3.14)' "$CONTROL" || fail "Installer package must depend on current Calamares"
grep -q 'calamares-settings-ubuntu-common' "$CONTROL" || fail "Installer must use Ubuntu common Calamares settings"
grep -q '^etc/$' "$INSTALL" || fail "Calamares configuration is not packaged"
grep -q '^usr/$' "$INSTALL" || fail "Installer launcher/assets are not packaged"

grep -q 'branding: genixbit' "$SETTINGS" || fail "GenixBit branding is not selected"
grep -q 'disable-cancel-during-exec: true' "$SETTINGS" || fail "Install execution should not be cancelable mid-write"
grep -q '/cdrom/casper/filesystem.squashfs' "$MODULES/unpackfs.conf" || fail "Installer does not unpack the live squashfs"
grep -q 'lightdm' "$MODULES/displaymanager.conf" || fail "Installer does not configure LightDM"
grep -q 'startxfce4' "$MODULES/displaymanager.conf" || fail "Installer does not configure XFCE"
grep -q 'defaultFileSystemType: "ext4"' "$MODULES/partition.conf" || fail "Installer must use a conservative default filesystem"
grep -q 'genixbit-os-installer-config' "$MODULES/packages.conf" || fail "Installer package must be removed from installed target"

grep -q '^Exec=/usr/bin/genixbit-os-installer$' "$DESKTOP" || fail "Desktop launcher must use the fixed installer wrapper"
if grep -Eq '(curl|wget|eval|bash -c|sh -c|rm -rf|mkfs|wipefs|dd )' "$LAUNCHER"; then
    fail "Installer launcher contains an unexpected dynamic/destructive command"
fi

python3 - "$SETTINGS" "$MODULES/unpackfs.conf" "$MODULES/displaymanager.conf" "$MODULES/partition.conf" "$MODULES/welcome.conf" "$MODULES/packages.conf" "$BRANDING" <<'PY'
import pathlib
import sys
import yaml

for raw in sys.argv[1:]:
    path = pathlib.Path(raw)
    with path.open("r", encoding="utf-8") as handle:
        value = yaml.safe_load(handle)
    if not isinstance(value, dict):
        raise SystemExit(f"[FAIL] {path} does not contain a YAML mapping")
    print(f"[PASS] YAML: {path}")
PY

echo "[PASS] Native GenixBit Calamares installer contract is enforced."
