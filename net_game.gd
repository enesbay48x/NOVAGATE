extends RefCounted
# NOVAGATE - ISTEMCI TARAFI COK OYUNCULU YAPISTIRICI
# main.gd'nin "enemies" dizisini kullanir: sunucudaki NPC'ler ve DUSMAN SIRKET oyunculari buraya
# "kukla" (puppet) olarak girer, boylece hedefleme / ates / minimap / bar kodlari aynen calisir.
# Ayni sirketten oyuncular "players" sozlugunde tutulur (hedeflenemez, yalnizca gorunur).

var g                       # main.gd
var net: Node               # Net autoload
var npcs: Dictionary = {}   # uid  -> enemies girdisi
var players: Dictionary = {}  # peer -> girdi (dost + dusman oyuncular)
var state_t: float = 0.0
var auc = null              # saatlik acik artirma istemcisi
var last_attacker: int = 0
var last_attacker_t: float = -100.0

const DOData := preload("res://data.gd")
const AucClient := preload("res://auction_client.gd")
const STATE_DT := 0.066
const SMOOTH := 12.0
const FRIEND_PICK_R := 4.5   # dost oyuncuya tiklama yaricapi (uyari icin)

var drone_sig: String = ""   # sunucuya en son bildirilen droid dizilimi


func _init(main_node, net_node: Node) -> void:
	g = main_node
	net = net_node
	auc = AucClient.new(main_node, net_node)


var group_leader: int = 0
var group_members: Array = []   # [[peer, ad, harita], ...] (bos = grupta degilim)


func in_group() -> bool:
	return not group_members.is_empty()


func is_group_peer(peer: int) -> bool:
	for m in group_members:
		if int(m[0]) == peer:
			return true
	return false


# Benim haritamda bulunan grup arkadaslarimin varliklari (minimap'te menzil siniri olmadan gosterilir).
func group_ents() -> Array:
	var out: Array = []
	for m in group_members:
		var pe: int = int(m[0])
		if pe == net.my_id:
			continue
		var e = players.get(pe)
		if e != null and is_instance_valid(e.node):
			out.append(e)
	return out


func clear_group() -> void:
	group_leader = 0
	group_members = []
	_tint_plates()
	if g.dohud != null:
		g.dohud.group_changed()


func on_g_state(leader: int, members: Array) -> void:
	group_leader = leader
	group_members = members
	_tint_plates()
	if g.dohud != null:
		g.dohud.group_changed()


func on_g_invite(from_peer: int, from_name: String) -> void:
	if g.dohud != null:
		g.dohud.on_group_invite(from_peer, from_name)


func _tint_plates() -> void:
	for e in players.values():
		_tint_plate(e)


# Grup arkadaslarinin isim plakasi yesil olur.
func _tint_plate(e) -> void:
	var pl = e.get("plate")
	if pl == null or not is_instance_valid(pl) or pl.get_child_count() == 0:
		return
	var lb := pl.get_child(pl.get_child_count() - 1) as Label
	if lb == null:
		return
	var col := Color(0.5, 0.95, 1.0) if bool(e.get("friendly", false)) else Color(1.0, 0.45, 0.4)
	if is_group_peer(int(e.get("peer", -1))):
		col = Color(0.45, 1.0, 0.5)
	lb.add_theme_color_override("font_color", col)


func reset_map() -> void:
	for pe in players.values():
		var pl = pe.get("plate")
		if pl != null and is_instance_valid(pl):
			pl.queue_free()
	npcs.clear()
	players.clear()
	drone_sig = ""   # yeni baglanti / yeni harita: droid dizilimi sunucuya yeniden bildirilsin


func _vis_vol() -> Dictionary:
	return {"left": 1, "sh": 0.0, "hull": 0.0, "flash": false, "pos": Vector3.ZERO, "vis": true}


# ------------------------------------------------------------------ harita girisi
func on_map_init(map_name: String, npc_list: Array, player_list: Array) -> void:
	if map_name != g.cur or g.world == null:
		return
	reset_map()
	for info in npc_list:
		add_npc(info)
	for info in player_list:
		add_player(info)


# ------------------------------------------------------------------ bonus kutular (sunucu otoriter)
# Sunucu kutu listesini gonderir; herkes AYNI kutulari AYNI yerde gorur. Kutuyu ilk alan kazanir.
func on_boxes(map_name: String, list: Array) -> void:
	if map_name != g.cur or g.world == null:
		return
	g._cancel_collect()
	for b in g.boxes:
		if is_instance_valid(b.node):
			b.node.queue_free()
	g.boxes.clear()
	for it in list:
		_make_box(int(it[0]), float(it[1]), float(it[2]))


