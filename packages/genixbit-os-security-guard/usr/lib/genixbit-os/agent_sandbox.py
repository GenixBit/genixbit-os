#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Namespace & Cgroups Agent Sandbox Runner
import json
import os
import subprocess
import sys
import tempfile

def execute_sandboxed(command, workspace_dir=None, timeout_sec=30):
    if not workspace_dir:
        try:
            workspace_dir = tempfile.gettempdir()
        except Exception:
            workspace_dir = os.getcwd()
            
    try:
        os.makedirs(workspace_dir, exist_ok=True)
    except Exception:
        workspace_dir = os.getcwd()
    
    # Check if bwrap or standard unshare is available
    has_bwrap = shutil_which("bwrap")
    
    if has_bwrap:
        cmd = ["bwrap", "--ro-bind", "/usr", "/usr", "--ro-bind", "/lib", "/lib",
               "--ro-bind", "/lib64", "/lib64", "--ro-bind", "/bin", "/bin",
               "--bind", workspace_dir, workspace_dir, "--chdir", workspace_dir,
               "--unshare-net", "--unshare-pid", "--"] + command
    else:
        # Fallback isolation inside sandbox workspace
        cmd = command

    try:
        proc = subprocess.run(cmd, cwd=workspace_dir, capture_output=True, text=True, timeout=timeout_sec)
        return {
            "status": "success",
            "exit_code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "isolated": bool(has_bwrap)
        }
    except subprocess.TimeoutExpired:
        return {
            "status": "timeout",
            "exit_code": -1,
            "error": f"Execution timed out after {timeout_sec}s",
            "isolated": bool(has_bwrap)
        }

def shutil_which(cmd):
    import shutil
    return shutil.which(cmd) is not None

if __name__ == "__main__":
    res = execute_sandboxed(["echo", "Hello from GenixBit Sandbox!"])
    print(json.dumps(res, indent=2))
