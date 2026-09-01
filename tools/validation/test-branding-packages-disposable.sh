#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS branding packages lifecycle and diversion validator.

set -Eeuo pipefail
IFS=$'\n\t'

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

info() {
    printf '[INFO] %s\n' "$*"
}

# 1. SETUP BUILD PREREQUISITES INSIDE CONTAINER
info "Setting up test environment inside container..."
apt-get update -y
apt-get install -y debhelper dpkg-dev apt-utils --no-install-recommends

DEBS_DIR="/workspace/packages/build-debs"
BASE_SOURCE_DIR="/workspace/packages/genixbit-os-base-files"
[[ -d "$DEBS_DIR" ]] || fail "Build directory $DEBS_DIR does not exist"
[[ -f "$BASE_SOURCE_DIR/usr/lib/os-release" ]] || fail "Base identity source is missing"

packages=(
    "genixbit-os-base-files"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

base_deb=$(find "$DEBS_DIR" -maxdepth 1 -name 'genixbit-os-base-files_*.deb' | head -n 1)
[[ -n "$base_deb" ]] || fail "Missing built genixbit-os-base-files package"
base_package_version=$(dpkg-deb -f "$base_deb" Version)
[[ -n "$base_package_version" ]] || fail "Could not read built base-files package version"
expected_os_version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$BASE_SOURCE_DIR/usr/lib/os-release" | head -n 1)
expected_os_version_id=$(sed -n 's/^VERSION_ID="\(.*\)"$/\1/p' "$BASE_SOURCE_DIR/usr/lib/os-release" | head -n 1)
[[ -n "$expected_os_version" && -n "$expected_os_version_id" ]] || fail "Could not read expected OS identity version"

# Keep track of original Ubuntu base identity contents
orig_os_release=$(cat /etc/os-release)
orig_issue=$(cat /etc/issue)

# Verify no custom files are currently installed
if grep -q "GenixBit" /etc/os-release 2>/dev/null; then
    fail "System already has GenixBit identity before tests"
fi

# Run initial sanity checks
dpkg --audit
apt-get check

# 2. VERIFY CLEAN INSTALLATION
info "Performing clean installation of branding packages..."
for pkg in "${packages[@]}"; do
    deb_file=$(find "$DEBS_DIR" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    [[ -n "$deb_file" ]] || fail "Missing deb file for $pkg"
    info "Installing $deb_file with dependency resolution..."
    apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confnew" \
        "$deb_file"

    dpkg --audit
    apt-get check
done

pass "All packages installed cleanly."

# 3. VERIFY FILE OWNERSHIP AND DIVERSIONS
info "Verifying file ownership and dpkg-divert states..."
diverted_files=(
    "/usr/lib/os-release"
    "/etc/lsb-release"
    "/etc/issue"
    "/etc/issue.net"
)

for f in "${diverted_files[@]}"; do
    dpkg-divert --list "$f" | grep -q "genixbit-os-base-files" || fail "$f is not diverted by genixbit-os-base-files"
    dpkg -S "$f" | grep -q "genixbit-os-base-files" || fail "$f is not owned by genixbit-os-base-files in dpkg database"
done

pass "File ownership and diversions verified."

# 4. VERIFY IDENTITY CONTENTS
info "Validating branding identity contents..."
grep -q 'NAME="GenixBit OS"' /etc/os-release || fail "NAME was not updated in /etc/os-release"
grep -Fq "VERSION=\"$expected_os_version\"" /etc/os-release || fail "VERSION does not match packaged identity ($expected_os_version)"
grep -Fq "VERSION_ID=\"$expected_os_version_id\"" /etc/os-release || fail "VERSION_ID does not match packaged identity ($expected_os_version_id)"

[[ -f "/usr/share/pixmaps/genixbit-mark.svg" ]] || fail "Theme icon is missing"
[[ -f "/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg" ]] || fail "Dark wallpaper is missing"
[[ -f "/usr/share/genixbit-os-installer-config/slides/welcome.html" ]] || fail "Welcome slide is missing"

pass "Identity contents verified."

# 5. VERIFY UPGRADE
info "Verifying package upgrade cycle..."
UPGRADE_TEMP=$(mktemp -d)
cp -r "$BASE_SOURCE_DIR" "$UPGRADE_TEMP/"
ch_path="$UPGRADE_TEMP/genixbit-os-base-files/debian/changelog"
upgrade_version="${base_package_version}+ci1"

cat - "$ch_path" <<EOF > "$UPGRADE_TEMP/new_changelog"
genixbit-os-base-files ($upgrade_version) resolute; urgency=medium

  * Disposable lifecycle upgrade validation.

 -- GenixBit Labs Private Limited <maintainers@genixbit.com>  Sun, 30 Aug 2026 00:00:00 +0000

EOF
mv "$UPGRADE_TEMP/new_changelog" "$ch_path"

(
    cd "$UPGRADE_TEMP/genixbit-os-base-files"
    chmod +x debian/rules
    dpkg-buildpackage -us -uc -b
)

upgrade_deb=$(find "$UPGRADE_TEMP" -maxdepth 1 -name "genixbit-os-base-files_${upgrade_version}_*.deb" | head -n 1)
[[ -n "$upgrade_deb" ]] || fail "Failed to build upgrade deb package for $upgrade_version"

info "Upgrading package with $upgrade_deb..."
dpkg -i --force-confnew "$upgrade_deb"

installed_ver=$(dpkg-query -W -f='${Version}' genixbit-os-base-files)
if [[ "$installed_ver" != "$upgrade_version" ]]; then
    fail "Upgrade failed: version is $installed_ver, expected $upgrade_version"
fi

dpkg --audit
apt-get check
pass "Package upgrade verified."

# 6. VERIFY ROLLBACK / DOWNGRADE
info "Verifying package rollback (downgrade) cycle..."
info "Downgrading to original built version $base_package_version using $base_deb..."
dpkg -i --force-confnew "$base_deb"

rolled_ver=$(dpkg-query -W -f='${Version}' genixbit-os-base-files)
if [[ "$rolled_ver" != "$base_package_version" ]]; then
    fail "Rollback failed: version is $rolled_ver, expected $base_package_version"
fi

dpkg --audit
apt-get check
pass "Package rollback verified."

# 7. VERIFY REMOVAL & PURGE (BASE IDENTITY RESTORATION)
info "Verifying package removal, purge, and identity restoration..."
for pkg in "${packages[@]}"; do
    info "Purging package: $pkg..."
    dpkg -P "$pkg"
    dpkg --audit
    apt-get check
done

if grep -q "GenixBit" /etc/os-release 2>/dev/null; then
    fail "/etc/os-release was not restored to original state"
fi

restored_os_release=$(cat /etc/os-release)
if [[ "$restored_os_release" != "$orig_os_release" ]]; then
    fail "Restored /etc/os-release contents do not match original"
fi

restored_issue=$(cat /etc/issue)
if [[ "$restored_issue" != "$orig_issue" ]]; then
    fail "Restored /etc/issue contents do not match original"
fi

for f in "${diverted_files[@]}"; do
    [[ -f "$f" ]] || fail "Diverted file $f is missing after package purge"
done

rm -rf "$UPGRADE_TEMP"

pass "Package removal and identity restoration verified successfully!"
info "All lifecycle tests PASSED."
exit 0
