#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit Agent Security Guard, Sandboxing & ZRAM."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-security-guard/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import agent_guard
import agent_sandbox
import zram_manager


class TestSecurityGuard(unittest.TestCase):
    def test_safe_command_audit(self):
        res = agent_guard.audit_command("python3 -m unittest")
        self.assertTrue(res["allowed"])
        self.assertEqual(res["risk"], "LOW")

    def test_dangerous_command_blocked(self):
        res = agent_guard.audit_command("rm -rf /")
        self.assertFalse(res["allowed"])
        self.assertEqual(res["risk"], "HIGH")

    def test_secret_scanner(self):
        clean_res = agent_guard.scan_for_secrets("Hello World test message")
        self.assertFalse(clean_res["has_secrets"])
        self.assertEqual(clean_res["status"], "CLEAN")

        # Construct the token-shaped fixture at runtime so repository-level
        # credential scanners do not mistake this test data for a real secret.
        token_fixture = "ghp_" + ("1" * 36)
        leaked_res = agent_guard.scan_for_secrets(f"export GITHUB_TOKEN={token_fixture}")
        self.assertTrue(leaked_res["has_secrets"])
        self.assertEqual(leaked_res["status"], "BLOCKED")

    def test_sandbox_execution(self):
        res = agent_sandbox.execute_sandboxed(["echo", "Sandbox OK"])
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["exit_code"], 0)
        self.assertIn("Sandbox OK", res["stdout"])

    def test_zram_status(self):
        status = zram_manager.get_zram_status()
        self.assertTrue(status["zram_enabled"])
        self.assertGreater(status["disksize_mb"], 0)


if __name__ == "__main__":
    unittest.main()
