import ssl
import socket
import json
import time

# Test 1: TLS handshake with certificate verification (like Godot would do)
ctx = ssl.create_default_context()
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED

print("=== TEST 1: TLS Handshake with cert verification ===")
try:
    sock = socket.create_connection(('127.0.0.1', 8444), timeout=10)
    ssock = ctx.wrap_socket(sock, server_hostname='localhost')
    print(f'TLS version: {ssock.version()}')
    print(f'Server cert subject: {ssock.getpeercert().get("subject")}')
    ssock.close()
    print('TLS handshake: BASARILI')
except Exception as e:
    print(f'TLS handshake: BASARISIZ - {e}')

# Test 2: Full HTTP POST /register
print()
print('=== TEST 2: Kayit olma (HTTPS POST) ===')
reg_user = f'test{int(time.time())}'
body = json.dumps({'username': reg_user, 'password': 'Test123!', 'faction': 1, 'callsign': reg_user})

try:
    sock = socket.create_connection(('127.0.0.1', 8444), timeout=10)
    ssock = ctx.wrap_socket(sock, server_hostname='localhost')
    request = f'POST /register HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}'
    ssock.sendall(request.encode('utf-8'))
    response = b''
    while True:
        chunk = ssock.recv(4096)
        if not chunk:
            break
        response += chunk
    ssock.close()
    header_end = response.find(b'\r\n\r\n')
    body_text = response[header_end+4:].decode('utf-8', errors='replace')
    print(f'Yanit: {body_text}')
    data = json.loads(body_text)
    if data.get('ok'):
        print(f'  BASARILI: account_id={data["account_id"]}')
    else:
        print(f'  BASARISIZ: {data.get("error", "bilinmeyen")}')
except Exception as e:
    print(f'  HATA: {e}')

# Test 3: Full HTTP POST /login
print()
print('=== TEST 3: Giris yapma (HTTPS POST) ===')
body = json.dumps({'username': reg_user, 'password': 'Test123!'})
try:
    sock = socket.create_connection(('127.0.0.1', 8444), timeout=10)
    ssock = ctx.wrap_socket(sock, server_hostname='localhost')
    request = f'POST /login HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}'
    ssock.sendall(request.encode('utf-8'))
    response = b''
    while True:
        chunk = ssock.recv(4096)
        if not chunk:
            break
        response += chunk
    ssock.close()
    header_end = response.find(b'\r\n\r\n')
    body_text = response[header_end+4:].decode('utf-8', errors='replace')
    print(f'Yanit: {body_text}')
    data = json.loads(body_text)
    if data.get('ok'):
        print(f'  BASARILI: account_id={data["account_id"]}, token={data.get("session_token", "")[:40]}...')
    else:
        print(f'  BASARISIZ: {data.get("error", "bilinmeyen")}')
except Exception as e:
    print(f'  HATA: {e}')

# Test 4: Wrong password
print()
print('=== TEST 4: Yanlis sifre ===')
body = json.dumps({'username': reg_user, 'password': 'Yanlis123!'})
try:
    sock = socket.create_connection(('127.0.0.1', 8444), timeout=10)
    ssock = ctx.wrap_socket(sock, server_hostname='localhost')
    request = f'POST /login HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}'
    ssock.sendall(request.encode('utf-8'))
    response = b''
    while True:
        chunk = ssock.recv(4096)
        if not chunk:
            break
        response += chunk
    ssock.close()
    header_end = response.find(b'\r\n\r\n')
    body_text = response[header_end+4:].decode('utf-8', errors='replace')
    print(f'Yanit: {body_text}')
    data = json.loads(body_text)
    if not data.get('ok'):
        print('  DOGRU: Yanlis sifre reddedildi')
    else:
        print('  HATA: Yanlis sifre kabul edildi!')
except Exception as e:
    print(f'  HATA: {e}')

print()
print('=== TUM TESTLER TAMAMLANDI ===')
