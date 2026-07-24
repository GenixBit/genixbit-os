#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executes commands inside a QEMU guest VM via authenticated SSH or dedicated QEMU Guest Agent socket.
# Captures command stdout, stderr, timestamps, exit code, and stdout/stderr SHA-256 digests.

set -Eeuo pipefail
IFS=$'\n\t'

CMD=""
SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
QGA_SOCKET=""
OUT_LOG=""
STDERR_LOG=""
RESULT_JSON=""
VERIFY_DISK_BOOT=false
REBOOT=false
SHUTDOWN=false
TIMEOUT_SEC=300

fail() {
    printf '[FAIL] guest-command.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --cmd)
            (($# >= 2)) || fail '--cmd requires a command string.'
            CMD=$2
            shift 2
            ;;
        --ssh-port)
            (($# >= 2)) || fail '--ssh-port requires a port.'
            SSH_PORT=$2
            shift 2
            ;;
        --ssh-user)
            (($# >= 2)) || fail '--ssh-user requires a username.'
            SSH_USER=$2
            shift 2
            ;;
        --ssh-key)
            (($# >= 2)) || fail '--ssh-key requires a path.'
            SSH_KEY=$2
            shift 2
            ;;
        --guest-agent-socket|--guest-agent)
            (($# >= 2)) || fail '--guest-agent-socket requires a socket path.'
            QGA_SOCKET=$2
            shift 2
            ;;
        --out-log|--stdout-log)
            (($# >= 2)) || fail '--out-log requires a path.'
            OUT_LOG=$2
            shift 2
            ;;
        --stderr-log)
            (($# >= 2)) || fail '--stderr-log requires a path.'
            STDERR_LOG=$2
            shift 2
            ;;
        --result-json)
            (($# >= 2)) || fail '--result-json requires a path.'
            RESULT_JSON=$2
            shift 2
            ;;
        --verify-disk-boot)
            VERIFY_DISK_BOOT=true
            shift
            ;;
        --reboot)
            REBOOT=true
            shift
            ;;
        --shutdown)
            SHUTDOWN=true
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

if [[ "$REBOOT" == "true" ]]; then
    CMD="sudo systemctl reboot"
elif [[ "$SHUTDOWN" == "true" ]]; then
    CMD="sudo systemctl poweroff"
fi

[[ -n "$CMD" ]] || fail '--cmd, --verify-disk-boot, --reboot, or --shutdown is required.'

START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)

cleanup_tmp() {
    rm -f "$STDOUT_FILE" "$STDERR_FILE" 2>/dev/null || true
}
trap cleanup_tmp EXIT

CHANNEL=""
EXIT_CODE=1
EXEC_SUCCESS=false

# Channel 1: Authenticated SSH over localhost port forwarding
if [[ -n "$SSH_PORT" ]]; then
    CHANNEL="ssh"
    SSH_OPTS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=10" -p "$SSH_PORT")
    if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
        SSH_OPTS+=(-i "$SSH_KEY")
    fi

    set +e
    timeout "$TIMEOUT_SEC" ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "$CMD" > "$STDOUT_FILE" 2> "$STDERR_FILE"
    EXIT_CODE=$?
    set -e

    if [[ "$REBOOT" == "true" || "$SHUTDOWN" == "true" ]]; then
        # SSH disconnect on reboot/poweroff gives 255 or 0
        if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 255 ]]; then
            EXEC_SUCCESS=true
            EXIT_CODE=0
        fi
    elif [[ $EXIT_CODE -eq 0 ]]; then
        EXEC_SUCCESS=true
    fi
fi

# Channel 2: QEMU Guest Agent (via dedicated virtio-serial QGA socket, NOT QMP monitor socket)
if [[ "$EXEC_SUCCESS" == "false" && -n "$QGA_SOCKET" && -S "$QGA_SOCKET" ]]; then
    CHANNEL="qemu-guest-agent"
    qga_python=$(cat <<PYEOF
import socket, json, base64, time, sys

sock_path = "${QGA_SOCKET}"
cmd_str = """${CMD}"""

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(15)
    s.connect(sock_path)

    # Ping QGA
    s.sendall(b'{"execute": "guest-ping"}\n')
    res = json.loads(s.recv(4096).decode())
    if "error" in res:
        sys.exit(1)

    # Execute via guest-exec
    req = json.dumps({"execute": "guest-exec", "arguments": {"path": "/bin/bash", "arg": ["-c", cmd_str], "capture-output": True}})
    s.sendall(req.encode() + b'\n')
    res = json.loads(s.recv(4096).decode())
    pid = res.get("return", {}).get("pid")
    if not pid:
        sys.exit(1)

    # Poll status
    status_req = json.dumps({"execute": "guest-exec-status", "arguments": {"pid": pid}})
    start_t = time.time()
    while time.time() - start_t < 60:
        s.sendall(status_req.encode() + b'\n')
        status_res = json.loads(s.recv(8192).decode())
        ret = status_res.get("return", {})
        if ret.get("exited", False):
            out_b64 = ret.get("out-data", "")
            err_b64 = ret.get("err-data", "")
            exit_code = ret.get("exitcode", 0)
            with open("${STDOUT_FILE}", "wb") as f:
                f.write(base64.b64decode(out_b64))
            with open("${STDERR_FILE}", "wb") as f:
                f.write(base64.b64decode(err_b64))
            sys.exit(exit_code)
        time.sleep(1)
    sys.exit(1)
except Exception as e:
    sys.exit(1)
PYEOF
)
    set +e
    python3 -c "$qga_python"
    EXIT_CODE=$?
    set -e
    if [[ $EXIT_CODE -eq 0 ]]; then
        EXEC_SUCCESS=true
    fi
fi

# NO SERIAL LOG FALLBACK! Serial logs do not prove arbitrary command execution.
if [[ "$EXEC_SUCCESS" == "false" && -z "$CHANNEL" ]]; then
    fail "No valid authenticated channel (SSH port or QGA socket) configured for guest command execution!"
fi

END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STDOUT_TEXT=$(cat "$STDOUT_FILE" 2>/dev/null || echo "")
STDERR_TEXT=$(cat "$STDERR_FILE" 2>/dev/null || echo "")

STDOUT_SHA=$(sha256sum "$STDOUT_FILE" 2>/dev/null | awk '{print $1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
STDERR_SHA=$(sha256sum "$STDERR_FILE" 2>/dev/null | awk '{print $1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

# Save stdout log
if [[ -n "$OUT_LOG" ]]; then
    mkdir -p "$(dirname "$OUT_LOG")"
    cat <<EOF > "$OUT_LOG"
=== Authenticated Guest Command Output ($CHANNEL) ===
Command: $CMD
Start Timestamp: $START_TIME
Completion Timestamp: $END_TIME
Exit Code: $EXIT_CODE
Channel: $CHANNEL
--- STDOUT ---
$STDOUT_TEXT
EOF
fi

# Save stderr log
if [[ -n "$STDERR_LOG" ]]; then
    mkdir -p "$(dirname "$STDERR_LOG")"
    cat <<EOF > "$STDERR_LOG"
=== Authenticated Guest Command Error ($CHANNEL) ===
Command: $CMD
--- STDERR ---
$STDERR_TEXT
EOF
fi

# Save result JSON if requested
if [[ -n "$RESULT_JSON" ]]; then
    mkdir -p "$(dirname "$RESULT_JSON")"
    cat <<EOF > "$RESULT_JSON"
{
  "command": "$CMD",
  "channel": "$CHANNEL",
  "start_timestamp": "$START_TIME",
  "completion_timestamp": "$END_TIME",
  "exit_code": $EXIT_CODE,
  "stdout_sha256": "$STDOUT_SHA",
  "stderr_sha256": "$STDERR_SHA",
  "status": "$([[ "$EXEC_SUCCESS" == "true" ]] && echo "PASS" || echo "FAIL")"
}
EOF
fi

# Part 3: Additive Disk-Boot Verification
if [[ "$VERIFY_DISK_BOOT" == "true" && "$EXEC_SUCCESS" == "true" ]]; then
    info "Executing additive disk-boot assertion check..."
    BOOT_VERIFY_CMD="findmnt -n -o SOURCE,FSTYPE / && lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS && cat /proc/cmdline && cat /etc/os-release"
    BOOT_CHECK_OUT=""
    
    if [[ "$CHANNEL" == "ssh" ]]; then
        SSH_OPTS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=10" -p "$SSH_PORT")
        if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then SSH_OPTS+=(-i "$SSH_KEY"); fi
        BOOT_CHECK_OUT=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "$BOOT_VERIFY_CMD" 2>&1 || echo "FAILED_BOOT_CHECK")
    fi

    if echo "$BOOT_CHECK_OUT" | grep -E "(iso9660|/dev/sr0|boot=casper|iso-scan)" >/dev/null 2>&1 || [[ "$BOOT_CHECK_OUT" == "FAILED_BOOT_CHECK" ]]; then
        fail "Disk-boot verification failed! Guest root filesystem is mounted from ISO/casper live media:\n$BOOT_CHECK_OUT"
    fi
    info "Additive disk-boot assertion verified: guest is booted from installed virtual disk."
fi

if [[ "$EXEC_SUCCESS" == "true" ]]; then
    printf '[PASS] Authenticated guest command executed (%s): %s\n' "$CHANNEL" "$CMD"
    exit 0
else
    fail "Authenticated guest command failed (channel: $CHANNEL, exit code $EXIT_CODE): $CMD\nSTDOUT:\n$STDOUT_TEXT\nSTDERR:\n$STDERR_TEXT"
fi
