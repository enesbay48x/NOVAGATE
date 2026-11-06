extends RefCounted
# NOVAGATE - SAATLIK ACIK ARTIRMA (yalnizca dedicated sunucuda calisir)
#
# * Tek kategori: SAATLIK. Her tur ROUND_SECS (1 saat) surer, LOT_COUNT adet esya satilir.
# * Esyalar yalnizca oyunun gercek verisinden (data.gd: LASERS / GENS / DRONES) secilir.
# * Sunucu: teklifi dogrular, en yuksek teklifi tutar, turu bitirir, kazanani belirler.
# * Para / esya hareketi POSTA KUTUSU (mail) uzerinden gider: iade, kazanilan esya, reddedilen teklifin parasi.
#   Istemci uygulayip kaydettikten sonra c_auc_ack ile onaylar; onaylanmayan posta kaybolmaz, tekrar gonderilir.
#   Istemci uygulanan posta numaralarini kayitta tutar (SV.auc_done) -> ayni posta iki kez uygulanmaz.
# * Her istek bir "op" numarasi tasir; ayni op ikinci kez islenmez (cift tiklama / yeniden gonderme guvenligi).
# * Durum her degisiklikte user://novagate_auction.json dosyasina yazilir; sunucu yeniden baslayinca okunur.
#
# NOT: Oyunun Kredi/Uridium bakiyesi istemci kaydinda (SV) tutuldugu icin sunucu bakiyeyi GORMEZ.
#      Istemci teklif tutarini once kendi bakiyesinden duser ("emanet"), sunucuya ne kadar odedigini bildirir;
#      sunucu odenen tutari teklifle karsilastirir, gecersizse tamamini posta ile iade eder.

const DOData := preload("res://data.gd")
const SAVE_PATH := "user://novagate_auction.json"
const ROUND_SECS := 3600
const LOT_COUNT := 8
const MAX_BID := 2000000000
const HIST_MAX := 150
const OPS_MAX := 300
const BIDS_KEEP := 40
# Fiyat ayarlari (istedigin gibi degistir)
const START_FRAC := 0.5        # baslangic teklifi = esyanin degerinin %50'si
const URI_TO_CR := 20          # Uridium ile satilan esyalarin kredi karsiligi
const INSTANT_DIV := 100       # "Hemen Al" Uridium bedeli = deger / bu sayi

var net: Node
var srv                          # NetServer (players sozlugu icin)
var d: Dictionary = {}
var _chk: float = 0.0
var _fresh: Dictionary = {}     # oyuncu anahtari -> bu oturumda sunucu envanterine yazilip istemciye yollanan posta idleri
var _rng := RandomNumberGenerator.new()


func _init(n: Node, s) -> void:
	net = n
	srv = s
	_rng.randomize()
	_load()
	var now: int = _now()
	if (d["lots"] as Array).is_empty() or int(d["round_end"]) <= 0:
		_new_round(now)
		_save()
	elif now >= int(d["round_end"]):
		_end_round(now)
		_save()
	print("[ACIK ARTIRMA] Tur %d, %d esya, bitisine %d sn." % [int(d["round"]), (d["lots"] as Array).size(), maxi(0, int(d["round_end"]) - now)])


# ------------------------------------------------------------------ yardimcilar
func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _blank() -> Dictionary:
	return {"v": 1, "next_lot": 1, "next_mail": 1, "round": 0, "round_end": 0,
		"lots": [], "mail": {}, "hist": [], "ops": {}}


func _load() -> void:
	d = _blank()
	var path := SAVE_PATH
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		path = path + ".tmp"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		for k in (parsed as Dictionary).keys():
			d[k] = (parsed as Dictionary)[k]
		for k in ["lots", "hist"]:
			if not (d[k] is Array):
				d[k] = []
		for k in ["mail", "ops"]:
			if not (d[k] is Dictionary):
				d[k] = {}
	else:
		# bozuk dosya: uzerine yazmadan once yedegini al
		push_error("[ACIK ARTIRMA] Kayit dosyasi okunamadi, yedeklendi: " + path + ".bozuk")
		var da := DirAccess.open("user://")
		if da != null:
			da.copy(path.get_file(), path.get_file() + ".bozuk")


