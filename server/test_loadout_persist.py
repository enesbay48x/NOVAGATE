"""Gemi + ekipman kalicilik testi (gecici sqlite). Calistir: python3 test_loadout_persist.py"""
import os, sys, tempfile, json
tmp = tempfile.mkdtemp()
os.environ["NOVAGATE_DB_PATH"] = os.path.join(tmp, "t.db")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server_db as db

db.init_db()
conn = db.get_db()
conn.execute("INSERT INTO accounts (id, username, password_hash, faction, callsign, created_at) VALUES (1,'a','x',1,'A',0)")
conn.close()
fails = 0
def check(name, cond):
    global fails
    print(("OK   " if cond else "FAIL ") + name)
    if not cond: fails += 1

# 1) yeni oyuncu: Phoenix verilir
st = db.load_player_state(1)
check("yeni oyuncu aktif gemi = phoenix", st["ship"] == "phoenix" and st["owned"] == ["phoenix"])

# envanter + ikinci gemi (satin alma sonucu gibi)
conn = db.get_db()
conn.execute("INSERT INTO player_ships VALUES (1,'yamato',0)")
for it, q in (("lf2", 4), ("lf1", 2), ("g3n-3310", 2), ("sg3n-a02", 1), ("iris", 1)):
    conn.execute("INSERT OR REPLACE INTO inventory (account_id,item_id,quantity) VALUES (1,?,?)", (it, q))
conn.close()

# 2) aktif gemi kaydi
check("sahip olunmayan gemi reddedilir", not db.save_active_ship(1, "goliath")["ok"])
check("yamato kaydedilir", db.save_active_ship(1, "yamato")["ok"])
st = db.load_player_state(1)
check("giriste yamato yuklenir (Phoenix degil)", st["ship"] == "yamato")

# 3) ekipman kaydi + sunucu dogrulamasi
cfg0 = {"las": ["lf2", "lf2", "lf2"], "gen": ["g3n-3310", "sg3n-a02", "yok"], "drn": ["iris", "iris"], "form": "ar", "drone_equip": {"iris_0": {"slot_0": "lf1", "slot_1": "yamato"}}}
cfg1 = {"las": ["lf1"], "gen": [], "drn": [], "form": "hack", "drone_equip": {}}
r = db.save_loadout(1, "yamato", [cfg0, cfg1], 1)
check("save_loadout ok", r["ok"])
c0, c1 = r["loads"]
check("yuva siniri: yamato 2 lazer", c0["las"] == ["lf2", "lf2"])
check("bilinmeyen jenerator atilir", c0["gen"] == ["g3n-3310", "sg3n-a02"])
check("envanterdeki 1 droid kadar droid", c0["drn"] == ["iris"] and c1["drn"] == ["iris"])
check("droid slotunda gecersiz esya atilir", c0["drone_equip"] == {"iris_0": {"slot_0": "lf1"}})
check("gecersiz formasyon std olur", c1["form"] == "std" and c0["form"] == "ar")
check("sahip olunmayan gemiye kayit reddedilir", not db.save_loadout(1, "goliath", [cfg0], 0)["ok"])
check("bilinmeyen gemi reddedilir", not db.save_loadout(1, "xyz", [cfg0], 0)["ok"])

st = db.load_player_state(1)
check("giriste yamato ekipmani geri yuklenir", st["loads"]["yamato"][0]["las"] == ["lf2", "lf2"] and st["cfg_index"] == 1)

# 4) cikarma da kaydedilir
cfg0["las"] = ["lf2"]
db.save_loadout(1, "yamato", [cfg0, cfg1], 0)
st = db.load_player_state(1)
check("cikarilan lazer kaydedildi", st["loads"]["yamato"][0]["las"] == ["lf2"] and st["cfg_index"] == 0)

# 5) mühimmat
check("muhimmat kaydi", db.save_selected_ammo(1, "x2")["ok"] and db.load_player_state(1)["selected_ammo"] == "x2")
check("gecersiz muhimmat reddedilir", not db.save_selected_ammo(1, "zzz")["ok"])

# 6) aktif gemi artik hesapta degilse Phoenix'e doner
conn = db.get_db(); conn.execute("DELETE FROM player_ships WHERE ship_id='yamato'"); conn.close()
check("gemi kaybolursa phoenix", db.load_player_state(1)["ship"] == "phoenix")
print("\nSONUC:", "HEPSI GECTI" if not fails else "%d HATA" % fails)
sys.exit(1 if fails else 0)
