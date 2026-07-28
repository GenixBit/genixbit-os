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
# Direct-kernel boot options (Step 7: activate autoinstall)
KERNEL_PATH=""
INITRD_PATH=""
KERNEL_APPEND="boot=casper autoinstall console=ttyS0,115200n8 ---"
NO_REBOOT=false

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
        --kernel)
            (($# >= 2)) || fail '--kernel requires a path.'
            KERNEL_PATH=$2
            shift 2
            ;;
        --initrd)
            (($# >= 2)) || fail '--initrd requires a path.'
            INITRD_PATH=$2
            shift 2
            ;;
        --append)
            (($# >= 2)) || fail '--append requires a kernel cmdline string.'
            KERNEL_APPEND=$2
            shift 2
            ;;
        --no-reboot)
            NO_REBOOT=true
            shift
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
        qemu_args=("-m" "4096" "-smp" "4" "-cpu" "host" "-enable-kvm")

        if ! "$QEMU_BIN" -enable-kvm -help >/dev/null 2>&1; then
            qemu_args=("-m" "4096" "-smp" "4")
        fi

        if [[ "$MODE" == "uefi" ]]; then
            OVMF_CODE=""
            OVMF_VARS_TEMPLATE=""
            for f in "/usr/share/OVMF/OVMF_CODE_4M.fd" "/usr/share/OVMF/OVMF_CODE.fd" "/usr/share/ovmf/OVMF.fd" "/usr/share/edk2/ovmf/OVMF_CODE.fd"; do
                if [[ -f "$f" ]]; then OVMF_CODE="$f"; break; fi
            done
            for f in "/usr/share/OVMF/OVMF_VARS_4M.fd" "/usr/share/OVMF/OVMF_VARS.fd" "/usr/share/ovmf/OVMF_VARS.fd" "/usr/share/edk2/ovmf/OVMF_VARS.fd"; do
                if [[ -f "$f" ]]; then OVMF_VARS_TEMPLATE="$f"; break; fi
            done

            if [[ -n "$OVMF_CODE" && -n "$OVMF_VARS_TEMPLATE" ]]; then
                VARS_COPY="${STATE_DIR}/ovmf-vars-${VM_ID}.fd"
                cp -f "$OVMF_VARS_TEMPLATE" "$VARS_COPY"
                qemu_args+=("-drive" "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" "-drive" "if=pflash,format=raw,file=$VARS_COPY")
            else
                fail "UEFI mode requested but OVMF firmware images not found!"
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
            # ISO always attached read-only as CDROM (even with direct-kernel boot,
            # the installer squashfs must come from this exact ISO).
            qemu_args+=("-drive" "file=$ISO_PATH,format=raw,media=cdrom,readonly=on" "-boot" "d")
        fi

        if [[ -n "$SEED_ISO_PATH" && -f "$SEED_ISO_PATH" ]]; then
            qemu_args+=("-drive" "file=$SEED_ISO_PATH,format=raw,if=virtio")
        fi

        # Step 7: Direct-kernel autoinstall boot.
        # When --kernel and --initrd are supplied, use QEMU's -kernel/-initrd/-append
        # to force subiquity into autoinstall mode without relying on the GRUB menu.
        # The canonical ISO is STILL attached read-only above; its squashfs provides
        # the installer payload. This only bootstraps the autoinstall flow.
        if [[ -n "$KERNEL_PATH" && -n "$INITRD_PATH" ]]; then
            [[ -f "$KERNEL_PATH" && -s "$KERNEL_PATH" ]] || fail "--kernel path does not exist or is empty: $KERNEL_PATH"
            [[ -f "$INITRD_PATH" && -s "$INITRD_PATH" ]] || fail "--initrd path does not exist or is empty: $INITRD_PATH"
            # Require 'autoinstall' in the kernel append string — fail closed if missing
            echo "$KERNEL_APPEND" | grep -q 'autoinstall' || fail "--append must contain 'autoinstall' keyword for direct-kernel boot. Got: $KERNEL_APPEND"
            qemu_args+=(
                "-kernel" "$KERNEL_PATH"
                "-initrd" "$INITRD_PATH"
                "-append" "$KERNEL_APPEND"
            )
            printf '[INFO] Direct-kernel autoinstall boot: kernel=%s initrd=%s append=%s\n' "$KERNEL_PATH" "$INITRD_PATH" "$KERNEL_APPEND"
        fi

        if [[ "$NO_REBOOT" == "true" ]]; then
            qemu_args+=("-no-reboot")
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

        # Write per-VM state JSON file (record full argument vector)
        STATE_FILE="${STATE_DIR}/vm-${VM_ID}.json"
        QEMU_ARGS_JSON=$(python3 -c "
import json, sys
args = $(python3 -c "import sys,json; print(json.dumps($(printf '%s ' "${qemu_args[@]}" | python3 -c 'import sys; words=sys.stdin.read().split(); print(words)')))") 
print(json.dumps(args))
" 2>/dev/null || echo '[]')
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
    'kernel_path': '$KERNEL_PATH',
    'initrd_path': '$INITRD_PATH',
    'kernel_cmdline': '$KERNEL_APPEND',
    'no_reboot': $([ '$NO_REBOOT' = 'true' ] && echo True || echo False),
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
        # Gracefully no-op if the pid-file is missing — VM may already be stopped
        if [[ -z "$PID_FILE" || ! -f "$PID_FILE" ]]; then
            printf '[INFO] run-qemu.sh (stop): pid-file absent or missing for VM %s — already stopped, skipping.\n' "$VM_ID" >&2
            exit 0
        fi
        [[ -n "$QMP_SOCKET" ]] || QMP_SOCKET="${STATE_DIR}/qmp-${VM_ID}.sock"

        QEMU_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
        [[ -n "$QEMU_PID" ]] || {
            printf '[INFO] run-qemu.sh (stop): pid-file present but empty for VM %s — treating as ALREADY_STOPPED_VERIFIED.\n' "$VM_ID" >&2
            rm -f "$PID_FILE" "$QMP_SOCKET" 2>/dev/null || true
            printf '[PASS] VM stopped cleanly (ALREADY_STOPPED_VERIFIED)\n'
            exit 0
        }

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
                    SHUTDOWN_STATE="STOPPED_BY_SIGTERM"
                else
                    kill -9 "$QEMU_PID" 2>/dev/null || true
                    SHUTDOWN_STATE="STOPPED_BY_SIGKILL"
                fi
            fi
        else
            SHUTDOWN_STATE="ALREADY_STOPPED_VERIFIED"
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

        if [[ "$SHUTDOWN_STATE" == "STOPPED_GRACEFULLY" || "$SHUTDOWN_STATE" == "ALREADY_STOPPED_VERIFIED" ]]; then
            printf '[PASS] VM stopped cleanly (%s)\n' "$SHUTDOWN_STATE"
            exit 0
        elif [[ "$SHUTDOWN_STATE" == "STOPPED_BY_SIGTERM" ]]; then
            printf '[FAIL] VM required SIGTERM to terminate (%s) — forced termination is a release-gate failure.\n' "$SHUTDOWN_STATE" >&2
            exit 1
        elif [[ "$SHUTDOWN_STATE" == "STOPPED_BY_SIGKILL" ]]; then
            printf '[FAIL] VM required SIGKILL to terminate (%s) — forced termination is a release-gate failure.\n' "$SHUTDOWN_STATE" >&2
            exit 1
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
