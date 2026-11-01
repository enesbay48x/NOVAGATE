extends SceneTree
# Headless hizli test: DarkOrbit lazer atis sistemi (test_lazer.gd)
# Calistirma: godot --headless --path . --script res://test_lazer.gd
# Kapsam: laserpoint cikis noktalari, atis/isin sayisi, muhimmat hasari, SAB emme, RSB beklemesi.

var fails := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	_run()


func _cfg(las: Array) -> Dictionary:
	# sg3n-a01: kalkan jeneratoru (max_sh > 0 olsun ki SAB emme testine esit olsun)
	return {"las": las, "gen": ["sg3n-a01"], "drn": [], "form": "std", "drone_equip": {}}


func _mk_enemy(M, world: Node3D, id: String, model: String, shield: float) -> Dictionary:
	var n: Node3D = M.make_ship(model, 6.0, Color(1.0, 0.6, 0.6))
	world.add_child(n)
	n.position = Vector3(0, 0, 24)
	return {"node": n, "id": id, "name": id, "hp": 500000.0, "mx": 500000.0,
		"sh": shield, "msh": shield, "aggro": false, "d": {"xp": 0, "cr": 0, "hon": 0, "uri": 0, "resp": 0}}


func _set_load(M, las: Array) -> void:
	M.SV["loads"] = {"goliath": [_cfg(las)]}


