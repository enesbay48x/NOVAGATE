extends Node
# NOVAGATE - AG KATMANI (autoload: "Net")
# Bu betik hem sunucuda hem istemcide ayni yolda (/root/Net) calisir; RPC'ler burada tanimlidir.
#   Sunucu : godot --headless --path <proje> -- --server --port=7777
#   Istemci: oyunun ana menusunde "Cok oyunculu" kutusunu isaretle, sunucu adresini yaz.

const PROTO := 6   # 6: grup sistemi (c_g_* / s_g_*), sirket + grup sohbeti, paylasimli NPC odulu;  5: 5: sunucu otoriter guvenli bolge + kapi dogrulamasi (c_jump / s_jump_result / s_prot); 4: bonus kutular
# ---- OTOMATIK BAGLANTI ----------------------------------------------------------
# Buraya sunucunun adresini bir kez yaz (ornek: "100.64.12.5:7777" veya "oyun.alanadi.com:7777").
# Doluysa: giris ekranindaki "Cok oyunculu" kutusu ve adres alani gizlenir, oyun giris yapinca
# PC'de ve telefonda OTOMATIK bu sunucuya baglanir. Bos birakirsan eski elle adres girme calisir.
const SERVER_ADDR := ""
const DEFAULT_PORT := 7777
const MAX_PEERS := 32
const NetServer := preload("res://net_server.gd")
const NetGame := preload("res://net_game.gd")

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
	multiplayer.server_disconnected.connect(_on_server_lost)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		var port: int = DEFAULT_PORT
		for a in args:
			if str(a).begins_with("--port="):
				port = int(str(a).substr(7))
		_start_server(port)


# ------------------------------------------------------------------ SUNUCU
func _start_server(port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, MAX_PEERS)
	if err != OK:
		push_error("[SUNUCU] Port %d acilamadi (hata %d). Baska bir sunucu aciksa kapat." % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	Engine.max_fps = 30
	srv = NetServer.new(self)
	print("==============================================")
	print(" NOVAGATE SUNUCUSU calisiyor  |  UDP port %d" % port)
	print(" Kapatmak icin pencereyi kapat / Ctrl+C")
	print("==============================================")


func _process(dt: float) -> void:
	if is_server and srv != null:
		srv.tick(dt)


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


func send_drones(form: String, drn: Array) -> void:
	if online:
		rpc_id(1, "c_drones", form, drn)


func send_died(killer: int) -> void:
	if online:
		rpc_id(1, "c_died", killer)


func send_box_take(id: int) -> void:
	if online:
		rpc_id(1, "c_box_take", id)


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
func c_join(proto: int, nm: String, faction: int, ship: String) -> void:
	if not is_server or srv == null:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var r: Array = srv.on_join(id, proto, nm, faction, ship)
	rpc_id(id, "s_join_result", bool(r[0]), str(r[1]))


@rpc("any_peer", "call_remote", "reliable")
func c_ship(ship: String) -> void:
	if is_server and srv != null:
		srv.on_ship(multiplayer.get_remote_sender_id(), ship)


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
func s_pvp_reward(victim: int) -> void:
	if gm != null and online:
		gm.on_pvp_reward(victim)


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
