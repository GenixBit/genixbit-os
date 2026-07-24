#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}
MODE=""
ISO_PATH=""
DISK_PATH=""
EXPECTED_SHA256=""
MEMORY_MB=8192
CPU_COUNT=4
DISK_SIZE="40G"
CREATE_DISK=false
BOOT_INSTALLED=false
DRY_RUN=false
HEADLESS=false
VNC_ENDPOINT=""
VGA_DEVICE="std"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/genixbit-os-vm"
OVMF_CODE=""
OVMF_VARS_TEMPLATE=""

usage() {
    cat <<EOF
Usage:
  ${PROGRAM} --mode bios|uefi --iso PATH [options]
  ${PROGRAM} --mode bios|uefi --installed --disk PATH [options]

Required:
  --mode MODE              Firmware mode: bios or uefi.
  --iso PATH               ISO to boot. Required unless --installed is used.

Disk options:
  --disk PATH              QCOW2 disk path. Defaults outside the repository.
  --create-disk            Create the disk when it does not exist.
  --disk-size SIZE         New disk size. Default: ${DISK_SIZE}.
  --installed              Boot from the virtual disk without attaching the ISO.

Validation options:
  --sha256 DIGEST          Require the ISO to match this SHA-256 digest.
  --memory MB              Guest memory in MiB. Default: ${MEMORY_MB}.
  --cpus COUNT             Guest virtual CPU count. Default: ${CPU_COUNT}.
  --vga DEVICE             QEMU VGA type. Default: ${VGA_DEVICE}.
  --headless               Use -nographic for console-only diagnostics.
  --vnc ENDPOINT           Use loopback-only VNC, for example 127.0.0.1:1.
  --state-dir PATH         Persistent VM state directory.
  --ovmf-code PATH         Override the UEFI OVMF code image.
  --ovmf-vars PATH         Override the matching OVMF variables template.
  --dry-run                Print commands without creating files or starting QEMU.
  -h, --help               Show this help.

Examples:
  ${PROGRAM} --mode bios --iso /srv/private/GenixBitOS.iso \
    --sha256 <digest> --create-disk

  ${PROGRAM} --mode uefi --iso /srv/private/GenixBitOS.iso \
    --sha256 <digest> --create-disk

  ${PROGRAM} --mode uefi --installed \
    --disk ~/.local/state/genixbit-os-vm/genixbit-uefi.qcow2
EOF
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

print_command() {
    printf '[COMMAND] '
    printf '%q ' "$@"
    printf '\n'
}

find_ovmf_pair() {
    local pair code vars
    local -a candidates=(
        '/usr/share/OVMF/OVMF_CODE_4M.fd|/usr/share/OVMF/OVMF_VARS_4M.fd'
        '/usr/share/OVMF/OVMF_CODE.fd|/usr/share/OVMF/OVMF_VARS.fd'
        '/usr/share/edk2/ovmf/OVMF_CODE.fd|/usr/share/edk2/ovmf/OVMF_VARS.fd'
        '/usr/share/qemu/OVMF_CODE.fd|/usr/share/qemu/OVMF_VARS.fd'
    )

    for pair in "${candidates[@]}"; do
        IFS='|' read -r code vars <<<"$pair"
        if [[ -r "$code" && -r "$vars" ]]; then
            OVMF_CODE=$code
            OVMF_VARS_TEMPLATE=$vars
            return 0
        fi
    done

    if [[ "$DRY_RUN" == true ]]; then
        OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
        OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"
        return 0
    fi

    die 'No matching OVMF code and variables pair was found. Install the ovmf package or pass --ovmf-code and --ovmf-vars.'
}

while (($# > 0)); do
    case "$1" in
        --mode)
            (($# >= 2)) || die '--mode requires a value.'
            MODE=$2
            shift 2
            ;;
        --iso)
            (($# >= 2)) || die '--iso requires a path.'
            ISO_PATH=$2
            shift 2
            ;;
        --disk)
            (($# >= 2)) || die '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --sha256)
            (($# >= 2)) || die '--sha256 requires a digest.'
            EXPECTED_SHA256=$2
            shift 2
            ;;
        --memory)
            (($# >= 2)) || die '--memory requires a value.'
            MEMORY_MB=$2
            shift 2
            ;;
        --cpus)
            (($# >= 2)) || die '--cpus requires a value.'
            CPU_COUNT=$2
            shift 2
            ;;
        --disk-size)
            (($# >= 2)) || die '--disk-size requires a value.'
            DISK_SIZE=$2
            shift 2
            ;;
        --vga)
            (($# >= 2)) || die '--vga requires a value.'
            VGA_DEVICE=$2
            shift 2
            ;;
        --state-dir)
            (($# >= 2)) || die '--state-dir requires a path.'
            STATE_DIR=$2
            shift 2
            ;;
        --ovmf-code)
            (($# >= 2)) || die '--ovmf-code requires a path.'
            OVMF_CODE=$2
            shift 2
            ;;
        --ovmf-vars)
            (($# >= 2)) || die '--ovmf-vars requires a path.'
            OVMF_VARS_TEMPLATE=$2
            shift 2
            ;;
        --vnc)
            (($# >= 2)) || die '--vnc requires an endpoint.'
            VNC_ENDPOINT=$2
            shift 2
            ;;
        --create-disk)
            CREATE_DISK=true
            shift
            ;;
        --installed)
            BOOT_INSTALLED=true
            shift
            ;;
        --headless)
            HEADLESS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ "$MODE" == 'bios' || "$MODE" == 'uefi' ]] || die '--mode must be bios or uefi.'
[[ "$MEMORY_MB" =~ ^[0-9]+$ ]] || die '--memory must be an integer number of MiB.'
[[ "$CPU_COUNT" =~ ^[0-9]+$ ]] || die '--cpus must be an integer.'
((MEMORY_MB >= 2048)) || die 'At least 2048 MiB of guest memory is required.'
((CPU_COUNT >= 1)) || die 'At least one virtual CPU is required.'

if [[ -n "$VNC_ENDPOINT" ]]; then
    [[ "$HEADLESS" == false ]] || die '--vnc and --headless cannot be used together.'
    case "$VNC_ENDPOINT" in
        127.0.0.1:*|localhost:*) ;;
        *) die '--vnc must bind to loopback, for example 127.0.0.1:1. Use an SSH tunnel for remote access.' ;;
    esac
fi

if [[ "$BOOT_INSTALLED" == false ]]; then
    [[ -n "$ISO_PATH" ]] || die '--iso is required unless --installed is used.'
    if [[ "$DRY_RUN" == false ]]; then
        [[ -f "$ISO_PATH" ]] || die "ISO file not found: $ISO_PATH"
    fi
else
    [[ -z "$ISO_PATH" ]] || die 'Do not pass --iso together with --installed.'
fi

require_command qemu-system-x86_64

if [[ "$BOOT_INSTALLED" == false && -n "$EXPECTED_SHA256" ]]; then
    require_command sha256sum
    [[ "$EXPECTED_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || die '--sha256 must contain exactly 64 hexadecimal characters.'
    if [[ "$DRY_RUN" == false ]]; then
        actual_sha256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
        if [[ "${actual_sha256,,}" != "${EXPECTED_SHA256,,}" ]]; then
            die "ISO checksum mismatch. Expected ${EXPECTED_SHA256}; received ${actual_sha256}."
        fi
        printf '[PASS] ISO SHA-256 matched: %s\n' "$actual_sha256"
    else
        printf '[INFO] ISO SHA-256 validation skipped in dry-run mode.\n'
    fi
fi

mkdir_command=(mkdir -p "$STATE_DIR")
if [[ "$DRY_RUN" == true ]]; then
    print_command "${mkdir_command[@]}"
else
    "${mkdir_command[@]}"
fi

if [[ -z "$DISK_PATH" ]]; then
    DISK_PATH="${STATE_DIR}/genixbit-${MODE}.qcow2"
fi

if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$DISK_PATH")"
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$repo_root" ]]; then
    disk_parent=$(cd "$(dirname "$DISK_PATH")" 2>/dev/null && pwd -P || true)
    if [[ -n "$disk_parent" ]]; then
        disk_absolute="${disk_parent}/$(basename "$DISK_PATH")"
        case "$disk_absolute" in
            "$repo_root"/*) die 'VM disks must be stored outside the Git repository.' ;;
        esac
    fi
fi

if [[ ! -e "$DISK_PATH" ]]; then
    [[ "$CREATE_DISK" == true ]] || die "Virtual disk does not exist: $DISK_PATH. Pass --create-disk to create it."
    require_command qemu-img
    create_disk_command=(qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE")
    if [[ "$DRY_RUN" == true ]]; then
        print_command "${create_disk_command[@]}"
    else
        "${create_disk_command[@]}"
    fi
else
    [[ -f "$DISK_PATH" ]] || die "Disk path is not a regular file: $DISK_PATH"
fi

qemu_command=(
    qemu-system-x86_64
    -name "GenixBit OS 0.1.0-alpha (${MODE})"
    -m "$MEMORY_MB"
    -smp "$CPU_COUNT"
    -drive "file=${DISK_PATH},if=virtio,format=qcow2"
    -nic "user,model=virtio-net-pci"
    -rtc base=utc
    -vga "$VGA_DEVICE"
)

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    qemu_command+=(-enable-kvm -cpu host)
    printf '[INFO] KVM acceleration enabled.\n'
else
    printf '[WARN] /dev/kvm is unavailable; QEMU will use software emulation.\n' >&2
fi

if [[ "$MODE" == 'bios' ]]; then
    qemu_command+=(-machine pc)
else
    if [[ -n "$OVMF_CODE" || -n "$OVMF_VARS_TEMPLATE" ]]; then
        [[ -n "$OVMF_CODE" && -n "$OVMF_VARS_TEMPLATE" ]] || die 'Pass both --ovmf-code and --ovmf-vars when overriding OVMF.'
        [[ -r "$OVMF_CODE" ]] || die "OVMF code image is not readable: $OVMF_CODE"
        [[ -r "$OVMF_VARS_TEMPLATE" ]] || die "OVMF variables template is not readable: $OVMF_VARS_TEMPLATE"
    else
        find_ovmf_pair
    fi

    vars_state="${DISK_PATH%.*}.ovmf-vars.fd"
    if [[ ! -e "$vars_state" ]]; then
        copy_vars_command=(cp --reflink=auto "$OVMF_VARS_TEMPLATE" "$vars_state")
        if [[ "$DRY_RUN" == true ]]; then
            print_command "${copy_vars_command[@]}"
        else
            "${copy_vars_command[@]}"
        fi
    fi

    qemu_command+=(
        -machine q35
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}"
        -drive "if=pflash,format=raw,unit=1,file=${vars_state}"
    )
fi

if [[ "$BOOT_INSTALLED" == true ]]; then
    qemu_command+=(-boot "order=c,menu=on")
else
    qemu_command+=(-cdrom "$ISO_PATH" -boot "order=d,menu=on")
fi


if [[ -n "$VNC_ENDPOINT" ]]; then
    qemu_command+=(-display none -vnc "$VNC_ENDPOINT")
elif [[ "$HEADLESS" == true ]]; then
    printf '[WARN] Headless mode cannot prove that the graphical live desktop or installer works.\n' >&2
    qemu_command+=(-nographic)
fi

printf '[INFO] Firmware mode: %s\n' "$MODE"
printf '[INFO] Virtual disk: %s\n' "$DISK_PATH"
printf '[INFO] Boot target: %s\n' "$([[ "$BOOT_INSTALLED" == true ]] && printf 'installed disk' || printf 'ISO')"
print_command "${qemu_command[@]}"

if [[ "$DRY_RUN" == true ]]; then
    exit 0
fi

exec "${qemu_command[@]}"
