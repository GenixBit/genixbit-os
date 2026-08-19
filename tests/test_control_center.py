#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit Control Center & Appearance Hub."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-control-center/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import control_center

class TestControlCenter(unittest.TestCase):
    def test_get_default_settings(self):
        settings = control_center.get_current_settings()
        self.assertIn("theme_mode", settings)
        self.assertIn("gtk_theme", settings)
        self.assertIn("accent_color", settings)
        self.assertIn("dock_theme", settings)

    def test_set_theme_mode(self):
        res_dark = control_center.set_theme_mode("dark")
        self.assertEqual(res_dark["applied_settings"]["theme_mode"], "dark")
        self.assertEqual(res_dark["applied_settings"]["gtk_theme"], "GenixBit-Dark")

        res_light = control_center.set_theme_mode("light")
        self.assertEqual(res_light["applied_settings"]["theme_mode"], "light")
        self.assertEqual(res_light["applied_settings"]["gtk_theme"], "GenixBit-Light")

    def test_set_accent_color(self):
        res = control_center.set_accent_color("indigo")
        self.assertEqual(res["applied_settings"]["accent_color"], "indigo")
        self.assertEqual(res["applied_settings"]["accent_hex"], "#6366f1")

    def test_invalid_theme_mode(self):
        with self.assertRaises(ValueError):
            control_center.set_theme_mode("invalid_mode")

if __name__ == "__main__":
    unittest.main()
