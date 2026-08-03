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

QMP_CLIENT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qmp-client.py"

send_qmp_cmd() {
    local socket="$1"
    python3 "$QMP_CLIENT" --socket "$socket" "$2" "${@:3}" 2>/dev/null || true
}

qmp_query_status() {
    local socket_path="$1"
    python3 "$QMP_CLIENT" --socket "$socket_path" --timeout 5 query-status
}

qmp_query_active_status() {
    local socket_path="$1"
    python3 "$QMP_CLIENT" \
        --socket "$socket_path" \
        --timeout 5 \
        query-active-status
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
            qemu_args=("-m" "4096" "-smp" "4" "-accel" "tcg,thread=multi" "-cpu" "max")
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
            qemu_args+=(
                "-device" "qemu-xhci,id=xhci"
                "-drive" "file=$SEED_ISO_PATH,format=raw,id=seeddrive,if=none,readonly=on"
                "-device" "usb-storage,bus=xhci.0,drive=seeddrive"
            )
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
            qemu_args+=("-display" "none")
        fi

        rm -f "$QMP_SOCKET" "$PID_FILE"
        touch "$SERIAL_LOG"

        # Start QEMU as managed background process
        "$QEMU_BIN" "${qemu_args[@]}" >"${STATE_DIR}/qemu-${VM_ID}.stderr" 2>&1 &
        QEMU_PID=$!
        echo "$QEMU_PID" > "$PID_FILE"

        # MANDATORY QMP READINESS VALIDATION
        QMP_READY=false
        qmp_status=""
        qmp_start_time=$(date +%s)
        while true; do
            curr_time=$(date +%s)
            if (((curr_time - qmp_start_time) > 30)); then
                break
            fi

            if kill -0 "$QEMU_PID" 2>/dev/null &&
               [[ -S "$QMP_SOCKET" ]]; then

                qmp_status=$(qmp_query_active_status "$QMP_SOCKET" 2>/dev/null) || qmp_status=""

                case "$qmp_status" in
                    running|prelaunch)
                    QMP_READY=true
                    break
                        ;;
                    *)
                        QMP_READY=false
                        ;;
                esac
            fi
            sleep 1
        done

        if [[ "$QMP_READY" != "true" ]]; then
            kill -9 "$QEMU_PID" 2>/dev/null || true
            rm -f "$PID_FILE" "$QMP_SOCKET"
            fail "QEMU process failed QMP readiness check (VM ID: $VM_ID)!"
        fi

        # Write per-VM state JSON file (record full argument vector via NUL-delimited serialization)
        STATE_FILE="${STATE_DIR}/vm-${VM_ID}.json"
        QEMU_ARGS_FILE="${STATE_DIR}/qemu-${VM_ID}-arguments.json"
        printf '%s\0' "${qemu_args[@]}" | \
        python3 -c '
import json
import sys

raw = sys.stdin.buffer.read().split(b"\0")
args = [item.decode("utf-8", errors="replace") for item in raw if item]
json.dump(args, sys.stdout, indent=2)
' > "$QEMU_ARGS_FILE"
        QEMU_BIN=$(get_qemu_binary)
        NO_REBOOT="$NO_REBOOT" \
        VM_ID="$VM_ID" \
        MODE="$MODE" \
        QEMU_PID="$QEMU_PID" \
        PID_FILE="$PID_FILE" \
        QMP_SOCKET="$QMP_SOCKET" \
        SSH_PORT="$SSH_PORT" \
        SERIAL_LOG="$SERIAL_LOG" \
        DISK_PATH="$DISK_PATH" \
        ISO_PATH="$ISO_PATH" \
        SEED_ISO_PATH="$SEED_ISO_PATH" \
        KERNEL_PATH="$KERNEL_PATH" \
        INITRD_PATH="$INITRD_PATH" \
        KERNEL_APPEND="$KERNEL_APPEND" \
        QEMU_BIN="$QEMU_BIN" \
        QEMU_ARGS_FILE="$QEMU_ARGS_FILE" \
        STATE_FILE="$STATE_FILE" \
        python3 - <<'PYEOF'
import json
import os

def boolean(name: str) -> bool:
    value = os.environ.get(name, "").strip().lower()
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be true or false, got {value!r}")
    return value == "true"

with open(os.environ["QEMU_ARGS_FILE"], "r") as f:
    qemu_args_list = json.load(f)

