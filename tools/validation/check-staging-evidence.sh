#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validation script for GenixBit OS Package Staging Evidence Manifests

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))
INFRA_DIR="$REPO_ROOT/infra/package-staging"

EVIDENCE_FILE="${1:-}"
REQUIRE_COMPLETE=0

for arg in "$@"; do
    case "$arg" in
        --require-complete)
            REQUIRE_COMPLETE=1
            ;;
    esac
done

if [[ -z "$EVIDENCE_FILE" || "$EVIDENCE_FILE" == --* ]]; then
    # Look for evidence manifest in infra/package-staging/
    EVIDENCE_FILE=$(find "$INFRA_DIR" -maxdepth 1 -name "evidence-*.json" 2>/dev/null | head -n1 || true)
fi

if [[ -z "$EVIDENCE_FILE" || ! -f "$EVIDENCE_FILE" ]]; then
    if [[ "$REQUIRE_COMPLETE" -eq 1 ]]; then
        echo "[ERROR] Staging Evidence Check: No evidence manifest found, but --require-complete was specified." >&2
        exit 1
    else
        echo "[INFO] Staging Evidence Check: No staging evidence manifest present (environment not deployed)."
        exit 0
    fi
fi

# Validate JSON Schema
if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
    python3 -c "import json, jsonschema; jsonschema.validate(json.load(open('$EVIDENCE_FILE')), json.load(open('$INFRA_DIR/schemas/staging-evidence.schema.json')))"
    echo "[PASS] Evidence manifest '$EVIDENCE_FILE' conforms to JSON Schema."
fi

# Check for SIMULATED or FAILED statuses
if grep -i -E 'SIMULATED|FAILED' "$EVIDENCE_FILE" >/dev/null; then
    if [[ "$REQUIRE_COMPLETE" -eq 1 ]]; then
        echo "[ERROR] Evidence manifest '$EVIDENCE_FILE' contains SIMULATED or FAILED stage records!" >&2
        exit 1
    fi
fi

echo "[PASS] Staging Evidence Manifest Validation Passed: $EVIDENCE_FILE"
