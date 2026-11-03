extends SceneTree
# NOVAGATE odul kalicilik entegrasyon testi.
# Calistirmadan once server_db.py ayni makinede 127.0.0.1:54321'de acik olmalidir.
# Test gecici DB kopyasina yazar; mevcut oyuncu verilerine dokunmaz.


func _fail(msg: String) -> void:
	print("[FAIL] ", msg)
	quit(1)


func _init() -> void:
	# NetServer yalnizca RPC gondermek icin net.callv("rpc_id", ...) kullanir.
	# Testte gercek Node yeterlidir; gonderimler testin dogrulamasini etkilemez.
	var fake := Node.new()
	var srv = load("res://net_server.gd").new(fake)
	if not srv.db_connected:
		_fail("server_db baglantisi yok")
		return

	var uname: String = "reward_it_%d" % int(Time.get_unix_time_from_system())
	var cr: Dictionary = srv.db_send("create_account", {
		"username": uname,
		"password_hash": "test",
		"faction": 1,
		"callsign": uname,
		"item_price_data": {"start_inventory": {"lf2": 15}, "start_ammo": {"x1": 100}},
	})
	if not cr.has("ok") or not cr["ok"]:
		_fail("test hesabi olusturulamadi: %s" % str(cr))
		return
	var aid: int = int(cr["account_id"])
	var ps: Dictionary = srv.db_send("load_player_state", {"account_id": aid}).get("player_state", {})
	if ps.is_empty():
		_fail("baslangic durumu yuklenemedi")
		return
	print("[OK] Test hesabi: account_id=%d cr=%d uri=%d" % [aid, int(ps.cr), int(ps.uri)])

	var pid: int = 1
	var pos := Vector3(10000.0, 0.0, 10000.0)
	srv.players[pid] = {
		"id": pid, "account_id": aid, "name": uname, "faction": 1, "ship": "phoenix",
		"map": "1-1", "pos": pos, "group": 0,
		"_sv_cr": int(ps.cr), "_sv_uri": int(ps.uri), "_sv_xp": float(ps.xp),
		"_sv_hon": float(ps.hon), "_sv_sep": int(ps.get("sep", 0)),
		"_sv_kills": int(ps.kills), "_sv_pvp_kills": int(ps.pvp_kills),
	}
	var w: Dictionary = srv._get_world("1-1")

	# --- 1) Bonus kutusu: sunucu odulu DB'ye yazmali, ayni kutu tekrar odul vermemeli
	var box_ids: Array = (w.boxes as Dictionary).keys()
	if box_ids.is_empty():
		_fail("haritada kutu yok")
		return
	var bid: int = int(box_ids[0])
	(w.boxes as Dictionary)[bid] = pos
	var before: Dictionary = _db_state(srv, aid)
	srv.on_box_take(pid, bid)
	var after: Dictionary = _db_state(srv, aid)
	var box_gain: int = (int(after.cr) - int(before.cr)) + (int(after.uri) - int(before.uri)) \
		+ (int(after.ammo.get("x1", 0)) - int(before.ammo.get("x1", 0)))
	if box_gain <= 0:
		_fail("kutu odulu DB'ye yazilmadi (cr/uri/ammo degismedi)")
		return
	if (w.boxes as Dictionary).has(bid):
		_fail("alinan kutu sunucu dunyasindan silinmedi")
		return
	var cr_after_first: int = int(after.cr)
	var uri_after_first: int = int(after.uri)
	var ammo_after_first: int = int(after.ammo.get("x1", 0))
	srv.on_box_take(pid, bid)   # ayni kutu tekrar
	var after2: Dictionary = _db_state(srv, aid)
	if int(after2.cr) != cr_after_first or int(after2.uri) != uri_after_first \
			or int(after2.ammo.get("x1", 0)) != ammo_after_first:
		_fail("ayni kutu ikinci kez odul verdi")
		return
	print("[OK] Bonus kutusu odulu kalici ve tek seferlik (cr+%d uri+%d ammo+%d)" % [
		int(after.cr) - int(before.cr), int(after.uri) - int(before.uri),
		int(after.ammo.get("x1", 0)) - int(before.ammo.get("x1", 0))])

	# --- 2) Mermi odulu de kalici olmali + event id idempotent
	var ammo_base: int = int(_db_state(srv, aid).ammo.get("x1", 0))
	var ammo_ev: String = "box:test:ammo:%d" % aid
	var ar1: Dictionary = srv._grant_reward(srv.players[pid], ammo_ev, "reward_box", 0, 0, 0.0, 0.0, 0, 0, 0, {"x1": 250})
	var ar2: Dictionary = srv._grant_reward(srv.players[pid], ammo_ev, "reward_box", 0, 0, 0.0, 0.0, 0, 0, 0, {"x1": 250})
	if not ar1.get("ok", false) or not ar2.get("duplicate", false):
		_fail("mermi odulu idempotent degil")
		return
	var ammo_state: Dictionary = _db_state(srv, aid)
	if int(ammo_state.ammo.get("x1", 0)) != ammo_base + 250:
		_fail("mermi odulu DB'ye bir kez yazilmadi: %s" % str(ammo_state.ammo))
		return
	print("[OK] Mermi odulu kalici, ayni olay iki kez yazilmiyor")

	# --- 3) NPC olumu: cr/uri/xp/hon/kills/sep DB'ye yazilmali; tekrar odul yok
	var npc: Dictionary = srv._make_npc(w, "streuner", pos, -1)
	if npc.is_empty():
		_fail("test NPC'si olusturulamadi")
		return
	var before_npc: Dictionary = _db_state(srv, aid)
	var expected_kills: int = int(before_npc.kills) + 1
	srv._kill_npc(w, npc, pid, false)
	var after_npc: Dictionary = _db_state(srv, aid)
	if int(after_npc.cr) != int(before_npc.cr) + 400:
		_fail("NPC kredi odulu yanlis: %d -> %d" % [int(before_npc.cr), int(after_npc.cr)])
		return
	if int(after_npc.uri) != int(before_npc.uri) + 1:
		_fail("NPC uridium odulu yanlis")
		return
	if int(after_npc.xp) != int(before_npc.xp) + 400:
		_fail("NPC XP odulu yanlis")
		return
	if int(after_npc.kills) != expected_kills:
		_fail("NPC oldurme sayisi kaydedilmedi")
		return
	if int(after_npc.get("sep", 0)) != int(before_npc.get("sep", 0)) + 10:
		_fail("NPC Seprom odulu yanlis")
		return
	var cr_after_npc: int = int(after_npc.cr)
	srv._kill_npc(w, npc, pid, false)   # ayni NPC olumu tekrar
	var after_npc2: Dictionary = _db_state(srv, aid)
	if int(after_npc2.cr) != cr_after_npc or int(after_npc2.kills) != expected_kills:
		_fail("ayni NPC olumu ikinci kez odul verdi")
		return
	print("[OK] NPC odulu (cr/uri/xp/hon/kills/sep) kalici ve tek seferlik")

	# --- 4) Yeniden giris: DB'den yuklenen degerler sunucu bellegiyle ayni olmali
	var relog: Dictionary = srv.db_send("load_player_state", {"account_id": aid}).get("player_state", {})
	var p: Dictionary = srv.players[pid]
	var checks := {
		"cr": int(relog.cr) == int(p._sv_cr),
		"uri": int(relog.uri) == int(p._sv_uri),
		"xp": int(relog.xp) == int(p._sv_xp),
		"hon": int(relog.hon) == int(p._sv_hon),
		"sep": int(relog.get("sep", 0)) == int(p._sv_sep),
		"kills": int(relog.kills) == int(p._sv_kills),
		"ammo": int(relog.ammo.get("x1", 0)) == ammo_base + 250,
	}
	for k in checks.keys():
		if not bool(checks[k]):
			_fail("yeniden giris senkron hatasi: %s (db=%s bellek=%s)" % [k, str(relog.get(k, "?")), str(p.get("_sv_" + k, "?"))])
			return
	print("[OK] Yeniden giris senkronizasyonu: cr=%d uri=%d xp=%d hon=%d sep=%d kills=%d ammo=%d" % [
		int(relog.cr), int(relog.uri), int(relog.xp), int(relog.hon),
		int(relog.get("sep", 0)), int(relog.kills), int(relog.ammo.get("x1", 0))])
	print("[PASS] TUM ODUL KALICILIK TESTLERI BASARILI")
	quit(0)


func _db_state(srv, aid: int) -> Dictionary:
	var r: Dictionary = srv.db_send("load_player_state", {"account_id": aid})
	if not r.has("ok") or not r["ok"]:
		_fail("DB durumu okunamadi: %s" % str(r))
		return {}
	return r["player_state"]
