#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Safe wrapper to run building and testing inside Docker.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

echo "[INFO] Running build and validation suite inside disposable Ubuntu 26.04 Docker container..."
docker run --rm -v "$WORKSPACE_DIR":/workspace -w /workspace ubuntu:26.04 bash -c "
  bash /workspace/tools/validation/build-branding-packages.sh && \
  bash /workspace/tools/validation/test-branding-packages-disposable.sh
"

echo "[PASS] Package build and validation completed successfully inside Docker."
