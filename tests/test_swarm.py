#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for GenixBit Multi-Agent Swarm & Pipeline Engine."""
import os
import sys
import unittest

PKG_LIB = os.path.join(os.path.dirname(__file__), "../packages/genixbit-os-swarm/usr/lib/genixbit-os")
if PKG_LIB not in sys.path:
    sys.path.insert(0, PKG_LIB)

import swarm_coordinator
import pipeline_engine

class TestSwarm(unittest.TestCase):
    def test_swarm_task_coordination(self):
        res = swarm_coordinator.coordinate_task("Develop authentication module")
        self.assertEqual(res["status"], "success")
        self.assertIn("Planner", res["active_roles"])
        self.assertIn("Coder", res["active_roles"])
        self.assertIn("Tester", res["active_roles"])
        self.assertEqual(len(res["workflow"]), 5)

    def test_pipeline_execution(self):
        res = pipeline_engine.run_pipeline("pre-release-gate")
        self.assertEqual(res["status"], "success")
        self.assertTrue(res["all_passed"])
        self.assertGreaterEqual(res["total_stages"], 5)

if __name__ == "__main__":
    unittest.main()
