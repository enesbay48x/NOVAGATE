extends RefCounted
# NOVAGATE - SUNUCU MANTIGI (dedicated sunucu surecinde calisir)
# - oyuncu listesi, harita bazli "dunya" (world) ve PAYLASIMLI NPC simulasyonu
# - Cubikon / Protegit savunma sistemi (main.gd'deki mantigin sunucu portu)
# - PvP hasar iletimi, sohbet, oldurme duyurulari
# Konumlar main.gd ile ayni birimde (Godot birimi; 1 DO birimi = DOData.S).

const DOData := preload("res://data.gd")
const Auction := preload("res://auction.gd")
const SafeZone := preload("res://safe_zone.gd")
const SkillTree := preload("res://skill_tree.gd")
const RankSys := preload("res://rank_system.gd")

# ---- SUNUCU DB KOPRUSU (TCP/JSON, 127.0.0.1:54321) ---------------------------
const DB_HOST := "127.0.0.1"
const DB_PORT := 54321
const DB_TIMEOUT_MS := 3000    # db_send zaman asimi (ms)
var db_tcp: StreamPeerTCP
var db_connected: bool = false
var db_instance_id: String = ""

var ghosts: Dictionary = {}     # oyuncu adi -> kopma aninda kilit/catisma sayaclari (cikip girerek sifirlanmasin)
# Combat Logout: baglantisi kopan oyuncu `players` icinde AYNI kayitla kalir (ghost=true, ghost_t=kalan sn). Boylece gemi
# haritada gorunur, NPC/oyuncular saldirabilir, harita (NPC'ler) bosalmaz. Sure/hasar sunucuda tutulur.
var safe_t: float = 0.0
var prot_sync_t: float = 0.0
const SAFE_DT := 0.1            # koruma durumunu yeniden hesaplama araligi (sn)
const JUMP_TOKEN_SEC := 15.0    # onaylanan atlayisin harita degisimini tamamlama suresi

var net: Node
var maps: Dictionary = {}
var auc = null                  # saatlik acik artirma (auction.gd)
var players: Dictionary = {}    # peer_id -> Dictionary
var worlds: Dictionary = {}     # harita adi -> Dictionary
var next_uid: int = 1
var groups: Dictionary = {}     # grup id -> {id, leader, members: [peer, ...]}
var invites: Dictionary = {}    # davet edilen peer -> {from, dl}
var next_gid: int = 1
const GROUP_MAX := 5            # grup en fazla 5 kisi
const INVITE_SEC := 30.0
var clock: float = 0.0
const FIRE_BURST := 2.0   # oyuncu salvo dogrulamisinda ag gecikmesi icin izin verilen birikmis salvo sayisi
var psnap_t: float = 0.0
var nsnap_t: float = 0.0
var stat_t: float = 0.0
var npc_override_t: float = 0.0   # son npc_overrides okuma zamani
var ban_tick_t: float = 0.0   # ban kick tick sayaci
var balance_tick_t: float = 0.0   # online oyuncu bakiye senkronizasyon sayaci
var pos_save_t: float = 0.0   # oyuncu konumu periyodik kayit sayaci
var rank_t: float = 0.0       # rütbe yeniden hesaplama sayaci (60 sn'de bir)
var admin_tick_t: float = 0.0 # admin durumu yenileme sayaci (30 sn'de bir)
var stale_lock_t: float = 0.0 # bayat kilit temizleme sayaci (30 sn'de bir)
var npc_overrides: Dictionary = {}   # map_id -> npc_count (admin panelden)
var reward_run_id: String = ""        # her sunucu acilisinda benzersiz odul olay kimligi
var next_box_id: int = 1              # kutular dunya yeniden kurulsa da tekrar etmeyen kimlik
var next_pvp_seq: int = 1             # PvP odul olay sayaci

const PSNAP_DT := 0.066         # oyuncu konum yayini (~15 Hz)
const NSNAP_DT := 0.1           # NPC konum yayini (10 Hz)
const NPC_SPACING := 2200.0     # iki NPC dogma noktasi arasi asgari mesafe (DO birimi)


func _init(n: Node) -> void:
	net = n
	maps = DOData.make_maps()
	print("[SUNUCU] %d harita yuklendi." % maps.size())
	auc = Auction.new(net, self)
	# Odul idempotency anahtari: yeniden baslatmada eski olaylarla cakismaz.
	reward_run_id = "%d-%d" % [int(Time.get_unix_time_from_system()), randi()]
	db_connect()


func db_connect() -> void:
	"""
	server_db.py ulasilabilir mi yoklar. server_db her baglantida TEK istek isleyip baglantiyi kapatir,
	bu yuzden kalici baglanti tutulmaz; db_send her istek icin yeni baglanti acar.
	"""
	db_instance_id = str(Time.get_unix_time_from_system())
	var r: Dictionary = db_send("ping", {})
	db_connected = str(r.get("error", "")) != "db_baglanti_yok"
	if db_connected:
		print("[SUNUCU] DB koprusu baglandi: %s:%d" % [DB_HOST, DB_PORT])
	else:
		print("[SUNUCU] DB baglantisi kurulamadi: %s:%d" % [DB_HOST, DB_PORT])


func db_send(method: String, payload: Dictionary) -> Dictionary:
	"""
	server_db'ye JSON mesaj gonderir ve cevabi dondurur (bloklayan, kisa zaman asimli).
	Protokol: tek satir JSON + "\\n" gonder, tek satir JSON + "\\n" cevap al, baglanti kapanir.
	"""
	var request: Dictionary = {"method": method}
	for key in payload.keys():
		request[key] = payload[key]
	var msg: String = JSON.stringify(request) + "\n"
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(DB_HOST, DB_PORT) != OK:
		return {"ok": false, "error": "db_baglanti_yok"}
	var deadline: int = Time.get_ticks_msec() + DB_TIMEOUT_MS
	# Baglanti kurulana kadar bekle
	while true:
		tcp.poll()
		var st: int = tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			break
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE or Time.get_ticks_msec() > deadline:
			tcp.disconnect_from_host()
			return {"ok": false, "error": "db_baglanti_yok"}
		OS.delay_msec(1)
	tcp.put_data(msg.to_utf8_buffer())
	# Cevabi satir sonuna (\n) kadar oku
	var buf := PackedByteArray()
	while Time.get_ticks_msec() <= deadline:
		tcp.poll()
		var n: int = tcp.get_available_bytes()
		if n > 0:
			var r: Array = tcp.get_data(n)
			if int(r[0]) == OK:
				buf.append_array(r[1])
				if buf.has(10):
					break
		elif tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break   # karsi taraf baglantiyi kapatti
		else:
			OS.delay_msec(1)
	tcp.disconnect_from_host()
	var parsed: Variant = JSON.parse_string(buf.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "db_gecersiz_yanit"}
	return parsed


func _hash_sha256(text: String) -> String:
	"""
	Godot 4.7.2 HashingContext ile SHA-256 hash hesaplar.
	Token hash'ini saklamak icin kullanilir (HMAC token dogrulamasi degistirilmez).
	"""
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	var hash_bytes: PackedByteArray = ctx.finish()
	return hash_bytes.hex_encode()


func w2g(x: float, y: float) -> Vector3:
	return Vector3(x * DOData.S, 0.0, y * DOData.S)


# ------------------------------------------------------------------ gonderim yardimcilari
func _bcast(map_name: String, method: String, args: Array, except_peer: int = 0) -> void:
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if str(p.map) != map_name or int(pid) == except_peer or bool(p.get("ghost", false)):
			continue
		net.callv("rpc_id", [int(pid), method] + args)


func _to(peer: int, method: String, args: Array) -> void:
	if players.has(peer) and not bool(players[peer].get("ghost", false)):
		net.callv("rpc_id", [peer, method] + args)


func _players_in(map_name: String) -> Array:
	var out: Array = []
	for pid in players.keys():
		if str(players[pid].map) == map_name:
			out.append(int(pid))
	return out


# ------------------------------------------------------------------ SUNUCU TARAFI ODUL KAYDI
# Odul, istemciye bildirilmeden ONCE veritabanina atomik olarak yazilir. Ayni
# event_id tekrar gelirse DB odulu ikinci kez vermez (idempotent).
func _grant_reward(p: Dictionary, event_id: String, source: String,
		cr: int = 0, uri: int = 0, xp: float = 0.0, hon: float = 0.0,
		kills: int = 0, sep: int = 0, pvp_kills: int = 0,
		ammo: Dictionary = {}, items: Dictionary = {}, meta: Dictionary = {}) -> Dictionary:
	var acct_id: int = int(p.get("account_id", 0))
	if acct_id <= 0:
		return {"ok": false, "error": "no_account"}
	var payload: Dictionary = {
		"account_id": acct_id,
		"event_id": event_id,
		"source": source,
		"cr": cr,
		"uri": uri,
		"xp": xp,
		"hon": hon,
		"kills": kills,
		"sep": sep,
		"pvp_kills": pvp_kills,
		"ammo": ammo,
		"items": items,
		"meta": meta,
	}
	var res: Dictionary = db_send("grant_reward", payload)
	# Kisa DB mesguliyetinde tekrar dene; basarisizsa istemciye odul bildirilmez.
	var tries: int = 0
	while (not res.has("ok") or res.get("ok", false) == false) and tries < 2:
		var err: String = str(res.get("error", ""))
		if err != "busy_retry" and err != "db_baglanti_yok" and err != "db_gecersiz_yanit" and err != "internal":
			break
		tries += 1
		OS.delay_msec(25)
		res = db_send("grant_reward", payload)
	if not res.has("ok") or res.get("ok", false) == false:
		print("[SUNUCU] ODUL KAYDEDILEMEDI: event=%s account=%d hata=%s" % [event_id, acct_id, str(res.get("error", "?"))])
		return res
	# Bellekteki sunucu kopyasini DB'nin kesin degerleriyle guncelle.
	p["_sv_cr"] = int(res.get("new_cr", p.get("_sv_cr", 0)))
	p["_sv_uri"] = int(res.get("new_uri", p.get("_sv_uri", 0)))
	p["_sv_xp"] = float(res.get("new_xp", p.get("_sv_xp", 0.0)))
	p["_sv_hon"] = float(res.get("new_hon", p.get("_sv_hon", 0.0)))
	p["_sv_sep"] = int(res.get("new_sep", p.get("_sv_sep", 0)))
	p["_sv_kills"] = int(res.get("new_kills", p.get("_sv_kills", 0)))
	p["_sv_pvp_kills"] = int(res.get("new_pvp_kills", p.get("_sv_pvp_kills", 0)))
	return res


