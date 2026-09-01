#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Non-destructive runtime smoke test for the current GenixBit OS live ISO.
# Boots the ISO payload under QEMU using its real kernel/initrd, waits for the
# graphical target and LightDM on the serial console, captures the real QEMU
# framebuffer, and records only observed evidence.

set -Eeuo pipefail
IFS=$'\n\t'

ISO_PATH=""
MODE="uefi"
TIMEOUT_SEC=900
STATE_DIR=""

fail() {
    printf '[FAIL] smoke-current-live-iso.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --iso)
            (($# >= 2)) || fail '--iso requires a path.'
            ISO_PATH=$2
            shift 2
            ;;
        --mode)
            (($# >= 2)) || fail '--mode requires bios or uefi.'
            MODE=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || fail '--timeout requires seconds.'
            TIMEOUT_SEC=$2
            shift 2
            ;;
        --state-dir)
            (($# >= 2)) || fail '--state-dir requires a path.'
            STATE_DIR=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || fail 'Valid --iso path is required.'
[[ "$MODE" == "uefi" || "$MODE" == "bios" ]] || fail '--mode must be bios or uefi.'
[[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || fail '--timeout must be an integer.'

command -v qemu-system-x86_64 >/dev/null 2>&1 || fail 'qemu-system-x86_64 is required.'
command -v qemu-img >/dev/null 2>&1 || fail 'qemu-img is required.'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required.'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
QMP_CLIENT="$SCRIPT_DIR/qmp-client.py"

if [[ -z "$STATE_DIR" ]]; then
    STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/genixbit-live-smoke.XXXXXX")
else
    mkdir -p "$STATE_DIR"
fi
STATE_DIR=$(cd "$STATE_DIR" && pwd -P)

DISK_PATH="$STATE_DIR/live-smoke-${MODE}.qcow2"
SERIAL_LOG="$STATE_DIR/live-smoke-${MODE}.serial.log"
QMP_SOCKET="$STATE_DIR/live-smoke-${MODE}.qmp.sock"
PID_FILE="$STATE_DIR/live-smoke-${MODE}.pid"
SCREENSHOT="$STATE_DIR/live-smoke-${MODE}.ppm"
RESULT_JSON="$STATE_DIR/live-smoke-${MODE}.json"
KERNEL_JSON="$STATE_DIR/kernel-extraction.json"

QEMU_PID=""
cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        if [[ -S "$QMP_SOCKET" ]]; then
            python3 "$QMP_CLIENT" --socket "$QMP_SOCKET" --timeout 5 quit >/dev/null 2>&1 || true
            for _ in {1..10}; do
                kill -0 "$QEMU_PID" 2>/dev/null || break
                sleep 1
            done
        fi
        kill "$QEMU_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$QEMU_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

qemu-img create -f qcow2 "$DISK_PATH" 8G >/dev/null

bash "$SCRIPT_DIR/extract-installer-kernel.sh" \
    --iso "$ISO_PATH" \
    --out-dir "$STATE_DIR/kernel" \
    --out-json "$KERNEL_JSON" >/dev/null

VMLINUX=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["vmlinuz_path"])' "$KERNEL_JSON")
INITRD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["initrd_path"])' "$KERNEL_JSON")
[[ -s "$VMLINUX" && -s "$INITRD" ]] || fail 'Failed to extract non-empty kernel/initrd from ISO.'

qemu_args=(
    -m 4096
    -smp 4
    -drive "file=$DISK_PATH,format=qcow2,if=virtio,cache=unsafe"
    -device ahci,id=ahci0
    -drive "file=$ISO_PATH,format=raw,if=none,id=isocd,media=cdrom,readonly=on"
    -device ide-cd,bus=ahci0.0,drive=isocd
    -netdev user,id=net0
    -device virtio-net-pci,netdev=net0
    -vga virtio
    -display none
    -serial "file:$SERIAL_LOG"
    -qmp "unix:$QMP_SOCKET,server,nowait"
    -pidfile "$PID_FILE"
    -kernel "$VMLINUX"
    -initrd "$INITRD"
    -append "boot=casper nopersistent console=ttyS0,115200n8 systemd.show_status=1 systemd.log_level=info ---"
    -no-reboot
)

if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    qemu_args+=( -enable-kvm -cpu host )
else
    qemu_args+=( -accel tcg,thread=multi -cpu max )
fi

if [[ "$MODE" == "uefi" ]]; then
    OVMF_CODE=""
    OVMF_VARS=""
    for candidate in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd /usr/share/edk2/ovmf/OVMF_CODE.fd; do
        if [[ -f "$candidate" ]]; then OVMF_CODE=$candidate; break; fi
    done
    for candidate in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/ovmf/OVMF_VARS.fd /usr/share/edk2/ovmf/OVMF_VARS.fd; do
        if [[ -f "$candidate" ]]; then OVMF_VARS=$candidate; break; fi
    done
    [[ -n "$OVMF_CODE" && -n "$OVMF_VARS" ]] || fail 'UEFI mode requested but OVMF firmware is unavailable.'
    cp "$OVMF_VARS" "$STATE_DIR/OVMF_VARS.fd"
    qemu_args+=(
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
        -drive "if=pflash,format=raw,file=$STATE_DIR/OVMF_VARS.fd"
    )
fi

: > "$SERIAL_LOG"
rm -f "$QMP_SOCKET" "$PID_FILE"
qemu-system-x86_64 "${qemu_args[@]}" >"$STATE_DIR/qemu.stderr.log" 2>&1 &
QEMU_PID=$!
echo "$QEMU_PID" > "$PID_FILE"

# QMP readiness is mandatory evidence that the VM itself started successfully.
qmp_ready=false
for _ in {1..30}; do
    if kill -0 "$QEMU_PID" 2>/dev/null && [[ -S "$QMP_SOCKET" ]]; then
        qmp_status=$(python3 "$QMP_CLIENT" --socket "$QMP_SOCKET" --timeout 5 query-active-status 2>/dev/null || true)
        if [[ "$qmp_status" == "running" || "$qmp_status" == "prelaunch" ]]; then
            qmp_ready=true
            break
        fi
    fi
    sleep 1
done
[[ "$qmp_ready" == "true" ]] || fail 'QEMU failed to become QMP-ready.'

start_epoch=$(date +%s)
graphical_observed=false
lightdm_observed=false
failure_observed=""

while true; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        failure_observed='QEMU exited before graphical live-session readiness.'
        break
    fi

    if grep -Eqi 'kernel panic|entered emergency mode|you are in emergency mode' "$SERIAL_LOG"; then
        failure_observed='Kernel panic or emergency mode observed on serial console.'
        break
    fi

    if grep -Eqi 'Reached target (Graphical Interface|graphical\.target)' "$SERIAL_LOG"; then
        graphical_observed=true
    fi
    if grep -Eqi 'Started .*Light Display Manager|Started lightdm\.service|Started LightDM' "$SERIAL_LOG"; then
        lightdm_observed=true
    fi

    if [[ "$graphical_observed" == "true" && "$lightdm_observed" == "true" ]]; then
        break
    fi

    now_epoch=$(date +%s)
    if (( now_epoch - start_epoch >= TIMEOUT_SEC )); then
        failure_observed="Timed out after ${TIMEOUT_SEC}s waiting for graphical.target and LightDM."
        break
    fi
    sleep 2
done

[[ -z "$failure_observed" ]] || fail "$failure_observed"

bash "$SCRIPT_DIR/capture-screenshot.sh" --socket "$QMP_SOCKET" --output "$SCREENSHOT" >/dev/null

SCREEN_META=$(python3 - "$SCREENSHOT" <<'PYEOF'
import hashlib
import json
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    magic = f.readline().strip()
    if magic != b"P6":
        raise SystemExit("QMP screenshot is not binary PPM (P6)")

    tokens = []
    while len(tokens) < 3:
        line = f.readline()
        if not line:
            raise SystemExit("Truncated PPM header")
        if line.startswith(b"#"):
            continue
        tokens.extend(line.split())

    width, height, maxval = map(int, tokens[:3])
    pixels = f.read()

if width < 640 or height < 480:
    raise SystemExit(f"Framebuffer too small: {width}x{height}")
if maxval != 255:
    raise SystemExit(f"Unexpected PPM max value: {maxval}")
expected = width * height * 3
if len(pixels) < expected:
    raise SystemExit(f"Truncated framebuffer payload: {len(pixels)} < {expected}")

# Reject a completely uniform framebuffer. Sample across the full image to keep
# this check inexpensive without attempting OCR or image interpretation.
step = max(3, (expected // 5000 // 3) * 3)
samples = {pixels[i:i+3] for i in range(0, expected - 2, step)}
if len(samples) < 2:
    raise SystemExit("Framebuffer is uniform; no visible live-session output observed")

sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
print(json.dumps({"width": width, "height": height, "sha256": sha, "sampled_colors": len(samples)}))
PYEOF
) || fail 'Framebuffer validation failed.'

ISO_SHA=$(sha256sum "$ISO_PATH" | awk '{print $1}')
SERIAL_SHA=$(sha256sum "$SERIAL_LOG" | awk '{print $1}')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ISO_PATH="$ISO_PATH" \
MODE="$MODE" \
ISO_SHA="$ISO_SHA" \
SERIAL_LOG="$SERIAL_LOG" \
SERIAL_SHA="$SERIAL_SHA" \
SCREENSHOT="$SCREENSHOT" \
SCREEN_META="$SCREEN_META" \
TIMESTAMP="$TIMESTAMP" \
RESULT_JSON="$RESULT_JSON" \
python3 - <<'PYEOF'
import json
import os

screen = json.loads(os.environ["SCREEN_META"])
result = {
    "schema_version": "1.0",
    "test": "current_live_iso_runtime_smoke",
    "firmware_mode": os.environ["MODE"],
    "iso_path": os.environ["ISO_PATH"],
    "iso_sha256": os.environ["ISO_SHA"],
    "qmp_ready": True,
    "graphical_target_observed": True,
    "lightdm_started_observed": True,
    "serial_log": os.environ["SERIAL_LOG"],
    "serial_sha256": os.environ["SERIAL_SHA"],
    "framebuffer_path": os.environ["SCREENSHOT"],
    "framebuffer_sha256": screen["sha256"],
    "framebuffer_width": screen["width"],
    "framebuffer_height": screen["height"],
    "framebuffer_sampled_colors": screen["sampled_colors"],
    "evidence_sources": ["qmp", "serial_console", "qmp_screendump"],
    "timestamp": os.environ["TIMESTAMP"],
    "status": "PASS",
}
with open(os.environ["RESULT_JSON"], "w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2)
PYEOF

printf '[PASS] GenixBit live ISO reached graphical.target with LightDM and a non-uniform framebuffer (%s): %s\n' "$MODE" "$RESULT_JSON"
exit 0
