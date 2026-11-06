# Galaxy Gate DB testi (python3 test_gate_db.py): parca yuvalari, tekrarlanan parca -> carpan x2..x6,
# carpan kullanimi, fazla parca -> cephane, aktivasyon, ilerleme, bitis/yeniden insa.
import os, sys, tempfile, random
d = tempfile.mkdtemp()
os.environ["NOVAGATE_DB_PATH"] = os.path.join(d, "t.db")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server_db as db
db.init_db()
r = db.create_account("tester", "a" * 64, 1, "Tester", {})
aid = int(r.get("account_id", 0)) or int(db.get_account_id_by_username("tester"))
ok = True
def check(name, cond, got=None):
    global ok
    print(("PASS " if cond else "FAIL ") + name, "" if cond else got)
    ok = ok and cond
def set_uri(n):
    c = db.get_db()
    c.execute("UPDATE player_data SET uri = ? WHERE account_id = ?", (n, aid)); c.close()
def uri():
    c = db.get_db(); v = c.execute("SELECT uri FROM player_data WHERE account_id = ?", (aid,)).fetchone()[0]; c.close(); return v
def force_roll(kind):
    db._gate_roll_reward = lambda: kind
n = [0]
def pulse():
    n[0] += 1
    return db.gate_generator_pulse(aid, "t%d" % n[0])

i = db.gate_info(aid)
check("bos bilgi", i["ok"] and i["gen"] == {"mult": 0, "armed": False} and all(i["gates"][g]["parts"] == 0 for g in db.GATE_IDS), i)
check("odul tablosu toplam 100", sum(p for _, p in db.GATE_GEN_TABLE) == 100)
check("gerekli parcalar 34/48/82", db.GATE_PARTS_REQUIRED == {"alpha": 34, "beta": 48, "gamma": 82})

# --- uridium ---
set_uri(99)
check("99 uridium ile basim reddedilir", pulse().get("error") == "yetersiz_uridium")
set_uri(250); force_roll("ammo")
r = pulse()
check("basim 100 uridium duser", r["ok"] and r["new_uri"] == 150 and uri() == 150, (r, uri()))
r2 = db.gate_generator_pulse(aid, "t%d" % n[0])
check("ayni tx_id tekrar odul/dusum yapmaz", uri() == 150 and r2.get("duplicate_tx"), (r2, uri()))
check("cephane odulu yazildi", r["reward_type"] == "ammo" and r["reward_amount"] > 0)

# --- parca: yuva bazli ---
set_uri(100000); force_roll("part")
random.seed(1)
for _ in range(400):
    r = pulse()
    assert r["ok"], r
i = db.gate_info(aid)
check("400 parca sonrasi her kapi tamamlandi (34/48/82)",
      [i["gates"][g]["parts"] for g in db.GATE_IDS] == [34, 48, 82], i["gates"])
check("yuvalar benzersiz ve aralikta", all(len(set(i["gates"][g]["slots"])) == db.GATE_PARTS_REQUIRED[g] for g in db.GATE_IDS))
check("tekrarlanan parcalar carpan biriktirdi", i["gen"]["mult"] >= 2, i["gen"])

# --- carpan x2..x6 sirasi (temiz hesap uzerinde) ---
db.gate_finish(aid, "alpha", True); db.gate_finish(aid, "beta", True); db.gate_finish(aid, "gamma", True)
c = db.get_db(); c.execute("DELETE FROM player_gate_gen WHERE account_id = ?", (aid,)); c.close()
# tum yuvalari doldur, sonra her parca tekrar olur
c = db.get_db()
for g in db.GATE_IDS:
    for s in range(db.GATE_PARTS_REQUIRED[g]):
        c.execute("INSERT OR IGNORE INTO player_gate_slots(account_id,gate_id,slot) VALUES(?,?,?)", (aid, g, s))
c.close()
seen = []
for _ in range(5):
    r = pulse(); seen.append(r["gen"]["mult"]); assert r["duplicate"], r
check("tekrar parca: x2,x3,x4,x5,x6", seen == [2, 3, 4, 5, 6], seen)
check("x6 sonrasi arm", db.gate_generator_arm(aid, True)["ok"] and db.gate_info(aid)["gen"] == {"mult": 6, "armed": True})
db.gate_generator_arm(aid, False)
r = pulse()
check("x6 doluyken tekrar parca: otomatik kullanilir ve sifirlanir",
      r["auto_used"] and r["mult_used"] == 6 and r["gen"] == {"mult": 0, "armed": False}, r)
check("kapi tam doluyken carpanli parca cephaneye cevrilir",
      r["reward_detail"]["part"]["granted"] == 0 and r["reward_detail"]["part"]["surplus"] == 6, r["reward_detail"])