func _save() -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[ACIK ARTIRMA] Kayit yazilamadi!")
		return
	f.store_string(JSON.stringify(d))
	f.close()
	var da := DirAccess.open("user://")
	if da == null:
		return
	var main_name := SAVE_PATH.get_file()
	if da.file_exists(main_name):
		da.remove(main_name)
	da.rename(tmp.get_file(), main_name)


func _key(peer: int) -> String:
	if srv.players.has(peer):
		return str(srv.players[peer].name).strip_edges().to_lower()
	return ""


func _name_of(peer: int) -> String:
	if srv.players.has(peer):
		return str(srv.players[peer].name)
	return ""


func _peer_of(key: String) -> int:
	for pid in srv.players.keys():
		if str(srv.players[pid].name).strip_edges().to_lower() == key:
			return int(pid)
	return 0


func _def(id: String) -> Dictionary:
	if DOData.LASERS.has(id):
		return DOData.LASERS[id]
	if DOData.GENS.has(id):
		return DOData.GENS[id]
	if DOData.DRONES.has(id):
		return DOData.DRONES[id]
	return {}


func _type_of(id: String) -> String:
	if DOData.LASERS.has(id):
		return "Lazer"
	if DOData.GENS.has(id):
		return "Hız Jeneratörü" if str(DOData.GENS[id].type) == "spd" else "Kalkan Jeneratörü"
	return "Droid"


func _value_cr(id: String) -> int:
	var df: Dictionary = _def(id)
	var cr: int = int(df.get("cr", 0))
	if cr > 0:
		return cr
	return int(df.get("uri", 0)) * URI_TO_CR


func _lot(id: int) -> Dictionary:
	for l in (d["lots"] as Array):
		if int(l["id"]) == id:
			return l
	return {}


# ------------------------------------------------------------------ tur yonetimi
func _new_round(now: int) -> void:
	d["round"] = int(d["round"]) + 1
	d["round_end"] = now + ROUND_SECS
	var pool: Array = []
	for id in DOData.LASER_ORDER:
		pool.append(str(id))
	for id in DOData.GEN_ORDER:
		pool.append(str(id))
	for id in DOData.DRONE_ORDER:
		pool.append(str(id))
	# karistir (Fisher-Yates)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var lots: Array = []
	for i in range(mini(LOT_COUNT, pool.size())):
		var id: String = str(pool[i])
		var val: int = _value_cr(id)
		var df: Dictionary = _def(id)
		lots.append({
			"id": int(d["next_lot"]), "item": id, "name": str(df.get("name", id)), "type": _type_of(id),
			"start": maxi(100, int(float(val) * START_FRAC)),
			"instant": maxi(1, int(ceil(float(val) / float(INSTANT_DIV)))),
			"bid": 0, "bidder": "", "bkey": "", "bids": [], "state": "open"})
		d["next_lot"] = int(d["next_lot"]) + 1
	d["lots"] = lots


func _end_round(now: int) -> void:
	for lot in (d["lots"] as Array):
		if str(lot["state"]) != "open":
			continue
		if str(lot["bkey"]) != "":
			lot["state"] = "won"
			_mail(str(lot["bkey"]), {"kind": "item", "item": str(lot["item"]), "qty": 1,
				"txt": "Açık artırmayı kazandın: %s  (%d Kr)" % [str(lot["name"]), int(lot["bid"])]})
			_hist(lot, "won", str(lot["bkey"]), str(lot["bidder"]), int(lot["bid"]), 0, now)
		else:
			lot["state"] = "unsold"
			_hist(lot, "unsold", "", "", 0, 0, now)
	_new_round(now)


