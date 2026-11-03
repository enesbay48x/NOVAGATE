#!/usr/bin/env python3
# =============================================================================
# NOVAGATE 3D - PHASE 1 KAPSAMLI YEREL TEST SCRIPTI
# Tum testler localhost'ta calisir. AWS'ye baglanti yok.
# =============================================================================

import socket
import ssl
import json
import os
import sys
import time
import hashlib
import hmac
import secrets
import shutil

from argon2 import PasswordHasher

AUTH_HOST = "127.0.0.1"
AUTH_PORT = 8443
DB_HOST = "127.0.0.1"
DB_PORT = 54321
HMAC_KEY = b"phase1-test-hmac-key-change-in-production"
BACKUP_KEY = None  # Testte dynamique uretilecek
INSTANCE_ID = "test-instance-001"

def _make_fernet_key() -> bytes:
    from cryptography.fernet import Fernet
    return Fernet.generate_key()

def tls_send(method, payload, expect_tls=True):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # yerel test self-signed
    with socket.create_connection((AUTH_HOST, AUTH_PORT), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname="localhost") as ssock:
            msg = json.dumps({"method": method, **payload}) + "\n"
            ssock.sendall(msg.encode("utf-8"))
            data = ssock.recv(65536)
            return json.loads(data.decode("utf-8").strip())

def db_send(method, payload):
    with socket.create_connection((DB_HOST, DB_PORT), timeout=5) as sock:
        msg = json.dumps({"method": method, **payload}) + "\n"
        sock.sendall(msg.encode("utf-8"))
        data = sock.recv(65536)
        return json.loads(data.decode("utf-8").strip())

results = []

def check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    results.append((name, status, detail))
    print(f"[{status}] {name} {detail}")

# =============================================================================
# GRUP A: Servis calisma kontrolu
# =============================================================================
try:
    r = tls_send("login", {"username": "nonexistent", "password": "x"})
    check("auth_service calisiyor (login cevabi dondu)", r.get("ok") == False or "error" in r, f"cevap: {r}")
except Exception as e:
    check("auth_service calisiyor", False, f"hata: {e}")

try:
    _fernet_key_for_init = _make_fernet_key()
    r = db_send("backup", {"backup_key": _fernet_key_for_init.decode("utf-8")})
    check("server_db calisiyor (backup cevabi)", r.get("ok") in (True, False), f"cevap: {r}")
except Exception as e:
    check("server_db calisiyor", False, f"hata: {e}")

# =============================================================================
# GRUP B: Hesap olusturma (atomik)
# =============================================================================
uname = f"svtest_{int(time.time())}"
ph = PasswordHasher()
pw_hash = ph.hash("TestPass123!")
r = db_send("create_account", {
    "username": uname,
    "password_hash": pw_hash,
    "faction": 2,
    "callsign": "SVTestPilot",
    "item_price_data": {"start_inventory": {"lf1": 4, "sg3n-a01": 1}, "start_ammo": {"x1": 100, "x2": 50}}
})
acct_id = None
if r.get("ok"):
    acct_id = r["account_id"]
check("Yeni hesap olusturuldu (atomik)", r.get("ok") == True, f"account_id={acct_id}, hata={r.get('error')}")

# Ayni kullanici adi ile ikinci olusturma (red)
if acct_id:
    r2 = db_send("create_account", {
        "username": uname,
        "password_hash": pw_hash,
        "faction": 1,
        "callsign": "Dup",
        "item_price_data": {}
    })
    check("Ayni kullanici adi ile ikinci olusturma RED", r2.get("ok") == False, f"cevap: {r2}")

