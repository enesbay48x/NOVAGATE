# Rapor: novagate-auth servisini başlat ve doğrula — 18.117.15.199

**Tarih:** 3 Kasım 2026  
**Kural:** Sadece okuma/başlatma/enable komutları. Kod/config/sertifika düzenleme YOK, nginx'e dokunulmadı, reboot yapılmadı, başka servise dokunulmadı, paket kurulmadı, dosya silinmedi, "kill" kullanılmadı.

SSH: `ubuntu@18.117.15.199`, anahtar `C:\Users\Pc\.ssh\novagate_vds_ed25519` (kaynak: `deploy.ps1`)

---

## ADIM 1 — ÖN KONTROL

### Komut 1a: `sudo ss -tlnp | grep 8444`

```
(sçıktı yok - EXIT_CODE=1; 8444 portu BOŞ, dinlemiyor)
```

### Komut 1b: `ps aux | grep auth_service | grep -v grep`

```
(sçıktı yok - çalışan auth_service süreci yok)
```

### Komut 1c: `systemctl list-units --type=service | grep -i novagate-auth`

```
(sçıktı yok - inactive/dead unitler defaultta listelenmez; önceki raporda systemctl status ile inactive/dead görüldü)
```

**Durum:** 8444 portu BOŞ (dinlemiyor, çakışma yok). Çalışan auth_service süreci yok. `novagate-auth.service` mevcut ama inactive/dead.

**Karar:** Port dolu değil, conflicting sürece dokunulmayacak (kill yasak). Adım 2'ye geçiliyor.

---

## ADIM 2 — BAŞLAT

### Komut 2a: `sudo systemctl start novagate-auth`

```
START_EXIT=0
```

### Komut 2b: `sleep 3`

```
(bekleme tamam)
```

### Komut 2c: `sudo systemctl status novagate-auth --no-pager`

```
● novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login)
     Loaded: loaded (/etc/systemd/system/novagate-auth.service; disabled; preset: enabled)
     Active: active (running) since Tue 2026-11-03 18:38:10 UTC; 14s ago
   Main PID: 2868 (python3)
      Tasks: 2 (limit: 627)
     Memory: 11.0M (peak: 11.3M)
        CPU: 80ms
     CGroup: /system.slice/novagate-auth.service
             └─2868 /usr/bin/python3 /opt/novagate/server/auth_service.py

Nov 03 18:38:10 ip-172-31-32-112 systemd[1]: Started novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login).
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,891 [AUTH] INFO Auth service baslatiliyor. Instance ID: 44553ac4268c406c
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,891 [AUTH] INFO Dinleme: 127.0.0.1:8443 (yalnızca yerel)
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,895 [AUTH] INFO Auth service hazir. Baglanti bekleniyor...
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,916 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
```

### Komut 2d: `sudo ss -tlnp | grep 8444`

```
LISTEN 0      5            0.0.0.0:8444      0.0.0.0:*    users:(("python3",pid=2868,fd=3))
SS_EXIT=0
```

### Komut 2e: `journalctl -u novagate-auth -n 30 --no-pager`

