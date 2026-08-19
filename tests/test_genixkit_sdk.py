#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import os
import shutil
import tempfile
import unittest
import sys

sys.path.insert(0, os.path.abspath("packages/genixbit-os-agents/usr/lib/genixbit-os"))
from genixkit import GenixApp, GenixAI, GenixSecurity, Permission, AppStorage

class TestGenixKitSDK(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="genixkit_test_")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_app_lifecycle(self):
        events = []
        class MyApp(GenixApp):
            def on_launch(self):
                events.append("launch")
            def on_suspend(self):
                events.append("suspend")
            def on_resume(self):
                events.append("resume")
            def on_terminate(self):
                events.append("terminate")

        app = MyApp("com.genixbit.testapp", "TestApp")
        app.run()
        self.assertIn("launch", events)
        app.on_suspend()
        self.assertIn("suspend", events)
        app.on_resume()
        self.assertIn("resume", events)
        app.on_terminate()
        self.assertIn("terminate", events)

    def test_security_permissions(self):
        audit_p = os.path.join(self.test_dir, "audit.jsonl")
        sec = GenixSecurity("com.genixbit.testsec", audit_log_path=audit_p)
        self.assertFalse(sec.check_permission(Permission.READ_FILE))
        
        granted = sec.request_permission(Permission.READ_FILE, reason="Read user document")
        self.assertTrue(granted)
        self.assertTrue(sec.check_permission(Permission.READ_FILE))
        self.assertTrue(os.path.exists(audit_p))

    def test_app_storage(self):
        store_p = os.path.join(self.test_dir, "storage")
        storage = AppStorage("com.genixbit.teststore", custom_dir=store_p)
        storage.set_key("theme_accent", "cyber_cyan")
        self.assertEqual(storage.get_key("theme_accent"), "cyber_cyan")
        self.assertEqual(storage.get_key("nonexistent", 42), 42)

    def test_ai_client(self):
        ai = GenixAI("http://127.0.0.1:99999") # Offline fallback test
        resp = ai.chat("Hello AI")
        self.assertIn("Hello AI", resp)

    def test_genix_system(self):
        from genixkit import GenixSystem
        rel = GenixSystem.get_os_release()
        self.assertEqual(rel["name"], "GenixBit OS")
        self.assertEqual(rel["id"], "genixbit")
        self.assertTrue(len(GenixSystem.get_hostname()) > 0)
        self.assertIn(GenixSystem.get_active_theme(), ["dark", "light"])

    def test_genix_ipc(self):
        from genixkit import GenixIPC
        ipc = GenixIPC("test_channel")
        self.assertTrue(ipc.send_message("test_app", {"action": "ping"}))
        msgs = ipc.read_messages()
        self.assertTrue(len(msgs) >= 1)
        self.assertEqual(msgs[-1]["payload"]["action"], "ping")

if __name__ == "__main__":
    unittest.main()
