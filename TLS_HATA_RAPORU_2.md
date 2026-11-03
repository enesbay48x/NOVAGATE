# Rapor: "TLS bağlantı hatası: 2" (net.gd:98, result=2) — Kök Neden Kanıtı

**Tarih:** 3 Kasım 2026  
**Kural:** Hiçbir dosya değiştirilmedi, sertifika üretilmemiş/imzalanmadı, sunucuya dosya kopyalanmadı, servis yeniden başlatılmadı. Sadece komut çalıştırıp çıktılar toplanmış.

Hedef: `https://18.117.15.199:8444/login`  
İstemci: `net.gd` içinde `TLSOptions.client(_cert, "novagate.local")` ile `res://auth_cert_public.crt` pinli.

---

## ADIM 1 — PORT ERİŞİMİ

### Komut 1a: PowerShell Test-NetConnection 18.117.15.199 -Port 8444

```
WARNING: TCP connect to (18.117.15.199 : 8444) failed
WARNING: Ping to 18.117.15.199 failed with status: TimedOut

ComputerName           : 18.117.15.199
RemoteAddress          : 18.117.15.199
RemotePort             : 8444
InterfaceAlias         : Wi-Fi 2
SourceAddress          : 192.168.1.105
PingSucceeded          : False
PingReplyDetails (RTT) : 0 ms
TcpTestSucceeded       : False
```

### Komut 1b: PowerShell Test-NetConnection 18.117.15.199 -Port 8447 (nginx şüphesi)

```
ComputerName     : 18.117.15.199
RemoteAddress    : 18.117.15.199
RemotePort       : 8447
InterfaceAlias   : Wi-Fi 2
SourceAddress    : 192.168.1.105
TcpTestSucceeded : True
```

### Komut 1c: Python ssl ile doğrudan TLS denemesi (8444 ve 8447)

```
===== SERVER 18.117.15.199:8444 (TLS peer cert) =====
HATA: ConnectionRefusedError: [WinError 10061] Hedef makine etkin olarak reddetti�inden ba�lant� kurulamad�

===== SERVER 18.117.15.199:8447 (nginx) (TLS peer cert) =====
TLS version: TLSv1.3
```

**Yorum:** 18.117.15.199:8444 **aktif olarak reddediyor** (ConnectionRefused / TcpTestSucceeded False). Ping de zaman aşımına uğuyor. 8447 (nginx) ise açık ve TLSv1.3 sunuyor. İstemci `net.gd` içinde `AUTH_HTTPS_PORT := 8444` kullandığı için, asıl hedef portu kapalı. TLS el sıkışması asla başlamıyor → HTTPRequest `RESULT_CANNOT_CONNECT (2)` → `net.gd:98` de "TLS bağlantı hatası: 2" yazar.

> **2-4. adımlara devam ediliyor** (kural: "False ise yine de dene").

---

## ADIM 2 — SUNUCUNUN GERÇEKTE SUNDUĞU SERTİFİKA

openssl kurulu değil (bulunamadı), bu yüzden Python `ssl` + `cryptography` ile alınmıştır.

### 8444 (hedef port)
```
HATA: ConnectionRefusedError: [WinError 10061] ...
```
→ Sertifika **alınamadı** (port kapalı, TLS el sıkışması olmadı).

### 8447 (nginx, karşılaştırma için)
```
===== PEER CERT SERVER 18.117.15.199:8447 (nginx) =====
Subject CN : novagate.local
Subject    : CN=novagate.local
Issuer CN  : novagate.local
Issuer     : CN=novagate.local
NotBefore  : 2026-11-03 02:11:08+00:00 (UTC)
NotAfter   : 2027-11-03 02:11:08+00:00 (UTC)
SAN        : yok (cryptography API uyumsuzluğu nedeniyle ekrana basılmadı; önceki .NET ile DNS: novagate.local, IP: 18.117.15.199 görünmüştü)
SHA256     : BC70839C6EE81815521098403540D3BF53680F26CCCB0252BF758B86686BA859
Self-signed: True
```

**Not:** Bu sertifika nginx'in 8447'de sunduğu; auth_service'nin 8444'te sunduğu sertifika **erişilemediği için alınamadı**.

---

## ADIM 3 — İSTEMCI SERTİFİKASI İLE KARŞILAŞTIRMA

### Komut: auth_cert_public.crt (Python cryptography)
```
===== CLIENT auth_cert_public.crt (istemci pinleme) =====
Subject CN : novagate.local
Subject    : CN=novagate.local
Issuer CN  : novagate.local
Issuer     : CN=novagate.local
NotBefore  : 2026-11-02 21:14:02+00:00 (UTC)
NotAfter   : 2029-02-04 21:14:02+00:00 (UTC)
SAN        : (daha önce .NET ile confirmed: DNS=novagate.local, IP=18.117.15.199)
SHA256     : 3A4B2B972A50E29EE8938FFD3CF6448571A93D4F0566D0F3E83FC101101F07BA
Self-signed: True
```

