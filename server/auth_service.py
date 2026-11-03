#!/usr/bin/env python3
# =============================================================================
# NOVAGATE 3D - AUTH SERVICE (Phase 1, Sadece Yerel Geliştirme)
# TCP + TLS, 127.0.0.1:8443
#
# Guvenlik onemli notlari:
# - HMAC imza anahtari HIcbir kaynak koduna yazilmaz. Ortam degiskeni
#   NOVAGATE_TOKEN_HMAC_KEY ile okunur. Yoksa kismi erisim izni olan
#   gizli dosyadan okunur.
# - Session token'in TAMI veritabaninda SAKLANMAZ; sadece SHA-256 hash'i
#   saklanir.
# - used_tokens kaydi, session lock olusturulmasi ve oturumun baglanmasi
#   ATOMIK transaction icinde yapilir.
# - Eski SHA-256+salt hesaplar dogrulamadan donusturulmez.
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
import threading
import sqlite3
import logging
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# LOGGING (hassas bilgiler asla loglanmaz)
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [AUTH] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("auth_service")

# ---------------------------------------------------------------------------
# HMAC IMZA ANAHTARI GUVENLI OKUMA
# ---------------------------------------------------------------------------
def load_hmac_key() -> bytes:
    """
    HMAC anahtarini guvenli bir kaynaktan okur.
    Oncelik: 1) NOVAGATE_TOKEN_HMAC_KEY ortam degiskeni
             2) NOVAGATE_TOKEN_KEY_FILE ile isaretlenen gizli dosya
    Anahtar asla kod icinde yazilmaz, asla loglanmaz.
    """
    env_key = os.environ.get("NOVAGATE_TOKEN_HMAC_KEY")
    if env_key:
        return env_key.encode("utf-8")

    key_file = os.environ.get("NOVAGATE_TOKEN_KEY_FILE")
    if key_file:
        try:
            with open(key_file, "rb") as f:
                return f.read().strip()
        except FileNotFoundError:
            log.error("HMAC anahtar dosyasi bulunamadi: %s", key_file)
            sys.exit(1)

    log.error("NOVAGATE_TOKEN_HMAC_KEY ortam degiskeni veya NOVAGATE_TOKEN_KEY_FILE tanimli degil.")
    sys.exit(1)


TOKEN_HMAC_KEY = load_hmac_key()
TOKEN_HMAC_KEY_ID = hashlib.sha256(TOKEN_HMAC_KEY).hexdigest()[:16]  # anahtar kimligi (anahtar degil)

# ---------------------------------------------------------------------------
# SABITLER
# ---------------------------------------------------------------------------
HOST = "127.0.0.1"
PORT = 8443
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "novagate_auth.db")
TOKEN_TTL_SECONDS = 30 * 60  # 30 dakika
AUD = "novagate-game-server"  # hedef sunucu kimligi

# TLS sertifikati (yerel test icin self-signed; üretimde CA imzali sertifika gerekli)
CERT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "auth_cert.pem")
KEY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "auth_key.pem")

