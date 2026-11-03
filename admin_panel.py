#!/usr/bin/env python3
# =============================================================================
# NOVAGATE 3D - ADMIN KONTROL PANELI
# Sadece 127.0.0.1'den erisilebilir (SSH tüneliyle)
# Kullanici: NOVAGATE, sifre: >= 24 karakter rastgele (argon2 hash)
# =============================================================================

import os
import sys
import time
import json
import sqlite3
import secrets
import hashlib
import hmac
import logging
from datetime import datetime, timezone
from functools import wraps
from flask import Flask, request, redirect, url_for, render_template_string, session, make_response, abort

logging.basicConfig(level=logging.INFO, format="%(asctime)s [ADMIN] %(levelname)s %(message)s")
log = logging.getLogger("admin_panel")

ADMIN_HOST = "127.0.0.1"
ADMIN_PORT = 8445
ADMIN_USER = "NOVAGATE"
SECRET_KEY = secrets.token_hex(32)
SESSION_TIMEOUT = 30 * 60  # 30 dakika
FAILURE_LIMIT = 5
LOCKOUT_SECONDS = 15 * 60  # 15 dakika

# Argon2 varsa kullan, yoksa scrypt
try:
    from argon2 import PasswordHasher
    _ph = PasswordHasher()
    def hash_password(pw: str) -> str:
        return _ph.hash(pw)
    def verify_password(pw: str, h: str) -> bool:
        try:
            _ph.verify(h, pw)
            return True
        except Exception:
            return False
    HASH_ALGO = "argon2"
except Exception:
    HASH_ALGO = "scrypt"
    def hash_password(pw: str) -> str:
        salt = os.urandom(16)
        dk = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=64)
        return hashlib.sha256((salt + dk).hex().encode()).hexdigest() + "$scrypt$" + salt.hex()
    def verify_password(pw: str, h: str) -> bool:
        try:
            algo, salt_hex = h.rsplit("$scrypt$", 1)
            salt = bytes.fromhex(salt_hex)
            dk = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=64)
            expected = hashlib.sha256((salt + dk).hex().encode()).hexdigest() + "$scrypt$" + salt_hex
            return hmac.compare_digest(expected, h)
        except Exception:
            return False

# ---------------------------------------------------------------------------
# SHIFRE (tek seferlik uretildi, sadece hash saklanir, sifre asla dosyaya yazilmaz)
# Sifre: (>= 24 karakter, secrets ile tek seferlik uretildi, en sonda bir kez gosterr)
# ---------------------------------------------------------------------------
ADMIN_PASSWORD_HASH = "$argon2id$v=19$m=65536,t=3,p=4$LDgzzc3n5bmXVyYJstyZww$74J8XW5mgHEHshqwfwxA87Bn/6aivIDlA7I/NNJpgU8"

# ---------------------------------------------------------------------------
# VERITABANI YARDIMCILARI
# ---------------------------------------------------------------------------
AUTH_DB = "/opt/novagate/server/novagate_auth.db"
GAME_DB = "/opt/novagate/server/novagate_game.db"