func tick(dt: float) -> void:
	_chk += dt
	if _chk < 1.0:
		return
	_chk = 0.0
	var now: int = _now()
	if now >= int(d["round_end"]):
		_end_round(now)
		_save()
		_broadcast()
		print("[ACIK ARTIRMA] Yeni tur basladi: %d" % int(d["round"]))


func _hist(lot: Dictionary, kind: String, wkey: String, wname: String, price_cr: int, price_uri: int, t: int) -> void:
	var h: Array = d["hist"]
	h.append({"item": str(lot["item"]), "name": str(lot["name"]), "type": str(lot["type"]), "kind": kind,
		"w": wname, "wk": wkey, "p": price_cr, "pu": price_uri, "t": t})
	while h.size() > HIST_MAX:
		h.remove_at(0)


# ------------------------------------------------------------------ posta kutusu
func _mail(key: String, m: Dictionary) -> void:
	m["id"] = int(d["next_mail"])
	d["next_mail"] = int(d["next_mail"]) + 1
	var box: Array = (d["mail"] as Dictionary).get(key, [])
	box.append(m)
	(d["mail"] as Dictionary)[key] = box
	_push_mail(key)


func _refund(key: String, cr: int, uri: int) -> void:
	if key == "" or (cr <= 0 and uri <= 0):
		return
	_mail(key, {"kind": "refund", "cr": maxi(0, cr), "uri": maxi(0, uri)})


func _push_mail(key: String) -> void:
	var peer: int = _peer_of(key)
	if peer == 0:
		return
	var box: Array = (d["mail"] as Dictionary).get(key, [])
	if box.is_empty():
		return
	var acct: int = 0
	if srv.players.has(peer):
		acct = int(srv.players[peer].get("account_id", 0))
	var fresh: Array = _fresh.get(key, [])
	var keep: Array = []
	var out: Array = []
	var changed := false
	for m in box:
		if str(m.get("kind", "")) != "item":
			keep.append(m)
			out.append(m)
			continue
		var mid: int = int(m.get("id", 0))
		if bool(m.get("granted", false)):
			if fresh.has(mid):
				keep.append(m)      # bu oturumda yazildi, istemci ack edene kadar tekrar gonder
				out.append(m)
			else:
				changed = true      # onceki oturumda sunucuya yazilmis: giriste zaten yuklendi, postayi at
			continue
		if acct <= 0:
			keep.append(m)
			continue
		# ESKI HATA: urun sadece istemcide yerel kayda yaziliyordu. Simdi once SUNUCU envanterine yaz.
		var r: Dictionary = srv.db_send("auction_grant_item", {
			"account_id": acct,
			"item_id": str(m.get("item", "")),
			"quantity": int(m.get("qty", 1)),
			"tx_id": "auc:%s:%d" % [key, mid],
		})
		if bool(r.get("ok", false)):
			m["granted"] = true
			changed = true
			fresh.append(mid)
			keep.append(m)
			out.append(m)
			# sunucunun bellekteki kopyasini da guncelle
			var p: Dictionary = srv.players[peer]
			if p.get("_sv_inventory", null) is Dictionary:
				var iv: Dictionary = p["_sv_inventory"]
				iv[str(m.get("item", ""))] = int(iv.get(str(m.get("item", "")), 0)) + int(m.get("qty", 1))
		else:
			keep.append(m)          # posta kaybolmaz, sonra tekrar denenir
			var err: String = str(r.get("error", ""))
			print("[ACIK ARTIRMA] teslim edilemedi: %s -> %s (%s)" % [key, str(m.get("item", "")), err])
			if err == "drone_cap":
				_notify(key, "Açık artırma ödülün hazır ama droid sınırı dolu. Yer açınca otomatik teslim edilir.")
	_fresh[key] = fresh
	if changed:
		if keep.is_empty():
			(d["mail"] as Dictionary).erase(key)
		else:
			(d["mail"] as Dictionary)[key] = keep
		_save()
	if out.is_empty():
		return
	net.rpc_id(peer, "s_auc_mail", out.duplicate(true))


