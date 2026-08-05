#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run-Scoped Runtime Evidence Collector for GenixBit OS

set -Eeuo pipefail
IFS=$'\n\t'

fail() {
    printf '[FAIL] collect-current-runtime-evidence: %s\n' "$1" >&2
    exit 1
}

STAGE_LOGS_DIR=""
RUNTIME_DIR=""
CANDIDATE_SHA=""
WORKFLOW_RUN_ID=""
WORKFLOW_RUN_ATTEMPT=""
BUILD_A_SHA256=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stage-logs-dir)
            STAGE_LOGS_DIR="$2"
            shift 2
            ;;
        --runtime-dir)
            RUNTIME_DIR="$2"
            shift 2
            ;;
        --candidate-sha)
            CANDIDATE_SHA="$2"
            shift 2
            ;;
        --workflow-run-id)
            WORKFLOW_RUN_ID="$2"
            shift 2
            ;;
        --workflow-run-attempt)
            WORKFLOW_RUN_ATTEMPT="$2"
            shift 2
            ;;
        --build-a-sha256)
            BUILD_A_SHA256="$2"
            shift 2
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

[[ -n "$STAGE_LOGS_DIR" ]] || fail "--stage-logs-dir is required"
[[ -n "$RUNTIME_DIR" ]] || fail "--runtime-dir is required"
[[ -n "$CANDIDATE_SHA" ]] || fail "--candidate-sha is required"
[[ -n "$WORKFLOW_RUN_ID" ]] || fail "--workflow-run-id is required"
[[ -n "$WORKFLOW_RUN_ATTEMPT" ]] || fail "--workflow-run-attempt is required"
[[ -n "$BUILD_A_SHA256" ]] || fail "--build-a-sha256 is required"

