import socket, time
time.sleep(3)
for port in [8444, 54321, 7777]:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    result = s.connect_ex(('127.0.0.1', port))
    status = 'OPEN' if result == 0 else 'CLOSED'
    print(f'Port {port}: {status}')
    s.close()