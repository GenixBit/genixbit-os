# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit IPC Abstraction API (GenixIPC)
import json
import os
import tempfile
import time

class GenixIPC:
    """
    GenixIPC provides a decoupled inter-process messaging transport abstraction.
    Applications publish and subscribe through this interface without direct binding
    to D-Bus, Unix Domain Sockets, or shared memory implementations.
    """
    def __init__(self, channel_name="default"):
        self.channel_name = channel_name
        self.ipc_dir = os.path.join(tempfile.gettempdir(), "genixbit_ipc")
        os.makedirs(self.ipc_dir, exist_ok=True)
        self.channel_file = os.path.join(self.ipc_dir, f"{channel_name}.ipc")

    def send_message(self, sender_id, payload):
        msg = {
            "sender": sender_id,
            "timestamp": time.time(),
            "payload": payload
        }
        with open(self.channel_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(msg) + "\n")
        return True

    def read_messages(self):
        if not os.path.exists(self.channel_file):
            return []
        messages = []
        with open(self.channel_file, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    try:
                        messages.append(json.loads(line.strip()))
                    except Exception:
                        pass
        return messages
