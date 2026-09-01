#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
MAKEFILE="$ROOT_DIR/Makefile"
BUILD="$ROOT_DIR/tools/local/build-current.sh"
VM="$ROOT_DIR/tools/local/run-vm.sh"
CLEAN="$ROOT_DIR/tools/local/clean-build.sh"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

for path in "$MAKEFILE" "$BUILD" "$VM" "$CLEAN"; do
    [[ -f "$path" ]] || fail "Missing local developer entry point: $path"
done

bash -n "$BUILD"
bash -n "$VM"
bash -n "$CLEAN"

for target in current vm clean check; do
    grep -Eq "^${target}:" "$MAKEFILE" || fail "Makefile target is missing: $target"
done

# Dry-run the public Make targets. This verifies Makefile parsing and target
# routing without installing packages, building an ISO, launching QEMU, or
# deleting any generated files.
make -C "$ROOT_DIR" -n current >/dev/null
make -C "$ROOT_DIR" -n vm >/dev/null
make -C "$ROOT_DIR" -n clean >/dev/null

# The current-image builder must fail before changing a mismatched host and must
# route the actual build through the canonical build.sh implementation.
grep -q 'TARGET_UBUNTU_VERSION' "$BUILD" || fail 'Build wrapper does not read the configured Ubuntu target.'
grep -q 'HOST_CODENAME' "$BUILD" || fail 'Build wrapper does not validate the host codename.'
grep -q "HOST_ID.*ubuntu" "$BUILD" || fail 'Build wrapper does not require Ubuntu.'
grep -q 'uname -m' "$BUILD" || fail 'Build wrapper does not validate architecture.'
grep -q 'exec bash.*build.sh' "$BUILD" || fail 'Build wrapper does not delegate to canonical build.sh.'

# Cleanup is intentionally bounded. Persistent VM disks are developer state and
# must never be swept by make clean.
grep -q 'safe_repo_path' "$CLEAN" || fail 'Cleanup lacks repository-bound path validation.'
grep -q 'packages/build-debs' "$CLEAN" || fail 'Cleanup does not cover generated package output.'
grep -q 'new_building_os' "$CLEAN" || fail 'Cleanup does not cover generated chroot output.'
grep -q 'Preserved persistent VM state' "$CLEAN" || fail 'Cleanup does not document persistent VM preservation.'
if grep -Eq 'rm[[:space:]].*\.local-artifacts|rm[[:space:]].*genixbit-test\.qcow2' "$CLEAN"; then
    fail 'Cleanup must not remove persistent local VM state.'
fi

# Keep the VM command routed through the existing single implementation rather
# than duplicating QEMU flags in the Makefile.
grep -q 'bash tools/local/run-vm.sh' "$MAKEFILE" || fail 'make vm does not use the canonical local VM runner.'

echo '[PASS] Local developer Makefile/build/VM/cleanup entry-point contract is enforced.'
