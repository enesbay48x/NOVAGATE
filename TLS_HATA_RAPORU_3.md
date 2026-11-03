# Rapor: auth_service neden 18.117.15.199:8444'te dinlemiyor? — Sunucu Tarafı

**Tarih:** 3 Kasım 2026  
**Kural:** Hiçbir şey değiştirilmedi. Sadece SSH ile okuma komutları çalıştırıldı.

Hedef: `https://18.117.15.199:8444/login`  
SSH: `ubuntu@18.117.15.199`, anahtar `C:\Users\Pc\.ssh\novagate_vds_ed25519` (kaynak: `deploy.ps1`)

---

## ÖN KOŞUL — SSH BAĞLANTI BİLGİSİ

Kaynak dosya: `C:\Users\Pc\Downloads\Yeni klasör\deploy.ps1`

```
$SSH_KEY  = "C:\Users\Pc\.ssh\novagate_vds_ed25519"
$SSH_USER = "ubuntu"
$SSH_HOST = "18.117.15.199"
$TARGET   = "${SSH_USER}@${SSH_HOST}"
$SSH_OPTS = @("-i", $SSH_KEY, "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new")
```

SSH bağlantısı **başarılı**: `SSH_CONNECTED_OK`, kullanıcı `ubuntu`, makine `ip-172-31-32-112`.

Servis adları (deploy.ps1'den): `novagate-auth`, `novagate-db`, `novagate-server`.

---

## ADIM 1 — DİNLEYEN PORTLAR

### Komut: `sudo ss -tlnp` (tam liste)

```
State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=603,fd=5),("nginx",pid=602,fd=5),("nginx",pid=600,fd=5))
LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=1074,fd=3),("systemd",pid=1,fd=87))
LISTEN 0      511          0.0.0.0:8447      0.0.0.0:*    users:(("nginx",pid=603,fd=7),("nginx",pid=602,fd=7),("nginx",pid=600,fd=7))
LISTEN 0      4096   127.0.0.53%lo:53        0.0.0.0:*    users:(("systemd-resolve",pid=384,fd=15))
LISTEN 0      4096      127.0.0.54:53        0.0.0.0:*    users:(("systemd-resolve",pid=384,fd=17))
LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=603,fd=6),("nginx",pid=602,fd=6),("nginx",pid=600,fd=6))
LISTEN 0      4096            [::]:22           [::]:*    users:(("sshd",pid=1074,fd=4),("systemd",pid=1,fd=88))
```

**Bulgu:** 8444 **hiçbir yerde dinlemiyor**. Açık portlar: 80 (nginx), 22 (sshd), 8447 (nginx).

---

## ADIM 2 — SERVİS DURUMU

### Komut: `systemctl list-units --type=service | grep -i -E 'nova|auth|nginx'`

(Grep komutu kabuk escaping sorunu verdi, ancak aşağıdaki status komutları net sonuç verdi.)

### Komut: `systemctl status auth_service --no-pager`

```
Unit auth_service.service could not be found.
```

### Komut: `systemctl status novagate-auth --no-pager`

```
○ novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login)
     Loaded: loaded (/etc/systemd/system/novagate-auth.service; disabled; preset: enabled)
     Active: inactive (dead)
```

### Komut: `systemctl status nginx --no-pager`

```
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-11-03 16:47:50 UTC; 53min ago
   Main PID: 600 (nginx)
```

**Bulgu:** `novagate-auth.service` **disabled** ve **inactive (dead)** — servis çalışmıyor ve otomatik başlatma kapalı. `nginx` aktif ama 8447'de (8444'te değil).

---

## ADIM 3 — SERVİS LOGU

### Komut: `sudo journalctl -u novagate-auth -n 100 --no-pager`

Önemli satırlar:

```
Nov 03 15:20:12 ... python3[52545]: 2026-11-03 15:20:12,770 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 15:30:33 ... python3[55215]: 2026-11-03 15:30:33,460 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 15:40:19 ... python3[57946]: 2026-11-03 15:40:19,290 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:15:05 ... python3[62767]: 2026-11-03 16:15:05,197 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:19:53 ... python3[65289]: 2026-11-03 16:19:53,619 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:25:49 ... python3[68101]: 2026-11-03 16:25:49,592 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:29:15 ... python3[70531]: 2026-11-03 16:29:15,620 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:32:07 ... python3[73102]: 2026-11-03 16:32:07,178 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:36:27 ... python3[76165]: 2026-11-03 16:36:27,972 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
Nov 03 16:43:22 ... python3[78894]: 2026-11-03 16:43:22,687 [AUTH] INFO Auth service hazir. Baglanti bekleniyor...
Nov 03 16:43:22 ... python3[78894]: Exception in thread Thread-1 (_start_https_login_server):
Nov 03 16:43:22 ... python3[78894]:   File "/opt/novagate/server/auth_service.py", line 477, in _start_https_login_server
Nov 03 16:43:22 ... python3[78894]:     with socketserver.TCPServer(("0.0.0.0", https_port), AuthHandler) as httpd:
Nov 03 16:43:22 ... python3[78894]: OSError: [Errno 98] Address already in use
Nov 03 16:47:32 ... systemd[1]: Stopped novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login).
```

