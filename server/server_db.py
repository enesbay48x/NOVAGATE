#!/usr/bin/env python3
# =============================================================================
# NOVAGATE 3D - SERVER DB SERVICE (Phase 1, Sadece Yerel Geliştirme)
# TCP/JSON, 127.0.0.1:54321 (yalnızca localhost, internete acilmaz)
#
# Guvenlik onemli notlari:
# - Tum ekonomik islemler BEGIN IMMEDIATE ile atomik.
# - Bakiye kontrolu, dusumu, envanter artisi ve transaction kaydi ayni islemde.
# - SQLite WAL + foreign keys etkindir.
# - Yedekler sifrelenir, saklama politikasi uygulanir.
# =============================================================================

import socket
import json
import os
import sys
import time
import hashlib
import hmac
import sqlite3
import threading
import logging
from datetime import datetime, timezone

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [DB] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("server_db")

HOST = "127.0.0.1"
PORT = int(os.environ.get("NOVAGATE_DB_PORT", "54321"))
# Test/ops icin veritabani yolu ortam degiskeniyle degistirilebilir.
# Tanimli degilse uretimdeki varsayilan yol kullanilir (mevcut davranis korunur).
DB_PATH = os.environ.get("NOVAGATE_DB_PATH") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "novagate_game.db"
)
BACKUP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backups")
BACKUP_RETENTION_DAYS = 7
BACKUP_INTERVAL_SECONDS = 3600  # 1 saat

# ---------------------------------------------------------------------------
# VERITABANI
# ---------------------------------------------------------------------------
def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=10.0, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=5000")
    return conn