state = {
    "vm_id": os.environ["VM_ID"],
    "mode": os.environ["MODE"],
    "pid": int(os.environ["QEMU_PID"]),
    "pid_file": os.environ["PID_FILE"],
    "qmp_socket": os.environ["QMP_SOCKET"],
    "ssh_port": int(os.environ["SSH_PORT"]),
    "serial_log": os.environ["SERIAL_LOG"],
    "disk_path": os.environ["DISK_PATH"],
    "iso_path": os.environ["ISO_PATH"],
    "seed_iso_path": os.environ["SEED_ISO_PATH"],
    "kernel_path": os.environ["KERNEL_PATH"],
    "initrd_path": os.environ["INITRD_PATH"],
    "kernel_cmdline": os.environ["KERNEL_APPEND"],
    "no_reboot": boolean("NO_REBOOT"),
    "qemu_binary": os.environ["QEMU_BIN"],
    "source_iso_path": os.environ["ISO_PATH"],
    "target_disk_path": os.environ["DISK_PATH"],
    "firmware_mode": os.environ["MODE"],
    "qemu_arguments": qemu_args_list,
    "start_timestamp": __import__("datetime").datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "state": "running",
    "qmp_ready": True,
}
with open(os.environ["STATE_FILE"], "w") as f:
    json.dump(state, f, indent=2)
PYEOF
        printf '[PASS] Managed QEMU background VM started successfully (VM: %s, PID: %s, Port: %s)\n' "$VM_ID" "$QEMU_PID" "$SSH_PORT"
        ;;

    stop)
        [[ -n "$STATE_DIR" ]] || fail '--state-dir is required for stop when a managed state file exists.'
        if [[ -z "$PID_FILE" || ! -f "$PID_FILE" ]]; then
            SHUTDOWN_STATE="NOT_STARTED"
            VM_ID="$VM_ID" \
            STATE_DIR="$STATE_DIR" \
            SHUTDOWN_STATE="$SHUTDOWN_STATE" \
            python3 - <<'PYEOF'
import json
import os
import datetime

result = {
    "vm_id": os.environ["VM_ID"],
    "pid": 0,
    "requested_action": "stop",
    "shutdown_state": os.environ["SHUTDOWN_STATE"],
    "process_alive_after_stop": False,
    "qmp_socket_present_after_stop": False,
    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": "SKIP",
}
path = os.path.join(os.environ["STATE_DIR"], f"shutdown-{os.environ['VM_ID']}.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)
PYEOF
            printf '[INFO] run-qemu.sh (stop): pid-file absent or missing for VM %s — not started, skipping.\n' "$VM_ID" >&2
            exit 0
        fi
        [[ -n "$QMP_SOCKET" ]] || QMP_SOCKET="${STATE_DIR}/qmp-${VM_ID}.sock"

        QEMU_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -z "$QEMU_PID" ]]; then
            SHUTDOWN_STATE="ALREADY_STOPPED_VERIFIED"
            rm -f "$PID_FILE" 2>/dev/null || true
            if [[ -S "$QMP_SOCKET" ]]; then rm -f "$QMP_SOCKET"; fi
            VM_ID="$VM_ID" \
            STATE_DIR="$STATE_DIR" \
            SHUTDOWN_STATE="$SHUTDOWN_STATE" \
            python3 - <<'PYEOF'
import json
import os
import datetime

