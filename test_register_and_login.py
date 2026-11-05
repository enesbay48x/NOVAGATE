import urllib.request
import urllib.parse
import json
import socket
import ssl
import sys
import time

import os
import re

ctx = ssl._create_unverified_context()


def _read_proto() -> int:
    """Sunucudaki net.gd'den PROTO degerini okur (login kapisi MIN_CLIENT_PROTO ister)."""
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (here, "/opt/novagate", os.getcwd()):
        try:
            with open(os.path.join(d, "net.gd"), encoding="utf-8") as f:
                m = re.search(r"const\s+PROTO\s*:?=\s*(\d+)", f.read())
            if m:
                return int(m.group(1))
        except OSError:
            continue
    return 9


PROTO = _read_proto()

username = "testplayer" + str(int(time.time()))[-6:]
print("Using username:", username)

# Step 1: Register a new test account via HTTPS
reg_url = "https://127.0.0.1:8444/register"
reg_data = json.dumps({
    "username": username,
    "password": "testpass123",
    "faction": 2,
    "callsign": "TestPilot"
}).encode()

try:
    req = urllib.request.Request(reg_url, data=reg_data, headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, context=ctx)
    body = json.loads(resp.read().decode())
    print("Register response:", body)
    if not body.get("ok"):
        print("REGISTER FAILED:", body.get("error"))
        sys.exit(1)
    account_id = body["account_id"]
    print("Registered account_id:", account_id)
except Exception as e:
    print("HTTPS register error:", e)
    sys.exit(1)

# Step 2: Login via HTTPS to get session token
login_url = "https://127.0.0.1:8444/login"
login_data = json.dumps({"username": username, "password": "testpass123", "proto": PROTO}).encode()
try:
    req = urllib.request.Request(login_url, data=login_data, headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, context=ctx)
    body = json.loads(resp.read().decode())
    if not body.get("ok"):
        print("LOGIN FAILED:", body.get("error"))
        sys.exit(1)
    token = body["session_token"]
    print("Token received (first 60 chars):", token[:60] + "...")
except Exception as e:
    print("HTTPS login error:", e)
    sys.exit(1)

# Step 3: Verify token via DB service (TCP/JSON on 54321)
msg = json.dumps({"method": "verify_and_consume_token", "session_token": token, "instance_id": "test_client"}) + "\n"
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(("127.0.0.1", 54321))
    sock.sendall(msg.encode())
    resp_data = sock.recv(4096)
    sock.close()
    resp = json.loads(resp_data.decode().strip())
    print("DB verify response:", resp)
    if resp.get("ok"):
        print("SUCCESS: Token verified! account_id =", resp.get("account_id"))
    else:
        print("FAILED: Token verification rejected:", resp.get("error"))
        sys.exit(1)
except Exception as e:
    print("DB verify error:", e)
    sys.exit(1)

# Step 4: Klan duman testi (DB servisi uzerinden): kur -> etiket hemen gelmeli -> dagit
def db_call(payload: dict) -> dict:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("127.0.0.1", 54321))
    s.sendall((json.dumps(payload) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.decode().strip())

try:
    suffix = str(int(time.time()))[-5:]
    tag = "T" + suffix[-3:]
    created = db_call({"method": "clan_op", "account_id": account_id, "op": "create",
                       "args": {"name": "Test Klan " + suffix, "tag": tag, "description": "deploy testi"}})
    if not created.get("ok"):
        print("FAILED: Klan kurulamadi:", created.get("error"))
        sys.exit(1)
    info = db_call({"method": "clan_tag_of", "account_id": account_id})
    if not (info.get("ok") and info.get("tag") == tag):
        print("FAILED: Klan etiketi gelmedi:", info)
        sys.exit(1)
    db_call({"method": "clan_op", "account_id": account_id, "op": "disband", "args": {}})
    print("SUCCESS: Clan verified! tag =", tag)
except Exception as e:
    print("Clan test error:", e)
    sys.exit(1)
