#!/usr/bin/env python3
"""Phase 2 Step 1 smoke test: TLS auth + token attach + player data load."""
import socket
import ssl
import json
import time

AUTH_HOST = "127.0.0.1"
AUTH_PORT = 8444
DB_HOST = "127.0.0.1"
DB_PORT = 54321
INSTANCE_ID = "test-instance-001"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def https_post(path, body_dict):
    body = json.dumps(body_dict)
    with socket.create_connection((AUTH_HOST, AUTH_PORT), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname="localhost") as ssock:
            req = (
                f"POST {path} HTTP/1.1\r\n"
                f"Host: {AUTH_HOST}:{AUTH_PORT}\r\n"
                f"Content-Type: application/json\r\n"
                f"Content-Length: {len(body)}\r\n"
                f"\r\n{body}"
            )
            ssock.sendall(req.encode("utf-8"))
            # Read until connection closed (HTTP/1.0)
            resp = b""
            while True:
                chunk = ssock.recv(4096)
                if not chunk:
                    break
                resp += chunk
    resp_str = resp.decode("utf-8", errors="replace")
    # Extract JSON body from HTTP response
    body_start = resp_str.index("{")
    return json.loads(resp_str[body_start:])

def db_send(method, payload):
    with socket.create_connection((DB_HOST, DB_PORT), timeout=5) as sock:
        msg = json.dumps({"method": method, **payload}) + "\n"
        sock.sendall(msg.encode("utf-8"))
        data = sock.recv(65536).decode("utf-8")
    return json.loads(data.strip())

uname = f"t2_{int(time.time())}"

# 1. Register
r = https_post("/register", {"username": uname, "password": "TestPass123!", "faction": 1, "callsign": uname})
assert r.get("ok") == True, f"Register failed: {r}"
print("[PASS] Register: account_id=%d" % r["account_id"])

# 2. Login
r = https_post("/login", {"username": uname, "password": "TestPass123!"})
assert r.get("ok") == True, f"Login failed: {r}"
token = r["session_token"]
acct_id = r["account_id"]
print("[PASS] Login: account_id=%d, token=%s..." % (acct_id, token[:30]))

# 3. Wrong password
r = https_post("/login", {"username": uname, "password": "WrongPass!"})
assert r.get("ok") == False, f"Wrong password should fail: {r}"
print("[PASS] Wrong password rejected")

# 4. Verify token via server_db
r = db_send("verify_and_consume_token", {"session_token": token, "instance_id": INSTANCE_ID})
assert r.get("ok") == True, f"Token verify failed: {r}"
print("[PASS] Token verify: account_id=%d" % r["account_id"])

# 5. Load player state
r = db_send("load_player_state", {"account_id": acct_id})
assert r.get("ok") == True, f"Load player state failed: {r}"
ps = r["player_state"]
assert ps["cr"] == 5000, f"Expected cr=5000, got {ps['cr']}"
assert ps["ship"] == "phoenix", f"Expected ship=phoenix, got {ps['ship']}"
assert ps["uri"] == 0, f"Expected uri=0, got {ps['uri']}"
print("[PASS] Load player state: cr=%d, ship=%s, uri=%d" % (ps["cr"], ps["ship"], ps["uri"]))

# 6. Idempotency: same token again should fail (used_tokens)
r = db_send("verify_and_consume_token", {"session_token": token, "instance_id": INSTANCE_ID})
assert r.get("ok") == False, f"Used token should be rejected: {r}"
print("[PASS] Used token rejected (idempotency)")

print()
print("=== TUM TESTLER BASARILI ===")
