#!/usr/bin/env python3
"""End-to-end ACP test for Parallax daemon."""
import json
import os
import socket
import sys
import time

SOCK_PATH = f"/tmp/parallax-{os.getuid()}.sock"

class DaemonClient:
    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(SOCK_PATH)
        self.sock.settimeout(30)
        self.buf = b""
        self.req_id = 0

    def send(self, method, params=None):
        self.req_id += 1
        msg = {"jsonrpc": "2.0", "id": self.req_id, "method": method}
        if params:
            msg["params"] = params
        data = json.dumps(msg) + "\n"
        self.sock.sendall(data.encode())
        return self.req_id

    def read_line(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("disconnected")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def call(self, method, params=None):
        req_id = self.send(method, params)
        # Read until we get response with matching id
        notifications = []
        while True:
            msg = self.read_line()
            if "id" in msg and msg["id"] == req_id:
                return msg, notifications
            else:
                notifications.append(msg)

    def read_notifications(self, timeout=15):
        """Read notifications until timeout."""
        self.sock.settimeout(1)
        notifications = []
        end = time.time() + timeout
        while time.time() < end:
            try:
                msg = self.read_line()
                notifications.append(msg)
                print(f"  << {msg.get('method', 'response')}: {json.dumps(msg.get('params', msg.get('result', msg.get('error'))))}")
            except socket.timeout:
                continue
            except Exception:
                break
        self.sock.settimeout(30)
        return notifications

    def close(self):
        self.sock.close()

def main():
    c = DaemonClient()

    # Ping
    resp, _ = c.call("ping")
    print(f"1. Ping: {resp['result']}")

    # Add project (or use existing)
    resp, _ = c.call("project/add", {"repo_path": "/tmp/parallax-test-repo"})
    if "error" in resp:
        # Project may already exist, try listing
        resp2, _ = c.call("project/list")
        projects = resp2.get("result", [])
        match = [p for p in projects if p["repo_path"] == "/tmp/parallax-test-repo"]
        if not match:
            print(f"2. Add project ERROR: {resp['error']}")
            return
        pid = match[0]["id"]
        print(f"2. Using existing project: {match[0]['name']}")
    else:
        pid = resp["result"]["id"]
        print(f"2. Project added: {resp['result']['name']}")

    # Create worktree (use timestamp for unique branch)
    import hashlib
    branch = f"feature/acp-{int(time.time()) % 100000}"
    resp, notifs = c.call("worktree/create", {
        "project_id": pid,
        "branch": branch,
        "source_branch": "main"
    })
    if "error" in resp:
        # Try listing existing worktrees
        resp2, _ = c.call("worktree/list", {"project_id": pid})
        wts = resp2.get("result", [])
        if wts:
            wtid = wts[0]["id"]
            print(f"3. Using existing worktree: {wts[0]['path']}")
        else:
            print(f"3. Create worktree ERROR: {resp['error']}")
            return
    else:
        wtid = resp["result"]["id"]
        print(f"3. Worktree created: {resp['result']['path']}")

    # Create session
    resp, _ = c.call("session/create", {
        "worktree_id": wtid,
        "agent_type": "claude_code"
    })
    if "error" in resp:
        print(f"4. Create session ERROR: {resp['error']}")
        return
    sid = resp["result"]["id"]
    print(f"4. Session created: {sid} (state: {resp['result']['state']})")

    # Send prompt
    print(f"5. Sending prompt...")
    resp, notifs = c.call("session/prompt", {
        "session_id": sid,
        "prompt": "Say hello world in one sentence. Be very brief."
    })
    if "error" in resp:
        print(f"   Prompt ERROR: {resp['error']}")
        for n in notifs:
            print(f"   Notification: {n.get('method')}: {n.get('params')}")
    else:
        print(f"   Prompt accepted: round {resp['result'].get('round_number')}")

    # Read streaming notifications
    print("6. Reading notifications for 15s...")
    notifs = c.read_notifications(timeout=15)

    # Check final state
    resp, _ = c.call("session/get", {"session_id": sid})
    state = resp["result"]["state"] if "result" in resp else "unknown"
    print(f"7. Final session state: {state}")

    c.close()

    # Show daemon logs
    print("\n=== DAEMON LOGS (agent-related) ===")
    try:
        with open("/tmp/parallax-daemon.log") as f:
            for line in f:
                if any(k in line.lower() for k in ["agent", "acp", "error", "stderr", "spawn", "initialize", "session"]):
                    # Strip ANSI codes
                    import re
                    clean = re.sub(r'\x1b\[[0-9;]*m', '', line.rstrip())
                    print(f"  {clean}")
    except FileNotFoundError:
        print("  (no log file)")

if __name__ == "__main__":
    main()