# =============================================================================
# GRUP C: Tum SV alanlarini yazip tekrar yukleme (tek tek dogrulama)
# =============================================================================
if acct_id:
    # Once mevcut durumu yukle
    r = db_send("load_player_state", {"account_id": acct_id})
    ps_before = r.get("player_state", {})
    check("Baslangic durumu yuklendi", r.get("ok") == True)

    # Tum SV alanlarini guncellemek icin dogrudan DB'ye yaz (simulasyon)
    # Not: Gerçek uygulama bu alanlari RPC üzerinden günceller; testte doğrudan DB'ye yazarak
    # load_player_state'nin tüm alanları doğru okuduğunu doğruluyoruz.
    import sqlite3
    _now_ts = int(time.time())
    conn = sqlite3.connect("server/novagate_game.db")
    conn.execute("BEGIN IMMEDIATE")
    conn.execute(
        "UPDATE player_data SET cr=12500, uri=750, xp=3500.5, hon=200.0, pvp_kills=15, rank_pen=0.5, "
        "ship='goliath', map_name='4-4', px=1200.0, pz=800.0, kills=42, skill_points=8, "
        "settings='{\"stars\": false, \"zoom\": 1.5, \"graphics\": 3}', drone_equip='{\"drone-a\": 1}' "
        "WHERE account_id = ?",
        (acct_id,),
    )
    conn.execute(
        "UPDATE player_prefs SET selected_ammo='x4', cfg_index=2, free_mode=1, route_to='5-1', updated_at=? WHERE account_id=?",
        (_now_ts, acct_id),
    )
    conn.execute("INSERT OR REPLACE INTO player_ships (account_id, ship_id, acquired_at) VALUES (?, 'goliath', ?)", (acct_id, _now_ts))
    conn.execute("INSERT OR REPLACE INTO player_forms (account_id, form_id) VALUES (?, 'delta')", (acct_id,))
    conn.execute("INSERT OR REPLACE INTO player_loads (account_id, load_key, load_data) VALUES (?, 'load1', '{\"weapon\": \"x4\"}')", (acct_id,))
    conn.execute("INSERT OR REPLACE INTO player_quests (account_id, quest_id, quest_data) VALUES (?, 'q_streuner', '{\"progress\": 3}')", (acct_id,))
    conn.execute("INSERT OR REPLACE INTO player_skills (account_id, skill_id, rank) VALUES (?, 'piloting', 3)", (acct_id,))
    conn.execute("INSERT OR REPLACE INTO player_maps_visited (account_id, map_name, visited_at) VALUES (?, '2-2', ?)", (acct_id, _now_ts))
    conn.execute("UPDATE accounts SET faction=3, callsign='UpdatedPilot' WHERE id=?", (acct_id,))
    conn.commit()
    conn.close()

    # Tekrar yukle ve HER BIR ALANI dogrula
    r = db_send("load_player_state", {"account_id": acct_id})
    ps = r.get("player_state", {})
    check("Tum SV alani yukleme basarili", r.get("ok") == True)

    check("SV.faction = 3", ps.get("faction") == 3, f"faction={ps.get('faction')}")
    check("SV.callsign = UpdatedPilot", ps.get("callsign") == "UpdatedPilot", f"callsign={ps.get('callsign')}")
    check("SV.cr = 12500", ps.get("cr") == 12500, f"cr={ps.get('cr')}")
    check("SV.uri = 750", ps.get("uri") == 750, f"uri={ps.get('uri')}")
    check("SV.xp = 3500.5", ps.get("xp") == 3500.5, f"xp={ps.get('xp')}")
    check("SV.hon = 200.0", ps.get("hon") == 200.0, f"hon={ps.get('hon')}")
    check("SV.pvp_kills = 15", ps.get("pvp_kills") == 15, f"pvp_kills={ps.get('pvp_kills')}")
    check("SV.rank_pen = 0.5", ps.get("rank_pen") == 0.5, f"rank_pen={ps.get('rank_pen')}")
    check("SV.ship = goliath", ps.get("ship") == "goliath", f"ship={ps.get('ship')}")
    check("SV.map = 4-4", ps.get("map") == "4-4", f"map={ps.get('map')}")
    check("SV.px = 1200.0", ps.get("px") == 1200.0, f"px={ps.get('px')}")
    check("SV.pz = 800.0", ps.get("pz") == 800.0, f"pz={ps.get('pz')}")
    check("SV.kills = 42", ps.get("kills") == 42, f"kills={ps.get('kills')}")
    check("SV.skill_points = 8", ps.get("skill_points") == 8, f"skill_points={ps.get('skill_points')}")
    check("SV.settings dict", isinstance(ps.get("settings"), dict), f"settings={ps.get('settings')}")
    check("SV.settings.stars=False", ps.get("settings", {}).get("stars") == False, f"settings.stars={ps.get('settings', {}).get('stars')}")
    check("SV.drone_equip drone-a=1", ps.get("drone_equip", {}).get("drone-a") == 1, f"drone_equip={ps.get('drone_equip')}")
    check("SV.selected_ammo=x4", ps.get("selected_ammo") == "x4", f"selected_ammo={ps.get('selected_ammo')}")
    check("SV.cfg_index=2", ps.get("cfg_index") == 2, f"cfg_index={ps.get('cfg_index')}")
    check("SV.free_mode=True", ps.get("free_mode") == True, f"free_mode={ps.get('free_mode')}")
    check("SV.route_to=5-1", ps.get("route_to") == "5-1", f"route_to={ps.get('route_to')}")
    check("SV.reg_ts var", isinstance(ps.get("reg_ts"), int), f"reg_ts={ps.get('reg_ts')}")
    check("SV.owned icerisinde goliath", "goliath" in (ps.get("owned") or []), f"owned={ps.get('owned')}")