# ------------------------------------------------------------------ TOKEN KIMLIK DOGRULAMA
func on_attach_token(peer_id: int, token: String) -> Array:
	"""
	ISTEMCI TARAFINDAN GELSEN DE TUM DOGRULAMA SUNUCU TARAFINDAN YAPILIR.
	Token'i server_db.py'ye gonderir, dogrulama basariliysa
	peer_id <-> account_id eslemesi olusturulur ve oyuncu verileri yuklenir.
	Donder: [ok: bool, msg: String, account_id: int, callsign: String, faction: int, player_state_json: String]
	"""
	print("[SUNUCU] on_attach_token cagrildi: peer_id=%d, token_prefix=%s" % [peer_id, token.substr(0, 20)])
	# 1. Token'i server_db'ye gonder (verify_and_consume_token)
	var resp: Dictionary = db_send("verify_and_consume_token", {
		"session_token": token,
		"instance_id": db_instance_id,
	})
	if not resp.has("ok") or resp["ok"] == false:
		print("[SUNUCU] Token dogrulanamadi: account_id=%d, resp=%s" % [peer_id, str(resp)])
		return [false, "Gecersiz veya sus mustum token", 0, "", 0, ""]
	var acct_id: int = int(resp["account_id"])
	print("[SUNUCU] Token dogrulandi: peer_id=%d, account_id=%d" % [peer_id, acct_id])

	# 1.5. Ban kontrolu (hesap yasakliysa giris engellenir)
	var ban_status: Dictionary = db_send("get_account_status", {
		"account_id": acct_id,
	})
	if ban_status.has("ok") and ban_status["ok"] and ban_status.get("ban_active", false):
		print("[SUNUCU] Banli hesap giris engellendi: account_id=%d" % acct_id)
		return [false, "Hesap yasakli: " + str(ban_status.get("ban_reason", "bilinmeyen")), 0, "", 0, ""]

	# 2. Session lock al: TEK CIHAZ KURALI -- yeni giren kazanir, eski oturum dusurulur.
	#    Kilit oturuma (token hash) baglidir; sunucu db_send ile atomik devralir.
	var session_hash: String = _hash_sha256(token)
	var lock_resp: Dictionary = db_send("acquire_session_lock", {
		"account_id": acct_id,
		"session_token_hash": session_hash,
		"instance_id": db_instance_id,
	})
	if lock_resp.is_empty() or not lock_resp.has("ok") or lock_resp["ok"] == false:
		print("[SUNUCU] Session lock alinamadi (DB): account_id=%d" % acct_id)
		return [false, "Veritabani hatasi, lutfen tekrar dene", 0, "", 0, ""]
	print("[SUNUCU] Session lock alindi: account_id=%d, devralindi=%s" % [acct_id, str(lock_resp.get("replaced", false))])
	# Bu sunucuda ayni hesabin eski oturumu varsa ONCE onu kaydedip dusur (yeni oturum
	# ancak ondan sonra DB'den veri yukler -> konum/envanter/bakiye kaybi olmaz).
	for old_pid in players.keys().duplicate():
		if int(old_pid) != peer_id and int(players[old_pid].get("account_id", -1)) == acct_id and not _is_ghost(players[old_pid]):
			print("[SUNUCU] Eski oturum dusuruluyor: account_id=%d, eski_peer=%d" % [acct_id, int(old_pid)])
			_kick_session(int(old_pid), "Hesabına başka bir cihazdan girildi")

	# 3. Oyuncu durumunu veritabanindan yukle
	var state_resp: Dictionary = db_send("load_player_state", {
		"account_id": acct_id,
	})
	if not state_resp.has("ok") or state_resp["ok"] == false:
		print("[SUNUCU] Player state yuklenemedi: account_id=%d" % acct_id)
		return [false, "Oyuncu verisi yuklenemedi", 0, "", 0, ""]
	print("[SUNUCU] Player state yuklendi: account_id=%d" % acct_id)

	var ps: Dictionary = state_resp["player_state"]

	# 4. players dict'e ekle (account_id ile izole)
	players[peer_id] = {
		"id": peer_id,
		"account_id": acct_id,
		"name": str(ps.get("callsign", "Gezgin")),
		"faction": int(ps.get("faction", 1)),
		"ship": str(ps.get("ship", "phoenix")),
		"map": "",
		"pos": Vector3.ZERO, "yaw": 0.0,
		"hp": 1.0,  # gecici; ilk c_state ile duzelir (eskiden bakiye yaziliyordu: hayalet gemi olurse olumsuz olurdu)
		"mhp": 1.0, "sh": 0.0, "msh": 0.0, "spd": 0.0,
		"in_safe": false, "ut": false, "chat_t": 0.0, "form": "std", "drn": [],
		"zone": 0, "prot": 0, "lock_t": -1.0e9, "arr_t": -1.0e9, "combat_t": -1.0e9, "last_dmg_t": -1.0e9,
		"jump_to": "", "jump_dl": -1.0, "respawn_ok": false, "group": 0,
		"wrecked": int(ps.get("wrecked", 0)) != 0,   # patlayan gemi tamir edilene kadar enkaz (DB'de kalici)
		# Sunucu tarafige ait oyuncu verisi (istemciye gosterilmez)
		"_sv_cr": int(ps.get("cr", 0)),
		"_sv_uri": int(ps.get("uri", 0)),
		"_sv_xp": float(ps.get("xp", 0.0)),
		"_sv_hon": float(ps.get("hon", 0.0)),
		"_sv_sep": int(ps.get("sep", 0)),
		"_sv_kills": int(ps.get("kills", 0)),
		"_sv_pvp_kills": int(ps.get("pvp_kills", 0)),
		"_sv_settings": str(ps.get("settings", "{}")),
		"_sv_inventory": ps.get("inv", {}),  # doldurulabilir
		"_sv_admin": int(ps.get("is_admin", 0)),   # admin yetkisi (sunucu tarafige)
		"_sv_reg_ts": int(ps.get("reg_ts", 0)),    # kayit gunu (rutbe hesabi)
		"_sv_rank_pen": float(ps.get("rank_pen", 0.0)),  # rutbe cezasi
		"_sv_skills": ps.get("skills", {}),
		"_sv_logdisks": int((ps.get("settings", {}) as Dictionary).get("logdisks", 0)) if typeof(ps.get("settings", {})) == TYPE_DICTIONARY else 0,
		"_sv_rd_resets": int((ps.get("settings", {}) as Dictionary).get("rd_resets", 0)) if typeof(ps.get("settings", {})) == TYPE_DICTIONARY else 0,
		"_sv_quests": ps.get("quests", {}),    # gorevler (rutbe hesabi)
		"_sv_rank": 0,    # rutbe rozeti (1..21), _calculate_ranks ile doldurulur
		"_sv_owned": ps.get("owned", [str(ps.get("ship", "phoenix"))]),  # sahip oldugu gemiler
		"_session_hash": session_hash,   # tek cihaz kurali: bu oturumun kilit kimligi
	}
	var p: Dictionary = players[peer_id]
	# Adminlik varsa police'i giris aninda owned'e ekle (30 sn tick'e bagli kalma)
	if bool(p.get("_sv_admin", 0)) and not "police" in p.get("_sv_owned", []):
		p["_sv_owned"].append("police")
		db_send("admin_ship", {"account_id": int(p.account_id), "ship": "police", "add": true})
		print("[ADMIN SHIP] account_id=%d callsign=%s police owned'e eklendi (giris aninda)" % [int(p.account_id), str(p.name)])

	# Combat Logout: sure dolmadan tekrar baglandiysa ayni hesabin hayalet gemisini MEVCUT durumuyla devral
	# (harita, konum, can, kalkan, savas sayaclari). Eski kimlik haritadakilerden silinir.
	var ghost_id: int = -1
	for gk in players.keys():
		if int(gk) != peer_id and _is_ghost(players[gk]) and int(players[gk].get("account_id", -1)) == acct_id:
			ghost_id = int(gk)
			break
	if ghost_id != -1:
		var gp: Dictionary = players[ghost_id]
		var gmap: String = str(gp.map)
		for gkey in ["pos", "yaw", "hp", "mhp", "sh", "msh", "spd", "in_safe", "zone", "prot", "lock_t", "arr_t",
				"combat_t", "last_dmg_t", "last_pvp_t", "form", "drn", "sel"]:
			if gp.has(gkey):
				p[gkey] = gp[gkey]
		p["_resume"] = {"map": gmap, "x": float((gp.pos as Vector3).x), "z": float((gp.pos as Vector3).z)}
		players.erase(ghost_id)
		if gmap != "":
			_bcast(gmap, "s_pleave", [ghost_id])
			ps["map"] = gmap
			ps["px"] = float((gp.pos as Vector3).x)
			ps["pz"] = float((gp.pos as Vector3).z)
		var mhp_g: float = maxf(float(gp.get("mhp", 1.0)), 1.0)
		var msh_g: float = float(gp.get("msh", 0.0))
		ps["resume"] = {"hp_r": clampf(float(gp.get("hp", mhp_g)) / mhp_g, 0.01, 1.0),
			"sh_r": clampf(float(gp.get("sh", 0.0)) / msh_g, 0.0, 1.0) if msh_g > 0.0 else 1.0}
		print("[COMBAT LOGOUT] %s tekrar baglandi, gemi mevcut durumuyla devralindi (eski_peer=%d, yeni_peer=%d, harita=%s)" % [str(p.name), ghost_id, peer_id, gmap])

	print("[SUNUCU] Token dogrulandi: peer=%d, account_id=%d, callsign=%s" % [peer_id, acct_id, str(ps.get("callsign", "Gezgin"))])

	# 5. Basarili sonuc dondur
	print("[SUNUCU] s_attach_result gonderiliyor: peer=%d" % peer_id)
	return [true, "Kimlik dogrulandi", acct_id,
		str(ps.get("callsign", "Gezgin")),
		int(ps.get("faction", 1)),
		JSON.stringify(ps)]


# ------------------------------------------------------------------ baglanti olaylari
func on_join(peer: int, proto: int, nm: String, faction: int, ship: String) -> Array:
	# [ok: bool, mesaj: String]
	if proto != net.PROTO:
		return [false, "Surum uyusmuyor (sunucu: %d, istemci: %d)." % [net.PROTO, proto]]
	# Kimlik dogrulamasi zorunlu: account_id yoksa kabul edilmez
	if not players.has(peer) or not players[peer].has("account_id"):
		return [false, "Kimlik dogrulanmamis erisim. Once token gonderin."]
	nm = nm.strip_edges()
	if nm.length() < 1 or nm.length() > 16:
		return [false, "Gecersiz oyuncu adi."]
	for pid in players.keys():
		if str(players[pid].name).to_lower() == nm.to_lower():
			return [false, "Bu isimle bir oyuncu zaten bagli."]
	if players.size() >= net.MAX_PEERS:
		return [false, "Sunucu dolu."]
	# Mevcut account_id'yi koru, diger alanlari guncelle
	var acct_id: int = int(players[peer].account_id)
	var old_p: Dictionary = players[peer]
	players[peer] = {"id": peer, "account_id": acct_id, "name": nm, "faction": clampi(faction, 1, 3), "ship": ship, "map": "",
		"pos": Vector3.ZERO, "yaw": 0.0, "hp": 1.0, "mhp": 1.0, "sh": 0.0, "msh": 0.0, "spd": 0.0,
		"in_safe": false, "ut": false, "chat_t": 0.0, "form": "std", "drn": [],
		# koruma / catisma durumu (hepsi sunucu saatiyle; birbirinden ayri)
		"zone": 0, "prot": 0, "lock_t": -1.0e9, "arr_t": -1.0e9, "combat_t": -1.0e9, "last_dmg_t": -1.0e9,
		"jump_to": "", "jump_dl": -1.0, "respawn_ok": false, "group": 0}
	# Token asamasinda yuklenen sunucu ekonomi/profil kopyasini KORU (odul kaybi olmasin).
	for _k in ["_sv_cr", "_sv_uri", "_sv_xp", "_sv_hon", "_sv_sep", "_sv_kills",
			"_sv_pvp_kills", "_sv_settings", "_sv_inventory", "_sv_admin",
			"_sv_rank", "_sv_reg_ts", "_sv_rank_pen", "_sv_quests", "_sv_owned", "_session_hash"]:
		if old_p.has(_k):
			players[peer][_k] = old_p[_k]
	if ghosts.has(nm.to_lower()):
		var gh: Dictionary = ghosts[nm.to_lower()]
		ghosts.erase(nm.to_lower())
		players[peer].lock_t = float(gh.lock_t)
		players[peer].combat_t = float(gh.combat_t)
		players[peer].arr_t = float(gh.arr_t)
	print("[SUNUCU] %s katildi (id %d, sirket %d). Oyuncu sayisi: %d" % [nm, peer, faction, players.size()])
	_system_chat("%s sunucuya katildi." % nm)
	# Ban kontrolu (on_join): yasakliysa kick et
	var join_ban: Dictionary = db_send("get_account_status", {"account_id": int(players[peer].account_id)})
	if join_ban.has("ok") and join_ban["ok"] and join_ban.get("ban_active", false):
		print("[SUNUCU] Banli oyuncu join aninda kick: account_id=%d" % players[peer].account_id)
		net.callv("rpc_id", [peer, "s_disconnect", "Hesap yasakli: " + str(join_ban.get("ban_reason", "bilinmeyen"))])
		players.erase(peer)
		return [false, "Hesap yasakli"]
	return [true, "Hos geldin, %s!" % nm]


# ------------------------------------------------------------------ COMBAT LOGOUT / SAVAS DURUMU (sunucu kontrollu)
func _is_ghost(p: Dictionary) -> bool:
	return bool(p.get("ghost", false))


# Oyuncu savasta mi? (saldirdi / saldirildi / hasar aldi). Tum sayaclar sunucu saatiyle tutulur.
func _in_combat(p: Dictionary) -> bool:
	return float(p.combat_t) > clock or float(p.lock_t) > clock or float(p.last_dmg_t) + DOData.COMBAT_SEC > clock


# Cikis suresi (sn): PvP -> COMBAT_LOGOUT_PVP_SEC, NPC saldirisi/savas -> COMBAT_LOGOUT_NPC_SEC, savas disi -> COMBAT_LOGOUT_SAFE_SEC.
func _logout_seconds(p: Dictionary) -> float:
	if float(p.get("last_pvp_t", -1.0e9)) + DOData.COMBAT_SEC > clock:
		return DOData.COMBAT_LOGOUT_PVP_SEC
	if _in_combat(p):
		return DOData.COMBAT_LOGOUT_NPC_SEC
	return DOData.COMBAT_LOGOUT_SAFE_SEC


# Hayalet gemi hasar alir: sure YENILENIR, kalkan/can sunucuda dusurulur, can 0 olursa normal olum akisi calisir.
func _ghost_damage(peer: int, dmg: float, killer: int, from_pvp: bool) -> void:
	if not players.has(peer) or dmg <= 0.0:
		return
	var g: Dictionary = players[peer]
	if not _is_ghost(g):
		return
	g.ghost_t = DOData.COMBAT_LOGOUT_PVP_SEC if from_pvp else DOData.COMBAT_LOGOUT_NPC_SEC
	g.last_dmg_t = clock
	g.combat_t = clock + DOData.COMBAT_SEC
	if from_pvp:
		g.last_pvp_t = clock
	var a: float = minf(float(g.sh), dmg * DOData.GHOST_SHIELD_ABSORB)
	g.sh = float(g.sh) - a
	g.hp = float(g.hp) - (dmg - a)
	if float(g.hp) <= 0.0:
		print("[COMBAT LOGOUT] %s hayalet gemisi yok edildi (acct=%d)" % [str(g.name), int(g.get("account_id", 0))])
		on_died(peer, killer)            # normal olum: kill mesaji + PvP odulu
		_finalize_ghost(peer, true)      # patlama: s_pleave; yeniden giriste ev haritasinda dogar


# Hayalet gemiyi guvenle kaldir ve durumunu kaydet. died=true: gemi yok edildi -> kayitli konum ev ussu (yeniden dogus).
func _finalize_ghost(peer: int, died: bool = false) -> void:
	if not players.has(peer):
		return
	var g: Dictionary = players[peer]
	if not _is_ghost(g):
		return
	var m: String = str(g.map)
	players.erase(peer)
	if m != "":
		_bcast(m, "s_pleave", [peer])
	if g.has("account_id") and m != "":
		if died:
			db_send("save_player_position", {"account_id": int(g.account_id),
				"map_name": str(DOData.FACTIONS[int(g.faction)].home), "px": 0.0, "pz": 0.0})
		else:
			var pos: Vector3 = g.pos
			if pos.x != 0.0 or pos.y != 0.0 or pos.z != 0.0:
				db_send("save_player_position", {"account_id": int(g.account_id), "map_name": m,
					"px": float(pos.x), "pz": float(pos.z)})
	if m != "":
		_maybe_free_world(m)
	print("[COMBAT LOGOUT] %s haritadan kaldirildi (%s, acct=%d)" % [str(g.name), "yok edildi" if died else "sure doldu", int(g.get("account_id", 0))])


