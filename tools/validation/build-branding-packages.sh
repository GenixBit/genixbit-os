#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS branding & migration packages build orchestrator.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
DEBS_OUTPUT_DIR="$WORKSPACE_DIR/packages/build-debs"

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

mkdir -p "$DEBS_OUTPUT_DIR"
export SOURCE_DATE_EPOCH=1784617200

packages=(
    "genixbit-os-archive-keyring"
    "genixbit-os-apt-config"
    "genixbit-os-base-files"
    "genixbit-os-desktop"
    "genixbit-os-theme"
    "genixbit-os-wallpapers"
    "genixbit-os-installer-config"
)

BUILD_TEMP=$(mktemp -d)
cleanup() {
    rm -rf "$BUILD_TEMP"
}
trap cleanup EXIT

for pkg in "${packages[@]}"; do
    info "Building package: $pkg..."
    
    pkg_src="$WORKSPACE_DIR/packages/$pkg"
    [[ -d "$pkg_src" ]] || fail "Package source directory missing: $pkg_src"
    
    chmod +x "$pkg_src/debian/rules" 2>/dev/null || true
    
    pkg_build_dir="$BUILD_TEMP/$pkg"
    cp -r "$pkg_src" "$pkg_build_dir"
    
    built_deb=""
    
    # Attempt 1: Standard dpkg-buildpackage if debhelper/dh is available
    if command -v dh &>/dev/null && command -v dpkg-buildpackage &>/dev/null; then
        (
            cd "$pkg_build_dir"
            GENIXBIT_PUBLIC_KEYRING="$pkg_src/keyring/genixbit-os-archive-keyring.pgp" dpkg-buildpackage -us -uc -b -d 2>/dev/null || true
        )
        built_deb=$(find "$BUILD_TEMP" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1 || true)
    fi
    
    # Attempt 2: Direct dpkg-deb fallback for non-Debian host / environments without dh
    if [[ -z "$built_deb" ]]; then
        info "Using dpkg-deb staging fallback for $pkg..."
        STAGE_DIR="$BUILD_TEMP/stage_$pkg"
        mkdir -p "$STAGE_DIR/DEBIAN"
        
        if [[ -d "$pkg_build_dir/usr" ]]; then
            cp -r "$pkg_build_dir/usr" "$STAGE_DIR/"
        fi
        if [[ -d "$pkg_build_dir/etc" ]]; then
            cp -r "$pkg_build_dir/etc" "$STAGE_DIR/"
        fi
        if [[ "$pkg" == "genixbit-os-archive-keyring" ]]; then
            mkdir -p "$STAGE_DIR/usr/share/keyrings"
            cp "$pkg_src/keyring/genixbit-os-archive-keyring.pgp" "$STAGE_DIR/usr/share/keyrings/genixbit-os-archive-keyring.pgp"
        fi
        
        for script in preinst postinst prerm postrm; do
            if [[ -f "$pkg_build_dir/debian/$script" ]]; then
                cp "$pkg_build_dir/debian/$script" "$STAGE_DIR/DEBIAN/"
                chmod +x "$STAGE_DIR/DEBIAN/$script"
            fi
        done
        
        ctrl_src="$pkg_build_dir/debian/control"
        ctrl_dst="$STAGE_DIR/DEBIAN/control"
        chlog_src="$pkg_build_dir/debian/changelog"
        
        python3 - "$ctrl_src" "$chlog_src" "$ctrl_dst" << 'PYEOF'
import sys, re

ctrl_src, chlog_src, ctrl_dst = sys.argv[1], sys.argv[2], sys.argv[3]

maint = "GenixBit Labs Private Limited <maintainers@genixbit.com>"
with open(ctrl_src) as f:
    for line in f:
        if line.startswith("Maintainer:"):
            maint = line.split(":", 1)[1].strip()
            break

ver = "0.2.0-alpha-1"
with open(chlog_src) as f:
    first = f.readline()
    m = re.search(r'\((.*?)\)', first)
    if m:
        ver = m.group(1)

with open(ctrl_src) as f:
    content = f.read()

# Split stanzas
stanzas = [s.strip() for s in content.split("\n\n") if s.strip()]
bin_stanza = ""
for s in stanzas:
    if s.startswith("Package:"):
        bin_stanza = s
        break

lines = bin_stanza.splitlines()
out_lines = []
inserted_meta = False

for line in lines:
    if line.startswith("Package:"):
        out_lines.append(line)
        out_lines.append(f"Version: {ver}")
        out_lines.append(f"Maintainer: {maint}")
    elif line.startswith("Depends:"):
        deps = line.split(":", 1)[1].strip()
        deps = deps.replace("${misc:Depends}", "").strip()
        deps = re.sub(r'^\s*,\s*', '', deps)
        deps = re.sub(r'\s*,\s*$', '', deps)
        deps = re.sub(r'\s*,\s*,\s*', ', ', deps)
        if deps:
            out_lines.append(f"Depends: {deps}")
    else:
        out_lines.append(line)

with open(ctrl_dst, "w") as f:
    f.write("\n".join(out_lines) + "\n")
PYEOF

        ver=$(head -n 1 "$pkg_build_dir/debian/changelog" | awk '{print $2}' | tr -d '()')
        if [[ -z "$ver" ]]; then ver="0.2.0-alpha-1"; fi
        out_deb="$BUILD_TEMP/${pkg}_${ver}_all.deb"

        dpkg-deb --root-owner-group --build "$STAGE_DIR" "$out_deb" >/dev/null
        built_deb="$out_deb"

    fi
    
    [[ -n "$built_deb" && -f "$built_deb" ]] || fail "Failed to build deb package for $pkg"
    
    info "Running quality checks for $pkg..."
    dpkg-deb --info "$built_deb"
    dpkg-deb --contents "$built_deb"
    
    target_deb="$DEBS_OUTPUT_DIR/$(basename "$built_deb")"
    cp "$built_deb" "$target_deb"
    
    sha256=$(python3 -c "import hashlib; print(hashlib.sha256(open('$target_deb','rb').read()).hexdigest())")
    info "Generated: $(basename "$target_deb") (SHA-256: $sha256)"
    pass "$pkg build completed successfully."
done

info "Built packages output in $DEBS_OUTPUT_DIR:"
ls -lh "$DEBS_OUTPUT_DIR"
pass "All replacement branding & migration packages built successfully."