def get_db(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=10.0, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def now_ts() -> int:
    return int(time.time())

def admin_log(admin_user: str, action: str, target_type: str, target_id: str, detail: str = None):
    """Tum admin islemlerini logla."""
    try:
        conn = get_db(AUTH_DB)
        conn.execute(
            "INSERT INTO admin_log (admin_user, action, target_type, target_id, detail, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (admin_user, action, target_type, target_id, detail, now_ts()),
        )
        conn.close()
    except Exception as e:
        log.error("admin_log yazilamadi: %s", e)

# ---------------------------------------------------------------------------
# GUVENLIK YARDIMCILARI
# ---------------------------------------------------------------------------
failures = {}  # ip -> {"count": int, "locked_until": int}

def is_locked(ip: str) -> bool:
    f = failures.get(ip)
    if not f:
        return False
    if now_ts() < f.get("locked_until", 0):
        return True
    # kilit sure dolmus ise sifirla
    failures.pop(ip, None)
    return False

def record_failure(ip: str):
    f = failures.get(ip, {"count": 0, "locked_until": 0})
    f["count"] = f.get("count", 0) + 1
    if f["count"] >= FAILURE_LIMIT:
        f["locked_until"] = now_ts() + LOCKOUT_SECONDS
    failures[ip] = f

def clear_failures(ip: str):
    failures.pop(ip, None)

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("authed"):
            return redirect(url_for("login", next=request.path))
        if now_ts() - session.get("authed_at", 0) > SESSION_TIMEOUT:
            session.clear()
            return redirect(url_for("login", next=request.path))
        # CSRF kontrolu
        csrf_cookie = request.cookies.get("csrf_token")
        csrf_form = request.form.get("csrf_token") or request.headers.get("X-CSRF-Token")
        if not csrf_cookie or not csrf_form or not hmac.compare_digest(csrf_cookie, csrf_form):
            abort(403)
        return f(*args, **kwargs)
    return decorated

def generate_csrf() -> str:
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_hex(32)
    return session["csrf_token"]

# ---------------------------------------------------------------------------
# FLASK APP
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.secret_key = SECRET_KEY
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SECURE"] = False  # localhost
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

LOGIN_HTML = """
<!DOCTYPE html>
<html>
<head><title>NovaGate Admin Giris</title></head>
<body>
<h2>NovaGate Admin Kontrol Paneli</h2>
{% if error %}<p style="color:red">{{ error }}</p>{% endif %}
{% if locked %}<p style="color:red">Cok fazla hatali deneme. 15 dakika bekleyin.</p>{% endif %}
<form method="post">
  Kullanici: <input name="username" value="NOVAGATE" readonly><br>
  Sifre: <input name="password" type="password"><br>
  <input type="hidden" name="csrf_token" value="{{ csrf }}">
  <button type="submit">Giris</button>
</form>
<p>SSH tunnel: ssh -L 8445:127.0.0.1:8445 ubuntu@18.117.15.199</p>
</body>
</html>
"""

DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head><title>NovaGate Admin Paneli</title></head>
<body>
<h2>NovaGate Admin Kontrol Paneli</h2>
<p>Hos geldin, <b>NOVAGATE</b>. <a href="/admin/logout">Cikis</a></p>

<h3>Oyuncu Arama / Listele</h3>
<form method="get" action="/admin/players">
  <input type="hidden" name="csrf_token" value="{{ csrf }}">
  Kullanici adi / Cagri adi: <input name="q">
  <button type="submit">Ara</button>
</form>
{% if players %}
<table border="1">
<tr><th>ID</th><th>Kullanici</th><th>Cagri</th><th>Ban</th><th>Mute</th><th>Admin</th><th>Islemler</th></tr>
{% for p in players %}
<tr>
<td>{{ p['id'] }}</td><td>{{ p['username'] }}</td><td>{{ p['callsign'] }}</td>
<td>{{ 'EVET' if p['is_banned'] else 'HAYIR' }}</td>
<td>{{ 'EVET' if p['is_muted'] else 'HAYIR' }}</td>
<td>{{ 'EVET' if p['is_admin'] else 'HAYIR' }}</td>
<td>
  <form method="post" action="/admin/ban/{{ p['id'] }}" style="display:inline" onsubmit="return confirm('Bu oyuncuyu yasaklamak istediginizden emin misiniz?')">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <select name="duration"><option value="86400">1 gun</option><option value="604800">1 hafta</option><option value="1296000">15 gun</option><option value="2592000">1 ay</option><option value="-1">Suresiz</option></select>
    <input name="reason" placeholder="sebeb">
    <button type="submit">Ban</button>
  </form>
  <form method="post" action="/admin/unban/{{ p['id'] }}" style="display:inline">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <button type="submit">Ban Kaldir</button>
  </form>
  <form method="post" action="/admin/mute/{{ p['id'] }}" style="display:inline" onsubmit="return confirm('Bu oyuncuyu susturmak istediginizden emin misiniz?')">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <select name="duration"><option value="86400">1 gun</option><option value="604800">1 hafta</option><option value="1296000">15 gun</option><option value="2592000">1 ay</option><option value="-1">Suresiz</option></select>
    <button type="submit">Mute</button>
  </form>
  <form method="post" action="/admin/unmute/{{ p['id'] }}" style="display:inline">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <button type="submit">Mute Kaldir</button>
  </form>
  <form method="post" action="/admin/credit/{{ p['id'] }}" style="display:inline" onsubmit="return confirm('Kredi eklemek istediginizden emin misiniz?')">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <input name="amount" type="number" placeholder="kredi">
    <button type="submit">Kredi Ekle</button>
  </form>
  <form method="post" action="/admin/uri/{{ p['id'] }}" style="display:inline" onsubmit="return confirm('Uridium eklemek istediginizden emin misiniz?')">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <input name="amount" type="number" placeholder="uridium">
    <button type="submit">Uridium Ekle</button>
  </form>
  <form method="post" action="/admin/admin/{{ p['id'] }}" style="display:inline" onsubmit="return confirm('Admin yetkisi degistirmek istediginizden emin misiniz?')">
    <input type="hidden" name="csrf_token" value="{{ csrf }}">
    <button type="submit">{{ 'Admin Yetkisi Al' if p['is_admin'] else 'Admin Ver' }}</button>
  </form>
</td>
</tr>
{% endfor %}
</table>
{% endif %}

<h3>Harita NPC Sayisi</h3>
<form method="post" action="/admin/npc" style="display:inline">
  <input type="hidden" name="csrf_token" value="{{ csrf }}">
  Harita ID: <input name="map_id" placeholder="1-1">
  NPC Sayisi: <input name="npc_count" type="number" min="0" max="1000">
  <button type="submit">Kaydet</button>
</form>

<h3>Admin Islem Logu (son 20)</h3>
<table border="1">
<tr><th>Zaman</th><th>Admin</th><th>Islem</th><th>Hedef Tipi</th><th>Hedef ID</th><th>Detay</th></tr>
{% for l in logs %}
<tr><td>{{ l['created_at'] }}</td><td>{{ l['admin_user'] }}</td><td>{{ l['action'] }}</td><td>{{ l['target_type'] }}</td><td>{{ l['target_id'] }}</td><td>{{ l['detail'] or '-' }}</td></tr>
{% endfor %}
</table>

<p><a href="/admin/logout">Guvenli Cikis</a></p>
</body>
</html>
"""

# ---------------------------------------------------------------------------
# ROTALAR
# ---------------------------------------------------------------------------
@app.before_request
def restrict_localhost():
    if request.remote_addr not in ("127.0.0.1", "::1", "localhost"):
        abort(403)

@app.route("/admin/login", methods=["GET", "POST"])
def login():
    ip = request.remote_addr
    if is_locked(ip):
        return render_template_string(LOGIN_HTML, error=None, locked=True), 403

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        csrf_cookie = request.cookies.get("csrf_token")
        csrf_form = request.form.get("csrf_token", "")
        if not csrf_cookie or not hmac.compare_digest(csrf_cookie, csrf_form):
            record_failure(ip)
            return render_template_string(LOGIN_HTML, error="Gecersiz istek", locked=False), 403

        if username == ADMIN_USER and verify_password(password, ADMIN_PASSWORD_HASH):
            clear_failures(ip)
            session.clear()
            session["authed"] = True
            session["authed_at"] = now_ts()
            session["csrf_token"] = secrets.token_hex(32)
            resp = make_response(redirect(url_for("dashboard")))
            resp.set_cookie("csrf_token", session["csrf_token"], httponly=True, samesite="Lax")
            admin_log(ADMIN_USER, "login", "admin", ADMIN_USER, "basarili giris")
            return resp
        else:
            record_failure(ip)
            admin_log(ADMIN_USER, "login_failed", "admin", ADMIN_USER, "basarisiz giris denemesi")
            return render_template_string(LOGIN_HTML, error="Kullanici adi veya sifre hatali", locked=False), 401

    csrf_val = secrets.token_hex(32)
    resp = make_response(render_template_string(LOGIN_HTML, error=None, locked=False, csrf=csrf_val))
    resp.set_cookie("csrf_token", csrf_val, httponly=True, samesite="Lax")
    return resp

@app.route("/admin/logout")
def logout():
    admin_log(ADMIN_USER, "logout", "admin", ADMIN_USER, "cikis yapildi")
    session.clear()
    resp = make_response(redirect(url_for("login")))
    resp.set_cookie("csrf_token", "", expires=0)
    return resp

@app.route("/admin/")
@require_auth
def dashboard():
    q = request.args.get("q", "").strip()
    players = []
    if q:
        conn = get_db(AUTH_DB)
        like = f"%{q}%"
        cur = conn.execute(
            "SELECT id, username, callsign, is_banned, ban_until, is_muted, mute_until, is_admin "
            "FROM accounts WHERE username LIKE ? OR callsign LIKE ? ORDER BY id LIMIT 50",
            (like, like),
        )
        players = [dict(r) for r in cur.fetchall()]
        conn.close()

    conn = get_db(AUTH_DB)
    cur = conn.execute("SELECT * FROM admin_log ORDER BY created_at DESC LIMIT 20")
    logs = [dict(r) for r in cur.fetchall()]
    conn.close()

    return render_template_string(DASHBOARD_HTML, players=players, logs=logs, csrf=generate_csrf())

@app.route("/admin/players")
@require_auth
def players_list():
    return redirect(url_for("dashboard", q=request.args.get("q", "")))

# ---- Ban / Mute ----
def _set_status(db_path, account_id, field, until_ts, reason=None):
    conn = get_db(db_path)
    conn.execute(f"UPDATE accounts SET {field}=? WHERE id=?", (1 if until_ts else 0, account_id))
    if field == "is_banned":
        conn.execute("UPDATE accounts SET ban_until=?, ban_reason=? WHERE id=?", (until_ts, reason, account_id))
    elif field == "is_muted":
        conn.execute("UPDATE accounts SET mute_until=? WHERE id=?", (until_ts, account_id))
    conn.commit()
    conn.close()
    admin_log(ADMIN_USER, field, "account", str(account_id), reason or f"until={until_ts}")

@app.route("/admin/ban/<int:account_id>", methods=["POST"])
@require_auth
def ban_account(account_id):
    duration = int(request.form.get("duration", "86400"))
    reason = request.form.get("reason", "").strip() or None
    if duration == -1:
        until = 0  # suremsi: is_banned=1, ban_until=0
    else:
        until = now_ts() + duration
    _set_status(AUTH_DB, account_id, "is_banned", until, reason)
    _set_status(GAME_DB, account_id, "is_banned", until, reason)
    # çevrimiçi oyuncuyu atmak icin net_server.gd üzerinden sinyal yok,
    # oyun sunucusu kendi ban kontrolunde kick yapar
    return redirect(url_for("dashboard"))

@app.route("/admin/unban/<int:account_id>", methods=["POST"])
@require_auth
def unban_account(account_id):
    _set_status(AUTH_DB, account_id, "is_banned", 0, None)
    _set_status(GAME_DB, account_id, "is_banned", 0, None)
    return redirect(url_for("dashboard"))

@app.route("/admin/mute/<int:account_id>", methods=["POST"])
@require_auth
def mute_account(account_id):
    duration = int(request.form.get("duration", "86400"))
    if duration == -1:
        until = 0
    else:
        until = now_ts() + duration
    _set_status(AUTH_DB, account_id, "is_muted", until, None)
    _set_status(GAME_DB, account_id, "is_muted", until, None)
    return redirect(url_for("dashboard"))

@app.route("/admin/unmute/<int:account_id>", methods=["POST"])
@require_auth
def unmute_account(account_id):
    _set_status(AUTH_DB, account_id, "is_muted", 0, None)
    _set_status(GAME_DB, account_id, "is_muted", 0, None)
    return redirect(url_for("dashboard"))

# ---- Ekonomi ----
@app.route("/admin/credit/<int:account_id>", methods=["POST"])
@require_auth
def credit_account(account_id):
    amount = int(request.form.get("amount", "0"))
    if amount <= 0:
        return redirect(url_for("dashboard"))
    conn = get_db(GAME_DB)
    conn.execute("BEGIN IMMEDIATE")
    conn.execute("UPDATE player_data SET cr = cr + ?, updated_at = ? WHERE account_id = ?", (amount, now_ts(), account_id))
    conn.execute(
        "INSERT INTO transactions (account_id, tx_id, type, amount_cr, status, created_at) "
        "VALUES (?, ?, 'admin_credit', ?, 'committed', ?)",
        (account_id, secrets.token_hex(16), amount, now_ts()),
    )
    conn.execute("COMMIT")
    conn.close()
    admin_log(ADMIN_USER, "credit", "account", str(account_id), f"+{amount} CR")
    return redirect(url_for("dashboard"))

@app.route("/admin/uri/<int:account_id>", methods=["POST"])
@require_auth
def uri_account(account_id):
    amount = int(request.form.get("amount", "0"))
    if amount <= 0:
        return redirect(url_for("dashboard"))
    conn = get_db(GAME_DB)
    conn.execute("BEGIN IMMEDIATE")
    conn.execute("UPDATE player_data SET uri = uri + ?, updated_at = ? WHERE account_id = ?", (amount, now_ts(), account_id))
    conn.execute(
        "INSERT INTO transactions (account_id, tx_id, type, amount_uri, status, created_at) "
        "VALUES (?, ?, 'admin_uri', ?, 'committed', ?)",
        (account_id, secrets.token_hex(16), amount, now_ts()),
    )
    conn.execute("COMMIT")
    conn.close()
    admin_log(ADMIN_USER, "uri", "account", str(account_id), f"+{amount} URI")
    return redirect(url_for("dashboard"))

# ---- Admin yetkisi ----
@app.route("/admin/admin/<int:account_id>", methods=["POST"])
@require_auth
def toggle_admin(account_id):
    # Tek doğru kaynak: oyun sunucusu is_admin'i GAME_DB (novagate_game.db)'dan okur.
    # Panel degisikligini AUTH_DB ve GAME_DB'ye ikisine de yazarak senkron tutar.
    new_val = None
    for db_path in (AUTH_DB, GAME_DB):
        conn = get_db(db_path)
        try:
            row = conn.execute("SELECT is_admin FROM accounts WHERE id=?", (account_id,)).fetchone()
            new_val = 0 if row and row["is_admin"] else 1
            conn.execute("UPDATE accounts SET is_admin=? WHERE id=?", (new_val, account_id))
            conn.commit()
        finally:
            conn.close()
    admin_log(ADMIN_USER, "admin_toggle", "account", str(account_id), f"is_admin={new_val}")
    return redirect(url_for("dashboard"))

# ---- NPC override ----
@app.route("/admin/npc", methods=["POST"])
@require_auth
def set_npc():
    map_id = request.form.get("map_id", "").strip()
    npc_count = int(request.form.get("npc_count", "0"))
    if not map_id or npc_count < 0 or npc_count > 1000:
        return redirect(url_for("dashboard"))
    conn = get_db(AUTH_DB)
    conn.execute(
        "INSERT OR REPLACE INTO npc_overrides (map_id, npc_count, updated_at) VALUES (?, ?, ?)",
        (map_id, npc_count, now_ts()),
    )
    conn.commit()
    conn.close()
    admin_log(ADMIN_USER, "npc_override", "map", map_id, f"npc_count={npc_count}")
    return redirect(url_for("dashboard"))

# ---- Log ----
@app.route("/admin/log")
@require_auth
def view_log():
    conn = get_db(AUTH_DB)
    cur = conn.execute("SELECT * FROM admin_log ORDER BY created_at DESC LIMIT 100")
    logs = [dict(r) for r in cur.fetchall()]
    conn.close()
    html = "<h2>Admin Islem Logu</h2><table border='1'><tr><th>Zaman</th><th>Admin</th><th>Islem</th><th>Hedef Tipi</th><th>Hedef ID</th><th>Detay</th></tr>"
    for l in logs:
        html += f"<tr><td>{l['created_at']}</td><td>{l['admin_user']}</td><td>{l['action']}</td><td>{l['target_type']}</td><td>{l['target_id']}</td><td>{l['detail'] or '-'}</td></tr>"
    html += "</table><p><a href='/admin/'>Geri</a></p>"
    return html

if __name__ == "__main__":
    app.run(host=ADMIN_HOST, port=ADMIN_PORT, debug=False)
