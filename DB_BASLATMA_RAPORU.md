# Rapor: novagate-db servisini başlat ve doğrula — 18.117.15.199

**Tarih:** 3 Kasım 2026  
**Kural:** Sadece okuma/başlatma/enable komutları. Kod/config düzenleme YOK, kill/reboot YOK, başka servise dokunulmadı, dosya silinmedi, DB dosyasına dokunulmadı.

SSH: `ubuntu@18.117.15.199`, anahtar `C:\Users\Pc\.ssh\novagate_vds_ed25519`

---

## ADIM 1 — ÖN KONTROL

### Komut 1a: `journalctl -u novagate-db -n 50 --no-pager`

```
Nov 03 16:33:09 ip-172-31-32-112 systemd[1]: Started novagate-db.service - NOVAGATE Game DB Service (TCP/JSON).
Nov 03 16:33:14 ip-172-31-32-112 python3[74069]: Traceback (most recent call last):
Nov 03 16:33:14 ip-172-31-32-112 python3[74069]:   File "/opt/novagate/server/server_db.py", line 249, in <module>
Nov 03 16:33:14 ip-172-31-32-112 python3[74069]:   File "/opt/novagate/server/server_db.py", line 58, in init_db
Nov 03 16:33:14 ip-172-31-32-112 python3[74069]:     conn.executescript(""")
Nov 03 16:33:14 ip-172-31-32-112 python3[74069]: sqlite3.OperationalError: database is locked
Nov 03 16:33:14 ip-172-31-32-112 systemd[1]: novagate-db.service: Main process exited, code=exited, status=1/FAILURE
Nov 03 16:33:14 ip-172-31-32-112 systemd[1]: novagate-db.service: Failed with result 'exit-code'.
...
Nov 03 16:36:22 ip-172-31-32-112 python3[76112]: ... Server DB hazir. Baglanti bekleniyor...
Nov 03 16:36:22 ip-172-31-32-112 systemd[1]: Stopping novagate-db.service ...
Nov 03 16:36:22 ip-172-31-32-112 systemd[1]: Stopped novagate-db.service ...
Nov 03 16:47:32 ip-172-31-32-112 systemd[1]: Stopped novagate-db.service ...
```

### Komut 1b: `sudo ss -tlnp | grep 54321`

```
(çıktı yok — SS_EXIT=1; port 54321 BOŞ, dinlemiyor)
```

### Komut 1c: `ps aux | grep -i server_db | grep -v grep`

```
(çıktı yok — PS_EXIT=1; çalışan server_db.py süreci yok)
```

**Durum:** Port 54321 BOŞ, çakışan süreç yok. `novagate-db.service` daha önce çalışmış ama son durumda inactive/dead. Geçmişte `database is locked` hatası var ama şu anda port boş.

**Karar:** Çakışma yok. Adım 2'ye geçiliyor.

---

## ADIM 2 — BAŞLAT

### Komut 2a: `sudo systemctl start novagate-db`

```
START_EXIT=0
```

### Komut 2b: `sleep 3`

```
(bekleme tamam)
```

### Komut 2c: `systemctl status novagate-db --no-pager`

```
● novagate-db.service - NOVAGATE Game DB Service (TCP/JSON)
     Loaded: loaded (/etc/systemd/system/novagate-db.service; disabled; preset: enabled)
     Active: active (running) since Tue 2026-11-03 18:45:50 UTC; 9s ago
   Main PID: 5088 (python3)
      Tasks: 1 (limit: 627)
     Memory: 9.9M (peak: 10.3M)
        CPU: 62ms
     CGroup: /system.slice/novagate-db.service
             └─5088 /usr/bin/python3 /opt/novagate/server/server_db.py

Nov 03 18:45:50 ip-172-31-32-112 systemd[1]: Started novagate-db.service - NOVAGATE Game DB Service (TCP/JSON).
Nov 03 18:45:50 ip-172-31-32-112 python3[5088]: 2026-11-03 18:45:50,949 [DB] INFO Server DB baslatiliyor. Instance ID: 63d89c49d70477a9
Nov 03 18:45:50 ip-172-31-32-112 python3[5088]: 2026-11-03 18:45:50,949 [DB] INFO Dinleme: 127.0.0.1:54321 (yalnızca yerel)
Nov 03 18:45:50 ip-172-31-32-112 python3[5088]: 2026-11-03 18:45:50,950 [DB] INFO Server DB hazir. Baglanti bekleniyor...
```

### Komut 2d: `sudo ss -tlnp | grep 54321`

```
LISTEN 0      16         127.0.0.1:54321      0.0.0.0:*    users:(("python3",pid=5088,fd=3))
SS_EXIT=0
```

### Komut 2e: `journalctl -u novagate-db -n 30 --no-pager`

