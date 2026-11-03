import ssl
import socket
import json
import time

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def https_post(path, body_dict):
    body = json.dumps(body_dict)
    sock = socket.create_connection(('127.0.0.1', 8444), timeout=10)
    ssock = ctx.wrap_socket(sock, server_hostname='127.0.0.1')
    request = f'POST {path} HTTP/1.1\r\nHost: 127.0.0.1:8444\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n{body}'
    ssock.sendall(request.encode('utf-8'))
    response = b''
    while True:
        chunk = ssock.recv(4096)
        if not chunk:
            break
        response += chunk
    ssock.close()
    header_end = response.find(b'\r\n\r\n')
    headers = response[:header_end].decode('utf-8', errors='replace')
    body_text = response[header_end+4:].decode('utf-8', errors='replace')
    return headers, body_text

print('=== TEST 1: Kayit olma ===')
reg_user = f'test{int(time.time())}'
headers, resp = https_post('/register', {'username': reg_user, 'password': 'Test123!', 'faction': 1, 'callsign': reg_user})
print(f'Kayityaniti: {resp}')
data = json.loads(resp)
if data.get('ok'):
    print(f'  BASARILI: account_id={data["account_id"]}, callsign={data["callsign"]}')
else:
    print(f'  BASARISIZ: {data.get("error", "bilinmeyen")}')

print()
print('=== TEST 2: Dogru sifre ile giris ===')
headers, resp = https_post('/login', {'username': reg_user, 'password': 'Test123!'})
print(f'Girisyaniti: {resp}')
data = json.loads(resp)
if data.get('ok'):
    print(f'  BASARILI: account_id={data["account_id"]}, callsign={data["callsign"]}, faction={data["faction"]}')
    token = data.get('session_token', '')
    print(f'  Token: {token[:40]}...')
else:
    print(f'  BASARISIZ: {data.get("error", "bilinmeyen")}')

print()
print('=== TEST 3: Yanlis sifre ===')
headers, resp = https_post('/login', {'username': reg_user, 'password': 'Yanlis123!'})
print(f'Yanlis sifre yaniti: {resp}')
data = json.loads(resp)
if not data.get('ok'):
    print('  DOGRU: Yanlis sifre reddedildi')
else:
    print('  HATA: Yanlis sifre kabul edildi!')

print()
print('=== TUM TESTLER TAMAMLANDI ===')