func _wait_bolts(M, want: int, ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and M.bullets.size() < want:
		await process_frame


func _hit_one(M, e, am: String, dmg: float) -> void:
	var vol := {"left": 1, "sh": 0.0, "hull": 0.0, "am": am, "flash": false, "pos": e.node.position}
	M._bolt_hit({"node": null, "tgt": e, "kind": "lf1", "col": Color.RED, "dmg": dmg, "vol": vol, "spd": 90.0, "t": 2.5, "last": e.node.position, "hr": 3.0, "gen": 0})


func _run() -> void:
	var M = load("res://main.gd").new()
	var world := Node3D.new()
	root.add_child(world)
	M.world = world
	M.running = true

	# oyuncu gemisi (goliath)
	var ship: Node3D = M.make_ship("goliath", 8.0, Color(1, 1, 1))
	world.add_child(ship)
	ship.position = Vector3.ZERO
	M.P = {"node": ship, "sh": 1000.0, "hp": 2000.0, "cd": 0.0}
	M.SV = {"ship": "goliath", "loads": {}, "cfgi": 0, "skills": {}, "sel": "x1",
		"ammo": {"x1": 99999, "x2": 99999, "x3": 99999, "x4": 99999, "sab": 99999, "rsb": 99999},
		"rockets": 50}
	_set_load(M, ["lf1"])

	await process_frame

	# --- 1) Gercek lazer cikis noktalari
	var lpts: Array = ship.get_meta("lpts", [])
	_check(lpts.size() >= 5, "goliath modelinde %d laserpoint node'u bulundu (>=5 beklenir)" % lpts.size())
	var dir := Vector3(0, 0, 1)
	var hps: Array = M._hp_origins(ship, dir)
	_check(not hps.is_empty(), "_hp_origins sonuc bos degil")
	var okNear := true
	for hp in hps:
		if Vector3(hp["p"]).distance_to(ship.position) > 4.6:
			okNear = false
	_check(okNear, "tum cikis noktalari gemi govdesinde (yaricap <= 4.6)")

	# --- 2) 5 lazer = 5 isin; isinlar gercek laserpoint'lerden cikar
	_set_load(M, ["lf1", "lf2", "lf3", "lf4", "lf1"])
	var e1 := _mk_enemy(M, world, "streuner", "streuner", 50000.0)
	M.target = e1
	M.player_volley(ship.position)
	await _wait_bolts(M, 5, 5000)
	_check(M.bullets.size() == 5, "5 lazerle salvoda %d isin (beklenen 5)" % M.bullets.size())
	var allHp := true
	for b in M.bullets:
		var mind := 99.0
		for lpt in lpts:
			mind = minf(mind, lpt.global_position.distance_to(Vector3(b.node.position)))
		if mind > 0.75:
			allHp = false
	_check(allHp, "her isin gercek bir laserpoint'ten cikiyor (sapma <= 0.75)")
	M.bullets.clear()

	# --- 3) muhimmat hasar davranisi
	var e2 := _mk_enemy(M, world, "streuner", "streuner", 100000.0)
	e2.sh = 100000.0
	var sh0: float = e2.sh
	var hp0: float = e2.hp
	_hit_one(M, e2, "x4", 100.0)
	_check(absf((sh0 - e2.sh) - 80.0) < 0.01 and absf((hp0 - e2.hp) - 20.0) < 0.01,
		"X4: isabetin %%80'i kalkana(-80), kalan govdeye(-20) (carpan 4)")
	hp0 = e2.hp
	e2.sh = 20.0
	_hit_one(M, e2, "x2", 100.0)
	_check(absf((hp0 - e2.hp) - 80.0) < 0.01, "X2: kalkan yetmadigindan hasarin kalani govdeye (-80)")
	e2.sh = 100000.0

	# --- 4) SAB: sadece kalkan emer, govde hasari YOK, enerji oyuncuya
	_set_load(M, ["lf1", "lf1", "lf1", "lf1", "lf1"])
	M.SV["sel"] = "sab"
	M.target = e2
	M.P["sh"] = 300.0
	M.bullets.clear()
	var eh0: float = e2.hp
	e2.sh = 3000.0
	var esh0: float = e2.sh
	M.player_volley(ship.position)
	await _wait_bolts(M, 5, 5000)
	for b in M.bullets:
		b["last"] = e2.node.position
		b["gen"] = 0
		M._bolt_hit(b)
	var shGain: float = M.P.sh - 300.0
	_check(M.P.sh <= M.max_sh(), "SAB: oyuncu kalkani azamiyi asmiyor")
	_check(shGain > 0.0 and shGain < 1000.0, "SAB: emilen enerji oyuncu kalkanina gecti (+%s, 5x40x2.0x0.88-1.12)" % M._n(shGain))
	_check(absf(e2.hp - eh0) < 0.01, "SAB: govde hasari verilmedi (hasar=%s)" % M._n(absf(e2.hp - eh0)))
	_check(esh0 - e2.sh > 0.0, "SAB: hedefin kalkani azaldi")
	# kalkani bitmis hedefte emme OLMAMALI
	M.P["sh"] = 100.0
	e2.sh = 0.0
	M.bullets.clear()
	var follo: float = e2.hp
	_hit_one(M, e2, "sab", 100.0)
	_check(absf(M.P.sh - 100.0) < 0.01 and absf(e2.hp - follo) < 0.01, "SAB: hedefin kalkani bitiksa emme yok, govde hasari yok")

	# --- 5) RSB: atis sonrasi bekleme (KESINLIKLE 3 sn); beklemede salvo X1'e duser
	M.select_ammo("rsb")
	M.rsb_cd = 0.0
	M.bullets.clear()
	M.player_volley(ship.position)
	var rsb_cd_after: float = M.rsb_cd
	_check(rsb_cd_after == M.RSB_COOLDOWN, "RSB atisi sonrasi bekleme=%s sn (beklenen %s)" % [str(rsb_cd_after), str(M.RSB_COOLDOWN)])
	_check(M.RSB_COOLDOWN == 3.0, "RSB bekleme sabiti kesinlikle 3.0 sn")
	var rsb_a: int = int(M.SV.ammo["rsb"])
	var x1_a: int = int(M.SV.ammo["x1"])
	await _wait_bolts(M, 5, 5000)
	M.bullets.clear()
	M.rsb_cd = 3.0  # bekleme halen suruyor
	M.player_volley(ship.position)
	_check(int(M.SV.ammo["rsb"]) == rsb_a, "RSB beklerken RSB cephanesi harcanmadi")
	_check(int(M.SV.ammo["x1"]) == x1_a - 5, "RSB beklerken salvo X1 ile atildi (X1 stogu 5 azaldi)")

	# --- 6) 10 lazer = 10 isin
	_set_load(M, ["lf1", "lf2", "lf3", "lf4", "lf1", "lf2", "lf3", "lf4", "lf1", "lf2"])
	M.SV["sel"] = "x1"
	M.rsb_cd = 0.0
	M.bullets.clear()
	M.target = e1
	M.player_volley(ship.position)
	await _wait_bolts(M, 10, 5000)
	_check(M.bullets.size() == 10, "10 lazerle salvoda %d isin (beklenen 10)" % M.bullets.size())

	# --- 7) rocket ve NPC atisi fire_bolt cagrilari bozulmali degil
	M.bullets.clear()
	M._npc_bolt({"node": e1.node, "hp": 100.0, "id": "streuner"}, 0, 10.0, 0)
	_check(M.bullets.size() == 1, "NPC atisi calisiyor (_npc_bolt)")

	# --- 8) PARALEL ucus: 4 lazer ayni anda, ayri cikis + ayri bitis, yan yana
	_set_load(M, ["lf1", "lf1", "lf1", "lf1"])
	M.SV["sel"] = "x1"
	M.rsb_cd = 0.0
	M.bullets.clear()
	M.target = e1
	M.player_volley(ship.position)
	await _wait_bolts(M, 4, 3000)
	_check(M.bullets.size() == 4, "4 lazer salvo ayni anda: %d isin (beklenen 4)" % M.bullets.size())
	_check(is_equal_approx(M.LASER_INTERVAL, 0.60) and is_equal_approx(DOData.PLAYER_FIRE_INTERVAL, 0.60), "oyuncu salvo araligi = %s sn (beklenen 0.60)" % str(M.LASER_INTERVAL))
	_check(is_equal_approx(DOData.NPC_FIRE_INTERVAL, 0.90), "NPC atis araligi = %s sn (beklenen 0.90)" % str(DOData.NPC_FIRE_INTERVAL))
	# isinlara ozel bitis ofsetleri birbirinden farkli olmali (yan yana isabet)
	var offs: Array = []
	var offUniq := true
	var startUniq := true
	for bb in M.bullets:
		offs.append(Vector3(bb.get("off", Vector3.ZERO)))
	for a2 in offs.size():
		for c2 in range(a2 + 1, offs.size()):
			if Vector3(offs[a2]).distance_to(Vector3(offs[c2])) < 0.9:
				offUniq = false
	for sa in M.bullets:
		for sb in M.bullets:
			if sa != sb and Vector3(sa.node.position).distance_to(Vector3(sb.node.position)) < 0.15:
				startUniq = false
	_check(offUniq, "isin bitis (isabet) ofsetleri birbirinden ayri (mesafe > 0.9)")
	_check(startUniq, "isinlar farkli cikis noktalarindan gidiyor (aynı koordinattan cikmiyor)")
	_check(offs.size() == M.bullets.size(), "her isina ozel ofset hesaplandi")
	# hedef degistiginde(eski isinlar eski hedefe gidebilir): hedef degisimi sonrasi yonlenme kontrolu
	var tOld = M.target
	var changed := true
	for bb in M.bullets:
		if bb.tgt != tOld:
			changed = false
	_check(changed, "isinlar atildiklari salvo hedefine kilitli (b.tgt atis anindaki hedef)")
	# muhimmat sprite'lari hazir
	_check(M._laser_sprite("x1", 0.9) != null and M._laser_sprite("x2", 1.0) != null
		and M._laser_sprite("x3", 1.1) != null and M._laser_sprite("x4", 1.3) != null
		and M._laser_sprite("sab", 1.15) != null and M._laser_sprite("rsb", 1.55) != null,
		"tum muhimmat lazer sprite'lari yukleniyor (x1/x2/x3/x4/sab/rsb)")

	# --- 9) RSB OTOMATIK GERI DONUS (select_ammo merkezi uzerinden)
	_set_load(M, ["lf1", "lf1", "lf1", "lf1"])
	M.rsb_cd = 0.0
	M.rsb_prev = ""
	M.bullets.clear()
	M.target = e1
	M.select_ammo("x4")
	_check(M.rsb_prev == "x4" and str(M.SV.sel) == "x4", "manuel X4 secimi: onceki muhimmat (rsb_prev='x4') kaydedildi")
	var rsb_b: int = int(M.SV.ammo["rsb"])
	M.select_ammo("rsb")
	_check(str(M.SV.sel) == "rsb", "RSB secildi (bekleme yok, cephanesi var)")
	M.player_volley(ship.position)
	await _wait_bolts(M, 4, 3000)
	_check(M.rsb_cd == M.RSB_COOLDOWN and M.RSB_COOLDOWN == 3.0, "RSB salvo sonrasi bekleme kesinlikle 3.0 sn basladi")
	_check(str(M.SV.sel) == "x4", "RSB salvo sonrasi OTOMATIK X4'e donuldu (manuel secim gerekmiyor)")
	await _wait_bolts(M, 0, 2500)   # salvonun havadan inmesini bekle (cift atis kontrolu icin)
	_check(int(M.SV.ammo["rsb"]) == rsb_b - 4, "RSB cephanesi yalnizca 1 salvo kadar dustu (4) - sonsuz/ceft atis yok")
	# beklemede RSB secilemez; secim degismez, cephaneyi harcamaz
	M.select_ammo("rsb")
	_check(str(M.SV.sel) == "x4", "RSB beklerken RSB tekrar secilemedi (secim X4'te kaliyor)")
	# beklemeyi manuel secimle ezmek: oyuncu X2'yi secerse otomatik donus X2'ye olur (ezilmez)
	M.rsb_cd = 3.0
	M.select_ammo("x2")
	_check(M.rsb_prev == "x2" and str(M.SV.sel) == "x2", "bekleme sirasinda manuel X2 secildi: rsb_prev X2'ye guncellendi")
	M.rsb_cd = 0.0
	M.bullets.clear()
	M.select_ammo("rsb")
	M.player_volley(ship.position)
	_check(str(M.SV.sel) == "x2", "ikinci RSB atisi sonrasi otomatik X2'ye donuldu (oyuncunun yeni secimi ezilmedi)")
	M.bullets.clear()

	print("=== SONUC: %d hata ===" % fails)
	quit(1 if fails > 0 else 0)
