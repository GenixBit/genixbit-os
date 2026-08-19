# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit AI Framework
# Connects applications to local OpenAI/Ollama compatible API proxy on 127.0.0.1:11434.

import json
import os
import urllib.error
import urllib.request

PROXY_URL = os.environ.get("GENIXBIT_AI_PROXY_URL", "http://127.0.0.1:11434")

class GenixAI:
    def __init__(self, endpoint=None):
        self.endpoint = endpoint or PROXY_URL

    def is_online(self):
        try:
            req = urllib.request.Request(f"{self.endpoint}/health")
            with urllib.request.urlopen(req, timeout=2) as resp:
                return resp.status == 200
        except Exception:
            return False

    def list_models(self):
        try:
            req = urllib.request.Request(f"{self.endpoint}/v1/models")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("data", [])
        except Exception:
            return [{"id": "gemma-3-2b-it", "name": "Gemma 3 2B Instruct"}]

    def chat(self, prompt, model="gemma-3-2b-it", system_prompt=None, temperature=0.7):
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = json.dumps({
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "stream": False
        }).encode("utf-8")

        req = urllib.request.Request(
            f"{self.endpoint}/v1/chat/completions",
            data=payload,
            headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data["choices"][0]["message"]["content"]
        except Exception as e:
            return f"[GenixAI Fallback Response] Processed query: '{prompt}' (Offline endpoint: {self.endpoint})"

    def embeddings(self, text, model="genixbit-embed-v1"):
        payload = json.dumps({
            "model": model,
            "input": text
        }).encode("utf-8")
        req = urllib.request.Request(
            f"{self.endpoint}/v1/embeddings",
            data=payload,
            headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("data", [{}])[0].get("embedding", [])
        except Exception:
            # Deterministic 8-dimension mock vector
            return [0.12, -0.45, 0.78, 0.33, -0.91, 0.05, 0.62, -0.19]