func on_ship(peer: int, ship: String) -> void:
	# Gemi (= hangar) degistirme: tum kurallar SUNUCUDA dogrulanir, sonuc s_ship_result ile bildirilir.
	if not players.has(peer) or _is_ghost(players[peer]):
		return
	var p: Dictionary = players[peer]
	if str(p.ship) == ship:
		return
	var ok := false
	for s in DOData.SHIPS:
		if str(s.id) == ship:
			ok = true
			break
	if not ok:
		_to(peer, "s_ship_result", [false, str(p.ship), "Bilinmeyen gemi."])
		return
	# 1) Savasta gemi/hangar degistirme yasak.
	if _in_combat(p):
		print("[ON_SHIP] account_id=%d gemi degistirme REDDEDILDI (savasta)" % int(p.account_id))
		_to(peer, "s_ship_result", [false, str(p.ship), "Savaşta gemi/hangar değiştirilemez."])
		return
	# 2) Gemi hesabin olmali; police sadece admin icin.
	if not (ship in (p.get("_sv_owned", []) as Array)):
		print("[ON_SHIP] account_id=%d sahip olmadigi gemi REDDEDILDI: %s" % [int(p.account_id), ship])
		_to(peer, "s_ship_result", [false, str(p.ship), "Bu gemiye sahip değilsin."])
		return
	if ship == "police" and not bool(p.get("_sv_admin", 0)):
		print("[ON_SHIP] account_id=%d police secimi REDDEDILDI (degil admin)" % int(p.account_id))
		_to(peer, "s_ship_result", [false, str(p.ship), "Bu gemi yalnızca yöneticiler içindir."])
		return
	# 3) Aktif gemi veritabanina KALICI yazilir; yazilamazsa degisiklik de yapilmaz (bir sonraki giriste Phoenix'e donmesin).
	var ship_resp: Dictionary = db_send("save_active_ship", {"account_id": int(p.account_id), "ship": ship})
	if not ship_resp.has("ok") or not ship_resp["ok"]:
		print("[ON_SHIP] active_ship kaydedilemedi: account_id=%d (%s)" % [int(p.account_id), str(ship_resp.get("error", "?"))])
		_to(peer, "s_ship_result", [false, str(p.ship), "Gemi kaydedilemedi, tekrar dene."])
		return
	p.ship = ship
	_to(peer, "s_ship_result", [true, ship, ""])
	if str(p.map) != "":
		# s_pjoin: istemci oyuncuyu yeniden olusturur (yeni gemi modeli), digerlerine owned olmadan
		_bcast(str(p.map), "s_pjoin", [_player_info(p)], peer)


# Muhimmat (lazer cephanesi) secimi: savasta/hasar alirken de SERBEST (hangar ekipman/gemi kilidi ayri: equip_block + on_ship).
func on_select_ammo(peer: int, ammo: String) -> void:
	if not players.has(peer) or _is_ghost(players[peer]):
		return
	var p: Dictionary = players[peer]
	if not DOData.AMMO.any(func(am): return str(am.id) == ammo):
		_to(peer, "s_select_ammo_result", [false, str(p.get("sel", "x1")), "Bilinmeyen mühimmat."])
		return
	if ammo == str(p.get("sel", "x1")):
		_to(peer, "s_select_ammo_result", [true, ammo, ""])
		return
	p.sel = ammo
	db_send("save_selected_ammo", {"account_id": int(p.account_id), "ammo": ammo})
	_to(peer, "s_select_ammo_result", [true, ammo, ""])


# Ekipman/konfigurasyon kaydi (lazer, jenerator, droid, formasyon, aktif konfig). Konfigurasyon degistirme savasta SERBEST.
# Istemcinin yolladigi liste guvenilmez: veritabani katmani yuva sayisi + envanter + katalogla suzer, suzulmus hali geri doner.
func on_save_loadout(peer: int, ship: String, loads_json: String, cfgi: int, seq: int) -> void:
	if not players.has(peer) or _is_ghost(players[peer]) or loads_json.length() > 40000:
		return
	var p: Dictionary = players[peer]
	if ship != str(p.ship):
		return   # yalnizca sunucuda aktif olan geminin ekipmani yazilabilir
	var parsed = JSON.parse_string(loads_json)
	if typeof(parsed) != TYPE_ARRAY:
		return
	var resp: Dictionary = db_send("save_loadout", {"account_id": int(p.account_id), "ship": ship, "loads": parsed, "cfg_index": cfgi})
	if not resp.has("ok") or not resp["ok"]:
		print("[LOADOUT] kaydedilemedi: account_id=%d (%s)" % [int(p.account_id), str(resp.get("error", "?"))])
		return
	_to(peer, "s_loadout_result", [ship, JSON.stringify(resp.get("loads", [])), int(resp.get("cfg_index", 0)), seq])


# Yetenek agaci: kurallar (puan, on kosul, maliyet) burada dogrulanir, bedel DB'de atomik dusulur.
func on_skill_op(peer: int, op: String, arg: String) -> void:
	if not players.has(peer) or _is_ghost(players[peer]):
		return
	var p: Dictionary = players[peer]
	var acct: int = int(p.get("account_id", 0))
	var skills: Dictionary = (p.get("_sv_skills", {}) as Dictionary).duplicate()
	var disks: int = int(p.get("_sv_logdisks", 0))
	var resets: int = int(p.get("_sv_rd_resets", 0))
	var d_cr := 0
	var d_uri := 0
	var d_sep := 0
	var err := ""
	var total_pts: int = mini(SkillTree.MAX_POINTS, SkillTree.points_for_disks(disks))
	var spent := 0
	for sk in SkillTree.SKILLS:
		spent += clampi(int(skills.get(str(sk.id), 0)), 0, int(sk.pts))
	match op:
		"logdisk":
			var n: int = clampi(int(arg), 1, 100000)
			n = mini(n, int(SkillTree.CUM[SkillTree.MAX_POINTS]) - disks)
			if n <= 0:
				err = "max_puan"
			else:
				d_uri = n * SkillTree.LOGDISK_URI
				disks += n
		"skill":
			var sk: Dictionary = SkillTree.find(arg)
			var rank: int = int(skills.get(arg, 0))
			if sk.is_empty() or rank >= int(sk.pts):
				err = "gecersiz_yetenek"
			elif spent >= total_pts:
				err = "puan_yok"
			else:
				for rk in (sk.req as Dictionary).keys():
					if int(skills.get(str(rk), 0)) < int((sk.req as Dictionary)[rk]):
						err = "on_kosul"
				if err == "":
					var cost: Dictionary = SkillTree.level_cost(sk, rank + 1)
					d_cr = int(cost.cr)
					d_sep = int(cost.sep)
					skills[arg] = rank + 1
		"reset":
			if spent <= 0:
				err = "sifirlanacak_yok"
			else:
				d_uri = SkillTree.RESET_BASE_URI * (1 << clampi(resets, 0, 20))
				skills = {}
				resets += 1
		_:
			err = "gecersiz_islem"
	if err != "":
		_to(peer, "s_skill_result", [op, false, err, JSON.stringify(p.get("_sv_skills", {})), int(p.get("_sv_logdisks", 0)), int(p.get("_sv_rd_resets", 0)), int(p.get("_sv_cr", 0)), int(p.get("_sv_uri", 0)), int(p.get("_sv_sep", 0))])
		return
	var resp: Dictionary = db_send("apply_skill_change", {"account_id": acct, "d_cr": d_cr, "d_uri": d_uri, "d_sep": d_sep, "skills": skills, "logdisks": disks, "rd_resets": resets})
	if resp.has("ok") and resp["ok"]:
		p["_sv_skills"] = skills
		p["_sv_logdisks"] = disks
		p["_sv_rd_resets"] = resets
		p["_sv_cr"] = int(resp.get("new_cr", 0))
		p["_sv_uri"] = int(resp.get("new_uri", 0))
		p["_sv_sep"] = int(resp.get("new_sep", 0))
		_to(peer, "s_skill_result", [op, true, "", JSON.stringify(skills), disks, resets, int(p["_sv_cr"]), int(p["_sv_uri"]), int(p["_sv_sep"])])
	else:
		var e: String = str(resp.get("error", "bilinmeyen"))
		print("[YETENEK] basarisiz: account_id=%d op=%s hata=%s" % [acct, op, e])
		_to(peer, "s_skill_result", [op, false, e, JSON.stringify(p.get("_sv_skills", {})), int(p.get("_sv_logdisks", 0)), int(p.get("_sv_rd_resets", 0)), int(resp.get("new_cr", p.get("_sv_cr", 0))), int(resp.get("new_uri", p.get("_sv_uri", 0))), int(resp.get("new_sep", p.get("_sv_sep", 0)))])


# Alt hizli slot cubugu (10 slot, "tur:id" metinleri). Istemciye guvenilmez: uzunluk/bicim sunucuda suzulur.
func on_save_quickbar(peer: int, qb_json: String) -> void:
	if not players.has(peer) or _is_ghost(players[peer]) or qb_json.length() > 800:
		return
	var parsed = JSON.parse_string(qb_json)
	if typeof(parsed) != TYPE_ARRAY or parsed.size() > 10:
		return
	var clean: Array = []
	for v in parsed:
		var s: String = str(v)
		if s.length() > 40 or (s != "" and s.count(":") != 1):
			s = ""
		clean.append(s)
	var p: Dictionary = players[peer]
	var resp: Dictionary = db_send("save_quickbar", {"account_id": int(p.account_id), "quickbar": clean})
	if not resp.has("ok") or not resp["ok"]:
		print("[QUICKBAR] kaydedilemedi: account_id=%d (%s)" % [int(p.account_id), str(resp.get("error", "?"))])



func _kick_session(peer: int, reason: String) -> void:
	# Tek cihaz kurali: oturumu dusur. Kayit (konum) on_disconnect icinde yazilir; envanter/bakiye
	# zaten olay aninda DB'ye yazildigi icin kaybolmaz. Kilit YENI oturumda oldugundan birakilmaz.
	if not players.has(peer):
		return
	net.callv("rpc_id", [peer, "s_disconnect", reason])   # mevcut RPC; istemci mesaji gosterip baglantiyi keser
	on_disconnect(peer, false)
	var mp = net.multiplayer.multiplayer_peer
	if mp != null:
		mp.disconnect_peer(peer)   # guvenlik agi (reliable paket once gider)


func on_disconnect(peer: int, release_lock: bool = true, force_remove: bool = false) -> void:
	# Baglanti koptu (istemci kapandi / internet gitti / kick): gemi SILINMEZ. Sunucu sureyi kendisi tutar.
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	if _is_ghost(p):
		return
	# Oturum kilidini YALNIZCA kendi oturumuysa birak (eski oturum yeni oturumun kilidini silemez)
	if release_lock and p.has("account_id") and str(p.get("_session_hash", "")) != "":
		db_send("release_session_lock", {"account_id": int(p["account_id"]), "session_token_hash": str(p["_session_hash"])})
	var old_map: String = str(p.map)
	_remove_from_group(peer, false)
	invites.erase(peer)
	for ik in invites.keys():
		if int(invites[ik].from) == peer:
			invites.erase(ik)
	# Konumu kaydet (ayrilista)
	if p.has("account_id") and old_map != "":
		var pos: Vector3 = p.pos
		if pos.x != 0.0 or pos.y != 0.0 or pos.z != 0.0:
			db_send("save_player_position", {
				"account_id": int(p.account_id),
				"map_name": old_map,
				"px": float(pos.x),
				"pz": float(pos.z),
			})
	# Haritada degilse (ya da banli ise) bekleyecek gemi yok: normal temizlik.
	if old_map == "" or force_remove:
		players.erase(peer)
		if old_map != "":
			_bcast(old_map, "s_pleave", [peer])
			_maybe_free_world(old_map)
		return
	# Combat Logout: ayni kayit hayalete cevrilir. Sure = savas durumuna gore (15 / 30 sn).
	var logout_sec: float = _logout_seconds(p)
	p["ghost"] = true
	p["ghost_t"] = logout_sec
	p["ut"] = false
	print("[COMBAT LOGOUT] %s haritada kaliyor: sure=%.0f sn, acct=%d" % [str(p.name), logout_sec, int(p.get("account_id", 0))])
	_system_chat("%s sunucudan ayrildi (gemi %.0f sn haritada kalir)." % [str(p.name), logout_sec])


func _maybe_free_world(map_name: String) -> void:
	if worlds.has(map_name) and _players_in(map_name).is_empty():
		worlds.erase(map_name)
		print("[SUNUCU] Harita %s bos, NPC'ler temizlendi." % map_name)


# ------------------------------------------------------------------ harita girisi
func on_map(peer: int, map_name: String, x: float, z: float) -> void:
	if not players.has(peer) or not maps.has(map_name):
		return
	var p: Dictionary = players[peer]
	if p.has("_resume"):
		var rs: Dictionary = p["_resume"]
		p.erase("_resume")
		map_name = str(rs.map)
		x = float(rs.x)
		z = float(rs.z)
		if not maps.has(map_name):
			return
	var old_map: String = str(p.map)
	var jumped: bool = false
	if old_map != "" and old_map != map_name:
		# Harita degisimi YALNIZCA sunucunun onayladigi kapi atlayisi (on_jump) ya da olum sonrasi
		# ev haritasina yeniden dogus ile olabilir; istemci kendi basina harita degistiremez.
		var token_ok: bool = str(p.jump_to) == map_name and clock < float(p.jump_dl)
		var home_ok: bool = bool(p.respawn_ok) and map_name == str(DOData.FACTIONS[int(p.faction)].home)
		if not token_ok and not home_ok:
			_to(peer, "s_jump_result", [false, old_map, "Geçersiz harita değişikliği."])
			return
		jumped = token_ok
		_bcast(old_map, "s_pleave", [peer])
		# Harita degisirken mevcut konumu kaydet
		if p.has("account_id") and str(p.map) != "":
			var pos: Vector3 = p.pos
			if pos.x != 0.0 or pos.y != 0.0 or pos.z != 0.0:
				db_send("save_player_position", {
					"account_id": int(p.account_id),
					"map_name": str(p.map),
					"px": float(pos.x),
					"pz": float(pos.z),
				})
		p.map = ""
		_maybe_free_world(old_map)
	elif old_map == map_name:
		_bcast(old_map, "s_pleave", [peer])   # ayni haritaya yeniden dogus (olum): once eskiyi sil
	p.jump_to = ""
	p.jump_dl = -1.0
	p.respawn_ok = false
	p.map = map_name
	p.pos = Vector3(x, 0.0, z)
	p.in_safe = false
	var w: Dictionary = _get_world(map_name)
	# Gecici gecis korumasi (varsa, ayri ayarlanabilir; varsayilan KAPALI): yalnizca kapidan gelip dusman haritasina girince
	if jumped:
		p.arr_t = clock + SafeZone.arrival_seconds(w.m, int(p.faction))
	_update_safe(p, w, true)
	# istemciye harita durumunu gonder
	var npc_list: Array = []
	for uid in (w.npcs as Dictionary).keys():
		npc_list.append(_npc_info(w.npcs[uid]))
	var plist: Array = []
	for pid in _players_in(map_name):
		if pid != peer:
			plist.append(_player_info(players[pid]))
	_to(peer, "s_map_init", [map_name, npc_list, plist])
	_to(peer, "s_boxes", [map_name, _box_list(w)])   # bonus kutular: herkes AYNI listeyi alir
	if auc != null and not bool(p.get("auc_sent", false)):
		p["auc_sent"] = true
		auc.on_player_ready(peer)
	_bcast(map_name, "s_pjoin", [_player_info(p)], peer)   # digerlerine owned olmadan
	if int(p.group) != 0:
		_group_push(int(p.group))   # grup uyelerinin harita bilgisi guncellensin


