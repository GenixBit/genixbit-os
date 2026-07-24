#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Managed QEMU virtual machine lifecycle controller with mandatory QMP readiness, per-VM state JSON, and fail-closed shutdown procedures.

set -Eeuo pipefail
IFS=$'\n\t'

ACTION="${1:-}"
shift || true

VM_ID=""
MODE="uefi"
ISO_PATH=""
SEED_ISO_PATH=""
DISK_PATH=""
STATE_DIR=""
SERIAL_LOG=""
QMP_SOCKET=""
PID_FILE=""
SSH_PORT=""
HEADLESS=true
TIMEOUT_SEC=600
INSTALLED=false

fail() {
    printf '[FAIL] run-qemu.sh (%s): %s\n' "${ACTION:-unknown}" "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --vm-id)
            (($# >= 2)) || fail '--vm-id requires a value.'
            VM_ID=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
            shift 2
            ;;
        --iso)
            (($# >= 2)) || fail '--iso requires a path.'
            ISO_PATH=$2
            shift 2
            ;;
        --seed-iso)
            (($# >= 2)) || fail '--seed-iso requires a path.'
            SEED_ISO_PATH=$2
            shift 2
            ;;
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --state-dir)
            (($# >= 2)) || fail '--state-dir requires a path.'
            STATE_DIR=$2
            shift 2
            ;;
        --serial-log)
            (($# >= 2)) || fail '--serial-log requires a path.'
            SERIAL_LOG=$2
            shift 2
            ;;
        --qmp-socket)
            (($# >= 2)) || fail '--qmp-socket requires a path.'
            QMP_SOCKET=$2
            shift 2
            ;;
        --pid-file)
            (($# >= 2)) || fail '--pid-file requires a path.'
            PID_FILE=$2
            shift 2
            ;;
        --ssh-port)
            (($# >= 2)) || fail '--ssh-port requires a port.'
            SSH_PORT=$2
            shift 2
            ;;
        --headless)
            HEADLESS=true
            shift
            ;;
        --installed)
            INSTALLED=true
            shift
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$ACTION" ]] || fail "Usage: run-qemu.sh <start|status|stop|wait|screenshot> [options]"

get_qemu_binary() {
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo "qemu-system-x86_64"
    elif command -v qemu-kvm >/dev/null 2>&1; then
        echo "qemu-kvm"
    else
        fail "QEMU executable (qemu-system-x86_64) not found."
    fi
}

send_qmp_cmd() {
    local socket="$1"
    local cmd="$2"
    python3 -c "
import socket, sys, json
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('$socket')
greeting = s.recv(4096)
s.sendall(json.dumps({'execute': 'qmp_capabilities'}).encode() + b'\n')
resp1 = s.recv(4096)
s.sendall(json.dumps($cmd).encode() + b'\n')
resp2 = s.recv(4096)
s.close()
sys.stdout.write(resp2.decode())
"
}

case "$ACTION" in
    start)
        [[ -n "$VM_ID" ]] || fail '--vm-id is required for start.'
        [[ -n "$DISK_PATH" ]] || fail '--disk is required for start.'
        [[ -n "$STATE_DIR" ]] || fail '--state-dir is required for start.'

        mkdir -p "$STATE_DIR"
        [[ -n "$SERIAL_LOG" ]] || SERIAL_LOG="${STATE_DIR}/serial-${VM_ID}.log"
        [[ -n "$QMP_SOCKET" ]] || QMP_SOCKET="${STATE_DIR}/qmp-${VM_ID}.sock"
        [[ -n "$PID_FILE" ]] || PID_FILE="${STATE_DIR}/qemu-${VM_ID}.pid"

        # Allocate unique loopback port (FAIL CLOSED - NO 2222 fallback!)
        if [[ -z "$SSH_PORT" ]]; then
            SSH_PORT=$(bash "$(dirname "$0")/allocate-local-port.sh")
        fi

        QEMU_BIN=$(get_qemu_binary)
        qemu_args=("-m" "4096" "-smp" "2" "-enable-kvm")

        if ! "$QEMU_BIN" -enable-kvm -help >/dev/null 2>&1; then
            qemu_args=("-m" "4096" "-smp" "2")
        fi

        if [[ "$MODE" == "uefi" ]]; then
            OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
            OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS.fd"
            VARS_COPY="${STATE_DIR}/ovmf-vars-${VM_ID}.fd"

            if [[ -f "$OVMF_CODE" && -f "$OVMF_VARS_TEMPLATE" ]]; then
                cp -f "$OVMF_VARS_TEMPLATE" "$VARS_COPY"
                qemu_args+=("-drive" "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" "-drive" "if=pflash,format=raw,file=$VARS_COPY")
            fi
        fi

        # Explicit virtio-net-pci and netdev pairing (NO -nic user fallback!)
        qemu_args+=(
            "-drive" "file=$DISK_PATH,format=qcow2,if=virtio"
            "-netdev" "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
            "-device" "virtio-net-pci,netdev=net0"
            "-serial" "file:$SERIAL_LOG"
            "-qmp" "unix:$QMP_SOCKET,server,nowait"
            "-pidfile" "$PID_FILE"
        )

        if [[ "$INSTALLED" == "false" && -n "$ISO_PATH" ]]; then
            qemu_args+=("-cdrom" "$ISO_PATH" "-boot" "d")
        fi

        if [[ -n "$SEED_ISO_PATH" && -f "$SEED_ISO_PATH" ]]; then
            qemu_args+=("-drive" "file=$SEED_ISO_PATH,format=raw,if=virtio")
        fi

        if [[ "$HEADLESS" == "true" ]]; then
            qemu_args+=("-nographic" "-display" "none")
        fi

        rm -f "$QMP_SOCKET" "$PID_FILE"
        touch "$SERIAL_LOG"

        # Start QEMU as managed background process
        "$QEMU_BIN" "${qemu_args[@]}" >"${STATE_DIR}/qemu-${VM_ID}.stderr" 2>&1 &
        QEMU_PID=$!
        echo "$QEMU_PID" > "$PID_FILE"

        # MANDATORY QMP READINESS VALIDATION
        QMP_READY=false
        qmp_start_time=$(date +%s)
        while true; do
            curr_time=$(date +%s)
            if (((curr_time - qmp_start_time) > 30)); then
                break
            fi

            if kill -0 "$QEMU_PID" 2>/dev/null && [[ -S "$QMP_SOCKET" ]]; then
                qmp_status=$(send_qmp_cmd "$QMP_SOCKET" '{"execute": "query-status"}' 2>/dev/null || echo "")
                if echo "$qmp_status" | grep -E '"status": "(running|prelaunch)"' >/dev/null 2>&1; then
                    QMP_READY=true
                    break
                fi
            fi
            sleep 1
        done

        if [[ "$QMP_READY" != "true" ]]; then
            kill -9 "$QEMU_PID" 2>/dev/null || true
            rm -f "$PID_FILE" "$QMP_SOCKET"
            fail "QEMU process failed QMP readiness check (VM ID: $VM_ID)!"
        fi

        # Write per-VM state JSON file
        STATE_FILE="${STATE_DIR}/vm-${VM_ID}.json"
        python3 -c "
import json, time
state = {
    'vm_id': '$VM_ID',
    'mode': '$MODE',
    'pid': $QEMU_PID,
    'pid_file': '$PID_FILE',
    'qmp_socket': '$QMP_SOCKET',
    'ssh_port': $SSH_PORT,
    'serial_log': '$SERIAL_LOG',
    'disk_path': '$DISK_PATH',
    'iso_path': '$ISO_PATH',
    'seed_iso_path': '$SEED_ISO_PATH',
    'start_timestamp': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")',
    'state': 'running',
    'qmp_ready': True
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"
        printf '[PASS] Managed QEMU background VM started successfully (VM: %s, PID: %s, Port: %s)\n' "$VM_ID" "$QEMU_PID" "$SSH_PORT"
        ;;

    stop)
        [[ -n "$PID_FILE" && -f "$PID_FILE" ]] || fail '--pid-file is required for stop.'
        [[ -n "$QMP_SOCKET" ]] || QMP_SOCKET="${STATE_DIR}/qmp-${VM_ID}.sock"

        QEMU_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
        [[ -n "$QEMU_PID" ]] || fail "PID file $PID_FILE is empty."

        SHUTDOWN_STATE="STOP_FAILED"

        if kill -0 "$QEMU_PID" 2>/dev/null; then
            if [[ -S "$QMP_SOCKET" ]]; then
                send_qmp_cmd "$QMP_SOCKET" '{"execute": "system_powerdown"}' >/dev/null 2>&1 || true
            fi

            # Wait up to 15 seconds for graceful shutdown
            stop_start=$(date +%s)
            while kill -0 "$QEMU_PID" 2>/dev/null; do
                if (( $(date +%s) - stop_start > 15 )); then
                    break
                fi
                sleep 1
            done

            if ! kill -0 "$QEMU_PID" 2>/dev/null; then
                SHUTDOWN_STATE="STOPPED_GRACEFULLY"
            else
                kill -15 "$QEMU_PID" 2>/dev/null || true
                sleep 2
                if ! kill -0 "$QEMU_PID" 2>/dev/null; then
                    SHUTDOWN_STATE="STOPPED_BY_SIGTERM_CLEANUP"
                else
                    kill -9 "$QEMU_PID" 2>/dev/null || true
                    SHUTDOWN_STATE="STOPPED_BY_SIGKILL_CLEANUP"
                fi
            fi
        else
            SHUTDOWN_STATE="ALREADY_STOPPED"
        fi

        rm -f "$PID_FILE" "$QMP_SOCKET"

        # State JSON update
        if [[ -n "$VM_ID" && -n "$STATE_DIR" && -f "${STATE_DIR}/vm-${VM_ID}.json" ]]; then
            python3 -c "
import json
p = '${STATE_DIR}/vm-${VM_ID}.json'
with open(p, 'r') as f: data = json.load(f)
data['state'] = '$SHUTDOWN_STATE'
with open(p, 'w') as f: json.dump(data, f, indent=2)
"
        fi

        if [[ "$SHUTDOWN_STATE" == "STOPPED_GRACEFULLY" || "$SHUTDOWN_STATE" == "ALREADY_STOPPED" ]]; then
            printf '[PASS] VM stopped cleanly (%s)\n' "$SHUTDOWN_STATE"
            exit 0
        else
            fail "VM shutdown required forced cleanup or failed ($SHUTDOWN_STATE)!"
        fi
        ;;

    status)
        [[ -n "$PID_FILE" && -f "$PID_FILE" ]] || fail '--pid-file is required for status.'
        QEMU_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if kill -0 "$QEMU_PID" 2>/dev/null; then
            printf 'RUNNING (PID: %s)\n' "$QEMU_PID"
        else
            printf 'STOPPED\n'
        fi
        ;;

    screenshot)
        [[ -n "$QMP_SOCKET" && -S "$QMP_SOCKET" ]] || fail 'Valid QMP socket required for screenshot.'
        OUT_FILE="${1:-screenshot.ppm}"
        send_qmp_cmd "$QMP_SOCKET" "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"$OUT_FILE\"}}" >/dev/null 2>&1
        [[ -f "$OUT_FILE" && -s "$OUT_FILE" ]] || fail "Screenshot capture failed to create non-empty file at $OUT_FILE"
        printf '[PASS] Screenshot captured to %s\n' "$OUT_FILE"
        ;;

    *)
        fail "Unknown action: $ACTION"
        ;;
esac
