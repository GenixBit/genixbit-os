# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit Sandboxed App Storage

import json
import os

class AppStorage:
    def __init__(self, app_id, custom_dir=None):
        self.app_id = app_id
        self.base_dir = custom_dir or os.path.expanduser(f"~/.local/share/genixbit/app-data/{app_id}")
        self.config_path = os.path.join(self.base_dir, "config.json")
        try:
            os.makedirs(self.base_dir, exist_ok=True)
        except Exception:
            pass
        self._data = self._load()

    def _load(self):
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return {}
        return {}

    def _save(self):
        try:
            os.makedirs(self.base_dir, exist_ok=True)
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._data, f, indent=2)
        except Exception:
            pass

    def set_key(self, key, value):
        self._data[key] = value
        self._save()

    def get_key(self, key, default=None):
        return self._data.get(key, default)

    def get_data_dir(self):
        return self.base_dir
