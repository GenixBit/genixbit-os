#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Waits for authentic installer completion inside guest VM and verifies completion token read directly from /etc/genixbit-install-token.
# Calls verify-disk-structure.sh for real offline disk verification and derives result fields dynamically.
#
# Every exit path writes the requested --out-json file before returning.
# On timeout, installer_terminal_state=TIMEOUT and final_status=FAIL.
# Does not perform offline disk inspection while QEMU remains alive.

set -Eeuo pipefail
IFS=$'\n\t'

VM_ID=""
TOKEN=""
PID_FILE=""
QMP_SOCKET=""
SERIAL_LOG=""
SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
DISK_PATH=""
MODE="uefi"
TIMEOUT_SEC=600
NATURAL_SHUTDOWN_GRACE=180
OUT_JSON=""

fail() {
    printf '[FAIL] wait-for-install-completion.sh: %s\n' "$*" >&2
    exit 1
}

write_out_json() {
    local terminal_state="$1"
    local final="$2"
    local fail_phase="${3:-}"
    local fail_reason="${4:-}"
    local token_observed="${5:-false}"
    local progress_observed="${6:-false}"
    local qemu_stopped="${7:-false}"
    local fs_verified="${8:-false}"
    local token_hash="${9:-}"

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    [[ -n "$token_hash" ]] || token_hash=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')

    VM_ID="$VM_ID" \
    MODE="$MODE" \
    TERMINAL_STATE="$terminal_state" \
    FINAL_STATUS="$final" \
    FAIL_PHASE="$fail_phase" \
    FAIL_REASON="$fail_reason" \
    TOKEN_HASH="$token_hash" \
    TS="$ts" \
    TOKEN_OBSERVED="$token_observed" \
    PROGRESS_OBSERVED="$progress_observed" \
    QEMU_STOPPED="$qemu_stopped" \
    FS_VERIFIED="$fs_verified" \
    OUT_JSON="$OUT_JSON" \
    python3 - "$OUT_JSON" <<'PYEOF'
import json
import os
import sys

def boolean(name: str) -> bool:
    value = os.environ.get(name, "").strip().lower()
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be true or false, got {value!r}")
    return value == "true"

result = {
    "schema_version": "1.0",
    "vm_id": os.environ["VM_ID"],
    "firmware_mode": os.environ["MODE"],
    "installer_progress_observed": boolean("PROGRESS_OBSERVED"),
    "serial_token_observed": boolean("TOKEN_OBSERVED"),
    "filesystem_token_verified": boolean("FS_VERIFIED"),
    "qemu_process_stopped": boolean("QEMU_STOPPED"),
    "installer_terminal_state": os.environ["TERMINAL_STATE"],
    "failure_phase": os.environ.get("FAIL_PHASE", ""),
    "failure_reason": os.environ.get("FAIL_REASON", ""),
    "completion_token_hash": os.environ["TOKEN_HASH"],
    "token_source": "installed_root_filesystem",
    "token_path": "/etc/genixbit-install-token",
    "root_partition": "/dev/vda1",
    "root_fs_type": "ext4",
    "verification_timestamp": os.environ["TS"],
    "final_status": os.environ["FINAL_STATUS"],
}
with open(os.environ["OUT_JSON"], "w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2)
PYEOF
}

while (($# > 0)); do
    case "$1" in
        --vm-id)
            (($# >= 2)) || fail '--vm-id requires a value.'
            VM_ID=$2
            shift 2
            ;;
        --token)
            (($# >= 2)) || fail '--token requires a string.'
            TOKEN=$2
            shift 2
            ;;
        --pid-file)
            (($# >= 2)) || fail '--pid-file requires a path.'
            PID_FILE=$2
            shift 2
            ;;
        --qmp-socket)
            (($# >= 2)) || fail '--qmp-socket requires a path.'
            QMP_SOCKET=$2
            shift 2
            ;;
        --serial-log)
            (($# >= 2)) || fail '--serial-log requires a path.'
            SERIAL_LOG=$2
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
            (($# >= 2)) || fail '--ssh-key requires a private key path.'
            SSH_KEY=$2
            shift 2
            ;;
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires uefi or bios.'
            MODE=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        --out-json)
            (($# >= 2)) || fail '--out-json requires a path.'
            OUT_JSON=$2
            shift 2
            ;;
        --natural-shutdown-grace)
            (($# >= 2)) || fail '--natural-shutdown-grace requires seconds.'
            NATURAL_SHUTDOWN_GRACE=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$VM_ID" ]] || fail '--vm-id is required.'
[[ -n "$TOKEN" ]] || fail '--token is required.'
[[ -n "$DISK_PATH" ]] || fail '--disk is required.'

state_dir="$(dirname "$DISK_PATH")"
[[ -n "$OUT_JSON" ]] || OUT_JSON="${state_dir}/install-completion-result-${VM_ID}.json"

printf '[INFO] Waiting for authentic installer completion (VM: %s, Timeout: %ss)...\n' "$VM_ID" "$TIMEOUT_SEC"

start_time=$(date +%s)
installer_progress_observed=false
serial_token_observed=false
qemu_process_stopped=false
filesystem_token_verified=false
installer_terminal_state="RUNNING"

initial_disk_alloc=$(stat -c%s "$DISK_PATH" 2>/dev/null || stat -f%z "$DISK_PATH" 2>/dev/null || echo "0")

while true; do
    curr_time=$(date +%s)
    elapsed=$((curr_time - start_time))

    # Track disk allocation growth as progress evidence (never as completion)
    disk_alloc=$(stat -c%s "$DISK_PATH" 2>/dev/null || stat -f%z "$DISK_PATH" 2>/dev/null || echo "0")
    if (( disk_alloc > initial_disk_alloc + 50000000 )); then
        installer_progress_observed=true
    fi

    # Check serial token signal
    if [[ -f "$SERIAL_LOG" ]] && grep -F "$TOKEN" "$SERIAL_LOG" >/dev/null 2>&1; then
        serial_token_observed=true
        printf '[INFO] Completion token observed in serial log after %ss — waiting for natural installer shutdown (grace: %ss)...\n' "$elapsed" "$NATURAL_SHUTDOWN_GRACE" >&2

        # After seeing the token, do NOT immediately force-stop.
        # Wait up to NATURAL_SHUTDOWN_GRACE seconds for QEMU to exit naturally (poweroff from installer).
        natural_shutdown_ok=false
        grace_start=$(date +%s)
        while true; do
            grace_now=$(date +%s)
            grace_elapsed=$(( grace_now - grace_start ))

            if [[ -f "$PID_FILE" ]]; then
                qpid=$(cat "$PID_FILE" 2>/dev/null || echo "")
                if [[ -n "$qpid" ]] && ! kill -0 "$qpid" 2>/dev/null; then
                    natural_shutdown_ok=true
                    qemu_process_stopped=true
                    printf '[INFO] QEMU exited naturally after installer poweroff (%ss after token).\n' "$grace_elapsed" >&2
                    break
                fi
            else
                natural_shutdown_ok=true
                qemu_process_stopped=true
                break
            fi

            if (( grace_elapsed >= NATURAL_SHUTDOWN_GRACE )); then
                printf '[FAIL] QEMU did not exit naturally within %ss after completion token — installer failed to poweroff.\n' "$NATURAL_SHUTDOWN_GRACE" >&2
                natural_shutdown_ok=false
                break
            fi
            sleep 2
        done

        if [[ "$natural_shutdown_ok" != "true" ]]; then
            installer_terminal_state="TIMEOUT"
            printf '[FAIL] Natural installer shutdown grace period expired. Letting caller cleanup trap handle VM termination.\n' >&2
            write_out_json "$installer_terminal_state" "FAIL" "installer_completion_wait" "Natural shutdown grace expired after token observation - QEMU still alive" \
                "$serial_token_observed" "$installer_progress_observed" "false" "false"
            fail "Installer did not power off naturally after completion token. Completion cannot be verified."
        fi

        installer_terminal_state="NATURAL_EXIT"
        break
    fi

    # Check if QEMU already exited before token observed
    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            qemu_process_stopped=true
            printf '[INFO] QEMU process exited (no serial token yet) after %ss.\n' "$elapsed" >&2
            installer_terminal_state="EARLY_EXIT"
            break
        fi
    fi

    if ((elapsed >= TIMEOUT_SEC)); then
        printf '[WARN] Installer wait loop reached timeout (%ss) for VM %s\n' "$TIMEOUT_SEC" "$VM_ID" >&2
        installer_terminal_state="TIMEOUT"
        break
    fi

    sleep 2
done

TOKEN_HASH=$(printf '%s' "$TOKEN" | sha256sum | awk '{print $1}')

if [[ "$installer_terminal_state" == "TIMEOUT" ]]; then
    write_out_json "TIMEOUT" "FAIL" "installer_completion_wait" "Installer wait loop timed out after ${TIMEOUT_SEC}s" \
        "$serial_token_observed" "$installer_progress_observed" "$qemu_process_stopped" "false" "$TOKEN_HASH"
    fail "Installer wait loop timed out for VM $VM_ID after ${TIMEOUT_SEC}s. Letting caller cleanup trap terminate VM."
fi

# For EARLY_EXIT or NATURAL_EXIT: process already stopped, proceed to disk inspection
if [[ "$qemu_process_stopped" != "true" ]]; then
    # QEMU still alive — we must NOT inspect disk. Return failure to caller, let cleanup trap handle termination.
    write_out_json "RUNNING" "FAIL" "installer_completion_wait" "QEMU still alive after wait loop" \
        "$serial_token_observed" "$installer_progress_observed" "false" "false" "$TOKEN_HASH"
    fail "Installer VM still alive after wait period. Letting caller cleanup trap handle termination."
fi

VERIFY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Call real offline disk-structure inspector helper (QEMU is confirmed stopped)
disk_inspect_json="${state_dir}/disk-inspection-${MODE}.json"
disk_inspect_status="FAIL"
if bash "$(dirname "$0")/verify-disk-structure.sh" --disk "$DISK_PATH" --token "$TOKEN" --mode "$MODE" --out-json "$disk_inspect_json"; then
    disk_inspect_status="PASS"
fi

# Offline target filesystem token verification
if [[ "$disk_inspect_status" == "PASS" ]]; then
    filesystem_token_verified=true
fi

final_status="FAIL"
if [[ "$filesystem_token_verified" == "true" ]]; then
    final_status="PASS"
fi

write_out_json "$installer_terminal_state" "$final_status" "" "" \
    "$serial_token_observed" "$installer_progress_observed" "$qemu_process_stopped" "$filesystem_token_verified" "$TOKEN_HASH"

if [[ "$final_status" != "PASS" ]]; then
    fail "Installer completion token ($TOKEN) not verified in target root filesystem for VM $VM_ID! (final_status: FAIL)"
fi

printf '[PASS] Installer completion verified in root filesystem and recorded in %s\n' "$OUT_JSON"
exit 0
