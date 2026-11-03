# Rapor: "Geçersiz veya süresi dolmuş token" hatasının kök nedeni

**Tarih:** 3 Kasım 2026  
**Kural:** Hiçbir dosya değiştirilmedi, servis başlatılmadı/durdurulmadı. Sadece okunup raporlandı.

---

## ADIM 1 — İSTEMCI: Token alma ve gönderme (net.gd / main.gd)

### Token alma (main.gd:1860-1894)
```gd
# Giris: TLS ile auth_service'ye gonder
Net.login_via_tls(nm, pw)   # main.gd:1862
```
`_on_auth_result` callback'inde (main.gd:1866):
```gd
Net.session_token = token   # auth_service'den gelen session_token
Net.attach_token(token)     # main.gd:1894
```

### Token gönderme (net.gd:127-141)
`attach_token()` (net.gd:127):
```gd
rpc_id(1, "c_attach_token", token)   # net.gd:140
```
`c_attach_token` RPC (net.gd:370-379) — istemciden sunucuya:
```gd
@rpc("any_peer", "call_remote", "reliable")
func c_attach_token(token: String) -> void:
    if not is_server or srv == null: return
    var id: int = multiplayer.get_remote_sender_id()
    var r: Array = srv.on_attach_token(id, token)   # net_server.gd'ye yonlendir
    rpc_id(id, "s_attach_result", bool(r[0]), str(r[1]), int(r[2]), str(r[3]), int(r[4]), str(r[5]))
```

**Özet:** İstemci token'ı `Net.session_token` ile saklar, `c_attach_token(token)` RPC'si ile ENet sunucusuna (peer 1) gönderir. Token ham string olarak gider, ayrı bir şifreleme yok.

---

## ADIM 2 — OYUN SUNUCUSU: c_attach_token ve token doğrulama (net_server.gd)

### `on_attach_token` (net_server.gd:220-379)
```gd
func on_attach_token(peer_id: int, token: String) -> Array:
    # 1. Token'i server_db'ye gonder (verify_and_consume_token)
    var resp: Dictionary = db_send("verify_and_consume_token", {
        "session_token": token,
        "instance_id": db_instance_id,
    })
    if not resp.has("ok") or resp["ok"] == false:
        print("[SUNUCU] Token dogrulanamadi: ...")
        return [false, "Gecersiz veya sus mustum token", 0, "", 0, ""]
```

### Doğrulama mekanizması
- **Nerede:** `db_send()` üzerinden `127.0.0.1:54321` (server_db.py) TCP/JSON bağlantısı (net_server.gd:72-129)
- **Nasil:** `verify_and_consume_token` metodu, `session_token` ve `instance_id` gönderilir
- **Hata mesajı:** `db_baglanti_yok` veya doğrulama başarısız olduğunda `"Gecersiz veya sus mustum token"` (net_server.gd:235) — bu tam olarak kullanıcı ekranda görünen hata mesajıdır.

**Özet:** Oyun sunucusu token'ı kendi belleğinde doğrulamaz; `server_db.py`'ye TCP üzerinden sorar. `db_send` cevabı `ok == false` ise hata döner.

---

## ADIM 3 — AUTH SERVİSİ: Token üretimi, saklama, ömrü (auth_service.py / server_db.py)

### Token üretimi (auth_service.py:215-222)
```gd
def make_session_token(account_id: int) -> str:
    jti = secrets.token_urlsafe(32)
    now = int(time.time())
    expires_at = now + TOKEN_TTL_SECONDS   # 30 dk
    payload = f"{account_id}:{jti}:{expires_at}:{AUD}"   # AUD = "novagate-game-server"
    sig = hmac.new(TOKEN_HMAC_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
    token = f"{payload}:{sig}"   # 5 parca: account_id:jti:expires_at:aud:signature
    return token
```
- **Format:** `account_id:jti:expires_at:aud:hmac_sha256`
- **TTL:** `TOKEN_TTL_SECONDS = 30 * 60` = 30 dakika (auth_service.py:77)
- **İmza:** HMAC-SHA256, anahtar `TOKEN_HMAC_KEY` (ortam değişkeni `NOVAGATE_TOKEN_HMAC_KEY` veya dosya `NOVAGATE_TOKEN_KEY_FILE`)

### Token doğrulama ve tüketme (auth_service.py:229-293, server_db.py:1001-1079)
İki implementasyon var:
1. `auth_service.py` — HTTPS `/login` içinde `consume_token` metodu (doğrudan çağrı, TCP raw)
2. `server_db.py` — `verify_and_consume_token(token, instance_id)` (oyun sunucusu `db_send` üzerinden çağırır)

İkisi de şunları kontrol eder:
- Token 5 parçaya bölünebiliyor mu
- `aud == "novagate-game-server"`
- `expires_at` henüz geçmedi mi
- HMAC imzası eşleşiyor mu
- `jti` daha önce kullanılmış mı (`used_tokens` tablosu, tek kullanım)
- Hesap var mı ve yasaklı mı (`accounts.is_banned = 0`)

**Token saklama:** `used_tokens` tablosu (SQLite, `server_db.py:204-211`), `jti` PRIMARY KEY, tek kullanım.

### Oyun sunucusunun auth_service'e erişişi
- Doğrudan HTTP çağrı **YOK**
- `db_send("verify_and_consume_token", ...)` → `127.0.0.1:54321` → `server_db.py`
- `server_db.py` içinde `verify_and_consume_token` kendi HMAC anahtarını okur (`NOVAGATE_TOKEN_HMAC_KEY` veya `NOVAGATE_TOKEN_KEY_FILE`)

---