**Bulgu:** Servis önceki çalışmalarında 8444'te başarıyla dinliyordu ("HTTPS login endpoint hazir: https://127.0.0.1:8444/login"). Son başlangıçta (16:43:22) `OSError: [Errno 98] Address already in use` hatası verdi, ardından 16:47:32'de durdu. System reboot'ı (16:47:46) sonrası `disabled` olduğundan otomatik başlamadı.

### Komut: `sudo journalctl -u novagate-auth --since "2026-11-02 18:00" --no-pager | tail -100`

```
Failed to add match '18:00': Invalid argument
```
(Saat biçimi kabuk tarafından reddedildi; -n 100 çıktısı yeterli.)

---

## ADIM 4 — SERTİFİKA VE ANAHTAR DOSYALARI

### Komut: `cat /etc/systemd/system/novagate-auth.service`

```
[Unit]
Description=NOVAGATE Auth Service (TLS + HTTPS login)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=novagate
Group=novagate
WorkingDirectory=/opt/novagate/server
ExecStart=/usr/bin/python3 /opt/novagate/server/auth_service.py
Restart=on-failure
RestartSec=5
Environment=NOVAGATE_TOKEN_KEY_FILE=/opt/novagate/server/.hmac_key
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Komut: `grep -n "CERT_FILE\|KEY_FILE\|https_port\|PORT" /opt/novagate/server/auth_service.py`

(Kodtan önceki okumada:)
- `CERT_FILE = .../server/auth_cert.pem` (satır 81)
- `KEY_FILE = .../server/auth_key.pem` (satır 82)
- `https_port = 8444` (satır 475)
- `socketserver.TCPServer(("0.0.0.0", https_port), ...)` (satır 477)

### Komut: `ls -l /opt/novagate/server/auth_cert.pem /opt/novagate/server/auth_key.pem`

```
-rw-r--r-- 1 novagate novagate 1172 Nov  2 21:28 /opt/novagate/server/auth_cert.pem
-rw------- 1 novagate novagate 1704 Nov  2 21:28 /opt/novagate/server/auth_key.pem
```

### Komut: `openssl x509 -in /opt/novagate/server/auth_cert.pem -noout -subject -issuer -dates -fingerprint -sha256`

```
subject=CN = novagate.local
issuer=CN = novagate.local
notBefore=Nov  2 21:14:02 2026 GMT
notAfter=Feb  4 21:14:02 2029 GMT
sha256 Fingerprint=3A:4B:2B:97:2A:50:E2:9E:E8:93:8F:FD:3C:F6:44:85:71:A9:3D:4F:05:66:D0:F3:E8:3F:C1:01:10:1F:07:BA
```

### Komut: modulus MD5 karşılaştırması (sudo -u novagate)

```
key_modulus
MD5(stdin)= 3e9fb2cfb3695b200db97870c5af67b4
cert_modulus
MD5(stdin)= 3e9fb2cfb3695b200db97870c5af67b4
```

**Bulgu:** Cert ve key çifti **eşleşiyor** (aynı modulus MD5). Sunucu sertifikası SHA256 parmak izi `3A:4B:2B...07BA` — **istemciyle (`auth_cert_public.crt`) birebir aynı**. Sertifika sorunu yok.

(Anahtar içeriği rapora yazılmadı, sadece hash çıktısı verildi.)

---

## ADIM 5 — SON DEĞİŞİKLİKLER

### Komut: `stat` + `uptime -s` + `last reboot`

```
=== stat auth_service.py ===
Modify: 2026-11-03 16:41:13.393926252 +0000
Change: 2026-11-03 16:43:45.518691803 +0000
Birth:  2026-11-02 20:03:03.331346843 +0000

=== stat auth_cert.pem ===
Modify: 2026-11-02 21:28:11.348836092 +0000

=== stat auth_key.pem ===
Modify: 2026-11-02 21:28:11.358548758 +0000

=== stat novagate-auth.service ===
Modify: 2026-11-02 20:35:02.143819589 +0000

=== uptime -s ===
2026-11-03 16:47:46

