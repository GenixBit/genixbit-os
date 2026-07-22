#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Generate machine-readable JSON release manifest for a package or release build.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat <<'EOF'
Usage: create-release-manifest.sh --package NAME --version VER --output PATH

Options:
  --package NAME  Package name.
  --version VER   Package version.
  --output PATH   Output JSON manifest filepath.
  -h, --help      Show this help.
EOF
}

PACKAGE=""
VERSION=""
OUTPUT=""

while (($# > 0)); do
    case "$1" in
        --package)
            (($# >= 2)) || { echo "Error: --package requires a name." >&2; exit 1; }
            PACKAGE=$2
            shift 2
            ;;
        --version)
            (($# >= 2)) || { echo "Error: --version requires a version." >&2; exit 1; }
            VERSION=$2
            shift 2
            ;;
        --output)
            (($# >= 2)) || { echo "Error: --output requires a path." >&2; exit 1; }
            OUTPUT=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PACKAGE" || -z "$VERSION" || -z "$OUTPUT" ]]; then
    echo "Error: Missing required arguments." >&2
    exit 1
fi

cat <<EOF > "$OUTPUT"
{
  "\$schema": "https://os.genixbit.com/schemas/package-manifest.v1.json",
  "schema_version": "1.0",
  "package": "$PACKAGE",
  "version": "$VERSION",
  "architecture": "amd64",
  "source_repository": "https://github.com/GenixBit/genixbit-os",
  "build_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "license": "GPL-3.0-or-later",
  "builder": "GenixBit OS Maintainers <ftpmaster@genixbit.com>",
  "channel": "resolute-alpha"
}
EOF

echo "[PASS] Created release manifest at: $OUTPUT"
