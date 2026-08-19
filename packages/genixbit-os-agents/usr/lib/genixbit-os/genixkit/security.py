# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit Security & Permission Model

import enum
import json
import os
import sys

class Permission(enum.Enum):
    READ_FILE = "READ_FILE"
    WRITE_FILE = "WRITE_FILE"
    EXECUTE_COMMAND = "EXECUTE_COMMAND"
    OPEN_APPLICATION = "OPEN_APPLICATION"
    CHANGE_SETTING = "CHANGE_SETTING"
    ACCESS_MICROPHONE = "ACCESS_MICROPHONE"
    ACCESS_CAMERA = "ACCESS_CAMERA"
    NETWORK_REQUEST = "NETWORK_REQUEST"
    SCREEN_CAPTURE = "SCREEN_CAPTURE"

DEFAULT_AUDIT_LOG = os.path.expanduser("~/.local/share/genixbit/audit/ai_permissions.jsonl")

class GenixSecurity:
    def __init__(self, app_id, audit_log_path=None):
        self.app_id = app_id
        self.audit_log_path = audit_log_path or DEFAULT_AUDIT_LOG
        self.granted_permissions = set()
        try:
            os.makedirs(os.path.dirname(self.audit_log_path), exist_ok=True)
        except Exception:
            pass

    def request_permission(self, permission: Permission, reason="Application operation"):
        perm_str = permission.value if isinstance(permission, Permission) else str(permission)
        granted = True
        self.granted_permissions.add(perm_str)
        self._log_audit(perm_str, reason, granted)
        return granted

    def check_permission(self, permission: Permission):
        perm_str = permission.value if isinstance(permission, Permission) else str(permission)
        return perm_str in self.granted_permissions

    def _log_audit(self, perm_str, reason, granted):
        entry = {
            "app_id": self.app_id,
            "permission": perm_str,
            "reason": reason,
            "granted": granted,
            "timestamp": int(__import__("time").time())
        }
        try:
            with open(self.audit_log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")
        except Exception as e:
            sys.stderr.write(f"[GenixSecurity] Audit log write skipped: {e}\n")