```
Nov 03 16:34:10 ... [DB] INFO Server DB hazir. Baglanti bekleniyor...
Nov 03 16:36:22 ... Stopping novagate-db.service ...
Nov 03 16:36:22 ... Stopped novagate-db.service ...
Nov 03 16:43:16 ... Stopping novagate-db.service ...
Nov 03 16:43:16 ... Stopped novagate-db.service ...
Nov 03 16:43:48 ... [DB] INFO Server DB baslatiliyor. Instance ID: 5a300e6bdf7cf8de
Nov 03 16:43:48 ... [DB] INFO Dinleme: 127.0.0.1:54321 (yalnızca yerel)
Nov 03 16:43:48 ... [DB] INFO Server DB hazir. Baglanti bekleniyor...
Nov 03 16:47:32 ... Stopping novagate-db.service ...
Nov 03 16:47:32 ... Stopped novagate-db.service ...
-- Boot 03709e1bbc2c43cfa66b6fa9e97e724a --
Nov 03 18:45:50 ip-172-31-32-112 systemd[1]: Started novagate-db.service - NOVAGATE Game DB Service (TCP/JSON).
Nov 03 18:45:50 ip-172-31-32-112 python3[5088]: 2026-11-03 18:45:50,949 [DB] INFO Server DB baslatiliyor. Instance ID: 63d89c49d70477a9
Nov 03 18:45:50 ip-172-31-32-112 python3[5088]: 2026-11-03 18:45:50,949 [DB] INFO Dinleme: 127.0.0.1:54321 (yalnızca yerel)
Nov 03 18:45:50 ip-172-31-32-112 python3[5088]: 2026-11-03 18:45:50,950 [DB] INFO Server DB hazir. Baglanti bekleniyor...
```

**Adım 2 SONUÇ: BAŞARILI.** `Active: active (running)`, PID 5088, port 54321 dinliyor (`127.0.0.1:54321`), log'da hata yok.

---

## ADIM 3 — KARARARLILIK KONTROLÜ

### Komut 3a: `sleep 30`

```
(bekleme tamam)
```

### Komut 3b: `systemctl is-active novagate-db ; sudo ss -tlnp | grep 54321`

```
active
LISTEN 0      16         127.0.0.1:54321      0.0.0.0:*    users:(("python3",pid=5088,fd=3))
```

**Adım 3 SONUÇ: BAŞARILI.** 30 saniye sonra servis hala `active`, port 54321 hala dinliyor, PID (5088) değişmedi.

---

## ADIM 4 — ENABLE

### Komut 4a: `sudo systemctl enable novagate-db`

```
Created symlink /etc/systemd/system/multi-user.target.wants/novagate-db.service → /etc/systemd/system/novagate-db.service.
ENABLE_EXIT=0
```

### Komut 4b: `systemctl is-enabled novagate-auth novagate-db novagate-server`

```
enabled
enabled
enabled
```

**Adım 4 SONUÇ: BAŞARILI.** `novagate-db` `enabled` olarak ayarlandı (reboot sonrası otomatik başlayacak). Üç servis de enabled.

---

## ADIM 5 — OYUN SUNUCUSU LOGU (sadece oku)

### Komut 5a: `journalctl -u novagate-server -n 30 --no-pager`

```
Nov 03 18:42:03 ... [SUNUCU] Token dogrulanamadi: ..., resp={ "ok": false, "error": "db_baglanti_yok" }
...
Nov 03 18:45:06 ... [SUNUCU] Token dogrulanamadi: ..., resp={ "ok": false, "error": "db_baglanti_yok" }
...
Nov 03 18:46:41 ... [SUNUCU] Token dogrulandi: peer_id=1797512888, account_id=1
Nov 03 18:46:41 ... [SUNUCU] Session lock alindi: account_id=1, devralindi=false
Nov 03 18:46:41 ... [SUNUCU] Player state yuklendi: account_id=1
Nov 03 18:46:41 ... [SUNUCU] Token dogrulandi: peer=1797512888, account_id=1, callsign=asdasd
Nov 03 18:46:41 ... [SUNUCU] s_attach_result gonderiliyor: peer=1797512888
Nov 03 18:46:42 ... [SUNUCU] Harita 2-4 etkinlestirildi: 18 NPC dogdu.
```

**Adım 5 SONUÇ:** DB'nin başlatılmasından sonraki son girişlerde `db_baglanti_yok` hatası artık çıkmıyor. `Token dogrulandi`, `Session lock alindi`, `s_attach_result gonderiliyor` mesajları görünüyor — token doğrulama artık çalışıyor.

---

## SONUÇ

| Kontrol | Durum | Kanıt |
|---------|-------|-------|
| Servis çalışıyor mu | **Evet** | `Active: active (running)`, PID 5088 |
| 54321 dinliyor mu | **Evet** | `LISTEN 127.0.0.1:54321` by python3 pid 5088 |
| Kararlı (30 sn) | **Evet** | `active`, 54321 hala dinliyor, PID aynı |
| Enable edildi mi | **Evet** | `systemctl is-enabled` → `enabled` |
| Token doğrulama çalışıyor mu | **Evet** | `Token dogrulandi`, `s_attach_result gonderiliyor` (son 30 satır) |

**Kök neden çözüldü:** `novagate-db.service` inactive/dead olduğu için token doğrulama `db_baglanti_yok` hatası veriyordu. Servis başlatıldı, port 54321'de dinlemeye başladı, oyun sunucusu token'ı doğrulayabiliyor, ve reboot sonrası otomatik başlayacak şekilde enable edildi.

**Uygulanan işlemler:** Sadece `sudo systemctl start novagate-db` ve `sudo systemctl enable novagate-db`. Hiçbir kod/config/DB dosyası/kill/reboot/diğer servis işlemi yapılmadı.