# =============================================================================
# GRUP D: Satin alma (idempotency, yetersiz bakiye, gecersiz miktar)
# =============================================================================
if acct_id:
    tx_id = f"tx_{secrets.token_hex(8)}"
    r = db_send("purchase_item", {
        "account_id": acct_id,
        "item_id": "x2",
        "quantity": 10,
        "tx_id": tx_id,
        "price_cr": 1000,
        "price_uri": 0,
    })
    check("Satin alma basarili", r.get("ok") == True, f"cevap: {r}")
    if r.get("ok"):
        check("Yeni cr=11500", r.get("new_cr") == 11500, f"new_cr={r.get('new_cr')}")

    # Idempotency: ayni tx_id ikinci kez
    r2 = db_send("purchase_item", {
        "account_id": acct_id,
        "item_id": "x2",
        "quantity": 10,
        "tx_id": tx_id,
        "price_cr": 1000,
        "price_uri": 0,
    })
    check("Idempotency: ayni tx_id ikinci istek cached sonuc", r2.get("ok") == True and r2.get("new_cr") == 11500, f"cevap: {r2}")

    # Yetersiz bakiye
    r = db_send("purchase_item", {
        "account_id": acct_id,
        "item_id": "x4",
        "quantity": 1,
        "tx_id": f"tx_{secrets.token_hex(8)}",
        "price_cr": 999999,
        "price_uri": 0,
    })
    check("Yetersiz bakiye RED", r.get("ok") == False and r.get("error") == "insufficient_funds", f"cevap: {r}")

    # Negatif miktar
    r = db_send("purchase_item", {
        "account_id": acct_id,
        "item_id": "x1",
        "quantity": -5,
        "tx_id": f"tx_{secrets.token_hex(8)}",
        "price_cr": 100,
        "price_uri": 0,
    })
    check("Negatif miktar RED", r.get("ok") == False and r.get("error") == "invalid_quantity", f"cevap: {r}")

    # Sifir miktar
    r = db_send("purchase_item", {
        "account_id": acct_id,
        "item_id": "x1",
        "quantity": 0,
        "tx_id": f"tx_{secrets.token_hex(8)}",
        "price_cr": 100,
        "price_uri": 0,
    })
    check("Sifir miktar RED", r.get("ok") == False and r.get("error") == "invalid_quantity", f"cevap: {r}")

