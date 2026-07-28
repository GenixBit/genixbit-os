#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Production QMP client for GenixBit OS VM lifecycle.

Supports at least query-status, system-powerdown, and screendump.
Uses a persistent receive buffer that preserves unread bytes between calls.

Usage:
  python3 tools/vm/qmp-client.py --socket SOCKET query-status
  python3 tools/vm/qmp-client.py --socket SOCKET query-active-status
  python3 tools/vm/qmp-client.py --socket SOCKET system-powerdown
  python3 tools/vm/qmp-client.py --socket SOCKET screendump --file PATH
"""

import json
import os
import socket
import stat
import sys
import time
import uuid


class QMPError(RuntimeError):
    """Raised on QMP error responses, protocol violations, or timeouts."""


class QMPConnection:
    """Persistent-buffer QMP connection over a Unix socket.

    The receive buffer is maintained across calls to receive_object(),
    so unread bytes from a previous read are preserved.
    """

    def __init__(self, sock, timeout_seconds=10):
        self.sock = sock
        self.sock.settimeout(timeout_seconds)
        self.buffer = b""
        self.deadline = time.monotonic() + timeout_seconds

    def receive_object(self):
        """Read one complete JSON object from the stream.

        Parses newline-delimited JSON. Ignores empty lines and
        non-dict JSON values. Returns the first complete dict found.
        """
        while time.monotonic() < self.deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(value, dict):
                    return value

            try:
                chunk = self.sock.recv(4096)
            except socket.timeout:
                raise TimeoutError("QMP socket timed out during read")
            except ConnectionResetError:
                raise QMPError("QMP connection reset by peer")

            if not chunk:
                raise QMPError("QMP socket closed before the expected response")

            self.buffer += chunk

        raise TimeoutError("Timed out waiting for QMP response")

    def send_request(self, execute, arguments=None, request_id=None):
        """Send a QMP request and wait for its response.

        Returns the response dict. Ignores asynchronous events and
        unrelated response IDs.
        """
        if request_id is None:
            request_id = str(uuid.uuid4())

        req = {"execute": execute, "id": request_id}
        if arguments is not None:
            req["arguments"] = arguments

        self.sock.sendall(json.dumps(req).encode() + b"\n")

        while True:
            response = self.receive_object()

            if "error" in response and response.get("id") == request_id:
                error_desc = response["error"].get("desc", str(response["error"]))
                raise QMPError(
                    f"QMP {execute} failed: {error_desc}"
                )

            if response.get("id") == request_id:
                return response

    def handshake(self):
        """Perform QMP capability negotiation. Returns the greeting."""
        greeting = self.receive_object()
        if not isinstance(greeting, dict) or "QMP" not in greeting:
            raise QMPError("Missing or invalid QMP greeting")

        caps_id = f"caps-{uuid.uuid4()}"
        self.sock.sendall(
            json.dumps({"execute": "qmp_capabilities", "id": caps_id}).encode()
            + b"\n"
        )

        while True:
            response = self.receive_object()
            if response.get("id") == caps_id:
                if "error" in response:
                    raise QMPError(
                        f"qmp_capabilities failed: {response['error']}"
                    )
                break

        return greeting

    def query_status(self):
        """Query VM status. Returns the status string (running, prelaunch, etc.)."""
        status_id = f"status-{uuid.uuid4()}"
        response = self.send_request("query-status", request_id=status_id)
        status = response.get("return", {}).get("status", "")
        if status not in ("running", "prelaunch", "shutdown", "stop", "inmigrate",
                          "postmigrate", "colo", "guest-panicked"):
            raise QMPError(f"Unexpected QMP status: {status!r}")
        return status

    def query_active_status(self):
        """Query status and require a VM state that is active for readiness."""
        status = self.query_status()
        if status not in {"running", "prelaunch"}:
            raise QMPError(f"VM is not active for readiness: {status!r}")
        return status

    def system_powerdown(self):
        """Request system powerdown. Returns the response."""
        return self.send_request("system_powerdown")

    def screendump(self, filename):
        """Capture a PPM screendump. Returns the response."""
        return self.send_request("screendump", arguments={"filename": filename})

    def close(self):
        """Close the socket."""
        try:
            self.sock.close()
        except OSError:
            pass


def connect(socket_path, timeout=10):
    """Connect to a QMP Unix socket, perform handshake, return QMPConnection."""
    if not os.path.exists(socket_path):
        raise QMPError(f"QMP socket not found: {socket_path}")
    if not stat.S_ISSOCK(os.stat(socket_path).st_mode):
        raise QMPError(f"Not a socket: {socket_path}")

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(socket_path)
    except (ConnectionRefusedError, FileNotFoundError) as exc:
        sock.close()
        raise QMPError(f"QMP connection failed: {exc}")

    conn = QMPConnection(sock, timeout)
    conn.handshake()
    return conn


def main():
    socket_path = ""
    command = ""
    timeout = 10
    screendump_file = ""

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--socket" and i + 1 < len(args):
            socket_path = args[i + 1]
            i += 2
        elif args[i] == "--timeout" and i + 1 < len(args):
            timeout = int(args[i + 1])
            i += 2
        elif args[i] == "--file" and i + 1 < len(args):
            screendump_file = args[i + 1]
            i += 2
        elif args[i] in ("query-status", "query-active-status", "system-powerdown", "screendump"):
            command = args[i]
            i += 1
        else:
            print(f"Unknown argument: {args[i]}", file=sys.stderr)
            sys.exit(2)

    if not socket_path:
        print("Usage: qmp-client.py --socket SOCKET [--timeout SEC] <command> [args]", file=sys.stderr)
        sys.exit(2)

    if not command:
        print("No command specified. Use: query-status | query-active-status | system-powerdown | screendump", file=sys.stderr)
        sys.exit(2)

    try:
        conn = connect(socket_path, timeout=timeout)
        if command == "query-status":
            status = conn.query_status()
            print(status)
        elif command == "query-active-status":
            status = conn.query_active_status()
            print(status)
        elif command == "system-powerdown":
            conn.system_powerdown()
            print("OK")
        elif command == "screendump":
            if not screendump_file:
                print("screendump requires --file argument", file=sys.stderr)
                sys.exit(2)
            conn.screendump(screendump_file)
            print("OK")
        else:
            print(f"Unknown command: {command}", file=sys.stderr)
            sys.exit(2)
    except (QMPError, TimeoutError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        if "conn" in locals():
            conn.close()


if __name__ == "__main__":
    main()
