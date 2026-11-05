extends Node
# NOVAGATE - AG KATMANI (autoload: "Net")
# Bu betik hem sunucuda hem istemcide ayni yolda (/root/Net) calisir; RPC'ler burada tanimlidir.
#   Sunucu : godot --headless --path <proje> -- --server --port=7777
#   Istemci: oyunun ana menusunde "Cok oyunculu" kutusunu isaretle, sunucu adresini yaz.

const PROTO := 9   # 9: genel olay kanali (c_event/s_event) + auth surum kapisi; 8: tamir (c_repair/s_repair_result), nick/sirket degistirme (c_change_*/s_account_result); 7: grup sistemi + s_npc_reward RPC; 6: grup sistemi (c_g_* / s_g_*), sirket + grup sohbeti, paylasimli NPC odulu;  5: sunucu otoriter guvenli bolge + kapi dogrulamasi; 4: bonus kutular
# ---- OTOMATIK BAGLANTI ----------------------------------------------------------
# Yayin sunucusunun adresi (ornek: "54.x.x.x:7777" veya "oyun.alanadi.com:7777").
# Doluysa: giris ekranindaki "Cok oyunculu" kutusu ve adres alani gizlenir, oyun giris yapinca
# PC'de ve telefonda OTOMATIK bu sunucuya baglanir. Bos birakirsan eski elle adres girme calisir.
#
# GELISTIRME / YAYIN ayrimi:
#   - Yayin istemcisi (export edilen release build) do grup: PROD_SERVER_ADDR kullanilir.
#   - Editorde calisirken NOVAGATE_SERVER ortam degiskeni tanimliysa o adres kullanilir
#     (ornek  local test icin:  set NOVAGATE_SERVER=127.0.0.1:7777).
#     Tanimli degilse editorde elle adres girme alanini kullan (AWS adresi on-doldurulur).
# AWS yayin sunucusu (us-east-2, t3.micro, Elastic IP)
const PROD_SERVER_ADDR := "18.117.15.199:7777"
var SERVER_ADDR: String = PROD_SERVER_ADDR
const DEFAULT_PORT := 7777
# Yayin kapasitesi: hedef 100 eszamanli oyuncu; limit 32 -> 128 cikarildi.
# NOT: 128 eszamanli baglanti ENet tarafinda kaynak duzeyinde desteklidir; bant genisligi
# ve performans dogrulamasi AWS'de yuk testiyle yapilacak (onaylanmis sonuc yok).
const MAX_PEERS := 128
const NetServer := preload("res://net_server.gd")
const NetGame := preload("res://net_game.gd")

# ---- KIMLIK DOGRULAMA (TLS) ------------------------------------------------
# Auth servisi: https://18.117.15.199:8444/login (Production AWS)
# Gelistirme icin: set NOVAGATE_AUTH_HOST=127.0.0.1
const AUTH_HOST := "18.117.15.199"
const AUTH_HTTPS_PORT := 8444
var session_token: String = ""    # auth_service'tan alinan oturum jetonu
var account_id: int = 0           # sunucu tarafindan dogrulanmis hesap kimligi
var auth_http_request: HTTPRequest  # TLS login icin
var tls_opts: TLSOptions            # sertifika sabitleme (self-signed auth sertifikasi)

var is_server: bool = false     # bu surec dedicated sunucu mu
var online: bool = false        # istemci: sunucuya bagli ve dunyada
var my_id: int = 0
var last_error: String = ""
var srv = null                  # NetServer (yalnizca sunucuda)
var gm = null                   # NetGame (yalnizca istemcide)
var game = null                 # main.gd
var _join_state: int = 0        # 0 bekliyor, 1 basarili, -1 reddedildi
var _join_msg: String = ""
var _state_t: float = 0.0


func _ready() -> void:
	# Gelistirme istemcisinde yayin adresini NOVAGATE_SERVER ile ezebilirsin
	# (local test: set NOVAGATE_SERVER=127.0.0.1:7777).
	var env_addr := OS.get_environment("NOVAGATE_SERVER")
	if env_addr != "":
		SERVER_ADDR = env_addr
	multiplayer.server_disconnected.connect(_on_server_lost)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.peer_connected.connect(_on_peer_joined)
	# TLS login icin HTTPRequest (auth_service.py HTTPS endpoint)
	auth_http_request = HTTPRequest.new()
	add_child(auth_http_request)
	auth_http_request.request_completed.connect(_on_auth_http_completed)
	# Self-signed auth sertifikasini guvenilir say (sabitleme). Alan adi: novagate.local
	var _cert := X509Certificate.new()
	if _cert.load("res://auth_cert_public.crt") == OK:
		tls_opts = TLSOptions.client(_cert, "novagate.local")
		auth_http_request.set_tls_options(tls_opts)
	else:
		push_error("[NET] auth_cert_public.crt yuklenemedi (export filtresine *.crt eklendi mi?)")
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		var port: int = DEFAULT_PORT
		for a in args:
			if str(a).begins_with("--port="):
				port = int(str(a).substr(7))
		_start_server(port)