func on_box_new(id: int, x: float, z: float) -> void:
	if g.world == null:
		return
	for b in g.boxes:
		if int(b.get("id", -1)) == id:
			return
	_make_box(id, x, z)


func _make_box(id: int, x: float, z: float) -> void:
	var bx: Node3D = g._make_bonus_box(Vector3(x, 0.0, z))
	g.world.add_child(bx)
	g.boxes.append({"node": bx, "id": id})


# taker: kutuyu alan oyuncu (kendimiz ise odul ver). 0 = kutu yok/baskasi almis, -1 = cok uzaktik (kutu duruyor).
func on_box_gone(id: int, taker: int) -> void:
	var ent = null
	for b in g.boxes:
		if int(b.get("id", -1)) == id:
			ent = b
			break
	if ent == null:
		return
	if taker == -1:
		if is_same(ent, g.collect_box):
			g._cancel_collect()
		g.toast("Kutu çok uzakta, tekrar yaklaş.")
		return
	var mine: bool = taker == net.my_id and is_same(ent, g.collect_box)
	if mine:
		g.box_reward()
	else:
		if is_same(ent, g.collect_box):
			g.toast("Bu kutuyu başka bir oyuncu aldı.")
			g.collect_box = null
			g.collect_t = 0.0
		if is_instance_valid(ent.node):
			ent.node.queue_free()
		g.boxes.erase(ent)


# ------------------------------------------------------------------ NPC kuklalari
func add_npc(info: Array) -> void:
	if g.world == null or info.size() < 7:
		return
	var uid: int = int(info[0])
	if npcs.has(uid):
		_drop_entry(npcs[uid])
		npcs.erase(uid)
	var pos := Vector3(float(info[2]), 0.0, float(info[3]))
	var e = g.spawn_npc(str(info[1]), pos)
	if not (e is Dictionary):
		return
	e["uid"] = uid
	e["net_pos"] = pos
	e["net_yaw"] = float(info[4])
	e.hp = float(info[5])
	e.sh = float(info[6])
	var n3: Node3D = e.node
	n3.rotation.y = float(info[4])
	npcs[uid] = e


func on_npc_snap(arr: PackedFloat32Array) -> void:
	var i: int = 0
	while i + 7 <= arr.size():
		var e = npcs.get(int(arr[i]))
		if e != null:
			e["net_pos"] = Vector3(arr[i + 1], 0.0, arr[i + 2])
			e["net_yaw"] = arr[i + 3]
			e.hp = arr[i + 4]
			e.sh = arr[i + 5]
			e.aggro = arr[i + 6] > 0.5
		i += 7


func on_npc_dead(uid: int, killer: int, silent: bool, share_n: int = 1) -> void:
	var e = npcs.get(uid)
	if e == null:
		return
	npcs.erase(uid)
	e.hp = 0.0
	if is_instance_valid(e.node) and not silent:
		g.boom(e.node.position, float(e.node.get_meta("r", 3.0)) * 1.6)
	_drop_entry(e)

# Sunucu tarafindan gelen odul: [npc_id, cr, uri, xp, hon]
@rpc("any_peer", "call_remote", "reliable")
func on_npc_reward(npc_id: String, cr: int, uri: int, xp: int, hon: int) -> void:
	g.give_reward_cr_uri_xp_hon(cr, uri, xp, hon, npc_id)
	g.save_game()


func _drop_entry(e) -> void:
	if e == null:
		return
	if g.target != null and is_same(g.target, e):
		g.target = null
	for i in range(g.enemies.size() - 1, -1, -1):
		if is_same(g.enemies[i], e):
			g.enemies.remove_at(i)
			break
	var plt = e.get("plate")
	if plt != null and is_instance_valid(plt):
		plt.queue_free()
	if e.has("node") and is_instance_valid(e.node):
		e.node.queue_free()


func on_npc_fire(uid: int, target_peer: int, dmg: float) -> void:
	var e = npcs.get(uid)
	if e == null or g.P == null or not g.running:
		return
	var gen: int = g.map_gen
	# Sunucudan gelen her s_npc_fire = TEK atis: tek lazer gorseli, hasar yalnizca hedef oyuncuda ve yalnizca bir kez.
	if target_peer == net.my_id:
		g._npc_bolt(e, 0, dmg, gen)
	else:
		_npc_bolt_vis(e, 0, target_peer, gen)


