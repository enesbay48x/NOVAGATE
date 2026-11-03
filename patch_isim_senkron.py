#!/usr/bin/env python3
"""
NovaGate - gercek isim duzeltmesi (player_5 yerine kayitli takma ad).

NOT: Once patch_session_lock.py uygulanmis olmali.
Kullanim:  python3 patch_isim_senkron.py [PROJE_KOKU]   (varsayilan /opt/novagate)

Sorun: Hesaplar novagate_auth.db'de olusuyor, oyun sunucusu ise novagate_game.db'den okuyor.
Oyun DB'sinde "player_5" gibi yer tutucu hesap olustugu icin takma ad ve sirket kayboluyor.
Cozum: Giriste (acquire_session_lock icinde) auth DB'den kullanici adi, takma ad ve sirket okunur
(salt okunur) ve oyun DB'sindeki hesap satirina yazilir. Sifre hash'i KOPYALANMAZ.
Mevcut yer tutucu hesaplar da bir sonraki giriste otomatik duzelir.
Yedek: server_db.py.isim_oncesi_yedek. Tekrar calistirmak zararsizdir.
"""
import os
import shutil
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/opt/novagate"
DB_PY = os.path.join(ROOT, "server", "server_db.py")

with open(DB_PY, "r", encoding="utf-8", newline="") as f:
    src = f.read()

if "# [ISIM-FIX]" in src:
    print("Zaten uygulanmis, atlandi.")
    sys.exit(0)

anchor = (
    "            (account_id, f\"player_{account_id}\", f\"player_{account_id}\", now),\n"
    "        )\n"
)
if "# [KILIT-FIX]" not in src or src.count(anchor) != 1:
    sys.exit("HATA: Once patch_session_lock.py uygulanmali (ya da dosya beklenenden farkli). Duruyorum.")

block = anchor + (
    "\n"
    "        # [ISIM-FIX] Auth DB'deki gercek kullanici adi / takma ad / sirket bilgisini oyun DB'sine aktar.\n"
    "        try:\n"
    "            _auth_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), \"novagate_auth.db\")\n"
    "            _a = sqlite3.connect(\"file:\" + _auth_path + \"?mode=ro\", uri=True, timeout=5.0)\n"
    "            try:\n"
    "                _r = _a.execute(\n"
    "                    \"SELECT username, callsign, faction FROM accounts WHERE id = ?\", (account_id,)\n"
    "                ).fetchone()\n"
    "            finally:\n"
    "                _a.close()\n"
    "            if _r:\n"
    "                conn.execute(\n"
    "                    \"UPDATE accounts SET username = ?, callsign = ?, faction = ? WHERE id = ?\",\n"
    "                    (_r[0], _r[1], int(_r[2]), account_id),\n"
    "                )\n"
    "        except Exception as _e:\n"
    "            log.warning(\"auth bilgisi senkronlanamadi (account_id=%s): %s\", account_id, _e)\n"
)

bak = DB_PY + ".isim_oncesi_yedek"
if not os.path.exists(bak):
    shutil.copy2(DB_PY, bak)
    print("yedek:", bak)
with open(DB_PY, "w", encoding="utf-8", newline="") as f:
    f.write(src.replace(anchor, block))
print("Uygulandi. novagate-db ve novagate-server yeniden baslatilmali.")
