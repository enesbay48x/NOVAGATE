#!/usr/bin/env python3
# =============================================================================
# NOVAGATE 3D - YONETICI KONTROL PANELI  (v2)
#
# - Sadece 127.0.0.1:8445 dinler; disariya nginx (8447, https) acar.
# - Coklu yetkili: Super Admin / Moderator rolleri, argon2 sifre + istege bagli TOTP 2FA.
# - Admin rutbesi verilince police gemisi hangara girer, alinca kaybolur.
# - Oyuncu sifresi sifirlama (mevcut sifre gorulemez: tek yonlu hash).
# - Sayfalar: Genel Bakis, Oyuncular (+ oyuncu karti), Cevrimici, Etkinlikler
#   (sirkete ozel bonus), Haritalar (NPC), Ekonomi, Loglar.
# =============================================================================

import os
import re
import sys
import time
import hmac
import base64
import hashlib
import struct
import secrets
import sqlite3
import logging
from datetime import datetime, timezone, timedelta
from functools import wraps

from flask import (Flask, request, redirect, url_for, session, flash, abort,
                   render_template, make_response, has_request_context)
from flask import g as flask_g
from jinja2 import DictLoader

try:
    from zoneinfo import ZoneInfo
    _TZ = ZoneInfo("Europe/Istanbul")
except Exception:  # tzdata yoksa sabit UTC+3
    _TZ = timezone(timedelta(hours=3))

logging.basicConfig(level=logging.INFO, format="%(asctime)s [ADMIN] %(levelname)s %(message)s")
log = logging.getLogger("admin_panel")

# ---------------------------------------------------------------------------
# AYARLAR
# ---------------------------------------------------------------------------
ADMIN_HOST = "127.0.0.1"
ADMIN_PORT = 8445
ADMIN_USER = "NOVAGATE"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
AUTH_DB = os.environ.get("NOVAGATE_AUTH_DB_PATH", "/opt/novagate/server/novagate_auth.db")
GAME_DB = os.environ.get("NOVAGATE_DB_PATH", "/opt/novagate/server/novagate_game.db")

# Sirket adlari (faction 1/2/3). Oyundaki adlara gore buradan degistirebilirsiniz.
COMPANY_NAMES = {1: "Şirket 1", 2: "Şirket 2", 3: "Şirket 3"}
COMPANY_COLORS = {1: "#3b82f6", 2: "#ef4444", 3: "#22c55e"}

# Tek seferlik kredi/uridium islem siniri KALDIRILDI (istenen miktar verilebilir).
# Etkinlik sinirlari
MAX_EVENT_BONUS_PCT = 1000        # en fazla +%1000 (= 11 kat)
MAX_EVENT_MINUTES = 24 * 60

SESSION_TIMEOUT = 30 * 60
PENDING_TIMEOUT = 5 * 60          # sifre sonrasi 2FA kodu girme suresi
MIN_PANEL_PW = 10                 # panel yetkilisi sifre alt siniri
MIN_PLAYER_PW = 6                 # panelden oyuncuya elle verilen sifre alt siniri (oyun en az 4 ister)
TOTP_ISSUER = "NovaGate"
ROLE_SUPER, ROLE_MOD = "super", "mod"
ROLE_LABELS = {ROLE_SUPER: "Süper Admin", ROLE_MOD: "Moderatör"}
FAILURE_LIMIT = 5
LOCKOUT_SECONDS = 15 * 60
PAGE_SIZE = 25

KNOWN_MAPS = ([f"1-{i}" for i in range(1, 9)] + [f"2-{i}" for i in range(1, 9)] +
              [f"3-{i}" for i in range(1, 9)] + [f"4-{i}" for i in range(1, 6)])

# ---------------------------------------------------------------------------
# SIFRE DOGRULAMA (argon2id). Hash ortam degiskeniyle de verilebilir.
# ---------------------------------------------------------------------------
ADMIN_PASSWORD_HASH = os.environ.get(
    "NOVAGATE_ADMIN_HASH",
    "$argon2id$v=19$m=65536,t=3,p=4$LDgzzc3n5bmXVyYJstyZww$74J8XW5mgHEHshqwfwxA87Bn/6aivIDlA7I/NNJpgU8",
)

try:
    from argon2 import PasswordHasher
    _ph = PasswordHasher()

    def verify_password(pw: str, h: str) -> bool:
        try:
            _ph.verify(h, pw)
            return True
        except Exception:
            return False

    def hash_password(pw: str) -> str:
        return _ph.hash(pw)

    # Kullanici adi yokken de ayni sureyi harcamak icin (kullanici adi tahminini zorlastirir)
    DUMMY_HASH = _ph.hash(secrets.token_hex(16))
except Exception:  # argon2 kurulu degil: giris KAPALI kalir (guvensiz yedege dusmeyiz)
    log.error("argon2-cffi kurulu degil! 'pip install argon2-cffi' calistirin. Giris devre disi.")

    def verify_password(pw: str, h: str) -> bool:
        return False

    def hash_password(pw: str) -> str:
        raise RuntimeError("argon2-cffi kurulu degil")

    DUMMY_HASH = ""


# ---------------------------------------------------------------------------
# KALICI GIZLI ANAHTAR (yeniden baslatinca oturumlar dusmesin)
# ---------------------------------------------------------------------------
def _load_secret() -> str:
    env = os.environ.get("NOVAGATE_ADMIN_SECRET")
    if env:
        return env
    path = os.path.join(BASE_DIR, ".admin_secret")
    try:
        with open(path, "r") as f:
            val = f.read().strip()
            if len(val) >= 32:
                return val
    except OSError:
        pass
    val = secrets.token_hex(32)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(val)
    except OSError:
        log.warning("Gizli anahtar dosyaya yazilamadi; bu calisma icin gecici anahtar kullaniliyor.")
    return val


