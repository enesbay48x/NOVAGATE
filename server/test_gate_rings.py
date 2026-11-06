# Halka (ilk kapi bitirme) ve siralama verisi testi: python3 test_gate_rings.py
import os, sys, tempfile
d = tempfile.mkdtemp()
os.environ["NOVAGATE_DB_PATH"] = os.path.join(d, "t.db")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server_db as db
db.init_db()
ok = True
def check(name, cond, got=None):
    global ok
    print(("PASS " if cond else "FAIL ") + name, "" if cond else got)
    ok = ok and cond
def mk(name, fac):
    r = db.create_account(name, "a" * 64, fac, name, {})
    return int(r.get("account_id", 0)) or int(db.get_account_id_by_username(name))
a = mk("ali", 1); b = mk("veli", 1); c = mk("can", 2)

r = db.gate_finish(a, "alpha", True)
check("ilk bitiren halka alir", r["ok"] and r["first"] and r["rings"] == 1, r)
r = db.gate_finish(b, "alpha", True)
check("ikinci bitiren halka ALMAZ", r["ok"] and not r["first"] and r["rings"] == 0, r)
r = db.gate_finish(a, "alpha", True)
check("ayni kapiyi tekrar bitirmek halka eklemez", not r["first"] and r["rings"] == 1, r)
db.gate_finish(a, "beta", True); r = db.gate_finish(a, "gamma", True)
check("3 kapi = 3 halka", r["first"] and r["rings"] == 3, r)
check("en fazla 3 halka", db.gate_rings_of(a) == 3)
check("gecersiz kapi reddedilir", db.gate_finish(a, "zeta", True).get("error") == "gecersiz_kapi")
check("load_player_state halka doner", db.load_player_state(a)["gate_rings"] == 3)

# admin halka almaz
conn = db.get_db(); conn.execute("UPDATE accounts SET is_admin = 1 WHERE id = ?", (c,)); conn.close()
conn = db.get_db(); conn.execute("DELETE FROM gate_first_clear"); conn.close()
r = db.gate_finish(c, "alpha", True)
check("admin halka almaz", r["ok"] and not r["first"], r)

# sirket bazli mod
db.GATE_RING_PER_COMPANY = True
conn = db.get_db(); conn.execute("UPDATE accounts SET is_admin = 0 WHERE id = ?", (c,)); conn.close()
r1 = db.gate_finish(a, "alpha", True); r2 = db.gate_finish(c, "alpha", True)
check("sirket modunda her sirketin ilki halka alir", r1["first"] and r2["first"], (r1, r2))
db.GATE_RING_PER_COMPANY = False

# siralama satirlari
rows = db.rank_rows()
check("rank_rows tum hesaplari doner", rows["ok"] and len(rows["rows"]) == 3, rows)
ra = [x for x in rows["rows"] if x["account_id"] == a][0]
check("rank_rows halka sayisini icerir", ra["rings"] == 1 and ra["faction"] == 1, ra)
print("SONUC:", "HEPSI GECTI" if ok else "HATA VAR")
sys.exit(0 if ok else 1)
