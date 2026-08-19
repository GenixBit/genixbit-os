#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import os
import shutil
import tempfile
import unittest
import sys

sys.path.insert(0, os.path.abspath("packages/genixbit-os-store/usr/lib/genixbit-os"))
import gbx_core

class TestGBXPackageManager(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="gbx_test_")
        self.old_cwd = os.getcwd()
        os.chdir(self.test_dir)
        
        # Override paths to temp
        gbx_core.GBX_APPS_DIR = os.path.join(self.test_dir, "apps")
        gbx_core.GBX_DB_PATH = os.path.join(self.test_dir, "db", "packages.json")
        gbx_core.GBX_BACKUPS_DIR = os.path.join(self.test_dir, "backups")
        gbx_core.GBX_DESKTOP_DIR = os.path.join(self.test_dir, "applications")

    def tearDown(self):
        os.chdir(self.old_cwd)
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_create_and_build_package(self):
        ret = gbx_core.cmd_create("Calculator Pro")
        self.assertEqual(ret, 0)
        self.assertTrue(os.path.exists("calculator-pro/manifest.json"))
        self.assertTrue(os.path.exists("calculator-pro/src/main.py"))

        ret = gbx_core.cmd_build("calculator-pro")
        self.assertEqual(ret, 0)
        gbx_file = "calculator-pro/com.genixbit.calculator-pro_1.0.0.gbx"
        self.assertTrue(os.path.exists(gbx_file))

        # Verify
        valid, msg, manifest = gbx_core.verify_package(gbx_file)
        self.assertTrue(valid)
        self.assertEqual(manifest["id"], "com.genixbit.calculator-pro")

    def test_install_and_remove_package(self):
        gbx_core.cmd_create("Notes App")
        gbx_core.cmd_build("notes-app")
        gbx_file = "notes-app/com.genixbit.notes-app_1.0.0.gbx"

        # Install
        ret = gbx_core.cmd_install(gbx_file)
        self.assertEqual(ret, 0)

        db = gbx_core.load_db()
        self.assertIn("com.genixbit.notes-app", db["packages"])

        # Audit
        self.assertEqual(gbx_core.cmd_audit(), 0)

        # Remove
        ret = gbx_core.cmd_remove("com.genixbit.notes-app")
        self.assertEqual(ret, 0)
        db = gbx_core.load_db()
        self.assertNotIn("com.genixbit.notes-app", db["packages"])

    def test_doctor_diagnostic(self):
        self.assertEqual(gbx_core.cmd_doctor(), 0)

if __name__ == "__main__":
    unittest.main()
