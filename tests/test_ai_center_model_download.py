#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Deterministic integrity tests for the GenixBit AI Center model downloader."""

from __future__ import annotations

import hashlib
import http.server
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import threading
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
AI_CENTER = REPO_ROOT / "packages/genixbit-os-ai-center/bin/genixbit-ai-center"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return


class ModelDownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server_root = tempfile.TemporaryDirectory()
        cls.root_path = pathlib.Path(cls.server_root.name)
        handler = lambda *args, **kwargs: QuietHandler(  # noqa: E731
            *args, directory=cls.server_root.name, **kwargs
        )
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.server_thread.join(timeout=5)
        cls.server_root.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.temp_path = pathlib.Path(self.temp.name)
        self.cache = self.temp_path / "cache"
        self.catalog = self.temp_path / "catalog.json"

    def tearDown(self):
        self.temp.cleanup()

    def write_catalog(self, *, model_id, source_url, sha256, quantization="Q4_TEST"):
        self.catalog.write_text(
            json.dumps(
                {
                    "catalog_version": "ci",
                    "models": [
                        {
                            "id": model_id,
                            "name": "CI Test Model",
                            "family": "CI",
                            "parameters": "tiny",
                            "license": "test-only",
                            "recommended_vram_gb": 0,
                            "recommended_ram_gb": 0,
                            "quantization": quantization,
                            "size_mb": 0,
                            "sha256": sha256,
                            "download_url": source_url,
                            "description": "Deterministic downloader fixture",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

    def run_pull(self, model_id):
        env = os.environ.copy()
        env.update(
            {
                "GENIXBIT_MODEL_CATALOG": str(self.catalog),
                "GENIXBIT_MODELS_CACHE_DIR": str(self.cache),
                "GENIXBIT_MODEL_DOWNLOAD_TIMEOUT": "5",
            }
        )
        return subprocess.run(
            ["python3", str(AI_CENTER), "pull", model_id],
            env=env,
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )

    def install_path(self, model_id, quantization="Q4_TEST"):
        return self.cache / f"{model_id}-{quantization}.gguf"

    def test_downloads_verifies_and_atomically_installs_real_bytes(self):
        model_id = "ci-good"
        payload = b"GGUF" + b"\x00\x00\x00\x03" + (b"verified-model-bytes" * 64)
        source = self.root_path / "good.gguf"
        source.write_bytes(payload)
        digest = hashlib.sha256(payload).hexdigest()
        self.write_catalog(
            model_id=model_id,
            source_url=f"{self.base_url}/good.gguf",
            sha256=digest,
        )

        result = self.run_pull(model_id)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = self.install_path(model_id)
        self.assertEqual(installed.read_bytes(), payload)
        self.assertEqual(stat.S_IMODE(installed.stat().st_mode), 0o600)
        self.assertFalse(list(self.cache.glob("*.part.*")))
        self.assertIn("verified SHA256", result.stdout)

    def test_checksum_mismatch_fails_closed_and_leaves_no_artifact(self):
        model_id = "ci-bad-sha"
        payload = b"GGUF" + b"checksum-mismatch"
        source = self.root_path / "bad-sha.gguf"
        source.write_bytes(payload)
        self.write_catalog(
            model_id=model_id,
            source_url=f"{self.base_url}/bad-sha.gguf",
            sha256="0" * 64,
        )

        result = self.run_pull(model_id)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.install_path(model_id).exists())
        self.assertFalse(list(self.cache.glob("*.part.*")))
        self.assertIn("SHA256 mismatch", result.stdout)

    def test_non_gguf_payload_is_rejected_even_with_matching_checksum(self):
        model_id = "ci-not-gguf"
        payload = b"NOTG" + b"not-a-model"
        source = self.root_path / "not-gguf.bin"
        source.write_bytes(payload)
        self.write_catalog(
            model_id=model_id,
            source_url=f"{self.base_url}/not-gguf.bin",
            sha256=hashlib.sha256(payload).hexdigest(),
        )

        result = self.run_pull(model_id)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.install_path(model_id).exists())
        self.assertIn("not a GGUF model", result.stdout)

    def test_non_loopback_plain_http_source_is_rejected_before_download(self):
        model_id = "ci-insecure"
        self.write_catalog(
            model_id=model_id,
            source_url="http://example.com/model.gguf",
            sha256="1" * 64,
        )

        result = self.run_pull(model_id)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.install_path(model_id).exists())
        self.assertIn("unsupported or insecure download URL", result.stdout)

    def test_verified_cache_is_accepted_without_network_access(self):
        model_id = "ci-cached"
        payload = b"GGUF" + b"cached-model"
        self.cache.mkdir(mode=0o700)
        installed = self.install_path(model_id)
        installed.write_bytes(payload)
        os.chmod(installed, 0o600)
        self.write_catalog(
            model_id=model_id,
            source_url="https://127.0.0.1:1/not-needed.gguf",
            sha256=hashlib.sha256(payload).hexdigest(),
        )

        result = self.run_pull(model_id)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(installed.read_bytes(), payload)
        self.assertIn("Existing cached model has the expected SHA256", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