# include_owned=true sadece isteyen istemciye (kendisine) giden s_pjoin'de gonderilir.
# _bcast ile diger oyunculara giden pakette owned listesi olmaz (ag trafikini kisitlar).
func _player_info(p: Dictionary, include_owned: bool = false) -> Array:
	var arr: Array = [int(p.id), str(p.name), int(p.faction), str(p.ship), float((p.pos as Vector3).x), float((p.pos as Vector3).z),
		float(p.yaw), float(p.hp), float(p.mhp), float(p.sh), float(p.msh), str(p.form), (p.drn as Array).duplicate(),
		int(p.get("_sv_admin", 0)), int(p.get("_sv_rank", 0))]
	if include_owned:
		arr.append((p.get("_sv_owned", []) as Array).duplicate())
	return arr

# Her 60 saniyede bir calistirilir: her sirket icin oyuncularin rutbesini hesaplar.
# Adminler siralamaya girmez. RankSys.points() formulu ile puan hesaplanir, RankSys.rank_index()
# ile rutbe indeksi (0..19) bulunur ve 1..21 arasinda bir rozet numarasina donusturulur
# (20 = en yuksek rutbe rank_20.png, 21 = admin rank_21.png).
func _calculate_ranks() -> void:
	var now: float = Time.get_unix_time_from_system()
	# Sirketlere gore ayir: {faction: [peer_id, ...]}
	var by_faction: Dictionary = {}
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if str(p.map) == "":
			continue
		var f: int = int(p.faction)
		if not by_faction.has(f):
			by_faction[f] = []
		(by_faction[f] as Array).append(pid)
	# Her sirket icin sirala ve rutbe ata
	for f in by_faction.keys():
		var members: Array = by_faction[f]
		# Puan hesapla
		var entries: Array = []
		for pid in members:
			var p: Dictionary = players[pid]
			var acct_id: int = int(p.get("account_id", -1))
			if bool(p.get("_sv_admin", 0)):
				var old_rank: int = int(p.get("_sv_rank", 0))
				p["_sv_rank"] = 21   # admin: rank_21.png
				if 21 != old_rank and str(p.map) != "":
					# Admin rozeti: kendine ve haritadaki digerlere gonder (mevcut s_pjoin RPC'si, yeni RPC yok).
					_to(int(pid), "s_pjoin", [_player_info(p, true)])
					_bcast(str(p.map), "s_pjoin", [_player_info(p)], int(pid))
				print("[RANK DEBUG] account_id=%d faction=%d admin -> rank=21 (rank_21.png), old=%d" % [acct_id, f, old_rank])
				continue
			var sv: Dictionary = {
				"xp": float(p.get("_sv_xp", 0.0)),
				"hon": float(p.get("_sv_hon", 0.0)),
				"ship": str(p.get("ship", "phoenix")),
				"pvp_kills": int(p.get("_sv_pvp_kills", 0)),
				"kills": int(p.get("_sv_kills", 0)),
				"reg_ts": int(p.get("_sv_reg_ts", now)),
				"rank_pen": float(p.get("_sv_rank_pen", 0.0)),
				"quests": p.get("_sv_quests", {}),
				"settings": p.get("_sv_settings", "{}"),
			}
			var pts: Dictionary = RankSys.points(sv, now)
			entries.append({"pid": pid, "pts": float(pts.total), "acct_id": acct_id})
		# Puanla sirala (yukselen)
		entries.sort_custom(func(a, b): return float(a.pts) > float(b.pts))
		# Sira no ver ve rutbe indeksi hesapla
		var counts: int = entries.size()
		for i in range(entries.size()):
			var e: Dictionary = entries[i]
			var pos: int = i + 1
			var idx: int = RankSys.rank_index(pos, counts)
			var rank_num: int = RankSys.icon_id(idx)   # 1..20
			var p: Dictionary = players[e.pid]
			var old_rank: int = int(p.get("_sv_rank", 0))
			p["_sv_rank"] = rank_num
			print("[RANK DEBUG] account_id=%d faction=%d pos=%d/%d pts=%.2f idx=%d rank=%d, old=%d" % [e.acct_id, f, pos, counts, float(e.pts), idx, rank_num, old_rank])
			if rank_num != old_rank and str(p.map) != "":
				# Rozette degisiklik var: digerlerine ve kendine gonder (mevcut s_pjoin RPC'si, yeni RPC yok).
				_bcast(str(p.map), "s_pjoin", [_player_info(p)], e.pid)
				_to(int(e.pid), "s_pjoin", [_player_info(p)])



func _npc_info(e: Dictionary) -> Array:
	return [int(e.uid), str(e.id), float((e.pos as Vector3).x), float((e.pos as Vector3).z), float(e.yaw), float(e.hp), float(e.sh)]


# Koruma durumunu SUNUCU hesaplar (konum + saldiri kilidi + gecici koruma); degisince oyuncuya bildirir.
# p.in_safe = "su an GERCEKTEN korumadayim" (NPC/PvP hasar kontrolleri bunu kullanir).
func _update_safe(p: Dictionary, w: Dictionary, force: bool = false) -> void:
	var zone: int = SafeZone.zone_kind(w.m, int(p.faction), p.pos as Vector3, w.base, w.portal_defs)
	p.zone = zone
	var pr: int = SafeZone.protection(zone, float(p.lock_t), float(p.arr_t), clock)
	p.in_safe = pr != SafeZone.NONE
	if force or pr != int(p.prot):
		p.prot = pr
		_to(int(p.id), "s_prot", [pr])


# Oyuncu saldirdi (lazer/roket/NPC ya da oyuncuya): korumasi derhal kalkar ve AGGRESSOR_LOCK_SEC boyunca geri gelmez.
# Boylece guvenli bolgeye kacmak saldirinin sonuclarindan kurtarmaz.
func _register_attack(p: Dictionary) -> void:
	p.lock_t = SafeZone.lock_after_attack(clock)
	p.arr_t = -1.0e9
	if worlds.has(str(p.map)):
		_update_safe(p, worlds[str(p.map)])


# Kapidan atlama istegi: kapiya yakinlik + catisma kilidi SUNUCUDA dogrulanir; onaylanirsa kisa sureli jeton verilir.
func on_jump(peer: int, to: String) -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	var mn: String = str(p.map)
	if mn == "" or not worlds.has(mn):
		return
	var w: Dictionary = worlds[mn]
	var near: bool = false
	for pd in w.portal_defs:
		if str(pd.to) == to and (p.pos as Vector3).distance_to(pd.pos as Vector3) <= DOData.PORTAL_RANGE * DOData.S * 1.8:
			near = true
			break
	if not near:
		_to(peer, "s_jump_result", [false, mn, "Kapıya yeterince yakın değilsin."])
		return
	var why: String = SafeZone.jump_block_reason(w.m, clock, float(p.combat_t))
	if why != "":
		_to(peer, "s_jump_result", [false, mn, why])
		return
	var dest: String = to
	if to == "random":
		var names: Array = maps.keys()
		names.erase(mn)
		dest = str(names[randi() % names.size()])
	if not maps.has(dest):
		_to(peer, "s_jump_result", [false, mn, "Geçersiz hedef harita."])
		return
	p.jump_to = dest
	p.jump_dl = clock + JUMP_TOKEN_SEC
	_to(peer, "s_jump_result", [true, dest, "random" if to == "random" else ""])


# ------------------------------------------------------------------ oyuncu durumu
func on_state(peer: int, x: float, z: float, yaw: float, hp: float, mhp: float, sh: float, msh: float, spd: float, ut: bool) -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	if str(p.map) == "":
		return
	var m: Dictionary = maps[str(p.map)]
	p.pos = Vector3(clampf(x, 0.0, float(m.w) * DOData.S), 0.0, clampf(z, 0.0, float(m.h) * DOData.S))
	p.yaw = yaw
	p.mhp = maxf(mhp, 1.0)
	p.hp = clampf(hp, 0.0, float(p.mhp))   # tamir/rapor max HP'yi asamaz
	p.sh = sh
	p.msh = maxf(msh, 0.0)
	p.spd = spd
	p.ut = ut
	if worlds.has(str(p.map)):
		_update_safe(p, worlds[str(p.map)])


# ------------------------------------------------------------------ droidler
func on_drones(peer: int, form: String, drn: Array) -> void:
	if not players.has(peer):
		return
	var clean: Array = []
	for d in drn:
		var id: String = str(d)
		if DOData.DRONES.has(id) and clean.size() < DOData.MAX_DRONES:
			clean.append(id)
	form = form.strip_edges().substr(0, 24)
	if form == "":
		form = "std"
	var p: Dictionary = players[peer]
	p.form = form
	p.drn = clean
	if str(p.map) != "":
		_bcast(str(p.map), "s_pdrones", [peer, form, clean], peer)


# ------------------------------------------------------------------ savas
func on_fire_vis(peer: int, kind: int, ref: int, nb: int, ammo: String) -> void:
	if not players.has(peer) or str(players[peer].map) == "":
		return
	# Sunucu dogrulamasi: oyuncu salvosu PLAYER_FIRE_INTERVAL'dan sik olamaz. Jeton kovasi: ortalama hiz tam sinirda tutulur,
	# ag gecikmesi yuzunden birikip gelen en fazla FIRE_BURST salvoya izin verilir. Fazlasi yayinlanmaz / saldiri sayilmaz.
	var fp: Dictionary = players[peer]
	var ftok: float = minf(FIRE_BURST, float(fp.get("fire_tok", FIRE_BURST)) + (clock - float(fp.get("fire_tok_t", clock))) / DOData.PLAYER_FIRE_INTERVAL)
	fp["fire_tok_t"] = clock
	if ftok < 1.0:
		fp["fire_tok"] = ftok
		return
	fp["fire_tok"] = ftok - 1.0
	_register_attack(players[peer])   # ates acmak (NPC ya da oyuncuya) korumayi derhal kaldirir
	_bcast(str(players[peer].map), "s_fire", [peer, kind, ref, clampi(nb, 1, 10), ammo], peer)


# Ozel esya efekti: yalnizca GORSEL yayin. Gecerli indeks + oyuncu basina en fazla 2 sn'de bir (spam korumasi).
func on_extra(peer: int, idx: int) -> void:
	if not players.has(peer) or str(players[peer].map) == "":
		return
	if idx < 0 or idx > 4:
		return
	var xp: Dictionary = players[peer]
	if clock - float(xp.get("extra_t", -99.0)) < 2.0:
		return
	xp["extra_t"] = clock
	_bcast(str(xp.map), "s_extra", [peer, idx], peer)


func on_hit_npc(peer: int, uid: int, dmg: float, mode: int = 0) -> void:
	if not players.has(peer) or _is_ghost(players[peer]) or dmg <= 0.0 or dmg > 5.0e6:
		return
	var p: Dictionary = players[peer]
	if not worlds.has(str(p.map)):
		return
	var w: Dictionary = worlds[str(p.map)]
	if not (w.npcs as Dictionary).has(uid):
		return
	var e: Dictionary = w.npcs[uid]
	if float(e.hp) <= 0.0:
		return
	var dd: Vector3 = (e.pos as Vector3) - (p.pos as Vector3)
	dd.y = 0.0
	if dd.length() > DOData.LASER_RANGE * DOData.S * 3.0:
		return    # cok uzaktan gelen vurus: reddedildi
	_register_attack(p)   # guvenli bolgede NPC'ye saldirmak korumayi kaldirir
	# --- Sahiplik mantigi (A) ---
	if e.owner == 0:
		e.owner = peer
		e.owner_hit_t = clock
	elif e.owner == peer:
		e.owner_hit_t = clock   # sahibinin kendi vurusu: sureyi yenile
	# baska oyuncu vursa owner degismez, owner_hit_t degismez
	if mode == 1:
		# SAB: yalnizca kalkan emer, govdeye hasar vermez
		e.sh = maxf(0.0, float(e.sh) - minf(float(e.sh), dmg))
		e.aggro = true
		e.last_hit_t = clock
		if e.owner == 0 or int(e.owner) == peer:
			e.target = peer
		var tally: Dictionary = e.tally
		tally[peer] = float(tally.get(peer, 0.0)) + dmg
		return
	var a: float = minf(float(e.sh), dmg * 0.8)
	e.sh = float(e.sh) - a
	e.hp = float(e.hp) - (dmg - a)
	e.aggro = true
	e.last_hit_t = clock
	if e.owner == 0 or int(e.owner) == peer:
		e.target = peer
	var tally: Dictionary = e.tally
	tally[peer] = float(tally.get(peer, 0.0)) + dmg
	if float(e.hp) <= 0.0:
		_kill_npc(w, e, e.owner, false)   # owner'a ver (sahiplik yoksa 0)


func _top_damager(w: Dictionary, e: Dictionary, fallback: int) -> int:
	var best: int = fallback
	var bv: float = -1.0
	var tally: Dictionary = e.tally
	for k in tally.keys():
		if players.has(int(k)) and str(players[int(k)].map) == str(w.name) and float(tally[k]) > bv:
			bv = float(tally[k])
			best = int(k)
	return best


