import socket, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
body = b'{"username": "test_smoke", "password": "TestPass123!", "faction": 1, "callsign": "test_smoke"}'
with socket.create_connection(('127.0.0.1', 8444), timeout=5) as sock:
    with ctx.wrap_socket(sock, server_hostname='localhost') as ssock:
        req = b'POST /register HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n' % len(body) + body
        ssock.sendall(req)
        resp = ssock.recv(65536)
        print('Raw response:')
        print(resp.decode('utf-8', errors='replace')[:1000])