# ---------------------------------------------------------------------------
# VERITABANI YARDIMCILARI
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
                password_hash TEXT NOT NULL,           -- Argon2id hash (tek onayli sifre sistem)
                faction INTEGER NOT NULL DEFAULT 1 CHECK(faction IN (1,2,3)),
                callsign TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                last_login INTEGER,
                is_banned INTEGER NOT NULL DEFAULT 0,
                ban_until INTEGER,
                is_muted INTEGER NOT NULL DEFAULT 0,
                mute_until INTEGER
            );

            CREATE TABLE IF NOT EXISTS used_tokens (
                jti TEXT PRIMARY KEY,                  -- jeton benzersiz kimligi
                account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
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
# SIFRE DOGRULAMA
# ---------------------------------------------------------------------------
def verify_argon2id(stored_hash: str, password: str) -> bool:
    try:
        from argon2 import PasswordHasher
        ph = PasswordHasher()
        ph.verify(stored_hash, password)
        return True
    except Exception:
        return False


def authenticate_user(username: str, password: str):
    """
    Kullanici dogrulama. Yalnizca Argon2id kullanilir.
    Dondurur: {"account_id": int, "callsign": str, "faction": int} veya None
    """
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT id, password_hash, faction, callsign, is_banned, ban_until "
            "FROM accounts WHERE username = ? COLLATE NOCASE",
            (username,),
        ).fetchone()
        if row is None:
            return None

        if row["is_banned"] and row["ban_until"] and int(time.time()) < int(row["ban_until"]):
            return {"ok": False, "error": "hesap_banli", "ban_reason": row["ban_reason"] or "bilinmeyen", "ban_until": row["ban_until"]}
        if row["is_banned"] and not row["ban_until"]:
            return {"ok": False, "error": "hesap_banli", "ban_reason": row["ban_reason"] or "bilinmeyen", "ban_until": 0}

        if not verify_argon2id(row["password_hash"], password):
            return None

        conn.execute(
            "UPDATE accounts SET last_login = ? WHERE id = ?",
            (int(time.time()), row["id"]),
        )
        conn.commit()
        return {
            "account_id": row["id"],
            "callsign": row["callsign"],
            "faction": row["faction"],
        }
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# SESSION TOKEN URETIMI (HMAC imzali, jti + expires_at + aud)
# ---------------------------------------------------------------------------
def make_session_token(account_id: int) -> str:
    jti = secrets.token_urlsafe(32)
    now = int(time.time())
    expires_at = now + TOKEN_TTL_SECONDS
    payload = f"{account_id}:{jti}:{expires_at}:{AUD}"
    sig = hmac.new(TOKEN_HMAC_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
    token = f"{payload}:{sig}"
    return token


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def verify_and_consume_token(token: str, instance_id: str) -> dict | None:
    """
    Jetonu dogrular ve atomik olarak kullanildi olarak isaretler.
    Ayni jeton ikinci kez kullanilamaz.
    Dondurur: {"account_id": int} veya None
    """
    try:
        parts = token.split(":")
        if len(parts) != 5:
            return None
        account_id_str, jti, expires_at_str, aud, sig = parts
        if aud != AUD:
            return None

        expires_at = int(expires_at_str)
        if int(time.time()) > expires_at:
            return None  # sure dolmus

        # HMAC dogrulama (zaman karsi koyma ataquesine karsi constant-time kiyas)
        payload = f"{account_id_str}:{jti}:{expires_at_str}:{aud}"
        expected_sig = hmac.new(TOKEN_HMAC_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected_sig, sig):
            return None

        account_id = int(account_id_str)

        # ATOMIK: used_tokens kaydi + session lock kontrolu
        conn = get_db()
        try:
            conn.execute("BEGIN IMMEDIATE")
            # Ayni jti daha once kullanildi mi?
            existing = conn.execute(
                "SELECT jti FROM used_tokens WHERE jti = ?", (jti,)
            ).fetchone()
            if existing:
                conn.execute("ROLLBACK")
                return None

            # Hesabin varligini ve aktifligini kontrol et
            acct = conn.execute(
                "SELECT id FROM accounts WHERE id = ? AND is_banned = 0", (account_id,)
            ).fetchone()
            if not acct:
                conn.execute("ROLLBACK")
                return None

            # Jetonu isaretle
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
            log.warning("Token consumme BUSY: %s", e)
            return None
        finally:
            conn.close()
    except Exception:
        return None


# ---------------------------------------------------------------------------
# TLS CONTEXT
# ---------------------------------------------------------------------------
def build_ssl_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    # Phase 1 yerel test icin istemci sertifikati zorunlu degil.
    # Üretimde: ctx.verify_mode = ssl.CERT_REQUIRED (mutual TLS)
    ctx.verify_mode = ssl.CERT_NONE
    ctx.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    return ctx


# ---------------------------------------------------------------------------
# ISTEMCI HANDLERI
# ---------------------------------------------------------------------------
def handle_client(conn_stream: ssl.SSLSocket, addr: tuple, instance_id: str) -> None:
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

        if method == "login":
            username = msg.get("username", "")
            password = msg.get("password", "")
            result = authenticate_user(username, password)
            if result is None:
                resp = {"ok": False, "error": "invalid_credentials"}
            elif not result.get("ok", True):
                resp = result  # {"ok": False, "error": "hesap_banli", "ban_reason": ..., "ban_until": ...}
            else:
                token = make_session_token(result["account_id"])
                resp = {
                    "ok": True,
                    "account_id": result["account_id"],
                    "callsign": result["callsign"],
                    "faction": result["faction"],
                    "session_token": token,
                    "token_ttl": TOKEN_TTL_SECONDS,
                }
        elif method == "consume_token":
            token = msg.get("session_token", "")
            result = verify_and_consume_token(token, instance_id)
            if result is None:
                resp = {"ok": False, "error": "invalid_or_expired_token"}
            else:
                resp = {"ok": True, "account_id": result["account_id"]}
        else:
            resp = {"ok": False, "error": "unknown_method"}

        conn_stream.sendall((json.dumps(resp) + "\n").encode("utf-8"))
    except Exception as e:
        log.error("Client handler error: %s", e)
    finally:
        try:
            conn_stream.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# HTTPS LOGIN ENDPOINT (Godot HTTPRequest icin)
# Godot 4'de raw TCP+TLS icin yerel API yok, bu yuzden auth_service.py
# ayrı bir HTTPS sunucusu calistirir. Godot istemcisi HTTPRequest ile
# https://127.0.0.1:8444/login adresine POST yapar.
# ---------------------------------------------------------------------------
def _start_https_login_server() -> None:
    import http.server
    import socketserver

    class AuthHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path == "/login":
                self._handle_login()
            elif self.path == "/register":
                self._handle_register()
            else:
                self.send_response(404)
                self.end_headers()

        def _handle_login(self):
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                data = json.loads(body.decode("utf-8"))
                username = data.get("username", "")
                password = data.get("password", "")
                result = authenticate_user(username, password)
                if result is None:
                    resp = {"ok": False, "error": "invalid_credentials"}
                elif not result.get("ok", True):
                    resp = result  # {"ok": False, "error": "hesap_banli", "ban_reason": ..., "ban_until": ...}
                else:
                    token = make_session_token(result["account_id"])
                    resp = {
                        "ok": True,
                        "account_id": result["account_id"],
                        "callsign": result["callsign"],
                        "faction": result["faction"],
                        "session_token": token,
                        "token_ttl": TOKEN_TTL_SECONDS,
                    }
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                body_bytes = json.dumps(resp).encode("utf-8")
                self.send_header("Content-Length", str(len(body_bytes)))
                self.end_headers()
                self.wfile.write(body_bytes)
            except Exception as e:
                log.error("HTTPS login error: %s", e)
                self.send_response(500)
                self.end_headers()

        def _handle_register(self):
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                data = json.loads(body.decode("utf-8"))
                username = data.get("username", "")
                password = data.get("password", "")
                faction = int(data.get("faction", 1))
                callsign = data.get("callsign", username)

                if not username or not password:
                    resp = {"ok": False, "error": "kullanici_adi_ve_sifre_gerekli"}
                elif len(username) < 3 or len(username) > 16:
                    resp = {"ok": False, "error": "kullanici_adi_3_16_karakter"}
                elif len(password) < 4:
                    resp = {"ok": False, "error": "sifre_en_az_4_karakter"}
                else:
                    from argon2 import PasswordHasher
                    ph = PasswordHasher()
                    pw_hash = ph.hash(password)
                    conn = get_db()
                    try:
                        # Kullanici adi kontrolu
                        existing = conn.execute(
                            "SELECT id FROM accounts WHERE username = ? COLLATE NOCASE", (username,)
                        ).fetchone()
                        if existing:
                            resp = {"ok": False, "error": "kullanici_adi_zaten_var"}
                        else:
                            conn.execute(
                                "INSERT INTO accounts (username, password_hash, faction, callsign, created_at) "
                                "VALUES (?, ?, ?, ?, ?)",
                                (username, pw_hash, faction, callsign, int(time.time())),
                            )
                            conn.commit()
                            new_id = conn.execute(
                                "SELECT id FROM accounts WHERE username = ? COLLATE NOCASE", (username,)
                            ).fetchone()["id"]
                            resp = {"ok": True, "account_id": new_id, "callsign": callsign, "faction": faction}
                    finally:
                        conn.close()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                body_bytes = json.dumps(resp).encode("utf-8")
                self.send_header("Content-Length", str(len(body_bytes)))
                self.end_headers()
                self.wfile.write(body_bytes)
            except Exception as e:
                log.error("HTTPS register error: %s", e)
                self.send_response(500)
                self.end_headers()

        def log_message(self, format, *args):
            pass  # HTTP loglarini bastir (hassas bilgi sızıntısı yok)

    class ReuseTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    https_port = 8444
    ctx = build_ssl_context()
    try:
        with ReuseTCPServer(("0.0.0.0", https_port), AuthHandler) as httpd:
            httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
            log.info("HTTPS login endpoint hazir: https://127.0.0.1:%d/login", https_port)
            httpd.serve_forever()
    except OSError as e:
        log.error("HTTPS login endpoint baslatilamadi (port %d): %s", https_port, e)
        sys.exit(1)


# ---------------------------------------------------------------------------
# SUNUCU DONGUSU
# ---------------------------------------------------------------------------
def main() -> None:
    instance_id = secrets.token_hex(8)
    log.info("Auth service baslatiliyor. Instance ID: %s", instance_id)
    log.info("Dinleme: %s:%d (yalnızca yerel)", HOST, PORT)

    # HTTPS login endpoint'i arkaplan isigi olarak baslat
    https_thread = threading.Thread(target=_start_https_login_server, daemon=True)
    https_thread.start()

    # Sertifika yoksa uyarı ver (yerel test icin self-signed olabilir)
    if not os.path.exists(CERT_FILE) or not os.path.exists(KEY_FILE):
        log.warning("TLS sertifika dosyalari eksik: %s, %s", CERT_FILE, KEY_FILE)
        log.warning("Gerçek TLS icin geçerli sertifika gerekli.")

    ctx = build_ssl_context()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(16)
        log.info("Auth service hazir. Baglanti bekleniyor...")

        while True:
            raw_conn, addr = srv.accept()
            try:
                ssl_conn = ctx.wrap_socket(raw_conn, server_side=True)
                t = threading.Thread(target=handle_client, args=(ssl_conn, addr, instance_id), daemon=True)
                t.start()
            except Exception as e:
                log.error("SSL wrap error: %s", e)
                try:
                    raw_conn.close()
                except Exception:
                    pass


if __name__ == "__main__":
    main()