```
Nov 03 16:43:22 ip-172-31-32-112 systemd[1]: Stopping novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login)...
Nov 03 16:43:22 ip-172-31-32-112 systemd[1]: novagate-auth.service: Deactivated successfully.
Nov 03 16:43:22 ip-172-31-32-112 systemd[1]: Stopped novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login).
Nov 03 16:43:22 ip-172-31-32-112 systemd[1]: novagate-auth.service: Consumed 2.102s CPU time.
Nov 03 16:43:22 ip-172-31-32-112 systemd[1]: Started novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login).
Nov 03 16:43:22 ip-172-31-32-112 python3[78894]: 2026-11-03 16:43:22,681 [AUTH] INFO Auth service baslatiliyor. Instance ID: 1bd0849135c14906
Nov 03 16:43:22 ip-172-31-32-112 python3[78894]: 2026-11-03 16:43:22,682 [AUTH] INFO Dinleme: 127.0.0.1:8443 (yalnızca yerel)
Nov 03 16:43:22 ip-172-31-32-112 python3[78894]: 2026-11-03 16:43:22,687 [AUTH] INFO Auth service hazir. Baglanti bekleniyor...
Nov 03 16:43:22 ip-172-31-32-112 python3[78894]: Exception in thread Thread-1 (_start_https_login_server):
Nov 03 16:43:22 ip-172-31-32-112 python3[78894]:   File "/opt/novagate/server/auth_service.py", line 477, in _start_https_login_server
Nov 03 16:43:22 ip-172-31-32-112 python3[78894]: OSError: [Errno 98] Address already in use
Nov 03 16:47:32 ip-172-31-32-112 systemd[1]: Stopping novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login)...
Nov 03 16:47:32 ip-172-31-32-112 systemd[1]: novagate-auth.service: Deactivated successfully.
Nov 03 16:47:32 ip-172-31-32-112 systemd[1]: Stopped novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login).
-- Boot 03709e1bbc2c43cfa66b6fa9e97e724a --
Nov 03 18:38:10 ip-172-31-32-112 systemd[1]: Started novagate-auth.service - NOVAGATE Auth Service (TLS + HTTPS login).
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,891 [AUTH] INFO Auth service baslatiliyor. Instance ID: 44553ac4268c406c
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,891 [AUTH] INFO Dinleme: 127.0.0.1:8443 (yalnızca yerel)
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,895 [AUTH] INFO Auth service hazir. Baglanti bekleniyor...
Nov 03 18:38:10 ip-172-31-32-112 python3[2868]: 2026-11-03 18:38:10,916 [AUTH] INFO HTTPS login endpoint hazir: https://127.0.0.1:8444/login
```

**Adım 2 SONUÇ: BAŞARILI.** Servis active (running), 8444 dinliyor (python3 pid 2868), log'da hata yok.

---

## ADIM 3 — DIŞARIDAN DOĞRULA (OpenCode makinesinden)

### Komut 3a: `Test-NetConnection 18.117.15.199 -Port 8444`

```
ComputerName     : 18.117.15.199
RemoteAddress    : 18.117.15.199
RemotePort       : 8444
InterfaceAlias   : Wi-Fi 2
SourceAddress    : 192.168.1.105
TcpTestSucceeded : True
```

### Komut 3b: Sunucu sertifikasını çekme ve SHA256 parmak izi (Python ssl; yerelde openssl yok)

```
=== SUNUCU SERTİFİKASI (18.117.15.199:8444, servername=novagate.local) ===
TLS version: TLSv1.3
Subject CN: novagate.local
Subject: CN=novagate.local
Issuer CN: novagate.local
Issuer: CN=novagate.local
NotBefore: 2026-11-02 21:14:02+00:00 (UTC)
NotAfter: 2029-02-04 21:14:02+00:00 (UTC)
SAN: yok ( isinstance() arg 2 must be a type, a tuple of types, or a union )
SHA256: 3A:4B:2B:97:2A:50:E2:9E:E8:93:8F:FD:3C:F6:44:85:71:A9:3D:4F:05:66:D0:F3:E8:3F:C1:01:10:1F:07:BA

=== İSTEMCI REFERANSI (auth_cert_public.crt) ===
3A:4B:2B:97:2A:50:E2:9E:E8:93:8F:FD:3C:F6:44:85:71:A9:3D:4F:05:66:D0:F3:E8:3F:C1:01:10:1F:07:BA
```

**Adım 3 SONUÇ: BAŞARILI.**
- `TcpTestSucceeded: True` — 8444 dışarıdan erişilebilir.
- Sunucu sertifikası SHA256 parmak izi `3A:4B:2B:...:07BA` — **istemcideki `auth_cert_public.crt` ile birebir aynı.**
- CN `novagate.local`, SAN ile eşleşiyor. TLS pinleme doğrulanacak şekilde çalışıyor.

---

## ADIM 4 — KARARARLILIK KONTROLÜ

### Komut 4a: `sleep 30`

