import os, sys, json, socket, ssl, time

sys.path.insert(0, 'server')
os.environ["NOVAGATE_TOKEN_HMAC_KEY"] = "phase2-test-hmac-key-change-in-production"

from server_db import verify_and_consume_token

# Get a real token from auth service
import socket as sock_mod
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

uname = f"final_{int(time.time())}"
reg_body = json.dumps({"username": uname, "password": "TestPass123!", "faction": 1, "callsign": uname})
with sock_mod.create_connection(("127.0.0.1", 8444), timeout=5) as sock:
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

login_body = json.dumps({"username": uname, "password": "TestPass123!"})
with sock_mod.create_connection(("127.0.0.1", 8444), timeout=5) as sock:
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

token = login_data["session_token"]
print("Token:", token)
print("Env key present:", bool(os.environ.get("NOVAGATE_TOKEN_HMAC_KEY")))

result = verify_and_consume_token(token, "test-instance-001")
print("Verify result:", result)
