#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Test upstream branding audit checker behavior.

set -Eeuo pipefail
IFS=$'\n\t'

TMP_DIR=""

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

TMP_DIR=$(mktemp -d)
DUMMY_AUDIT="$TMP_DIR/UPSTREAM-BRANDING-AUDIT.md"

write_audit() {
    local keyring_class=${1:-"TECHNICAL_DEPENDENCY"}
    local keyring_phase=${2:-"Phase 3"}
    local legal_action=${3:-"Keep unchanged."}
    local extra_row=${4:-""}

    cat <<EOF > "$DUMMY_AUDIT"
# Upstream Branding Audit

| Surface / Path | Current Text | Classification | Reason | Action Required | Target Phase | Replacement Dependency | Validation Needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| UPSTREAM.md:L1 | AnduinOS attribution | LEGAL_ATTRIBUTION | Mandatory attribution | $legal_action | N/A | None | Legal review |
| args.sh:L13 | packages.anduinos.com | $keyring_class | Active APT URL | Migrate URL | $keyring_phase | genixbit-os-apt-config | Clean install |
$extra_row
EOF
}

test_pass() {
    local desc=$1
    if bash tools/validation/check-upstream-branding-audit.sh --audit-file "$DUMMY_AUDIT" >/dev/null 2>&1; then
        printf '[PASS] Behavior test passed: %s\n' "$desc"
    else
        printf '[FAIL] Behavior test failed (expected PASS): %s\n' "$desc" >&2
        exit 1
    fi
}

test_fail() {
    local desc=$1
    if ! bash tools/validation/check-upstream-branding-audit.sh --audit-file "$DUMMY_AUDIT" >/dev/null 2>&1; then
        printf '[PASS] Behavior test passed (correctly rejected): %s\n' "$desc"
    else
        printf '[FAIL] Behavior test failed (expected FAIL): %s\n' "$desc" >&2
        exit 1
    fi
}

# 1. Valid audit -> PASS
write_audit
test_pass "valid audit"

# 2. Missing classification -> FAIL
write_audit "" "Phase 3" "Keep" "| test.sh:L1 | test | | reason | action | Phase 1 | none | test |"
test_fail "missing classification"

# 3. Unknown classification -> FAIL
write_audit "UNKNOWN_CLASSIFICATION"
test_fail "unknown classification"

# 4. Technical dependency without migration phase -> FAIL
write_audit "TECHNICAL_DEPENDENCY" "N/A"
test_fail "technical dependency without migration phase"

# 5. Legal attribution marked for deletion -> FAIL
write_audit "TECHNICAL_DEPENDENCY" "Phase 3" "Delete file completely"
test_fail "legal attribution marked for deletion"

printf '[PASS] All upstream branding audit behavior tests passed.\n'
