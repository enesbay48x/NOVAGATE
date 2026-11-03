import os, sys, json, socket, ssl, time

sys.path.insert(0, 'server')

# Check env var
print("NOVAGATE_TOKEN_HMAC_KEY env:", os.environ.get("NOVAGATE_TOKEN_HMAC_KEY"))

# Now test the actual flow via sockets (like the smoke test does)
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
            resp = b""
            while True:
                chunk = ssock.recv(4096)
                if not chunk:
                    break
                resp += chunk
    resp_str = resp.decode("utf-8", errors="replace")
    body_start = resp_str.index("{")
    return json.loads(resp_str[body_start:])

# Register and login
uname = f"dbg_{int(time.time())}"
r = https_post("/register", {"username": uname, "password": "TestPass123!", "faction": 1, "callsign": uname})
print("Register:", r)
r = https_post("/login", {"username": uname, "password": "TestPass123!"})
print("Login:", r)
token = r["session_token"]
print("Token:", token)

# Now verify via server_db
from server_db import verify_and_consume_token
result = verify_and_consume_token(token, INSTANCE_ID)
print("Verify result:", result)