# ---------------------------------------------------------------------------
# VERITABANI YARDIMCILARI
# ---------------------------------------------------------------------------
def get_db(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=10.0, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def now_ts() -> int:
    return int(time.time())


def _columns(conn, table):
    return {r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()}


# ---------------------------------------------------------------------------
# TOTP / 2FA (RFC 6238, SHA1, 6 hane, 30 sn) - ek kutuphane gerektirmez
# ---------------------------------------------------------------------------
def totp_new_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def _hotp(secret_b32: str, counter: int) -> str:
    key = base64.b32decode(secret_b32 + "=" * (-len(secret_b32) % 8), casefold=True)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    o = mac[-1] & 0x0F
    code = (struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{code:06d}"


def totp_verify(secret_b32: str, code: str, last_step: int = 0):
    """Kod dogruysa kullanilan zaman adimini (int), degilse None dondurur.
    +-1 adim (30 sn) tolerans. last_step'ten kucuk/esit adimlar reddedilir (ayni kod ikinci kez kullanilamaz)."""
    code = re.sub(r"\s+", "", code or "")
    if not re.fullmatch(r"\d{6}", code):
        return None
    try:
        step = int(time.time() // 30)
        for off in (0, -1, 1):
            s = step + off
            if s > int(last_step or 0) and hmac.compare_digest(_hotp(secret_b32, s), code):
                return s
    except Exception:
        return None
    return None


def ensure_schema():
    """Panelin ihtiyac duydugu tablo/sutunlari (yoksa) olusturur. Mevcut veriye dokunmaz."""
    # --- AUTH DB ---
    c = get_db(AUTH_DB)
    try:
        c.execute("""CREATE TABLE IF NOT EXISTS admin_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT, admin_user TEXT NOT NULL, action TEXT NOT NULL,
            target_type TEXT NOT NULL, target_id TEXT NOT NULL, detail TEXT, created_at INTEGER NOT NULL)""")
        c.execute("""CREATE TABLE IF NOT EXISTS panel_admins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL COLLATE NOCASE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'mod',
            totp_secret TEXT,
            totp_enabled INTEGER NOT NULL DEFAULT 0,
            totp_last_step INTEGER NOT NULL DEFAULT 0,
            active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            created_by TEXT,
            last_login INTEGER,
            pw_changed_at INTEGER)""")
        if not c.execute("SELECT 1 FROM panel_admins LIMIT 1").fetchone():
            # Ilk calistirma: mevcut tek yonetici (NOVAGATE) ayni sifresiyle Super Admin olarak devralinir.
            c.execute("INSERT INTO panel_admins (username, password_hash, role, created_at, created_by) VALUES (?,?,?,?,?)",
                      (ADMIN_USER, ADMIN_PASSWORD_HASH, ROLE_SUPER, now_ts(), "sistem"))
        cols = _columns(c, "accounts")
        for col, ddl in (("is_admin", "INTEGER DEFAULT 0"), ("ban_reason", "TEXT DEFAULT NULL")):
            if col not in cols:
                c.execute(f"ALTER TABLE accounts ADD COLUMN {col} {ddl}")
    finally:
        c.close()
    # --- GAME DB (sunucu da bu tablolari kendisi olusturur; IF NOT EXISTS ile uyumlu) ---
    g = get_db(GAME_DB)
    try:
        g.execute("""CREATE TABLE IF NOT EXISTS npc_overrides (
            map_id TEXT PRIMARY KEY, npc_count INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)""")
        g.execute("""CREATE TABLE IF NOT EXISTS company_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            faction INTEGER NOT NULL DEFAULT 0,          -- 0 = tum sirketler
            bonus_pct INTEGER NOT NULL,                  -- +% (300 => odul 4 kati)
            scope_npc INTEGER NOT NULL DEFAULT 1,
            scope_pvp INTEGER NOT NULL DEFAULT 0,
            resources TEXT NOT NULL DEFAULT 'cr,uri,xp,hon',
            starts_at INTEGER NOT NULL,
            ends_at INTEGER NOT NULL,
            ended_at INTEGER,                            -- elle erken bitirildiyse
            created_by TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            note TEXT,
            boosted_rewards INTEGER NOT NULL DEFAULT 0,
            extra_cr INTEGER NOT NULL DEFAULT 0,
            extra_uri INTEGER NOT NULL DEFAULT 0,
            extra_xp REAL NOT NULL DEFAULT 0,
            extra_hon REAL NOT NULL DEFAULT 0)""")
        g.execute("CREATE INDEX IF NOT EXISTS idx_company_events_time ON company_events(starts_at, ends_at)")
        cols = _columns(g, "accounts")
        for col, ddl in (("is_admin", "INTEGER DEFAULT 0"), ("ban_reason", "TEXT DEFAULT NULL")):
            if col not in cols:
                g.execute(f"ALTER TABLE accounts ADD COLUMN {col} {ddl}")
    finally:
        g.close()


def admin_log(action: str, target_type: str, target_id, detail: str = None, actor: str = None):
    """Tum yonetici islemleri, islemi yapan yetkili adiyla loglanir."""
    try:
        who = actor
        if who is None:
            who = (session.get("admin_user") or "?") if has_request_context() else "sistem"
        conn = get_db(AUTH_DB)
        conn.execute(
            "INSERT INTO admin_log (admin_user, action, target_type, target_id, detail, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (who, action, target_type, str(target_id), detail, now_ts()))
        conn.close()
    except Exception as e:
        log.error("admin_log yazilamadi: %s", e)


# ---------------------------------------------------------------------------
# FLASK
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.secret_key = _load_secret()
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SECURE=True,        # panel nginx uzerinden https ile acilir
    SESSION_COOKIE_SAMESITE="Strict",
    SESSION_COOKIE_NAME="ng_admin",
    MAX_CONTENT_LENGTH=64 * 1024,
)

# ---- Giris denemesi sinirlama (istemci IP'si nginx'in X-Real-IP basligindan) ----
failures = {}


def client_ip() -> str:
    # Panel sadece 127.0.0.1'e baglidir; baslik yalnizca nginx'ten gelebilir.
    if request.remote_addr in ("127.0.0.1", "::1"):
        return request.headers.get("X-Real-IP", request.remote_addr)
    return request.remote_addr


def is_locked(ip: str) -> bool:
    f = failures.get(ip)
    if not f:
        return False
    if now_ts() < f.get("locked_until", 0):
        return True
    if f.get("locked_until", 0):
        failures.pop(ip, None)
    return False


def record_failure(ip: str):
    f = failures.setdefault(ip, {"count": 0, "locked_until": 0})
    f["count"] += 1
    if f["count"] >= FAILURE_LIMIT:
        f["locked_until"] = now_ts() + LOCKOUT_SECONDS
        f["count"] = 0


def csrf_token() -> str:
    if "csrf" not in session:
        session["csrf"] = secrets.token_hex(32)
    return session["csrf"]


def check_csrf():
    sent = request.form.get("csrf_token", "")
    real = session.get("csrf", "")
    if not real or not sent or not hmac.compare_digest(sent, real):
        abort(403)


@app.before_request
def _guard():
    if request.remote_addr not in ("127.0.0.1", "::1"):
        abort(403)   # panel yalnizca nginx (yerel) uzerinden erisilebilir
    if request.method == "POST":
        check_csrf()


@app.after_request
def _headers(resp):
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["Cache-Control"] = "no-store"
    resp.headers["Content-Security-Policy"] = (
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
        "img-src 'self' data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
    return resp


def actor() -> str:
    return (session.get("admin_user") or "?") if has_request_context() else "sistem"


def get_panel_admin(aid=None, username=None):
    c = get_db(AUTH_DB)
    try:
        if aid is not None:
            r = c.execute("SELECT * FROM panel_admins WHERE id=?", (aid,)).fetchone()
        else:
            r = c.execute("SELECT * FROM panel_admins WHERE username=? COLLATE NOCASE", (username,)).fetchone()
        return dict(r) if r else None
    finally:
        c.close()


def load_admin():
    """Oturumdaki yetkiliyi her istekte DB'den okur: rol / devre disi birakma aninda gecerli olur."""
    if not session.get("authed") or not session.get("admin_id"):
        return None
    cached = flask_g.get("adm_cache", 0)
    if cached != 0:
        return cached
    adm = get_panel_admin(aid=session["admin_id"])
    if adm and not adm["active"]:
        adm = None
    flask_g.adm_cache = adm
    return adm


def require_auth(f):
    @wraps(f)
    def wrapper(*a, **kw):
        if not session.get("authed"):
            return redirect(url_for("login"))
        if now_ts() - session.get("authed_at", 0) > SESSION_TIMEOUT:
            session.clear()
            flash("Oturum süresi doldu, tekrar giriş yapın.", "warn")
            return redirect(url_for("login"))
        if not load_admin():
            session.clear()
            flash("Hesabınız devre dışı bırakılmış veya bulunamıyor.", "err")
            return redirect(url_for("login"))
        session["authed_at"] = now_ts()   # etkinlik oldukca oturum uzar
        return f(*a, **kw)
    return wrapper


def require_super(f):
    """Yalnizca Super Admin rolu."""
    @wraps(f)
    def inner(*a, **kw):
        adm = load_admin()
        if not adm or adm["role"] != ROLE_SUPER:
            return render_template("error.html", code=403,
                                   msg="Bu işlem için Süper Admin yetkisi gerekir."), 403
        return f(*a, **kw)
    return require_auth(inner)


@app.context_processor
def _inject_admin():
    adm = load_admin()
    return {"me": adm, "is_super": bool(adm and adm["role"] == ROLE_SUPER), "role_label": ROLE_LABELS}


def finalize_login(adm: dict, ip: str):
    session.clear()
    session["authed"] = True
    session["authed_at"] = now_ts()
    session["admin_id"] = adm["id"]
    session["admin_user"] = adm["username"]
    csrf_token()
    c = get_db(AUTH_DB)
    try:
        c.execute("UPDATE panel_admins SET last_login=? WHERE id=?", (now_ts(), adm["id"]))
    finally:
        c.close()
    failures.pop(ip, None)
    admin_log("login", "admin", adm["username"], f"başarılı giriş ({ip}) rol={adm['role']}")


def reauth_ok(adm: dict, password: str) -> bool:
    """Hassas islemlerden once yetkilinin kendi panel sifresini yeniden dogrular."""
    ip = client_ip()
    if is_locked(ip):
        return False
    if verify_password(password or "", adm["password_hash"]):
        return True
    record_failure(ip)
    admin_log("reauth_failed", "admin", adm["username"], f"hassas islem icin yanlis sifre ({ip})")
    return False


def check_new_panel_password(pw: str, username: str):
    if len(pw) < MIN_PANEL_PW:
        return f"Şifre en az {MIN_PANEL_PW} karakter olmalı."
    if len(pw) > 128:
        return "Şifre en fazla 128 karakter olabilir."
    if pw.lower() == (username or "").lower():
        return "Şifre kullanıcı adıyla aynı olamaz."
    return None


# ---- Sablon filtreleri ----
def fmt_dt(ts):
    if not ts:
        return "-"
    return datetime.fromtimestamp(int(ts), tz=_TZ).strftime("%d.%m.%Y %H:%M:%S")


def fmt_num(n):
    try:
        return f"{int(n):,}".replace(",", ".")
    except Exception:
        return str(n)


def fmt_dur(sec):
    sec = max(int(sec), 0)
    h, r = divmod(sec, 3600)
    m, s = divmod(r, 60)
    return f"{h}sa {m:02d}dk {s:02d}sn" if h else f"{m}dk {s:02d}sn"


app.jinja_env.filters["dt"] = fmt_dt
app.jinja_env.filters["num"] = fmt_num
app.jinja_env.filters["dur"] = fmt_dur
app.jinja_env.globals.update(
    company_name=lambda f: COMPANY_NAMES.get(int(f or 0), "Tümü" if int(f or 0) == 0 else f"Şirket {f}"),
    company_color=lambda f: COMPANY_COLORS.get(int(f or 0), "#94a3b8"),
    csrf=csrf_token,
    now=now_ts,
)


from markupsafe import Markup, escape
from urllib.parse import urlencode, quote


def page_url(p):
    args = request.args.to_dict()
    args["page"] = p
    return request.path + "?" + urlencode(args)


def pager(page, pages):
    if pages <= 1:
        return ""
    out = ['<div class="pager">']
    if page > 1:
        out.append('<a class="btn sec sm" href="%s">‹ Önceki</a>' % escape(page_url(page - 1)))
    out.append('<span class="mut">Sayfa %d / %d</span>' % (page, pages))
    if page < pages:
        out.append('<a class="btn sec sm" href="%s">Sonraki ›</a>' % escape(page_url(page + 1)))
    out.append("</div>")
    return Markup("".join(out))


app.jinja_env.globals["pager"] = pager

# ---------------------------------------------------------------------------
# ORTAK SORGULAR
# ---------------------------------------------------------------------------
def online_ids(gconn=None):
    close = gconn is None
    gconn = gconn or get_db(GAME_DB)
    try:
        rows = gconn.execute("SELECT account_id FROM session_locks WHERE expires_at > ?", (now_ts(),)).fetchall()
        return {r["account_id"] for r in rows}
    finally:
        if close:
            gconn.close()


def active_events(gconn=None, only_active=True):
    close = gconn is None
    gconn = gconn or get_db(GAME_DB)
    try:
        t = now_ts()
        if only_active:
            rows = gconn.execute(
                "SELECT * FROM company_events WHERE ended_at IS NULL AND starts_at <= ? AND ends_at > ? "
                "ORDER BY ends_at", (t, t)).fetchall()
        else:
            rows = gconn.execute(
                "SELECT * FROM company_events WHERE ended_at IS NULL AND ends_at > ? ORDER BY starts_at", (t,)).fetchall()
        return [dict(r) for r in rows]
    finally:
        if close:
            gconn.close()


def ban_state(row, now=None):
    now = now or now_ts()
    banned = bool(row["is_banned"]) and (not row["ban_until"] or now < row["ban_until"])
    muted = bool(row["is_muted"]) and (not row["mute_until"] or now < row["mute_until"])
    return banned, muted


def page_args():
    try:
        page = max(int(request.args.get("page", "1")), 1)
    except ValueError:
        page = 1
    return page, (page - 1) * PAGE_SIZE


def int_form(name, default=0, lo=None, hi=None):
    try:
        v = int(str(request.form.get(name, default)).strip())
    except ValueError:
        v = default
    if lo is not None:
        v = max(v, lo)
    if hi is not None:
        v = min(v, hi)
    return v


def reason_required():
    r = request.form.get("reason", "").strip()
    if len(r) < 3:
        return None
    return r[:200]


# ---------------------------------------------------------------------------
# GIRIS / CIKIS
# ---------------------------------------------------------------------------
@app.route("/")
def root():
    return redirect(url_for("dashboard"))


@app.route("/admin/login", methods=["GET", "POST"])
def login():
    ip = client_ip()
    if request.method == "POST":
        if is_locked(ip):
            return render_template("login.html", error="Çok fazla hatalı deneme. 15 dakika sonra tekrar deneyin."), 429
        username = request.form.get("username", "").strip()[:40]
        password = request.form.get("password", "")[:256]
        time.sleep(0.6)   # kaba kuvvet denemelerini yavaslatir
        adm = get_panel_admin(username=username) if username else None
        pw_ok = verify_password(password, adm["password_hash"] if adm else DUMMY_HASH)
        if adm and adm["active"] and pw_ok:
            if adm["totp_enabled"] and adm["totp_secret"]:
                keep = session.get("csrf")
                session.clear()
                if keep:
                    session["csrf"] = keep
                session["pending_id"] = adm["id"]
                session["pending_at"] = now_ts()
                session["pending_fail"] = 0
                return redirect(url_for("login_2fa"))
            finalize_login(adm, ip)
            return redirect(url_for("dashboard"))
        record_failure(ip)
        admin_log("login_failed", "admin", username or "?", f"başarısız giriş denemesi ({ip})", actor="-")
        return render_template("login.html", error="Kullanıcı adı veya şifre hatalı."), 401
    if is_locked(ip):
        return render_template("login.html", error="Çok fazla hatalı deneme. 15 dakika sonra tekrar deneyin."), 429
    return render_template("login.html", error=None)


@app.route("/admin/login/2fa", methods=["GET", "POST"])
def login_2fa():
    ip = client_ip()
    pid = session.get("pending_id")
    if not pid or now_ts() - session.get("pending_at", 0) > PENDING_TIMEOUT:
        session.pop("pending_id", None)
        flash("Doğrulama süresi doldu, yeniden giriş yapın.", "warn")
        return redirect(url_for("login"))
    if is_locked(ip):
        return render_template("login_2fa.html", error="Çok fazla hatalı deneme. 15 dakika sonra tekrar deneyin."), 429
    if request.method == "POST":
        time.sleep(0.4)
        adm = get_panel_admin(aid=pid)
        step = None
        if adm and adm["active"] and adm["totp_enabled"] and adm["totp_secret"]:
            step = totp_verify(adm["totp_secret"], request.form.get("code", ""), adm["totp_last_step"])
        if step:
            # Ayni kod ikinci kez kullanilamasin: adimi atomik olarak ilerlet
            c = get_db(AUTH_DB)
            try:
                cur = c.execute("UPDATE panel_admins SET totp_last_step=? WHERE id=? AND totp_last_step<?",
                                (step, adm["id"], step))
                taken = cur.rowcount > 0
            finally:
                c.close()
            if taken:
                finalize_login(adm, ip)
                return redirect(url_for("dashboard"))
        record_failure(ip)
        session["pending_fail"] = session.get("pending_fail", 0) + 1
        admin_log("login_2fa_failed", "admin", adm["username"] if adm else "?", f"hatalı 2FA kodu ({ip})", actor="-")
        if session["pending_fail"] >= 5:
            session.pop("pending_id", None)
            flash("Çok fazla hatalı kod. Yeniden giriş yapın.", "err")
            return redirect(url_for("login"))
        return render_template("login_2fa.html", error="Doğrulama kodu hatalı, süresi geçmiş ya da az önce kullanılmış (yeni kodu bekleyin)."), 401
    return render_template("login_2fa.html", error=None)


@app.route("/admin/logout", methods=["POST"])
@require_auth
def logout():
    admin_log("logout", "admin", actor(), "çıkış yapıldı")
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------------------
# HESABIM (sifre + 2FA)
# ---------------------------------------------------------------------------
@app.route("/admin/account")
@require_auth
def account():
    adm = load_admin()
    setup = session.get("totp_setup")
    uri = grouped = None
    if setup and not adm["totp_enabled"]:
        uri = "otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30" % (
            quote(TOTP_ISSUER), quote(adm["username"]), setup, quote(TOTP_ISSUER))
        grouped = " ".join(setup[i:i + 4] for i in range(0, len(setup), 4))
    else:
        setup = None
    return render_template("account.html", setup=setup, uri=uri, grouped=grouped, min_pw=MIN_PANEL_PW,
                           active="account")


@app.route("/admin/account/password", methods=["POST"])
@require_auth
def account_password():
    adm = load_admin()
    new = request.form.get("new", "")
    if new != request.form.get("again", ""):
        flash("Yeni şifre ve tekrarı aynı değil.", "err")
    elif not reauth_ok(adm, request.form.get("current", "")):
        flash("Mevcut şifre yanlış.", "err")
    elif new == request.form.get("current", ""):
        flash("Yeni şifre mevcut şifreyle aynı olamaz.", "err")
    else:
        err = check_new_panel_password(new, adm["username"])
        if err:
            flash(err, "err")
        else:
            c = get_db(AUTH_DB)
            try:
                c.execute("UPDATE panel_admins SET password_hash=?, pw_changed_at=? WHERE id=?",
                          (hash_password(new), now_ts(), adm["id"]))
            finally:
                c.close()
            admin_log("panel_password_change", "staff", adm["username"], "kendi panel şifresini değiştirdi")
            flash("Şifreniz güncellendi.", "ok")
    return redirect(url_for("account"))


@app.route("/admin/account/2fa/start", methods=["POST"])
@require_auth
def account_2fa_start():
    if load_admin()["totp_enabled"]:
        return redirect(url_for("account"))
    session["totp_setup"] = totp_new_secret()
    return redirect(url_for("account"))


@app.route("/admin/account/2fa/cancel", methods=["POST"])
@require_auth
def account_2fa_cancel():
    session.pop("totp_setup", None)
    return redirect(url_for("account"))


@app.route("/admin/account/2fa/enable", methods=["POST"])
@require_auth
def account_2fa_enable():
    adm = load_admin()
    secret = session.get("totp_setup")
    if not secret or adm["totp_enabled"]:
        return redirect(url_for("account"))
    step = totp_verify(secret, request.form.get("code", ""), 0)
    if not step:
        flash("Kod hatalı. Uygulamadaki güncel 6 haneli kodu girin (telefon saatinin doğru olduğundan emin olun).", "err")
        return redirect(url_for("account"))
    c = get_db(AUTH_DB)
    try:
        c.execute("UPDATE panel_admins SET totp_secret=?, totp_enabled=1, totp_last_step=? WHERE id=?",
                  (secret, step, adm["id"]))
    finally:
        c.close()
    session.pop("totp_setup", None)
    admin_log("2fa_enable", "staff", adm["username"], "2FA etkinleştirildi")
    flash("2FA etkinleştirildi. Bundan sonraki girişlerde kod istenecek.", "ok")
    return redirect(url_for("account"))


@app.route("/admin/account/2fa/disable", methods=["POST"])
@require_auth
def account_2fa_disable():
    adm = load_admin()
    if not adm["totp_enabled"]:
        return redirect(url_for("account"))
    if not reauth_ok(adm, request.form.get("current", "")):
        flash("Şifre yanlış.", "err")
        return redirect(url_for("account"))
    step = totp_verify(adm["totp_secret"], request.form.get("code", ""), adm["totp_last_step"])
    if not step:
        flash("2FA kodu hatalı ya da az önce kullanıldı (aynı kod iki kez geçmez; uygulamada yeni kod çıkana kadar ~30 sn bekleyin).", "err")
        return redirect(url_for("account"))
    c = get_db(AUTH_DB)
    try:
        c.execute("UPDATE panel_admins SET totp_enabled=0, totp_secret=NULL, totp_last_step=0 WHERE id=?", (adm["id"],))
    finally:
        c.close()
    admin_log("2fa_disable", "staff", adm["username"], "2FA kapatıldı")
    flash("2FA kapatıldı.", "warn")
    return redirect(url_for("account"))


# ---------------------------------------------------------------------------
# YETKILILER (panel hesaplari / roller) - yalnizca Super Admin
# ---------------------------------------------------------------------------
def _active_super_count(c, exclude_id=None) -> int:
    q, args = "SELECT COUNT(*) FROM panel_admins WHERE role=? AND active=1", [ROLE_SUPER]
    if exclude_id is not None:
        q += " AND id<>?"
        args.append(exclude_id)
    return c.execute(q, args).fetchone()[0]


@app.route("/admin/staff")
@require_super
def staff():
    c = get_db(AUTH_DB)
    try:
        rows = [dict(r) for r in c.execute(
            "SELECT id, username, role, totp_enabled, active, created_at, created_by, last_login "
            "FROM panel_admins ORDER BY id").fetchall()]
    finally:
        c.close()
    return render_template("staff.html", rows=rows, pm=police_mismatch(), min_pw=MIN_PANEL_PW, active="staff")


@app.route("/admin/staff/add", methods=["POST"])
@require_super
def staff_add():
    me = load_admin()
    username = request.form.get("username", "").strip()
    role = request.form.get("role", "")
    pw = request.form.get("password", "")
    err = None
    if not re.fullmatch(r"[A-Za-z0-9_.-]{3,24}", username):
        err = "Kullanıcı adı 3-24 karakter olmalı (harf, rakam, _ . -)."
    elif role not in ROLE_LABELS:
        err = "Geçersiz rol."
    else:
        err = check_new_panel_password(pw, username)
    if not err and not reauth_ok(me, request.form.get("admin_password", "")):
        err = "Sizin panel şifreniz yanlış."
    if err:
        flash(err, "err")
        return redirect(url_for("staff"))
    c = get_db(AUTH_DB)
    try:
        if c.execute("SELECT 1 FROM panel_admins WHERE username=? COLLATE NOCASE", (username,)).fetchone():
            flash("Bu kullanıcı adı zaten var.", "err")
            return redirect(url_for("staff"))
        c.execute("INSERT INTO panel_admins (username, password_hash, role, created_at, created_by) VALUES (?,?,?,?,?)",
                  (username, hash_password(pw), role, now_ts(), me["username"]))
    finally:
        c.close()
    admin_log("staff_add", "staff", username, f"rol={role}")
    flash(f"{username} ({ROLE_LABELS[role]}) eklendi. İlk girişte şifresini ve 2FA'yı Hesabım sayfasından ayarlamasını söyleyin.", "ok")
    return redirect(url_for("staff"))


@app.route("/admin/staff/<int:sid>/role", methods=["POST"])
@require_super
def staff_role(sid):
    me = load_admin()
    role = request.form.get("role", "")
    if role not in ROLE_LABELS:
        abort(400)
    if sid == me["id"]:
        flash("Kendi rolünüzü değiştiremezsiniz.", "err")
        return redirect(url_for("staff"))
    c = get_db(AUTH_DB)
    try:
        t = c.execute("SELECT username, role, active FROM panel_admins WHERE id=?", (sid,)).fetchone()
        if not t:
            abort(404)
        if t["role"] == ROLE_SUPER and role != ROLE_SUPER and t["active"] and _active_super_count(c, sid) < 1:
            flash("Son Süper Admin'in rolü düşürülemez.", "err")
            return redirect(url_for("staff"))
        c.execute("UPDATE panel_admins SET role=? WHERE id=?", (role, sid))
    finally:
        c.close()
    admin_log("staff_role", "staff", t["username"], f"{t['role']} → {role}")
    flash(f"{t['username']} artık {ROLE_LABELS[role]}.", "ok")
    return redirect(url_for("staff"))


@app.route("/admin/staff/<int:sid>/active", methods=["POST"])
@require_super
def staff_active(sid):
    me = load_admin()
    if sid == me["id"]:
        flash("Kendi hesabınızı devre dışı bırakamazsınız.", "err")
        return redirect(url_for("staff"))
    c = get_db(AUTH_DB)
    try:
        t = c.execute("SELECT username, role, active FROM panel_admins WHERE id=?", (sid,)).fetchone()
        if not t:
            abort(404)
        new = 0 if t["active"] else 1
        if not new and t["role"] == ROLE_SUPER and _active_super_count(c, sid) < 1:
            flash("Son Süper Admin devre dışı bırakılamaz.", "err")
            return redirect(url_for("staff"))
        c.execute("UPDATE panel_admins SET active=? WHERE id=?", (new, sid))
    finally:
        c.close()
    admin_log("staff_active", "staff", t["username"], "etkinleştirildi" if new else "devre dışı bırakıldı")
    flash(f"{t['username']} {'etkinleştirildi' if new else 'devre dışı bırakıldı (açık oturumları düşer)'}.", "ok")
    return redirect(url_for("staff"))


@app.route("/admin/staff/<int:sid>/reset2fa", methods=["POST"])
@require_super
def staff_reset2fa(sid):
    me = load_admin()
    if sid == me["id"]:
        flash("Kendi 2FA'nızı Hesabım sayfasından kapatın.", "err")
        return redirect(url_for("staff"))
    c = get_db(AUTH_DB)
    try:
        t = c.execute("SELECT username FROM panel_admins WHERE id=?", (sid,)).fetchone()
        if not t:
            abort(404)
        c.execute("UPDATE panel_admins SET totp_enabled=0, totp_secret=NULL, totp_last_step=0 WHERE id=?", (sid,))
    finally:
        c.close()
    admin_log("2fa_reset", "staff", t["username"], "2FA sıfırlandı")
    flash(f"{t['username']} için 2FA sıfırlandı; kendisi yeniden kurabilir.", "ok")
    return redirect(url_for("staff"))


@app.route("/admin/staff/<int:sid>/password", methods=["POST"])
@require_super
def staff_password(sid):
    me = load_admin()
    pw = request.form.get("password", "")
    c = get_db(AUTH_DB)
    try:
        t = c.execute("SELECT username FROM panel_admins WHERE id=?", (sid,)).fetchone()
        if not t:
            abort(404)
        err = check_new_panel_password(pw, t["username"])
        if not err and not reauth_ok(me, request.form.get("admin_password", "")):
            err = "Sizin panel şifreniz yanlış."
        if err:
            flash(err, "err")
            return redirect(url_for("staff"))
        c.execute("UPDATE panel_admins SET password_hash=?, pw_changed_at=? WHERE id=?",
                  (hash_password(pw), now_ts(), sid))
    finally:
        c.close()
    admin_log("staff_password", "staff", t["username"], "şifre Süper Admin tarafından belirlendi")
    flash(f"{t['username']} için yeni şifre kaydedildi.", "ok")
    return redirect(url_for("staff"))


@app.route("/admin/staff/police-sync", methods=["POST"])
@require_super
def police_sync():
    res = sync_police()
    admin_log("police_sync", "staff", "-", f"eklenen={res['added']} kaldırılan={res['removed']} gemisi_sıfırlanan={res['ship_reset']}")
    msg = (f"Polis gemisi senkronize edildi: {res['added']} adminin hangarına eklendi, "
           f"{res['removed']} hesaptan kaldırıldı, {res['ship_reset']} oyuncunun aktif gemisi Phoenix yapıldı.")
    if res["online_pending"]:
        msg += (f" {res['online_pending']} çevrimiçi oyuncunun aktif gemisi şu an police görünüyor; "
                "oyundan çıkıp girince Phoenix'e döner (sunucu çevrimiçi oyuncunun gemisini kendisi yönetir).")
    flash(msg, "ok")
    return redirect(url_for("staff"))


# ---------------------------------------------------------------------------
# GENEL BAKIS
# ---------------------------------------------------------------------------
@app.route("/admin/")
@require_auth
def dashboard():
    a = get_db(AUTH_DB)
    g = get_db(GAME_DB)
    try:
        total = a.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        by_faction = {r["faction"]: r["c"] for r in a.execute(
            "SELECT faction, COUNT(*) c FROM accounts GROUP BY faction").fetchall()}
        t = now_ts()
        banned = a.execute(
            "SELECT COUNT(*) FROM accounts WHERE is_banned=1 AND (ban_until IS NULL OR ban_until=0 OR ban_until>?)", (t,)).fetchone()[0]
        new24 = a.execute("SELECT COUNT(*) FROM accounts WHERE created_at > ?", (t - 86400,)).fetchone()[0]
        online = online_ids(g)
        online_by_faction = {1: 0, 2: 0, 3: 0}
        if online:
            ph = ",".join("?" * len(online))
            for r in g.execute(f"SELECT faction, COUNT(*) c FROM accounts WHERE id IN ({ph}) GROUP BY faction", tuple(online)).fetchall():
                online_by_faction[r["faction"]] = r["c"]
        events = active_events(g, only_active=False)
        logs = [dict(r) for r in a.execute("SELECT * FROM admin_log ORDER BY id DESC LIMIT 8").fetchall()]
    finally:
        a.close()
        g.close()
    return render_template("dashboard.html", total=total, by_faction=by_faction, banned=banned, new24=new24,
                           online_n=len(online), online_by_faction=online_by_faction, events=events, logs=logs,
                           active="dashboard")


# ---------------------------------------------------------------------------
# OYUNCULAR
# ---------------------------------------------------------------------------
@app.route("/admin/players")
@require_auth
def players():
    q = request.args.get("q", "").strip()[:60]
    fac = request.args.get("faction", "")
    status = request.args.get("status", "")
    page, off = page_args()
    where, args = [], []
    if q:
        if q.isdigit():
            where.append("(id = ? OR username LIKE ? OR callsign LIKE ?)")
            args += [int(q), f"%{q}%", f"%{q}%"]
        else:
            where.append("(username LIKE ? OR callsign LIKE ?)")
            args += [f"%{q}%", f"%{q}%"]
    if fac in ("1", "2", "3"):
        where.append("faction = ?")
        args.append(int(fac))
    t = now_ts()
    if status == "banned":
        where.append("is_banned=1 AND (ban_until IS NULL OR ban_until=0 OR ban_until>?)")
        args.append(t)
    elif status == "muted":
        where.append("is_muted=1 AND (mute_until IS NULL OR mute_until=0 OR mute_until>?)")
        args.append(t)
    elif status == "admin":
        where.append("is_admin=1")
    w = (" WHERE " + " AND ".join(where)) if where else ""
    a = get_db(AUTH_DB)
    g = get_db(GAME_DB)
    try:
        total = a.execute(f"SELECT COUNT(*) FROM accounts{w}", args).fetchone()[0]
        rows = [dict(r) for r in a.execute(
            f"SELECT id, username, callsign, faction, created_at, last_login, is_banned, ban_until, "
            f"is_muted, mute_until, is_admin FROM accounts{w} ORDER BY id DESC LIMIT ? OFFSET ?",
            args + [PAGE_SIZE, off]).fetchall()]
        ids = [r["id"] for r in rows]
        pdata, online = {}, online_ids(g)
        if ids:
            ph = ",".join("?" * len(ids))
            for r in g.execute(f"SELECT account_id, cr, uri, ship, map_name FROM player_data WHERE account_id IN ({ph})", ids).fetchall():
                pdata[r["account_id"]] = dict(r)
    finally:
        a.close()
        g.close()
    for r in rows:
        r["banned"], r["muted"] = ban_state(r, t)
        r["pd"] = pdata.get(r["id"])
        r["online"] = r["id"] in online
    pages = max((total + PAGE_SIZE - 1) // PAGE_SIZE, 1)
    return render_template("players.html", rows=rows, q=q, fac=fac, status=status, page=page, pages=pages,
                           total=total, active="players")


@app.route("/admin/players/<int:aid>")
@require_auth
def player(aid):
    a = get_db(AUTH_DB)
    g = get_db(GAME_DB)
    try:
        acc = a.execute("SELECT * FROM accounts WHERE id=?", (aid,)).fetchone()
        if not acc:
            abort(404)
        acc = dict(acc)
        gacc = g.execute("SELECT is_admin FROM accounts WHERE id=?", (aid,)).fetchone()
        acc["is_admin"] = int(gacc["is_admin"]) if gacc and gacc["is_admin"] is not None else int(acc.get("is_admin") or 0)
        pd = g.execute("SELECT * FROM player_data WHERE account_id=?", (aid,)).fetchone()
        pd = dict(pd) if pd else None
        ships = [r["ship_id"] for r in g.execute("SELECT ship_id FROM player_ships WHERE account_id=? ORDER BY acquired_at", (aid,)).fetchall()]
        ammo = [dict(r) for r in g.execute("SELECT ammo_id, quantity FROM ammo WHERE account_id=? AND quantity>0", (aid,)).fetchall()]
        drones = [dict(r) for r in g.execute("SELECT drone_id, quantity, equipped FROM player_drones WHERE account_id=?", (aid,)).fetchall()]
        items = [dict(r) for r in g.execute("SELECT item_id, quantity FROM inventory WHERE account_id=? AND quantity>0", (aid,)).fetchall()]
        txs = [dict(r) for r in g.execute(
            "SELECT type, amount_cr, amount_uri, item_id, created_at FROM transactions WHERE account_id=? "
            "ORDER BY id DESC LIMIT 15", (aid,)).fetchall()]
        is_online = aid in online_ids(g)
        logs = [dict(r) for r in a.execute(
            "SELECT * FROM admin_log WHERE target_type='account' AND target_id=? ORDER BY id DESC LIMIT 15", (str(aid),)).fetchall()]
    finally:
        a.close()
        g.close()
    acc["banned"], acc["muted"] = ban_state(acc)
    return render_template("player.html", acc=acc, pd=pd, ships=ships, ammo=ammo, drones=drones, items=items,
                           txs=txs, online=is_online, logs=logs,
                           active="players")


def _both_dbs_update(sql_auth, sql_game, args):
    for path, sql in ((AUTH_DB, sql_auth), (GAME_DB, sql_game)):
        c = get_db(path)
        try:
            c.execute(sql, args)
        finally:
            c.close()


@app.route("/admin/players/<int:aid>/ban", methods=["POST"])
@require_auth
def ban(aid):
    reason = reason_required()
    if not reason:
        flash("Ban için en az 3 karakterlik bir sebep yazmalısınız.", "err")
        return redirect(url_for("player", aid=aid))
    dur = int_form("duration", 86400)
    until = 0 if dur == -1 else now_ts() + max(dur, 60)   # is_banned=1 & ban_until=0 => süresiz
    _both_dbs_update("UPDATE accounts SET is_banned=1, ban_until=?, ban_reason=? WHERE id=?",
                     "UPDATE accounts SET is_banned=1, ban_until=?, ban_reason=? WHERE id=?",
                     (until, reason, aid))
    admin_log("ban", "account", aid, f"{'süresiz' if until == 0 else 'bitiş=' + fmt_dt(until)} | sebep: {reason}")
    flash("Oyuncu yasaklandı. Çevrimiçiyse sunucu birkaç saniye içinde atar.", "ok")
    return redirect(url_for("player", aid=aid))


@app.route("/admin/players/<int:aid>/unban", methods=["POST"])
@require_auth
def unban(aid):
    _both_dbs_update("UPDATE accounts SET is_banned=0, ban_until=0, ban_reason=NULL WHERE id=?",
                     "UPDATE accounts SET is_banned=0, ban_until=0, ban_reason=NULL WHERE id=?", (aid,))
    admin_log("unban", "account", aid, "yasak kaldırıldı")
    flash("Yasak kaldırıldı.", "ok")
    return redirect(url_for("player", aid=aid))


@app.route("/admin/players/<int:aid>/mute", methods=["POST"])
@require_auth
def mute(aid):
    dur = int_form("duration", 86400)
    until = 0 if dur == -1 else now_ts() + max(dur, 60)
    _both_dbs_update("UPDATE accounts SET is_muted=1, mute_until=? WHERE id=?",
                     "UPDATE accounts SET is_muted=1, mute_until=? WHERE id=?", (until, aid))
    admin_log("mute", "account", aid, "süresiz" if until == 0 else f"bitiş={fmt_dt(until)}")
    flash("Oyuncu susturuldu.", "ok")
    return redirect(url_for("player", aid=aid))


@app.route("/admin/players/<int:aid>/unmute", methods=["POST"])
@require_auth
def unmute(aid):
    _both_dbs_update("UPDATE accounts SET is_muted=0, mute_until=0 WHERE id=?",
                     "UPDATE accounts SET is_muted=0, mute_until=0 WHERE id=?", (aid,))
    admin_log("unmute", "account", aid, "susturma kaldırıldı")
    flash("Susturma kaldırıldı.", "ok")
    return redirect(url_for("player", aid=aid))


@app.route("/admin/players/<int:aid>/resource", methods=["POST"])
@require_super
def resource(aid):
    kind = request.form.get("kind", "")
    reason = reason_required()
    amount = int_form("amount", 0)
    if kind not in ("cr", "uri"):
        abort(400)
    if not reason:
        flash("Kaynak değişikliği için en az 3 karakterlik sebep zorunludur.", "err")
        return redirect(url_for("player", aid=aid))
    if amount == 0:
        flash("Miktar 0 olamaz.", "err")
        return redirect(url_for("player", aid=aid))
    g = get_db(GAME_DB)
    try:
        g.execute("BEGIN IMMEDIATE")
        row = g.execute(f"SELECT {kind} FROM player_data WHERE account_id=?", (aid,)).fetchone()
        if not row:
            g.execute("ROLLBACK")
            flash("Bu oyuncunun oyun verisi yok (henüz hiç giriş yapmamış).", "err")
            return redirect(url_for("player", aid=aid))
        new_val = max(int(row[0]) + amount, 0)
        applied = new_val - int(row[0])
        g.execute(f"UPDATE player_data SET {kind}=?, updated_at=? WHERE account_id=?", (new_val, now_ts(), aid))
        col = "amount_cr" if kind == "cr" else "amount_uri"
        g.execute(f"INSERT INTO transactions (account_id, tx_id, type, {col}, status, created_at) "
                  f"VALUES (?, ?, ?, ?, 'committed', ?)",
                  (aid, secrets.token_hex(16), f"admin_{kind}", applied, now_ts()))
        g.execute("COMMIT")
    except Exception as e:
        try:
            g.execute("ROLLBACK")
        except Exception:
            pass
        log.error("resource hata: %s", e)
        flash("İşlem başarısız oldu.", "err")
        return redirect(url_for("player", aid=aid))
    finally:
        g.close()
    admin_log(kind, "account", aid, f"{applied:+d} {kind.upper()} | sebep: {reason}")
    flash(f"{'Kredi' if kind == 'cr' else 'Uridium'} güncellendi: {applied:+,}".replace(",", "."), "ok")
    return redirect(url_for("player", aid=aid))


# ---------------------------------------------------------------------------
# ADMIN RUTBESI + POLICE GEMISI
# Oyun sunucusu da online oyuncular icin 30 sn'de bir ayni isi yapar; panel ise
# cevrimdisi oyuncular dahil DB'yi dogrudan duzeltir (gemi hangardan kaybolur).
# ---------------------------------------------------------------------------
POLICE_SHIP = "police"


def set_game_admin(aid: int, new_val: int) -> dict:
    """Oyun adminligini iki DB'de gunceller; police gemisini hangara ekler / hangardan kaldirir."""
    online = aid in online_ids()
    res = {"ok": True, "online": online, "police_added": False, "police_removed": False, "ship_reset": False}
    g = get_db(GAME_DB)
    try:
        g.execute("BEGIN IMMEDIATE")
        if not g.execute("SELECT 1 FROM accounts WHERE id=?", (aid,)).fetchone():
            g.execute("ROLLBACK")
            return {"ok": False, "error": "no_game_account"}
        g.execute("UPDATE accounts SET is_admin=? WHERE id=?", (new_val, aid))
        if new_val:
            cur = g.execute("INSERT OR IGNORE INTO player_ships (account_id, ship_id, acquired_at) VALUES (?,?,?)",
                            (aid, POLICE_SHIP, now_ts()))
            res["police_added"] = cur.rowcount > 0
        else:
            cur = g.execute("DELETE FROM player_ships WHERE account_id=? AND ship_id=?", (aid, POLICE_SHIP))
            res["police_removed"] = cur.rowcount > 0
            if not online:   # cevrimiciyse aktif gemiyi sunucu kendi bellegindeki durumla birlikte degistirir
                cur = g.execute("UPDATE player_data SET ship='phoenix', updated_at=? WHERE account_id=? AND ship=?",
                                (now_ts(), aid, POLICE_SHIP))
                res["ship_reset"] = cur.rowcount > 0
        g.execute("COMMIT")
    except Exception as e:
        try:
            g.execute("ROLLBACK")
        except Exception:
            pass
        log.error("set_game_admin hata: %s", e)
        return {"ok": False, "error": "db"}
    finally:
        g.close()
    a = get_db(AUTH_DB)
    try:
        a.execute("UPDATE accounts SET is_admin=? WHERE id=?", (new_val, aid))
    finally:
        a.close()
    return res


def police_mismatch() -> dict:
    """Admin olup polis gemisi olmayanlar / admin olmayip polis gemisi (veya aktif police) olanlar."""
    g = get_db(GAME_DB)
    try:
        missing = [dict(r) for r in g.execute(
            "SELECT a.id, a.callsign FROM accounts a WHERE a.is_admin=1 AND NOT EXISTS "
            "(SELECT 1 FROM player_ships s WHERE s.account_id=a.id AND s.ship_id=?)", (POLICE_SHIP,)).fetchall()]
        extra = [dict(r) for r in g.execute(
            "SELECT a.id, a.callsign FROM accounts a WHERE a.is_admin IS NOT 1 AND (EXISTS "
            "(SELECT 1 FROM player_ships s WHERE s.account_id=a.id AND s.ship_id=?) OR EXISTS "
            "(SELECT 1 FROM player_data p WHERE p.account_id=a.id AND p.ship=?))",
            (POLICE_SHIP, POLICE_SHIP)).fetchall()]
    finally:
        g.close()
    return {"missing": missing, "extra": extra}


def sync_police() -> dict:
    pm = police_mismatch()
    online = online_ids()
    out = {"added": 0, "removed": 0, "ship_reset": 0, "online_pending": 0}
    g = get_db(GAME_DB)
    try:
        g.execute("BEGIN IMMEDIATE")
        for r in pm["missing"]:
            cur = g.execute("INSERT OR IGNORE INTO player_ships (account_id, ship_id, acquired_at) VALUES (?,?,?)",
                            (r["id"], POLICE_SHIP, now_ts()))
            out["added"] += cur.rowcount
        for r in pm["extra"]:
            cur = g.execute("DELETE FROM player_ships WHERE account_id=? AND ship_id=?", (r["id"], POLICE_SHIP))
            out["removed"] += cur.rowcount
            if r["id"] not in online:
                cur = g.execute("UPDATE player_data SET ship='phoenix', updated_at=? WHERE account_id=? AND ship=?",
                                (now_ts(), r["id"], POLICE_SHIP))
                out["ship_reset"] += cur.rowcount
            elif g.execute("SELECT 1 FROM player_data WHERE account_id=? AND ship=?", (r["id"], POLICE_SHIP)).fetchone():
                out["online_pending"] += 1   # cevrimici: aktif gemi, oyuncu cikinca / giris yapinca Phoenix'e doner
        g.execute("COMMIT")
    except Exception as e:
        try:
            g.execute("ROLLBACK")
        except Exception:
            pass
        log.error("sync_police hata: %s", e)
    finally:
        g.close()
    return out


@app.route("/admin/players/<int:aid>/admin", methods=["POST"])
@require_super
def toggle_admin(aid):
    g = get_db(GAME_DB)
    try:
        row = g.execute("SELECT is_admin FROM accounts WHERE id=?", (aid,)).fetchone()
    finally:
        g.close()
    if not row:
        flash("Bu hesap oyuna henüz hiç girmemiş; admin rütbesi ilk girişten sonra verilebilir.", "err")
        return redirect(url_for("player", aid=aid))
    new_val = 0 if int(row["is_admin"] or 0) else 1
    res = set_game_admin(aid, new_val)
    if not res["ok"]:
        flash("İşlem başarısız oldu (veritabanı hatası).", "err")
        return redirect(url_for("player", aid=aid))
    detail = f"is_admin={new_val}"
    if new_val:
        detail += " | police gemisi hangara eklendi" if res["police_added"] else " | police zaten hangardaydı"
        msg = "Admin rütbesi verildi. Polis gemisi hangara eklendi."
        if res["online"]:
            msg += " Oyuncu çevrimiçi: gemi en geç ~30 sn içinde hangarında görünür."
    else:
        detail += " | police gemisi hangardan kaldırıldı" if res["police_removed"] else " | police hangarda yoktu"
        if res["ship_reset"]:
            detail += " | aktif gemi phoenix yapıldı"
        msg = "Admin rütbesi alındı. Polis gemisi hangardan kaldırıldı."
        if res["ship_reset"]:
            msg += " Aktif gemisi Phoenix'e çevrildi."
        if res["online"]:
            msg += " Oyuncu çevrimiçi: sunucu en geç ~30 sn içinde gemiyi kaldırıp Phoenix'e geçirir."
    admin_log("admin_toggle", "account", aid, detail)
    flash(msg, "ok")
    return redirect(url_for("player", aid=aid))


_PW_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"   # karisan harfler (0/O, 1/l/I) yok


def gen_temp_password(n: int = 12) -> str:
    return "".join(secrets.choice(_PW_ALPHABET) for _ in range(n))


@app.route("/admin/players/<int:aid>/password", methods=["POST"])
@require_super
def player_password(aid):
    """Oyuncu sifresini degistirir. Mevcut sifre gorulemez (Argon2id tek yonlu hash)."""
    me = load_admin()
    reason = reason_required()
    mode = request.form.get("mode", "generate")
    if not reason:
        flash("Şifre değişikliği için en az 3 karakterlik sebep zorunludur.", "err")
        return redirect(url_for("player", aid=aid))
    if mode == "custom":
        new_pw = request.form.get("new_password", "")
        if not MIN_PLAYER_PW <= len(new_pw) <= 128:
            flash(f"Yeni şifre {MIN_PLAYER_PW}-128 karakter olmalı.", "err")
            return redirect(url_for("player", aid=aid))
        shown = None
    else:
        new_pw = gen_temp_password()
        shown = new_pw
    if not reauth_ok(me, request.form.get("admin_password", "")):
        flash("Sizin panel şifreniz yanlış.", "err")
        return redirect(url_for("player", aid=aid))
    new_hash = hash_password(new_pw)
    a = get_db(AUTH_DB)
    try:
        cur = a.execute("UPDATE accounts SET password_hash=? WHERE id=?", (new_hash, aid))
        found = cur.rowcount > 0
        who = a.execute("SELECT username, callsign FROM accounts WHERE id=?", (aid,)).fetchone()
    finally:
        a.close()
    if not found:
        flash("Hesap bulunamadı.", "err")
        return redirect(url_for("player", aid=aid))
    try:   # oyun DB'sindeki kopya (giris auth DB'den yapilir; tutarlilik icin)
        g = get_db(GAME_DB)
        try:
            g.execute("UPDATE accounts SET password_hash=? WHERE id=?", (new_hash, aid))
        finally:
            g.close()
    except Exception as e:
        log.warning("oyun DB sifre kopyasi guncellenemedi: %s", e)
    admin_log("password_reset", "account", aid,
              f"sebep: {reason} | yöntem: {'geçici şifre üretildi' if shown else 'elle belirlendi'}")
    return render_template("pwreset.html", aid=aid, who=who, shown=shown, active="players")


# ---------------------------------------------------------------------------
# CEVRIMICI OYUNCULAR
# ---------------------------------------------------------------------------
@app.route("/admin/online")
@require_auth
def online():
    g = get_db(GAME_DB)
    try:
        rows = [dict(r) for r in g.execute(
            "SELECT a.id, a.username, a.callsign, a.faction, a.is_admin, p.ship, p.map_name, p.cr, p.uri, s.locked_at "
            "FROM session_locks s JOIN accounts a ON a.id = s.account_id "
            "LEFT JOIN player_data p ON p.account_id = a.id WHERE s.expires_at > ? "
            "ORDER BY p.map_name, a.callsign", (now_ts(),)).fetchall()]
    finally:
        g.close()
    maps = {}
    for r in rows:
        maps[r["map_name"] or "?"] = maps.get(r["map_name"] or "?", 0) + 1
    return render_template("online.html", rows=rows, maps=sorted(maps.items()), active="online")


# ---------------------------------------------------------------------------
# ETKINLIKLER (SIRKETE OZEL BONUS)
# ---------------------------------------------------------------------------
@app.route("/admin/events")
@require_super
def events():
    t = now_ts()
    g = get_db(GAME_DB)
    try:
        rows = [dict(r) for r in g.execute("SELECT * FROM company_events ORDER BY id DESC LIMIT 40").fetchall()]
    finally:
        g.close()
    for r in rows:
        if r["ended_at"]:
            r["status"] = "iptal"
        elif t < r["starts_at"]:
            r["status"] = "planlı"
        elif t < r["ends_at"]:
            r["status"] = "aktif"
        else:
            r["status"] = "bitti"
    return render_template("events.html", rows=rows, max_pct=MAX_EVENT_BONUS_PCT, max_min=MAX_EVENT_MINUTES,
                           companies=COMPANY_NAMES, active="events")


@app.route("/admin/events/start", methods=["POST"])
@require_super
def event_start():
    faction = int_form("faction", 0, 0, 3)
    pct = int_form("bonus_pct", 0)
    minutes = int_form("minutes", 0)
    delay = int_form("delay", 0, 0, MAX_EVENT_MINUTES)
    scope_npc = 1 if request.form.get("scope_npc") else 0
    scope_pvp = 1 if request.form.get("scope_pvp") else 0
    res_list = [r for r in ("cr", "uri", "xp", "hon") if request.form.get(f"res_{r}")]
    note = request.form.get("note", "").strip()[:120]
    err = None
    if not 1 <= pct <= MAX_EVENT_BONUS_PCT:
        err = f"Bonus yüzdesi 1 ile {MAX_EVENT_BONUS_PCT} arasında olmalı."
    elif not 1 <= minutes <= MAX_EVENT_MINUTES:
        err = f"Süre 1 ile {MAX_EVENT_MINUTES} dakika arasında olmalı."
    elif not (scope_npc or scope_pvp):
        err = "En az bir kapsam seçin (NPC öldürme ve/veya oyuncu öldürme)."
    elif not res_list:
        err = "En az bir ödül türü seçin."
    if err:
        flash(err, "err")
        return redirect(url_for("events"))
    start = now_ts() + delay * 60
    end = start + minutes * 60
    g = get_db(GAME_DB)
    try:
        g.execute("BEGIN IMMEDIATE")
        # Ayni sirkete (veya tum sirketlere) ayni anda iki etkinlik verilmez.
        clash = g.execute(
            "SELECT id FROM company_events WHERE ended_at IS NULL AND ends_at > ? AND starts_at < ? "
            "AND (faction = ? OR faction = 0 OR ? = 0) LIMIT 1", (start, end, faction, faction)).fetchone()
        if clash:
            g.execute("ROLLBACK")
            flash(f"Bu zaman aralığında aynı şirket için zaten bir etkinlik var (#{clash['id']}). Önce onu bitirin.", "err")
            return redirect(url_for("events"))
        cur = g.execute(
            "INSERT INTO company_events (faction, bonus_pct, scope_npc, scope_pvp, resources, starts_at, ends_at, "
            "created_by, created_at, note) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (faction, pct, scope_npc, scope_pvp, ",".join(res_list), start, end, actor(), now_ts(), note or None))
        eid = cur.lastrowid
        g.execute("COMMIT")
    finally:
        g.close()
    admin_log("event_start", "event", eid,
              f"şirket={COMPANY_NAMES.get(faction, 'Tümü')} | +%{pct} (x{1 + pct / 100:g}) | {minutes} dk | "
              f"npc={scope_npc} pvp={scope_pvp} | ödül={','.join(res_list)}")
    flash(f"Etkinlik #{eid} başlatıldı. Sunucu birkaç saniye içinde uygular.", "ok")
    return redirect(url_for("events"))


@app.route("/admin/events/<int:eid>/end", methods=["POST"])
@require_super
def event_end(eid):
    g = get_db(GAME_DB)
    try:
        g.execute("UPDATE company_events SET ended_at=? WHERE id=? AND ended_at IS NULL AND ends_at > ?",
                  (now_ts(), eid, now_ts()))
    finally:
        g.close()
    admin_log("event_end", "event", eid, "elle bitirildi")
    flash(f"Etkinlik #{eid} bitirildi.", "ok")
    return redirect(url_for("events"))


# ---------------------------------------------------------------------------
# HARITALAR (NPC SAYISI)
# ---------------------------------------------------------------------------
@app.route("/admin/maps")
@require_super
def maps():
    g = get_db(GAME_DB)
    try:
        ov = {r["map_id"]: dict(r) for r in g.execute("SELECT * FROM npc_overrides").fetchall()}
        online = {}
        for r in g.execute("SELECT p.map_name m, COUNT(*) c FROM session_locks s JOIN player_data p "
                           "ON p.account_id = s.account_id WHERE s.expires_at > ? GROUP BY p.map_name", (now_ts(),)).fetchall():
            online[r["m"]] = r["c"]
    finally:
        g.close()
    rows = [{"map": m, "override": ov.get(m), "players": online.get(m, 0)} for m in KNOWN_MAPS]
    return render_template("maps.html", rows=rows, active="maps")


@app.route("/admin/maps/set", methods=["POST"])
@require_super
def map_set():
    map_id = request.form.get("map_id", "").strip()
    n = int_form("npc_count", -1)
    if map_id not in KNOWN_MAPS or not 0 <= n <= 1000:
        flash("Geçersiz harita veya NPC sayısı (0-1000).", "err")
        return redirect(url_for("maps"))
    g = get_db(GAME_DB)
    try:
        g.execute("INSERT OR REPLACE INTO npc_overrides (map_id, npc_count, updated_at) VALUES (?,?,?)",
                  (map_id, n, now_ts()))
    finally:
        g.close()
    admin_log("npc_override", "map", map_id, f"npc_count={n}")
    flash(f"{map_id} için NPC üst sınırı {n} yapıldı.", "ok")
    return redirect(url_for("maps"))


@app.route("/admin/maps/clear", methods=["POST"])
@require_super
def map_clear():
    map_id = request.form.get("map_id", "").strip()
    g = get_db(GAME_DB)
    try:
        g.execute("DELETE FROM npc_overrides WHERE map_id=?", (map_id,))
    finally:
        g.close()
    admin_log("npc_override_clear", "map", map_id, "sınır kaldırıldı")
    flash(f"{map_id} NPC sınırı kaldırıldı.", "ok")
    return redirect(url_for("maps"))


# ---------------------------------------------------------------------------
# EKONOMI
# ---------------------------------------------------------------------------
@app.route("/admin/economy")
@require_super
def economy():
    g = get_db(GAME_DB)
    try:
        tot = dict(g.execute("SELECT COALESCE(SUM(cr),0) cr, COALESCE(SUM(uri),0) uri, COUNT(*) n FROM player_data").fetchone())
        per = [dict(r) for r in g.execute(
            "SELECT a.faction, COUNT(*) n, COALESCE(SUM(p.cr),0) cr, COALESCE(SUM(p.uri),0) uri "
            "FROM player_data p JOIN accounts a ON a.id = p.account_id GROUP BY a.faction ORDER BY a.faction").fetchall()]
        rich_uri = [dict(r) for r in g.execute(
            "SELECT a.id, a.callsign, a.faction, p.cr, p.uri FROM player_data p JOIN accounts a ON a.id = p.account_id "
            "WHERE a.is_admin IS NOT 1 ORDER BY p.uri DESC LIMIT 10").fetchall()]
        rich_cr = [dict(r) for r in g.execute(
            "SELECT a.id, a.callsign, a.faction, p.cr, p.uri FROM player_data p JOIN accounts a ON a.id = p.account_id "
            "WHERE a.is_admin IS NOT 1 ORDER BY p.cr DESC LIMIT 10").fetchall()]
        admin_tx = [dict(r) for r in g.execute(
            "SELECT t.type, t.amount_cr, t.amount_uri, t.created_at, a.callsign, a.id aid FROM transactions t "
            "LEFT JOIN accounts a ON a.id = t.account_id WHERE t.type LIKE 'admin_%' ORDER BY t.id DESC LIMIT 20").fetchall()]
        day = dict(g.execute(
            "SELECT COALESCE(SUM(amount_cr),0) cr, COALESCE(SUM(amount_uri),0) uri FROM transactions "
            "WHERE type LIKE 'admin_%' AND created_at > ?", (now_ts() - 86400,)).fetchone())
    finally:
        g.close()
    return render_template("economy.html", tot=tot, per=per, rich_uri=rich_uri, rich_cr=rich_cr, admin_tx=admin_tx,
                           day=day, active="economy")


# ---------------------------------------------------------------------------
# LOGLAR
# ---------------------------------------------------------------------------
@app.route("/admin/logs")
@require_auth
def logs():
    q = request.args.get("q", "").strip()[:80]
    action = request.args.get("action", "").strip()[:40]
    ttype = request.args.get("type", "").strip()[:20]
    d_from = request.args.get("from", "").strip()
    d_to = request.args.get("to", "").strip()
    page, off = page_args()
    where, args = [], []
    if q:
        where.append("(detail LIKE ? OR target_id LIKE ? OR action LIKE ?)")
        args += [f"%{q}%"] * 3
    if action:
        where.append("action = ?")
        args.append(action)
    if ttype:
        where.append("target_type = ?")
        args.append(ttype)

    def _ts(s, end=False):
        try:
            d = datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=_TZ)
            return int(d.timestamp()) + (86400 if end else 0)
        except ValueError:
            return None
    f, t = _ts(d_from), _ts(d_to, True)
    if f:
        where.append("created_at >= ?")
        args.append(f)
    if t:
        where.append("created_at < ?")
        args.append(t)
    w = (" WHERE " + " AND ".join(where)) if where else ""
    a = get_db(AUTH_DB)
    try:
        total = a.execute(f"SELECT COUNT(*) FROM admin_log{w}", args).fetchone()[0]
        rows = [dict(r) for r in a.execute(
            f"SELECT * FROM admin_log{w} ORDER BY id DESC LIMIT ? OFFSET ?", args + [PAGE_SIZE * 2, (page - 1) * PAGE_SIZE * 2]).fetchall()]
        actions = [r[0] for r in a.execute("SELECT DISTINCT action FROM admin_log ORDER BY action").fetchall()]
    finally:
        a.close()
    pages = max((total + PAGE_SIZE * 2 - 1) // (PAGE_SIZE * 2), 1)
    return render_template("logs.html", rows=rows, q=q, action=action, ttype=ttype, d_from=d_from, d_to=d_to,
                           actions=actions, page=page, pages=pages, total=total, active="logs")


# ---------------------------------------------------------------------------
# HATA SAYFALARI
# ---------------------------------------------------------------------------
@app.errorhandler(403)
def e403(_):
    return render_template("error.html", code=403, msg="Erişim reddedildi (oturum veya güvenlik anahtarı geçersiz). Sayfayı yenileyip tekrar deneyin."), 403


@app.errorhandler(404)
def e404(_):
    return render_template("error.html", code=404, msg="Sayfa veya kayıt bulunamadı."), 404


@app.errorhandler(400)
def e400(_):
    return render_template("error.html", code=400, msg="Geçersiz istek."), 400


@app.errorhandler(500)
def e500(e):
    log.exception("500: %s", e)
    return render_template("error.html", code=500, msg="Beklenmeyen bir hata oluştu. Detay sunucu loguna yazıldı."), 500



# ---------------------------------------------------------------------------
# ARAYUZ SABLONLARI (koyu tema, duyarli / mobil uyumlu)
# ---------------------------------------------------------------------------
_CSS = """
:root{--bg:#0b1220;--panel:#111a2e;--panel2:#16213a;--line:#233052;--txt:#e6ecf8;--mut:#8b9bbd;--acc:#38bdf8;
--acc2:#6366f1;--ok:#22c55e;--warn:#f59e0b;--err:#ef4444;--r:12px}
*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--txt);
font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
a{color:var(--acc);text-decoration:none}a:hover{text-decoration:underline}
.layout{display:flex;min-height:100vh}
.side{width:230px;background:var(--panel);border-right:1px solid var(--line);padding:18px 12px;position:sticky;top:0;
height:100vh;display:flex;flex-direction:column;flex-shrink:0}
.brand{font-weight:800;font-size:17px;letter-spacing:.5px;padding:4px 10px 18px}
.brand span{color:var(--acc)}
.nav a{display:flex;gap:10px;align-items:center;padding:10px 12px;border-radius:9px;color:var(--mut);margin-bottom:3px;font-weight:500}
.nav a:hover{background:var(--panel2);color:var(--txt);text-decoration:none}
.nav a.on{background:linear-gradient(90deg,rgba(56,189,248,.18),rgba(99,102,241,.12));color:var(--txt);
box-shadow:inset 3px 0 0 var(--acc)}
.side .foot{margin-top:auto;padding:10px}
.main{flex:1;min-width:0;padding:22px 26px 60px}
.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px;gap:10px;flex-wrap:wrap}
h1{font-size:22px;margin:0}h2{font-size:16px;margin:0 0 12px}
.sub{color:var(--mut);font-size:13px}
.grid{display:grid;gap:14px}.g4{grid-template-columns:repeat(auto-fit,minmax(190px,1fr))}
.g2{grid-template-columns:repeat(auto-fit,minmax(340px,1fr))}
.card{background:var(--panel);border:1px solid var(--line);border-radius:var(--r);padding:16px}
.stat .v{font-size:28px;font-weight:800;margin-top:2px}.stat .l{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.6px}
.stat .d{color:var(--mut);font-size:12px;margin-top:4px}
table{width:100%;border-collapse:collapse}th,td{padding:9px 10px;text-align:left;border-bottom:1px solid var(--line);vertical-align:middle}
th{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.5px;font-weight:600;white-space:nowrap}
tr:hover td{background:rgba(255,255,255,.02)}.tw{overflow-x:auto}
.badge{display:inline-block;padding:2px 9px;border-radius:99px;font-size:12px;font-weight:600;border:1px solid transparent;white-space:nowrap}
.b-ok{background:rgba(34,197,94,.14);color:#4ade80;border-color:rgba(34,197,94,.3)}
.b-err{background:rgba(239,68,68,.14);color:#f87171;border-color:rgba(239,68,68,.3)}
.b-warn{background:rgba(245,158,11,.14);color:#fbbf24;border-color:rgba(245,158,11,.3)}
.b-mut{background:rgba(139,155,189,.14);color:var(--mut);border-color:rgba(139,155,189,.25)}
.b-acc{background:rgba(56,189,248,.14);color:var(--acc);border-color:rgba(56,189,248,.3)}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px;background:var(--mut)}.dot.on{background:var(--ok);box-shadow:0 0 8px var(--ok)}
input,select,textarea{background:#0b1426;color:var(--txt);border:1px solid var(--line);border-radius:8px;padding:8px 10px;font:inherit;max-width:100%}
input:focus,select:focus{outline:2px solid rgba(56,189,248,.5);border-color:var(--acc)}
label{display:block;color:var(--mut);font-size:12px;margin-bottom:4px;font-weight:600}
.f{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end}.f>div{min-width:0}
button,.btn{background:var(--acc2);color:#fff;border:0;border-radius:8px;padding:8px 14px;font:inherit;font-weight:600;cursor:pointer;display:inline-block}
button:hover,.btn:hover{filter:brightness(1.12);text-decoration:none}
.btn.sec{background:var(--panel2);border:1px solid var(--line);color:var(--txt)}.btn.red{background:#dc2626}.btn.grn{background:#16a34a}
.btn.sm{padding:4px 10px;font-size:12px}
.flash{padding:11px 14px;border-radius:9px;margin-bottom:10px;border:1px solid;font-weight:500}
.flash.ok{background:rgba(34,197,94,.12);border-color:rgba(34,197,94,.35);color:#86efac}
.flash.err{background:rgba(239,68,68,.12);border-color:rgba(239,68,68,.35);color:#fca5a5}
.flash.warn{background:rgba(245,158,11,.12);border-color:rgba(245,158,11,.35);color:#fcd34d}
.kv{display:grid;grid-template-columns:140px 1fr;gap:6px 12px}.kv .k{color:var(--mut)}
.pager{display:flex;gap:6px;align-items:center;margin-top:14px;flex-wrap:wrap}.mut{color:var(--mut)}
.chip{display:inline-flex;align-items:center;gap:6px;padding:2px 10px;border-radius:99px;font-size:12px;font-weight:700;color:#fff}
.hint{color:var(--mut);font-size:12px;margin-top:4px}.pre{white-space:pre-wrap;word-break:break-word}
.big{font-size:15px;font-weight:700;color:var(--acc)}
.menu-btn{display:none}
@media(max-width:860px){.layout{display:block}.side{position:static;width:auto;height:auto;flex-direction:row;flex-wrap:wrap;
align-items:center;padding:10px}.brand{padding:4px 8px}.nav{display:flex;flex-wrap:wrap;gap:2px;width:100%}
.nav a{padding:7px 10px;margin:0}.side .foot{margin:0;padding:6px 8px}.main{padding:16px 12px 50px}
.kv{grid-template-columns:110px 1fr}}
"""

_JS = """
document.addEventListener('submit',function(e){var m=e.target.getAttribute('data-confirm');if(m&&!confirm(m)){e.preventDefault();}});
function tick(){document.querySelectorAll('[data-end]').forEach(function(el){var s=parseInt(el.getAttribute('data-end'))-Math.floor(Date.now()/1000);
if(s<=0){el.textContent='bitti';return;}var h=Math.floor(s/3600),m=Math.floor(s%3600/60),x=s%60;
el.textContent=(h?h+'sa ':'')+String(m).padStart(2,'0')+'dk '+String(x).padStart(2,'0')+'sn';});}
tick();setInterval(tick,1000);
"""

TEMPLATES = {}

TEMPLATES["base.html"] = """<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{% block title %}Yönetim{% endblock %} · NovaGate</title>
<style>""" + _CSS + """</style></head><body>

<div class="layout"><aside class="side"><div class="brand">NOVA<span>GATE</span> · Yönetim</div>
<nav class="nav">
<a href="{{ url_for('dashboard') }}" class="{{ 'on' if active=='dashboard' }}">▣ Genel Bakış</a>
<a href="{{ url_for('players') }}" class="{{ 'on' if active=='players' }}">👤 Oyuncular</a>
<a href="{{ url_for('online') }}" class="{{ 'on' if active=='online' }}">🟢 Çevrimiçi</a>
{% if is_super %}<a href="{{ url_for('events') }}" class="{{ 'on' if active=='events' }}">⚡ Etkinlikler</a>
<a href="{{ url_for('maps') }}" class="{{ 'on' if active=='maps' }}">🗺 Haritalar</a>
<a href="{{ url_for('economy') }}" class="{{ 'on' if active=='economy' }}">💰 Ekonomi</a>{% endif %}
<a href="{{ url_for('logs') }}" class="{{ 'on' if active=='logs' }}">📜 Loglar</a>
{% if is_super %}<a href="{{ url_for('staff') }}" class="{{ 'on' if active=='staff' }}">🛡 Yetkililer</a>{% endif %}
{% if me %}<a href="{{ url_for('account') }}" class="{{ 'on' if active=='account' }}">⚙ Hesabım</a>{% endif %}</nav>
<div class="foot">{% if me %}<div class="mut" style="font-size:12px;margin-bottom:8px">{{ me.username }}<br><span class="badge b-acc">{{ role_label[me.role] }}</span></div>{% endif %}<form method="post" action="{{ url_for('logout') }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<button class="btn sec sm" type="submit">Güvenli Çıkış</button></form></div></aside>
<main class="main">{% if me and not me.totp_enabled and active!='account' %}<div class="flash warn">Hesabınız 2 adımlı doğrulama (2FA) ile korunmuyor. <a href="{{ url_for('account') }}">Şimdi etkinleştir →</a></div>{% endif %}{% with msgs = get_flashed_messages(with_categories=true) %}{% for c,m in msgs %}<div class="flash {{ c }}">{{ m }}</div>{% endfor %}{% endwith %}
{% block body %}{% endblock %}</main></div><script>""" + _JS + """</script></body></html>"""

TEMPLATES["login.html"] = """<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NovaGate Yönetim Girişi</title><style>""" + _CSS + """
body{display:flex;align-items:center;justify-content:center;min-height:100vh;
background:radial-gradient(900px 500px at 70% -10%,rgba(99,102,241,.25),transparent),radial-gradient(700px 400px at 0% 110%,rgba(56,189,248,.18),transparent),var(--bg)}
.box{width:min(380px,92vw)}.box h1{text-align:center;margin-bottom:4px}.box input{width:100%;margin-bottom:12px}
</style></head><body><div class="card box"><h1>NOVA<span style="color:var(--acc)">GATE</span></h1>
<p class="sub" style="text-align:center;margin-top:0">Yönetici Kontrol Paneli</p>
{% if error %}<div class="flash err">{{ error }}</div>{% endif %}
<form method="post" autocomplete="off"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<label>Kullanıcı adı</label><input name="username" required autofocus>
<label>Şifre</label><input name="password" type="password" required>
<button type="submit" style="width:100%">Giriş yap</button></form></div></body></html>"""

TEMPLATES["error.html"] = """{% extends 'base.html' %}{% block body %}<div class="card" style="max-width:560px">
<h1>{{ code }}</h1><p>{{ msg }}</p><a class="btn" href="{{ url_for('dashboard') }}">Genel Bakış'a dön</a></div>{% endblock %}"""

TEMPLATES["dashboard.html"] = """{% extends 'base.html' %}{% block title %}Genel Bakış{% endblock %}{% block body %}
<div class="top"><div><h1>Genel Bakış</h1><div class="sub">Sunucu ve oyuncu özeti</div></div></div>
<div class="grid g4">
<div class="card stat"><div class="l">Çevrimiçi</div><div class="v">{{ online_n }}</div>
<div class="d">{% for f in (1,2,3) %}<span class="chip" style="background:{{ company_color(f) }}">{{ company_name(f) }} {{ online_by_faction[f] }}</span> {% endfor %}</div></div>
<div class="card stat"><div class="l">Toplam hesap</div><div class="v">{{ total|num }}</div><div class="d">Son 24 saatte +{{ new24 }}</div></div>
<div class="card stat"><div class="l">Aktif yasaklı</div><div class="v">{{ banned }}</div><div class="d"><a href="{{ url_for('players', status='banned') }}">Listele</a></div></div>
<div class="card stat"><div class="l">Şirket dağılımı</div><div class="v" style="font-size:16px;line-height:1.9">
{% for f in (1,2,3) %}<span class="chip" style="background:{{ company_color(f) }}">{{ company_name(f) }}: {{ by_faction.get(f,0) }}</span> {% endfor %}</div></div></div>
<div class="grid g2" style="margin-top:14px">
<div class="card"><h2>⚡ Aktif / planlı etkinlikler</h2>
{% if events %}<div class="tw"><table><tr><th>Şirket</th><th>Bonus</th><th>Durum</th></tr>
{% for e in events %}<tr><td><span class="chip" style="background:{{ company_color(e.faction) }}">{{ company_name(e.faction) }}</span></td>
<td><b>+%{{ e.bonus_pct }}</b> <span class="mut">(x{{ '%g' % (1 + e.bonus_pct/100) }})</span></td>
<td>{% if now() < e.starts_at %}<span class="badge b-warn">başlıyor: {{ e.starts_at|dt }}</span>{% else %}<span class="badge b-ok">kalan <span data-end="{{ e.ends_at }}"></span></span>{% endif %}</td></tr>{% endfor %}</table></div>
{% else %}<div class="mut">Şu an aktif etkinlik yok.</div>{% endif %}
<p><a class="btn sm" href="{{ url_for('events') }}">Etkinlik yönet</a></p></div>
<div class="card"><h2>📜 Son işlemler</h2><div class="tw"><table><tr><th>Zaman</th><th>İşlem</th><th>Hedef</th></tr>
{% for l in logs %}<tr><td class="mut">{{ l.created_at|dt }}</td><td>{{ l.action }}</td><td>{{ l.target_type }} {{ l.target_id }}</td></tr>{% endfor %}</table></div>
<p><a class="btn sec sm" href="{{ url_for('logs') }}">Tüm loglar</a></p></div></div>{% endblock %}"""

TEMPLATES["players.html"] = """{% extends 'base.html' %}{% block title %}Oyuncular{% endblock %}{% block body %}
<div class="top"><div><h1>Oyuncular</h1><div class="sub">{{ total|num }} kayıt</div></div></div>
<div class="card" style="margin-bottom:14px"><form class="f" method="get">
<div><label>Ara (kullanıcı adı / çağrı adı / ID)</label><input name="q" value="{{ q }}" style="width:260px"></div>
<div><label>Şirket</label><select name="faction"><option value="">Hepsi</option>{% for f in (1,2,3) %}<option value="{{ f }}" {{ 'selected' if fac==f|string }}>{{ company_name(f) }}</option>{% endfor %}</select></div>
<div><label>Durum</label><select name="status"><option value="">Hepsi</option><option value="banned" {{ 'selected' if status=='banned' }}>Yasaklı</option>
<option value="muted" {{ 'selected' if status=='muted' }}>Susturulmuş</option><option value="admin" {{ 'selected' if status=='admin' }}>Admin</option></select></div>
<button type="submit">Filtrele</button><a class="btn sec" href="{{ url_for('players') }}">Temizle</a></form></div>
<div class="card"><div class="tw"><table><tr><th>ID</th><th>Oyuncu</th><th>Şirket</th><th>Gemi / Harita</th><th>Kredi</th><th>Uridium</th><th>Son giriş</th><th>Durum</th></tr>
{% for r in rows %}<tr><td class="mut">{{ r.id }}</td>
<td><span class="dot {{ 'on' if r.online }}"></span><a href="{{ url_for('player', aid=r.id) }}"><b>{{ r.callsign }}</b></a><div class="mut" style="font-size:12px">{{ r.username }}</div></td>
<td><span class="chip" style="background:{{ company_color(r.faction) }}">{{ company_name(r.faction) }}</span></td>
<td>{% if r.pd %}{{ r.pd.ship }} <span class="mut">· {{ r.pd.map_name }}</span>{% else %}<span class="mut">-</span>{% endif %}</td>
<td>{{ r.pd.cr|num if r.pd else '-' }}</td><td>{{ r.pd.uri|num if r.pd else '-' }}</td><td class="mut">{{ r.last_login|dt }}</td>
<td>{% if r.banned %}<span class="badge b-err">yasaklı</span> {% endif %}{% if r.muted %}<span class="badge b-warn">susturulmuş</span> {% endif %}{% if r.is_admin %}<span class="badge b-acc">admin</span>{% endif %}</td></tr>
{% else %}<tr><td colspan="8" class="mut">Kayıt bulunamadı.</td></tr>{% endfor %}</table></div>
{{ pager(page,pages) }}</div>{% endblock %}"""

TEMPLATES["player.html"] = """{% extends 'base.html' %}{% block title %}{{ acc.callsign }}{% endblock %}{% block body %}
<div class="top"><div><h1><span class="dot {{ 'on' if online }}"></span>{{ acc.callsign }}
<span class="chip" style="background:{{ company_color(acc.faction) }};vertical-align:middle">{{ company_name(acc.faction) }}</span></h1>
<div class="sub">Hesap #{{ acc.id }} · {{ acc.username }} · {{ 'çevrimiçi' if online else 'çevrimdışı' }}
{% if acc.banned %} · <span class="badge b-err">yasaklı</span>{% endif %}{% if acc.muted %} · <span class="badge b-warn">susturulmuş</span>{% endif %}{% if acc.is_admin %} · <span class="badge b-acc">admin</span>{% endif %}</div></div>
<a class="btn sec" href="{{ url_for('players') }}">‹ Listeye dön</a></div>
<div class="grid g2">
<div class="card"><h2>Hesap</h2><div class="kv">
<div class="k">Kayıt</div><div>{{ acc.created_at|dt }}</div><div class="k">Son giriş</div><div>{{ acc.last_login|dt }}</div>
<div class="k">Yasak</div><div>{% if acc.banned %}{{ 'süresiz' if not acc.ban_until else (acc.ban_until|dt) }} · <span class="mut">{{ acc.ban_reason or '-' }}</span>{% else %}yok{% endif %}</div>
<div class="k">Susturma</div><div>{% if acc.muted %}{{ 'süresiz' if not acc.mute_until else (acc.mute_until|dt) }}{% else %}yok{% endif %}</div></div></div>
<div class="card"><h2>Oyun verisi</h2>{% if pd %}<div class="kv">
<div class="k">Kredi</div><div class="big">{{ pd.cr|num }}</div><div class="k">Uridium</div><div class="big">{{ pd.uri|num }}</div>
<div class="k">Deneyim / Onur</div><div>{{ pd.xp|round|int|num }} / {{ pd.hon|round|int|num }}</div>
<div class="k">Öldürme</div><div>{{ pd.kills|num }} NPC · {{ pd.pvp_kills|num }} PvP</div>
<div class="k">Gemi / Harita</div><div>{{ pd.ship }} · {{ pd.map_name }}</div><div class="k">Yetenek puanı</div><div>{{ pd.skill_points }}</div></div>
{% else %}<div class="mut">Henüz hiç oyuna girmemiş (oyun verisi yok).</div>{% endif %}</div></div>
<div class="grid g2" style="margin-top:14px">
<div class="card"><h2>Yönetim işlemleri</h2>
{% if is_super %}<form method="post" action="{{ url_for('resource', aid=acc.id) }}" class="f" data-confirm="Kaynak değişikliği uygulansın mı?" style="margin-bottom:14px">
<input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div><label>Tür</label><select name="kind"><option value="cr">Kredi</option><option value="uri">Uridium</option></select></div>
<div><label>Miktar (+ ekle / − çıkar)</label><input name="amount" type="number" required style="width:140px"></div>
<div style="flex:1;min-width:140px"><label>Sebep (zorunlu)</label><input name="reason" required minlength="3" style="width:100%"></div>
<button type="submit">Uygula</button></form>
<div class="hint" style="margin:-8px 0 14px">Miktar sınırı yok. Bakiye 0'ın altına düşmez. Tüm işlemler loglanır.</div>{% else %}<div class="hint" style="margin-bottom:14px">Kaynak verme/alma, admin rütbesi ve şifre işlemleri yalnızca Süper Admin yetkisindedir.</div>{% endif %}
{% if acc.banned %}<form method="post" action="{{ url_for('unban', aid=acc.id) }}" style="display:inline"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn grn" type="submit">Yasağı kaldır</button></form>
{% else %}<form method="post" action="{{ url_for('ban', aid=acc.id) }}" class="f" data-confirm="Bu oyuncu yasaklansın mı?"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div><label>Süre</label><select name="duration"><option value="3600">1 saat</option><option value="86400" selected>1 gün</option><option value="604800">1 hafta</option><option value="2592000">1 ay</option><option value="-1">Süresiz</option></select></div>
<div style="flex:1;min-width:140px"><label>Yasak sebebi (zorunlu)</label><input name="reason" required minlength="3" style="width:100%"></div><button class="btn red" type="submit">Yasakla</button></form>{% endif %}
<div style="margin-top:14px" class="f">
{% if acc.muted %}<form method="post" action="{{ url_for('unmute', aid=acc.id) }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn grn" type="submit">Susturmayı kaldır</button></form>
{% else %}<form method="post" action="{{ url_for('mute', aid=acc.id) }}" class="f"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<select name="duration"><option value="3600">1 saat</option><option value="86400" selected>1 gün</option><option value="604800">1 hafta</option><option value="-1">Süresiz</option></select><button class="btn sec" type="submit">Sustur</button></form>{% endif %}
{% if is_super %}<form method="post" action="{{ url_for('toggle_admin', aid=acc.id) }}" data-confirm="{{ 'Admin rütbesi alınsın mı? Polis gemisi hangardan kaldırılacak.' if acc.is_admin else 'Admin rütbesi verilsin mi? Polis gemisi hangara eklenecek.' }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<button class="btn sec" type="submit">{{ 'Admin rütbesini al' if acc.is_admin else 'Admin rütbesi ver' }}</button></form>{% endif %}</div>
{% if acc.is_admin %}<div class="hint" style="margin-top:8px">🚓 Polis gemisi: {{ 'hangarda' if 'police' in ships else 'henüz eklenmedi (oyuncu girince ya da ~30 sn içinde eklenir)' }}</div>{% endif %}</div>
<div class="card"><h2>Envanter</h2><div class="kv">
<div class="k">Gemiler</div><div>{% for s in ships %}<span class="badge b-mut">{{ s }}</span> {% else %}-{% endfor %}</div>
<div class="k">Mühimmat</div><div>{% for a in ammo %}<span class="badge b-mut">{{ a.ammo_id }}: {{ a.quantity|num }}</span> {% else %}-{% endfor %}</div>
<div class="k">Droidler</div><div>{% for d in drones %}<span class="badge b-mut">{{ d.drone_id }} ×{{ d.quantity }}{{ ' ✓' if d.equipped }}</span> {% else %}-{% endfor %}</div>
<div class="k">Eşyalar</div><div>{% for i in items %}<span class="badge b-mut">{{ i.item_id }} ×{{ i.quantity }}</span> {% else %}-{% endfor %}</div></div></div>
{% if is_super %}<div class="card"><h2>🔑 Oyuncu şifresi</h2>
<div class="hint" style="margin:-6px 0 12px">Şifreler Argon2id ile tek yönlü saklanır; mevcut şifre <b>görüntülenemez</b>. Bunun yerine yeni şifre belirleyebilir ya da geçici şifre üretip <b>bir kez</b> görebilirsiniz.</div>
<form method="post" action="{{ url_for('player_password', aid=acc.id) }}" data-confirm="Oyuncunun şifresi değiştirilsin mi?"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div class="f"><div><label>Yöntem</label><select name="mode"><option value="generate">Geçici şifre üret (bir kez gösterilir)</option><option value="custom">Şifreyi ben yazayım</option></select></div>
<div><label>Yeni şifre (yalnızca "ben yazayım")</label><input name="new_password" type="password" autocomplete="new-password" maxlength="128"></div></div>
<div class="f" style="margin-top:10px"><div style="flex:1;min-width:160px"><label>Sebep (zorunlu)</label><input name="reason" required minlength="3" style="width:100%"></div>
<div><label>Sizin panel şifreniz</label><input name="admin_password" type="password" required autocomplete="current-password"></div>
<button class="btn red" type="submit">Şifreyi değiştir</button></div></form>
<div class="hint">Oyuncu çevrimiçiyse mevcut oturumu açık kalır; yeni şifre bir sonraki girişte geçerli olur. İşlem loglanır (şifre loglanmaz).</div></div>{% endif %}</div>
<div class="grid g2" style="margin-top:14px">
<div class="card"><h2>Son işlemler (oyun)</h2><div class="tw"><table><tr><th>Zaman</th><th>Tür</th><th>Kredi</th><th>Uridium</th></tr>
{% for t in txs %}<tr><td class="mut">{{ t.created_at|dt }}</td><td>{{ t.type }}</td><td>{{ t.amount_cr|num }}</td><td>{{ t.amount_uri|num }}</td></tr>{% else %}<tr><td colspan="4" class="mut">Kayıt yok</td></tr>{% endfor %}</table></div></div>
<div class="card"><h2>Bu oyuncuya yapılan yönetici işlemleri</h2><div class="tw"><table><tr><th>Zaman</th><th>İşlem</th><th>Detay</th></tr>
{% for l in logs %}<tr><td class="mut">{{ l.created_at|dt }}</td><td>{{ l.action }}</td><td class="pre">{{ l.detail or '-' }}</td></tr>{% else %}<tr><td colspan="3" class="mut">Kayıt yok</td></tr>{% endfor %}</table></div></div></div>{% endblock %}"""

TEMPLATES["online.html"] = """{% extends 'base.html' %}{% block title %}Çevrimiçi{% endblock %}{% block body %}
<div class="top"><div><h1>Çevrimiçi oyuncular</h1><div class="sub">{{ rows|length }} oyuncu bağlı · her yenilemede güncellenir</div></div><a class="btn sec" href="{{ url_for('online') }}">↻ Yenile</a></div>
<div class="card" style="margin-bottom:14px"><h2>Harita dağılımı</h2>{% for m,c in maps %}<span class="badge b-acc" style="margin:2px">{{ m }}: {{ c }}</span>{% else %}<span class="mut">Kimse bağlı değil.</span>{% endfor %}</div>
<div class="card"><div class="tw"><table><tr><th>Oyuncu</th><th>Şirket</th><th>Harita</th><th>Gemi</th><th>Kredi</th><th>Uridium</th><th>Bağlanma</th></tr>
{% for r in rows %}<tr><td><a href="{{ url_for('player', aid=r.id) }}"><b>{{ r.callsign }}</b></a>{% if r.is_admin %} <span class="badge b-acc">admin</span>{% endif %}</td>
<td><span class="chip" style="background:{{ company_color(r.faction) }}">{{ company_name(r.faction) }}</span></td><td>{{ r.map_name or '-' }}</td><td>{{ r.ship or '-' }}</td>
<td>{{ r.cr|num }}</td><td>{{ r.uri|num }}</td><td class="mut">{{ r.locked_at|dt }}</td></tr>{% else %}<tr><td colspan="7" class="mut">Şu an çevrimiçi oyuncu yok.</td></tr>{% endfor %}</table></div></div>{% endblock %}"""

TEMPLATES["events.html"] = """{% extends 'base.html' %}{% block title %}Etkinlikler{% endblock %}{% block body %}
<div class="top"><div><h1>Etkinlikler</h1><div class="sub">Şirkete özel zamanlı ödül bonusu</div></div></div>
<div class="card" style="margin-bottom:14px"><h2>⚡ Yeni bonus etkinliği başlat</h2>
<form method="post" action="{{ url_for('event_start') }}" id="evf" data-confirm="Etkinlik başlatılsın mı? Seçilen şirketin oyuncuları bonus almaya başlayacak.">
<input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div class="f"><div><label>Şirket</label><select name="faction"><option value="0">Tüm şirketler</option>
{% for k,v in companies.items() %}<option value="{{ k }}">{{ v }}</option>{% endfor %}</select></div>
<div><label>Bonus yüzdesi (+%)</label><input name="bonus_pct" id="pct" type="number" min="1" max="{{ max_pct }}" value="300" style="width:120px" required></div>
<div><label>Süre (dakika)</label><input name="minutes" id="min" type="number" min="1" max="{{ max_min }}" value="60" style="width:120px" required></div>
<div><label>Hızlı süre</label><button type="button" class="btn sec sm" onclick="document.getElementById('min').value=30">30 dk</button>
<button type="button" class="btn sec sm" onclick="document.getElementById('min').value=60">1 saat</button>
<button type="button" class="btn sec sm" onclick="document.getElementById('min').value=120">2 saat</button></div>
<div><label>Başlama gecikmesi (dk, 0 = hemen)</label><input name="delay" type="number" min="0" value="0" style="width:120px"></div></div>
<div class="f" style="margin-top:12px"><div><label>Kapsam</label>
<label style="display:inline;color:var(--txt)"><input type="checkbox" name="scope_npc" checked> NPC öldürme</label>&nbsp;&nbsp;
<label style="display:inline;color:var(--txt)"><input type="checkbox" name="scope_pvp" checked> Oyuncu öldürme (PvP)</label></div>
<div><label>Ödül türleri</label>
<label style="display:inline;color:var(--txt)"><input type="checkbox" name="res_cr" checked> Kredi</label>&nbsp;
<label style="display:inline;color:var(--txt)"><input type="checkbox" name="res_uri" checked> Uridium</label>&nbsp;
<label style="display:inline;color:var(--txt)"><input type="checkbox" name="res_xp" checked> Deneyim</label>&nbsp;
<label style="display:inline;color:var(--txt)"><input type="checkbox" name="res_hon" checked> Onur</label></div>
<div style="flex:1;min-width:180px"><label>Not (isteğe bağlı)</label><input name="note" maxlength="120" style="width:100%"></div></div>
<div class="flash warn" style="margin-top:14px" id="prev"></div>
<div class="hint">Bonus yalnızca seçilen şirketin oyuncularının <b>kendi</b> öldürdüğü NPC/oyunculardan gelen ödüle uygulanır. PvP ödülü oyunda Onur'dur.
Aynı şirket için aynı anda iki etkinlik çalıştırılamaz. En fazla +%{{ max_pct }}.</div>
<p><button type="submit" class="btn grn">Etkinliği başlat</button></p></form></div>
<script>(function(){var p=document.getElementById('pct'),m=document.getElementById('min'),o=document.getElementById('prev');
function u(){var x=parseInt(p.value)||0,y=parseInt(m.value)||0;var k=(1+x/100);o.textContent='+%'+x+' bonus = normal ödülün '+(Math.round(k*100)/100)+' katı, '+y+' dakika boyunca. '+
(x>0?'(Örnek: 1.000 kredi → '+Math.round(1000*k).toLocaleString('tr-TR')+' kredi)':'');}
p.oninput=m.oninput=u;u();})();</script>
<div class="card"><h2>Etkinlik geçmişi</h2><div class="tw"><table><tr><th>#</th><th>Şirket</th><th>Bonus</th><th>Kapsam</th><th>Zaman</th><th>Durum</th><th>Verilen ekstra</th><th></th></tr>
{% for e in rows %}<tr><td class="mut">{{ e.id }}</td><td><span class="chip" style="background:{{ company_color(e.faction) }}">{{ company_name(e.faction) }}</span></td>
<td><b>+%{{ e.bonus_pct }}</b><div class="mut" style="font-size:12px">x{{ '%g' % (1 + e.bonus_pct/100) }}</div></td>
<td>{% if e.scope_npc %}NPC {% endif %}{% if e.scope_pvp %}PvP{% endif %}<div class="mut" style="font-size:12px">{{ e.resources }}</div></td>
<td class="mut" style="font-size:12px">{{ e.starts_at|dt }}<br>→ {{ (e.ended_at or e.ends_at)|dt }}</td>
<td>{% if e.status=='aktif' %}<span class="badge b-ok">aktif · <span data-end="{{ e.ends_at }}"></span></span>
{% elif e.status=='planlı' %}<span class="badge b-warn">planlı</span>{% elif e.status=='iptal' %}<span class="badge b-err">elle bitirildi</span>{% else %}<span class="badge b-mut">bitti</span>{% endif %}</td>
<td style="font-size:12px">{{ e.boosted_rewards|num }} ödül<br>+{{ e.extra_cr|num }} kr · +{{ e.extra_uri|num }} uri<br>+{{ e.extra_xp|round|int|num }} xp · +{{ e.extra_hon|round|int|num }} onur</td>
<td>{% if e.status in ('aktif','planlı') %}<form method="post" action="{{ url_for('event_end', eid=e.id) }}" data-confirm="Etkinlik şimdi bitirilsin mi?"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn red sm" type="submit">Bitir</button></form>{% endif %}</td></tr>
{% else %}<tr><td colspan="8" class="mut">Henüz etkinlik yok.</td></tr>{% endfor %}</table></div></div>{% endblock %}"""

TEMPLATES["maps.html"] = """{% extends 'base.html' %}{% block title %}Haritalar{% endblock %}{% block body %}
<div class="top"><div><h1>Haritalar</h1><div class="sub">Harita başına NPC üst sınırı (boş = oyunun varsayılanı)</div></div></div>
<div class="card" style="margin-bottom:14px"><form method="post" action="{{ url_for('map_set') }}" class="f"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div><label>Harita</label><select name="map_id">{% for r in rows %}<option>{{ r.map }}</option>{% endfor %}</select></div>
<div><label>NPC üst sınırı (0-1000)</label><input name="npc_count" type="number" min="0" max="1000" required style="width:150px"></div>
<button type="submit">Kaydet</button></form></div>
<div class="card"><div class="tw"><table><tr><th>Harita</th><th>Oyuncu</th><th>NPC sınırı</th><th>Son değişiklik</th><th></th></tr>
{% for r in rows %}<tr><td><b>{{ r.map }}</b></td><td>{{ r.players }}</td>
<td>{% if r.override %}<span class="badge b-acc">{{ r.override.npc_count }}</span>{% else %}<span class="mut">varsayılan</span>{% endif %}</td>
<td class="mut">{{ r.override.updated_at|dt if r.override else '-' }}</td>
<td>{% if r.override %}<form method="post" action="{{ url_for('map_clear') }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><input type="hidden" name="map_id" value="{{ r.map }}"><button class="btn sec sm" type="submit">Sınırı kaldır</button></form>{% endif %}</td></tr>{% endfor %}</table></div></div>{% endblock %}"""

TEMPLATES["economy.html"] = """{% extends 'base.html' %}{% block title %}Ekonomi{% endblock %}{% block body %}
<div class="top"><div><h1>Ekonomi</h1><div class="sub">Dolaşımdaki kaynaklar ve yönetici işlemleri</div></div></div>
<div class="grid g4"><div class="card stat"><div class="l">Toplam kredi</div><div class="v">{{ tot.cr|num }}</div></div>
<div class="card stat"><div class="l">Toplam uridium</div><div class="v">{{ tot.uri|num }}</div></div>
<div class="card stat"><div class="l">Oyun verisi olan hesap</div><div class="v">{{ tot.n|num }}</div></div>
<div class="card stat"><div class="l">Son 24sa yönetici verdi</div><div class="v" style="font-size:18px">{{ day.cr|num }} kr<br>{{ day.uri|num }} uri</div></div></div>
<div class="grid g2" style="margin-top:14px"><div class="card"><h2>Şirket bazında</h2><div class="tw"><table><tr><th>Şirket</th><th>Oyuncu</th><th>Kredi</th><th>Uridium</th></tr>
{% for p in per %}<tr><td><span class="chip" style="background:{{ company_color(p.faction) }}">{{ company_name(p.faction) }}</span></td><td>{{ p.n }}</td><td>{{ p.cr|num }}</td><td>{{ p.uri|num }}</td></tr>{% endfor %}</table></div></div>
<div class="card"><h2>Son yönetici işlemleri</h2><div class="tw"><table><tr><th>Zaman</th><th>Oyuncu</th><th>Tür</th><th>Miktar</th></tr>
{% for t in admin_tx %}<tr><td class="mut">{{ t.created_at|dt }}</td><td><a href="{{ url_for('player', aid=t.aid) }}">{{ t.callsign or t.aid }}</a></td><td>{{ t.type }}</td>
<td>{{ ('%+d kr'|format(t.amount_cr)) if t.amount_cr else '' }} {{ ('%+d uri'|format(t.amount_uri)) if t.amount_uri else '' }}</td></tr>{% else %}<tr><td colspan="4" class="mut">Kayıt yok</td></tr>{% endfor %}</table></div></div>
<div class="card"><h2>En çok uridium (adminler hariç)</h2><div class="tw"><table><tr><th>#</th><th>Oyuncu</th><th>Uridium</th><th>Kredi</th></tr>
{% for r in rich_uri %}<tr><td class="mut">{{ loop.index }}</td><td><a href="{{ url_for('player', aid=r.id) }}">{{ r.callsign }}</a></td><td>{{ r.uri|num }}</td><td>{{ r.cr|num }}</td></tr>{% endfor %}</table></div></div>
<div class="card"><h2>En çok kredi (adminler hariç)</h2><div class="tw"><table><tr><th>#</th><th>Oyuncu</th><th>Kredi</th><th>Uridium</th></tr>
{% for r in rich_cr %}<tr><td class="mut">{{ loop.index }}</td><td><a href="{{ url_for('player', aid=r.id) }}">{{ r.callsign }}</a></td><td>{{ r.cr|num }}</td><td>{{ r.uri|num }}</td></tr>{% endfor %}</table></div></div></div>{% endblock %}"""

TEMPLATES["logs.html"] = """{% extends 'base.html' %}{% block title %}Loglar{% endblock %}{% block body %}
<div class="top"><div><h1>Yönetici logları</h1><div class="sub">{{ total|num }} kayıt · saatler İstanbul saati</div></div></div>
<div class="card" style="margin-bottom:14px"><form class="f" method="get">
<div><label>Ara</label><input name="q" value="{{ q }}" style="width:200px"></div>
<div><label>İşlem</label><select name="action"><option value="">Hepsi</option>{% for a in actions %}<option {{ 'selected' if a==action }}>{{ a }}</option>{% endfor %}</select></div>
<div><label>Hedef tipi</label><select name="type"><option value="">Hepsi</option>{% for t in ('account','event','map','admin','staff') %}<option {{ 'selected' if t==ttype }}>{{ t }}</option>{% endfor %}</select></div>
<div><label>Başlangıç</label><input type="date" name="from" value="{{ d_from }}"></div><div><label>Bitiş</label><input type="date" name="to" value="{{ d_to }}"></div>
<button type="submit">Filtrele</button><a class="btn sec" href="{{ url_for('logs') }}">Temizle</a></form></div>
<div class="card"><div class="tw"><table><tr><th>Zaman</th><th>İşlem</th><th>Hedef</th><th>Detay</th></tr>
{% for l in rows %}<tr><td class="mut" style="white-space:nowrap">{{ l.created_at|dt }}</td><td><span class="badge b-mut">{{ l.action }}</span></td>
<td>{{ l.target_type }} {% if l.target_type=='account' %}<a href="{{ url_for('player', aid=l.target_id) }}">#{{ l.target_id }}</a>{% else %}{{ l.target_id }}{% endif %}</td><td class="pre">{{ l.detail or '-' }}</td></tr>
{% else %}<tr><td colspan="4" class="mut">Kayıt bulunamadı.</td></tr>{% endfor %}</table></div>{{ pager(page,pages) }}</div>{% endblock %}"""

TEMPLATES["login_2fa.html"] = """<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NovaGate 2FA</title><style>""" + _CSS + """
body{display:flex;align-items:center;justify-content:center;min-height:100vh;
background:radial-gradient(900px 500px at 70% -10%,rgba(99,102,241,.25),transparent),radial-gradient(700px 400px at 0% 110%,rgba(56,189,248,.18),transparent),var(--bg)}
.box{width:min(380px,92vw)}.box h1{text-align:center;margin-bottom:4px}.box input{width:100%;margin-bottom:12px}
</style></head><body><div class="card box"><h1>NOVA<span style="color:var(--acc)">GATE</span></h1>
<p class="sub" style="text-align:center;margin-top:0">İki adımlı doğrulama</p>
{% if error %}<div class="flash err">{{ error }}</div>{% endif %}
{% with msgs = get_flashed_messages(with_categories=true) %}{% for c,m in msgs %}<div class="flash {{ c }}">{{ m }}</div>{% endfor %}{% endwith %}
<form method="post" autocomplete="off"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<label>Doğrulama uygulamasındaki 6 haneli kod</label>
<input name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]*" maxlength="7" required autofocus style="letter-spacing:6px;font-size:22px;text-align:center">
<button type="submit" style="width:100%">Doğrula</button></form>
<p class="sub" style="text-align:center;margin-bottom:0"><a href="{{ url_for('login') }}">‹ Girişe dön</a></p></div></body></html>"""

TEMPLATES["pwreset.html"] = """{% extends 'base.html' %}{% block title %}Şifre değiştirildi{% endblock %}{% block body %}
<div class="card" style="max-width:600px"><h1>Şifre değiştirildi</h1>
<p class="sub">{{ who.callsign if who else '' }} ({{ who.username if who else aid }}) · hesap #{{ aid }}</p>
{% if shown %}<p>Geçici şifre (<b>yalnızca bu sayfada, bir kez</b> gösterilir):</p>
<div class="big" style="font-size:26px;letter-spacing:2px;user-select:all;margin:8px 0 14px">{{ shown }}</div>
<div class="flash warn">Oyuncuya güvenli bir kanaldan iletin ve girişten sonra oyun içinden değiştirmesini söyleyin. Bu sayfadan ayrılınca şifre bir daha görüntülenemez.</div>
{% else %}<p>Yeni şifre kaydedildi. Oyuncu bir sonraki girişinde bunu kullanır.</p>{% endif %}
<p class="hint">Oyuncu çevrimiçiyse mevcut oturumu açık kalır. İşlem loglandı (şifre loglanmaz).</p>
<a class="btn" href="{{ url_for('player', aid=aid) }}">Oyuncu kartına dön</a></div>{% endblock %}"""

TEMPLATES["account.html"] = """{% extends 'base.html' %}{% block title %}Hesabım{% endblock %}{% block body %}
<div class="top"><div><h1>Hesabım</h1><div class="sub">{{ me.username }} · <span class="badge b-acc">{{ role_label[me.role] }}</span> · son giriş {{ me.last_login|dt }}</div></div></div>
<div class="grid g2">
<div class="card"><h2>🔑 Şifre değiştir</h2>
<form method="post" action="{{ url_for('account_password') }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<label>Mevcut şifre</label><input type="password" name="current" required autocomplete="current-password" style="width:100%;margin-bottom:10px">
<label>Yeni şifre (en az {{ min_pw }} karakter)</label><input type="password" name="new" required minlength="{{ min_pw }}" autocomplete="new-password" style="width:100%;margin-bottom:10px">
<label>Yeni şifre (tekrar)</label><input type="password" name="again" required minlength="{{ min_pw }}" autocomplete="new-password" style="width:100%;margin-bottom:12px">
<button type="submit">Şifreyi güncelle</button></form></div>
<div class="card"><h2>🛡 İki adımlı doğrulama (2FA)</h2>
{% if me.totp_enabled %}
<p><span class="badge b-ok">Açık</span> Girişte şifrenin yanında doğrulama uygulamasındaki 6 haneli kod da istenir.</p>
<form method="post" action="{{ url_for('account_2fa_disable') }}" data-confirm="2FA kapatılsın mı? Hesabınızın güvenliği azalır."><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div class="f"><div><label>Şifreniz</label><input type="password" name="current" required autocomplete="current-password"></div>
<div><label>Güncel kod</label><input name="code" inputmode="numeric" required maxlength="7" style="width:110px"></div>
<button class="btn red" type="submit">2FA'yı kapat</button></div></form>
{% elif setup %}
<p>1) Telefonunuzda Google Authenticator, Microsoft Authenticator veya Authy'yi açın ve <b>kurulum anahtarı gir</b> (manuel giriş) seçeneğini seçin.</p>
<p>Hesap adı: <b>NovaGate ({{ me.username }})</b> · tür: <b>zamana dayalı</b> · anahtar:</p>
<div class="big pre" style="font-size:19px;letter-spacing:2px;user-select:all;margin:6px 0">{{ grouped }}</div>
<div class="hint" style="margin-bottom:12px">Uygulama bağlantı kabul ediyorsa: <span class="pre" style="user-select:all">{{ uri }}</span></div>
<form method="post" action="{{ url_for('account_2fa_enable') }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<p>2) Uygulamanın gösterdiği 6 haneli kodu girin:</p>
<div class="f"><input name="code" inputmode="numeric" required maxlength="7" autofocus style="width:130px;letter-spacing:4px;font-size:18px;text-align:center">
<button class="btn grn" type="submit">Doğrula ve aç</button></div></form>
<form method="post" action="{{ url_for('account_2fa_cancel') }}" style="margin-top:10px"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn sec sm" type="submit">İptal</button></form>
{% else %}
<p><span class="badge b-warn">Kapalı</span> Hesabınızı korumak için açmanız önerilir.</p>
<form method="post" action="{{ url_for('account_2fa_start') }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn grn" type="submit">2FA kurulumunu başlat</button></form>
<div class="hint">Telefonunuzu kaybederseniz sunucuda <span class="pre">admin_panel.py --reset-2fa KULLANICI</span> komutuyla sıfırlanır.</div>
{% endif %}</div></div>{% endblock %}"""

TEMPLATES["staff.html"] = """{% extends 'base.html' %}{% block title %}Yetkililer{% endblock %}{% block body %}
<div class="top"><div><h1>Panel yetkilileri</h1><div class="sub">Yönetim paneline girebilen hesaplar · roller · 2FA durumu</div></div></div>
<div class="card" style="margin-bottom:14px"><h2>Roller</h2><div class="kv">
<div class="k">Süper Admin</div><div>Her şey: kaynak verme, admin rütbesi (polis gemisi), oyuncu şifresi, etkinlik, harita, ekonomi ve yetkili yönetimi.</div>
<div class="k">Moderatör</div><div>Oyuncuları, çevrimiçi listesini ve logları görür; oyuncu yasaklar / susturur. Kaynak, rütbe, şifre, etkinlik, harita, ekonomi ve yetkili yönetimi yoktur.</div></div></div>
<div class="card" style="margin-bottom:14px"><h2>Yeni yetkili ekle</h2>
<form method="post" action="{{ url_for('staff_add') }}" class="f" data-confirm="Yeni panel hesabı oluşturulsun mu?"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<div><label>Kullanıcı adı</label><input name="username" required minlength="3" maxlength="24" autocomplete="off" style="width:160px"></div>
<div><label>Rol</label><select name="role"><option value="mod">Moderatör</option><option value="super">Süper Admin</option></select></div>
<div><label>Başlangıç şifresi (en az {{ min_pw }})</label><input name="password" type="password" required minlength="{{ min_pw }}" autocomplete="new-password"></div>
<div><label>Sizin şifreniz</label><input name="admin_password" type="password" required autocomplete="current-password"></div>
<button class="btn grn" type="submit">Ekle</button></form></div>
<div class="card" style="margin-bottom:14px"><div class="tw"><table><tr><th>Kullanıcı</th><th>Rol</th><th>2FA</th><th>Durum</th><th>Son giriş</th><th>İşlemler</th></tr>
{% for s in rows %}<tr><td><b>{{ s.username }}</b>{% if s.id==me.id %} <span class="badge b-acc">siz</span>{% endif %}<div class="mut" style="font-size:12px">ekleyen: {{ s.created_by or '-' }}</div></td>
<td><span class="badge {{ 'b-acc' if s.role=='super' else 'b-mut' }}">{{ role_label[s.role] }}</span></td>
<td>{% if s.totp_enabled %}<span class="badge b-ok">açık</span>{% else %}<span class="badge b-warn">kapalı</span>{% endif %}</td>
<td>{% if s.active %}<span class="badge b-ok">aktif</span>{% else %}<span class="badge b-err">devre dışı</span>{% endif %}</td>
<td class="mut">{{ s.last_login|dt }}</td>
<td>{% if s.id==me.id %}<a class="btn sec sm" href="{{ url_for('account') }}">Hesabım</a>{% else %}
<div class="f" style="gap:6px;align-items:center">
<form method="post" action="{{ url_for('staff_role', sid=s.id) }}" class="f" style="gap:4px"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<select name="role"><option value="mod" {{ 'selected' if s.role=='mod' }}>Moderatör</option><option value="super" {{ 'selected' if s.role=='super' }}>Süper Admin</option></select><button class="btn sec sm" type="submit">Rol</button></form>
<form method="post" action="{{ url_for('staff_active', sid=s.id) }}" data-confirm="{{ 'Hesap devre dışı bırakılsın mı?' if s.active else 'Hesap etkinleştirilsin mi?' }}"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn {{ 'red' if s.active else 'grn' }} sm" type="submit">{{ 'Devre dışı bırak' if s.active else 'Etkinleştir' }}</button></form>
{% if s.totp_enabled %}<form method="post" action="{{ url_for('staff_reset2fa', sid=s.id) }}" data-confirm="Bu kişinin 2FA'sı sıfırlansın mı?"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button class="btn sec sm" type="submit">2FA sıfırla</button></form>{% endif %}
<details><summary class="btn sec sm" style="list-style:none">Şifre belirle</summary>
<form method="post" action="{{ url_for('staff_password', sid=s.id) }}" class="f" style="margin-top:6px" data-confirm="Bu kişinin şifresi değiştirilsin mi?"><input type="hidden" name="csrf_token" value="{{ csrf() }}">
<input name="password" type="password" placeholder="yeni şifre" required minlength="{{ min_pw }}" autocomplete="new-password"><input name="admin_password" type="password" placeholder="sizin şifreniz" required autocomplete="current-password"><button class="btn sm" type="submit">Kaydet</button></form></details></div>{% endif %}</td></tr>{% endfor %}</table></div></div>
<div class="card"><h2>🚓 Polis gemisi senkronizasyonu</h2>
<p class="sub" style="margin-top:-6px">Admin rütbesi verdiğinizde polis gemisi hangara girer, aldığınızda kaybolur. Bu araç eski/tutarsız kayıtları toplu düzeltir.</p>
<div class="kv"><div class="k">Admin ama gemisi yok</div><div>{% if pm.missing %}{% for r in pm.missing[:10] %}<a href="{{ url_for('player', aid=r.id) }}">{{ r.callsign }}</a>{{ ', ' if not loop.last }}{% endfor %}{% if pm.missing|length>10 %} …+{{ pm.missing|length-10 }}{% endif %}{% else %}<span class="mut">yok ✓</span>{% endif %}</div>
<div class="k">Admin değil ama polis gemisi var</div><div>{% if pm.extra %}{% for r in pm.extra[:10] %}<a href="{{ url_for('player', aid=r.id) }}">{{ r.callsign }}</a>{{ ', ' if not loop.last }}{% endfor %}{% if pm.extra|length>10 %} …+{{ pm.extra|length-10 }}{% endif %}{% else %}<span class="mut">yok ✓</span>{% endif %}</div></div>
{% if pm.missing or pm.extra %}<form method="post" action="{{ url_for('police_sync') }}" style="margin-top:12px" data-confirm="Polis gemileri adminlik durumuna göre düzeltilsin mi?"><input type="hidden" name="csrf_token" value="{{ csrf() }}"><button type="submit">Şimdi senkronize et</button></form>{% endif %}</div>{% endblock %}"""


app.jinja_loader = DictLoader(TEMPLATES)


def _cli(argv) -> int:
    """Sunucuda kurtarma komutlari (2FA telefonu kaybolursa / sifre unutulursa):
       python admin_panel.py --list
       python admin_panel.py --reset-2fa KULLANICI
       python admin_panel.py --set-password KULLANICI"""
    import getpass
    cmd = argv[1]
    if cmd == "--list":
        c = get_db(AUTH_DB)
        for r in c.execute("SELECT id, username, role, active, totp_enabled FROM panel_admins ORDER BY id"):
            print(f"#{r['id']} {r['username']} rol={r['role']} aktif={r['active']} 2fa={r['totp_enabled']}")
        c.close()
        return 0
    if len(argv) != 3:
        print(_cli.__doc__)
        return 2
    adm = get_panel_admin(username=argv[2])
    if not adm:
        print("Yetkili bulunamadi.")
        return 1
    c = get_db(AUTH_DB)
    try:
        if cmd == "--reset-2fa":
            c.execute("UPDATE panel_admins SET totp_enabled=0, totp_secret=NULL, totp_last_step=0 WHERE id=?", (adm["id"],))
            admin_log("2fa_reset", "staff", adm["username"], "sunucu komut satırından sıfırlandı", actor="cli")
            print("2FA sıfırlandı.")
        elif cmd == "--set-password":
            pw = getpass.getpass("Yeni şifre: ")
            if pw != getpass.getpass("Tekrar: "):
                print("Şifreler aynı değil.")
                return 1
            err = check_new_panel_password(pw, adm["username"])
            if err:
                print(err)
                return 1
            c.execute("UPDATE panel_admins SET password_hash=?, pw_changed_at=?, active=1 WHERE id=?",
                      (hash_password(pw), now_ts(), adm["id"]))
            admin_log("staff_password", "staff", adm["username"], "sunucu komut satırından belirlendi", actor="cli")
            print("Şifre güncellendi.")
        else:
            print(_cli.__doc__)
            return 2
    finally:
        c.close()
    return 0


if __name__ == "__main__":
    ensure_schema()
    if len(sys.argv) > 1:
        sys.exit(_cli(sys.argv))
    app.run(host=ADMIN_HOST, port=ADMIN_PORT, debug=False, threaded=True)