func on_ack(peer: int, ids: Array) -> void:
	var key: String = _key(peer)
	if key == "":
		return
	var box: Array = (d["mail"] as Dictionary).get(key, [])
	var keep: Array = []
	for m in box:
		var drop := false
		for i in ids:
			if int(i) == int(m["id"]):
				drop = true
				break
		if not drop:
			keep.append(m)
	if keep.is_empty():
		(d["mail"] as Dictionary).erase(key)
	else:
		(d["mail"] as Dictionary)[key] = keep
	_save()


# ------------------------------------------------------------------ op (cift islem) korumasi
func _has_op(key: String, op: int) -> bool:
	for x in ((d["ops"] as Dictionary).get(key, []) as Array):
		if int(x) == op:
			return true
	return false


func _mark_op(key: String, op: int) -> void:
	var arr: Array = (d["ops"] as Dictionary).get(key, [])
	arr.append(op)
	while arr.size() > OPS_MAX:
		arr.remove_at(0)
	(d["ops"] as Dictionary)[key] = arr


# ------------------------------------------------------------------ istemci istekleri
func on_player_ready(peer: int) -> void:
	_fresh.erase(_key(peer))   # yeni oturum: istemci envanteri zaten sunucudan yuklendi
	_send_state(peer)
	_push_mail(_key(peer))


func on_open(peer: int, pending: Array) -> void:
	var key: String = _key(peer)
	if key == "":
		return
	var known: Array = []
	var unknown: Array = []
	for op in pending:
		var o: int = int(op)
		if _has_op(key, o):
			known.append(o)
		else:
			_mark_op(key, o)      # sunucuya hic ulasmamis islem: bir daha islenmesin
			unknown.append(o)
	if not unknown.is_empty():
		_save()
	net.rpc_id(peer, "s_auc_resolve", known, unknown)
	_send_state(peer)
	_push_mail(key)


func on_bid(peer: int, op: int, lot_id: int, amount: int, paid: int) -> void:
	var key: String = _key(peer)
	if key == "":
		return
	if _has_op(key, op):
		return
	_mark_op(key, op)
	paid = clampi(paid, 0, MAX_BID)
	var now: int = _now()
	var lot: Dictionary = _lot(lot_id)
	var err := ""
	var need: int = 0
	if lot.is_empty() or str(lot["state"]) != "open" or now >= int(d["round_end"]):
		err = "Bu açık artırma artık açık değil."
	elif amount <= 0 or amount > MAX_BID:
		err = "Geçersiz teklif."
	elif amount < int(lot["start"]):
		err = "Teklif başlangıç fiyatından (%d Kr) düşük olamaz." % int(lot["start"])
	elif amount <= int(lot["bid"]):
		err = "Teklif, mevcut en yüksek tekliften yüksek olmalı."
	else:
		var mine: int = int(lot["bid"]) if str(lot["bkey"]) == key else 0
		need = amount - mine
		if paid < need:
			err = "Ödenen Kredi teklif için yetersiz."
	if err != "":
		_refund(key, paid, 0)
		_reply(peer, op, false, err)
		_save()
		_broadcast()
		return
	var prev_key: String = str(lot["bkey"])
	var prev_bid: int = int(lot["bid"])
	if prev_key != "" and prev_key != key:
		_refund(prev_key, prev_bid, 0)
		_notify(prev_key, "Teklifin geçildi: %s  (yeni teklif %d Kr). Kredin iade edildi." % [str(lot["name"]), amount])
	if paid > need:
		_refund(key, paid - need, 0)
	lot["bid"] = amount
	lot["bidder"] = _name_of(peer)
	lot["bkey"] = key
	var bids: Array = lot["bids"]
	bids.append({"n": _name_of(peer), "k": key, "a": amount, "t": now})
	while bids.size() > BIDS_KEEP:
		bids.remove_at(0)
	_reply(peer, op, true, "Teklif verildi: %s  %d Kr" % [str(lot["name"]), amount])
	_save()
	_broadcast()


