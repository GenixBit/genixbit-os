#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS Multi-Channel APT Staging & SBOM Generation Utility
# Publishes built deb packages to target channels (alpha, beta, stable) and generates SBOM attestations.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHANNEL=${1:-"alpha"}
BUILD_DEBS_DIR="${REPO_ROOT}/packages/build-debs"
REPO_OUTPUT_DIR="${REPO_ROOT}/dist/apt-repo/${CHANNEL}"

echo "============================================================"
echo "    GenixBit OS 1.1.0 — APT Channel Publisher & SBOM Gen    "
echo "============================================================"
echo "• Target Channel:      ${CHANNEL}"
echo "• Source Debs:         ${BUILD_DEBS_DIR}"
echo "• Repository Output:   ${REPO_OUTPUT_DIR}"
echo "------------------------------------------------------------"

if [[ ! -d "$BUILD_DEBS_DIR" ]]; then
    echo "[INFO] Building debian packages..."
    python3 "${REPO_ROOT}/tools/build-phase4-debs.py"
fi

mkdir -p "${REPO_OUTPUT_DIR}/pool/main"
mkdir -p "${REPO_OUTPUT_DIR}/dists/resolute-${CHANNEL}/main/binary-all"

# Copy deb packages
cp -f "${BUILD_DEBS_DIR}/"*.deb "${REPO_OUTPUT_DIR}/pool/main/"

# Generate Packages manifest
echo "[1/3] Generating Packages index manifest..."
PKG_INDEX="${REPO_OUTPUT_DIR}/dists/resolute-${CHANNEL}/main/binary-all/Packages"
> "$PKG_INDEX"

TMP_CTRL="${REPO_ROOT}/packages/.tmp-build/control.tmp"
mkdir -p "${REPO_ROOT}/packages/.tmp-build"

for deb in "${REPO_OUTPUT_DIR}/pool/main/"*.deb; do
    if [[ -f "$deb" ]]; then
        dpkg-deb -I "$deb" control > "$TMP_CTRL" 2>/dev/null || true
        cat "$TMP_CTRL" >> "$PKG_INDEX"
        echo "Filename: pool/main/$(basename "$deb")" >> "$PKG_INDEX"
        echo "Size: $(wc -c < "$deb" | tr -d ' ')" >> "$PKG_INDEX"
        echo "SHA256: $(shasum -a 256 "$deb" | awk '{print $1}')" >> "$PKG_INDEX"
        echo "" >> "$PKG_INDEX"
    fi
done

gzip -9 -c "$PKG_INDEX" > "${PKG_INDEX}.gz"
echo "[PASS] Generated Packages and Packages.gz index."

# Generate InRelease manifest
echo "[2/3] Generating Release manifest..."
RELEASE_FILE="${REPO_OUTPUT_DIR}/dists/resolute-${CHANNEL}/Release"
cat <<EOF > "$RELEASE_FILE"
Origin: GenixBit
Label: GenixBit OS
Suite: resolute-${CHANNEL}
Codename: resolute-${CHANNEL}
Components: main
Architectures: all amd64 arm64
Description: Official GenixBit OS ${CHANNEL} Channel Repository
Date: $(date -u +'%a, %d %b %Y %H:%M:%S UTC')
EOF
echo "[PASS] Generated Release metadata."

# Generate Software Bill of Materials (SBOM)
echo "[3/3] Generating Software Bill of Materials (SBOM)..."
SBOM_FILE="${REPO_OUTPUT_DIR}/genixbit-os-1.1.0-${CHANNEL}-sbom.json"
cat <<EOF > "$SBOM_FILE"
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "metadata": {
    "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
    "component": {
      "type": "operating-system",
      "name": "genixbit-os",
      "version": "1.1.0",
      "channel": "${CHANNEL}"
    }
  },
  "components": [
    { "name": "genixbit-os-base-files", "version": "1.0.0-lts", "type": "library" },
    { "name": "genixbit-os-ai-runtime", "version": "1.0.0-lts", "type": "application" },
    { "name": "genixbit-os-ai-center", "version": "1.0.0-lts", "type": "application" },
    { "name": "genixbit-os-agents", "version": "1.0.0-lts", "type": "application" },
    { "name": "genixbit-os-gpu-diagnostics", "version": "1.0.0-lts", "type": "application" },
    { "name": "genixbit-os-store", "version": "1.0.0-lts", "type": "application" },
    { "name": "genixbit-os-desktop", "version": "1.0.0-lts", "type": "metapackage" },
    { "name": "genixbit-os-theme", "version": "1.0.0-lts", "type": "data" },
    { "name": "genixbit-os-wallpapers", "version": "1.0.0-lts", "type": "data" }
  ]
}
EOF
echo "[PASS] Generated CycloneDX SBOM: ${SBOM_FILE}"

echo "============================================================"
echo "[SUCCESS] Channel '${CHANNEL}' published cleanly."
echo "============================================================"