func on_hit_player(peer: int, victim: int, dmg: float) -> void:
	if not players.has(peer) or not players.has(victim) or peer == victim or dmg <= 0.0 or dmg > 5.0e6:
		return
	if _is_ghost(players[peer]):
		return
	var a: Dictionary = players[peer]
	var v: Dictionary = players[victim]
	if str(a.map) == "" or str(a.map) != str(v.map):
		return
	if int(a.faction) == int(v.faction):
		return   # dost ateşi yok
	if not worlds.has(str(a.map)):
		return
	var dd: Vector3 = (a.pos as Vector3) - (v.pos as Vector3)
	dd.y = 0.0
	if dd.length() > DOData.LASER_RANGE * DOData.S * 3.0:
		return
	# 1) Saldiran, guvenli bolgede olsa bile koruma DERHAL kalkar (ve kilitlenir: kacarak kurtulamaz).
	_register_attack(a)
	# 2) Kurban hala GERCEK korumadaysa (guvenli bolge / gecici koruma) hasar YOK. Saldiran artik korumasiz oldugu icin
	#    kurban misilleme yapabilir; kurban kendisi saldirdiysa (kilitliyse) zaten korumasizdir.
	_update_safe(v, worlds[str(v.map)])
	if bool(v.in_safe):
		return
	# 3) Hasar verildi: iki taraf da "catisma" durumuna girer (kapi kilidi icin; hasar almaktan ayri sayac).
	a.combat_t = clock + DOData.COMBAT_SEC
	v.combat_t = clock + DOData.COMBAT_SEC
	v.last_dmg_t = clock
	a["last_pvp_t"] = clock
	v["last_pvp_t"] = clock
	if _is_ghost(v):
		_ghost_damage(victim, dmg, peer, true)   # baglantisi kopmus gemi: hasari sunucu uygular, sure yenilenir
		return
	_to(victim, "s_hurt", [peer, dmg])


func on_died(victim: int, killer: int) -> void:
	if not players.has(victim):
		return
	var v: Dictionary = players[victim]
	var map_name: String = str(v.map)
	# Olum: yeniden dogus yeni bir baslangic (kilit/catisma sifirlanir); yalnizca ev haritasina donus izni verilir.
	v.lock_t = -1.0e9
	v.combat_t = -1.0e9
	v.arr_t = -1.0e9
	v.last_dmg_t = -1.0e9   # patlayan gemi artik savasta sayilmaz (Phoenix'e gecis / tamir hemen yapilabilsin)
	v.respawn_ok = true
	v["wrecked"] = true   # yeniden dogus: can 0, tamir edilmeden gemi kullanilamaz (cikis-giris ile kacilamaz)
	if int(v.get("account_id", 0)) > 0:
		db_send("set_wrecked", {"account_id": int(v.account_id), "wrecked": true})
	if killer != 0 and players.has(killer) and killer != victim and int(players[killer].faction) != int(v.faction):
		var k: Dictionary = players[killer]
		print("[SUNUCU] %s -> %s (PvP)" % [str(k.name), str(v.name)])
		_bcast(map_name, "s_kill", ["%s, %s oyuncusunu yok etti!" % [str(k.name), str(v.name)]])
		# PvP odulu de DB'ye yazilir; ayni olum olayi tekrar islenemez.
		var event_id: String = "pvp:%s:%d:%d:%d" % [reward_run_id, next_pvp_seq, int(k.get("account_id", 0)), victim]
		next_pvp_seq += 1
		var pvp_res: Dictionary = _grant_reward(k, event_id, "reward_pvp",
			0, 0, 0.0, 100.0, 0, 0, 1, {}, {}, {"victim": int(v.get("account_id", 0)), "map": map_name})
		if pvp_res.has("ok") and pvp_res.get("ok", false):
			_to(killer, "s_pvp_reward", [victim, pvp_res])
	else:
		_bcast(map_name, "s_kill", ["%s yok edildi." % str(v.name)])


# ch: 0 genel (herkes), 1 sirket (yalniz ayni sirket), 2 grup (yalniz grup uyeleri)
func on_chat(peer: int, text: String, ch: int = 0) -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	# Mute kontrolu (susturulmus oyuncu sohbet atamaz)
	var mute_status: Dictionary = db_send("get_account_status", {
		"account_id": int(p.account_id),
	})
	if mute_status.has("ok") and mute_status["ok"] and mute_status.get("mute_active", false):
		_to(peer, "s_chat", ["", 0, "Sohbet engeli durmustur.", 0])
		return
	text = text.strip_edges().substr(0, 120)
	if text == "" or clock - float(p.chat_t) < 0.5:
		return
	p.chat_t = clock
	print("[SOHBET%s] %s: %s" % [["", "-SIRKET", "-GRUP"][clampi(ch, 0, 2)], str(p.name), text])
	for pid in players.keys():
		var q: Dictionary = players[pid]
		if _is_ghost(q):
			continue
		if ch == 1 and int(q.faction) != int(p.faction):
			continue
		if ch == 2 and (int(p.group) == 0 or int(q.group) != int(p.group)):
			continue
		net.callv("rpc_id", [int(pid), "s_chat", str(p.name), int(p.faction), text, clampi(ch, 0, 2)])


func _system_chat(text: String) -> void:
	for pid in players.keys():
		if _is_ghost(players[pid]):
			continue
		net.callv("rpc_id", [int(pid), "s_chat", "", 0, text, 0])


# ------------------------------------------------------------------ GRUP
func _sys_to(peer: int, text: String) -> void:
	_to(peer, "s_chat", ["", 0, text, 0])


func _group_say(gid: int, text: String) -> void:
	if not groups.has(gid):
		return
	for m in (groups[gid].members as Array):
		_sys_to(int(m), text)


func _group_push(gid: int) -> void:
	if not groups.has(gid):
		return
	var g: Dictionary = groups[gid]
	var arr: Array = []
	for m in (g.members as Array):
		if players.has(int(m)):
			arr.append([int(m), str(players[int(m)].name), str(players[int(m)].map)])
	for m in (g.members as Array):
		_to(int(m), "s_g_state", [int(g.leader), arr])


# Davet: yalniz AYNI sirketten ve AYNI haritadaki oyuncu gruba alinabilir (dusman sirket oyuncusu alinamaz).
func on_g_invite(peer: int, target: int) -> void:
	if not players.has(peer) or not players.has(target) or peer == target:
		return
	var a: Dictionary = players[peer]
	var t: Dictionary = players[target]
	if str(a.map) == "" or str(a.map) != str(t.map):
		_sys_to(peer, "Oyuncu bu haritada degil.")
		return
	if int(a.faction) != int(t.faction):
		_sys_to(peer, "Dusman sirket oyuncusu gruba alinamaz.")
		return
	if int(t.group) != 0:
		_sys_to(peer, "%s zaten bir grupta." % str(t.name))
		return
	var gid: int = int(a.group)
	if gid != 0 and groups.has(gid):
		var g: Dictionary = groups[gid]
		if int(g.leader) != peer:
			_sys_to(peer, "Yalnizca grup lideri davet edebilir.")
			return
		if (g.members as Array).size() >= GROUP_MAX:
			_sys_to(peer, "Grup dolu (en fazla %d kisi)." % GROUP_MAX)
			return
	invites[target] = {"from": peer, "dl": clock + INVITE_SEC}
	_to(target, "s_g_invite", [peer, str(a.name)])
	_sys_to(peer, "%s oyuncusuna grup daveti gonderildi." % str(t.name))


func on_g_answer(peer: int, accept: bool) -> void:
	if not players.has(peer) or not invites.has(peer):
		return
	var inv: Dictionary = invites[peer]
	invites.erase(peer)
	var from: int = int(inv.from)
	if not players.has(from):
		return
	if clock > float(inv.dl):
		_sys_to(peer, "Davetin suresi dolmus.")
		return
	var a: Dictionary = players[from]
	var t: Dictionary = players[peer]
	if not accept:
		_sys_to(from, "%s grup davetini reddetti." % str(t.name))
		return
	if int(t.group) != 0 or int(a.faction) != int(t.faction):
		return
	var gid: int = int(a.group)
	if gid == 0 or not groups.has(gid):
		gid = next_gid
		next_gid += 1
		groups[gid] = {"id": gid, "leader": from, "members": [from]}
		a.group = gid
	var g: Dictionary = groups[gid]
	if (g.members as Array).size() >= GROUP_MAX:
		_sys_to(peer, "Grup dolu.")
		return
	(g.members as Array).append(peer)
	t.group = gid
	_group_say(gid, "%s gruba katildi." % str(t.name))
	_group_push(gid)


func on_g_leave(peer: int) -> void:
	_remove_from_group(peer, true)


func on_g_kick(peer: int, target: int) -> void:
	if not players.has(peer) or not players.has(target) or peer == target:
		return
	var gid: int = int(players[peer].group)
	if gid == 0 or not groups.has(gid) or int(groups[gid].leader) != peer or int(players[target].group) != gid:
		return
	_remove_from_group(target, true, "gruptan cikarildi")


func _remove_from_group(peer: int, notify: bool, why: String = "gruptan ayrildi") -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	var gid: int = int(p.group)
	p.group = 0
	if gid == 0 or not groups.has(gid):
		return
	var g: Dictionary = groups[gid]
	(g.members as Array).erase(peer)
	if notify:
		_to(peer, "s_g_state", [0, []])
	var left: Array = g.members
	if left.size() <= 1:
		for m in left:
			if players.has(int(m)):
				players[int(m)].group = 0
				_to(int(m), "s_g_state", [0, []])
				_sys_to(int(m), "%s %s. Grup dagildi." % [str(p.name), why])
		groups.erase(gid)
		return
	if int(g.leader) == peer:
		g.leader = int(left[0])
	_group_say(gid, "%s %s." % [str(p.name), why])
	_group_push(gid)


# ------------------------------------------------------------------ dunya + NPC dogumu
func _get_world(map_name: String) -> Dictionary:
	if worlds.has(map_name):
		return worlds[map_name]
	var m: Dictionary = maps[map_name]
	var w: Dictionary = {"name": map_name, "m": m, "npcs": {}, "respawn": [], "base": null, "portals": [], "portal_defs": [],
		"boxes": {}, "box_resp": []}
	if m.base != null:
		w.base = w2g(float(m.base.x), float(m.base.y))
	for pt in m.portals:
		(w.portals as Array).append(w2g(float(pt.x), float(pt.y)))
		(w.portal_defs as Array).append({"to": str(pt.to), "pos": w2g(float(pt.x), float(pt.y))})
	worlds[map_name] = w
	_spawn_world_boxes(w)
	_spawn_world_npcs(w)
	print("[SUNUCU] Harita %s etkinlestirildi: %d NPC dogdu." % [map_name, (w.npcs as Dictionary).size()])
	return w


# ------------------------------------------------------------------ BONUS KUTULAR (sunucu otoriter)
const BOX_RESPAWN := 90.0        # alinan kutunun yerine yenisi bu kadar sn sonra cikar
const BOX_TAKE_RANGE := 14.0     # kutu alirken oyuncu ile kutu arasi azami mesafe (Godot birimi; gecikme payi dahil)


func _box_rand_pos(w: Dictionary) -> Vector3:
	var m: Dictionary = w.m
	return w2g(randf_range(800.0, float(m.w) - 800.0), randf_range(800.0, float(m.h) - 800.0))


func _spawn_world_boxes(w: Dictionary) -> void:
	var m: Dictionary = w.m
	var size_mul: float = maxf(1.0, sqrt(float(m.w) * float(m.h) / (DOData.STD_MAP_W * DOData.STD_MAP_H)))
	for i in int(35.0 * size_mul):
		_add_box(w, _box_rand_pos(w))


func _add_box(w: Dictionary, pos: Vector3) -> int:
	# Kimlik GLOBAL sayactan gelir: harita/dunya yeniden kurulsa da ayni kutu
	# kimligi tekrar kullanilmaz (ayni kutudan iki kez odul verilmesini engeller).
	var id: int = next_box_id
	next_box_id += 1
	(w.boxes as Dictionary)[id] = pos
	return id


func _box_list(w: Dictionary) -> Array:
	var out: Array = []
	for id in (w.boxes as Dictionary).keys():
		var pos: Vector3 = w.boxes[id]
		out.append([int(id), pos.x, pos.z])
	return out


# Kutu odulu SUNUCUDA belirlenir (istemci rastgele odul uretemez).
func _roll_box_reward() -> Dictionary:
	var cr: int = 0
	var uri: int = 0
	var ammo: Dictionary = {}
	var r: float = randf()
	if r < 0.75:
		cr = randi_range(500, 2000)
	elif r < 0.95:
		ammo["x1"] = randi_range(200, 1000)
	else:
		uri = randi_range(5, 40)
	return {"cr": cr, "uri": uri, "ammo": ammo, "items": {}}


# Oyuncu kutuyu almak istedi: ilk gelen alir, kutu herkesten silinir.
# Odul DB'ye yazilamazsa kutu SILINMEZ; istemciye -2 ile "tekrar dene" bildirilir.
func on_box_take(peer: int, id: int) -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	var map_name: String = str(p.map)
	if map_name == "" or not worlds.has(map_name):
		return
	var w: Dictionary = worlds[map_name]
	if not (w.boxes as Dictionary).has(id):
		_to(peer, "s_box_gone", [id, 0])   # baskasi almis (ya da yok): istemcide sil, odul verme
		return
	var pos: Vector3 = w.boxes[id]
	var pp: Vector3 = p.pos
	if Vector2(pp.x - pos.x, pp.z - pos.z).length() > BOX_TAKE_RANGE:
		_to(peer, "s_box_gone", [id, -1])  # cok uzak: odul yok, kutu kalir
		return
	var acct_id: int = int(p.get("account_id", 0))
	if acct_id <= 0:
		_to(peer, "s_box_gone", [id, -2])
		return
	var reward: Dictionary = _roll_box_reward()
	var event_id: String = "box:%s:%d:%d" % [reward_run_id, id, acct_id]
	var res: Dictionary = _grant_reward(p, event_id, "reward_box",
		int(reward.cr), int(reward.uri), 0.0, 0.0, 0, 0, 0,
		reward.ammo, reward.items, {"map": map_name, "box_id": id})
	if not res.has("ok") or res.get("ok", false) == false:
		_to(peer, "s_box_gone", [id, -2])   # odul yazilamadi: kutu yerinde kalsin
		return
	# DB yazimi basarili: kutu artik alinmis sayilir.
	(w.boxes as Dictionary).erase(id)
	(w.box_resp as Array).append(BOX_RESPAWN)
	# Odul verisi ONCE sahibine gider, sonra herkese kutu kaldirma bildirimi.
	_to(peer, "s_box_reward", [id, res])
	_bcast(map_name, "s_box_gone", [id, peer])


