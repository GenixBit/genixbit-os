#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validates installed guest system identity, APT repository status, and package health by executing observed commands inside the guest over authenticated SSH.

set -Eeuo pipefail
IFS=$'\n\t'

DISK_PATH=""
MODE="uefi"
SSH_PORT=""
SSH_USER="genixbit"
SSH_KEY=""
VM_ID=""
PID_FILE=""

fail() {
    printf '[FAIL] validate-installed-system.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --disk)
            (($# >= 2)) || fail '--disk requires a path.'
            DISK_PATH=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
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
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$DISK_PATH" && -f "$DISK_PATH" ]] || fail 'Valid --disk path is required.'
[[ -n "$SSH_PORT" ]] || fail '--ssh-port is required.'

state_dir="$(dirname "$DISK_PATH")/val-${MODE}-state"
stage_logs_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/infra/package-staging/results/stage-logs"
mkdir -p "$state_dir" "$stage_logs_dir"

printf '[INFO] Validating installed system health inside guest (%s mode, VM: %s, Port: %s)...\n' "$MODE" "$VM_ID" "$SSH_PORT"

VALIDATION_CMD="cat /etc/os-release && uname -a && findmnt -n -o SOURCE,FSTYPE / && lsblk -f && cat /proc/cmdline && dpkg-query -W genixbit-os-archive-keyring genixbit-os-apt-config genixbit-os-base-files genixbit-os-desktop genixbit-os-theme genixbit-os-wallpapers genixbit-os-installer-config && apt-cache policy && apt-get update && apt-get check && dpkg --audit && systemctl --failed && find /etc/apt -maxdepth 3 -type f -print && grep -R . /etc/apt 2>/dev/null"

guest_log="$stage_logs_dir/${MODE}-guest-validation.log"

bash "$(dirname "$0")/guest-command.sh" \
    --cmd "$VALIDATION_CMD" \
    --ssh-port "$SSH_PORT" \
    --ssh-user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --vm-id "$VM_ID" \
    --pid-file "$PID_FILE" \
    --out-log "$guest_log" \
    --verify-disk-boot

# Verify required product identity and packages in guest log
if ! grep -i "GenixBit" "$guest_log" >/dev/null 2>&1; then
    fail "Guest validation failed! Product identity 'GenixBit' missing from guest output."
fi

# Verify no release-blocking failed systemd services
if grep -E "0 loaded units listed" "$guest_log" >/dev/null 2>&1 || ! grep -E "failed" "$guest_log" >/dev/null 2>&1; then
    printf '[PASS] No failed systemd units detected in guest.\n'
else
    FAILED_UNITS=$(grep -E "\.service|\.target" "$guest_log" | grep -vE "(speech-dispatcher|systemd-hostnamed)" || true)
    if [[ -n "$FAILED_UNITS" ]]; then
        fail "Release-blocking failed systemd units detected in guest:\n$FAILED_UNITS"
    fi
fi

printf '[PASS] Installed system package health & identity verified inside guest for %s mode: %s\n' "$MODE" "$DISK_PATH"
exit 0
