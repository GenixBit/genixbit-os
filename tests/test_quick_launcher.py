#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit Spotlight HUD Quick Launcher."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-quick-launcher/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import quick_launcher

class TestQuickLauncher(unittest.TestCase):
    def test_empty_search_returns_defaults(self):
        res = quick_launcher.search("")
        self.assertEqual(res["mode"], "apps")
        self.assertGreater(len(res["results"]), 4)

    def test_fuzzy_app_search(self):
        res = quick_launcher.search("control")
        self.assertEqual(res["mode"], "apps")
        self.assertGreater(res["match_count"], 0)
        self.assertEqual(res["results"][0]["name"], "GenixBit Control Center")

    def test_ai_query_mode(self):
        res = quick_launcher.search("@ai What is GenixBit OS?")
        self.assertEqual(res["mode"], "ai_inference")
        self.assertEqual(res["prompt"], "What is GenixBit OS?")
        self.assertIn("genixbit-agent run", res["results"][0]["exec"])

if __name__ == "__main__":
    unittest.main()