## ADIM 4 — İKİ TARAFIN UYUMU

| Özellik | İstemci (net.gd/main.gd) | Oyun Sunucusu (net_server.gd) | Auth Servisi (auth_service.py) | Server DB (server_db.py) | Eşleşiyor mu? |
|---------|-------------------------|------------------------------|-------------------------------|--------------------------|---------------|
| Token format | `session_token` string (auth_service'den gelir) | `c_attach_token(token)` RPC ile alır | `account_id:jti:expires_at:aud:sig` | 5 parça beklenir | **Evet** |
| Audience | Yok (istemci sadece iletir) | `instance_id` gönderir | `AUD = "novagate-game-server"` | `"novagate-game-server"` | **Evet** |
| TTL | `token_ttl` alanı ile gelir (30 dk) | Geçmez | `TOKEN_TTL_SECONDS = 1800` | `expires_at` karşılaştırılır | **Evet** |
| Secret/anahtar | Yok (istemci imzalamaz) | `TOKEN_HMAC_KEY` okumaz | `TOKEN_HMAC_KEY` ile imzalar | `TOKEN_HMAC_KEY` ile doğrular | **Evet** (aynı ortam/değişken) |
| Tek kullanım | Yok | `verify_and_consume_token` ister | `used_tokens` insert | `used_tokens` jti PRIMARY KEY | **Evet** |
| Saat | İstemci yerel saati | Sunucu yerel saati | `int(time.time())` | `int(time.time())` | **Evet** (aynı makine) |

**Özet:** Token formatı, secret, TTL, saat kullanımı iki taraf arasında uyumlu. Fark yok.

---

## ADIM 5 — SUNUCU (SSH, sadece okuma)

### Servis durumları
```
novagate-server.service   loaded active running   NOVAGATE oyun sunucusu (Godot 4 headless, ENet UDP 7777)
novagate-auth.service     loaded active running   NOVAGATE Auth Service (TLS + HTTPS login)
novagate-db.service       loaded inactive (dead)  NOVAGATE Game DB Service (TCP/JSON)
```

- `novagate-server`: PID 530 (godot), `/opt/godot/godot --headless --path /opt/novagate -- --server --port=7777`, 16:47:50 UTC'den beri çalışıyor
- `novagate-auth`: PID 2868 (python3), 18:38:10 UTC'den beri çalışıyor
- **`novagate-db`: inactive (dead), disabled** — **BU KÖK NEDENDİR**

### Oyun sunucusu logu (journalctl -u novagate-server)
Tekrarlanan hata:
```
Nov 03 18:42:03 ... godot[530]: [SUNUCU] on_attach_token cagrildi: peer_id=711879094, token_prefix=1:RI0ZW2R-w8ttEkaQMF
Nov 03 18:42:03 ... godot[530]: [SUNUCU] Token dogrulanamadi: account_id=711879094, resp={ "ok": false, "error": "db_baglanti_yok" }
```
Bu hata her `c_attach_token` çağrısında tekrarlanıyor (birden fazla peer_id, farklı token prefixleri). Tüm cevaplar `db_baglanti_yok`.

### Auth servisi logu
- HTTPS login endpoint `https://127.0.0.1:8444/login` hazır, hata yok.
- Token üretimi çalışıyor (istemci token alabiliyor, çünkü giriş TLS başarılı).

**Özet:** Token **üretiliyor** (auth_service çalışıyor), ancak **doğrulanamıyor** çünkü `novagate-db.service` çalışmıyor. `db_send("verify_and_consume_token")` `{"ok": false, "error": "db_baglanti_yok"}` döndürüyor, ve oyun sunucusu bunu `"Gecersiz veya sus mustum token"` olarak istemciye yansıtıyor.

---

## KÖK NEDEN

**Kanıtlanan:** `novagate-db.service` (server_db.py, 127.0.0.1:54321) inactive/dead.

Zincir:
1. İstemci TLS ile token alır (başarılı)
2. İstemci `c_attach_token(token)` gönderir
3. Oyun sunucusu `on_attach_token` → `db_send("verify_and_consume_token", ...)` → `127.0.0.1:54321`
4. `novagate-db.service` çalışmadığı için bağlantı reddedilir → `{"ok": false, "error": "db_baglanti_yok"}`
5. Oyun sunucusu `resp["ok"] == false` görür → `"Gecersiz veya sus mustum token"` döner
6. İstemci ekranda "Geçersiz veya süresi dolmuş token" görür

**Token'ı kasten "süresi dolmuş" veya "geçersiz" ilan etmiyor; DB'ye erişilemediği için doğrulama asla tamamlanamıyor.**

---

## KANITLANAMAYANLAR

- Token'ın kendi başında süresinin dolup dolmadığı: doğrulanamadı (DB'de `used_tokens` kontrol edilemedi çünkü servis down)
- İstemci tarafından gönderilen token'ın gerçek içeriği (secret/token içeriği rapora yazılmadı, kural)
- AWS Security Group veya ağ katmanında bir sorun: doğrulanamadı (ağa ilişkin değişiklik yapılmadı, sadece `ss -tlnp` ve `Test-NetConnection` 8444 başarılı)

---

## ÖNERİLEN DÜZELME (UYGULANMAYACAK)

1. `sudo systemctl start novagate-db` — DB servisini başlat (127.0.0.1:54321)
2. `sudo systemctl enable novagate-db` — reboot sonrası otomatik başlatma
3. Yeniden dene: `c_attach_token` artık `verify_and_consume_token` üzerinden doğrulanmalı

Bu adımlar rapor kapsamında sadece öneridir; **uygulanmamıştır.**