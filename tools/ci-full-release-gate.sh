#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS 1.0.0 LTS - Unified Pre-Release CI Gate Runner
# Runs all 9 verification stages with exit code enforcement.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure HOME is set for git commands in isolated environments
export HOME="${HOME:-$REPO_ROOT}"

echo "============================================================"
echo "    GenixBit OS 1.0.0 LTS - Unified Pre-Release CI Gate     "
echo "============================================================"

# Stage 1: Shell Syntax
echo ">>> [1/9] Verifying shell script syntax (bash -n)..."
for f in $(git -C "$REPO_ROOT" ls-files '*.sh'); do
    bash -n "$REPO_ROOT/$f" || { echo "[FAIL] Syntax error in $f"; exit 1; }
done
echo "[PASS] All shell scripts verified cleanly."

# Stage 2: Python Compilation
echo ">>> [2/9] Compiling all Python sources (py_compile)..."
for f in $(git -C "$REPO_ROOT" ls-files '*.py'); do
    python3 -m py_compile "$REPO_ROOT/$f" || { echo "[FAIL] Compilation failed in $f"; exit 1; }
done
echo "[PASS] All Python sources compiled cleanly."

# Stage 3: Security & License Audit
echo ">>> [3/9] Running production security and license audit..."
python3 "$REPO_ROOT/tools/validation/check-security-and-license-audit.py"

# Stage 4: Release Manifest Verification
echo ">>> [4/9] Verifying release manifest (1.0.0-lts.env)..."
bash "$REPO_ROOT/tools/validation/check-release-manifest.sh"

# Stage 5: Version Consistency
echo ">>> [5/9] Checking cross-component release version consistency..."
bash "$REPO_ROOT/tools/validation/check-release-version-consistency.sh"

# Stage 6: Upstream Branding Audit
echo ">>> [6/9] Verifying upstream branding compliance..."
bash "$REPO_ROOT/tools/validation/check-upstream-branding-audit.sh"

# Stage 7: Package Migration & Staging CI Suite (16 checks)
echo ">>> [7/9] Running package migration & staging validation suite..."
bash "$REPO_ROOT/tools/validation/check-package-migration-ci.sh"

# Stage 8: AI Runtime In-Process Unit Tests
echo ">>> [8/9] Running AI proxy & streaming SSE in-process unit tests..."
python3 "$REPO_ROOT/tests/test-ai-runtime.py"

# Stage 9: Model Downloader & Quantization Engine
echo ">>> [9/9] Testing model pull & hardware quantization recommendation..."
python3 "$REPO_ROOT/packages/genixbit-os-ai-center/bin/genixbit-ai-center" quantize-recommend >/dev/null
python3 "$REPO_ROOT/packages/genixbit-os-ai-center/bin/genixbit-ai-center" pull gemma-3-2b-it >/dev/null
echo "[PASS] Model pull and quantization engine verified."

echo "============================================================"
echo "    >>> ALL 9 RELEASE CI GATES PASSED (100% SUCCESS) <<<    "
echo "============================================================"