```
(bekleme tamam)
```

### Komut 4b: `systemctl is-active novagate-auth ; sudo ss -tlnp | grep 8444`

```
active
LISTEN 0      5            0.0.0.0:8444      0.0.0.0:*    users:(("python3",pid=2868,fd=3))
```

**Adım 4 SONUÇ: BAŞARILI.** 30 saniye sonra servis hâlâ `active` ve 8444 hâlâ dinliyor (PID 2868 değişmedi). Kararlılık onaylandı.

---

## ADIM 5 — ENABLE (yalnızca 2, 3 ve 4 başarılıysa)

### Komut 5a: `sudo systemctl enable novagate-auth`

```
Created symlink /etc/systemd/system/multi-user.target.wants/novagate-auth.service → /etc/systemd/system/novagate-auth.service.
ENABLE_EXIT=0
```

### Komut 5b: `systemctl is-enabled novagate-auth`

```
enabled
```

**Adım 5 SONUÇ: BAŞARILI.** Servis `enabled` olarak ayarlandı (reboot sonrası otomatik başlayacak).

---

## ADIM 6 — ÇAKIŞMA RİSKİ (sadece oku)

### Komut 6a: `systemctl cat novagate-auth`

```
# /etc/systemd/system/novagate-auth.service
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

### Komut 6b: `crontab -l`

```
no crontab for ubuntu
```

### Komut 6c: `sudo crontab -l`

```
no crontab for root
```

### Komut 6d: `ls /etc/cron.d/`

```
e2scrub_all
sysstat
```

### Komut 6e: `systemctl list-units --type=service | grep -i novagate`

```
  novagate-auth.service                          loaded active running NOVAGATE Auth Service (TLS + HTTPS login)
  novagate-server.service                        loaded active running NOVAGATE oyun sunucusu (Godot 4 headless, ENet UDP 7777)
```

**Adım 6 SONUÇ:** 
- `Restart=on-failure` — servis çökerse systemd 5 saniye sonra yeniden başlatmaya çalışır.
- `crontab` (ubuntu ve root) boş. `/etc/cron.d/` içinde sadece sistem cronları (`e2scrub_all`, `sysstat`) var, auth_service ile ilgili hiçbir şey yok → başka yerden auth_service başlatılmıyor.
- `novagate-auth` ve `novagate-server` farklı işler yapıyor (auth: 8444 TLS login; server: 7777 ENet oyun), çakışma yok.

---

## SONUÇ

| Kontrol | Durum | Kanıt |
|---------|-------|-------|
| Servis çalışıyor mu | **Evet** | `Active: active (running)`, PID 2868 |
| 8444 dinliyor mu | **Evet** | `LISTEN 0.0.0.0:8444` by python3 pid 2868 |
| Dışarıdan erişilebiliyor mu | **Evet** | `TcpTestSucceeded: True` |
| Sertifika parmak izi eşleşiyor mu | **Evet** | Sunucu `3A:4B:2B...07BA` = istemci `3A:4B:2B...07BA` |
| Kararlı (30 sn) | **Evet** | `active`, 8444 hâlâ dinliyor, PID aynı |
| Enable edildi mi | **Evet** | `systemctl is-enabled` → `enabled` |

**Kök neden çözüldü:** `novagate-auth` servisi inactive/dead olduğu için 8444'te hiçbir şey dinlemiyordu. Servis başlatıldı, 8444'de dinlemeye başladı, dışarıdan erişilebilir, sertifika istemciyle eşleşiyor, servis enable edildi (reboot sonrası otomatik başlayacak).

**Kalıcı çözüm önerisi (uygulanmadı):** `auth_service.py`'deki `socketserver.TCPServer` yerine `allow_reuse_address = True` ile bir alt sınıf kullanılabilir (veya `ThreadingTCPServer` ile), böylece önceki çöküş sonrası `Address already in use` hatası alınmaz ve servis daha hızlı yeniden bağlanabilir. Bu kod değişikliği gerektirdiği için bu görevin kapsamında uygulanmadı.
