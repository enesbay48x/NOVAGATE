import urllib.request
import urllib.parse
import json
import socket
import sys

# Step 1: Login via HTTPS to get session token
login_url = "https://127.0.0.1:8444/login"
data = json.dumps({"username": "testuser", "password": "testpass123"}).encode()
req = urllib.request.Request(login_url, data=data, headers={"Content-Type": "application/json"})
try:
    resp = urllib.request.urlopen(req, context=__import__("ssl")._create_unverified_context())
    body = json.loads(resp.read().decode())
    print("Auth login response:", body)
    if not body.get("ok"):
        print("LOGIN FAILED:", body.get("error"))
        sys.exit(1)
    token = body["session_token"]
    print("Token received:", token[:40] + "...")
except Exception as e:
    print("HTTPS login error:", e)
    sys.exit(1)

# Step 2: Verify token via DB service (TCP/JSON on 54321)
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
