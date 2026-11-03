import socket

print("=== AWS Bağlantı Testi ===")
print()

# Test 1: HTTPS Auth (TCP 8444)
print("Test 1: AWS Auth (TCP 8444)")
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
result = s.connect_ex(('18.117.15.199', 8444))
if result == 0:
    print("  -> OPEN (bağlantı kuruldu)")
else:
    print(f"  -> CLOSED (hata kodu: {result})")
s.close()

# Test 2: UDP 7777 (ENet oyun sunucusu)
print("Test 2: ENet Oyun Sunucusu (UDP 7777)")
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
try:
    s.sendto(b'test', ('18.117.15.199', 7777))
    data, addr = s.recvfrom(1024)
    print(f"  -> Yanıt geldi: {data[:50]} from {addr}")
except socket.timeout:
    print("  -> Yanıt yok (timeout) - Port closed veya firewall")
except Exception as e:
    print(f"  -> Hata: {e}")
s.close()

print("\nTest tamamlandı.")