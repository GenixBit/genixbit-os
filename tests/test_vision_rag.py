#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit Multimodal Vision & Vector RAG."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-vision-rag/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import vision_engine
import vector_rag

class TestVisionRAG(unittest.TestCase):
    def test_desktop_ui_inspection(self):
        res = vision_engine.inspect_desktop_ui()
        self.assertEqual(res["status"], "success")
        self.assertGreaterEqual(res["confidence"], 0.95)
        self.assertGreater(len(res["elements_detected"]), 0)

    def test_ocr_processing(self):
        res = vision_engine.perform_ocr("test.png")
        self.assertEqual(res["status"], "success")
        self.assertIn("GenixBit", res["text_detected"])

    def test_vector_rag_search(self):
        res = vector_rag.search_rag("proxy port 11434")
        self.assertEqual(res["embedding_dimensions"], 1024)
        self.assertGreater(res["matches_found"], 0)
        self.assertIn("Proxy", res["results"][0]["title"])

if __name__ == "__main__":
    unittest.main()
