#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Boot a GenixBit OS ISO in a persistent local QEMU test VM.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

memory_mb=4096
cpus=4
disk="$ROOT_DIR/.local-artifacts/genixbit-test.qcow2"
disk_size=40G
iso=""

usage() {
    cat <<'EOF'
Usage: tools/local/run-vm.sh [options]

Options:
  --iso PATH        ISO to boot. Defaults to the newest dist/GenixBitOS-*.iso.
  --memory MB       Guest memory in MiB (default: 4096).
  --cpus N          Virtual CPU count (default: 4).
  --disk PATH       Persistent qcow2 disk path.
  --disk-size SIZE  New disk size when the disk does not exist (default: 40G).
  -h, --help        Show this help.

The VM disk is persistent and is never overwritten automatically.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)
            [[ $# -ge 2 ]] || { echo "[ERROR] --iso requires a path." >&2; exit 2; }
            iso="$2"
            shift 2
            ;;
        --memory)
            [[ $# -ge 2 ]] || { echo "[ERROR] --memory requires a value." >&2; exit 2; }
            memory_mb="$2"
            shift 2
            ;;
        --cpus)
            [[ $# -ge 2 ]] || { echo "[ERROR] --cpus requires a value." >&2; exit 2; }
            cpus="$2"
            shift 2
            ;;
        --disk)
            [[ $# -ge 2 ]] || { echo "[ERROR] --disk requires a path." >&2; exit 2; }
            disk="$2"
            shift 2
            ;;
        --disk-size)
            [[ $# -ge 2 ]] || { echo "[ERROR] --disk-size requires a value." >&2; exit 2; }
            disk_size="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$memory_mb" =~ ^[1-9][0-9]*$ ]] || { echo "[ERROR] --memory must be a positive integer." >&2; exit 2; }
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || { echo "[ERROR] --cpus must be a positive integer." >&2; exit 2; }
[[ "$disk_size" =~ ^[1-9][0-9]*[KMGTP]?$ ]] || { echo "[ERROR] --disk-size must look like 40G or 8192M." >&2; exit 2; }

for command_name in qemu-system-x86_64 qemu-img; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "[ERROR] $command_name is required." >&2
        echo "        Ubuntu: sudo apt install qemu-system-x86 qemu-utils" >&2
        echo "        macOS:  brew install qemu" >&2
        exit 1
    fi
done

if [[ -z "$iso" ]]; then
    shopt -s nullglob
    isos=("$ROOT_DIR"/dist/GenixBitOS-*.iso)
    shopt -u nullglob
    if [[ ${#isos[@]} -eq 0 ]]; then
        echo "[ERROR] No GenixBit OS ISO found under $ROOT_DIR/dist/." >&2
        echo "        Build one with 'make current' on the supported Ubuntu build host," >&2
        echo "        or pass an existing image with --iso PATH." >&2
        exit 1
    fi
    iso="${isos[$((${#isos[@]} - 1))]}"
elif [[ "$iso" != /* ]]; then
    iso="$PWD/$iso"
fi

if [[ ! -f "$iso" ]]; then
    echo "[ERROR] ISO not found: $iso" >&2
    exit 1
fi

if [[ "$disk" != /* ]]; then
    disk="$PWD/$disk"
fi
mkdir -p -- "$(dirname -- "$disk")"

if [[ ! -e "$disk" ]]; then
    echo "[VM] Creating persistent test disk: $disk ($disk_size)"
    qemu-img create -f qcow2 "$disk" "$disk_size"
elif [[ ! -f "$disk" ]]; then
    echo "[ERROR] VM disk path exists but is not a regular file: $disk" >&2
    exit 1
fi

accel=tcg
host_os="$(uname -s)"
host_arch="$(uname -m)"
if [[ "$host_os" == Linux && -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    accel=kvm
elif [[ "$host_os" == Darwin && "$host_arch" == x86_64 ]]; then
    accel=hvf
fi

if [[ "$host_os" == Darwin && "$host_arch" == arm64 ]]; then
    echo "[VM] Apple Silicon detected; the current x86_64 ISO will use TCG emulation and may run slowly."
fi

echo "[VM] ISO:    $iso"
echo "[VM] Disk:   $disk"
echo "[VM] CPUs:   $cpus"
echo "[VM] Memory: ${memory_mb} MiB"
echo "[VM] Accel:  $accel"

cmd=(
    qemu-system-x86_64
    -name "GenixBit OS Local Test"
    -machine q35
    -accel "$accel"
    -m "$memory_mb"
    -smp "$cpus"
    -boot "once=d,menu=on"
    -cdrom "$iso"
    -drive "file=$disk,if=virtio,format=qcow2"
    -nic "user,model=e1000e"
)

exec "${cmd[@]}"