func _npc_bolt_vis(e: Dictionary, nj: int, target_peer: int, gen: int) -> void:
	if gen != g.map_gen or not g.running:
		return
	var tp = players.get(target_peer)
	if tp == null or not is_instance_valid(tp.node) or not is_instance_valid(e.node) or float(e.hp) <= 0.0:
		return
	var dir: Vector3 = (tp.node as Node3D).position - (e.node as Node3D).position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var side := Vector3(dir.z, 0.0, -dir.x)
	var from: Vector3 = (e.node as Node3D).position + dir * 1.5 + side * [-0.9, 0.9, 0.0][nj % 3]
	g.fire_bolt(from, tp, "enemy", Color(1.0, 0.3, 0.35), 0.0, _vis_vol(), "n_" + str(e.id))


# ------------------------------------------------------------------ oyuncu kuklalari
func add_player(info: Array) -> void:
	if g.world == null or info.size() < 11:
		return
	var peer: int = int(info[0])
	if peer == net.my_id:
		return
	remove_player(peer)
	var nm: String = str(info[1])
	var fac: int = int(info[2])
	var is_adm: bool = info.size() > 13 and int(info[13]) == 1
	var pos := Vector3(float(info[4]), 0.0, float(info[5]))
	var enemy: bool = fac != int(g.SV.get("faction", 1))
	var node: Node3D = g.make_ship(str(info[3]), 6.0, g.ship_faction_tint(fac))
	node.position = pos
	node.rotation.y = float(info[6])
	g.world.add_child(node)
	var col: Color = Color(1.0, 0.45, 0.4) if enemy else Color(0.5, 0.95, 1.0)
	var nt: Label3D = g.tag(nm, Vector3.ZERO, col)
	nt.top_level = true
	nt.font_size = 32
	nt.outline_size = 7
	nt.outline_modulate = Color(0, 0, 0, 0.9)
	node.add_child(nt)
	var plate = g.make_remote_plate(nm, fac, col, is_adm)
	if plate != null:
		nt.visible = false
	var d: Dictionary = {"name": nm, "model": str(info[3]), "sz": 6.0, "hp": float(info[8]), "sh": float(info[10]),
		"spd": 320, "dmg": 0, "aggr": false, "xp": 0, "hon": 0, "cr": 0, "uri": 0, "resp": 0.0}
	var ent: Dictionary = {"node": node, "id": "player", "name": nm, "hp": maxf(float(info[7]), 1.0), "mx": maxf(float(info[8]), 1.0),
		"sh": float(info[9]), "msh": maxf(float(info[10]), 1.0), "v": Vector3.ZERO, "t": 0.0, "cd": 0.0, "aggro": false, "d": d,
		"player": true, "peer": peer, "faction": fac, "friendly": not enemy, "net_pos": pos, "net_yaw": float(info[6]),
		"name_tag": nt, "tag_dz": 1.8, "home_pos": pos, "zone": -1, "plate": plate}
	if enemy:
		var nbar: Dictionary = g._make_bar3d(node, g.BAR_W, 1.8)
		nbar.root.visible = false
		ent["hp_back"] = nbar.root
		ent["hp_fill"] = nbar.hp_fill
		ent["sh_fill"] = nbar.sh_fill
		ent["bar_w"] = g.BAR_W
		ent["bar_y"] = 1.8
		g.enemies.append(ent)
	players[peer] = ent
	_tint_plate(ent)
	if info.size() >= 13:
		_set_drones(ent, str(info[11]), info[12] as Array)
	if enemy:
		g.toast("Düşman oyuncu: %s" % nm)


func remove_player(peer: int) -> void:
	var ent = players.get(peer)
	if ent == null:
		return
	players.erase(peer)
	_drop_entry(ent)


func on_player_snap(arr: Array) -> void:
	for it in arr:
		var ent = players.get(int(it[0]))
		if ent == null:
			continue
		ent["net_pos"] = Vector3(float(it[1]), 0.0, float(it[2]))
		ent["net_yaw"] = float(it[3])
		ent.hp = float(it[4])
		ent.mx = maxf(float(it[5]), 1.0)
		ent.sh = float(it[6])
		ent.msh = maxf(float(it[7]), 1.0)


# ------------------------------------------------------------------ droidler
# Kendi droid dizilimimiz degistiginde (ya da haritaya girince) sunucuya bildirilir.
func _sync_my_drones() -> void:
	if g.P == null or not net.online:
		return
	var c: Dictionary = g.cfg()
	var form: String = str(c.get("form", "std"))
	var drn: Array = []
	for d in c.get("drn", []):
		drn.append(str(d))
	var sig: String = form + "|" + ",".join(PackedStringArray(drn))
	if sig == drone_sig:
		return
	drone_sig = sig
	net.send_drones(form, drn)


