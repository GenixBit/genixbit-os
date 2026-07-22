#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared path safety verification library for GenixBit repository tooling.

set -euo pipefail

validate_repository_path() {
    local path="${1:-}"
    local param_name="${2:-repository path}"

    # 1. Reject empty or whitespace-only paths
    if [[ -z "$path" || "$path" =~ ^[[:space:]]+$ ]]; then
        echo "Error: Safety violation - $param_name cannot be empty or whitespace." >&2
        return 1
    fi

    # 2. Check forbidden system roots immediately (even if unreadable/permission denied)
    local raw_clean
    # shellcheck disable=SC2001
    raw_clean=$(echo "$path" | sed 's#^//*#/#')
    case "$raw_clean" in
        /|/root|/etc|/usr|/var|/boot|/sys|/proc|/dev)
            echo "Error: Safety violation - Refusing operation on root system directory: $path" >&2
            return 1
            ;;
    esac

    if [[ -n "${HOME:-}" && "$raw_clean" == "$HOME" ]]; then
        echo "Error: Safety violation - Refusing operation on user home directory: $path" >&2
        return 1
    fi

    # 3. Canonicalize path if accessible, else retain clean path
    local abs_path=""
    if [[ -d "$path" ]]; then
        abs_path=$(cd "$path" 2>/dev/null && pwd -P || echo "$raw_clean")
    elif [[ -d "$(dirname "$path")" ]]; then
        local parent_dir
        parent_dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P || dirname "$path")
        abs_path="${parent_dir}/$(basename "$path")"
    else
        echo "Error: Safety violation - Parent directory of $param_name does not exist: $path" >&2
        return 1
    fi

    # Normalize multiple leading slashes
    # shellcheck disable=SC2001
    abs_path=$(echo "$abs_path" | sed 's#^//*#/#')

    # 4. Reject root, home, and system directories after canonicalization
    if [[ "$abs_path" == "/" || "$abs_path" == "/root" || "$abs_path" == "/etc" || "$abs_path" == "/usr" || "$abs_path" == "/var" ]]; then
        echo "Error: Safety violation - Refusing operation on root system directory: $abs_path" >&2
        return 1
    fi

    if [[ -n "${HOME:-}" && "$abs_path" == "$HOME" ]]; then
        echo "Error: Safety violation - Refusing operation on user home directory: $abs_path" >&2
        return 1
    fi

    # 5. Check GENIXBIT_REPOSITORY_ROOT if defined
    if [[ -n "${GENIXBIT_REPOSITORY_ROOT:-}" ]]; then
        local allowed_root
        allowed_root=$(cd "$GENIXBIT_REPOSITORY_ROOT" 2>/dev/null && pwd -P || echo "$GENIXBIT_REPOSITORY_ROOT")
        if [[ "$abs_path" != "$allowed_root"* ]]; then
            echo "Error: Safety violation - Path $abs_path is outside allowed root $allowed_root" >&2
            return 1
        fi
    fi

    echo "$abs_path"
    return 0
}