# ------------------------------------------------------------------ TLS KIMLIK DOGRULAMA
func login_via_tls(username: String, password: String) -> void:
	"""
	auth_service.py HTTPS endpoint ile TLS guvenli giris yapar.
	Sonuc _on_auth_http_completed ile geri doner.
	"""
	last_error = ""
	var url := "https://%s:%d/login" % [AUTH_HOST, AUTH_HTTPS_PORT]
	var body: String = JSON.stringify({"username": username, "password": password, "proto": PROTO})
	var headers: PackedStringArray = ["Content-Type: application/json"]
	auth_http_request.request(url, headers, HTTPClient.METHOD_POST, body)


# Oyun-ici sifre degistirme. cb(ok: bool, error: String) ile sonuc doner. Eski sifre sunucuda dogrulanir.
func change_password_via_tls(username: String, old_pw: String, new_pw: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	if tls_opts != null:
		req.set_tls_options(tls_opts)
	req.timeout = 10.0
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			cb.call(false, "Sunucuya ulaşılamadı.")
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			cb.call(false, "Geçersiz sunucu yanıtı.")
			return
		if bool(data.get("ok", false)):
			cb.call(true, "")
			return
		match str(data.get("error", "")):
			"eski_sifre_yanlis": cb.call(false, "Mevcut şifre yanlış.")
			"sifre_en_az_4_karakter": cb.call(false, "Yeni şifre en az 4 karakter olmalı.")
			"yeni_sifre_ayni": cb.call(false, "Yeni şifre mevcut şifreyle aynı olamaz.")
			"cok_fazla_deneme": cb.call(false, "Çok fazla hatalı deneme. 10 dakika sonra tekrar dene.")
			_: cb.call(false, "Şifre değiştirilemedi.")
	)
	var url := "https://%s:%d/change_password" % [AUTH_HOST, AUTH_HTTPS_PORT]
	var payload: String = JSON.stringify({"username": username, "old_password": old_pw, "new_password": new_pw})
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if req.request(url, headers, HTTPClient.METHOD_POST, payload) != OK:
		req.queue_free()
		cb.call(false, "İstek gönderilemedi.")


