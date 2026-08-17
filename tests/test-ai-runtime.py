#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Direct unit test for GenixBit AI Proxy handler methods and responses

import io
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath("packages/genixbit-os-ai-runtime/bin"))

from importlib.machinery import SourceFileLoader
proxy_module = SourceFileLoader("genixbit_ai_proxy", "packages/genixbit-os-ai-runtime/bin/genixbit-ai-proxy").load_module()

class FakeSocket:
    def __init__(self, request_bytes):
        self.rfile = io.BytesIO(request_bytes)
        self.wfile = io.BytesIO()

    def makefile(self, mode, *args, **kwargs):
        if "r" in mode:
            return self.rfile
        elif "w" in mode:
            return self.wfile
        return self.rfile

    def sendall(self, data):
        self.wfile.write(data)

    def close(self):
        pass

def call_handler(method, path, body=None, headers=None):
    if headers is None:
        headers = {}
    body_bytes = json.dumps(body).encode("utf-8") if body is not None else b""
    if body is not None and "Content-Length" not in headers:
        headers["Content-Length"] = str(len(body_bytes))
    if body is not None and "Content-Type" not in headers:
        headers["Content-Type"] = "application/json"

    req_str = f"{method} {path} HTTP/1.1\r\n"
    for k, v in headers.items():
        req_str += f"{k}: {v}\r\n"
    req_str += "\r\n"

    raw_req = req_str.encode("utf-8") + body_bytes
    fake_sock = FakeSocket(raw_req)

    class MockServer:
        pass

    handler = proxy_module.GenixBitAIProxyHandler(fake_sock, ("127.0.0.1", 54321), MockServer())
    resp_bytes = fake_sock.wfile.getvalue()

    # Parse response HTTP status and body
    header_part, _, body_part = resp_bytes.partition(b"\r\n\r\n")
    header_lines = header_part.decode("utf-8", errors="replace").split("\r\n")
    status_line = header_lines[0]
    status_code = int(status_line.split(" ")[1])

    return status_code, body_part.decode("utf-8", errors="replace")

class TestAIProxyHandler(unittest.TestCase):
    def test_health_endpoint(self):
        status, body = call_handler("GET", "/health")
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertEqual(data["status"], "online")
        self.assertEqual(data["service"], "genixbit-ai-proxy")
        self.assertEqual(data["version"], "1.0.0-lts")

    def test_models_endpoint(self):
        status, body = call_handler("GET", "/v1/models")
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertIn("data", data)
        self.assertGreaterEqual(len(data["data"]), 1)
        model_ids = [m["id"] for m in data["data"]]
        self.assertIn("gemma-3-2b-it", model_ids)

    def test_chat_completions_non_streaming(self):
        status, body = call_handler("POST", "/v1/chat/completions", {
            "model": "gemma-3-2b-it",
            "messages": [{"role": "user", "content": "Explain local AI OS"}],
            "stream": False
        })
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertEqual(data["object"], "chat.completion")
        self.assertIn("choices", data)
        content = data["choices"][0]["message"]["content"]
        self.assertIn("GenixBit OS AI Runtime", content)

    def test_chat_completions_streaming(self):
        status, body = call_handler("POST", "/v1/chat/completions", {
            "model": "gemma-3-2b-it",
            "messages": [{"role": "user", "content": "Stream test"}],
            "stream": True
        })
        self.assertEqual(status, 200)
        self.assertIn("data: {", body)
        self.assertIn("data: [DONE]", body)

    def test_embeddings(self):
        status, body = call_handler("POST", "/v1/embeddings", {
            "model": "gemma-3-2b-it",
            "input": "Embedding vector test for Antigravity"
        })
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertEqual(data["object"], "list")
        self.assertEqual(len(data["data"][0]["embedding"]), 128)

if __name__ == "__main__":
    unittest.main()
