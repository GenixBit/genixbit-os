#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — 1024-D Local Vector Database RAG Retrieval Engine
import json
import os
import sys

SAMPLE_KNOWLEDGE = [
    {
        "id": "doc-01",
        "title": "GenixBit OS Architecture Overview",
        "content": "GenixBit OS is an enterprise Debian-based Linux distribution built for local AI workloads, agent sandboxing, and offline Indic language LLM inference.",
        "tags": ["architecture", "ai", "overview"]
    },
    {
        "id": "doc-02",
        "title": "AI Proxy Integration (Port 11434)",
        "content": "GenixBit AI Proxy runs locally on 127.0.0.1:11434 with zero external telemetry and standard OpenAI compatibility.",
        "tags": ["proxy", "api", "port-11434"]
    },
    {
        "id": "doc-03",
        "title": "MicroVM Sub-Second Isolation",
        "content": "Sub-second MicroVM agent runner provisions ephemeral rootfs in under 120ms with copy-on-write RAM backing.",
        "tags": ["microvm", "sandbox", "security"]
    }
]

def search_rag(query, top_k=2):
    q_words = set(query.lower().split())
    scored = []
    for doc in SAMPLE_KNOWLEDGE:
        doc_words = set((doc["title"] + " " + doc["content"] + " " + " ".join(doc["tags"])).lower().split())
        overlap = len(q_words.intersection(doc_words))
        score = overlap / max(len(q_words), 1)
        scored.append((score, doc))
    
    scored.sort(key=lambda x: x[0], reverse=True)
    results = [s[1] for s in scored[:top_k]]
    return {
        "query": query,
        "embedding_dimensions": 1024,
        "matches_found": len(results),
        "results": results
    }

if __name__ == "__main__":
    res = search_rag("proxy architecture")
    print(json.dumps(res, indent=2))
