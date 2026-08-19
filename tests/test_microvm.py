#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit MicroVM, Quantization Engine & LoRA Manager."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-microvm/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import microvm_runner
import quantization_engine
import lora_manager

class TestMicroVM(unittest.TestCase):
    def test_microvm_boot_execution(self):
        res = microvm_runner.run_in_microvm(["echo", "MicroVM Boot Test"])
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["exit_code"], 0)
        self.assertLess(res["boot_time_ms"], 250)
        self.assertIn("MicroVM Boot Test", res["stdout"])

    def test_quantization_calculation(self):
        res = quantization_engine.quantize_model("deepseek-r1-7b", "Q4_K_M")
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["quant_type"], "Q4_K_M")
        self.assertGreater(res["estimated_size_gb"], 0)

    def test_quantization_invalid_type(self):
        with self.assertRaises(ValueError):
            quantization_engine.quantize_model("test-model", "INVALID_FORMAT")

    def test_lora_adapters_list_and_swap(self):
        adapters = lora_manager.list_active_adapters()
        self.assertGreater(len(adapters), 0)

        swap_res = lora_manager.swap_adapter("lora-coder-v1")
        self.assertEqual(swap_res["status"], "success")
        self.assertFalse(swap_res["reload_required"])

if __name__ == "__main__":
    unittest.main()