result = {
    "vm_id": os.environ["VM_ID"],
    "pid": 0,
    "requested_action": "stop",
    "shutdown_state": os.environ["SHUTDOWN_STATE"],
    "process_alive_after_stop": False,
    "qmp_socket_present_after_stop": False,
    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": "PASS",
}
path = os.path.join(os.environ["STATE_DIR"], f"shutdown-{os.environ['VM_ID']}.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)
PYEOF
            printf '[PASS] VM stopped cleanly (ALREADY_STOPPED_VERIFIED)\n'
            exit 0
        fi

        SHUTDOWN_STATE="STOP_FAILED"
        PROCESS_ALIVE=false
        QMP_PRESENT=false

        ORIGINAL_QEMU_PID="$QEMU_PID"

        if kill -0 "$QEMU_PID" 2>/dev/null; then
            PROCESS_ALIVE=true
            if [[ -S "$QMP_SOCKET" ]]; then
                QMP_PRESENT=true
                python3 "$QMP_CLIENT" --socket "$QMP_SOCKET" system-powerdown >/dev/null 2>&1 || true
            fi

            stop_start=$(date +%s)
            while kill -0 "$QEMU_PID" 2>/dev/null; do
                if (( $(date +%s) - stop_start > 15 )); then
                    break
                fi
                sleep 1
            done

            if ! kill -0 "$QEMU_PID" 2>/dev/null; then
                SHUTDOWN_STATE="NATURAL_EXIT"
                PROCESS_ALIVE=false
            else
                kill -15 "$QEMU_PID" 2>/dev/null || true
                sleep 2
                if ! kill -0 "$QEMU_PID" 2>/dev/null; then
                    SHUTDOWN_STATE="FORCED_SIGTERM"
                    PROCESS_ALIVE=false
                else
                    kill -9 "$QEMU_PID" 2>/dev/null || true
                    sleep 1
                    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
                        SHUTDOWN_STATE="FORCED_SIGKILL"
                        PROCESS_ALIVE=false
                    else
                        SHUTDOWN_STATE="STOP_FAILED"
                        PROCESS_ALIVE=true
                    fi
                fi
            fi
        else
            SHUTDOWN_STATE="ALREADY_STOPPED_VERIFIED"
            PROCESS_ALIVE=false
        fi

        # Verify process directly via original PID (not inferred from PID file)
        PROCESS_ALIVE_AFTER=false
        if [[ -n "$ORIGINAL_QEMU_PID" ]] && kill -0 "$ORIGINAL_QEMU_PID" 2>/dev/null; then
            PROCESS_ALIVE_AFTER=true
        fi

        if [[ "$PROCESS_ALIVE_AFTER" == "true" ]]; then
            SHUTDOWN_STATE="STOP_FAILED"
            PROCESS_ALIVE=true
            # Preserve PID file as evidence when STOP_FAILED
        else
            rm -f "$PID_FILE" 2>/dev/null || true
        fi

        # Remove QMP socket, then verify it is gone
        rm -f "$QMP_SOCKET" 2>/dev/null || true
        QMP_PRESENT_AFTER=false
        if [[ -S "$QMP_SOCKET" ]]; then
            QMP_PRESENT_AFTER=true
        fi

        SHUTDOWN_STATUS="PASS"
        if [[ "$SHUTDOWN_STATE" == "FORCED_SIGTERM" || "$SHUTDOWN_STATE" == "FORCED_SIGKILL" || "$SHUTDOWN_STATE" == "STOP_FAILED" ]]; then
            SHUTDOWN_STATUS="FAIL"
        fi

        VM_ID="$VM_ID" \
        STATE_DIR="$STATE_DIR" \
        QEMU_PID="$QEMU_PID" \
        SHUTDOWN_STATE="$SHUTDOWN_STATE" \
        PROCESS_ALIVE="$PROCESS_ALIVE" \
        QMP_PRESENT_AFTER="$QMP_PRESENT_AFTER" \
        SHUTDOWN_STATUS="$SHUTDOWN_STATUS" \
        python3 - <<'PYEOF'
import json
import os
import datetime

def boolean(name: str) -> bool:
    value = os.environ.get(name, "").strip().lower()
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be true or false, got {value!r}")
    return value == "true"

result = {
    "vm_id": os.environ["VM_ID"],
    "pid": int(os.environ["QEMU_PID"]),
    "requested_action": "stop",
    "shutdown_state": os.environ["SHUTDOWN_STATE"],
    "process_alive_after_stop": boolean("PROCESS_ALIVE"),
    "qmp_socket_present_after_stop": boolean("QMP_PRESENT_AFTER"),
    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": os.environ["SHUTDOWN_STATUS"],
}
path = os.path.join(os.environ["STATE_DIR"], f"shutdown-{os.environ['VM_ID']}.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)
PYEOF

        # State JSON update (set state to actual result, never running)
        if [[ -n "$VM_ID" && -n "$STATE_DIR" ]]; then
            state_file_path="${STATE_DIR}/vm-${VM_ID}.json"
            if [[ -f "$state_file_path" ]]; then
                STATE_FILE_PATH="$state_file_path" \
                SHUTDOWN_STATE="$SHUTDOWN_STATE" \
                SHUTDOWN_STATUS="$SHUTDOWN_STATUS" \
                python3 - <<'PYEOF'
import json
import os

path = os.environ["STATE_FILE_PATH"]
with open(path, "r") as f:
    data = json.load(f)
data["state"] = os.environ["SHUTDOWN_STATE"]
data["shutdown_status"] = os.environ["SHUTDOWN_STATUS"]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
            fi
        fi

        # Before returning PASS, require process and QMP socket are both gone
        if [[ "$SHUTDOWN_STATUS" == "PASS" ]]; then
            if [[ "$PROCESS_ALIVE" == "true" ]]; then
                fail "Shutdown recorded PASS but process is still alive!"
            fi
            if [[ "$QMP_PRESENT_AFTER" == "true" ]]; then
                fail "Shutdown recorded PASS but QMP socket is still present!"
            fi
        fi

        if [[ "$SHUTDOWN_STATE" == "NATURAL_EXIT" || "$SHUTDOWN_STATE" == "ALREADY_STOPPED_VERIFIED" ]]; then
            printf '[PASS] VM stopped cleanly (%s)\n' "$SHUTDOWN_STATE"
            exit 0
        elif [[ "$SHUTDOWN_STATE" == "FORCED_SIGTERM" ]]; then
            printf '[FAIL] VM required SIGTERM to terminate (%s) — forced termination is a release-gate failure.\n' "$SHUTDOWN_STATE" >&2
            exit 1
        elif [[ "$SHUTDOWN_STATE" == "FORCED_SIGKILL" ]]; then
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
        python3 "$QMP_CLIENT" --socket "$QMP_SOCKET" --file "$OUT_FILE" screendump >/dev/null 2>&1 || true
        [[ -f "$OUT_FILE" && -s "$OUT_FILE" ]] || fail "Screenshot capture failed to create non-empty file at $OUT_FILE"
        printf '[PASS] Screenshot captured to %s\n' "$OUT_FILE"
        ;;

    *)
        fail "Unknown action: $ACTION"
        ;;
esac
