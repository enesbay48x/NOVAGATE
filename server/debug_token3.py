import os, sys, json, socket, ssl, time, sqlite3

sys.path.insert(0, 'server')
os.environ["NOVAGATE_TOKEN_HMAC_KEY"] = "phase2-test-hmac-key-change-in-production"

from server_db import verify_and_consume_token, get_db

# Check used_tokens table
conn = sqlite3.connect("server/novagate_game.db")
rows = conn.execute("SELECT jti, account_id FROM used_tokens").fetchall()
print("used_tokens rows:", len(rows))
for r in rows[:5]:
    print("  jti:", r[0][:20], "... account_id:", r[1])
conn.close()

# Now test verify_and_consume_token with a fresh token
from argon2 import PasswordHasher
# We need a real token from auth service. Let's do it via socket.
import socket
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

uname = f"dbg2_{int(time.time())}"
reg_body = json.dumps({"username": uname, "password": "TestPass123!", "faction": 1, "callsign": uname})
with socket.create_connection(("127.0.0.1", 8444), timeout=5) as sock:
    with ctx.wrap_socket(sock, server_hostname="localhost") as ssock:
        req = b"POST /register HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % len(reg_body) + reg_body.encode()
        ssock.sendall(req)
        resp = b""
        while True:
            chunk = ssock.recv(4096)
            if not chunk:
                break
            resp += chunk
        resp_str = resp.decode("utf-8", errors="replace")
        body_start = resp_str.index("{")
        reg_data = json.loads(resp_str[body_start:])
        print("Register:", reg_data)

login_body = json.dumps({"username": uname, "password": "TestPass123!"})
with socket.create_connection(("127.0.0.1", 8444), timeout=5) as sock:
    with ctx.wrap_socket(sock, server_hostname="localhost") as ssock:
        req = b"POST /login HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % len(login_body) + login_body.encode()
        ssock.sendall(req)
        resp = b""
        while True:
            chunk = ssock.recv(4096)
            if not chunk:
                break
            resp += chunk
        resp_str = resp.decode("utf-8", errors="replace")
        body_start = resp_str.index("{")
        login_data = json.loads(resp_str[body_start:])
        print("Login:", login_data)

token = login_data["session_token"]
print("Token jti:", token.split(":")[1])
result = verify_and_consume_token(token, "test-instance-001")
print("Verify result:", result)

# Check used_tokens again
conn = sqlite3.connect("server/novagate_game.db")
rows = conn.execute("SELECT jti, account_id FROM used_tokens WHERE jti = ?", (token.split(":")[1],)).fetchall()
print("JTI in used_tokens:", len(rows))
conn.close()