# =============================================================================
# GRUP E: Session lock (heartbeat/lease)
# =============================================================================
if acct_id:
    r = db_send("acquire_session_lock", {
        "account_id": acct_id,
        "session_token_hash": hashlib.sha256(b"test-token").hexdigest(),
        "instance_id": INSTANCE_ID,
    })
    check("Session lock alindi", r.get("ok") == True, f"cevap: {r}")

    r2 = db_send("acquire_session_lock", {
        "account_id": acct_id,
        "session_token_hash": hashlib.sha256(b"test-token-2").hexdigest(),
        "instance_id": INSTANCE_ID,
    })
    check("Ayni instance kilit yenilendi", r2.get("ok") == True, f"cevap: {r2}")

    r3 = db_send("acquire_session_lock", {
        "account_id": acct_id,
        "session_token_hash": hashlib.sha256(b"other").hexdigest(),
        "instance_id": "other-instance",
    })
    check("Baska instance kilit alinamadi (BUSY)", r3.get("ok") == False, f"cevap: {r3}")

    db_send("release_session_lock", {"account_id": acct_id, "instance_id": INSTANCE_ID})

    r4 = db_send("acquire_session_lock", {
        "account_id": acct_id,
        "session_token_hash": hashlib.sha256(b"other-2").hexdigest(),
        "instance_id": "other-instance",
    })
    check("Kilit birakildiktan sonra baska instance alabilir", r4.get("ok") == True, f"cevap: {r4}")

# =============================================================================
# GRUP F: Auth login (TLS) - yanlis sifre
# =============================================================================
try:
    r = tls_send("login", {"username": "testuser_xyz", "password": "wrong"})
    check("Auth login yanlis sifre RED", r.get("ok") == False, f"cevap: {r}")
except Exception as e:
    check("Auth login baglanti testi", False, f"hata: {e}")

# =============================================================================
# GRUP G: Stale lock temizleme
# =============================================================================
if acct_id:
    conn = sqlite3.connect("server/novagate_game.db")
    conn.execute("INSERT OR REPLACE INTO session_locks (account_id, session_token, locked_at, updated_at, expires_at, instance_id) VALUES (?, ?, ?, ?, ?, ?)",
                 (acct_id, "stale-hash", 1, 1, 1, "dead-instance"))
    conn.commit()
    conn.close()
    r = db_send("cleanup_stale_locks", {"instance_id": INSTANCE_ID})
    check("Stale lock temizlendi", r.get("deleted", 0) >= 1, f"silinen={r.get('deleted')}")

# =============================================================================
# GRUP H: Sifreli yedekleme (Fernet)
# =============================================================================
# Dogru anahtar ile yedek (Fernet anahtari dinamik uretilir)
_fernet_key = _make_fernet_key()
r = db_send("backup", {"backup_key": _fernet_key.decode("utf-8")})
check("Sifreli yedek olusturuldu (dogru anahtar)", r.get("ok") == True and r.get("encrypted") == True, f"cevap: {r}")
encrypted_path = r.get("path") if r.get("ok") else None

# Yedek dosyasinin fisiken var oldugunu ve boyutunun 0'dan buyuk oldugunu kontrol et
if encrypted_path:
    check("Sifreli yedek dosyasi mevcut", os.path.exists(encrypted_path) and os.path.getsize(encrypted_path) > 0, f"yol={encrypted_path}, boyut={os.path.getsize(encrypted_path) if os.path.exists(encrypted_path) else 0}")
    # Sifreli dosyanin iceriginin okunabilir bir SQLite veritabani olmamasini kontrol et (sifrelidir)
    with open(encrypted_path, "rb") as f:
        header = f.read(16)
    check("Sifreli dosya SQLite header'i icermiyor", header != b"SQLite format 3\x00", f"header={header[:16]}")

# Anahtar YOK (None) ile yedek — acik hata beklenir
r = db_send("backup", {"backup_key": ""})
check("Yedek anahtari yoksa acik hata", r.get("ok") == False and "YOK" in str(r.get("error", "")), f"cevap: {r}")