=== last reboot ===
reboot   system boot  7.0.0-1014-aws   Tue Nov  3 16:47   still running
reboot   system boot  7.0.0-1014-aws   Tue Nov  3 04:15 - 16:47  (12:31)
```

**Bulgu:**
- `auth_service.py` son 16:41:13 UTC'de değiştirildi (servis çöküşünden hemen önce).
- Sertifika/anahtar 2026-11-02 21:28'de oluşturuldu, sonradan değiştirilmedi.
- Servis dosyası 2026-11-02 20:35'de oluşturuldu, değiştirilmedi.
- Sistem 16:47:46 UTC'de reboot aldı; `novagate-auth` `disabled` olduğu için otomatik başlamadı.

---

## ADIM 6 — NGINX İLİŞKİSİ

### Komut: `cat /etc/nginx/sites-available/novagate_auth`

```
server {
    listen 8447 ssl;
    server_name 18.117.15.199;

    ssl_certificate /etc/nginx/server.crt;
    ssl_certificate_key /etc/nginx/server.key;
    ...
    location / {
        proxy_pass http://127.0.0.1:8445;
        ...
    }
}
```

### Komut: nginx status'tan önemli satırlar

```
2026/11/03 16:47:50 [warn] ... conflicting server name "18.117.15.199" on 0.0.0.0:8447, ignored
2026/11/03 17:41:17 [emerg] ... cannot load certificate key "/etc/nginx/server.key": ... Permission denied
```

**Bulgu:** Nginx **8447**'de dinliyor (8444'te değil), `proxy_pass http://127.0.0.1:8445` (admin panel, auth_service değil). Nginx'in kendi `server.key` dosyasıyla izin hatası var. Nginx, auth_service'in 8444'te dinlememesiyle alakalı değil (farklı port).

---

## ADIM 7 — AWS TARAFI

### Komut: `aws ec2 describe-security-groups --region us-east-2 ... 8444`

```
aws: [ERROR]: An error occurred (UnauthorizedOperation) when calling the DescribeSecurityGroups operation:
User: arn:aws:sts::257851647480:assumed-role/novagate-server-role/i-094c6723c2dbf082f
is not authorized to perform: ec2:DescribeSecurityGroups because no identity-based policy allows the ec2:DescribeSecurityGroups action
```

**Bulgu:** AWS güvenlik grubu kontrolü **doğrulanamadı** (instance IAM rolüne `ec2:DescribeSecurityGroups` izni yok). Bu, `ss -tlnp` tarafından zaten kanıtlanan "8444 dinlemiyor" bulgusunu etkilemez.

---

## KÖK NEDEN

Kanıtlanan seçenek: **(a) Servis çökmüş/hiç başlamamış**

Kanıtlar:
1. `ss -tlnp` → 8444'de hiçbir dinleyici yok.
2. `systemctl status novagate-auth` → `inactive (dead)`, `disabled`.
3. `journalctl` → servis 16:43:22'de `OSError: [Errno 98] Address already in use` ile çöktü, 16:47:32'de durdu. Sistem 16:47:46'de reboot aldı; servis `disabled` olduğu için otomatik başlamadı.
4. Sertifika/anahtar dosyaları mevcut, modulus eşleşiyor, parmak izi istemciyle aynı → sertifika sorunu **DEĞİL**.
5. Nginx 8447'de, 8444'te değil → mimari uyuşmazlığı da **DEĞİL** (farklı port, farklı hizmet).

Reddedilen seçenekler:
- (b) Sertifika/anahtar yükleme hatası → reddedildi (modulus eşleşiyor, fingerprint istemciyle aynı, dosyalar var ve okunabilir).
- (c) Başka porta bağlı → reddedildi (8444'te hiçbir şey dinlemiyor; çakışma geçiciydi ve şu an port boş).
- (d) Nginx ile mimari uyuşmazlığı → reddedildi (nginx 8447'de, auth_service 8444'te olmalı).
- (e) Başka → yok.

---

## ÖNERİLEN DÜZELME ADIMLARI (UYGULANMAYACAK)

1. `sudo systemctl start novagate-auth` — servisi başlat.
2. `sudo systemctl enable novagate-auth` — reboot sonrası otomatik başlatma için etkinleştir.
3. Eğer tekrar `Address already in use` verirse, 8444'te kalan eski süreci bulup (`sudo ss -tlnp | grep 8444`) sonlandırıp yeniden deneyin.
4. Nginx'in `server.key` izin hatasını da giderebilirsiniz (ayrı bir sorun, 8447'ye ait).

Bu adımlar rapor kapsamında sadece öneridir; **uygulanmamıştır.**
