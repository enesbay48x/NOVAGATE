#!/usr/bin/env python3
"""
NovaGate - oturum kilidi duzeltmesi.

Kullanim:  python3 patch_session_lock.py [PROJE_KOKU]
           (varsayilan: /opt/novagate ; yerelde proje klasoru)

Beklenen yapi:  <kok>/net_server.gd   ve   <kok>/server/server_db.py

Yapilanlar:
 1. server_db.py / acquire_session_lock: kilit eklenmeden once oyun veritabaninda
    hesap satiri yoksa olusturulur (session_locks.account_id -> accounts(id) FK hatasi giderilir).
    Ayrica sadece OperationalError degil tum sqlite3.Error yakalanir ve gercek hata loglanir.
 2. net_server.gd / on_attach_token: bos DB cevabi ile gercek kilit ayrilir,
    mesajdaki yazim hatasi ("zaska") duzeltilir.
 3. net_server.gd / on_disconnect: oyuncu ayrilinca release_session_lock cagrilir.

Her dosyanin yedegi <dosya>.kilit_oncesi_yedek olarak alinir. Tekrar calistirmak zararsizdir.
"""
import os
import re
import shutil
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/opt/novagate"
DB_PY = os.path.join(ROOT, "server", "server_db.py")
NET_GD = os.path.join(ROOT, "net_server.gd")
BACKUP_SUFFIX = ".kilit_oncesi_yedek"


def read(p):
    with open(p, "r", encoding="utf-8", newline="") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def backup(p):
    b = p + BACKUP_SUFFIX
    if not os.path.exists(b):
        shutil.copy2(p, b)
        print("  yedek:", b)


def replace_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        sys.exit("HATA: '%s' icin aranan metin %d kez bulundu (1 olmali). Dosya degismis olabilir, duruyorum." % (label, n))
    return text.replace(old, new)


# ---------------------------------------------------------------- server_db.py
print("server_db.py:", DB_PY)
src = read(DB_PY)
if "# [KILIT-FIX]" in src:
    print("  zaten uygulanmis, atlandi")
else:
    start = src.find("def acquire_session_lock(")
    if start < 0:
        sys.exit("HATA: acquire_session_lock bulunamadi")
    m = re.search(r"\n(?=def |# -{20,})", src[start + 10:])
    end = start + 10 + (m.start() if m else len(src) - start - 10)
    func = src[start:end]

    # 1) hesap satirini garanti et
    func = replace_once(
        func,
        "        expires_at = now + ttl_seconds\n",
        "        expires_at = now + ttl_seconds\n"
        "\n"
        "        # [KILIT-FIX] session_locks.account_id -> accounts(id) FK'si var. Hesap auth DB'sinde\n"
        "        # olusturuldugu icin oyun DB'sinde satir henuz olmayabilir; yoksa yer tutucu olustur\n"
        "        # (load_player_state ile ayni degerler).\n"
        "        conn.execute(\n"
        "            \"INSERT OR IGNORE INTO accounts (id, username, password_hash, faction, callsign, created_at) \"\n"
        "            \"VALUES (?, ?, '', 1, ?, ?)\",\n"
        "            (account_id, f\"player_{account_id}\", f\"player_{account_id}\", now),\n"
        "        )\n",
        "acquire_session_lock hesap garantisi",
    )
    # 2) tum sqlite hatalarini yakala, gercek hatayi logla
    func = replace_once(
        func,
        "    except sqlite3.OperationalError as e:",
        "    except sqlite3.Error as e:",
        "except blogu",
    )
    func = replace_once(
        func,
        'log.warning("acquire_session_lock BUSY: %s", e)',
        'log.warning("acquire_session_lock HATA (%s): %s", type(e).__name__, e)',
        "log satiri",
    )
    backup(DB_PY)
    write(DB_PY, src[:start] + func + src[end:])
    print("  uygulandi")

# ---------------------------------------------------------------- net_server.gd
print("net_server.gd:", NET_GD)
gd = read(NET_GD)
if "# [KILIT-FIX]" in gd:
    print("  zaten uygulanmis, atlandi")
else:
    # 2) hata mesajini ayir + yazim hatasi
    gd = replace_once(
        gd,
        '\tif not lock_resp.has("ok") or lock_resp["ok"] == false:\n'
        '\t\tprint("[SUNUCU] Session lock reddedildi: account_id=%d" % acct_id)\n'
        '\t\treturn [false, "Hesap zaska baska bir oturumda calisiyor", 0, "", 0, ""]\n',
        '\t# [KILIT-FIX] bos cevap = DB hatasi (gercek kilit degil)\n'
        '\tif lock_resp.is_empty() or not lock_resp.has("ok"):\n'
        '\t\tprint("[SUNUCU] Session lock: DB cevap vermedi: account_id=%d" % acct_id)\n'
        '\t\treturn [false, "Veritabani hatasi, lutfen tekrar dene", 0, "", 0, ""]\n'
        '\tif lock_resp["ok"] == false:\n'
        '\t\tprint("[SUNUCU] Session lock reddedildi: account_id=%d" % acct_id)\n'
        '\t\treturn [false, "Hesap baska bir oturumda calisiyor", 0, "", 0, ""]\n',
        "on_attach_token kilit kontrolu",
    )
    # 3) ayrilinca kilidi birak
    gd = replace_once(
        gd,
        "\tvar p: Dictionary = players[peer]\n\tvar old_map: String = str(p.map)\n\t_remove_from_group(peer, false)\n",
        "\tvar p: Dictionary = players[peer]\n"
        "\t# [KILIT-FIX] oyuncu ayrilinca oturum kilidini birak\n"
        "\tif p.has(\"account_id\"):\n"
        "\t\tdb_send(\"release_session_lock\", {\"account_id\": int(p[\"account_id\"]), \"instance_id\": db_instance_id})\n"
        "\tvar old_map: String = str(p.map)\n\t_remove_from_group(peer, false)\n",
        "on_disconnect",
    )
    backup(NET_GD)
    write(NET_GD, gd)
    print("  uygulandi")

print("Bitti. Degisikliklerin gecerli olmasi icin novagate-db ve novagate-server yeniden baslatilmali.")