func on_player_drones(peer: int, form: String, drn: Array) -> void:
	var ent = players.get(peer)
	if ent == null:
		return
	_set_drones(ent, form, drn)


# Baska oyuncunun gemisine droid dugumlerini ekler (oyuncunun kendi droidleriyle ayni model/dizilim).
func _set_drones(ent: Dictionary, form: String, drn: Array) -> void:
	for old_d in ent.get("drones", []):
		if is_instance_valid(old_d.node):
			old_d.node.queue_free()
	var list: Array = []
	ent["drones"] = list
	if not is_instance_valid(ent.node):
		return
	var ids: Array = []
	for d in drn:
		if DOData.DRONES.has(str(d)):
			ids.append(str(d))
	if ids.is_empty():
		return
	var offs: Array = g.form_offsets_for(form, ids.size())
	for i in ids.size():
		var id: String = ids[i]
		var dd: Dictionary = DOData.DRONES[id]
		var dn: Node3D = g._make_drone(dd.col, id)
		(ent.node as Node3D).add_child(dn)
		dn.position = offs[i]
		list.append({"node": dn, "off": offs[i], "ph": randf() * TAU, "spin": g._drone_scene(id) == null})


func _anim_drones(e, dt: float) -> void:
	var list = e.get("drones")
	if list == null or (list as Array).is_empty():
		return
	for d in list:
		if not is_instance_valid(d.node):
			continue
		var o: Vector3 = d.off
		(d.node as Node3D).position = Vector3(o.x, o.y + 0.3 * sin(g.clock * 2.2 + float(d.ph)), o.z)
		if bool(d.spin):
			(d.node as Node3D).rotation.y += dt * 2.0


# Tiklanan noktada ayni sirketten bir oyuncu varsa onu dondurur (saldirilamaz uyarisi icin).
func friendly_at(hit: Vector3):
	for e in players.values():
		if not bool(e.get("friendly", false)) or not is_instance_valid(e.node):
			continue
		var pr: float = maxf(float(e.node.get_meta("r", 3.0)) * 1.5, FRIEND_PICK_R)
		if (e.node as Node3D).position.distance_to(hit) < pr:
			return e
	return null


# ------------------------------------------------------------------ her kare
func step(dt: float) -> void:
	var k: float = minf(1.0, dt * SMOOTH)
	for e in npcs.values():
		_smooth(e, k)
	var blocked: bool = g._ui_blocking()
	for e in players.values():
		_smooth(e, k)
		_anim_drones(e, dt)
		if bool(e.get("friendly", false)) and e.get("plate") != null:
			g.update_remote_plate(e.get("plate"), e.node if is_instance_valid(e.node) else null, g.running and not blocked)
		elif bool(e.get("friendly", false)):
			var nt = e.get("name_tag")
			if nt != null and is_instance_valid(nt) and is_instance_valid(e.node):
				nt.visible = g.running and not blocked
				nt.global_position = g._screen_off_pos(e.node.global_position, Vector2(0.0, g._off_px(e.node.global_position, e.node, g.NAME_K, g.NAME_MIN_PX) + 6.0))
	state_t += dt
	if state_t >= STATE_DT and g.P != null and g.running:
		state_t = 0.0
		var mhp: float = g.max_hp()
		net.send_state(g.P.node.position.x, g.P.node.position.z, g.P.node.rotation.y, float(g.P.hp), mhp,
			float(g.P.sh), g.max_sh(), g.spd_cur, g.extras.untargetable())
	_sync_my_drones()


func _smooth(e, k: float) -> void:
	if not is_instance_valid(e.node):
		return
	var n: Node3D = e.node
	var np: Vector3 = e.net_pos
	if n.position.distance_to(np) > 40.0:
		n.position = np
	else:
		n.position = n.position.lerp(np, k)
	n.rotation.y = lerp_angle(n.rotation.y, float(e.net_yaw), k)


# ------------------------------------------------------------------ savas
# Yerel olarak uygulanan hasari sunucuya bildirir; yerel HP sunucu anlik goruntusuyle ezilir.
func hit_enemy(e, dmg: float, mode: int = 0) -> void:
	if e == null or not net.online:
		return
	if e.has("uid"):
		net.send_hit_npc(int(e.uid), dmg, mode)
	elif bool(e.get("player", false)) and mode == 0:
		net.send_hit_player(int(e.peer), dmg)
	e.hp = maxf(float(e.hp), 1.0)


