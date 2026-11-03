import sqlite3
import sys

def col_exists(conn, table, col):
    cur = conn.execute(f"PRAGMA table_info({table})")
    return any(r[1] == col for r in cur.fetchall())

def table_exists(conn, table):
    cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
    return cur.fetchone() is not None

db_paths = [
    '/opt/novagate/server/novagate_auth.db',
    '/opt/novagate/server/novagate_game.db',
]

for db_path in db_paths:
    print(f"=== {db_path} ===")
    conn = sqlite3.connect(db_path)

    # accounts tablosu kolonlari
    if not col_exists(conn, 'accounts', 'is_admin'):
        conn.execute("ALTER TABLE accounts ADD COLUMN is_admin INTEGER DEFAULT 0")
        print("  accounts.is_admin eklendi")
    else:
        print("  accounts.is_admin zaten var")

    if not col_exists(conn, 'accounts', 'ban_reason'):
        conn.execute("ALTER TABLE accounts ADD COLUMN ban_reason TEXT DEFAULT NULL")
        print("  accounts.ban_reason eklendi")
    else:
        print("  accounts.ban_reason zaten var")

    if not col_exists(conn, 'accounts', 'is_banned'):
        conn.execute("ALTER TABLE accounts ADD COLUMN is_banned INTEGER DEFAULT 0")
        print("  accounts.is_banned eklendi")
    else:
        print("  accounts.is_banned zaten var")

    if not col_exists(conn, 'accounts', 'ban_until'):
        conn.execute("ALTER TABLE accounts ADD COLUMN ban_until INTEGER DEFAULT 0")
        print("  accounts.ban_until eklendi")
    else:
        print("  accounts.ban_until zaten var")

    if not col_exists(conn, 'accounts', 'is_muted'):
        conn.execute("ALTER TABLE accounts ADD COLUMN is_muted INTEGER DEFAULT 0")
        print("  accounts.is_muted eklendi")
    else:
        print("  accounts.is_muted zaten var")

    if not col_exists(conn, 'accounts', 'mute_until'):
        conn.execute("ALTER TABLE accounts ADD COLUMN mute_until INTEGER DEFAULT 0")
        print("  accounts.mute_until eklendi")
    else:
        print("  accounts.mute_until zaten var")

    # admin_log tablo
    if not table_exists(conn, 'admin_log'):
        conn.execute("""CREATE TABLE IF NOT EXISTS admin_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            admin_user TEXT NOT NULL,
            action TEXT NOT NULL,
            target_type TEXT NOT NULL,
            target_id TEXT NOT NULL,
            detail TEXT,
            created_at INTEGER NOT NULL
        )""")
        print("  admin_log tablo olusturuldu")
    else:
        print("  admin_log zaten var")

    # npc_overrides tablo
    if not table_exists(conn, 'npc_overrides'):
        conn.execute("""CREATE TABLE IF NOT EXISTS npc_overrides (
            map_id TEXT PRIMARY KEY,
            npc_count INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
        )""")
        print("  npc_overrides tablo olusturuldu")
    else:
        print("  npc_overrides zaten var")

    conn.commit()
    conn.close()

print("VERITABANI_TAMAM")
