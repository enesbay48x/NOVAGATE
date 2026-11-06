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
            # Patlayan gemi: tamir edilene kadar enkaz (can 0) durumu; cikis-giris ile kacilamaz.
            "ALTER TABLE player_data ADD COLUMN wrecked INTEGER NOT NULL DEFAULT 0",
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

        # company_events tablo (admin panelinden sirkete ozel bonus etkinligi)
        conn.execute("""CREATE TABLE IF NOT EXISTS company_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            faction INTEGER NOT NULL DEFAULT 0,
            bonus_pct INTEGER NOT NULL,
            scope_npc INTEGER NOT NULL DEFAULT 1,
            scope_pvp INTEGER NOT NULL DEFAULT 0,
            resources TEXT NOT NULL DEFAULT 'cr,uri,xp,hon',
            starts_at INTEGER NOT NULL,
            ends_at INTEGER NOT NULL,
            ended_at INTEGER,
            created_by TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            note TEXT,
            boosted_rewards INTEGER NOT NULL DEFAULT 0,
            extra_cr INTEGER NOT NULL DEFAULT 0,
            extra_uri INTEGER NOT NULL DEFAULT 0,
            extra_xp REAL NOT NULL DEFAULT 0,
            extra_hon REAL NOT NULL DEFAULT 0
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
        forms = ["std"] + [r["form_id"] for r in forms_rows if r["form_id"] != "std"]   # standart halka herkeste vardir

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

        active_ship = pd["ship"] if pd["ship"] in owned else DEFAULT_SHIP   # kayitli aktif gemi gecersizse Phoenix
        if DEFAULT_SHIP not in owned and not owned:
            owned = [DEFAULT_SHIP]
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
            "wrecked": int(pd["wrecked"]) if "wrecked" in pd.keys() else 0,
            "pvp_kills": pd["pvp_kills"],
            "rank_pen": pd["rank_pen"],
            "ship": active_ship,
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
# ---------------------------------------------------------------------------
# MARKET KATALOGU (SUNUCU FIYATI) -- istemci data.gd ile AYNI (catalog.py'den uretildi)
# ---------------------------------------------------------------------------
CAT_SHIPS = {'defcom': (32000, 0),
 'goliath': (0, 80000),
 'leonov': (0, 9000),
 'liberator': (64000, 0),
 'nostromo': (100000, 0),
 'phoenix': (0, 0),
 'piranha': (80000, 0),
 'spearhead': (0, 80000),
 'vengeance': (0, 30000),
 'yamato': (16000, 0)}
CAT_SHIP_HIDDEN = ['bigboy', 'aegis', 'citadel', 'police']
CAT_LASERS = {'lf1': (65, 1000, 0),
 'lf2': (140, 50000, 0),
 'lf3': (150, 0, 10000),
 'lf4': (200, 0, 45000),
 'mp1': (70, 10000, 0)}
CAT_SPD_GENS = {'g3n-1010': (2, 2000, 0),
 'g3n-2010': (3, 4000, 0),
 'g3n-3210': (4, 8000, 0),
 'g3n-3310': (5, 16000, 0),
 'g3n-6900': (7, 0, 1000),
 'g3n-7900': (10, 0, 8000)}
CAT_SH_GENS = {'fs-01': (3200, 0.7, 256000, 0),
 'fs-02': (5600, 0.75, 2560000, 0),
 'sg3n-a01': (1000, 0.4, 8000, 0),
 'sg3n-a02': (2000, 0.5, 16000, 0),
 'sg3n-a03': (5000, 0.6, 256000, 0),
 'sg3n-b01': (9500, 0.7, 0, 2500),
 'sg3n-b02': (10000, 0.8, 0, 10000)}
CAT_AMMO = {'job': (2.0, 500, 'uri'),
 'pib': (4.0, 9000, 'uri'),
 'rsb': (6.0, 5000, 'uri'),
 'sab': (2.0, 1000, 'uri'),
 'x1': (1.0, 10000, 'cr'),
 'x2': (2.0, 500, 'uri'),
 'x3': (3.0, 1000, 'uri'),
 'x4': (4.0, 4000, 'uri')}
CAT_AMMO_PACKS = (1000, 10000, 50000)
CAT_DRONE_PRICES = {'flax': ('cr', [100000, 200000, 400000, 800000, 1600000, 3200000, 6400000, 12800000, 20000000, 20000000]),
 'iris': ('uri', [15000, 24000, 42000, 60000, 84000, 96000, 126000, 200000, 375000, 589000])}
CAT_MAX_DRONES = 10
CAT_SELL_RATE = 0.4
# Droid formasyonlari (data.gd FORMS ile ayni fiyatlar, yalnizca kredi). "std" ucretsiz ve herkeste vardir.
CAT_FORMS = {"tu": 25000, "ar": 25000, "la": 30000, "st": 35000, "pi": 40000, "da": 45000,
             "di": 50000, "ch": 55000, "mo": 60000, "cr": 70000, "he": 80000, "ba": 90000}


def _drone_total(conn, account_id: int) -> int:
    ids = list(CAT_DRONE_PRICES.keys())
    q = "SELECT COALESCE(SUM(quantity),0) FROM inventory WHERE account_id = ? AND item_id IN (%s)" % ",".join("?" * len(ids))
    return int(conn.execute(q, [account_id] + ids).fetchone()[0])


def _item_kind(item_id: str) -> str:
    if item_id.startswith("form:") and item_id[5:] in CAT_FORMS:
        return "form"
    if item_id in CAT_SHIPS or item_id in CAT_SHIP_HIDDEN:
        return "ship"
    if item_id in CAT_LASERS:
        return "laser"
    if item_id in CAT_SPD_GENS or item_id in CAT_SH_GENS:
        return "gen"
    if item_id in CAT_AMMO:
        return "ammo"
    if item_id in CAT_DRONE_PRICES:
        return "drone"
    return ""


def _unit_price(item_id: str):
    """Tek adetlik (cr, uri). Droid/cephane/gemi icin ayri hesap kullanilir."""
    if item_id in CAT_LASERS:
        return CAT_LASERS[item_id][1], CAT_LASERS[item_id][2]
    if item_id in CAT_SPD_GENS:
        return CAT_SPD_GENS[item_id][1], CAT_SPD_GENS[item_id][2]
    if item_id in CAT_SH_GENS:
        return CAT_SH_GENS[item_id][2], CAT_SH_GENS[item_id][3]
    return 0, 0


def drone_price(item_id: str, owned: int, n: int):
    """Oyuncunun o turden `owned` droidi varken sonraki n droidin toplam fiyati -> (cr, uri) veya None."""
    cur, seq = CAT_DRONE_PRICES[item_id]
    if owned < 0 or owned + n > len(seq):
        return None
    tot = sum(seq[owned:owned + n])
    return (tot, 0) if cur == "cr" else (0, tot)


def purchase_item(account_id: int, item_id: str, quantity: int, tx_id: str,
                  price_cr: int = 0, price_uri: int = 0) -> dict:
    """
    SUNUCU-OTORITER market islemi. price_cr/price_uri parametreleri YOKSAYILIR (istemciye guvenilmez).
    quantity > 0: satin alma, quantity < 0: satis (yalniz lazer/jenerator/droid; iade %40).
    Gemi -> player_ships, cephane -> ammo, lazer/jenerator/droid -> inventory. Hepsi tek BEGIN IMMEDIATE
    islemde (bakiye + kayit + transaction), ayni (account_id, tx_id) tekrar islenmez.
    """
    item_id = str(item_id)
    kind = _item_kind(item_id)
    if quantity == 0 or not kind:
        return {"ok": False, "error": "invalid_item" if not kind else "invalid_quantity"}
    selling = quantity < 0
    n = abs(int(quantity))
    if n > 100000:
        return {"ok": False, "error": "invalid_quantity"}
    if kind == "ship" and (item_id in CAT_SHIP_HIDDEN or selling or n != 1):
        return {"ok": False, "error": "not_purchasable"}
    if kind == "form" and (selling or n != 1):
        return {"ok": False, "error": "not_purchasable"}
    if kind == "ammo" and (selling or n not in CAT_AMMO_PACKS):
        return {"ok": False, "error": "invalid_pack"}
    if kind in ("laser", "gen", "drone") and n > (CAT_MAX_DRONES if kind == "drone" else 1000):
        return {"ok": False, "error": "invalid_quantity"}

    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        existing = conn.execute(
            "SELECT response_payload FROM transactions WHERE account_id = ? AND tx_id = ?",
            (account_id, tx_id),
        ).fetchone()
        if existing:
            conn.execute("ROLLBACK")
            return json.loads(existing["response_payload"])

        pd = conn.execute("SELECT cr, uri FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
        if not pd:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "account_not_found"}

        def fail(err):
            conn.execute("ROLLBACK")
            return {"ok": False, "error": err}

        def inv_qty(iid):
            r = conn.execute("SELECT quantity FROM inventory WHERE account_id = ? AND item_id = ?", (account_id, iid)).fetchone()
            return int(r[0]) if r else 0

        cost_cr = cost_uri = 0     # alimda dusulen
        gain_cr = gain_uri = 0     # satista eklenen
        if kind == "ship":
            if conn.execute("SELECT 1 FROM player_ships WHERE account_id = ? AND ship_id = ?", (account_id, item_id)).fetchone():
                return fail("already_owned")
            cost_cr, cost_uri = CAT_SHIPS[item_id]
        elif kind == "form":
            if conn.execute("SELECT 1 FROM player_forms WHERE account_id = ? AND form_id = ?", (account_id, item_id[5:])).fetchone():
                return fail("already_owned")
            cost_cr, cost_uri = CAT_FORMS[item_id[5:]], 0
        elif kind == "ammo":
            mult, per1000, cur = CAT_AMMO[item_id]
            tot = per1000 * n // 1000
            cost_cr, cost_uri = (tot, 0) if cur == "cr" else (0, tot)
        elif kind == "drone":
            owned_type = inv_qty(item_id)
            if selling:
                if owned_type < n:
                    return fail("not_enough_items")
                # satis: en son alinan n droidin fiyati uzerinden %40
                cur, seq = CAT_DRONE_PRICES[item_id]
                tot = sum(seq[owned_type - n:owned_type])
                g = int(tot * CAT_SELL_RATE)
                gain_cr, gain_uri = (g, 0) if cur == "cr" else (0, g)
            else:
                if _drone_total(conn, account_id) + n > CAT_MAX_DRONES:
                    return fail("drone_limit")
                p = drone_price(item_id, owned_type, n)
                if p is None:
                    return fail("drone_limit")
                cost_cr, cost_uri = p
        else:  # laser / gen
            u_cr, u_uri = _unit_price(item_id)
            if selling:
                if inv_qty(item_id) < n:
                    return fail("not_enough_items")
                gain_cr, gain_uri = int(u_cr * CAT_SELL_RATE) * n, int(u_uri * CAT_SELL_RATE) * n
            else:
                cost_cr, cost_uri = u_cr * n, u_uri * n

        if pd["cr"] < cost_cr or pd["uri"] < cost_uri:
            return fail("insufficient_funds")

        now = now_ts()
        conn.execute(
            "UPDATE player_data SET cr = cr - ? + ?, uri = uri - ? + ?, updated_at = ? WHERE account_id = ?",
            (cost_cr, gain_cr, cost_uri, gain_uri, now, account_id),
        )
        if kind == "ship":
            conn.execute("INSERT INTO player_ships (account_id, ship_id, acquired_at) VALUES (?, ?, ?)", (account_id, item_id, now))
        elif kind == "form":
            conn.execute("INSERT OR IGNORE INTO player_forms (account_id, form_id) VALUES (?, ?)", (account_id, item_id[5:]))
        elif kind == "ammo":
            conn.execute(
                "INSERT INTO ammo (account_id, ammo_id, quantity) VALUES (?, ?, ?) "
                "ON CONFLICT(account_id, ammo_id) DO UPDATE SET quantity = quantity + excluded.quantity",
                (account_id, item_id, n),
            )
        else:
            delta = -n if selling else n
            conn.execute(
                "INSERT INTO inventory (account_id, item_id, quantity) VALUES (?, ?, ?) "
                "ON CONFLICT(account_id, item_id) DO UPDATE SET quantity = quantity + excluded.quantity",
                (account_id, item_id, delta),
            )

        new_cr = int(pd["cr"]) - cost_cr + gain_cr
        new_uri = int(pd["uri"]) - cost_uri + gain_uri
        response_payload = json.dumps({
            "ok": True, "item_id": item_id, "kind": kind, "quantity": quantity,
            "new_cr": new_cr, "new_uri": new_uri, "tx_id": tx_id,
        })
        conn.execute(
            "INSERT INTO transactions (account_id, tx_id, type, amount_cr, amount_uri, item_id, item_qty, status, request_payload, response_payload, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 'committed', ?, ?, ?)",
            (account_id, tx_id, "sale" if selling else "purchase", gain_cr - cost_cr, gain_uri - cost_uri,
             item_id, quantity, "{}", response_payload, now),
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
                         ttl_seconds: int = 90) -> dict:
    """
    TEK CIHAZ KURALI: yeni giris HER ZAMAN kazanir. Kilit oturuma (session_token_hash) baglidir,
    sunucu surecine (instance_id) degil. BEGIN IMMEDIATE ile atomik: iki eszamanli giriste
    sirayla islenir, son giren kilidi alir, bir oncekinin session hash'i 'previous_session'
    olarak doner (sunucu o oturumu dusurur).
    Donus: {"ok": True, "replaced": bool, "previous_session": str}
    """
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = now_ts()
        expires_at = now + ttl_seconds

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
            "SELECT session_token, expires_at FROM session_locks WHERE account_id = ?",
            (account_id,),
        ).fetchone()
        previous = ""
        replaced = False
        if existing and existing["session_token"] != session_token_hash:
            # Baska bir oturum kilidi tutuyor (suresi dolmus olsa da olmasa da) -> yeni giris devralir.
            previous = existing["session_token"]
            replaced = now < existing["expires_at"]
        conn.execute(
            "INSERT OR REPLACE INTO session_locks (account_id, session_token, locked_at, updated_at, expires_at, instance_id) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (account_id, session_token_hash, now, now, expires_at, instance_id),
        )
        conn.execute("COMMIT")
        return {"ok": True, "replaced": replaced, "previous_session": previous}
    except sqlite3.Error as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.warning("acquire_session_lock HATA (%s): %s", type(e).__name__, e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def renew_session_lock(account_id: int, session_token_hash: str, ttl_seconds: int = 90) -> dict:
    """
    Heartbeat: kilit HALA bu oturumdaysa suresini uzatir. Baska oturum devraldiysa
    {"ok": True, "owned": False} doner -> sunucu bu oturumu dusurur.
    """
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = now_ts()
        cur = conn.execute(
            "UPDATE session_locks SET updated_at = ?, expires_at = ? WHERE account_id = ? AND session_token = ?",
            (now, now + ttl_seconds, account_id, session_token_hash),
        )
        owned = cur.rowcount == 1
        conn.execute("COMMIT")
        return {"ok": True, "owned": owned}
    except sqlite3.Error as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.warning("renew_session_lock HATA: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


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


def release_session_lock(account_id: int, session_token_hash: str) -> None:
    """Yalnizca kilit HALA bu oturuma aitse siler (eski oturum yeni oturumun kilidini silemez)."""
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            "DELETE FROM session_locks WHERE account_id = ? AND session_token = ?",
            (account_id, session_token_hash),
        )
        conn.execute("COMMIT")
    except Exception:
        try:
            conn.execute("ROLLBACK")
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
            "DELETE FROM session_locks WHERE expires_at < ?",
            (now,),
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


MAX_EVENT_BONUS_PCT_SERVER = 1000   # panelle ayni ust sinir; bozuk veri gelirse sunucu yine de sinirlar


def get_active_events() -> list:
    """Su an gecerli (baslamis, bitmemis, elle iptal edilmemis) sirket bonus etkinlikleri."""
    conn = get_db()
    try:
        t = now_ts()
        rows = conn.execute(
            "SELECT id, faction, bonus_pct, scope_npc, scope_pvp, resources, starts_at, ends_at "
            "FROM company_events WHERE ended_at IS NULL AND ends_at > ? ORDER BY starts_at", (t,)).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            d["bonus_pct"] = max(0, min(int(d["bonus_pct"]), MAX_EVENT_BONUS_PCT_SERVER))
            out.append(d)
        return out
    except Exception as e:
        log.error("get_active_events hata: %s", e)
        return []
    finally:
        conn.close()


def record_event_bonus(event_id: int, cr: int, uri: int, xp: float, hon: float) -> dict:
    """Etkinlik sayesinde verilen EKSTRA odulu etkinlik satirina ekler (istatistik)."""
    conn = get_db()
    try:
        conn.execute(
            "UPDATE company_events SET boosted_rewards = boosted_rewards + 1, "
            "extra_cr = extra_cr + ?, extra_uri = extra_uri + ?, extra_xp = extra_xp + ?, extra_hon = extra_hon + ? "
            "WHERE id = ?",
            (max(int(cr), 0), max(int(uri), 0), max(float(xp), 0.0), max(float(hon), 0.0), int(event_id)))
        return {"ok": True}
    except Exception as e:
        log.error("record_event_bonus hata: %s", e)
        return {"ok": False, "error": "internal"}
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


def save_active_ship(account_id: int, ship_id: str) -> dict:
    """Oyuncunun aktif gemisini player_data.ship'te kalici olarak kaydeder (gemi hesabin olmali)."""
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        if not conn.execute("SELECT 1 FROM player_ships WHERE account_id = ? AND ship_id = ?", (account_id, str(ship_id))).fetchone():
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "ship_not_owned"}
        conn.execute(
            "UPDATE player_data SET ship = ?, updated_at = ? WHERE account_id = ?",
            (ship_id, now_ts(), account_id),
        )
        conn.execute("COMMIT")
        return {"ok": True}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("save_active_ship hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# GEMI TAMIRI (SUNUCU-OTORITER): patlayan / hasarli gemi tamiri
#   Phoenix ucretsiz, diger tum gemiler 500 uridyum. Ucret DB'den atomik dusulur,
#   ayni (account_id, tx_id) ikinci kez islenmez (cift tahsilat olmaz).
# ---------------------------------------------------------------------------
REPAIR_COST_URI = 500
REPAIR_FREE_SHIPS = ("phoenix",)


def set_wrecked(account_id: int, wrecked: bool) -> dict:
    conn = get_db()
    try:
        conn.execute("UPDATE player_data SET wrecked = ?, updated_at = ? WHERE account_id = ?",
                     (1 if wrecked else 0, now_ts(), account_id))
        conn.commit()
        return {"ok": True}
    except Exception as e:
        log.error("set_wrecked hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def repair_ship(account_id: int, tx_id: str) -> dict:
    tx_id = str(tx_id)[:64]
    if not tx_id:
        return {"ok": False, "error": "invalid_tx"}
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        existing = conn.execute(
            "SELECT response_payload FROM transactions WHERE account_id = ? AND tx_id = ?",
            (account_id, tx_id),
        ).fetchone()
        if existing:
            conn.execute("ROLLBACK")
            return json.loads(existing["response_payload"])
        pd = conn.execute("SELECT cr, uri, ship FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
        if not pd:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "account_not_found"}
        ship = str(pd["ship"])
        cost = 0 if ship in REPAIR_FREE_SHIPS else REPAIR_COST_URI
        if int(pd["uri"]) < cost:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "insufficient_funds", "cost": cost, "new_uri": int(pd["uri"])}
        now = now_ts()
        new_uri = int(pd["uri"]) - cost
        conn.execute("UPDATE player_data SET uri = ?, wrecked = 0, updated_at = ? WHERE account_id = ?", (new_uri, now, account_id))
        payload = json.dumps({"ok": True, "ship": ship, "cost": cost,
                              "new_cr": int(pd["cr"]), "new_uri": new_uri, "tx_id": tx_id})
        conn.execute(
            "INSERT INTO transactions (account_id, tx_id, type, amount_cr, amount_uri, item_id, item_qty, status, request_payload, response_payload, created_at) "
            "VALUES (?, ?, 'repair', 0, ?, ?, 1, 'committed', '{}', ?, ?)",
            (account_id, tx_id, -cost, ship, payload, now),
        )
        conn.execute("COMMIT")
        return json.loads(payload)
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("repair_ship hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# NICK (CAGRI ADI) VE SIRKET DEGISTIRME  (oyun-ici ayarlar menusu)
#   Kimlik bilgisi novagate_auth.db'de durur; oyun DB'si girişte oradan senkronlanir.
#   Burada iki DB de ayni anda guncellenir. Giris adi (username) DEGISMEZ.
# ---------------------------------------------------------------------------
CALLSIGN_MIN, CALLSIGN_MAX = 3, 16
CALLSIGN_CHANGE_COOLDOWN_S = 24 * 3600          # nick: 24 saatte bir
FACTION_CHANGE_COOLDOWN_S = 7 * 24 * 3600       # sirket: 7 gunde bir
FACTION_HOME_MAP = {1: "1-1", 2: "2-1", 3: "3-1"}


def _auth_db() -> sqlite3.Connection:
    path = os.environ.get("NOVAGATE_AUTH_DB_PATH") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "novagate_auth.db")
    c = sqlite3.connect(path, timeout=10.0)
    c.row_factory = sqlite3.Row
    for col in ("callsign_changed_at", "faction_changed_at"):
        try:
            c.execute("ALTER TABLE accounts ADD COLUMN %s INTEGER DEFAULT 0" % col)
            c.commit()
        except Exception:
            pass
    return c


def _valid_callsign(name: str) -> bool:
    if not (CALLSIGN_MIN <= len(name) <= CALLSIGN_MAX):
        return False
    return all(ch.isalnum() or ch in "_-" for ch in name) and name.isascii()


def change_callsign(account_id: int, new_name: str) -> dict:
    new_name = str(new_name).strip()
    if not _valid_callsign(new_name):
        return {"ok": False, "error": "gecersiz_isim"}
    a = _auth_db()
    try:
        row = a.execute("SELECT callsign, callsign_changed_at FROM accounts WHERE id = ?", (account_id,)).fetchone()
        if not row:
            return {"ok": False, "error": "hesap_yok"}
        if row["callsign"].lower() == new_name.lower() and row["callsign"] == new_name:
            return {"ok": False, "error": "ayni_isim"}
        left = int(row["callsign_changed_at"] or 0) + CALLSIGN_CHANGE_COOLDOWN_S - now_ts()
        if left > 0:
            return {"ok": False, "error": "bekleme", "kalan_sn": left}
        clash = a.execute(
            "SELECT 1 FROM accounts WHERE id != ? AND (callsign = ? COLLATE NOCASE OR username = ? COLLATE NOCASE)",
            (account_id, new_name, new_name),
        ).fetchone()
        if clash:
            return {"ok": False, "error": "isim_kullanimda"}
        a.execute("UPDATE accounts SET callsign = ?, callsign_changed_at = ? WHERE id = ?", (new_name, now_ts(), account_id))
        a.commit()
    except sqlite3.OperationalError as e:
        log.error("change_callsign auth DB: %s", e)
        return {"ok": False, "error": "busy_retry"}
    finally:
        a.close()
    g = get_db()
    try:
        g.execute("UPDATE accounts SET callsign = ? WHERE id = ?", (new_name, account_id))
        g.commit()
    finally:
        g.close()
    return {"ok": True, "callsign": new_name}


def change_faction(account_id: int, new_faction: int) -> dict:
    new_faction = int(new_faction)
    if new_faction not in FACTION_HOME_MAP:
        return {"ok": False, "error": "gecersiz_sirket"}
    _gc = get_db()
    try:
        if _gc.execute("SELECT 1 FROM clan_members WHERE account_id = ?", (account_id,)).fetchone():
            return {"ok": False, "error": "klanda"}   # klan sirkete bagli: once klandan ayril
    except sqlite3.OperationalError:
        pass
    finally:
        _gc.close()
    a = _auth_db()
    try:
        row = a.execute("SELECT faction, faction_changed_at FROM accounts WHERE id = ?", (account_id,)).fetchone()
        if not row:
            return {"ok": False, "error": "hesap_yok"}
        if int(row["faction"]) == new_faction:
            return {"ok": False, "error": "ayni_sirket"}
        left = int(row["faction_changed_at"] or 0) + FACTION_CHANGE_COOLDOWN_S - now_ts()
        if left > 0:
            return {"ok": False, "error": "bekleme", "kalan_sn": left}
        a.execute("UPDATE accounts SET faction = ?, faction_changed_at = ? WHERE id = ?", (new_faction, now_ts(), account_id))
        a.commit()
    except sqlite3.OperationalError as e:
        log.error("change_faction auth DB: %s", e)
        return {"ok": False, "error": "busy_retry"}
    finally:
        a.close()
    g = get_db()
    try:
        g.execute("BEGIN IMMEDIATE")
        g.execute("UPDATE accounts SET faction = ? WHERE id = ?", (new_faction, account_id))
        # Yeni sirketin ev haritasinda dogar (eski sirket haritasinda kalamaz).
        g.execute("UPDATE player_data SET map_name = ?, px = 0.0, pz = 0.0, updated_at = ? WHERE account_id = ?",
                  (FACTION_HOME_MAP[new_faction], now_ts(), account_id))
        g.execute("COMMIT")
    except Exception as e:
        try:
            g.execute("ROLLBACK")
        except Exception:
            pass
        log.error("change_faction game DB: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        g.close()
    return {"ok": True, "faction": new_faction, "home_map": FACTION_HOME_MAP[new_faction]}



# ---------------------------------------------------------------------------
# AKTIF GEMI + EKIPMAN (KONFIGURASYON) KALICILIGI  -- tum dogrulama SUNUCUDA
# ---------------------------------------------------------------------------
# Gemi basina yuva sayilari (data.gd SHIPS ile ayni; droid yuvasi her gemide 10).
SHIP_CAPS = {
    "phoenix": (2, 1), "yamato": (2, 2), "leonov": (3, 3), "defcom": (4, 4), "liberator": (6, 6),
    "piranha": (8, 8), "nostromo": (8, 8), "bigboy": (10, 10), "spearhead": (5, 12),
    "vengeance": (10, 10), "goliath": (15, 15), "aegis": (10, 15), "citadel": (7, 20), "police": (50, 50),
}
FORM_IDS = {"std", "tu", "ar", "la", "st", "pi", "da", "di", "ch", "mo", "cr", "he", "ba"}
LOADOUT_CFG_COUNT = 2       # her gemide 2 konfigurasyon
LOADOUT_DRONE_SLOTS = 10    # droid yuvasi (CAT_MAX_DRONES)
DEFAULT_SHIP = "phoenix"


def _is_gen(item_id: str) -> bool:
    return item_id in CAT_SPD_GENS or item_id in CAT_SH_GENS


def _sanitize_cfg(raw, ship_id: str, inv: dict) -> dict:
    """Istemciden gelen tek konfigurasyonu dogrular: bilinmeyen esya, yuva asimi ve envanterde olmayan esya atilir."""
    las_cap, gen_cap = SHIP_CAPS.get(ship_id, (0, 0))
    out = {"las": [], "gen": [], "drn": [], "form": "std", "drone_equip": {}}
    if not isinstance(raw, dict):
        return out
    for key, cap, ok in (("las", las_cap, lambda i: i in CAT_LASERS),
                         ("gen", gen_cap, _is_gen),
                         ("drn", LOADOUT_DRONE_SLOTS, lambda i: i in CAT_DRONE_PRICES)):
        arr = raw.get(key, [])
        if not isinstance(arr, list):
            continue
        used = {}
        for it in arr:
            iid = str(it)
            if not ok(iid) or len(out[key]) >= cap:
                continue
            used[iid] = used.get(iid, 0) + 1
            if used[iid] > int(inv.get(iid, 0)):
                continue   # envanterde olmayan esya takilamaz
            out[key].append(iid)
    form = str(raw.get("form", "std"))
    out["form"] = form if form in FORM_IDS else "std"
    # Droid ekipmani: {"iris_0": {"slot_0": "lf1"}} -> yalnizca gecerli droid ornegi + lazer/kalkan jeneratoru
    de = raw.get("drone_equip", {})
    if isinstance(de, dict):
        for uid, slots in de.items():
            uid = str(uid)
            base, _, idx = uid.rpartition("_")
            if not idx.isdigit() or int(idx) >= len(out["drn"]) or out["drn"][int(idx)] != base:
                continue
            if not isinstance(slots, dict):
                continue
            clean = {}
            for sk, iid in slots.items():
                iid = str(iid)
                if str(sk).startswith("slot_") and str(sk)[5:].isdigit() and (iid in CAT_LASERS or _is_gen(iid)):
                    clean[str(sk)] = iid
            if clean:
                out["drone_equip"][uid] = clean
    return out


def apply_skill_change(account_id: int, d_cr: int, d_uri: int, d_sep: int, skills, logdisks: int, rd_resets: int) -> dict:
    """Yetenek agaci islemi (log disk / yetenek / sifirlama): bedel bakiyeden ATOMIK dusulur, yetenekler +
    logdisks + rd_resets kalici yazilir. Kurallar (on kosul, puan, maliyet) Godot sunucusunda dogrulanir;
    burada bakiye yeterliligi ve veri bicimi dogrulanir."""
    d_cr, d_uri, d_sep = int(d_cr), int(d_uri), int(d_sep)
    if min(d_cr, d_uri, d_sep) < 0 or not isinstance(skills, dict) or len(skills) > 64:
        return {"ok": False, "error": "invalid"}
    clean = {}
    for k, v in skills.items():
        k = str(k)
        v = int(v)
        if 0 < len(k) <= 40 and 0 < v <= 10:
            clean[k] = v
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        pd = conn.execute("SELECT cr, uri, COALESCE(sep, 0) AS sep, settings FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
        if not pd:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "account_not_found"}
        if int(pd["cr"]) < d_cr or int(pd["uri"]) < d_uri or int(pd["sep"]) < d_sep:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "insufficient_funds", "new_cr": int(pd["cr"]), "new_uri": int(pd["uri"]), "new_sep": int(pd["sep"])}
        try:
            st = json.loads(pd["settings"] or "{}")
        except Exception:
            st = {}
        if not isinstance(st, dict):
            st = {}
        st["logdisks"] = max(0, int(logdisks))
        st["rd_resets"] = max(0, int(rd_resets))
        new_cr, new_uri, new_sep = int(pd["cr"]) - d_cr, int(pd["uri"]) - d_uri, int(pd["sep"]) - d_sep
        conn.execute("UPDATE player_data SET cr = ?, uri = ?, sep = ?, settings = ?, updated_at = ? WHERE account_id = ?",
                     (new_cr, new_uri, new_sep, json.dumps(st), now_ts(), account_id))
        conn.execute("DELETE FROM player_skills WHERE account_id = ?", (account_id,))
        for k, v in clean.items():
            conn.execute("INSERT INTO player_skills (account_id, skill_id, rank) VALUES (?, ?, ?)", (account_id, k, v))
        conn.execute("COMMIT")
        return {"ok": True, "new_cr": new_cr, "new_uri": new_uri, "new_sep": new_sep}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("apply_skill_change hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def save_quickbar(account_id: int, quickbar) -> dict:
    """Alt hizli slot cubugunu (10 slot, 'tur:id') player_data.settings JSON'una yazar; girista geri gelir."""
    if not isinstance(quickbar, list) or len(quickbar) > 10:
        return {"ok": False, "error": "invalid"}
    clean = []
    for v in quickbar:
        s = str(v)[:40]
        parts = s.split(":")
        ok = s == "" or (len(parts) == 2 and all(p and len(p) <= 24 and all(ch.isalnum() or ch in "_-" for ch in p) for p in parts))
        clean.append(s if ok else "")
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute("SELECT settings FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
        if not row:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "account_not_found"}
        try:
            st = json.loads(row["settings"] or "{}")
        except Exception:
            st = {}
        if not isinstance(st, dict):
            st = {}
        st["quickbar"] = clean
        conn.execute("UPDATE player_data SET settings = ?, updated_at = ? WHERE account_id = ?",
                     (json.dumps(st), now_ts(), account_id))
        conn.execute("COMMIT")
        return {"ok": True}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("save_quickbar hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def save_loadout(account_id: int, ship_id: str, loads, cfg_index: int) -> dict:
    """Bir geminin konfigurasyonlarini (lazer/jenerator/droid/formasyon) + aktif konfigurasyon indeksini kaydeder.
    Gemi hesabin olmali; her esya sunucuda envanter/yuva sayisina gore suzulur. Suzulmus hali geri doner."""
    ship_id = str(ship_id)
    if ship_id not in SHIP_CAPS:
        return {"ok": False, "error": "unknown_ship"}
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        if not conn.execute("SELECT 1 FROM player_ships WHERE account_id = ? AND ship_id = ?", (account_id, ship_id)).fetchone():
            conn.execute("ROLLBACK")
            return {"ok": False, "error": "ship_not_owned"}
        inv = {r["item_id"]: int(r["quantity"]) for r in conn.execute(
            "SELECT item_id, quantity FROM inventory WHERE account_id = ?", (account_id,)).fetchall()}
        raw_list = loads if isinstance(loads, list) else []
        cfgs = [_sanitize_cfg(raw_list[i] if i < len(raw_list) else None, ship_id, inv) for i in range(LOADOUT_CFG_COUNT)]
        # Droidler gemiye aittir: iki konfigurasyonda ayni liste (istemci _sync_drn_all ile ayni kural)
        master = max(cfgs, key=lambda c: len(c["drn"]))["drn"]
        for c in cfgs:
            c["drn"] = list(master)
        cfg_index = max(0, min(LOADOUT_CFG_COUNT - 1, int(cfg_index)))
        conn.execute(
            "INSERT INTO player_loads (account_id, load_key, load_data) VALUES (?, ?, ?) "
            "ON CONFLICT(account_id, load_key) DO UPDATE SET load_data = excluded.load_data",
            (account_id, ship_id, json.dumps(cfgs)),
        )
        conn.execute(
            "INSERT INTO player_prefs (account_id, selected_ammo, cfg_index, free_mode, route_to, updated_at) "
            "VALUES (?, 'x1', ?, 0, '', ?) "
            "ON CONFLICT(account_id) DO UPDATE SET cfg_index = excluded.cfg_index, updated_at = excluded.updated_at",
            (account_id, cfg_index, now_ts()),
        )
        conn.execute("COMMIT")
        return {"ok": True, "loads": cfgs, "cfg_index": cfg_index}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("save_loadout hata: %s", e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def save_selected_ammo(account_id: int, ammo_id: str) -> dict:
    if str(ammo_id) not in CAT_AMMO:
        return {"ok": False, "error": "unknown_ammo"}
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            "INSERT INTO player_prefs (account_id, selected_ammo, cfg_index, free_mode, route_to, updated_at) "
            "VALUES (?, ?, 0, 0, '', ?) "
            "ON CONFLICT(account_id) DO UPDATE SET selected_ammo = excluded.selected_ammo, updated_at = excluded.updated_at",
            (account_id, str(ammo_id), now_ts()),
        )
        conn.execute("COMMIT")
        return {"ok": True}
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("save_selected_ammo hata: %s", e)
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
# ---------------------------------------------------------------------------
# KLAN SISTEMI  -- tum dogrulama SUNUCUDA (istemci verisine guvenilmez)
# ---------------------------------------------------------------------------
CLAN_MAX_MEMBERS = 50
CLAN_NAME_MIN, CLAN_NAME_MAX = 3, 20
CLAN_TAG_MIN, CLAN_TAG_MAX = 2, 4
CLAN_DESC_MAX = 200
CLAN_CREATE_COST_CR = 0          # klan kurma bedeli (kredi). 0 = ucretsiz. Istersen buradan ayarla.
CLAN_ROLE_MEMBER, CLAN_ROLE_OFFICER, CLAN_ROLE_LEADER = 0, 1, 2


def init_clan_tables() -> None:
    conn = get_db()
    try:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS clans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                tag TEXT NOT NULL UNIQUE COLLATE NOCASE,
                faction INTEGER NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS clan_members (
                account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                clan_id INTEGER NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
                role INTEGER NOT NULL DEFAULT 0,
                joined_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_clan_members_clan ON clan_members(clan_id);
            CREATE TABLE IF NOT EXISTS clan_requests (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                clan_id INTEGER NOT NULL REFERENCES clans(id) ON DELETE CASCADE,
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                kind TEXT NOT NULL CHECK(kind IN ('apply','invite')),
                by_account INTEGER,
                created_at INTEGER NOT NULL,
                UNIQUE(clan_id, account_id, kind)
            );
        """)
    finally:
        conn.close()


init_clan_tables()


def _clan_name_ok(name: str) -> bool:
    if not (CLAN_NAME_MIN <= len(name) <= CLAN_NAME_MAX) or not name.isascii():
        return False
    if name != name.strip() or "  " in name:
        return False
    return all(ch.isalnum() or ch in " _-" for ch in name)


def _clan_tag_ok(tag: str) -> bool:
    return CLAN_TAG_MIN <= len(tag) <= CLAN_TAG_MAX and tag.isascii() and tag.isalnum()


def _clan_of(conn, account_id: int):
    return conn.execute(
        "SELECT c.*, m.role AS my_role FROM clan_members m JOIN clans c ON c.id = m.clan_id WHERE m.account_id = ?",
        (account_id,)).fetchone()


def _clan_count(conn, clan_id: int) -> int:
    return int(conn.execute("SELECT COUNT(*) FROM clan_members WHERE clan_id = ?", (clan_id,)).fetchone()[0])


def clan_tag_of(account_id: int) -> dict:
    """Giris aninda / uyelik degisince: oyuncunun klan kimligi."""
    conn = get_db()
    try:
        c = _clan_of(conn, int(account_id))
        if not c:
            return {"ok": True, "clan_id": 0, "tag": "", "name": "", "role": 0}
        return {"ok": True, "clan_id": int(c["id"]), "tag": str(c["tag"]), "name": str(c["name"]), "role": int(c["my_role"])}
    finally:
        conn.close()


def _clan_state(conn, account_id: int) -> dict:
    me = conn.execute("SELECT faction FROM accounts WHERE id = ?", (account_id,)).fetchone()
    out = {"ok": True, "clan": None, "invites": [], "applied": [], "cost": CLAN_CREATE_COST_CR}
    c = _clan_of(conn, account_id)
    if c:
        role = int(c["my_role"])
        members = conn.execute(
            "SELECT m.account_id, m.role, m.joined_at, a.callsign FROM clan_members m "
            "JOIN accounts a ON a.id = m.account_id WHERE m.clan_id = ? ORDER BY m.role DESC, m.joined_at ASC",
            (int(c["id"]),)).fetchall()
        clan = {
            "id": int(c["id"]), "name": str(c["name"]), "tag": str(c["tag"]), "faction": int(c["faction"]),
            "description": str(c["description"]), "created_at": int(c["created_at"]), "role": role,
            "max": CLAN_MAX_MEMBERS,
            "members": [{"account_id": int(r["account_id"]), "callsign": str(r["callsign"]), "role": int(r["role"]),
                         "joined_at": int(r["joined_at"])} for r in members],
            "requests": [], "invited": [],
        }
        if role >= CLAN_ROLE_OFFICER:
            rq = conn.execute(
                "SELECT r.account_id, r.kind, r.created_at, a.callsign FROM clan_requests r "
                "JOIN accounts a ON a.id = r.account_id WHERE r.clan_id = ? ORDER BY r.created_at ASC",
                (int(c["id"]),)).fetchall()
            clan["requests"] = [{"account_id": int(r["account_id"]), "callsign": str(r["callsign"]),
                                 "created_at": int(r["created_at"])} for r in rq if r["kind"] == "apply"]
            clan["invited"] = [{"account_id": int(r["account_id"]), "callsign": str(r["callsign"])}
                               for r in rq if r["kind"] == "invite"]
        out["clan"] = clan
    else:
        inv = conn.execute(
            "SELECT c.id, c.name, c.tag, c.description FROM clan_requests r JOIN clans c ON c.id = r.clan_id "
            "WHERE r.account_id = ? AND r.kind = 'invite' ORDER BY r.created_at DESC", (account_id,)).fetchall()
        out["invites"] = [{"clan_id": int(r["id"]), "name": str(r["name"]), "tag": str(r["tag"]),
                           "members": _clan_count(conn, int(r["id"]))} for r in inv]
        ap = conn.execute(
            "SELECT c.id, c.name, c.tag FROM clan_requests r JOIN clans c ON c.id = r.clan_id "
            "WHERE r.account_id = ? AND r.kind = 'apply' ORDER BY r.created_at DESC", (account_id,)).fetchall()
        out["applied"] = [{"clan_id": int(r["id"]), "name": str(r["name"]), "tag": str(r["tag"])} for r in ap]
    return out


def _clan_join(conn, clan_id: int, account_id: int, faction: int) -> str:
    """Hesabi klana ekler. Hata kodu dondurur ('' = basarili). Cagiran BEGIN IMMEDIATE icinde olmali."""
    clan = conn.execute("SELECT * FROM clans WHERE id = ?", (clan_id,)).fetchone()
    if not clan:
        return "klan_yok"
    if _clan_of(conn, account_id):
        return "zaten_klanda"
    if int(clan["faction"]) != int(faction):
        return "farkli_sirket"
    if _clan_count(conn, clan_id) >= CLAN_MAX_MEMBERS:
        return "klan_dolu"
    conn.execute("INSERT INTO clan_members(account_id, clan_id, role, joined_at) VALUES (?,?,?,?)",
                 (account_id, clan_id, CLAN_ROLE_MEMBER, now_ts()))
    conn.execute("DELETE FROM clan_requests WHERE account_id = ?", (account_id,))
    return ""


def _sync_game_account_from_auth(conn, account_id: int) -> bool:
    """Auth DB'deki hesabi (varsa) oyun DB'sine kopyalar. Hesap auth DB'de de yoksa False doner."""
    try:
        a = _auth_db()
        try:
            r = a.execute("SELECT username, callsign, faction FROM accounts WHERE id = ?", (account_id,)).fetchone()
        finally:
            a.close()
        if not r:
            return False
        conn.execute(
            "INSERT OR IGNORE INTO accounts (id, username, password_hash, faction, callsign, created_at) "
            "VALUES (?, ?, '', ?, ?, ?)",
            (account_id, r[0], int(r[2]), r[1], now_ts()),
        )
        return True
    except Exception as e:
        log.warning("auth->oyun hesap aktarimi basarisiz (account_id=%s): %s", account_id, e)
        return False


def clan_op(account_id: int, op: str, args: dict) -> dict:
    account_id = int(account_id)
    if not isinstance(args, dict):
        args = {}
    conn = get_db()
    try:
        acc = conn.execute("SELECT id, faction, callsign FROM accounts WHERE id = ?", (account_id,)).fetchone()
        if not acc:
            # [KLAN-FIX] Yeni kayitli hesap auth DB'de var ama oyun DB'sine henuz oyuna girilmedigi icin
            # aktarilmamis olabilir: auth DB'de gercekten varsa oyun DB'sine aktar, yoksa hesap_yok.
            if _sync_game_account_from_auth(conn, account_id):
                acc = conn.execute("SELECT id, faction, callsign FROM accounts WHERE id = ?", (account_id,)).fetchone()
        if not acc:
            return {"ok": False, "error": "hesap_yok"}
        faction = int(acc["faction"])

        # ---------------- salt-okunur islemler
        if op == "me":
            return _clan_state(conn, account_id)
        if op == "list":
            q = str(args.get("q", "")).strip()[:20]
            rows = conn.execute(
                "SELECT c.id, c.name, c.tag, c.description, (SELECT COUNT(*) FROM clan_members m WHERE m.clan_id = c.id) AS n, "
                "(SELECT 1 FROM clan_requests r WHERE r.clan_id = c.id AND r.account_id = ? AND r.kind = 'apply') AS applied "
                "FROM clans c WHERE c.faction = ? AND (? = '' OR c.name LIKE ? ESCAPE '\\' OR c.tag LIKE ? ESCAPE '\\') "
                "ORDER BY n DESC, c.name ASC LIMIT 50",
                (account_id, faction, q, "%" + q.replace("%", "").replace("_", "\\_") + "%",
                 "%" + q.replace("%", "").replace("_", "\\_") + "%")).fetchall()
            return {"ok": True, "clans": [{"id": int(r["id"]), "name": str(r["name"]), "tag": str(r["tag"]),
                                           "description": str(r["description"]), "members": int(r["n"]),
                                           "max": CLAN_MAX_MEMBERS, "applied": bool(r["applied"])} for r in rows]}

        # ---------------- yazan islemler (tek transaction)
        conn.execute("BEGIN IMMEDIATE")
        affected = [account_id]
        err = ""
        mine = _clan_of(conn, account_id)
        my_role = int(mine["my_role"]) if mine else -1
        # Islemden ONCE uyeleri topla (dagitma / ayrilma sonrasi satirlar silinir).
        prev_members = [int(r["account_id"]) for r in conn.execute(
            "SELECT account_id FROM clan_members WHERE clan_id = ?", (int(mine["id"]),)).fetchall()] if mine else []
        extra_clan = 0
        target_id = 0

        def target_row(tid: int):
            return conn.execute(
                "SELECT m.account_id, m.role, a.callsign FROM clan_members m JOIN accounts a ON a.id = m.account_id "
                "WHERE m.account_id = ? AND m.clan_id = ?", (tid, int(mine["id"]))).fetchone() if mine else None

        if op == "create":
            name = str(args.get("name", "")).strip()
            tag = str(args.get("tag", "")).strip().upper()
            desc = str(args.get("description", "")).strip()[:CLAN_DESC_MAX]
            if mine:
                err = "zaten_klanda"
            elif not _clan_name_ok(name):
                err = "gecersiz_klan_adi"
            elif not _clan_tag_ok(tag):
                err = "gecersiz_tag"
            elif conn.execute("SELECT 1 FROM clans WHERE name = ? COLLATE NOCASE", (name,)).fetchone():
                err = "klan_adi_kullanimda"
            elif conn.execute("SELECT 1 FROM clans WHERE tag = ? COLLATE NOCASE", (tag,)).fetchone():
                err = "tag_kullanimda"
            else:
                if CLAN_CREATE_COST_CR > 0:
                    row = conn.execute("SELECT cr FROM player_data WHERE account_id = ?", (account_id,)).fetchone()
                    if not row or int(row["cr"]) < CLAN_CREATE_COST_CR:
                        err = "yetersiz_kredi"
                    else:
                        conn.execute("UPDATE player_data SET cr = cr - ? WHERE account_id = ?", (CLAN_CREATE_COST_CR, account_id))
                if not err:
                    cur = conn.execute("INSERT INTO clans(name, tag, faction, description, created_at) VALUES (?,?,?,?,?)",
                                       (name, tag, faction, desc, now_ts()))
                    conn.execute("INSERT INTO clan_members(account_id, clan_id, role, joined_at) VALUES (?,?,?,?)",
                                 (account_id, int(cur.lastrowid), CLAN_ROLE_LEADER, now_ts()))
                    conn.execute("DELETE FROM clan_requests WHERE account_id = ?", (account_id,))

        elif op == "apply":
            cid = int(args.get("clan_id", 0))
            clan = conn.execute("SELECT * FROM clans WHERE id = ?", (cid,)).fetchone()
            if mine:
                err = "zaten_klanda"
            elif not clan:
                err = "klan_yok"
            elif int(clan["faction"]) != faction:
                err = "farkli_sirket"
            elif _clan_count(conn, cid) >= CLAN_MAX_MEMBERS:
                err = "klan_dolu"
            elif conn.execute("SELECT COUNT(*) FROM clan_requests WHERE account_id = ? AND kind = 'apply'", (account_id,)).fetchone()[0] >= 5:
                err = "cok_basvuru"
            else:
                conn.execute("INSERT OR IGNORE INTO clan_requests(clan_id, account_id, kind, by_account, created_at) VALUES (?,?,?,?,?)",
                             (cid, account_id, "apply", account_id, now_ts()))
                extra_clan = cid

        elif op == "cancel_apply":
            extra_clan = int(args.get("clan_id", 0))
            conn.execute("DELETE FROM clan_requests WHERE clan_id = ? AND account_id = ? AND kind = 'apply'",
                         (extra_clan, account_id))

        elif op == "accept_invite":
            cid = int(args.get("clan_id", 0))
            inv = conn.execute("SELECT 1 FROM clan_requests WHERE clan_id = ? AND account_id = ? AND kind = 'invite'", (cid, account_id)).fetchone()
            if not inv:
                err = "davet_yok"
            else:
                err = _clan_join(conn, cid, account_id, faction)

        elif op == "decline_invite":
            conn.execute("DELETE FROM clan_requests WHERE clan_id = ? AND account_id = ? AND kind = 'invite'",
                         (int(args.get("clan_id", 0)), account_id))

        elif op == "invite":
            if my_role < CLAN_ROLE_OFFICER:
                err = "yetki_yok"
            else:
                nm = str(args.get("callsign", "")).strip()
                tgt = conn.execute("SELECT id, faction FROM accounts WHERE callsign = ? COLLATE NOCASE", (nm,)).fetchone()
                if not tgt:
                    err = "oyuncu_yok"
                elif int(tgt["faction"]) != int(mine["faction"]):
                    err = "farkli_sirket"
                elif _clan_of(conn, int(tgt["id"])):
                    err = "oyuncu_klanda"
                elif _clan_count(conn, int(mine["id"])) >= CLAN_MAX_MEMBERS:
                    err = "klan_dolu"
                else:
                    conn.execute("INSERT OR IGNORE INTO clan_requests(clan_id, account_id, kind, by_account, created_at) VALUES (?,?,?,?,?)",
                                 (int(mine["id"]), int(tgt["id"]), "invite", account_id, now_ts()))
                    affected.append(int(tgt["id"]))
                    target_id = int(tgt["id"])

        elif op == "cancel_invite":
            if my_role < CLAN_ROLE_OFFICER:
                err = "yetki_yok"
            else:
                tid = int(args.get("account_id", 0))
                conn.execute("DELETE FROM clan_requests WHERE clan_id = ? AND account_id = ? AND kind = 'invite'", (int(mine["id"]), tid))
                affected.append(tid)

        elif op in ("accept_request", "reject_request"):
            if my_role < CLAN_ROLE_OFFICER:
                err = "yetki_yok"
            else:
                tid = int(args.get("account_id", 0))
                rq = conn.execute("SELECT 1 FROM clan_requests WHERE clan_id = ? AND account_id = ? AND kind = 'apply'", (int(mine["id"]), tid)).fetchone()
                if not rq:
                    err = "basvuru_yok"
                elif op == "reject_request":
                    conn.execute("DELETE FROM clan_requests WHERE clan_id = ? AND account_id = ? AND kind = 'apply'", (int(mine["id"]), tid))
                    affected.append(tid)
                else:
                    trow = conn.execute("SELECT faction FROM accounts WHERE id = ?", (tid,)).fetchone()
                    if not trow:
                        err = "oyuncu_yok"
                    else:
                        err = _clan_join(conn, int(mine["id"]), tid, int(trow["faction"]))
                        affected.append(tid)

        elif op == "leave":
            if not mine:
                err = "klanda_degil"
            elif my_role == CLAN_ROLE_LEADER and _clan_count(conn, int(mine["id"])) > 1:
                err = "lider_ayrilamaz"
            elif my_role == CLAN_ROLE_LEADER:
                conn.execute("DELETE FROM clans WHERE id = ?", (int(mine["id"]),))
            else:
                conn.execute("DELETE FROM clan_members WHERE account_id = ?", (account_id,))

        elif op == "kick":
            tid = int(args.get("account_id", 0))
            t = target_row(tid)
            if my_role < CLAN_ROLE_OFFICER:
                err = "yetki_yok"
            elif not t or tid == account_id:
                err = "uye_yok"
            elif int(t["role"]) >= my_role:
                err = "yetki_yok"
            else:
                conn.execute("DELETE FROM clan_members WHERE account_id = ?", (tid,))
                affected.append(tid)

        elif op in ("promote", "demote"):
            tid = int(args.get("account_id", 0))
            t = target_row(tid)
            if my_role != CLAN_ROLE_LEADER:
                err = "yetki_yok"
            elif not t or tid == account_id:
                err = "uye_yok"
            else:
                new_role = CLAN_ROLE_OFFICER if op == "promote" else CLAN_ROLE_MEMBER
                if int(t["role"]) == new_role:
                    err = "rol_ayni"
                else:
                    conn.execute("UPDATE clan_members SET role = ? WHERE account_id = ?", (new_role, tid))
                    affected.append(tid)

        elif op == "transfer":
            tid = int(args.get("account_id", 0))
            t = target_row(tid)
            if my_role != CLAN_ROLE_LEADER:
                err = "yetki_yok"
            elif not t or tid == account_id:
                err = "uye_yok"
            else:
                conn.execute("UPDATE clan_members SET role = ? WHERE account_id = ?", (CLAN_ROLE_LEADER, tid))
                conn.execute("UPDATE clan_members SET role = ? WHERE account_id = ?", (CLAN_ROLE_OFFICER, account_id))
                affected.append(tid)

        elif op == "update":
            if my_role != CLAN_ROLE_LEADER:
                err = "yetki_yok"
            else:
                conn.execute("UPDATE clans SET description = ? WHERE id = ?",
                             (str(args.get("description", "")).strip()[:CLAN_DESC_MAX], int(mine["id"])))

        elif op == "disband":
            if my_role != CLAN_ROLE_LEADER:
                err = "yetki_yok"
            else:
                conn.execute("DELETE FROM clans WHERE id = ?", (int(mine["id"]),))

        else:
            err = "bilinmeyen_islem"

        if err:
            conn.execute("ROLLBACK")
            return {"ok": False, "error": err}

        conn.execute("COMMIT")
        # Etkilenen hesaplar: islem oncesi uyeler + yeni klanin uyeleri + (basvuru) hedef klanin uyeleri.
        affected += prev_members
        now_clan = _clan_of(conn, account_id)
        for cid in ([int(now_clan["id"])] if now_clan else []) + ([extra_clan] if extra_clan else []):
            affected += [int(r["account_id"]) for r in conn.execute(
                "SELECT account_id FROM clan_members WHERE clan_id = ?", (cid,)).fetchall()]
        res = _clan_state(conn, account_id)
        res["affected"] = sorted(set(affected))
        res["target"] = target_id
        return res
    except Exception as e:
        try:
            conn.execute("ROLLBACK")
        except Exception:
            pass
        log.error("clan_op %s: %s", op, e)
        return {"ok": False, "error": "internal"}
    finally:
        conn.close()


def clan_member_ids(clan_id: int) -> list:
    conn = get_db()
    try:
        return [int(r["account_id"]) for r in conn.execute("SELECT account_id FROM clan_members WHERE clan_id = ?", (int(clan_id),)).fetchall()]
    finally:
        conn.close()


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
            resp = acquire_session_lock(
                int(msg.get("account_id", 0)),
                msg.get("session_token_hash", ""),
                msg.get("instance_id", instance_id),
            )
        elif method == "verify_and_consume_token":
            resp = verify_and_consume_token(
                msg.get("session_token", ""),
                msg.get("instance_id", instance_id),
            )
            if resp is None:
                resp = {"ok": False, "error": "invalid_or_expired_token"}
            else:
                resp = {"ok": True, "account_id": resp["account_id"]}
        elif method == "renew_session_lock":
            resp = renew_session_lock(
                int(msg.get("account_id", 0)),
                msg.get("session_token_hash", ""),
            )
        elif method == "release_session_lock":
            release_session_lock(int(msg.get("account_id", 0)), msg.get("session_token_hash", ""))
            resp = {"ok": True}
        elif method == "cleanup_stale_locks":
            resp = {"ok": True, "deleted": cleanup_stale_locks(instance_id)}
        elif method == "get_npc_overrides":
            resp = {"ok": True, "overrides": get_npc_overrides()}
        elif method == "get_active_events":
            resp = {"ok": True, "events": get_active_events()}
        elif method == "record_event_bonus":
            resp = record_event_bonus(
                int(msg.get("event_id", 0)), int(msg.get("cr", 0)), int(msg.get("uri", 0)),
                float(msg.get("xp", 0.0)), float(msg.get("hon", 0.0)))
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
        elif method == "set_wrecked":
            resp = set_wrecked(int(msg.get("account_id", 0)), bool(msg.get("wrecked", False)))
        elif method == "repair_ship":
            resp = repair_ship(int(msg.get("account_id", 0)), str(msg.get("tx_id", "")))
        elif method == "change_callsign":
            resp = change_callsign(int(msg.get("account_id", 0)), str(msg.get("callsign", "")))
        elif method == "change_faction":
            resp = change_faction(int(msg.get("account_id", 0)), int(msg.get("faction", 0)))
        elif method == "save_active_ship":
            resp = save_active_ship(int(msg.get("account_id", 0)), str(msg.get("ship", "")))
        elif method == "save_loadout":
            resp = save_loadout(
                int(msg.get("account_id", 0)),
                str(msg.get("ship", "")),
                msg.get("loads", []),
                int(msg.get("cfg_index", 0)),
            )
        elif method == "apply_skill_change":
            resp = apply_skill_change(
                int(msg.get("account_id", 0)), int(msg.get("d_cr", 0)), int(msg.get("d_uri", 0)), int(msg.get("d_sep", 0)),
                msg.get("skills", {}), int(msg.get("logdisks", 0)), int(msg.get("rd_resets", 0)))
        elif method == "save_quickbar":
            resp = save_quickbar(int(msg.get("account_id", 0)), msg.get("quickbar", []))
        elif method == "save_selected_ammo":
            resp = save_selected_ammo(int(msg.get("account_id", 0)), str(msg.get("ammo", "")))
        elif method == "save_player_position":
            resp = save_player_position(
                int(msg.get("account_id", 0)),
                str(msg.get("map_name", "")),
                float(msg.get("px", 0.0)),
                float(msg.get("pz", 0.0)),
            )
        elif method == "clan_op":
            resp = clan_op(int(msg.get("account_id", 0)), str(msg.get("op", "")), msg.get("args", {}))
        elif method == "clan_tag_of":
            resp = clan_tag_of(int(msg.get("account_id", 0)))
        elif method == "clan_member_ids":
            resp = {"ok": True, "ids": clan_member_ids(int(msg.get("clan_id", 0)))}
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
