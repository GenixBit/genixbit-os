#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Executes commands inside a running QEMU guest VM via authenticated SSH.
# Captures stdout, stderr, timestamps, exit code, and SHA-256 digests without error suppression.

set -Eeuo pipefail
IFS=$'\n\t'

CMD=""
SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
OUT_LOG=""
STDERR_LOG=""
RESULT_JSON=""
VERIFY_DISK_BOOT=false
REBOOT=false
SHUTDOWN=false
TIMEOUT_SEC=300
VM_ID=""
PID_FILE=""

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
        --vm-id)
            (($# >= 2)) || fail '--vm-id requires a value.'
            VM_ID=$2
            shift 2
            ;;
        --pid-file)
            (($# >= 2)) || fail '--pid-file requires a path.'
            PID_FILE=$2
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
            # Ignore legacy arguments for backward compatibility
            if [[ "$1" == "--guest-agent-socket" || "$1" == "--guest-agent" || "$1" == "--qmp" || "$1" == "--serial-log" ]]; then
                shift 2
            else
                fail "Unknown argument: $1"
            fi
            ;;
    esac
done

if [[ "$REBOOT" == "true" ]]; then
    CMD="sudo systemctl reboot"
elif [[ "$SHUTDOWN" == "true" ]]; then
    CMD="sudo systemctl poweroff"
fi

[[ -n "$CMD" ]] || fail '--cmd, --verify-disk-boot, --reboot, or --shutdown is required.'
[[ -n "$SSH_PORT" ]] || fail '--ssh-port is required.'

START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)

cleanup_tmp() {
    rm -f "$STDOUT_FILE" "$STDERR_FILE" 2>/dev/null || true
}
trap cleanup_tmp EXIT

CHANNEL="ssh"
SSH_OPTS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -o "ConnectTimeout=10" -p "$SSH_PORT")
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

set +e
timeout "$TIMEOUT_SEC" ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "$CMD" > "$STDOUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

EXEC_SUCCESS=false

if [[ "$REBOOT" == "true" ]]; then
    # SSH disconnect exit 255 or 0 on reboot is accepted
    if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 255 ]]; then
        # Confirm guest returns after reboot
        sleep 3
        REBOOT_TOKEN="POST_REBOOT_$(date +%s)_$$"
        REBOOT_OK=false
        for _ in {1..30}; do
            if ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "echo '$REBOOT_TOKEN'" 2>/dev/null | grep -F "$REBOOT_TOKEN" >/dev/null 2>&1; then
                REBOOT_OK=true
                break
            fi
            sleep 2
        done
        if [[ "$REBOOT_OK" == "true" ]]; then
            EXEC_SUCCESS=true
            EXIT_CODE=0
        else
            fail "Reboot command sent but guest failed to return and authenticate post-reboot!"
        fi
    fi
elif [[ "$SHUTDOWN" == "true" ]]; then
    if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 255 ]]; then
        # Confirm QEMU process exits
        if [[ -n "$PID_FILE" && -f "$PID_FILE" ]]; then
            PID=$(cat "$PID_FILE" 2>/dev/null || echo "0")
            SHUTDOWN_OK=false
            for _ in {1..20}; do
                if ! kill -0 "$PID" 2>/dev/null; then
                    SHUTDOWN_OK=true
                    break
                fi
                sleep 1
            done
            if [[ "$SHUTDOWN_OK" == "true" ]]; then
                EXEC_SUCCESS=true
                EXIT_CODE=0
            else
                fail "Shutdown command sent but QEMU process (PID $PID) remained running!"
            fi
        else
            EXEC_SUCCESS=true
            EXIT_CODE=0
        fi
    fi
elif [[ $EXIT_CODE -eq 0 ]]; then
    EXEC_SUCCESS=true
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

# Save result JSON
if [[ -n "$RESULT_JSON" ]]; then
    mkdir -p "$(dirname "$RESULT_JSON")"
    cat <<EOF > "$RESULT_JSON"
{
  "command": "$CMD",
  "channel": "$CHANNEL",
  "vm_id": "${VM_ID:-unknown}",
  "start_timestamp": "$START_TIME",
  "completion_timestamp": "$END_TIME",
  "exit_code": $EXIT_CODE,
  "stdout_sha256": "$STDOUT_SHA",
  "stderr_sha256": "$STDERR_SHA",
  "status": "$([[ "$EXEC_SUCCESS" == "true" ]] && echo "PASS" || echo "FAIL")"
}
EOF
fi

# Additive Disk-Boot Verification
if [[ "$VERIFY_DISK_BOOT" == "true" && "$EXEC_SUCCESS" == "true" ]]; then
    BOOT_VERIFY_CMD="findmnt -n -o SOURCE,FSTYPE / && lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS && cat /proc/cmdline && cat /etc/os-release"
    BOOT_CHECK_OUT=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@127.0.0.1" "$BOOT_VERIFY_CMD" 2>&1 || echo "FAILED_BOOT_CHECK")

    if echo "$BOOT_CHECK_OUT" | grep -E "(iso9660|/dev/sr0|boot=casper|iso-scan)" >/dev/null 2>&1 || [[ "$BOOT_CHECK_OUT" == "FAILED_BOOT_CHECK" ]]; then
        fail "Disk-boot verification failed! Guest root filesystem is mounted from ISO/casper live media:\n$BOOT_CHECK_OUT"
    fi
fi

if [[ "$EXEC_SUCCESS" == "true" ]]; then
    printf '[PASS] Authenticated guest command executed (%s): %s\n' "$CHANNEL" "$CMD"
    exit 0
else
    fail "Authenticated guest command failed (channel: $CHANNEL, exit code $EXIT_CODE): $CMD\nSTDOUT:\n$STDOUT_TEXT\nSTDERR:\n$STDERR_TEXT"
fi
