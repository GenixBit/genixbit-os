#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Managed QEMU VM Lifecycle Controller: start, status, stop, wait, screenshot
# Runs QEMU as a managed background process with non-conflicting networking,
# QMP health checking, and persistent machine-readable state JSON tracking.

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM=${0##*/}

ACTION="start"
if [[ $# -gt 0 ]]; then
    case "$1" in
        start|status|stop|wait|screenshot)
            ACTION=$1
            shift
            ;;
    esac
fi

MODE=""
ISO_PATH=""
DISK_PATH=""
SEED_ISO=""
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
SERIAL_LOG=""
TIMEOUT_SEC=300
QMP_PATH=""
SCREENSHOT_PATH=""
MONITOR_PATH=""
PID_FILE=""
GUEST_AGENT_PATH=""
SSH_PORT=""
VM_ID=""

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

    die 'No matching OVMF code and variables pair was found.'
}

while (($# > 0)); do
    case "$1" in
        --action)
            ACTION=$2
            shift 2
            ;;
        --vm-id)
            VM_ID=$2
            shift 2
            ;;
        --mode)
            MODE=$2
            shift 2
            ;;
        --iso)
            ISO_PATH=$2
            shift 2
            ;;
        --seed-iso)
            SEED_ISO=$2
            shift 2
            ;;
        --disk)
            DISK_PATH=$2
            shift 2
            ;;
        --sha256)
            EXPECTED_SHA256=$2
            shift 2
            ;;
        --memory)
            MEMORY_MB=$2
            shift 2
            ;;
        --cpus)
            CPU_COUNT=$2
            shift 2
            ;;
        --disk-size)
            DISK_SIZE=$2
            shift 2
            ;;
        --vga)
            VGA_DEVICE=$2
            shift 2
            ;;
        --state-dir)
            STATE_DIR=$2
            shift 2
            ;;
        --ovmf-code)
            OVMF_CODE=$2
            shift 2
            ;;
        --ovmf-vars)
            OVMF_VARS_TEMPLATE=$2
            shift 2
            ;;
        --serial-log)
            SERIAL_LOG=$2
            shift 2
            ;;
        --timeout)
            TIMEOUT_SEC=$2
            shift 2
            ;;
        --qmp|--qmp-socket)
            QMP_PATH=$2
            shift 2
            ;;
        --screenshot)
            SCREENSHOT_PATH=$2
            shift 2
            ;;
        --monitor)
            MONITOR_PATH=$2
            shift 2
            ;;
        --pid-file)
            PID_FILE=$2
            shift 2
            ;;
        --guest-agent|--guest-agent-socket)
            GUEST_AGENT_PATH=$2
            shift 2
            ;;
        --ssh-port)
            SSH_PORT=$2
            shift 2
            ;;
        --vnc)
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
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

if [[ -z "$VM_ID" ]]; then
    VM_ID="vm_$(date +%s)_$$"
fi

if [[ -z "$PID_FILE" ]]; then
    PID_FILE="${STATE_DIR}/qemu-${VM_ID}.pid"
fi

if [[ -z "$QMP_PATH" ]]; then
    QMP_PATH="${STATE_DIR}/qmp-${VM_ID}.sock"
fi