func _tick_boxes(w: Dictionary, dt: float) -> void:
	var rs: Array = w.box_resp
	for i in range(rs.size() - 1, -1, -1):
		rs[i] = float(rs[i]) - dt
		if float(rs[i]) > 0.0:
			continue
		rs.remove_at(i)
		var pos: Vector3 = _box_rand_pos(w)
		var id: int = _add_box(w, pos)
		_bcast(str(w.name), "s_box_new", [id, pos.x, pos.z])


func _spot_free(w: Dictionary, pos: Vector3, used: Array) -> bool:
	var m: Dictionary = w.m
	var mx: float = float(m.w) * DOData.S
	var mz: float = float(m.h) * DOData.S
	var edge: float = 700.0 * DOData.S
	if pos.x < edge or pos.z < edge or pos.x > mx - edge or pos.z > mz - edge:
		return false
	if w.base != null and pos.distance_to(w.base as Vector3) < DOData.SAFE_RADIUS * DOData.S * 1.05:
		return false
	for pp in w.portals:
		if pos.distance_to(pp as Vector3) < DOData.PORTAL_RANGE * DOData.S * 1.5:
			return false
	for u in used:
		if (u as Vector3).distance_to(pos) < NPC_SPACING * DOData.S:
			return false
	return true


func _rand_pos(w: Dictionary) -> Vector3:
	var m: Dictionary = w.m
	var pos: Vector3 = w2g(randf_range(1500.0, float(m.w) - 1500.0), randf_range(1500.0, float(m.h) - 1500.0))
	for i in 6:
		if w.base != null and pos.distance_to(w.base as Vector3) < DOData.SAFE_RADIUS * DOData.S * 1.3:
			pos = w2g(randf_range(1500.0, float(m.w) - 1500.0), randf_range(1500.0, float(m.h) - 1500.0))
	return pos


func _zone_spot(w: Dictionary, z: Dictionary, used: Array) -> Vector3:
	var m: Dictionary = w.m
	if z.has("fixed"):
		var fp: Vector3 = w2g(float(z["fixed"][0]), float(z["fixed"][1]))
		var bd: Array = z.get("bounds", [])
		for gi in 24:
			if _spot_free(w, fp, used):
				return fp
			if bd.size() == 4:
				# Sektor sinirlari varsa (Cubikon): yeni nokta YALNIZCA sektorun icinden secilir, disina tasmaz.
				var mg: float = float(DOData.CUBIKON.get("sector_margin", 600.0))
				fp = w2g(randf_range(float(bd[0]) + mg, float(bd[2]) - mg), randf_range(float(bd[1]) + mg, float(bd[3]) - mg))
			else:
				fp += Vector3(randf_range(-1600.0, 1600.0), 0.0, randf_range(-1600.0, 1600.0)) * DOData.S
		return fp
	var fa: Array = z.get("area", [1500.0, 1500.0, float(m.w) - 1500.0, float(m.h) - 1500.0])
	for gi in 48:
		var pos: Vector3 = w2g(randf_range(float(fa[0]), float(fa[2])), randf_range(float(fa[1]), float(fa[3])))
		if _spot_free(w, pos, used):
			return pos
	return w2g(randf_range(1500.0, float(m.w) - 1500.0), randf_range(1500.0, float(m.h) - 1500.0))


func _spawn_world_npcs(w: Dictionary) -> void:
	var m: Dictionary = w.m
	var zones: Array = m.get("zones", [])
	if zones.is_empty():
		for ent in m.get("npcs", []):
			for i in int(ent[1]):
				_make_npc(w, str(ent[0]), _rand_pos(w), -1)
		return
	var used: Array = []
	for zi in zones.size():
		var z: Dictionary = zones[zi]
		for i in int(z.get("n", 1)):
			var sp: Vector3 = _zone_spot(w, z, used)
			used.append(sp)
			_make_npc(w, str(z.get("npc", "")), sp, zi)


func _make_npc(w: Dictionary, id: String, pos: Vector3, zone: int) -> Dictionary:
	if id.begins_with("uber_") and str(w.name) != "4-5":
		return {}
	if not DOData.NPCS.has(id):
		return {}
	var d: Dictionary = DOData.NPCS[id]
	var e: Dictionary = {"uid": next_uid, "id": id, "d": d, "pos": pos, "yaw": randf() * TAU,
		"hp": float(d.hp), "mx": float(d.hp), "sh": float(d.sh), "msh": float(d.sh),
		"v": Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized(), "t": 0.0, "cd": 0.0,
		"aggro": false, "zone": zone, "last_hit_t": -1.0e9, "tally": {}, "target": 0, "guard_home": 0,
		"owner": 0, "owner_hit_t": -1.0e9}
	next_uid += 1
	(w.npcs as Dictionary)[e.uid] = e
	return e


func _spawn_and_announce(w: Dictionary, id: String, pos: Vector3, zone: int) -> Dictionary:
	var e: Dictionary = _make_npc(w, id, pos, zone)
	if not e.is_empty():
		_bcast(str(w.name), "s_npc_spawn", [_npc_info(e)])
	return e


func _kill_npc(w: Dictionary, e: Dictionary, killer: int, silent: bool) -> void:
	# Ayni NPC olumu iki kez islenemez (odul/cift kayit korumasi).
	if bool(e.get("dead", false)):
		return
	e["dead"] = true
	e.hp = 0.0
	(w.npcs as Dictionary).erase(e.uid)
	# --- Cubikon hasar-oranli odul (B) ---
	if str(e.id) == "cubikon" and not silent:
		_cubikon_reward(w, e)
	# --- Normal NPC: owner'a odul (A) ---
	elif not silent and int(e.owner) != 0 and players.has(int(e.owner)) and str(players[int(e.owner)].map) == str(w.name):
		killer = int(e.owner)
	# Grup: oduller, NPC ile ayni haritadaki grup uyeleri arasinda ESIT bolunur (ornek: 10.000 kredi, 4 kisi = 2.500).
	var share_n: int = 1
	var mates: Array = []
	if not silent and killer != 0 and players.has(killer) and int(players[killer].group) != 0 and groups.has(int(players[killer].group)):
		for m in (groups[int(players[killer].group)].members as Array):
			if players.has(int(m)) and str(players[int(m)].map) == str(w.name):
				mates.append(int(m))
		share_n = maxi(mates.size(), 1)
	# NPC'yi butun istemcilerden kaldir (olum sunucu tarafindan bildirilir).
	_bcast(str(w.name), "s_npc_dead", [int(e.uid), killer, silent, share_n])
	# --- Normal NPC odul: sunucu hesaplar, DB'ye yazar, sonra istemciye bildirir (C) ---
	if not silent and killer != 0 and players.has(killer) and str(players[killer].map) == str(w.name):
		var d: Dictionary = e.d
		var cr: int = int(d.cr)
		var uri: int = int(d.uri)
		var xp: int = int(d.xp)
		var hon: int = int(d.hon)
		# Tekbasli veya grup: herkes ayni miktar alir (grup toplam payi / uyeme sayisi)
		var per_cr: int = int(cr / share_n)
		var per_uri: int = int(uri / share_n)
		var per_xp: int = int(xp / share_n)
		var per_hon: int = int(hon / share_n)
		var per_sep: int = int(round(float(per_uri) * float(SkillTree.SEPROM_PER_URI)))
		# Odulu alacaklar: killer + grupdaki digerleri
		var receivers: Array = [killer]
		for m in mates:
			if int(m) != killer:
				receivers.append(int(m))
		for r in receivers:
			var rp: Dictionary = players[int(r)]
			var acct_id: int = int(rp.get("account_id", 0))
			if acct_id <= 0:
				continue
			var event_id: String = "npc:%s:%d:%d" % [reward_run_id, int(e.uid), acct_id]
			var res: Dictionary = _grant_reward(rp, event_id, "reward_npc",
				per_cr, per_uri, float(per_xp), float(per_hon), 1, per_sep, 0,
				{}, {}, {"map": str(w.name), "npc": str(e.id), "uid": int(e.uid)})
			if res.has("ok") and res.get("ok", false):
				_to(int(r), "s_npc_reward", [{
					"npc_id": str(e.id),
					"uid": int(e.uid),
					"cr": per_cr,
					"uri": per_uri,
					"xp": per_xp,
					"hon": per_hon,
					"sep": per_sep,
					"kills": 1,
					"state": res,
				}])
	if silent or int(e.guard_home) != 0:
		return
	var at: Variant = null
	if str(e.id) == "cubikon":
		at = e.pos
	(w.respawn as Array).append({"t": float(e.d.resp), "id": str(e.id), "zone": int(e.zone), "at": at})

# --- Cubikon hasar-oranli odul ---
func _cubikon_reward(w: Dictionary, e: Dictionary) -> void:
	var C: Dictionary = DOData.CUBIKON
	var tally: Dictionary = e.tally
	var total: float = 0.0
	for k in tally.keys():
		total += float(tally[k])
	if total <= 0.0:
		return
	# Her oyuncunun ham payi
	var pays: Dictionary = {}
	for k in tally.keys():
		var pct: float = float(tally[k]) / total
		pays[int(k)] = pct
	# Grup toplami: grup uyesi ise grup adina topla
	var group_totals: Dictionary = {}
	var group_members: Dictionary = {}
	for pid in pays.keys():
		var p: Dictionary = players[pid]
		if not p: continue
		var g: int = int(p.group)
		if g != 0 and groups.has(g):
			var gm: Array = groups[g].members
			var in_group: bool = false
			for m in gm:
				if int(m) == pid:
					in_group = true
					break
			if in_group:
				if not group_totals.has(g):
					group_totals[g] = 0.0
					group_members[g] = []
				group_totals[g] += pays[pid]
				group_members[g].append(pid)
				pays[pid] = 0.0  # grup uyesinin tekil payi sifirla, grup totallendiginde dagitilacak
	# Toplemeleri dagit
	for g in group_totals.keys():
		var members: Array = group_members[g]
		var per_member: float = group_totals[g] / maxi(members.size(), 1)
		for m in members:
			if not pays.has(m):
				pays[m] = 0.0
			pays[m] += per_member
	# Odemeyi SUNUCUDA hesapla, DB'ye yaz, sonra bildir
	for pid in pays.keys():
		var pct: float = pays[pid]
		if pct <= 0.0:
			continue
		var p: Dictionary = players[pid]
		if not p: continue
		var acct_id: int = int(p.get("account_id", 0))
		if acct_id <= 0:
			continue
		var cr: int = roundi(float(DOData.NPCS["cubikon"].cr) * pct)
		var uri: int = roundi(float(DOData.NPCS["cubikon"].uri) * pct)
		var xp: int = roundi(float(DOData.CUBIKON_XP) * pct)
		var hon: int = roundi(float(DOData.NPCS["cubikon"].hon) * pct)
		var sep: int = int(round(float(uri) * float(SkillTree.SEPROM_PER_URI)))
		var event_id: String = "npc:%s:%d:%d" % [reward_run_id, int(e.uid), acct_id]
		var res: Dictionary = _grant_reward(p, event_id, "reward_npc",
			cr, uri, float(xp), float(hon), 1, sep, 0,
			{}, {}, {"map": str(w.name), "npc": "cubikon", "uid": int(e.uid), "share": pct})
		if res.has("ok") and res.get("ok", false):
			_to(int(pid), "s_npc_reward", [{
				"npc_id": "cubikon",
				"uid": int(e.uid),
				"cr": cr,
				"uri": uri,
				"xp": xp,
				"hon": hon,
				"sep": sep,
				"kills": 1,
				"state": res,
			}])


