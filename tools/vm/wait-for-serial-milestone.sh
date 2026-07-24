#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Monitors a serial log file for a target string/milestone with timeout.

set -Eeuo pipefail
IFS=$'\n\t'

LOG_PATH=""
PATTERN=""
TIMEOUT_SEC=300

fail() {
    printf '[FAIL] wait-for-serial-milestone.sh: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --log)
            (($# >= 2)) || fail '--log requires a path.'
            LOG_PATH=$2
            shift 2
            ;;
        --pattern)
            (($# >= 2)) || fail '--pattern requires a target pattern.'
            PATTERN=$2
            shift 2
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

[[ -n "$LOG_PATH" ]] || fail '--log is required.'
[[ -n "$PATTERN" ]] || fail '--pattern is required.'

end_time=$((SECONDS + TIMEOUT_SEC))

while ((SECONDS < end_time)); do
    if [[ -f "$LOG_PATH" ]] && grep -E "$PATTERN" "$LOG_PATH" >/dev/null 2>&1; then
        printf '[PASS] Serial milestone "%s" matched in %s\n' "$PATTERN" "$LOG_PATH"
        exit 0
    fi
    sleep 2
done

fail "Timeout (${TIMEOUT_SEC}s) reached waiting for pattern \"${PATTERN}\" in ${LOG_PATH}"
