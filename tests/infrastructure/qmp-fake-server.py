#!/usr/bin/env python3
"""Fake QMP Unix socket server for testing qmp-client.py.

Matches client-generated UUID request IDs in responses.
"""

import json
import os
import socket
import sys
import time


def recv_json(conn):
    """Read one newline-delimited JSON object from connection."""
    buf = b""
    while True:
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
        chunk = conn.recv(4096)
        if not chunk:
            raise ConnectionError("Client disconnected")
        buf += chunk


def respond_ok(conn, req, extra=None):
    """Send OK response for a request, using its ID."""
    resp = {"id": req.get("id"), "return": extra or {}}
    conn.sendall(json.dumps(resp).encode() + b"\n")


def respond_error(conn, req, error_class="GenericError", desc="error"):
    """Send error response for a request, using its ID."""
    resp = {"id": req.get("id"), "error": {"class": error_class, "desc": desc}}
    conn.sendall(json.dumps(resp).encode() + b"\n")


def wait_sendall(conn, data, delay=0):
    """Send data, optionally with a delay before."""
    if delay > 0:
        time.sleep(delay)
    conn.sendall(data)


def serve(sock_path, scenario, status="running"):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        os.unlink(sock_path)
    except OSError:
        pass
    sock.bind(sock_path)
    sock.listen(1)
    sock.settimeout(10)
    conn, _ = sock.accept()
    conn.settimeout(5)

    if scenario == "one_write":
        greeting = json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}})
        # Send greeting; caps req comes next but we don't read it
        conn.sendall(greeting.encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        respond_ok(conn, req, {"status": status})

    elif scenario == "split":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        # Split the JSON response across two writes
        req_id = req.get("id")
        conn.sendall(f'{{"id": "{req_id}", "ret'.encode())
        time.sleep(0.3)
        conn.sendall(f'urn": {{"status": "{status}"}}}}'.encode() + b"\n")

    elif scenario == "caps_together":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req2 = recv_json(conn)
        # Send status response — both responses arrive in same recv buffer
        respond_ok(conn, req2, {"status": status})

    elif scenario == "async_event":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        # Send async event first, then status response
        conn.sendall(json.dumps({"event": "STOP", "data": {}}).encode() + b"\n")
        respond_ok(conn, req, {"status": status})

    elif scenario == "wrong_id":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        # Send a stale response with wrong ID first
        wrong = json.dumps({"id": "stale-1", "return": {"status": "shutdown"}})
        conn.sendall(wrong.encode() + b"\n")
        respond_ok(conn, req, {"status": status})

    elif scenario == "misleading_greeting":
        conn.sendall(json.dumps({
            "QMP": {"version": {"qemu": {"major": 8}},
                    "capabilities": {"status": "running"}}
        }).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        respond_ok(conn, req, {"status": status})

    elif scenario == "error_desc":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        respond_error(conn, req, "DeviceNotFound", "Device was running but state unknown")

    elif scenario == "error_response":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        respond_error(conn, req, "GenericError", "not found")

    elif scenario == "malformed_json":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req1 = recv_json(conn)
        respond_ok(conn, req1)
        conn.sendall(b"not valid json at all\n")
        req2 = recv_json(conn)
        respond_ok(conn, req2, {"status": status})

    elif scenario == "premature_eof":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        # Close without responding to query-status

    elif scenario == "timeout":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        time.sleep(6)

    elif scenario == "powerdown":
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        respond_ok(conn, req)

    else:
        # Standard
        conn.sendall(json.dumps({"QMP": {"version": {"qemu": {"major": 8}}}}).encode() + b"\n")
        req = recv_json(conn)
        respond_ok(conn, req)
        req = recv_json(conn)
        respond_ok(conn, req, {"status": status})

    time.sleep(0.2)
    conn.close()
    sock.close()


def main():
    args = sys.argv[1:]

    scenario = "standard"
    if args and args[0].startswith("--"):
        scenario = args[0].lstrip("-").replace("-", "_")
        args = args[1:]

    sock_path = args[0]
    status = args[1] if len(args) > 1 else "running"

    try:
        os.unlink(sock_path)
    except FileNotFoundError:
        pass
    serve(sock_path, scenario, status)


if __name__ == "__main__":
    main()