def init_db() -> None:
    conn = get_db()
    try:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
            INSERT OR IGNORE INTO schema_version VALUES (1);

            CREATE TABLE IF NOT EXISTS accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL COLLATE NOCASE,
                password_hash TEXT NOT NULL,
                legacy_sha256_hash TEXT,
                legacy_salt TEXT,
                faction INTEGER NOT NULL DEFAULT 1 CHECK(faction IN (1,2,3)),
                callsign TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                last_login INTEGER,
                is_banned INTEGER NOT NULL DEFAULT 0,
                ban_until INTEGER,
                is_muted INTEGER NOT NULL DEFAULT 0,
                mute_until INTEGER
            );

            CREATE TABLE IF NOT EXISTS player_data (
                account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                cr INTEGER NOT NULL DEFAULT 0,
                uri INTEGER NOT NULL DEFAULT 0,
                xp REAL NOT NULL DEFAULT 0.0,
                hon REAL NOT NULL DEFAULT 0.0,
                pvp_kills INTEGER NOT NULL DEFAULT 0,
                rank_pen REAL NOT NULL DEFAULT 0.0,
                ship TEXT NOT NULL DEFAULT 'phoenix',
                map_name TEXT NOT NULL DEFAULT '1-1',
                px REAL NOT NULL DEFAULT 0.0,
                pz REAL NOT NULL DEFAULT 0.0,
                kills INTEGER NOT NULL DEFAULT 0,
                skill_points INTEGER NOT NULL DEFAULT 0,
                sep INTEGER NOT NULL DEFAULT 0,
                settings TEXT NOT NULL DEFAULT '{}',
                drone_equip TEXT NOT NULL DEFAULT '{}',
                reg_ts INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS inventory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                item_id TEXT NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 0,
                UNIQUE(account_id, item_id)
            );

            CREATE TABLE IF NOT EXISTS ammo (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                ammo_id TEXT NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(account_id, ammo_id)
            );

            CREATE TABLE IF NOT EXISTS player_stats_ext (
                account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                rockets INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS player_ships (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                ship_id TEXT NOT NULL,
                acquired_at INTEGER NOT NULL,
                PRIMARY KEY(account_id, ship_id)
            );

            CREATE TABLE IF NOT EXISTS player_prefs (
                account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                selected_ammo TEXT DEFAULT 'x1',
                cfg_index INTEGER DEFAULT 0,
                free_mode INTEGER DEFAULT 0,
                route_to TEXT DEFAULT '',
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS player_drones (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                drone_id TEXT NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 0,
                equipped INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(account_id, drone_id)
            );

            CREATE TABLE IF NOT EXISTS player_quests (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                quest_id TEXT NOT NULL,
                quest_data TEXT NOT NULL DEFAULT '{}',
                PRIMARY KEY(account_id, quest_id)
            );

            CREATE TABLE IF NOT EXISTS player_skills (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                skill_id TEXT NOT NULL,
                rank INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(account_id, skill_id)
            );

            CREATE TABLE IF NOT EXISTS player_loads (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                load_key TEXT NOT NULL,
                load_data TEXT NOT NULL DEFAULT '{}',
                PRIMARY KEY(account_id, load_key)
            );

            CREATE TABLE IF NOT EXISTS player_maps_visited (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                map_name TEXT NOT NULL,
                visited_at INTEGER NOT NULL,
                PRIMARY KEY(account_id, map_name)
            );

            CREATE TABLE IF NOT EXISTS player_forms (
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                form_id TEXT NOT NULL,
                PRIMARY KEY(account_id, form_id)
            );

            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                tx_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount_cr INTEGER DEFAULT 0,
                amount_uri INTEGER DEFAULT 0,
                item_id TEXT,
                item_qty INTEGER DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'committed',
                request_payload TEXT,
                response_payload TEXT,
                created_at INTEGER NOT NULL,
                UNIQUE(account_id, tx_id)
            );

            CREATE INDEX IF NOT EXISTS idx_tx_account_tx ON transactions(account_id, tx_id);

            CREATE TABLE IF NOT EXISTS session_locks (
                account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                session_token TEXT NOT NULL,
                locked_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                instance_id TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS used_tokens (
                jti TEXT PRIMARY KEY,
                account_id INTEGER NOT NULL,
                session_lock_id INTEGER,
                used_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                instance_id TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_used_tokens_account ON used_tokens(account_id);
            CREATE INDEX IF NOT EXISTS idx_used_tokens_expires ON used_tokens(expires_at);
        """)

        # Admin panel migration: accounts kolonları (yeni veritabanlari icin CREATE TABLE ile gelmez)
        for col_sql in [
            "ALTER TABLE accounts ADD COLUMN is_admin INTEGER DEFAULT 0",
            "ALTER TABLE accounts ADD COLUMN ban_reason TEXT DEFAULT NULL",
            # Seprom (bonus/NPC odulu) mevcut player_data tablosuna eklenir; eski veriler korunur.
            "ALTER TABLE player_data ADD COLUMN sep INTEGER NOT NULL DEFAULT 0",
        ]:
            try:
                conn.execute(col_sql)
            except sqlite3.OperationalError:
                pass  # zaten varsa gec

        # admin_log tablo
        conn.execute("""CREATE TABLE IF NOT EXISTS admin_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            admin_user TEXT NOT NULL,
            action TEXT NOT NULL,
            target_type TEXT NOT NULL,
            target_id TEXT NOT NULL,
            detail TEXT,
            created_at INTEGER NOT NULL
        )""")

        # npc_overrides tablo
        conn.execute("""CREATE TABLE IF NOT EXISTS npc_overrides (
            map_id TEXT PRIMARY KEY,
            npc_count INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
        )""")
    finally:
        conn.close()

init_db()

# ---------------------------------------------------------------------------
# YARDIMCI FONKSIONLAR
# ---------------------------------------------------------------------------
def now_ts() -> int:
    return int(time.time())


def get_account_id_by_username(username: str) -> int | None:
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT id FROM accounts WHERE username = ? COLLATE NOCASE", (username,)
        ).fetchone()
        return row["id"] if row else None
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# YENI HESAP OLUSTURMA (ATOMIK: account + player_data + ships + inventory + ammo + stats)
# ---------------------------------------------------------------------------
def create_account(username: str, password_hash_argon2id: str, faction: int,
                   callsign: str, item_price_data: dict) -> dict:
    """
    Yeni hesap, baslangic gemisi ve baslangic envanteri tek atomik transaction icinde olusturulur.
    Eski kayitlar silinmez.
    """
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        # 1) Hesap
        cur = conn.execute(
            "INSERT INTO accounts (username, password_hash, faction, callsign, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (username, password_hash_argon2id, faction, callsign, now_ts()),
        )
        account_id = cur.lastrowid

        # 2) Player data (baslangic: cr=5000, uri=0, ship=phoenix, map=ev, vb.)
        home_map = {1: "1-1", 2: "2-1", 3: "3-1"}.get(faction, "1-1")
        conn.execute(
            "INSERT INTO player_data (account_id, cr, uri, ship, map_name, reg_ts, updated_at) "
            "VALUES (?, 5000, 0, 'phoenix', ?, ?, ?)",
            (account_id, home_map, now_ts(), now_ts()),
        )

        # 3) Baslangic gemi (phoenix)
        conn.execute(
            "INSERT INTO player_ships (account_id, ship_id, acquired_at) VALUES (?, 'phoenix', ?)",
            (account_id, now_ts()),
        )

        # 4) Baslangic envanteri (item_price_data'dan okunur, sunucu tarafinda belirlenir)
        for item_id, qty in item_price_data.get("start_inventory", {}).items():
            conn.execute(
                "INSERT INTO inventory (account_id, item_id, quantity) VALUES (?, ?, ?)",
                (account_id, item_id, qty),
            )

        # 5) Baslangic mermi
        for ammo_id, qty in item_price_data.get("start_ammo", {}).items():
            conn.execute(
                "INSERT INTO ammo (account_id, ammo_id, quantity) VALUES (?, ?, ?)",
                (account_id, ammo_id, qty),
            )

        # 6) Roket sayisi
        conn.execute(
            "INSERT INTO player_stats_ext (account_id, rockets) VALUES (?, 50)",
            (account_id,),
        )

        # 7) Tercihler (selected_ammo=x1, cfg_index=0, free_mode=0)
        conn.execute(
            "INSERT INTO player_prefs (account_id, selected_ammo, cfg_index, free_mode, route_to, updated_at) "
            "VALUES (?, 'x1', 0, 0, '', ?)",
            (account_id, now_ts()),
        )

        conn.execute("COMMIT")
        return {"ok": True, "account_id": account_id}
    except sqlite3.IntegrityError as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        return {"ok": False, "error": "username_exists_or_constraint"}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("create_account hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# OYUNCU TAM DURUMUNU YUKLE (TUM SV ALANI)
# ---------------------------------------------------------------------------
def load_player_state(account_id: int) -> dict | None:
    conn = get_db()
    try:
        pd = conn.execute("SELECT * FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
        if not pd:
            # Hesap var ama player_data yok (yeni kayit): baslangic verileri olustur
            # Hesap kaydi yoksa olustur (auth_service'dan gelmis olabilir)
            acct = conn.execute(
                "SELECT id FROM accounts WHERE id = ?", (account_id,)
            ).fetchone()
            if not acct:
                conn.execute("BEGIN IMMEDIATE")
                conn.execute(
                    "INSERT INTO accounts (id, username, password_hash, faction, callsign, created_at) "
                    "VALUES (?, ?, '', 1, ?, ?)",
                    (account_id, f"player_{account_id}", f"player_{account_id}", now_ts()),
                )
                conn.execute("COMMIT")
            acct_faction = conn.execute(
                "SELECT faction FROM accounts WHERE id = ?", (account_id,)
            ).fetchone()
            acct_faction = acct_faction["faction"] if acct_faction else 1
            home_map = {1: "1-1", 2: "2-1", 3: "3-1"}.get(acct_faction, "1-1")
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                "INSERT INTO player_data (account_id, cr, uri, ship, map_name, reg_ts, updated_at) "
                "VALUES (?, 5000, 0, 'phoenix', ?, ?, ?)",
                (account_id, home_map, now_ts(), now_ts()),
            )
            conn.execute(
                "INSERT INTO player_ships (account_id, ship_id, acquired_at) VALUES (?, 'phoenix', ?)",
                (account_id, now_ts()),
            )
            conn.execute(
                "INSERT INTO player_stats_ext (account_id, rockets) VALUES (?, 50)",
                (account_id,),
            )
            conn.execute(
                "INSERT INTO player_prefs (account_id, selected_ammo, cfg_index, free_mode, route_to, updated_at) "
                "VALUES (?, 'x1', 0, 0, '', ?)",
                (account_id, now_ts()),
            )
            conn.execute("COMMIT")
            pd = conn.execute("SELECT * FROM player_data WHERE account_id = ?", (account_id,)).fetchone()

        acct = conn.execute("SELECT faction, callsign, is_admin FROM accounts WHERE id = ?", (account_id,)).fetchone()
        inv_rows = conn.execute("SELECT item_id, quantity FROM inventory WHERE account_id = ?", (account_id,)).fetchall()
        inv = {r["item_id"]: r["quantity"] for r in inv_rows}

        ammo_rows = conn.execute("SELECT ammo_id, quantity FROM ammo WHERE account_id = ?", (account_id,)).fetchall()
        ammo = {r["ammo_id"]: r["quantity"] for r in ammo_rows}

        ships_rows = conn.execute("SELECT ship_id FROM player_ships WHERE account_id = ?", (account_id,)).fetchall()
        owned = [r["ship_id"] for r in ships_rows]

        drones_rows = conn.execute("SELECT drone_id, equipped FROM player_drones WHERE account_id = ?", (account_id,)).fetchall()
        drone_equip = {r["drone_id"]: bool(r["equipped"]) for r in drones_rows}

        forms_rows = conn.execute("SELECT form_id FROM player_forms WHERE account_id = ?", (account_id,)).fetchall()
        forms = [r["form_id"] for r in forms_rows]

        loads_rows = conn.execute("SELECT load_key, load_data FROM player_loads WHERE account_id = ?", (account_id,)).fetchall()
        loads = {}
        for r in loads_rows:
            try:
                loads[r["load_key"]] = json.loads(r["load_data"])
            except Exception:
                loads[r["load_key"]] = {}

        quest_rows = conn.execute("SELECT quest_id, quest_data FROM player_quests WHERE account_id = ?", (account_id,)).fetchall()
        quests = {}
        for r in quest_rows:
            try:
                quests[r["quest_id"]] = json.loads(r["quest_data"])
            except Exception:
                quests[r["quest_id"]] = {}

        skill_rows = conn.execute("SELECT skill_id, rank FROM player_skills WHERE account_id = ?", (account_id,)).fetchall()
        skills = {r["skill_id"]: int(r["rank"]) for r in skill_rows}

        map_rows = conn.execute("SELECT map_name FROM player_maps_visited WHERE account_id = ?", (account_id,)).fetchall()
        maps_visited = [r["map_name"] for r in map_rows]

        prefs = conn.execute("SELECT * FROM player_prefs WHERE account_id = ?", (account_id,)).fetchone()
        stats = conn.execute("SELECT rockets FROM player_stats_ext WHERE account_id = ?", (account_id,)).fetchone()

        return {
            "account_id": account_id,
            "faction": acct["faction"],
            "callsign": acct["callsign"],
            "is_admin": int(acct["is_admin"]) if acct and "is_admin" in acct.keys() else 0,
            "cr": pd["cr"],
            "uri": pd["uri"],
            "xp": pd["xp"],
            "hon": pd["hon"],
            "sep": pd["sep"] if "sep" in pd.keys() else 0,
            "pvp_kills": pd["pvp_kills"],
            "rank_pen": pd["rank_pen"],
            "ship": pd["ship"],
            "map": pd["map_name"],
            "px": pd["px"],
            "pz": pd["pz"],
            "kills": pd["kills"],
            "skill_points": pd["skill_points"],
            "settings": json.loads(pd["settings"]),
            "drone_equip": json.loads(pd["drone_equip"]),
            "reg_ts": pd["reg_ts"],
            "inv": inv,
            "ammo": ammo,
            "rockets": stats["rockets"] if stats else 0,
            "owned": owned,
            "forms": forms,
            "loads": loads,
            "quests": quests,
            "skills": skills,
            "maps_visited": maps_visited,
            "selected_ammo": prefs["selected_ammo"] if prefs else "x1",
            "cfg_index": prefs["cfg_index"] if prefs else 0,
            "free_mode": bool(prefs["free_mode"]) if prefs else False,
            "route_to": prefs["route_to"] if prefs else "",
        }
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# EKONOMIK ISLEM: SATIN ALMA (ATOMIC, BEGIN IMMEDIATE)
# ---------------------------------------------------------------------------
def purchase_item(account_id: int, item_id: str, quantity: int, tx_id: str,
                  price_cr: int, price_uri: int) -> dict:
    """
    Atomik satin alma.
    - quantity negatif/sifir/gecersizse RED.
    - price_cr/price_uri SUNUCU TARAFINDAN hesaplanir (istemciden gelmez).
    - Ayni (account_id, tx_id) zaten varsa cached response dondurulur (idempotency).
    - Bakiye, envanter, transaction kaydi ayni BEGIN IMMEDIATE islemde.
    """
    if quantity <= 0:
        return {"ok": False, "error": "invalid_quantity"}
    if price_cr < 0 or price_uri < 0:
        return {"ok": False, "error": "invalid_price"}

    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")

        # Idempotency kontrolu
        existing = conn.execute(
            "SELECT response_payload FROM transactions WHERE account_id = ? AND tx_id = ?",
            (account_id, tx_id),
        ).fetchone()
        if existing:
            conn.execute("ROLLBACK")
            return json.loads(existing["response_payload"])

        # Bakiye kontrolu
        pd = conn.execute("SELECT cr, uri FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
        if not pd:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "account_not_found"}
        if pd["cr"] < price_cr or pd["uri"] < price_uri:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "insufficient_funds"}

        # Dusum
        conn.execute(
            "UPDATE player_data SET cr = cr - ?, uri = uri - ?, updated_at = ? WHERE account_id = ?",
            (price_cr, price_uri, now_ts(), account_id),
        )

        # Envanter artisi
        conn.execute(
            "INSERT INTO inventory (account_id, item_id, quantity) VALUES (?, ?, ?) "
            "ON CONFLICT(account_id, item_id) DO UPDATE SET quantity = quantity + excluded.quantity",
            (account_id, item_id, quantity),
        )

        # Transaction kaydi
        response_payload = json.dumps({
            "ok": True,
            "item_id": item_id,
            "quantity": quantity,
            "new_cr": pd["cr"] - price_cr,
            "new_uri": pd["uri"] - price_uri,
            "tx_id": tx_id,
        })
        conn.execute(
            "INSERT INTO transactions (account_id, tx_id, type, amount_cr, amount_uri, item_id, item_qty, status, request_payload, response_payload, created_at) "
            "VALUES (?, ?, 'purchase', ?, ?, ?, ?, 'committed', ?, ?, ?)",
            (account_id, tx_id, -price_cr, -price_uri, item_id, quantity, "{}", response_payload, now_ts()),
        )

        conn.execute("COMMIT")
        return json.loads(response_payload)
    except sqlite3.OperationalError as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        if "locked" in str(e).lower() or "busy" in str(e).lower():
            return {"ok": False, "error": "busy_retry"}
        log.error("purchase_item operational error: %s", e)
        return {"ok": False, "error": "internal"}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("purchase_item hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# ODUL ISLEMI (ATOMIC, IDEMPOTENT): bonus kutusu / NPC / PvP
# ---------------------------------------------------------------------------
# Ayni event_id ikinci kez gelirse odul TEKRAR EKLENMEZ; ilk islemin sonucu dondurulur.
MAX_REWARD_CR = 50_000_000
MAX_REWARD_URI = 5_000_000
MAX_REWARD_XP = 50_000_000
MAX_REWARD_HON = 5_000_000
MAX_REWARD_SEP = 50_000_000
MAX_REWARD_KILLS = 10_000
MAX_REWARD_ITEMS = 1_000_000


def _reward_int(value, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _reward_float(value, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def grant_reward(account_id: int, event_id: str, source: str,
                 cr: int = 0, uri: int = 0, xp: float = 0.0, hon: float = 0.0,
                 kills: int = 0, sep: int = 0, pvp_kills: int = 0,
                 ammo: dict | None = None, items: dict | None = None,
                 meta: dict | None = None) -> dict:
    """
    Sunucu tarafindan hesaplanan odulu oyuncu hesabina ATOMIK olarak yazar.

    - cr/uri/xp/hon/kills/sep/pvp_kills player_data'ya eklenir (negatif deger RED).
    - ammo/items envanter tablolarina UPSERT ile eklenir.
    - Ayni (account_id, event_id) daha once yazildiysa hicbir sey degismez; ilk
      cevap "duplicate": true ile geri dondurulur. Bu, ayni kutu/NPC olumunun
      birden fazla odul vermesini engeller.
    - Butun yazimlar tek BEGIN IMMEDIATE islemindedir; hata olursa ROLLBACK.
    """
    event_id = str(event_id or "").strip()
    source = str(source or "reward").strip()[:40]
    if not event_id or len(event_id) > 200:
        return {"ok": False, "error": "invalid_event_id"}
    account_id = _reward_int(account_id)
    if account_id <= 0:
        return {"ok": False, "error": "invalid_account"}

    cr = _reward_int(cr)
    uri = _reward_int(uri)
    kills = _reward_int(kills)
    sep = _reward_int(sep)
    pvp_kills = _reward_int(pvp_kills)
    xp = _reward_float(xp)
    hon = _reward_float(hon)

    if any(v < 0 for v in (cr, uri, xp, hon, kills, sep, pvp_kills)):
        return {"ok": False, "error": "negative_reward"}
    if (cr > MAX_REWARD_CR or uri > MAX_REWARD_URI or xp > MAX_REWARD_XP
            or hon > MAX_REWARD_HON or sep > MAX_REWARD_SEP
            or kills > MAX_REWARD_KILLS or pvp_kills > MAX_REWARD_KILLS):
        return {"ok": False, "error": "reward_too_large"}

    clean_ammo: dict[str, int] = {}
    for k, v in (ammo or {}).items():
        key = str(k)[:64]
        qty = _reward_int(v)
        if key and qty > 0:
            clean_ammo[key] = min(qty, MAX_REWARD_ITEMS)

    clean_items: dict[str, int] = {}
    for k, v in (items or {}).items():
        key = str(k)[:64]
        qty = _reward_int(v)
        if key and qty > 0:
            clean_items[key] = min(qty, MAX_REWARD_ITEMS)

    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")

        # 1) Idempotency: ayni olay daha once yazildi mi?
        existing = conn.execute(
            "SELECT response_payload FROM transactions WHERE account_id = ? AND tx_id = ?",
            (account_id, event_id),
        ).fetchone()
        if existing:
            conn.execute("ROLLBACK")
            try:
                resp = json.loads(existing["response_payload"])
            except Exception:
                resp = {"ok": True, "event_id": event_id}
            resp["duplicate"] = True
            return resp

        pd = conn.execute(
            "SELECT cr, uri, xp, hon, kills, pvp_kills, COALESCE(sep, 0) AS sep "
            "FROM player_data WHERE account_id = ?",
            (account_id,),
        ).fetchone()
        if not pd:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "account_not_found"}

        # 2) Ekonomi / profil sayaclari
        conn.execute(
            "UPDATE player_data SET cr = cr + ?, uri = uri + ?, xp = xp + ?, "
            "hon = hon + ?, kills = kills + ?, pvp_kills = pvp_kills + ?, "
            "sep = COALESCE(sep, 0) + ?, updated_at = ? WHERE account_id = ?",
            (cr, uri, xp, hon, kills, pvp_kills, sep, now_ts(), account_id),
        )

        # 3) Mermi / envanter odulleri (varsa)
        for ammo_id, qty in clean_ammo.items():
            conn.execute(
                "INSERT INTO ammo (account_id, ammo_id, quantity) VALUES (?, ?, ?) "
                "ON CONFLICT(account_id, ammo_id) DO UPDATE SET quantity = quantity + excluded.quantity",
                (account_id, ammo_id, qty),
            )
        for item_id, qty in clean_items.items():
            conn.execute(
                "INSERT INTO inventory (account_id, item_id, quantity) VALUES (?, ?, ?) "
                "ON CONFLICT(account_id, item_id) DO UPDATE SET quantity = quantity + excluded.quantity",
                (account_id, item_id, qty),
            )

        # 4) Guncel degerleri oku (istemciye sunucu dogrulamali deger olarak gonderilir)
        new_pd = conn.execute(
            "SELECT cr, uri, xp, hon, kills, pvp_kills, COALESCE(sep, 0) AS sep "
            "FROM player_data WHERE account_id = ?",
            (account_id,),
        ).fetchone()

        response_payload = json.dumps({
            "ok": True,
            "event_id": event_id,
            "source": source,
            "reward_cr": cr,
            "reward_uri": uri,
            "reward_xp": xp,
            "reward_hon": hon,
            "reward_sep": sep,
            "reward_kills": kills,
            "reward_pvp_kills": pvp_kills,
            "ammo": clean_ammo,
            "items": clean_items,
            "new_cr": int(new_pd["cr"]),
            "new_uri": int(new_pd["uri"]),
            "new_xp": float(new_pd["xp"]),
            "new_hon": float(new_pd["hon"]),
            "new_sep": int(new_pd["sep"]),
            "new_kills": int(new_pd["kills"]),
            "new_pvp_kills": int(new_pd["pvp_kills"]),
        })

        item_id = None
        item_qty = 0
        if clean_items:
            item_id = next(iter(clean_items))
            item_qty = sum(clean_items.values())
        elif clean_ammo:
            item_id = next(iter(clean_ammo))
            item_qty = sum(clean_ammo.values())

        conn.execute(
            "INSERT INTO transactions (account_id, tx_id, type, amount_cr, amount_uri, "
            "item_id, item_qty, status, request_payload, response_payload, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 'committed', ?, ?, ?)",
            (account_id, event_id, source, cr, uri, item_id, item_qty,
             json.dumps(meta or {}), response_payload, now_ts()),
        )

        conn.execute("COMMIT")
        return json.loads(response_payload)
    except sqlite3.OperationalError as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        if "locked" in str(e).lower() or "busy" in str(e).lower():
            return {"ok": False, "error": "busy_retry"}
        log.error("grant_reward operational error: %s", e)
        return {"ok": False, "error": "internal"}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("grant_reward hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# SESSION LOCK (HEARTBEAT/LEASE)
# ---------------------------------------------------------------------------
def acquire_session_lock(account_id: int, session_token_hash: str, instance_id: str,
                         ttl_seconds: int = 1800) -> bool:
    """
    Aktif oturum kilidi alir. Zaten aktif bir kilit varsa (ve bu instance'e ait degilse) FALSE dondurur.
    """
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = now_ts()
        expires_at = now + ttl_seconds

        # [KILIT-FIX] session_locks.account_id -> accounts(id) FK'si var. Hesap auth DB'sinde
        # olusturuldugu icin oyun DB'sinde satir henuz olmayabilir; yoksa yer tutucu olustur
        # (load_player_state ile ayni degerler).
        conn.execute(
            "INSERT OR IGNORE INTO accounts (id, username, password_hash, faction, callsign, created_at) "
            "VALUES (?, ?, '', 1, ?, ?)",
            (account_id, f"player_{account_id}", f"player_{account_id}", now),
        )

        # [ISIM-FIX] Auth DB'deki gercek kullanici adi / takma ad / sirket bilgisini oyun DB'sine aktar.
        try:
            _auth_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "novagate_auth.db")
            _a = sqlite3.connect("file:" + _auth_path + "?mode=ro", uri=True, timeout=5.0)
            try:
                _r = _a.execute(
                    "SELECT username, callsign, faction FROM accounts WHERE id = ?", (account_id,)
                ).fetchone()
            finally:
                _a.close()
            if _r:
                conn.execute(
                    "UPDATE accounts SET username = ?, callsign = ?, faction = ? WHERE id = ?",
                    (_r[0], _r[1], int(_r[2]), account_id),
                )
        except Exception as _e:
            log.warning("auth bilgisi senkronlanamadi (account_id=%s): %s", account_id, _e)

        existing = conn.execute(
            "SELECT instance_id, updated_at, expires_at FROM session_locks WHERE account_id = ?",
            (account_id,),
        ).fetchone()

        if existing:
            # Ayni instance'e aitse yenile
            if existing["instance_id"] == instance_id:
                conn.execute(
                    "UPDATE session_locks SET updated_at = ?, expires_at = ?, session_token = ? WHERE account_id = ?",
                    (now, expires_at, session_token_hash, account_id),
                )
                conn.execute("COMMIT")
                return True
            # Baska instance'e ait ve sure dolmamis ise kilitli
            if now < existing["expires_at"]:
                conn.execute("ROLLBACK")
                return False
            # Sure dolmus ise temizle ve al
        conn.execute(
            "INSERT OR REPLACE INTO session_locks (account_id, session_token, locked_at, updated_at, expires_at, instance_id) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (account_id, session_token_hash, now, now, expires_at, instance_id),
        )
        conn.execute("COMMIT")
        return True
    except sqlite3.Error as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.warning("acquire_session_lock HATA (%s): %s", type(e).__name__, e)
def verify_and_consume_token(token: str, instance_id: str) -> dict | None:
    """
    Jetonu dogrular ve atomik olarak kullanildi olarak isaretler.
    Ayni jeton ikinci kez kullanilamaz.
    Dondurur: {"account_id": int} veya None
    """
    try:
        parts = token.split(":")
        if len(parts) != 5:
            log.warning("verify: RED - parca sayisi=%d (beklenen 5)", len(parts))
            return None
        account_id_str, jti, expires_at_str, aud, sig = parts

        if aud != "novagate-game-server":
            log.warning("verify: RED - aud uyusmazligi (account_id=%s)", account_id_str)
            return None

        expires_at = int(expires_at_str)
        if int(time.time()) > expires_at:
            log.warning("verify: RED - sure dolmus (account_id=%s)", account_id_str)
            return None

        # HMAC dogrulama
        TOKEN_HMAC_KEY = None
        env_key = os.environ.get("NOVAGATE_TOKEN_HMAC_KEY")
        if env_key:
            TOKEN_HMAC_KEY = env_key.encode("utf-8")
        else:
            key_file = os.environ.get("NOVAGATE_TOKEN_KEY_FILE")
            if key_file:
                try:
                    with open(key_file, "rb") as f:
                        TOKEN_HMAC_KEY = f.read().strip()
                except FileNotFoundError:
                    log.warning("verify: RED - HMAC anahtar dosyasi bulunamadi")
                    return None
        if TOKEN_HMAC_KEY is None:
            log.warning("verify: RED - HMAC anahtari yok")
            return None

        payload = f"{account_id_str}:{jti}:{expires_at_str}:{aud}"
        expected_sig = hmac.new(TOKEN_HMAC_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected_sig, sig):
            log.warning("verify: RED - HMAC uyusmazligi (account_id=%s)", account_id_str)
            return None

        account_id = int(account_id_str)

        # ATOMIK: used_tokens kaydi
        conn = get_db()
        try:
            conn.execute("BEGIN IMMEDIATE")
            existing = conn.execute(
                "SELECT jti FROM used_tokens WHERE jti = ?", (jti,)
            ).fetchone()
            if existing:
                conn.execute("ROLLBACK")
                log.warning("verify: RED - token daha once kullanildi (jti=%s)", jti[:16])
                return None

            conn.execute(
                "INSERT INTO used_tokens (jti, account_id, used_at, expires_at, instance_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (jti, account_id, int(time.time()), expires_at, instance_id),
            )
            conn.execute("COMMIT")
            return {"account_id": account_id}
        except sqlite3.OperationalError as e:
            try:
                conn.execute("ROLLBACK")
            except Exception:
                pass
            log.warning("verify: RED - veritabani hatasi: %s", str(e))
            return None
        finally:
            conn.close()
    except Exception:
        log.exception("verify: RED - beklenmeyen hata")
        return None


def release_session_lock(account_id: int, instance_id: str) -> None:
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            "DELETE FROM session_locks WHERE account_id = ? AND instance_id = ?",
            (account_id, instance_id),
        )
        conn.execute("COMMIT")
    except Exception:
        pass
    finally:
        conn.close()


def cleanup_stale_locks(current_instance_id: str) -> int:
    """
    Cleans up stale session locks that belong to other instances and have expired.
    Active locks (with heartbeat) are not deleted.
    """
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = now_ts()
        cur = conn.execute(
            "DELETE FROM session_locks WHERE instance_id != ? AND expires_at < ?",
            (current_instance_id, now),
        )
        deleted = cur.rowcount
        conn.execute("COMMIT")
        return deleted
    except Exception:
        return 0
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# YEDEKLEME (SIFRELI, WAL SAFE BACKUP API)
# ---------------------------------------------------------------------------
def get_npc_overrides() -> dict:
    """Tum harita NPC override'larini dondurur: {map_id: npc_count}."""
    conn = get_db()
    try:
        rows = conn.execute("SELECT map_id, npc_count FROM npc_overrides").fetchall()
        return {r["map_id"]: r["npc_count"] for r in rows}
    except Exception as e:
        log.error("get_npc_overrides hata: %s", e)
        return {}
    finally:
        conn.close()


def get_account_status(account_id: int) -> dict:
    """Hesap ban/mute durumunu dondurur."""
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT is_banned, ban_until, ban_reason, is_muted, mute_until, is_admin FROM accounts WHERE id = ?",
            (account_id,),
        ).fetchone()
        if not row:
            return {"ok": False, "error": "not_found"}
        now = now_ts()
        return {
            "ok": True,
            "is_banned": bool(row["is_banned"]),
            "ban_until": row["ban_until"] or 0,
            "ban_reason": row["ban_reason"],
            "is_muted": bool(row["is_muted"]),
            "mute_until": row["mute_until"] or 0,
            "ban_active": bool(row["is_banned"]) and (row["ban_until"] == 0 or now < row["ban_until"]),
            "mute_active": bool(row["is_muted"]) and (row["mute_until"] == 0 or now < row["mute_until"]),
            "is_admin": bool(row["is_admin"]),
        }
    except Exception as e:
        log.error("get_account_status hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def get_player_balance(account_id: int) -> dict:
    """Oyuncunun cr/uri bakiyesini dondurur (online bellek senkronizasyonu icin)."""
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT cr, uri FROM player_data WHERE account_id = ?",
            (account_id,),
        ).fetchone()
        if not row:
            return {"ok": False, "error": "not_found"}
        return {
            "ok": True,
            "account_id": account_id,
            "cr": row["cr"],
            "uri": row["uri"],
        }
    except Exception as e:
        log.error("get_player_balance hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def admin_ship(account_id: int, ship_id: str, add: bool) -> dict:
    """Adminlik degisikliginde police gemisini owned listesine ekle/çıkar."""
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        if add:
            conn.execute(
                "INSERT OR IGNORE INTO player_ships (account_id, ship_id, acquired_at) VALUES (?, ?, ?)",
                (account_id, ship_id, now_ts()),
            )
        else:
            conn.execute(
                "DELETE FROM player_ships WHERE account_id = ? AND ship_id = ?",
                (account_id, ship_id),
            )
        conn.execute("COMMIT")
        return {"ok": True}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("admin_ship hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def _load_backup_key() -> bytes | None:
    """
    Yedekleme sifreleme anahtarini guvenli kaynaktan okur.
    Oncelik: NOVAGATE_BACKUP_KEY ortam degiskeni,
             NOVAGATE_BACKUP_KEY_FILE ile isaretlenen gizli dosya.
    Anahtar yoksa None dondurur; cagirici buna gore karar verir.
    Anahtar asla kod icinde yazilmaz, asla loglanmaz.
    """
    env_key = os.environ.get("NOVAGATE_BACKUP_KEY")
    if env_key:
        return env_key.encode("utf-8")

    key_file = os.environ.get("NOVAGATE_BACKUP_KEY_FILE")
    if key_file:
        try:
            with open(key_file, "rb") as f:
                return f.read().strip()
        except FileNotFoundError:
            log.error("Yedekleme anahtar dosyasi bulunamadi: %s", key_file)
            return None

    return None


def encrypt_backup(src_path: str, dst_path: str, key: bytes) -> bool:
    """
    SQLite yedek dosyasini Fernet (AES-128 CBC + HMAC) ile sifreler.
    Anahtar kodda, veritabaninda veya loglarda SAKLANMAZ.
    """
    try:
        from cryptography.fernet import Fernet
        f = Fernet(key)
        with open(src_path, "rb") as src_file:
            data = src_file.read()
        token = f.encrypt(data)
        with open(dst_path, "wb") as dst_file:
            dst_file.write(token)
        return True
    except Exception as e:
        log.error("Backup sifreleme hatasi: %s", e)
        return False


def decrypt_backup(src_path: str, dst_path: str, key: bytes) -> bool:
    """
    Sifreli yedek dosyasini cozer ve SQLite veritabanina yazar.
    Yanlis anahtar veya bozuk dosya icin False dondurur.
    """
    try:
        from cryptography.fernet import Fernet, InvalidToken
        f = Fernet(key)
        with open(src_path, "rb") as src_file:
            token = src_file.read()
        data = f.decrypt(token)
        with open(dst_path, "wb") as dst_file:
            dst_file.write(data)
        return True
    except InvalidToken:
        log.error("Backup cozulme hatasi: gecersiz anahtar veya bozuk dosya")
        return False
    except Exception as e:
        log.error("Backup cozumle hatasi: %s", e)
        return False


def run_backup(backup_key: bytes | None) -> dict:
    """
    SQLite online backup API ile WAL-safe yedek olusturur.
    Eger backup_key verilmemisse (None) sifreleme YAPILMADAN acik hata dondurur.
    Dondurur: {"ok": bool, "encrypted": bool, "path": str|None, "error": str|None}
    """
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = now_ts()
    backup_name = f"novagate_game_{ts}.db.bak"
    backup_path = os.path.join(BACKUP_DIR, backup_name)

    # SQLite online backup API (WAL-safe)
    src = get_db()
    try:
        dst = sqlite3.connect(backup_path)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()

    # Eger anahtar yoksa sifreleme YAPILMADAN acik hata dondur (plan geregi)
    if backup_key is None:
        return {
            "ok": False,
            "encrypted": False,
            "path": backup_path,
            "error": "BACKUP_KEY_YOK: yedekleme sifreleme anahtari tanimli degil, sifresiz yedek olusturulmadi",
        }

    # Sifreli yedek olustur
    encrypted_path = backup_path + ".enc"
    ok = encrypt_backup(backup_path, encrypted_path, backup_key)
    if not ok:
        return {"ok": False, "encrypted": False, "path": None, "error": "sifreleme_basarisiz"}

    # Sifresiz gecici dosyayi sil
    try:
        os.remove(backup_path)
    except Exception:
        pass

    # Eski yedekleri temizle (saklama politikasi)
    cutoff = now_ts() - (BACKUP_RETENTION_DAYS * 86400)
    if os.path.exists(BACKUP_DIR):
        for f_name in os.listdir(BACKUP_DIR):
            fpath = os.path.join(BACKUP_DIR, f_name)
            if os.path.isfile(fpath):
                try:
                    if os.path.getmtime(fpath) < cutoff:
                        os.remove(fpath)
                except Exception:
                    pass

    return {"ok": True, "encrypted": True, "path": encrypted_path, "error": None}


def run_restore(encrypted_path: str, backup_key: bytes, restore_db_path: str) -> dict:
    """
    Sifreli yedegi cozer ve ayrı bir test veritabanina geri yukler.
    Aktif veritabanini EZMEZ.
    Dondurur: {"ok": bool, "restored_path": str|None, "error": str|None}
    """
    try:
        from cryptography.fernet import InvalidToken
        decrypted_path = encrypted_path + ".dec"
        ok = decrypt_backup(encrypted_path, decrypted_path, backup_key)
        if not ok:
            return {"ok": False, "restored_path": None, "error": "cozulme_basarisiz_yanlis_anahtar_ya_da_bozuk_dosya"}

        # Cozulmus dosyayi hedef veritabanina kopyala (ayri test DB'si)
        import shutil
        shutil.copy2(decrypted_path, restore_db_path)
        try:
            os.remove(decrypted_path)
        except Exception:
            pass

        # Restore sonrasi veritabanini dogrula (tablo var mi?)
        conn = sqlite3.connect(restore_db_path, timeout=5.0)
        try:
            tables = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts'"
            ).fetchone()
            if not tables:
                return {"ok": False, "restored_path": restore_db_path, "error": "accounts_tablosu_yok"}
        finally:
            conn.close()

        return {"ok": True, "restored_path": restore_db_path, "error": None}
    except InvalidToken:
        return {"ok": False, "restored_path": None, "error": "gecersiz_anahtar"}
    except Exception as e:
        return {"ok": False, "restored_path": None, "error": str(e)}


# ---------------------------------------------------------------------------
# TCP/JSON SUNUCU (127.0.0.1:54321)
# ---------------------------------------------------------------------------
def handle_db_client(conn_stream: socket.socket, addr: tuple, instance_id: str) -> None:
    try:
        data = b""
        while True:
            chunk = conn_stream.recv(65536)
            if not chunk:
                break
            data += chunk
            if b"\n" in data:
                break
        if not data:
            return
        msg = json.loads(data.decode("utf-8").strip())
        method = msg.get("method")
        resp = {"ok": False, "error": "unknown_method"}

        if method == "create_account":
            resp = create_account(
                msg.get("username", ""),
                msg.get("password_hash", ""),
                int(msg.get("faction", 1)),
                msg.get("callsign", ""),
                msg.get("item_price_data", {}),
            )
        elif method == "load_player_state":
            ps = load_player_state(int(msg.get("account_id", 0)))
            resp = {"ok": True, "player_state": ps} if ps else {"ok": False, "error": "not_found"}
        elif method == "purchase_item":
            resp = purchase_item(
                int(msg.get("account_id", 0)),
                msg.get("item_id", ""),
                int(msg.get("quantity", 0)),
                msg.get("tx_id", ""),
                int(msg.get("price_cr", 0)),   # sunucu tarafinda hesaplanmis fiyat
                int(msg.get("price_uri", 0)),
            )
        elif method == "grant_reward":
            resp = grant_reward(
                int(msg.get("account_id", 0)),
                str(msg.get("event_id", "")),
                str(msg.get("source", "reward")),
                cr=msg.get("cr", 0),
                uri=msg.get("uri", 0),
                xp=msg.get("xp", 0),
                hon=msg.get("hon", 0),
                kills=msg.get("kills", 0),
                sep=msg.get("sep", 0),
                pvp_kills=msg.get("pvp_kills", 0),
                ammo=msg.get("ammo", {}) if isinstance(msg.get("ammo", {}), dict) else {},
                items=msg.get("items", {}) if isinstance(msg.get("items", {}), dict) else {},
                meta=msg.get("meta", {}) if isinstance(msg.get("meta", {}), dict) else {},
            )
        elif method == "acquire_session_lock":
            resp = {"ok": acquire_session_lock(
                int(msg.get("account_id", 0)),
                msg.get("session_token_hash", ""),
                msg.get("instance_id", instance_id),
            )}
        elif method == "verify_and_consume_token":
            resp = verify_and_consume_token(
                msg.get("session_token", ""),
                msg.get("instance_id", instance_id),
            )
            if resp is None:
                resp = {"ok": False, "error": "invalid_or_expired_token"}
            else:
                resp = {"ok": True, "account_id": resp["account_id"]}
        elif method == "release_session_lock":
            release_session_lock(int(msg.get("account_id", 0)), msg.get("instance_id", instance_id))
            resp = {"ok": True}
        elif method == "cleanup_stale_locks":
            resp = {"ok": True, "deleted": cleanup_stale_locks(instance_id)}
        elif method == "get_npc_overrides":
            resp = {"ok": True, "overrides": get_npc_overrides()}
        elif method == "get_account_status":
            resp = get_account_status(int(msg.get("account_id", 0)))
        elif method == "get_player_balance":
            resp = get_player_balance(int(msg.get("account_id", 0)))
        elif method == "admin_ship":
            resp = admin_ship(
                int(msg.get("account_id", 0)),
                str(msg.get("ship", "")),
                bool(msg.get("add", False)),
            )
        elif method == "save_player_position":
            resp = save_player_position(
                int(msg.get("account_id", 0)),
                str(msg.get("map_name", "")),
                float(msg.get("px", 0.0)),
                float(msg.get("pz", 0.0)),
            )
        elif method == "backup":
            backup_key = msg.get("backup_key", "")
            if isinstance(backup_key, str):
                backup_key = backup_key.encode("utf-8")
            resp = run_backup(backup_key if backup_key else None)
        elif method == "restore":
            encrypted_path = msg.get("encrypted_path", "")
            backup_key = msg.get("backup_key", "")
            restore_db_path = msg.get("restore_db_path", "")
            if isinstance(backup_key, str):
                backup_key = backup_key.encode("utf-8")
            resp = run_restore(encrypted_path, backup_key, restore_db_path)
        else:
            resp = {"ok": False, "error": "unknown_method"}

        conn_stream.sendall((json.dumps(resp) + "\n").encode("utf-8"))
    except Exception as e:
        log.error("DB client handler error: %s", e)
    finally:
        try:
            conn_stream.close()
        except Exception:
            pass


def save_player_position(account_id: int, map_name: str, px: float, pz: float) -> dict:
    """
    Oyuncunun mevcut konumunu kaydeder (map_name, px, pz, updated_at).
    map_name bos degismez. account_id'ye gore gunceller.
    """
    if not map_name or not isinstance(map_name, str) or map_name.strip() == "":
        return {"ok": False, "error": "empty_map_name"}
    try:
        px = float(px)
        pz = float(pz)
    except (TypeError, ValueError):
        return {"ok": False, "error": "invalid_coords"}
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            "UPDATE player_data SET map_name = ?, px = ?, pz = ?, updated_at = ? "
            "WHERE account_id = ?",
            (map_name.strip(), px, pz, now_ts(), account_id),
        )
        conn.execute("COMMIT")
        return {"ok": True}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("save_player_position hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def main() -> None:
    instance_id = hashlib.sha256(os.urandom(16)).hexdigest()[:16]
    log.info("Server DB baslatiliyor. Instance ID: %s", instance_id)
    log.info("Dinleme: %s:%d (yalnızca yerel)", HOST, PORT)

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(16)
        log.info("Server DB hazir. Baglanti bekleniyor...")

        while True:
            raw_conn, addr = srv.accept()
            t = threading.Thread(target=handle_db_client, args=(raw_conn, addr, instance_id), daemon=True)
            t.start()


if __name__ == "__main__":
    main()
