"""Tamir (500 uridyum, Phoenix bedava), nick ve sirket degistirme testi (gecici sqlite).
Calistir: python3 test_repair_account.py"""
import os, sys, tempfile, sqlite3, time
tmp = tempfile.mkdtemp()
os.environ["NOVAGATE_DB_PATH"] = os.path.join(tmp, "game.db")
os.environ["NOVAGATE_AUTH_DB_PATH"] = os.path.join(tmp, "auth.db")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server_db as db

db.init_db()
a = sqlite3.connect(os.environ["NOVAGATE_AUTH_DB_PATH"])
a.executescript("""CREATE TABLE accounts (id INTEGER PRIMARY KEY, username TEXT, password_hash TEXT,
  faction INTEGER, callsign TEXT, created_at INTEGER);
  INSERT INTO accounts VALUES (1,'ali','x',1,'ali',0),(2,'veli','x',2,'veli',0);""")
a.commit(); a.close()
g = db.get_db()
for i, (u, f) in enumerate((("ali", 1), ("veli", 2)), 1):
    g.execute("INSERT INTO accounts (id, username, password_hash, faction, callsign, created_at) VALUES (?,?,'x',?,?,0)", (i, u, f, u))
g.close()
db.load_player_state(1); db.load_player_state(2)
fails = 0
def check(name, cond):
    global fails
    print(("OK   " if cond else "FAIL ") + name)
    if not cond: fails += 1
def uri(i):
    c = db.get_db(); v = c.execute("SELECT uri FROM player_data WHERE account_id=?", (i,)).fetchone()[0]; c.close(); return v
def seturi(i, v):
    c = db.get_db(); c.execute("UPDATE player_data SET uri=? WHERE account_id=?", (v, i)); c.close()

# --- Phoenix: bedava
seturi(1, 0)
r = db.repair_ship(1, "t1")
check("Phoenix tamiri ucretsiz (uri 0 iken bile)", r["ok"] and r["cost"] == 0 and uri(1) == 0)
# --- diger gemi: 500
c = db.get_db(); c.execute("INSERT INTO player_ships VALUES (1,'yamato',0)"); c.close()
check("yamato aktif", db.save_active_ship(1, "yamato")["ok"])
r = db.repair_ship(1, "t2")
check("yamato, 0 uridyum: yetersiz bakiye", not r["ok"] and r["error"] == "insufficient_funds" and uri(1) == 0)
seturi(1, 1200)
r = db.repair_ship(1, "t3")
check("yamato tamiri tam 500 uridyum", r["ok"] and r["cost"] == 500 and uri(1) == 700 and r["new_uri"] == 700)
r2 = db.repair_ship(1, "t3")
check("ayni tx_id ikinci kez TAHSIL EDILMEZ", r2["ok"] and uri(1) == 700)
db.repair_ship(1, "t4")
check("yeni tx_id tekrar 500 dusurur", uri(1) == 200)
# --- enkaz kaliciligi
db.set_wrecked(1, True)
check("enkaz durumu yuklenir", db.load_player_state(1)["wrecked"] == 1)
seturi(1, 500)
db.repair_ship(1, "t5")
check("tamir enkazi temizler", db.load_player_state(1)["wrecked"] == 0 and uri(1) == 0)
# --- nick
check("kisa isim reddedilir", db.change_callsign(1, "ab")["error"] == "gecersiz_isim")
check("bosluklu isim reddedilir", db.change_callsign(1, "a b c")["error"] == "gecersiz_isim")
check("baskasinin ismi reddedilir", db.change_callsign(1, "VELI")["error"] == "isim_kullanimda")
r = db.change_callsign(1, "Kaptan_01")
check("nick degisti", r["ok"] and r["callsign"] == "Kaptan_01")
check("oyun DB'sinde de guncel", db.load_player_state(1)["callsign"] == "Kaptan_01")
check("nick 24 saat bekleme", db.change_callsign(1, "Baska_Ad")["error"] == "bekleme")
# --- sirket
check("gecersiz sirket", db.change_faction(1, 9)["error"] == "gecersiz_sirket")
check("ayni sirket", db.change_faction(1, 1)["error"] == "ayni_sirket")
c = db.get_db(); c.execute("UPDATE player_data SET map_name='1-3', px=55, pz=66 WHERE account_id=1"); c.close()
r = db.change_faction(1, 3)
st = db.load_player_state(1)
check("sirket degisti + yeni ev haritasi", r["ok"] and st["faction"] == 3 and st["map"] == "3-1" and st["px"] == 0.0)
check("sirket 7 gun bekleme", db.change_faction(1, 2)["error"] == "bekleme")
print("HEPSI GECTI" if not fails else "%d HATA" % fails)
sys.exit(1 if fails else 0)
