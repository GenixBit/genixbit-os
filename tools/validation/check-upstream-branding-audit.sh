#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate the upstream branding audit document.

set -Eeuo pipefail
IFS=$'\n\t'

AUDIT_FILE="docs/UPSTREAM-BRANDING-AUDIT.md"

usage() {
    cat <<'EOF'
Usage: check-upstream-branding-audit.sh [--audit-file PATH]

Options:
  --audit-file PATH  Read a specific audit file (default: docs/UPSTREAM-BRANDING-AUDIT.md).
  -h, --help         Show this help.
EOF
}

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

while (($# > 0)); do
    case "$1" in
        --audit-file)
            (($# >= 2)) || fail '--audit-file requires a path.'
            AUDIT_FILE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

# 1. docs/UPSTREAM-BRANDING-AUDIT.md exists
[[ -f "$AUDIT_FILE" ]] || fail "Audit file not found: $AUDIT_FILE"

# Extract markdown table rows (excluding headers and separators)
table_rows=()
while IFS= read -r line; do
    # Only process table row lines containing '|'
    if [[ "$line" =~ ^\|.*\|$ ]]; then
        # Skip header rows and formatting rows
        if [[ "$line" =~ ^\|[[:space:]]*---.*\|$ ]] || [[ "$line" =~ ^\|[[:space:]]*Surface.*\|$ ]]; then
            continue
        fi
        table_rows+=("$line")
    fi
done < "$AUDIT_FILE"

(( ${#table_rows[@]} > 0 )) || fail "No audit entries found in $AUDIT_FILE."

found_packages_anduinos=false

for row in "${table_rows[@]}"; do
    # Extract columns by splitting on '|'
    IFS='|' read -ra cols <<< "$row"
    # cols[0] is empty (before first |)
    # cols[1] -> Surface / Path
    # cols[2] -> Current Text
    # cols[3] -> Classification
    # cols[4] -> Reason
    # cols[5] -> Action Required
    # cols[6] -> Target Phase
    # cols[7] -> Replacement Dependency
    # cols[8] -> Validation Needed

    path_text=$(echo "${cols[1]:-}" | xargs)
    current_text=$(echo "${cols[2]:-}" | xargs)
    classification=$(echo "${cols[3]:-}" | tr -d '`' | xargs)
    action_required=$(echo "${cols[5]:-}" | xargs)
    target_phase=$(echo "${cols[6]:-}" | xargs)

    # Check for empty classification
    [[ -n "$classification" ]] || fail "Missing classification in row: $row"

    # 3. Recognized classifications
    case "$classification" in
        LEGAL_ATTRIBUTION|TECHNICAL_DEPENDENCY|BUILD_SYSTEM_COMMENT|USER_VISIBLE_MIGRATION_DEFECT|FALSE_POSITIVE|APPROVED_BASE_OS_REFERENCE)
            ;;
        *)
            fail "Unrecognized classification '$classification' in row: $row"
            ;;
    esac

    # 4. Technical dependencies contain a future migration phase
    if [[ "$classification" == "TECHNICAL_DEPENDENCY" ]]; then
        if [[ ! "$target_phase" =~ Phase\ [0-9] ]] && [[ "$target_phase" != "Ongoing" ]]; then
            fail "TECHNICAL_DEPENDENCY entry '$path_text' must specify a valid migration phase (e.g. Phase 3): found '$target_phase'"
        fi
    fi

    # 5. User-visible migration defects contain an action owner or target phase
    if [[ "$classification" == "USER_VISIBLE_MIGRATION_DEFECT" ]]; then
        if [[ ! "$target_phase" =~ Phase\ [0-9] ]] && [[ -z "$action_required" ]]; then
            fail "USER_VISIBLE_MIGRATION_DEFECT entry '$path_text' must specify a target phase or action requirement."
        fi
    fi

    # 6. Legal attribution is not marked for automatic deletion
    if [[ "$classification" == "LEGAL_ATTRIBUTION" ]]; then
        if [[ "$action_required" =~ [Dd]elete|[Rr]emove ]]; then
            fail "LEGAL_ATTRIBUTION entry '$path_text' is marked for deletion: $action_required"
        fi
    fi

    # 7. packages.anduinos.com remains classified as a temporary technical dependency
    if [[ "$current_text" == *"packages.anduinos.com"* ]] || [[ "$path_text" == *"packages.anduinos.com"* ]]; then
        if [[ "$classification" == "TECHNICAL_DEPENDENCY" ]]; then
            found_packages_anduinos=true
        else
            fail "packages.anduinos.com must be classified as TECHNICAL_DEPENDENCY (found: $classification)."
        fi
    fi
done

[[ "$found_packages_anduinos" == true ]] || fail "packages.anduinos.com entry was not found in audit table."

pass "Upstream branding audit $AUDIT_FILE is valid and compliant."
