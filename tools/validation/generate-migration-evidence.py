#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Wrapper script pointing generate-migration-evidence.py to collect-migration-evidence.py

import os
import sys

script_dir = os.path.dirname(os.path.abspath(__file__))
collect_script = os.path.join(script_dir, "collect-migration-evidence.py")
os.execv(sys.executable, [sys.executable, collect_script] + sys.argv[1:])