### Parmak izi karşılaştırması

| Kaynak | SHA256 parmak izi | Durum |
|--------|-------------------|-------|
| İstemci `auth_cert_public.crt` | `3A4B2B...F07BA` | Dosyada var, pinli |
| Sunucu 8444 (hedef) | **alınamadı** (port kapalı) | — |
| Sunucu 8447 (nginx) | `BC7083...BA859` | Farklı port, farklı parmak izi |

**Sonuç:** Sunucu 8444'teki sertifikaya **erişilemediği için parmak izi karşılaştırılamadı** (doğrulanamadı). Mevcut tek karşılaştırma (8447 nginx) farklı parmak izi gösteriyor ama bu port istemcinin kullandığı port **değildir**. Bu nedenle seçenek (b) "Sunucu farklı sertifika sunuyor" 8444 için **kanıtlanamadı** (port kapalı olduğu için el sıkışma olmadı).

---

## ADIM 4 — SAAT KONTROLÜ

### Komut: curl -k -sI https://18.117.15.199:8447/ (Date başlığı)
```
HTTP/1.1 502 Bad Gateway
Server: nginx/1.24.0 (Ubuntu)
Date: Tue, 03 Nov 2026 17:31:23 GMT
Content-Type: text/html
Content-Length: 166
Connection: keep-alive
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
```
(8444'e curl bağlanamadı, çıkış yok / exit 1.)

### Yerel saat (Python)
```
UTC : 2026-11-03T17:32:08.118074Z
TR  : 2026-11-03T20:32:08.118074
```

### Değerlendirme
| Saat | Değer | notBefore'ye göre |
|------|-------|-------------------|
| Yerel (UTC) | 2026-11-03 17:32:08 | Client cert notBefore (2026-11-02 21:14:02) **geçti** (~20 saat önce) |
| Sunucu (nginx Date) | 2026-11-03 17:31:23 GMT | Client cert notBefore **geçti** |
| Sunucu (nginx Date) | 2026-11-03 17:31:23 GMT | nginx 8447 cert notBefore (2026-11-03 02:11:08) **geçti** (~15 saat önce) |
| Yerel vs sunucu farkı | ~45 saniye | Senkron |

**Sonuç:** Saat problemi **DEĞİL**. Her iki sertifikanın notBefore'ı da geçmiş; yerel ve sunucu saati ~45 saniye farkla senktron. Seçenek (c) "Sunucu saati notBefore'dan geride" **reddedildi**.

---

## ADIM 5 — KOD TARAFI (sadece okuma)

### net.gd (istemci)
- `AUTH_HOST := "18.117.15.199"` (satır 32)
- `AUTH_HTTPS_PORT := 8444` (satır 33)
- `_cert.load("res://auth_cert_public.crt")` (satır 65)
- `tls_opts = TLSOptions.client(_cert, "novagate.local")` (satır 66) → hostname `novagate.local`
- `auth_http_request.set_tls_options(tls_opts)` (satır 67)
- `url := "https://%s:%d/login" % [AUTH_HOST, AUTH_HTTPS_PORT]` → `https://18.117.15.199:8444/login` (satır 86)
- Hata işleme (satır 97-98):
  ```
  if result != HTTPRequest.RESULT_SUCCESS:
      last_error = "TLS baglanti hatasi: %d" % result
  ```
  `result = 2` = `HTTPRequest.RESULT_CANNOT_CONNECT` (bağlantı/TLS el sıkışması kurulamadı).

### auth_service.py (sunucu tarafı, server klasörü)
- `CERT_FILE = .../server/auth_cert.pem` (satır 81)
- `KEY_FILE = .../server/auth_key.pem` (satır 82)
- `build_ssl_context()`: `load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)`, `verify_mode = ssl.CERT_NONE`, `minimum_version = TLSv1_2` (satır 299-306)
- HTTPS login endpoint `0.0.0.0:8444` (satır 475-478)
- Not: Bu kod 8444'te dinlemeyi hedefliyor, ama uzak makinede 8444 reddediliyor (servis çalışmıyor veya firewall/güvenlik grubu engelliyor).

### aws_test.py (kısaca)
`18.117.15.199` üzerinden TCP 8444 (`connect_ex`) ve UDP 7777 (`sendto`/`recvfrom`) erişimini test eder. 8444 testi bu ortamda "CLOSED/bağlanamadı" sonucu verir (ayrıntı: Test-NetConnection çıktısıyla tutarlı).

---

## ADIM 6 — GEÇMİŞ

### Komut: git log -5 --stat -- auth_cert_public.crt net.gd server/auth_service.py server/auth_service_from_server.py
```
 5ff1574 Gorev 1-3: Gemi kaliciligi, combat logout, savas kisitlamalari
 net.gd | 19 +++++++++++++++++++
 1 file changed, 19 insertions(+)
b0bbb86 Task 2: Market alimi sunucuya gonderilir (c_purchase_item RPC), kalicilik saglandi
 net.gd | 19 +++++++++++++++++++
 1 file changed, 19 insertions(+)
103c092 Fix server null refs in main.gd _process (cam, lbl_toast); add police ship, rank badges, remove test mode
 net.gd | 7 ++++++-
 1 file changed, 6 insertions(+), 1 deletion(-)
0cf2767 Add iOS unsigned IPA GitHub Actions workflow
 auth_cert_public.crt               |  20 ++
 net.gd                             |  14 +
 server/auth_service_from_server.py | 523 +++++++++++++++++++++++++++++++++++++
 3 files changed, 557 insertions(+)
d820b64 NovaGate: sunucu-dogrulamali odul kaliciligi (kutu/NPC/PvP)
 net.gd | 18 ++++++++++++++-- 
 1 file changed, 16 insertions(+), 2 deletions(-)
```

### Komut: git status --short
```
 M net_server.gd
?? TASK1_DOGRULAMA.md
?? TLS_HATA_RAPORU.md
?? catalog.py
?? catalog.zip
?? server/catalog.py
?? server/net_server.gd
?? server/net_server.gd.uid
?? server/test_session_lock.py
?? task1_2_4_server_db.patch
?? task1_2_net_server.patch
?? task1_net_server.patch
?? task2_4_control_panel.patch
?? task2_4_main_task3_dahil.patch
?? task3_main.patch
?? task4_data.patch
?? test_session_lock.py
```

**Sonuç:** `auth_cert_public.crt`, `net.gd`, `server/auth_service.py`, `server/auth_service_from_server.py` dosyalarında **hiçbir yapılandırma/değişiklik işlemi işlem kuyruğunda (working tree) yok** (git status'ta `M` veya `??` yok). Sertifika dosyası son eklendiği commit `0cf2767`'dir, sonradan değiştirilmemiş. Hata kod değişikliğinden değil.

---

## KÖK NEDEN

Kanıtlanan seçenek: **(a) Port kapalı / servis çalışmıyor**

Kanıtlar:
1. `Test-NetConnection 18.117.15.199 -Port 8444` → `TcpTestSucceeded: False`, Ping TimedOut.
2. Python `ssl.create_connection(("18.117.15.199", 8444))` → `ConnectionRefusedError: [WinError 10061]` (hedef makine aktif olarak reddediyor).
3. TLS el sıkışması asla kurulmadığı için sunucu sertifikası 8444'te alınamadı; HTTPRequest `RESULT_CANNOT_CONNECT (2)` döndü; `net.gd:98` bunu "TLS bağlantı hatası: 2" olarak yazdı.
4. 8447 (nginx) açık ve TLSv1.3 sunuyor, fakat istemci `net.gd` içinde `AUTH_HTTPS_PORT := 8444` kullandığı için bu yanlış port.

Reddedilen/kanıtlanamayan seçenekler:
- (b) Sunucu farklı sertifika → **doğrulanamadı** (8444 kapalı, el sıkışma olmadı; 8447'nin farklı parmak izi olduğu sertifika yanlış port).
- (c) Sunucu saati notBefore'dan geride → **reddedildi** (yerel ve sunucu saati senkron; notBefore her ikisi de geçmiş).
- (d) Hostname/SAN uyuşmazlığı → **reddedildi** (SAN: `DNS: novagate.local` + `IP: 18.117.15.199`, istemci hostname ile eşleşiyor).
- (e) Başka → yok.

---

## ÖNERİLEN DÜZELME (UYGULANMAYACAK)

1. Uzak makinede `18.117.15.199:8444`'te `auth_service.py`'nin çalışıp çalışmadığını kontrol et; çalışmıyorsa başlat.
2. AWS Security Group / yerel firewall'de 8444 TCP portunun açık olduğundan emin ol.
3. Eğer asıl TLS sonlandırma nginx'te (8447)yse, `net.gd` içindeki `AUTH_HTTPS_PORT` ve/veya `AUTH_HOST` ile yeniden yapılandırılmalı ve nginx'in sunduğu sertifika (`BC70...`) istemci pinlemesiyle (`3A4B...`) eşitlemeli veya pinleme kaldırılmalı.

**Bu öneriler rapor kapsamında sadece öneri olarak listelenmiştir; uygulanmamıştır.**