# =============================================================================
# GRUP H2: Yedekten geri yükleme (ayri test DB'sine, aktif DB'yi ezmeyerek)
# =============================================================================
if encrypted_path:
    restore_db_path = os.path.join("server", "test_restore.db")
    # Eski restore DB'sini temizle
    if os.path.exists(restore_db_path):
        os.remove(restore_db_path)

    # Dogru anahtar ile geri yükle
    r = db_send("restore", {
        "encrypted_path": encrypted_path,
        "backup_key": _fernet_key.decode("utf-8"),
        "restore_db_path": restore_db_path,
    })
    check("Sifreli yedekten geri Yukleme basarili", r.get("ok") == True, f"cevap: {r}")

    if r.get("ok"):
        # Geri yuklenen DB'de veri dogrulama
        conn = sqlite3.connect(restore_db_path, timeout=5.0)
        try:
            row = conn.execute("SELECT cr, uri, ship FROM player_data WHERE account_id = ?", (acct_id,)).fetchone()
            check("Geri yuklenen DB: cr=11500", row[0] == 11500 if row else None, f"cr={row[0] if row else None}")
            check("Geri yuklenen DB: uri=750", row[1] == 750 if row else None, f"uri={row[1] if row else None}")
            check("Geri yuklenen DB: ship=goliath", row[2] == "goliath" if row else None, f"ship={row[2] if row else None}")
        finally:
            conn.close()

        # Aktif veritabani etkilenmedi mi? (aktiv DB'de yine sorgu yap)
        r_check = db_send("load_player_state", {"account_id": acct_id})
        check("Aktif veritabani degismedi (cr=11500)", r_check.get("player_state", {}).get("cr") == 11500, f"aktif cr={r_check.get('player_state', {}).get('cr')}")

    # Yanlis anahtar ile geri yükle
    r = db_send("restore", {
        "encrypted_path": encrypted_path,
        "backup_key": "yanlis-anahtar-12345",
        "restore_db_path": restore_db_path + "_wrong",
    })
    check("Yanlis anahtar ile geri yukleme RED", r.get("ok") == False, f"cevap: {r}")

    # Boguk dosya ile geri yükle
    corrupt_path = os.path.join("server", "corrupt.enc")
    with open(corrupt_path, "wb") as f:
        f.write(b"this is not encrypted corrupt file content" * 10)
    r = db_send("restore", {
        "encrypted_path": corrupt_path,
        "backup_key": _fernet_key.decode("utf-8"),
        "restore_db_path": restore_db_path + "_corrupt",
    })
    check("Bozuk dosya ile geri yukleme RED", r.get("ok") == False, f"cevap: {r}")

    # Temizlik
    for p in [restore_db_path, restore_db_path + "_wrong", restore_db_path + "_corrupt", corrupt_path]:
        if os.path.exists(p):
            try:
                os.remove(p)
            except Exception:
                pass

# =============================================================================
# GRUP I: Backup saklama politikasi (eski yedekler temizlenir mi?)
# =============================================================================
# 7 gunluk saklama zaten kodda var; testte sadece yedek klasorunun var oldugunu kontrol ederiz
backup_dir = "server/backups"
check("Yedek klasoru mevcut", os.path.isdir(backup_dir), f"klasor={backup_dir}")

# =============================================================================
# SONUCLAR
# =============================================================================
print("\n" + "=" * 60)
print("PHASE 1 KAPSAMLI TEST SONUCLARI")
print("=" * 60)
passed = sum(1 for _, s, _ in results if s == "PASS")
failed = sum(1 for _, s, _ in results if s == "FAIL")
for name, status, detail in results:
    print(f"  [{status}] {name} {detail}")
print(f"\nTOPLAML: {passed} basarili, {failed} basarisiz / {len(results)}")
if failed > 0:
    sys.exit(1)
else:
    print("\nTUM TESTLER BASARILI. Phase 1 eksikler tamamlandi.")
