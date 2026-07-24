#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Wrapper script pointing generate-migration-evidence.py to collect-migration-evidence.py

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$SCRIPT_DIR/collect-migration-evidence.py" "$@"
