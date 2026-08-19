#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit Bharat AI & Compute Mesh."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-indic-llm/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import bharat_ai
import compute_mesh

class TestIndicLLM(unittest.TestCase):
    def test_list_22_languages(self):
        langs = bharat_ai.list_languages()
        self.assertEqual(len(langs), 22)
        codes = [l["code"] for l in langs]
        self.assertIn("hi", codes)
        self.assertIn("mr", codes)
        self.assertIn("ta", codes)
        self.assertIn("bn", codes)

    def test_get_language_info(self):
        info = bharat_ai.get_language_info("hi")
        self.assertIsNotNone(info)
        self.assertEqual(info["name"], "Hindi")
        self.assertEqual(info["script"], "Devanagari")

    def test_translation_mock(self):
        res = bharat_ai.translate_mock("Namaste", "hi", "en")
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["source"], "hi")

    def test_compute_mesh_discovery(self):
        status = compute_mesh.get_mesh_status()
        self.assertTrue(status["mesh_active"])
        self.assertGreaterEqual(status["peer_count"], 1)
        self.assertIn("llm-inference", status["local_node"]["capabilities"])

if __name__ == "__main__":
    unittest.main()