func on_buy(peer: int, op: int, lot_id: int, paid_uri: int) -> void:
	var key: String = _key(peer)
	if key == "":
		return
	if _has_op(key, op):
		return
	_mark_op(key, op)
	paid_uri = clampi(paid_uri, 0, MAX_BID)
	var now: int = _now()
	var lot: Dictionary = _lot(lot_id)
	var err := ""
	if lot.is_empty() or str(lot["state"]) != "open" or now >= int(d["round_end"]):
		err = "Bu açık artırma artık açık değil."
	elif paid_uri < int(lot["instant"]):
		err = "Ödenen Uridium 'Hemen Al' bedeli için yetersiz."
	if err != "":
		_refund(key, 0, paid_uri)
		_reply(peer, op, false, err)
		_save()
		_broadcast()
		return
	var price: int = int(lot["instant"])
	var prev_key: String = str(lot["bkey"])
	if prev_key != "":
		_refund(prev_key, int(lot["bid"]), 0)
		if prev_key != key:
			_notify(prev_key, "%s 'Hemen Al' ile satın alındı. Teklifin iade edildi." % str(lot["name"]))
	if paid_uri > price:
		_refund(key, 0, paid_uri - price)
	lot["state"] = "sold"
	lot["bidder"] = _name_of(peer)
	lot["bkey"] = key
	_mail(key, {"kind": "item", "item": str(lot["item"]), "qty": 1,
		"txt": "Hemen Al ile satın alındı: %s  (%d U)" % [str(lot["name"]), price]})
	_hist(lot, "instant", key, _name_of(peer), 0, price, now)
	_reply(peer, op, true, "")
	_save()
	_broadcast()


# ------------------------------------------------------------------ gonderim
func _reply(peer: int, op: int, ok: bool, text: String) -> void:
	net.rpc_id(peer, "s_auc_op", op, ok, text)


func _notify(key: String, text: String) -> void:
	var peer: int = _peer_of(key)
	if peer != 0:
		net.rpc_id(peer, "s_auc_msg", text)


func _snapshot(key: String) -> Dictionary:
	var lots_out: Array = []
	for lot in (d["lots"] as Array):
		var my_top: int = 0
		var bids_out: Array = []
		var bids: Array = lot["bids"]
		for b in bids:
			if str(b["k"]) == key:
				my_top = maxi(my_top, int(b["a"]))
		for i in range(maxi(0, bids.size() - 8), bids.size()):
			bids_out.append({"n": str(bids[i]["n"]), "a": int(bids[i]["a"]), "t": int(bids[i]["t"])})
		lots_out.append({"id": int(lot["id"]), "item": str(lot["item"]), "name": str(lot["name"]), "type": str(lot["type"]),
			"start": int(lot["start"]), "instant": int(lot["instant"]), "bid": int(lot["bid"]), "bidder": str(lot["bidder"]),
			"state": str(lot["state"]), "mine": str(lot["bkey"]) == key, "my_top": my_top, "bids": bids_out})
	var hist_out: Array = []
	var h: Array = d["hist"]
	for i in range(maxi(0, h.size() - 60), h.size()):
		var e: Dictionary = h[i]
		hist_out.append({"item": str(e["item"]), "name": str(e["name"]), "type": str(e["type"]), "kind": str(e["kind"]),
			"w": str(e["w"]), "p": int(e["p"]), "pu": int(e["pu"]), "t": int(e["t"]), "mine": str(e["wk"]) == key and key != ""})
	hist_out.reverse()
	return {"now": _now(), "end": int(d["round_end"]), "round": int(d["round"]), "lots": lots_out, "hist": hist_out}


func _send_state(peer: int) -> void:
	var key: String = _key(peer)
	if key == "":
		return
	net.rpc_id(peer, "s_auc_state", _snapshot(key))


func _broadcast() -> void:
	for pid in srv.players.keys():
		_send_state(int(pid))