[[ "$CANDIDATE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "candidate SHA must be a full 40-character lowercase hex string"
[[ "$BUILD_A_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "Build A SHA-256 must be a full 64-character lowercase hex string"

for bad in "unknown" "local" "0"; do
    [[ "$WORKFLOW_RUN_ID" != "$bad" ]] || fail "workflow run ID cannot be '$bad'"
    [[ "$WORKFLOW_RUN_ATTEMPT" != "$bad" ]] || fail "workflow run attempt cannot be '$bad'"
done

[[ -d "$STAGE_LOGS_DIR" ]] || fail "stage logs directory does not exist: $STAGE_LOGS_DIR"
mkdir -p "$RUNTIME_DIR"

abs_stage_logs=$(cd "$STAGE_LOGS_DIR" && pwd -P)
abs_runtime=$(cd "$RUNTIME_DIR" && pwd -P)

REQUIRED_FILES=(
    "uefi-installer-boot.serial.log"
    "bios-installer-boot.serial.log"
    "uefi-installed-boot.serial.log"
    "bios-installed-boot.serial.log"
    "uefi-guest-validation.log"
    "bios-guest-validation.log"
    "uefi-second-boot-validation.log"
    "bios-second-boot-validation.log"
)

GUEST_LOGS=(
    "uefi-guest-validation.log"
    "bios-guest-validation.log"
    "uefi-second-boot-validation.log"
    "bios-second-boot-validation.log"
)

SERIAL_LOGS=(
    "uefi-installer-boot.serial.log"
    "bios-installer-boot.serial.log"
    "uefi-installed-boot.serial.log"
    "bios-installed-boot.serial.log"
)

REQUIRED_HEALTH_COMMANDS=(
    "cat /etc/os-release"
    "dpkg-query -W"
    "apt-get update"
    "apt-get check"
    "dpkg --audit"
    "systemctl --failed"
)

REQUIRED_PACKAGES=(
    "genixbit-os-desktop"
    "genixbit-os-base"
    "linux-image-generic"
    "systemd"
    "apt"
    "dpkg"
)

calc_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

validate_guest_log() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    grep -q "=== Authenticated Guest Command Output (ssh) ===" "$filepath" || fail "$filename missing SSH channel header"
    grep -q "Start Timestamp:" "$filepath" || fail "$filename missing Start Timestamp"
    grep -q "Completion Timestamp:" "$filepath" || fail "$filename missing Completion Timestamp"
    grep -q "Exit Code: 0" "$filepath" || fail "$filename missing Exit Code: 0"
    grep -q "Channel: ssh" "$filepath" || fail "$filename missing Channel: ssh"

    for cmd in "${REQUIRED_HEALTH_COMMANDS[@]}"; do
        grep -qF "$cmd" "$filepath" || fail "$filename missing required command: $cmd"
    done

    grep -qi "genixbit" "$filepath" || fail "$filename missing product identity GenixBit"

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        grep -qF "$pkg" "$filepath" || fail "$filename missing required package: $pkg"
    done

    if grep -qE "Exit Code: (1|2|124|255)" "$filepath"; then
        fail "$filename contains non-zero command exit code"
    fi
    if grep -qE "Channel: (simulated|host)" "$filepath"; then
        fail "$filename contains forbidden non-SSH channel"
    fi
    if grep -qF "[FAIL]" "$filepath" || grep -qF "Authenticated guest command failed" "$filepath" || grep -qF "FAILED_BOOT_CHECK" "$filepath"; then
        fail "$filename contains failure markers"
    fi
}

validate_serial_log() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    if grep -qi "kernel panic" "$filepath"; then
        fail "$filename contains kernel panic"
    fi
    if grep -qi "emergency mode" "$filepath"; then
        fail "$filename contains emergency mode"
    fi
    if grep -qi "unable to mount root fs" "$filepath" || grep -qi "failed to mount root" "$filepath"; then
        fail "$filename contains failed root filesystem mount"
    fi
    if grep -qi "initramfs" "$filepath" && grep -qi "unable to mount" "$filepath"; then
        fail "$filename contains unresolved initramfs failure"
    fi
    if grep -qi "placeholder_evidence" "$filepath" || grep -qi "dummy_evidence" "$filepath"; then
        fail "$filename contains placeholder/dummy markers"
    fi

    if ! grep -qE "(Linux version|Reached target|login:|Welcome|GenixBit|systemd\[1\]|GRUB)" "$filepath"; then
        fail "$filename missing valid boot milestones"
    fi
}

# 1. Source verification and destination copying
for filename in "${REQUIRED_FILES[@]}"; do
    src="$abs_stage_logs/$filename"
    dst="$abs_runtime/$filename"

    [[ -e "$src" ]] || fail "source file does not exist: $src"
    [[ -f "$src" ]] || fail "source is not a regular file: $src"
    [[ -s "$src" ]] || fail "source file is empty: $src"

    real_src=$(cd "$(dirname "$src")" && pwd -P)/$(basename "$src")
    [[ "$real_src" == "$abs_stage_logs/$filename" ]] || fail "resolved source path $real_src is not inside stage-logs dir $abs_stage_logs"

    [[ ! -e "$dst" ]] || fail "destination file already exists: $dst"
    [[ "$real_src" != "$dst" ]] || fail "source and destination paths are identical: $src"

    cp "$src" "$dst"
    chmod 0644 "$dst"
done

# 2. Content validation of copied guest and serial logs
for filename in "${GUEST_LOGS[@]}"; do
    validate_guest_log "$abs_runtime/$filename"
done

for filename in "${SERIAL_LOGS[@]}"; do
    validate_serial_log "$abs_runtime/$filename"
done

uefi_inst_sha=$(calc_sha256 "$abs_runtime/uefi-installer-boot.serial.log")
bios_inst_sha=$(calc_sha256 "$abs_runtime/bios-installer-boot.serial.log")
[[ "$uefi_inst_sha" != "$bios_inst_sha" ]] || fail "UEFI and BIOS installer serial logs have identical SHA-256"

uefi_installed_sha=$(calc_sha256 "$abs_runtime/uefi-installed-boot.serial.log")
bios_installed_sha=$(calc_sha256 "$abs_runtime/bios-installed-boot.serial.log")
[[ "$uefi_installed_sha" != "$bios_installed_sha" ]] || fail "UEFI and BIOS installed serial logs have identical SHA-256"

# 3. Build runtime-evidence-manifest.json
manifest_file="$abs_runtime/runtime-evidence-manifest.json"

export abs_stage_logs abs_runtime CANDIDATE_SHA WORKFLOW_RUN_ID WORKFLOW_RUN_ATTEMPT BUILD_A_SHA256 manifest_file

python3 - <<'PYEOF'
import os, sys, json, hashlib

stage_logs_dir = os.environ["abs_stage_logs"]
runtime_dir = os.environ["abs_runtime"]

files_map = {}
for fname in [
    "uefi-installer-boot.serial.log",
    "bios-installer-boot.serial.log",
    "uefi-installed-boot.serial.log",
    "bios-installed-boot.serial.log",
    "uefi-guest-validation.log",
    "bios-guest-validation.log",
    "uefi-second-boot-validation.log",
    "bios-second-boot-validation.log"
]:
    fpath = os.path.join(runtime_dir, fname)
    size_bytes = os.path.getsize(fpath)
    sha256_hash = hashlib.sha256(open(fpath, "rb").read()).hexdigest()
    files_map[fname] = {
        "path": fpath,
        "size_bytes": size_bytes,
        "sha256": sha256_hash
    }

manifest_data = {
    "source_commit": os.environ["CANDIDATE_SHA"],
    "workflow_run_id": os.environ["WORKFLOW_RUN_ID"],
    "workflow_run_attempt": os.environ["WORKFLOW_RUN_ATTEMPT"],
    "build_a_iso_sha256": os.environ["BUILD_A_SHA256"],
    "source_stage_logs_dir": stage_logs_dir,
    "runtime_evidence_dir": runtime_dir,
    "files": files_map,
    "exit_code": 0,
    "status": "PASS"
}

with open(os.environ["manifest_file"], "w", encoding="utf-8") as f:
    json.dump(manifest_data, f, indent=2)
    f.write("\n")
PYEOF

chmod 0644 "$manifest_file"
printf '[PASS] collect-current-runtime-evidence: collected and validated all 8 runtime files and wrote manifest\n'
