#!/usr/bin/env bash
set -Eeuo pipefail


ISO_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --iso requires a path argument." >&2
                exit 1
            fi
            ISO_PATH="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Helper functions
die() {
    echo "[FAIL] $*" >&2
    exit 1
}

log_pass() {
    echo "[PASS] $*"
}

# 1. Read args.sh
if [[ ! -f args.sh ]]; then
    die "args.sh not found at repository root."
fi
TARGET_BUILD_VERSION=$(grep -E '^export TARGET_BUILD_VERSION=' args.sh | cut -d'"' -f2)
if [[ -z "$TARGET_BUILD_VERSION" ]]; then
    die "TARGET_BUILD_VERSION not defined in args.sh."
fi

# 2. Read docs/VALIDATION-STATUS.env
if [[ ! -f docs/VALIDATION-STATUS.env ]]; then
    die "docs/VALIDATION-STATUS.env not found."
fi
VALIDATION_VERSION=$(grep -E '^VALIDATION_VERSION=' docs/VALIDATION-STATUS.env | cut -d'=' -f2)
if [[ -z "$VALIDATION_VERSION" ]]; then
    die "VALIDATION_VERSION not defined in docs/VALIDATION-STATUS.env."
fi

# 3. Read packages/genixbit-os-base-files/usr/lib/os-release
OS_RELEASE="packages/genixbit-os-base-files/usr/lib/os-release"
if [[ ! -f "$OS_RELEASE" ]]; then
    die "$OS_RELEASE not found."
fi
VERSION_ID=$(grep -E '^VERSION_ID=' "$OS_RELEASE" | cut -d'"' -f2)
PRETTY_NAME=$(grep -E '^PRETTY_NAME=' "$OS_RELEASE" | cut -d'"' -f2)

if [[ -z "$VERSION_ID" ]]; then
    die "VERSION_ID not defined in $OS_RELEASE."
fi
if [[ -z "$PRETTY_NAME" ]]; then
    die "PRETTY_NAME not defined in $OS_RELEASE."
fi

# 4. Check Debian package changelogs
# Find all packages in packages/*/debian/changelog
changelogs=(packages/*/debian/changelog)
if [[ ${#changelogs[@]} -eq 0 ]]; then
    die "No package changelogs found in packages/*/debian/changelog."
fi

# 5. Perform validations
# Validation 1: VALIDATION_VERSION equals TARGET_BUILD_VERSION
if [[ "$VALIDATION_VERSION" != "$TARGET_BUILD_VERSION" ]]; then
    die "VALIDATION_VERSION ($VALIDATION_VERSION) in docs/VALIDATION-STATUS.env does not match TARGET_BUILD_VERSION ($TARGET_BUILD_VERSION) in args.sh."
fi

# Validation 2: TARGET_BUILD_VERSION equals VERSION_ID in GenixBit os-release
if [[ "$TARGET_BUILD_VERSION" != "$VERSION_ID" ]]; then
    die "TARGET_BUILD_VERSION ($TARGET_BUILD_VERSION) in args.sh does not match VERSION_ID ($VERSION_ID) in os-release."
fi

# Validation 3: PRETTY_NAME contains the same version
if [[ "$PRETTY_NAME" != *"$TARGET_BUILD_VERSION"* ]]; then
    die "PRETTY_NAME ($PRETTY_NAME) in os-release does not contain target build version ($TARGET_BUILD_VERSION)."
fi

# Validation 4: Branding package versions belong to the intended release cycle
for cl in "${changelogs[@]}"; do
    pkg_dir="$(dirname "$(dirname "$cl")")"
    pkg_name="$(basename "$pkg_dir")"
    if [[ ! -f "$cl" ]]; then
        continue
    fi
    first_line=$(head -n 1 "$cl")
    # Format of first line: pkg-name (version) codename; ...
    pkg_ver=$(echo "$first_line" | awk '{print $2}' | tr -d '()')
    if [[ -z "$pkg_ver" ]]; then
        die "Could not parse version from changelog of $pkg_name: $first_line"
    fi
    if [[ "$pkg_ver" != "$TARGET_BUILD_VERSION"* ]]; then
        die "Package $pkg_name version ($pkg_ver) in changelog does not belong to the intended release cycle ($TARGET_BUILD_VERSION)."
    fi
done

# Validation 5 & 6: ISO path validations if supplied
if [[ -n "$ISO_PATH" ]]; then
    iso_name=$(basename "$ISO_PATH")
    if [[ "$iso_name" != *"$TARGET_BUILD_VERSION"* ]]; then
        die "ISO filename ($iso_name) does not contain the target validation version ($TARGET_BUILD_VERSION)."
    fi
fi

log_pass "Release versions are consistent across args.sh, docs/VALIDATION-STATUS.env, os-release, and branding packages."
exit 0
