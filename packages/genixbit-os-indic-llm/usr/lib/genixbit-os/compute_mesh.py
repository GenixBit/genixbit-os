#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — LAN Peer-to-Peer Compute Mesh Discovery & Offloader
import json
import os
import socket
import sys

DEFAULT_PORT = 11435

def discover_local_node():
    hostname = socket.gethostname()
    ip = "127.0.0.1"
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
        
    return {
        "hostname": hostname,
        "ip": ip,
        "port": DEFAULT_PORT,
        "status": "online",
        "capabilities": ["llm-inference", "embeddings", "quantization"],
        "node_id": f"genixbit-node-{hostname.lower()}"
    }

def get_mesh_status():
    local_node = discover_local_node()
    peers = [local_node]
    return {
        "mesh_active": True,
        "local_node": local_node,
        "peer_count": len(peers),
        "peers": peers
    }

if __name__ == "__main__":
    status = get_mesh_status()
    print(json.dumps(status, indent=2))