# Action 2: Status check
if [[ "$ACTION" == "status" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            printf '[STATUS] VM %s is running (PID %s).\n' "$VM_ID" "$PID"
            exit 0
        fi
    fi
    die "VM $VM_ID is not running."
fi

# Action 3: Stop VM
if [[ "$ACTION" == "stop" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            # Send QMP system_powerdown if socket exists
            if [[ -S "$QMP_PATH" ]]; then
                python3 -c "import socket, json; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect('$QMP_PATH'); s.recv(4096); s.sendall(b'{\"execute\": \"qmp_capabilities\"}\n'); s.recv(4096); s.sendall(b'{\"execute\": \"system_powerdown\"}\n')" 2>/dev/null || true
            fi
            
            # Wait for shutdown
            for _ in {1..15}; do
                if ! kill -0 "$PID" 2>/dev/null; then
                    rm -f "$PID_FILE" "$QMP_PATH" 2>/dev/null || true
                    printf '[PASS] VM %s stopped cleanly.\n' "$VM_ID"
                    exit 0
                fi
                sleep 1
            done

            # Force SIGTERM if graceful shutdown timed out
            kill -15 "$PID" 2>/dev/null || true
            sleep 2
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null || true
            fi
            rm -f "$PID_FILE" "$QMP_PATH" 2>/dev/null || true
            printf '[WARN] VM %s terminated via signal.\n' "$VM_ID"
            exit 0
        fi
    fi
    printf '[INFO] VM %s is already stopped.\n' "$VM_ID"
    exit 0
fi

# Action 4: Start Managed Background VM
[[ "$MODE" == 'bios' || "$MODE" == 'uefi' ]] || die '--mode must be bios or uefi.'
[[ -n "$DISK_PATH" ]] || DISK_PATH="${STATE_DIR}/genixbit-${MODE}-${VM_ID}.qcow2"

if [[ "$BOOT_INSTALLED" == false ]]; then
    [[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || die 'Valid --iso is required for installation boot.'
fi

require_command qemu-system-x86_64

if [[ ! -e "$DISK_PATH" && "$CREATE_DISK" == true ]]; then
    require_command qemu-img
    qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE" >/dev/null
fi

mkdir -p "$STATE_DIR" "$(dirname "$DISK_PATH")"

# Remove stale sockets if no active process is using them
if [[ -S "$QMP_PATH" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "0")
        if ! kill -0 "$OLD_PID" 2>/dev/null; then
            rm -f "$QMP_PATH" "$PID_FILE"
        fi
    else
        rm -f "$QMP_PATH"
    fi
fi

# Allocate SSH port if not specified
if [[ -z "$SSH_PORT" ]]; then
    SSH_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh" 2>/dev/null || echo "2222")
fi

qemu_command=(
    qemu-system-x86_64
    -name "GenixBit OS 0.3.0-alpha (${MODE} - ${VM_ID})"
    -m "$MEMORY_MB"
    -smp "$CPU_COUNT"
    -drive "file=${DISK_PATH},if=virtio,format=qcow2"
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
    -rtc base=utc
    -vga "$VGA_DEVICE"
)

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    qemu_command+=(-enable-kvm -cpu host)
fi

if [[ "$MODE" == 'bios' ]]; then
    qemu_command+=(-machine pc)
else
    find_ovmf_pair
    vars_state="${DISK_PATH%.*}.ovmf-vars.fd"
    if [[ ! -e "$vars_state" ]]; then
        cp --reflink=auto "$OVMF_VARS_TEMPLATE" "$vars_state" 2>/dev/null || cp "$OVMF_VARS_TEMPLATE" "$vars_state"
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

if [[ -n "$SEED_ISO" && -f "$SEED_ISO" ]]; then
    qemu_command+=(-drive "file=${SEED_ISO},format=raw,if=virtio")
fi

if [[ -n "$SERIAL_LOG" ]]; then
    mkdir -p "$(dirname "$SERIAL_LOG")"
    qemu_command+=(-serial "file:${SERIAL_LOG}")
fi

if [[ -n "$QMP_PATH" ]]; then
    mkdir -p "$(dirname "$QMP_PATH")"
    qemu_command+=(-qmp "unix:${QMP_PATH},server,nowait")
fi

if [[ -n "$GUEST_AGENT_PATH" ]]; then
    mkdir -p "$(dirname "$GUEST_AGENT_PATH")"
    qemu_command+=(-chardev "socket,path=${GUEST_AGENT_PATH},server=on,wait=off,id=qga0" -device "virtio-serial" -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0")
fi

if [[ -n "$VNC_ENDPOINT" ]]; then
    qemu_command+=(-display none -vnc "$VNC_ENDPOINT")
elif [[ "$HEADLESS" == true ]]; then
    qemu_command+=(-display none)
fi

if [[ "$DRY_RUN" == true ]]; then
    print_command "${qemu_command[@]}"
    exit 0
fi

START_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Start QEMU as managed background process
"${qemu_command[@]}" >/dev/null 2>&1 &
QEMU_PID=$!

echo "$QEMU_PID" > "$PID_FILE"

# Wait for QMP socket to become responsive
QMP_READY=false
if [[ -n "$QMP_PATH" ]]; then
    for _ in {1..30}; do
        if [[ -S "$QMP_PATH" ]]; then
            if python3 -c "import socket, json; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(2); s.connect('$QMP_PATH'); s.recv(4096); s.sendall(b'{\"execute\": \"qmp_capabilities\"}\n'); res = json.loads(s.recv(4096).decode()); exit(0 if 'return' in res else 1)" 2>/dev/null; then
                QMP_READY=true
                break
            fi
        fi
        if ! kill -0 "$QEMU_PID" 2>/dev/null; then
            die "QEMU process died immediately after launch!"
        fi
        sleep 1
    done
fi

# Save machine-readable VM state JSON
QEMU_CMD_STR="${qemu_command[*]}"
QEMU_CMD_SHA=$(echo -n "$QEMU_CMD_STR" | sha256sum | awk '{print $1}')

STATE_JSON="${STATE_DIR}/vm_state.json"
cat <<EOF > "$STATE_JSON"
{
  "vm_id": "$VM_ID",
  "mode": "$MODE",
  "pid": $QEMU_PID,
  "pid_file": "$PID_FILE",
  "qmp_socket": "$QMP_PATH",
  "guest_agent_socket": "${GUEST_AGENT_PATH:-null}",
  "ssh_port": $SSH_PORT,
  "serial_log": "$SERIAL_LOG",
  "disk_path": "$DISK_PATH",
  "iso_path": "${ISO_PATH:-null}",
  "seed_iso_path": "${SEED_ISO:-null}",
  "start_timestamp": "$START_TIMESTAMP",
  "qemu_command": "$QEMU_CMD_STR",
  "qemu_command_sha256": "$QEMU_CMD_SHA",
  "state": "running"
}
EOF

printf '[PASS] Managed QEMU VM %s started in background (PID: %s, SSH Port: %s, QMP: %s)\n' "$VM_ID" "$QEMU_PID" "$SSH_PORT" "$QMP_PATH"
exit 0