# ------------------------------------------------------------------ ana dongu
func tick(dt: float) -> void:
	dt = minf(dt, 0.1)
	clock += dt
	if auc != null:
		auc.tick(dt)
	for wn in worlds.keys():
		var w: Dictionary = worlds[wn]
		_tick_respawn(w, dt)
		_tick_boxes(w, dt)
		var uids: Array = (w.npcs as Dictionary).keys()
		for uid in uids:
			if not (w.npcs as Dictionary).has(uid):
				continue
			_update_npc(w, w.npcs[uid], dt)
	nsnap_t += dt
	if nsnap_t >= NSNAP_DT:
		nsnap_t = 0.0
		for wn in worlds.keys():
			_send_npc_snap(worlds[wn])
	# Koruma durumu zamanla da degisir (saldiri kilidi bitti, gecici koruma bitti): duzenli yeniden hesapla
	safe_t += dt
	if safe_t >= SAFE_DT:
		safe_t = 0.0
		prot_sync_t += SAFE_DT
		var resync: bool = prot_sync_t >= 2.0   # 2 sn'de bir durum yeniden gonderilir: istemci ile sunucu ayrisamaz
		if resync:
			prot_sync_t = 0.0
		for pid in players.keys():
			var sp: Dictionary = players[pid]
			if str(sp.map) != "" and worlds.has(str(sp.map)):
				_update_safe(sp, worlds[str(sp.map)], resync)
	psnap_t += dt
	if psnap_t >= PSNAP_DT:
		psnap_t = 0.0
		_send_player_snaps()
	stat_t += dt
	if stat_t >= 60.0:
		stat_t = 0.0
		var npc_n: int = 0
		for wn in worlds.keys():
			npc_n += (worlds[wn].npcs as Dictionary).size()
		print("[SUNUCU] Oyuncu: %d | Aktif harita: %d | NPC: %d" % [players.size(), worlds.size(), npc_n])
		_calculate_ranks()
	npc_override_t += dt
	ban_tick_t += dt        # [ZAMANLAYICI-FIX] her karede artar (eskiden 5 sn'lik blogun icindeydi)
	balance_tick_t += dt
	pos_save_t += dt
	if npc_override_t >= 5.0:
		npc_override_t = 0.0
		var resp: Dictionary = db_send("get_npc_overrides", {})
		if resp.has("ok") and resp["ok"]:
			npc_overrides = resp.get("overrides", {})
		# NPC sayisini override ile sinirla (admin panelden)
		for wn in worlds.keys():
			var w: Dictionary = worlds[wn]
			var max_npc: int = int(npc_overrides.get(wn, 0))
			if max_npc > 0:
				var npcs: Dictionary = w.npcs as Dictionary
				while npcs.size() > max_npc:
					var first_uid: Variant = npcs.keys()[0]
					npcs.erase(first_uid)
	# Cele online oyuncularin ban durumunu kontrol et, banliysa kick et
	if ban_tick_t >= 5.0:
		ban_tick_t = 0.0
		for pid in players.keys().duplicate():
			var p: Dictionary = players[pid]
			var st: Dictionary = db_send("get_account_status", {"account_id": int(p.account_id)})
			if st.has("ok") and st["ok"] and st.get("ban_active", false):
				print("[SUNUCU] Banli oyuncu tick ile kick: account_id=%d" % p.account_id)
				if _is_ghost(p):
					_finalize_ghost(int(pid))   # banli hesabin gemisi haritada bekletilmez
					continue
				net.callv("rpc_id", [int(pid), "s_disconnect", "Hesap yasakli: " + str(st.get("ban_reason", "bilinmeyen"))])
				on_disconnect(int(pid), true, true)
	# Online oyuncularin cr/uri bakiyesini DB'den senkronize et (admin panelinden gelen degisiklikler icin)
	if balance_tick_t >= 30.0:
		balance_tick_t = 0.0
		for pid in players.keys().duplicate():
			var p: Dictionary = players[pid]
			if _is_ghost(p):
				continue
			var bal: Dictionary = db_send("get_player_balance", {"account_id": int(p.account_id)})
			if bal.has("ok") and bal["ok"]:
				p["_sv_cr"] = int(bal["cr"])
				p["_sv_uri"] = int(bal["uri"])
	# Admin durumu her 30 sn'de bir DB'den yenilenir (admin panelinden gelen degisiklik icin)
	admin_tick_t += dt
	if admin_tick_t >= 30.0:
		admin_tick_t = 0.0
		for pid in players.keys().duplicate():
			var p: Dictionary = players[pid]
			if _is_ghost(p):
				continue
			var st: Dictionary = db_send("get_account_status", {"account_id": int(p.account_id)})
			if st.has("ok") and st["ok"]:
				var new_admin: bool = bool(st.get("is_admin", false))
				var old_admin: bool = bool(p.get("_sv_admin", 0))
				if new_admin != old_admin:
					p["_sv_admin"] = 1 if new_admin else 0
					# Adminlik degisti: police gemisi owned listesini guncelle
					var owned: Array = p.get("_sv_owned", []).duplicate()
					if new_admin and not "police" in owned:
						owned.append("police")
						db_send("admin_ship", {"account_id": int(p.account_id), "ship": "police", "add": true})
					elif not new_admin and "police" in owned:
						owned.erase("police")
						db_send("admin_ship", {"account_id": int(p.account_id), "ship": "police", "add": false})
						# Aktif gimi police ise Phoenix'e don
						if str(p.ship) == "police":
							p.ship = "phoenix"
							# Haritadaki diger oyunculara guncellenen gemi bilgisini gonder
							if str(p.map) != "" and worlds.has(str(p.map)):
								_bcast(str(p.map), "s_pjoin", [_player_info(p)], int(pid))
					p["_sv_owned"] = owned
					# Haritadaki diger oyunculara ve kendine guncellenen oyuncu bilgisini gonder (owned guncellemesi icin mevcut s_pjoin RPC'si, yeni RPC yok).
					if str(p.map) != "" and worlds.has(str(p.map)):
						_bcast(str(p.map), "s_pjoin", [_player_info(p)], int(pid))
						_to(int(pid), "s_pjoin", [_player_info(p, true)])
	# Bayat session kilitlerini temizle + heartbeat (kilit TTL 90 sn, 30 sn'de bir yenilenir)
	stale_lock_t += dt
	if stale_lock_t >= 30.0:
		stale_lock_t = 0.0
		for hb_pid in players.keys().duplicate():
			var hb_p: Dictionary = players[hb_pid]
			if _is_ghost(hb_p):
				continue
			if hb_p.has("account_id") and str(hb_p.get("_session_hash", "")) != "":
				var hb: Dictionary = db_send("renew_session_lock", {"account_id": int(hb_p.account_id), "session_token_hash": str(hb_p._session_hash)})
				if hb.get("ok", false) and not hb.get("owned", true):
					_kick_session(int(hb_pid), "Hesabına başka bir cihazdan girildi")
		var cl: Dictionary = db_send("cleanup_stale_locks", {})
		if cl.has("ok"):
			print("[SUNUCU] Bayat kilit temizlendi: %d adet" % cl.get("deleted", 0))
	# Her oyuncunun konumunu periyodik olarak kaydet (~20 saniyede bir)
	if pos_save_t >= 20.0:
		pos_save_t = 0.0
		for pid in players.keys().duplicate():
			var p: Dictionary = players[pid]
			if _is_ghost(p):
				continue
			if p.has("account_id") and str(p.map) != "":
				var pos: Vector3 = p.pos
				if pos.x != 0.0 or pos.y != 0.0 or pos.z != 0.0:
					db_send("save_player_position", {
						"account_id": int(p.account_id),
						"map_name": str(p.map),
						"px": float(pos.x),
						"pz": float(pos.z),
					})



	# Combat Logout sayaci: sure dolan hayalet gemiler haritadan guvenle kaldirilir ve durumlari kaydedilir.
	for gpid in players.keys().duplicate():
		var gq: Dictionary = players[gpid]
		if not _is_ghost(gq):
			continue
		gq.ghost_t = float(gq.ghost_t) - dt
		if float(gq.ghost_t) <= 0.0:
			_finalize_ghost(int(gpid))


func _tick_respawn(w: Dictionary, dt: float) -> void:
	var rs: Array = w.respawn
	for i in range(rs.size() - 1, -1, -1):
		var r: Dictionary = rs[i]
		r.t = float(r.t) - dt
		if float(r.t) > 0.0:
			continue
		rs.remove_at(i)
		var pos: Vector3
		if r.at != null:
			pos = r.at as Vector3
		else:
			var zones: Array = (w.m as Dictionary).get("zones", [])
			var zi: int = int(r.zone)
			var used: Array = []
			for uid in (w.npcs as Dictionary).keys():
				used.append(w.npcs[uid].pos)
			if zi >= 0 and zi < zones.size():
				pos = _zone_spot(w, zones[zi], used)
			else:
				pos = _rand_pos(w)
		_spawn_and_announce(w, str(r.id), pos, int(r.zone))


func _send_npc_snap(w: Dictionary) -> void:
	var peers: Array = _players_in(str(w.name))
	if peers.is_empty():
		return
	var arr := PackedFloat32Array()
	for uid in (w.npcs as Dictionary).keys():
		var e: Dictionary = w.npcs[uid]
		arr.append(float(e.uid))
		arr.append((e.pos as Vector3).x)
		arr.append((e.pos as Vector3).z)
		arr.append(float(e.yaw))
		arr.append(float(e.hp))
		arr.append(float(e.sh))
		arr.append(1.0 if bool(e.aggro) else 0.0)
	for pid in peers:
		if _is_ghost(players[pid]):
			continue
		net.rpc_id(int(pid), "s_npc_snap", arr)


func _send_player_snaps() -> void:
	var by_map: Dictionary = {}
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if str(p.map) == "":
			continue
		if not by_map.has(str(p.map)):
			by_map[str(p.map)] = []
		(by_map[str(p.map)] as Array).append(int(pid))
	for mn in by_map.keys():
		var ids: Array = by_map[mn]
		if ids.size() < 2:
			continue
		for pid in ids:
			if _is_ghost(players[pid]):
				continue
			var arr: Array = []
			for oid in ids:
				if oid == pid:
					continue
				var o: Dictionary = players[oid]
				arr.append([int(oid), (o.pos as Vector3).x, (o.pos as Vector3).z, float(o.yaw), float(o.hp), float(o.mhp), float(o.sh), float(o.msh), float(o.spd)])
			net.rpc_id(int(pid), "s_psnap", arr)


# ------------------------------------------------------------------ NPC yapay zekasi
func _face(e: Dictionary, d: Vector3, dt: float) -> void:
	if d.length_squared() < 0.0001:
		return
	e.yaw = lerp_angle(float(e.yaw), atan2(d.x, d.z), minf(1.0, dt * 6.0))


func _clamp_pos(w: Dictionary, e: Dictionary) -> void:
	var m: Dictionary = w.m
	var pos: Vector3 = e.pos
	pos.x = clampf(pos.x, 0.0, float(m.w) * DOData.S)
	pos.z = clampf(pos.z, 0.0, float(m.h) * DOData.S)
	e.pos = pos


func _emit_fire(w: Dictionary, e: Dictionary, target_peer: int, dmg: float) -> void:
	if players.has(target_peer):
		var tp: Dictionary = players[target_peer]
		_update_safe(tp, w)
		if bool(tp.in_safe):
			return   # koruma kalkmadan NPC hasari da verilmez (sunucu karari)
		tp.last_dmg_t = clock
		if SafeZone.npc_damage_is_combat(w.m):
			tp.combat_t = maxf(float(tp.combat_t), clock + DOData.COMBAT_SEC)
		if _is_ghost(tp):
			_ghost_damage(target_peer, dmg, 0, false)   # NPC saldirisi altindaki hayalet: can sunucuda duser, sure yenilenir
	_bcast(str(w.name), "s_npc_fire", [int(e.uid), target_peer, dmg])


func _update_npc(w: Dictionary, e: Dictionary, dt: float) -> void:
	if str(e.id) == "cubikon":
		_update_cubic(w, e, dt)
		return
	if int(e.guard_home) != 0:
		_update_guard(w, e, dt)
		return
	var d: Dictionary = e.d
	var spd: float = float(d.spd) * DOData.S * DOData.SPEEDMULT * 0.8
	var aggro_u: float = DOData.AGGRO_RANGE * DOData.S
	var range_u: float = DOData.LASER_RANGE * DOData.S
	# --- Sahiplik sure dolumu ve temizleme (A) ---
	if int(e.owner) != 0:
		var owner_ok: bool = false
		if players.has(int(e.owner)):
			var op: Dictionary = players[int(e.owner)]
			if str(op.map) == str(w.name) and not bool(op.ut):
				owner_ok = true
		if not owner_ok:
			if clock - float(e.owner_hit_t) > 10.0:
				e.owner = 0
				e.owner_hit_t = -1.0e9
				e.target = 0
				e.aggro = false
	# hedef secimi: sahip varsa SADECE owner'a, yoksa normal mantik
	var tgt: Dictionary = {}
	var tl: float = 1.0e9
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if str(p.map) != str(w.name) or bool(p.in_safe) or bool(p.ut):
			continue
		# Sahip varsa SADECE ona atis yapilabilir
		if int(e.owner) != 0 and int(pid) != int(e.owner):
			continue
		var dv: Vector3 = (p.pos as Vector3) - (e.pos as Vector3)
		dv.y = 0.0
		var L: float = dv.length()
		var ok: bool = (bool(d.aggr) and L < aggro_u) or (bool(e.aggro) and L < aggro_u * 3.0)
		if not ok:
			continue
		var score: float = L - (1000.0 if int(pid) == int(e.target) else 0.0)
		if score < tl:
			tl = score
			tgt = p
	if not tgt.is_empty():
		var dvec: Vector3 = (tgt.pos as Vector3) - (e.pos as Vector3)
		dvec.y = 0.0
		var Ld: float = dvec.length()
		e.aggro = true
		e.target = int(tgt.id)
		if Ld > range_u * 0.6:
			e.pos = (e.pos as Vector3) + dvec.normalized() * spd * dt
		_face(e, dvec, dt)
		var cd_prev: float = float(e.cd)
		e.cd = cd_prev - dt
		if Ld < range_u and float(e.cd) <= 0.0:
			e.cd = DOData.rearm_cd(cd_prev, float(e.cd), dt, DOData.NPC_FIRE_INTERVAL)
			_emit_fire(w, e, int(tgt.id), DOData.npc_shot_damage(d))   # TEK atis: tek hasar degeri (sunucu belirler)
	else:
		e.aggro = false
		e.target = 0
		e.t = float(e.t) - dt
		if float(e.t) <= 0.0:
			e.t = randf_range(2.0, 5.0)
			e.v = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		e.pos = (e.pos as Vector3) + (e.v as Vector3) * spd * 0.3 * dt
		_face(e, e.v as Vector3, dt)
		var m: Dictionary = w.m
		var pp: Vector3 = e.pos
		if pp.x < 0.0 or pp.z < 0.0 or pp.x > float(m.w) * DOData.S or pp.z > float(m.h) * DOData.S:
			e.v = -(e.v as Vector3)
	_clamp_pos(w, e)


