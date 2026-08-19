#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit OS Themes, Plank Glass Dock & Vector Icons."""
import os
import pathlib
import unittest

class TestUITheme(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(__file__).parent.parent.resolve()

    def test_theme_files_exist(self):
        dark_gtk = self.root / "packages/genixbit-os-theme/usr/share/themes/GenixBit-Dark/gtk-3.0/gtk.css"
        light_gtk = self.root / "packages/genixbit-os-theme/usr/share/themes/GenixBit-Light/gtk-3.0/gtk.css"
        dark_xfwm = self.root / "packages/genixbit-os-theme/usr/share/themes/GenixBit-Dark/xfwm4/themerc"
        light_xfwm = self.root / "packages/genixbit-os-theme/usr/share/themes/GenixBit-Light/xfwm4/themerc"
        plank_dock = self.root / "packages/genixbit-os-theme/usr/share/plank/themes/GenixBit-Glass/dock.theme"

        self.assertTrue(dark_gtk.exists(), "Missing GenixBit-Dark gtk.css")
        self.assertTrue(light_gtk.exists(), "Missing GenixBit-Light gtk.css")
        self.assertTrue(dark_xfwm.exists(), "Missing GenixBit-Dark xfwm4 themerc")
        self.assertTrue(light_xfwm.exists(), "Missing GenixBit-Light xfwm4 themerc")
        self.assertTrue(plank_dock.exists(), "Missing GenixBit-Glass dock.theme")

    def test_icons_exist(self):
        icons_dir = self.root / "packages/genixbit-os-icons/usr/share/icons/GenixBit-Icons/scalable/apps"
        index_theme = self.root / "packages/genixbit-os-icons/usr/share/icons/GenixBit-Icons/index.theme"

        self.assertTrue(index_theme.exists(), "Missing GenixBit-Icons index.theme")
        self.assertTrue((icons_dir / "genixbit-control-center.svg").exists())
        self.assertTrue((icons_dir / "genixbit-launcher.svg").exists())
        self.assertTrue((icons_dir / "genixbit-swarm.svg").exists())
        self.assertTrue((icons_dir / "genixbit-guard.svg").exists())

if __name__ == "__main__":
    unittest.main()