func fire_started(tgt, nb: int, ammo: String) -> void:
	if not net.online or tgt == null:
		return
	if tgt.has("uid"):
		net.send_fire(0, int(tgt.uid), nb, ammo)
	elif bool(tgt.get("player", false)):
		net.send_fire(1, int(tgt.peer), nb, ammo)


func on_fire_vis(shooter: int, kind: int, ref: int, nb: int, ammo: String) -> void:
	var sp = players.get(shooter)
	if sp == null or not is_instance_valid(sp.node) or g.world == null:
		return
	var tgt = null
	var tpos: Vector3
	if kind == 0:
		tgt = npcs.get(ref)
		if tgt == null:
			return
		tpos = (tgt.node as Node3D).position
	elif ref == net.my_id:
		if g.P == null:
			return
		tpos = g.P.node.position    # tgt = null -> mermi bana dogru uçar (hasar sunucudan s_hurt ile gelir)
	else:
		tgt = players.get(ref)
		if tgt == null:
			return
		tpos = (tgt.node as Node3D).position
	var from0: Vector3 = (sp.node as Node3D).position
	var dir: Vector3 = tpos - from0
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var side := Vector3(dir.z, 0.0, -dir.x)
	var col: Color = g._ammo_col(ammo)
	var wf: float = float(g.AMMO_BOLT_W.get(ammo, 1.0))
	for j in mini(nb, 10):
		var off: float = (float(j) - float(nb - 1) * 0.5) * 0.55
		g.fire_bolt(from0 + dir * 1.2 + side * off + Vector3(0, 0.6, 0), tgt, "lf1", col, 0.0, _vis_vol(), ammo, wf)


# Sunucu GERCEK korumayi bildirir (0 yok, 1 ust, 2 kapi, 3 gecici gecis). Istemci koruma VEREMEZ; yalnizca gosterir.
func on_prot(kind: int) -> void:
	g.net_prot = kind


# Kapi atlama istegine sunucu cevabi. Onay gelmeden harita degistirilmez.
func on_jump_result(ok: bool, dest: String, note: String) -> void:
	if not ok:
		g.jump_wait_until = -1.0
		g.toast("Atlama engellendi: " + note)
		return
	if note == "random":
		g.toast("Solucan deliği seni %s haritasına ışınladı!" % dest)
	g.do_jump_to(dest)


func on_hurt(attacker: int, dmg: float) -> void:
	# Koruma kararini SUNUCU verir: s_hurt geldiyse hasar gecerlidir (guvenli bolgedeki oyuncuya sunucu zaten gondermez).
	if g.P == null or not g.running or g.extras.untargetable():
		return
	last_attacker = attacker
	last_attacker_t = g.clock
	g.impact(g.P.node.position, Color(1.0, 0.4, 0.3), false, 1.0)   # kalkan varken ozel efekt/balon yok
	g.hurt(dmg)


func report_death() -> void:
	var killer: int = last_attacker if g.clock - last_attacker_t < 12.0 else 0
	last_attacker = 0
	net.send_died(killer)


func on_kill_msg(text: String) -> void:
	g.toast(text)
	_chat_line("[color=#ffb347]%s[/color]" % text.replace("[", "[lb]"))


func on_pvp_reward(victim: int) -> void:
	g.SV.pvp_kills = int(g.SV.get("pvp_kills", 0)) + 1
	g.SV.hon = float(g.SV.get("hon", 0.0)) + 100.0 * (1.0 + g.skill_bonus("honor"))
	g.toast("Oyuncu yok edildi! +100 Honor")
	g.save_game()


# ------------------------------------------------------------------ sohbet
# ch: 0 genel, 1 sirket, 2 grup
func on_chat(nm: String, faction: int, text: String, ch: int = 0) -> void:
	var safe_t: String = text.replace("[", "[lb]")
	if nm == "":
		_chat_line("[color=#00ccff]Sistem:[/color] %s" % safe_t)
		return
	var col: String = ["#cccccc", "#ff6a6a", "#6ab0ff", "#ffd45a"][clampi(faction, 0, 3)]
	var line: String = "[color=%s][b]%s:[/b][/color] %s" % [col, nm.replace("[", "[lb]"), safe_t]
	if g.dohud == null:
		return
	if ch == 1:
		g.dohud._log_company(line)
	elif ch == 2:
		g.dohud._log_group(line)
	else:
		g.dohud._log_general(line)


func _chat_line(bb: String) -> void:
	if g.dohud != null:
		g.dohud._log_general(bb)