# ---------------- Cubikon (sabit patron) + Protegit suru
func _nearest_player(w: Dictionary, pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1.0e9
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if str(p.map) != str(w.name):
			continue
		var d: float = (p.pos as Vector3).distance_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


func _guard_count(w: Dictionary, home: Dictionary) -> int:
	var n: int = 0
	for uid in (w.npcs as Dictionary).keys():
		var g: Dictionary = w.npcs[uid]
		if str(g.id) == "protegit" and int(g.guard_home) == int(home.uid) and float(g.hp) > 0.0:
			n += 1
	return n


func _update_cubic(w: Dictionary, e: Dictionary, dt: float) -> void:
	var C: Dictionary = DOData.CUBIKON
	var np: Dictionary = _nearest_player(w, e.pos as Vector3)
	var L: float = 1.0e9
	if not np.is_empty():
		var dv: Vector3 = (np.pos as Vector3) - (e.pos as Vector3)
		dv.y = 0.0
		L = dv.length()
		_face(e, dv, dt)   # sadece bakar, konumu degismez
	var since_hit: float = clock - float(e.last_hit_t)
	if since_hit > float(C.regen_delay) and float(e.hp) < float(e.mx):
		e.hp = minf(float(e.mx), float(e.hp) + float(C.regen_hp) * dt)
	# Tamamen yenelirse tally'yi temizle (eski saldirilar yeni savasa karismasin)
	if since_hit > float(C.regen_delay) and float(e.hp) >= float(e.mx):
		e.tally = {}
	var leash_u: float = float(C.leash) * DOData.S
	var engaged: bool = since_hit < float(C.regen_delay) and L <= leash_u
	if engaged:
		if not bool(e.get("guards_called", false)):
			e["guards_called"] = true
			e["guard_quota"] = randi_range(int(C.guard_min), int(C.guard_max))
			e["wave_t"] = 0.0
		var missing: int = int(e.get("guard_quota", 0)) - _guard_count(w, e)
		if missing > 0:
			e["wave_t"] = float(e.get("wave_t", 0.0)) - dt
			if float(e["wave_t"]) <= 0.0:
				e["wave_t"] = float(C.wave_gap)
				for gi in mini(int(C.wave), missing):
					_spawn_guard(w, e)
	elif since_hit > float(C.regen_delay):
		e["guards_called"] = false


func _spawn_guard(w: Dictionary, home: Dictionary) -> void:
	var C: Dictionary = DOData.CUBIKON
	var orr: float = randf_range(float(C.swarm_r_min), float(C.swarm_r_max))
	var oa: float = randf() * TAU
	var ow: float = randf_range(float(C.swarm_w_min), float(C.swarm_w_max)) * (1.0 if randf() < 0.5 else -1.0)
	var at: Vector3 = (home.pos as Vector3) + Vector3(cos(oa) * orr, 0.0, sin(oa) * orr)
	var g: Dictionary = _spawn_and_announce(w, "protegit", at, -1)
	if g.is_empty():
		return
	g.guard_home = int(home.uid)
	g["home_pos"] = home.pos
	g.aggro = true
	g["orb_r"] = orr
	g["orb_a"] = oa
	g["orb_w"] = ow
	g.cd = 0.0   # ilk atis: menzile girdigi an; sonrakiler NPC_FIRE_INTERVAL aralikla
	g["far_t"] = 0.0
	g["desp"] = float(C.clean_after)


func _guard_target(w: Dictionary, home: Dictionary) -> Dictionary:
	# En cok hasar veren oyuncu (haritada olan); yoksa Cubikona en yakin oyuncu
	var best: int = 0
	var bv: float = -1.0
	var tally: Dictionary = home.tally
	for k in tally.keys():
		if players.has(int(k)) and str(players[int(k)].map) == str(w.name) and float(tally[k]) > bv:
			bv = float(tally[k])
			best = int(k)
	if best != 0:
		return players[best]
	return _nearest_player(w, home.pos as Vector3)


func _update_guard(w: Dictionary, e: Dictionary, dt: float) -> void:
	var C: Dictionary = DOData.CUBIKON
	var d: Dictionary = e.d
	var npcs: Dictionary = w.npcs
	var home: Dictionary = {}
	if npcs.has(int(e.guard_home)):
		home = npcs[int(e.guard_home)]
	if home.is_empty() or float(home.hp) <= 0.0:
		# Cubikon yok: sessiz temizlik sayaci, oyuncuya saldirmaz
		e["desp"] = float(e.get("desp", float(C.clean_after))) - dt
		if float(e["desp"]) <= 0.0:
			_kill_npc(w, e, 0, true)
			return
		var hp_pos: Vector3 = e.get("home_pos", e.pos)
		e.t = float(e.t) - dt
		if float(e.t) <= 0.0:
			e.t = randf_range(2.0, 5.0)
			var to_home: Vector3 = hp_pos - (e.pos as Vector3)
			to_home.y = 0.0
			e.v = to_home.normalized() if to_home.length() > 0.5 else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		var spd0: float = float(d.spd) * DOData.S * DOData.SPEEDMULT * 0.5
		e.pos = (e.pos as Vector3) + (e.v as Vector3) * spd0 * dt
		_face(e, e.v as Vector3, dt)
		return
	var hpos: Vector3 = home.pos
	var leash_u: float = float(C.leash) * DOData.S
	var tp: Dictionary = _guard_target(w, home)
	if tp.is_empty():
		return
	var pflat: Vector3 = (tp.pos as Vector3) - hpos
	pflat.y = 0.0
	if pflat.length() > leash_u:
		# Oyuncu cok uzaklasti: Cubikona don, kisa sure sonra sessizce yok ol
		e["far_t"] = float(e.get("far_t", 0.0)) + dt
		if float(e["far_t"]) >= float(C.leash_despawn):
			_kill_npc(w, e, 0, true)
			return
		var back: Vector3 = hpos - (e.pos as Vector3)
		back.y = 0.0
		if back.length() > 1.0:
			var spd_b: float = float(d.spd) * DOData.S * DOData.SPEEDMULT * 0.8
			e.pos = (e.pos as Vector3) + back.normalized() * spd_b * 1.15 * dt
			_face(e, back, dt)
		return
	e["far_t"] = 0.0
	# SURU: Cubikon etrafinda yorunge
	var ang: float = float(e.get("orb_a", 0.0)) + float(e.get("orb_w", 0.5)) * dt
	e["orb_a"] = ang
	var orr: float = float(e.get("orb_r", float(C.swarm_r_min)))
	var slot: Vector3 = hpos + Vector3(cos(ang) * orr, 0.0, sin(ang) * orr)
	var to_slot: Vector3 = slot - (e.pos as Vector3)
	to_slot.y = 0.0
	var spd: float = float(d.spd) * DOData.S * DOData.SPEEDMULT * 0.8
	var stp: float = minf(to_slot.length(), spd * 1.15 * dt)
	if to_slot.length() > 0.001:
		e.pos = (e.pos as Vector3) + to_slot.normalized() * stp
	var goff: Vector3 = (e.pos as Vector3) - hpos
	goff.y = 0.0
	if goff.length() > leash_u:
		var gcl: Vector3 = goff.normalized() * leash_u
		e.pos = Vector3(hpos.x + gcl.x, (e.pos as Vector3).y, hpos.z + gcl.z)
	var L: float = ((tp.pos as Vector3) - (e.pos as Vector3)).length()
	var engaged: bool = pflat.length() <= float(C.engage_range) * DOData.S and L <= float(C.guard_range) * DOData.S
	if engaged and not bool(tp.ut) and not bool(tp.in_safe):
		_face(e, (tp.pos as Vector3) - (e.pos as Vector3), dt)
		var cd_prev: float = float(e.cd)
		e.cd = cd_prev - dt
		var lock_ok: bool = clock >= float(home.get("guard_fire_t", 0.0))
		if float(e.cd) <= 0.0 and lock_ok:
			e.cd = DOData.rearm_cd(cd_prev, float(e.cd), dt, DOData.NPC_FIRE_INTERVAL)
			home["guard_fire_t"] = clock + float(C.fire_lock)
			_emit_fire(w, e, int(tp.id), DOData.npc_shot_damage(d))   # TEK atis: tek hasar degeri (sunucu belirler)
	else:
		_face(e, to_slot, dt)
	_clamp_pos(w, e)
# ------------------------------------------------------------------ GEMI TAMIRI (patlayan / hasarli gemi)
# Ucret SUNUCUDA hesaplanir ve DB'den atomik dusulur: Phoenix ucretsiz, diger gemiler 500 Uridium.
func on_repair(peer: int, tx_id: String) -> void:
	if not players.has(peer) or _is_ghost(players[peer]):
		return
	var p: Dictionary = players[peer]
	tx_id = tx_id.strip_edges()
	var acct_id: int = int(p.get("account_id", 0))
	var cur_uri: int = int(p.get("_sv_uri", 0))
	if acct_id <= 0 or tx_id.length() < 4 or tx_id.length() > 64:
		_to(peer, "s_repair_result", [false, "gecersiz_istek", tx_id, 0, cur_uri])
		return
	if not bool(p.get("wrecked", false)) and float(p.hp) >= float(p.mhp) - 1.0:
		_to(peer, "s_repair_result", [false, "tamir_gerekmiyor", tx_id, 0, cur_uri])
		return
	var resp: Dictionary = db_send("repair_ship", {"account_id": acct_id, "tx_id": tx_id})
	if resp.has("ok") and resp.get("ok", false):
		p["_sv_uri"] = int(resp.get("new_uri", cur_uri))
		p["wrecked"] = false
		p.hp = p.mhp
		p.sh = p.msh
		print("[SUNUCU] tamir: account_id=%d gemi=%s ucret=%d Uridium" % [acct_id, str(resp.get("ship", "?")), int(resp.get("cost", 0))])
		_to(peer, "s_repair_result", [true, "", tx_id, int(resp.get("cost", 0)), int(p["_sv_uri"])])
	else:
		var err: String = str(resp.get("error", "bilinmeyen"))
		print("[SUNUCU] tamir basarisiz: account_id=%d hata=%s" % [acct_id, err])
		_to(peer, "s_repair_result", [false, err, tx_id, int(resp.get("cost", 0)), int(resp.get("new_uri", cur_uri))])


# ------------------------------------------------------------------ HESAP AYARLARI: nick / sirket degistirme
func _wait_text(sec: int) -> String:
	if sec >= 86400:
		return "%d gün" % int(ceil(float(sec) / 86400.0))
	if sec >= 3600:
		return "%d saat" % int(ceil(float(sec) / 3600.0))
	return "%d dakika" % maxi(1, int(ceil(float(sec) / 60.0)))


func _account_err_text(resp: Dictionary) -> String:
	match str(resp.get("error", "")):
		"gecersiz_isim": return "İsim 3-16 karakter olmalı; yalnızca harf, rakam, _ ve - kullanılabilir."
		"isim_kullanimda": return "Bu isim başka bir oyuncu tarafından kullanılıyor."
		"ayni_isim": return "Bu zaten şu anki adın."
		"gecersiz_sirket": return "Geçersiz şirket."
		"ayni_sirket": return "Zaten bu şirkettesin."
		"bekleme": return "Tekrar değiştirmek için %s beklemelisin." % _wait_text(int(resp.get("kalan_sn", 0)))
		"busy_retry", "db_baglanti_yok": return "Sunucu meşgul, biraz sonra tekrar dene."
	return "İşlem yapılamadı."


# Isim / sirket degisince oturum kapatilir (istemci yeniden giris yapar). save_pos=false: eski haritadaki konum
# DB'ye yazilmaz (sirket degisiminde yeni ev haritasi korunur). Hayalet gemi birakilmaz (force_remove).
func _account_relogin(peer: int, reason: String, save_pos: bool) -> void:
	if not players.has(peer):
		return
	if not save_pos:
		players[peer].pos = Vector3.ZERO
	net.callv("rpc_id", [peer, "s_disconnect", reason])
	on_disconnect(peer, true, true)
	var mp = net.multiplayer.multiplayer_peer
	if mp != null:
		mp.disconnect_peer(peer)


func on_change_callsign(peer: int, new_name: String) -> void:
	if not players.has(peer) or _is_ghost(players[peer]):
		return
	var p: Dictionary = players[peer]
	if _in_combat(p):
		_to(peer, "s_account_result", ["callsign", false, "Savaş sırasında isim değiştirilemez.", ""])
		return
	var resp: Dictionary = db_send("change_callsign", {"account_id": int(p.get("account_id", 0)), "callsign": new_name.strip_edges()})
	if resp.has("ok") and resp.get("ok", false):
		print("[SUNUCU] nick degisti: account_id=%d -> %s" % [int(p.account_id), str(resp.callsign)])
		_to(peer, "s_account_result", ["callsign", true, "", str(resp.callsign)])
		_account_relogin(peer, "Çağrı adın değişti. Yeni adınla yeniden giriş yap.", true)
	else:
		_to(peer, "s_account_result", ["callsign", false, _account_err_text(resp), ""])


func on_change_faction(peer: int, faction: int) -> void:
	if not players.has(peer) or _is_ghost(players[peer]):
		return
	var p: Dictionary = players[peer]
	if _in_combat(p):
		_to(peer, "s_account_result", ["faction", false, "Savaş sırasında şirket değiştirilemez.", ""])
		return
	var resp: Dictionary = db_send("change_faction", {"account_id": int(p.get("account_id", 0)), "faction": faction})
	if resp.has("ok") and resp.get("ok", false):
		print("[SUNUCU] sirket degisti: account_id=%d -> %d" % [int(p.account_id), faction])
		_to(peer, "s_account_result", ["faction", true, "", str(faction)])
		_account_relogin(peer, "Şirketin değişti. Yeni şirketinin üssünde yeniden giriş yap.", false)
	else:
		_to(peer, "s_account_result", ["faction", false, _account_err_text(resp), ""])


# ------------------------------------------------------------------ MARKET ALIMI (istemciden gelen istek)
func on_purchase_item(peer: int, item_id: String, quantity: int, tx_id: String) -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	var acct_id: int = int(p.get("account_id", 0))
	if acct_id <= 0:
		net.callv("rpc_id", [peer, "s_purchase_result", false, "no_account", tx_id, 0, 0])
		return
	var resp: Dictionary = db_send("purchase_item", {
		"account_id": acct_id,
		"item_id": item_id,
		"quantity": quantity,
		"tx_id": tx_id,
		# Fiyati sunucu (server_db.py katalogu) kendisi hesaplar; istemciden fiyat alinmaz.
	})
	if resp.has("ok") and resp.get("ok", false):
		# Bellekteki sunucu kopyasini guncelle
		p["_sv_cr"] = int(resp.get("new_cr", p.get("_sv_cr", 0)))
		p["_sv_uri"] = int(resp.get("new_uri", p.get("_sv_uri", 0)))
		if str(resp.get("kind", "")) == "ship" and not (item_id in p.get("_sv_owned", [])):
			p["_sv_owned"].append(item_id)   # sunucu gemi dogrulamasi icin sahip listesi
		# Mermi/envanter odulunu istemciye bildir
		net.callv("rpc_id", [peer, "s_purchase_result", true, "", tx_id, int(resp.get("new_cr", 0)), int(resp.get("new_uri", 0))])
	else:
		var err: String = str(resp.get("error", "bilinmeyen hata"))
		print("[SUNUCU] market alimi basarisiz: account_id=%d, item=%s, hata=%s" % [acct_id, item_id, err])
		net.callv("rpc_id", [peer, "s_purchase_result", false, err, tx_id, 0, 0])