func _on_auth_http_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""
	TLS login HTTP cevabini isler.
	Basariliysa session_token'i saklar ve main.gd'e bildirir.
	"""
	if result != HTTPRequest.RESULT_SUCCESS:
		last_error = "TLS baglanti hatasi: %d" % result
		if game != null:
			game._on_auth_result(false, last_error)
		return

	if response_code != 200:
		last_error = "Sunucu hatasi: %d" % response_code
		if game != null:
			game._on_auth_result(false, last_error)
		return

	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if not data.has("ok") or data["ok"] == false:
		last_error = str(data.get("error", "bilinmeyen hata"))
		if game != null:
			game._on_auth_result(false, last_error)
		return

	session_token = str(data.get("session_token", ""))
	account_id = int(data.get("account_id", 0))
	var callsign: String = str(data.get("callsign", "Gezgin"))
	var faction: int = int(data.get("faction", 1))
	print("[NET] TLS giris basarili: account_id=%d, callsign=%s, faction=%d" % [account_id, callsign, faction])

	if game != null:
		game._on_auth_result(true, "", account_id, callsign, faction, session_token)


# ------------------------------------------------------------------ ENET TOKEN BAGLANTISI
func attach_token(token: String) -> void:
	"""
	Kimlik dogrulanmis jetonu ENet sunucusuna gonderir.
	c_attach_token RPC ile sunucu token'i dogrular ve oyuncu verilerini yukler.
	"""
	print("[ISTEMCI] attach_token cagrildi, online=%s" % online)
	if not online:
		last_error = "ENet baglantisi yok"
		print("[ISTEMCI] Hata: ENet baglantisi yok")
		if game != null:
			game._on_attach_result(false, "Oyun sunucusuna baglanilamadi.")
		return
	print("[ISTEMCI] c_attach_token RPC gonderiliyor, token_prefix=%s" % token.substr(0, 20))
	rpc_id(1, "c_attach_token", token)
	print("[ISTEMCI] c_attach_token RPC gonderildi")


# ------------------------------------------------------------------ SUNUCU
func _start_server(port: int) -> void:
	print("[SUNUCU] _start_server cagrildi: port=%d" % port)
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, MAX_PEERS)
	if err != OK:
		push_error("[SUNUCU] Port %d acilamadi (hata %d). Baska bir sunucu aciksa kapat." % [port, err])
		print("[SUNUCU] Port %d acilamadi, hata kodu: %d" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	Engine.max_fps = 30
	srv = NetServer.new(self)
	print("[SUNUCU] ENetMultiplayerPeer olusturuldu, port %d acildi" % port)
	print("==============================================")
	print(" NOVAGATE SUNUCUSU calisiyor  |  UDP port %d" % port)
	print(" Kapatmak icin pencereyi kapat / Ctrl+C")
	print("==============================================")


func _process(dt: float) -> void:
	if is_server and srv != null:
		srv.tick(dt)


# Sunucu: internet kopmasi daha hizli anlasilsin (varsayilan ~30 sn); sure DOData.NET_PEER_TIMEOUT_MAX_MS ile ayarlanir.
func _on_peer_joined(id: int) -> void:
	if not is_server:
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var pp = enet.get_peer(id)
	if pp != null:
		pp.set_timeout(32, 5000, DOData.NET_PEER_TIMEOUT_MAX_MS)


func _on_peer_gone(id: int) -> void:
	if is_server and srv != null:
		srv.on_disconnect(id)


# ------------------------------------------------------------------ ISTEMCI: baglan + katil
func attach(main_node) -> void:
	game = main_node
	gm = NetGame.new(main_node, self)


func connect_and_join(addr: String, info: Dictionary) -> bool:
	last_error = ""
	var host: String = addr.strip_edges()
	var port: int = DEFAULT_PORT
	var ci: int = host.rfind(":")
	if ci >= 0:
		port = int(host.substr(ci + 1))
		host = host.substr(0, ci)
	if host == "":
		host = "127.0.0.1"
	disconnect_from_server()
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host, port)
	if err != OK:
		last_error = "Baglanti baslatilamadi (hata %d)." % err
		return false
	multiplayer.multiplayer_peer = peer
	var t: float = 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		last_error = "Sunucuya ulasilamadi (%s:%d). Sunucu acik mi? Port/guvenlik duvari?" % [host, port]
		disconnect_from_server()
		return false
	my_id = multiplayer.get_unique_id()
	_join_state = 0
	_join_msg = ""
	rpc_id(1, "c_join", PROTO, str(info.get("name", "Gezgin")), int(info.get("faction", 1)), str(info.get("ship", "phoenix")))
	t = 0.0
	while _join_state == 0 and t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if _join_state != 1:
		last_error = _join_msg if _join_msg != "" else "Sunucu yanit vermedi."
		disconnect_from_server()
		return false
	online = true
	return true


func connect_only(addr: String) -> bool:
	"""
	Sadece ENet baglantisi kurar, c_join cagirmaz.
	Token dogrulamasina hazirlik icin kullanilir.
	"""
	last_error = ""
	var host: String = addr.strip_edges()
	var port: int = DEFAULT_PORT
	var ci: int = host.rfind(":")
	if ci >= 0:
		port = int(host.substr(ci + 1))
		host = host.substr(0, ci)
	if host == "":
		host = "127.0.0.1"
	disconnect_from_server()
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host, port)
	if err != OK:
		last_error = "Baglanti baslatilamadi (hata %d)." % err
		return false
	multiplayer.multiplayer_peer = peer
	var t: float = 0.0
	while peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		last_error = "Sunucuya ulasilamadi (%s:%d). Sunucu acik mi? Port/guvenlik duvari?" % [host, port]
		disconnect_from_server()
		return false
	my_id = multiplayer.get_unique_id()
	_join_state = 0
	_join_msg = ""
	online = true
	return true


func disconnect_from_server() -> void:
	online = false
	if multiplayer.multiplayer_peer != null and not is_server:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if gm != null:
		gm.reset_map()
		gm.clear_group()


func _on_server_lost() -> void:
	if is_server:
		return
	online = false
	multiplayer.multiplayer_peer = null
	if game != null and is_instance_valid(game):
		game.net_lost()


# ------------------------------------------------------------------ ISTEMCI -> SUNUCU yardimcilari
func enter_map(map_name: String, x: float, z: float) -> void:
	if online:
		send_ship(str(game.SV.get("ship", "phoenix")) if game != null and not game.SV.is_empty() else "phoenix")
		rpc_id(1, "c_map", map_name, x, z)


# Gemi degisince (hangar) ya da haritaya girerken guncel gemi modeli sunucuya bildirilir;
# boylece diger oyuncular gemini DOGRU modelle gorur.
func send_ship(ship: String) -> void:
	if online:
		rpc_id(1, "c_ship", ship)


func send_repair(tx_id: String) -> void:
	if online:
		rpc_id(1, "c_repair", tx_id)


func send_change_callsign(new_name: String) -> void:
	if online:
		rpc_id(1, "c_change_callsign", new_name)


func send_change_faction(faction: int) -> void:
	if online:
		rpc_id(1, "c_change_faction", faction)


# Kapidan atlama istegi: izni SUNUCU verir (s_jump_result). Istemci kendi basina harita degistiremez.
func send_jump(to_map: String) -> void:
	if online:
		rpc_id(1, "c_jump", to_map)


func send_state(x: float, z: float, yaw: float, hp: float, mhp: float, sh: float, msh: float, spd: float, ut: bool) -> void:
	if online:
		rpc_id(1, "c_state", x, z, yaw, hp, mhp, sh, msh, spd, ut)


func send_hit_npc(uid: int, dmg: float, mode: int = 0) -> void:
	if online:
		rpc_id(1, "c_hit_npc", uid, dmg, mode)


func send_hit_player(peer: int, dmg: float) -> void:
	if online:
		rpc_id(1, "c_hit_player", peer, dmg)


func send_fire(kind: int, ref: int, nb: int, ammo: String) -> void:
	if online:
		rpc_id(1, "c_fire", kind, ref, nb, ammo)


# Ozel esya (extra) kullanildi: sunucu ayni haritadaki diger oyunculara efekti yayinlar.
func send_extra(idx: int) -> void:
	if online and idx >= 0:
		rpc_id(1, "c_extra", idx)


func send_drones(form: String, drn: Array) -> void:
	if online:
		rpc_id(1, "c_drones", form, drn)


func send_died(killer: int) -> void:
	if online:
		rpc_id(1, "c_died", killer)


func send_box_take(id: int) -> void:
	if online:
		rpc_id(1, "c_box_take", id)


func send_purchase_item(item_id: String, qty: int, tx_id: String) -> void:
	if online:
		rpc_id(1, "c_purchase_item", item_id, qty, tx_id)


func send_select_ammo(ammo: String) -> void:
	if online:
		rpc_id(1, "c_select_ammo", ammo)


# Ekipman/konfigurasyon degisince (lazer, jenerator, droid, formasyon, aktif konfig) sunucuya kaydettir.
# loads_json = o geminin [konfig1, konfig2] listesi. Sunucu dogrular; suzulmus hali s_loadout_result ile doner.
func send_loadout(ship: String, loads_json: String, cfgi: int, seq: int) -> void:
	if online:
		rpc_id(1, "c_save_loadout", ship, loads_json, cfgi, seq)


# Yetenek agaci islemi: op = "logdisk" (arg=adet) | "skill" (arg=yetenek id) | "reset". Sunucu dogrular, sonuc s_skill_result ile gelir.
func send_skill_op(op: String, arg: String) -> void:
	if online:
		rpc_id(1, "c_skill_op", op, arg)


# Alt hizli slot cubugu (1-0 tuslari) sunucuda kalici saklanir; girista settings.quickbar olarak geri gelir.
func send_quickbar(qb_json: String) -> void:
	if online:
		rpc_id(1, "c_save_quickbar", qb_json)


# ch: 0 genel, 1 sirket, 2 grup
func send_chat(text: String, ch: int = 0) -> void:
	if online:
		rpc_id(1, "c_chat", text, ch)


func send_group_invite(peer: int) -> void:
	if online:
		rpc_id(1, "c_g_invite", peer)


func send_group_answer(accept: bool) -> void:
	if online:
		rpc_id(1, "c_g_answer", accept)


func send_group_leave() -> void:
	if online:
		rpc_id(1, "c_g_leave")


func send_group_kick(peer: int) -> void:
	if online:
		rpc_id(1, "c_g_kick", peer)


# ================================================================== RPC: istemci -> sunucu
@rpc("any_peer", "call_remote", "reliable")
func c_attach_token(token: String) -> void:
	"""
	Istemcinin TLS ile aldigi session token'i sunucu tarafinda dogrular.
	Basariliysa peer_id <-> account_id eslemesi olusturulur.
	"""
	if not is_server or srv == null:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var r: Array = srv.on_attach_token(id, token)
	rpc_id(id, "s_attach_result", bool(r[0]), str(r[1]), int(r[2]), str(r[3]), int(r[4]), str(r[5]))

@rpc("any_peer", "call_remote", "reliable")
func c_join(proto: int, nm: String, faction: int, ship: String) -> void:
	if not is_server or srv == null:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var r: Array = srv.on_join(id, proto, nm, faction, ship)
	rpc_id(id, "s_join_result", bool(r[0]), str(r[1]))


@rpc("any_peer", "call_remote", "reliable")
func c_ship(ship: String) -> void:
	if is_server and srv != null:
		srv.on_ship(multiplayer.get_remote_sender_id(), ship)   # tum dogrulama (savas, sahiplik, police) sunucuda


@rpc("any_peer", "call_remote", "reliable")
func c_map(map_name: String, x: float, z: float) -> void:
	if is_server and srv != null:
		srv.on_map(multiplayer.get_remote_sender_id(), map_name, x, z)


@rpc("any_peer", "call_remote", "reliable")
func c_jump(to_map: String) -> void:
	if is_server and srv != null:
		srv.on_jump(multiplayer.get_remote_sender_id(), to_map)


@rpc("any_peer", "call_remote", "unreliable")
func c_state(x: float, z: float, yaw: float, hp: float, mhp: float, sh: float, msh: float, spd: float, ut: bool) -> void:
	if is_server and srv != null:
		srv.on_state(multiplayer.get_remote_sender_id(), x, z, yaw, hp, mhp, sh, msh, spd, ut)


@rpc("any_peer", "call_remote", "reliable")
func c_hit_npc(uid: int, dmg: float, mode: int) -> void:
	if is_server and srv != null:
		srv.on_hit_npc(multiplayer.get_remote_sender_id(), uid, dmg, mode)


@rpc("any_peer", "call_remote", "reliable")
func c_hit_player(peer: int, dmg: float) -> void:
	if is_server and srv != null:
		srv.on_hit_player(multiplayer.get_remote_sender_id(), peer, dmg)


@rpc("any_peer", "call_remote", "reliable")
func c_fire(kind: int, ref: int, nb: int, ammo: String) -> void:
	if is_server and srv != null:
		srv.on_fire_vis(multiplayer.get_remote_sender_id(), kind, ref, nb, ammo)


@rpc("any_peer", "call_remote", "reliable")
func c_drones(form: String, drn: Array) -> void:
	if is_server and srv != null:
		srv.on_drones(multiplayer.get_remote_sender_id(), form, drn)


@rpc("any_peer", "call_remote", "reliable")
func c_died(killer: int) -> void:
	if is_server and srv != null:
		srv.on_died(multiplayer.get_remote_sender_id(), killer)


@rpc("any_peer", "call_remote", "reliable")
func c_box_take(id: int) -> void:
	if is_server and srv != null:
		srv.on_box_take(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String, ch: int) -> void:
	if is_server and srv != null:
		srv.on_chat(multiplayer.get_remote_sender_id(), text, ch)


# ---- GRUP: istemci -> sunucu
@rpc("any_peer", "call_remote", "reliable")
func c_g_invite(target: int) -> void:
	if is_server and srv != null:
		srv.on_g_invite(multiplayer.get_remote_sender_id(), target)


@rpc("any_peer", "call_remote", "reliable")
func c_g_answer(accept: bool) -> void:
	if is_server and srv != null:
		srv.on_g_answer(multiplayer.get_remote_sender_id(), accept)


@rpc("any_peer", "call_remote", "reliable")
func c_g_leave() -> void:
	if is_server and srv != null:
		srv.on_g_leave(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func c_g_kick(target: int) -> void:
	if is_server and srv != null:
		srv.on_g_kick(multiplayer.get_remote_sender_id(), target)


# ---- ACIK ARTIRMA (saatlik): istemci -> sunucu
@rpc("any_peer", "call_remote", "reliable")
func c_auc_open(pending: Array) -> void:
	if is_server and srv != null:
		srv.auc.on_open(multiplayer.get_remote_sender_id(), pending)


@rpc("any_peer", "call_remote", "reliable")
func c_auc_bid(op: int, lot: int, amount: int, paid: int) -> void:
	if is_server and srv != null:
		srv.auc.on_bid(multiplayer.get_remote_sender_id(), op, lot, amount, paid)


@rpc("any_peer", "call_remote", "reliable")
func c_auc_buy(op: int, lot: int, paid_uri: int) -> void:
	if is_server and srv != null:
		srv.auc.on_buy(multiplayer.get_remote_sender_id(), op, lot, paid_uri)


@rpc("any_peer", "call_remote", "reliable")
func c_auc_ack(ids: Array) -> void:
	if is_server and srv != null:
		srv.auc.on_ack(multiplayer.get_remote_sender_id(), ids)


# ================================================================== RPC: sunucu -> istemci
@rpc("authority", "call_remote", "reliable")
func s_attach_result(ok: bool, msg: String, account_id: int, callsign: String, faction: int, player_state_json: String) -> void:
	"""
	Sunucu tarafindan token dogrulama sonucu.
	Basariliysa oyuncu verileri istemciye gonderilir.
	"""
	_join_msg = msg
	_join_state = 1 if ok else -1
	if ok and game != null:
		game._on_attach_result(true, "", account_id, callsign, faction, player_state_json)
	elif not ok and game != null:
		game._on_auth_result(false, msg)


# Sunucu oyuncuyu atarken (ban vb.) gonderir. Bu RPC eskiden tanimli degildi: sunucu cagirinca hata veriyordu.
@rpc("authority", "call_remote", "reliable")
func s_disconnect(reason: String) -> void:
	if is_server:
		return
	last_error = reason
	online = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if game != null and is_instance_valid(game):
		game.net_lost(reason)


@rpc("authority", "call_remote", "reliable")
func s_join_result(ok: bool, msg: String) -> void:
	_join_msg = msg
	_join_state = 1 if ok else -1


@rpc("authority", "call_remote", "reliable")
func s_map_init(map_name: String, npc_list: Array, player_list: Array) -> void:
	if gm != null and online:
		gm.on_map_init(map_name, npc_list, player_list)


# Sunucunun hesapladigi GERCEK koruma: 0 yok, 1 ust, 2 kapi, 3 gecici gecis korumasi (safe_zone.gd)
@rpc("authority", "call_remote", "reliable")
func s_prot(kind: int) -> void:
	if gm != null and online:
		gm.on_prot(kind)


@rpc("authority", "call_remote", "reliable")
func s_jump_result(ok: bool, dest: String, note: String) -> void:
	if gm != null and online:
		gm.on_jump_result(ok, dest, note)


@rpc("authority", "call_remote", "reliable")
func s_boxes(map_name: String, list: Array) -> void:
	if gm != null and online:
		gm.on_boxes(map_name, list)


@rpc("authority", "call_remote", "reliable")
func s_box_new(id: int, x: float, z: float) -> void:
	if gm != null and online:
		gm.on_box_new(id, x, z)


@rpc("authority", "call_remote", "reliable")
func s_box_gone(id: int, taker: int) -> void:
	if gm != null and online:
		gm.on_box_gone(id, taker)


# Sunucunun DB'ye yazdigi kutu odulu (tek dogru kaynak).
@rpc("authority", "call_remote", "reliable")
func s_box_reward(id: int, info: Dictionary) -> void:
	if gm != null and online:
		gm.on_box_reward(id, info)


@rpc("authority", "call_remote", "reliable")
func s_pjoin(info: Array) -> void:
	if gm != null and online:
		gm.add_player(info)


@rpc("authority", "call_remote", "reliable")
func s_pleave(peer: int) -> void:
	if gm != null and online:
		gm.remove_player(peer)


@rpc("authority", "call_remote", "reliable")
func s_pdrones(peer: int, form: String, drn: Array) -> void:
	if gm != null and online:
		gm.on_player_drones(peer, form, drn)


@rpc("authority", "call_remote", "unreliable")
func s_psnap(arr: Array) -> void:
	if gm != null and online:
		gm.on_player_snap(arr)


@rpc("authority", "call_remote", "unreliable")
func s_npc_snap(arr: PackedFloat32Array) -> void:
	if gm != null and online:
		gm.on_npc_snap(arr)


@rpc("authority", "call_remote", "reliable")
func s_npc_spawn(info: Array) -> void:
	if gm != null and online:
		gm.add_npc(info)


@rpc("authority", "call_remote", "reliable")
func s_npc_dead(uid: int, killer: int, silent: bool, share_n: int) -> void:
	if gm != null and online:
		gm.on_npc_dead(uid, killer, silent, share_n)


# Sunucunun DB'ye yazdigi NPC odulu (cr/uri/xp/hon/sep + kesin yeni bakiyeler).
@rpc("authority", "call_remote", "reliable")
func s_npc_reward(info: Dictionary) -> void:
	if gm != null and online:
		gm.on_npc_reward(info)


# Gruptaki oyuncu NPC'yi oldurmediyse bile odulun payini alir (share_n = oduller kac kisiye bolundu)
@rpc("authority", "call_remote", "reliable")
func s_npc_share(npc_id: String, share_n: int) -> void:
	if gm != null and online:
		gm.on_npc_share(npc_id, share_n)


@rpc("authority", "call_remote", "reliable")
func s_g_invite(from_peer: int, from_name: String) -> void:
	if gm != null and online:
		gm.on_g_invite(from_peer, from_name)


# members: [[peer, ad, harita], ...]  (bos = grupta degilsin)
@rpc("authority", "call_remote", "reliable")
func s_g_state(leader: int, members: Array) -> void:
	if gm != null and online:
		gm.on_g_state(leader, members)


@rpc("authority", "call_remote", "reliable")
func s_npc_fire(uid: int, target_peer: int, dmg: float) -> void:
	if gm != null and online:
		gm.on_npc_fire(uid, target_peer, dmg)


@rpc("authority", "call_remote", "reliable")
func s_fire(shooter: int, kind: int, ref: int, nb: int, ammo: String) -> void:
	if gm != null and online:
		gm.on_fire_vis(shooter, kind, ref, nb, ammo)


@rpc("authority", "call_remote", "reliable")
func s_hurt(attacker: int, dmg: float) -> void:
	if gm != null and online:
		gm.on_hurt(attacker, dmg)


@rpc("authority", "call_remote", "reliable")
func s_kill(text: String) -> void:
	if gm != null and online:
		gm.on_kill_msg(text)


@rpc("authority", "call_remote", "reliable")
func s_pvp_reward(victim: int, info: Dictionary = {}) -> void:
	if gm != null and online:
		gm.on_pvp_reward(victim, info)


@rpc("authority", "call_remote", "reliable")
func s_chat(nm: String, faction: int, text: String, ch: int) -> void:
	if gm != null and online:
		gm.on_chat(nm, faction, text, ch)


# ---- ACIK ARTIRMA (saatlik): sunucu -> istemci
@rpc("authority", "call_remote", "reliable")
func s_auc_state(snap: Dictionary) -> void:
	if gm != null and online and gm.auc != null:
		gm.auc.on_state(snap)


@rpc("authority", "call_remote", "reliable")
func s_auc_mail(arr: Array) -> void:
	if gm != null and online and gm.auc != null:
		gm.auc.on_mail(arr)


@rpc("authority", "call_remote", "reliable")
func s_auc_op(op: int, ok: bool, text: String) -> void:
	if gm != null and online and gm.auc != null:
		gm.auc.on_op(op, ok, text)


@rpc("authority", "call_remote", "reliable")
func s_auc_resolve(known: Array, unknown: Array) -> void:
	if gm != null and online and gm.auc != null:
		gm.auc.on_resolve(known, unknown)


@rpc("authority", "call_remote", "reliable")
func s_auc_msg(text: String) -> void:
	if gm != null and online and gm.auc != null:
		gm.auc.on_msg(text)


# ================================================================== MARKET ALIMI (client -> sunucu)
@rpc("any_peer", "call_remote", "reliable")
func c_purchase_item(item_id: String, quantity: int, tx_id: String) -> void:
	if is_server and srv != null:
		srv.on_purchase_item(multiplayer.get_remote_sender_id(), item_id, quantity, tx_id)


# ================================================================== MARKET ALIMI SONUCI (sunucu -> client)
@rpc("authority", "call_remote", "reliable")
func s_purchase_result(ok: bool, error: String, tx_id: String, new_cr: int, new_uri: int) -> void:
	if gm != null and online:
		gm.on_purchase_result(ok, error, tx_id, new_cr, new_uri)


# ================================================================== TAMIR (client -> sunucu)
# Ucret (Phoenix ucretsiz, digerleri 500 uridyum) ve enkaz durumu SUNUCUDA dogrulanir.
@rpc("any_peer", "call_remote", "reliable")
func c_repair(tx_id: String) -> void:
	if is_server and srv != null:
		srv.on_repair(multiplayer.get_remote_sender_id(), tx_id)


@rpc("authority", "call_remote", "reliable")
func s_repair_result(ok: bool, error: String, tx_id: String, cost: int, new_uri: int) -> void:
	if gm != null and online:
		gm.on_repair_result(ok, error, tx_id, cost, new_uri)


# ================================================================== HESAP AYARLARI: nick / sirket (client -> sunucu)
@rpc("any_peer", "call_remote", "reliable")
func c_change_callsign(new_name: String) -> void:
	if is_server and srv != null:
		srv.on_change_callsign(multiplayer.get_remote_sender_id(), new_name)


@rpc("any_peer", "call_remote", "reliable")
func c_change_faction(faction: int) -> void:
	if is_server and srv != null:
		srv.on_change_faction(multiplayer.get_remote_sender_id(), faction)


@rpc("authority", "call_remote", "reliable")
func s_account_result(kind: String, ok: bool, error: String, value: String) -> void:
	if gm != null and online:
		gm.on_account_result(kind, ok, error, value)


# ================================================================== MUHIMMAT SECIMI (client -> sunucu)
@rpc("any_peer", "call_remote", "reliable")
func c_select_ammo(ammo: String) -> void:
	if is_server and srv != null:
		srv.on_select_ammo(multiplayer.get_remote_sender_id(), ammo)


# ================================================================== EKIPMAN KAYDI (client -> sunucu)
@rpc("any_peer", "call_remote", "reliable")
func c_save_loadout(ship: String, loads_json: String, cfgi: int, seq: int) -> void:
	if is_server and srv != null:
		srv.on_save_loadout(multiplayer.get_remote_sender_id(), ship, loads_json, cfgi, seq)


# ================================================================== YETENEK AGACI (client -> sunucu -> client)
@rpc("any_peer", "call_remote", "reliable")
func c_skill_op(op: String, arg: String) -> void:
	if is_server and srv != null:
		srv.on_skill_op(multiplayer.get_remote_sender_id(), op, arg)


@rpc("authority", "call_remote", "reliable")
func s_skill_result(op: String, ok: bool, error: String, skills_json: String, logdisks: int, rd_resets: int, new_cr: int, new_uri: int, new_sep: int) -> void:
	if gm != null and online:
		gm.g.on_skill_result(op, ok, error, skills_json, logdisks, rd_resets, new_cr, new_uri, new_sep)


# ================================================================== HIZLI SLOT CUBUGU KAYDI (client -> sunucu)
@rpc("any_peer", "call_remote", "reliable")
func c_save_quickbar(qb_json: String) -> void:
	if is_server and srv != null:
		srv.on_save_quickbar(multiplayer.get_remote_sender_id(), qb_json)


# ================================================================== EKIPMAN KAYDI SONUCU (sunucu -> client)
@rpc("authority", "call_remote", "reliable")
func s_loadout_result(ship: String, loads_json: String, cfgi: int, seq: int) -> void:
	if gm != null and online:
		gm.on_loadout_result(ship, loads_json, cfgi, seq)


# ================================================================== GEMI DEGISTIRME SONUCU (sunucu -> client)
@rpc("authority", "call_remote", "reliable")
func s_ship_result(ok: bool, ship: String, error: String) -> void:
	if gm != null and online:
		gm.on_ship_result(ok, ship, error)


# ================================================================== MUHIMMAT SECIMI SONUCI (sunucu -> client)
@rpc("authority", "call_remote", "reliable")
func s_select_ammo_result(ok: bool, ammo: String, error: String) -> void:
	if gm != null and online:
		gm.on_select_ammo_result(ok, ammo, error)


# ================================================================== OZEL ESYA (EXTRA) EFEKTI
@rpc("any_peer", "call_remote", "reliable")
func c_extra(idx: int) -> void:
	if is_server and srv != null:
		srv.on_extra(multiplayer.get_remote_sender_id(), idx)


@rpc("authority", "call_remote", "reliable")
func s_extra(peer: int, idx: int) -> void:
	if gm != null and online:
		gm.on_extra(peer, idx)


# ================================================================== GENEL OLAY KANALI
# ONEMLI: Yeni ozellik icin YENI @rpc YAZMA. Godot RPC'leri sira numarasiyla eslestirir; listeye
# fonksiyon eklemek eski istemcilerin baglanmasini bozar. Bunun yerine bu cifti kullan:
#   istemci -> sunucu:  Net.send_event("tip", {"anahtar": deger})   -> net_server.gd on_event()
#   sunucu -> istemci:  srv.send_event_to(peer, "tip", {...})        -> net_game.gd on_event()
# Yeni ozellik = yeni "tip" satiri (match blogunda). RPC listesi ayni kaldigi surece eski istemciler girer.
# Sunucu, istemciden gelen veriyi her zaman dogrulamali (veri guvenilmez).
@rpc("any_peer", "call_remote", "reliable")
func c_event(tip: String, veri: Dictionary) -> void:
	if is_server and srv != null:
		srv.on_event(multiplayer.get_remote_sender_id(), tip, veri)


@rpc("authority", "call_remote", "reliable")
func s_event(tip: String, veri: Dictionary) -> void:
	if gm != null and online:
		gm.on_event(tip, veri)


func send_event(tip: String, veri: Dictionary = {}) -> void:
	if online:
		rpc_id(1, "c_event", tip, veri)