# --- carpan kullanimi: ammo x katlanir, sonra sifirlanir ---
check("carpan yokken arm reddedilir", db.gate_generator_arm(aid, True).get("error") == "carpan_yok")
force_roll("part"); pulse(); pulse()          # x2, x3
check("2 tekrar -> x3", db.gate_info(aid)["gen"]["mult"] == 3)
db.gate_generator_arm(aid, True)
force_roll("xenomit")
r = pulse()
check("isaretli x3 xenomiti katlar (25*3)", r["reward_amount"] == db.GATE_GEN_XENOMIT * 3 and r["mult_used"] == 3, r)
check("kullanilan carpan sifirlandi", r["gen"] == {"mult": 0, "armed": False}, r["gen"])

# --- eksik yuvaya carpanli parca ---
c = db.get_db(); c.execute("DELETE FROM player_gate_slots WHERE account_id=? AND gate_id='gamma'", (aid,))
c.execute("UPDATE player_gate_parts SET parts = 0 WHERE account_id=? AND gate_id='gamma'", (aid,)); c.close()
c = db.get_db(); c.execute("INSERT INTO player_gate_gen(account_id,mult,armed,spins,updated_at) VALUES(?,?,1,0,0) ON CONFLICT(account_id) DO UPDATE SET mult=4, armed=1", (aid, 4)); c.close()
orig_choice = random.choice
random.choice = lambda seq: "gamma" if "gamma" in seq else orig_choice(seq)
force_roll("part")
r = pulse()
random.choice = orig_choice
p = r["reward_detail"]["part"]
check("carpanli parca: kapiya 4 parca yazildi", p["gate"] == "gamma" and p["granted"] == 4 and len(p["slots"]) == 4, p)
gi = db.gate_info(aid)["gates"]["gamma"]
check("parca sayisi guncel", gi["parts"] == 4, gi)

# --- diger oduller ---
set_uri(1000)
for kind, exp in (("nano_hull", "nano_hull"), ("repair_coupon", "repair_coupon"), ("logdisk", "logdisk")):
    force_roll(kind); r = pulse()
    check("odul: " + kind, r["ok"] and r["reward_type"] == exp and r["reward_amount"] == 1, r)

# --- aktivasyon ---
db.gate_finish(aid, "alpha", True)
check("eksik parcayla aktivasyon reddedilir", db.gate_activate(aid, "alpha", 34).get("error") == "parca_eksik")
c = db.get_db()
for s in range(34):
    c.execute("INSERT OR IGNORE INTO player_gate_slots(account_id,gate_id,slot) VALUES(?,?,?)", (aid, "alpha", s))
c.close()
check("tamamlaninca aktivasyon", db.gate_activate(aid, "alpha", 34)["ok"])
check("ikinci aktivasyon reddedilir", db.gate_activate(aid, "alpha", 34).get("error") == "zaten_aktif")
check("aktif olmayan kapida ilerleme yazilmaz", db.gate_save_progress(aid, "beta", 1, 1, 1).get("error") == "kapi_aktif_degil")
check("ilerleme yaz", db.gate_save_progress(aid, "alpha", 3, 2, 7)["ok"])
i = db.gate_info(aid)
check("ilerleme okunur", i["progress"]["alpha"] == {"section": 3, "grp": 2, "grp_killed": 7}, i["progress"])
check("kapi aktif okunur", i["gates"]["alpha"]["active"] and i["gates"]["alpha"]["parts"] == 34, i["gates"]["alpha"])
check("bitir+yeniden-insa", db.gate_finish(aid, "alpha", True)["ok"])
i = db.gate_info(aid)
check("bitince parca sifir, kapali, ilerleme yok",
      i["gates"]["alpha"]["parts"] == 0 and not i["gates"]["alpha"]["active"] and "alpha" not in i["progress"], i)

# --- NPC ile parca YOK ---
check("gate_add_part artik yok (NPC parcasi kaldirildi)", not hasattr(db, "gate_add_part"))

# --- eski sayac tabanli parcalar korunur ---
c = db.get_db()
c.execute("DELETE FROM player_gate_slots WHERE account_id=? AND gate_id='beta'", (aid,))
c.execute("INSERT INTO player_gate_parts(account_id,gate_id,parts,active,updated_at) VALUES(?,?,?,0,0) "
          "ON CONFLICT(account_id,gate_id) DO UPDATE SET parts=excluded.parts", (aid, "beta", 20)); c.close()
gi = db.gate_info(aid)["gates"]["beta"]
check("eski sayac -> yuvalar", gi["parts"] == 20 and gi["slots"] == list(range(20)), gi)
print("\nSONUC:", "HEPSI GECTI" if ok else "HATA VAR")
sys.exit(0 if ok else 1)
