extends RefCounted
# DarkOrbit3D - OZEL ESYALAR (5 ekstra): mantik + animasyonlu efektler.
# main.gd bu sinifi "extras" degiskeninde tutar; hud_do.gd "Ozel esyalar" kategorisinde gosterir.
# Tum ayarlar asagidaki sabitlerden degistirilebilir.

const DIR := "res://assets/extras/"
const ANIM_DIR := "res://assets/extras/animations/"

const IDS := ["E-NB-01", "E-WS-02", "E-EMP-03", "E-FR-05", "E-ENT-06"]

# ---- Ayarlar ----
const NUKE_FRAC := 0.15          # Nukleer: dusmanin MAKSIMUM govde canin %15'i (kalkani yok sayar)
const NUKE_RADIUS := 700.0       # Nukleer: "yakin" = lazer menzili (DarkOrbit birimi)
const SHIELD_TIME := 3.0         # 3 Saniyelik Koruma suresi
const EMA_TIME := 3.0            # EMA: dusmanlar seni hedefleyemez (sn)
const REPAIR_HP := 10000.0       # 10'lu Tamir: her basista yenilenen HP
const REPAIR_USES := 10          # 10'lu Tamir: kullanim hakki; haklar bitince REPAIR_COOLDOWN baslar, bitince 10 hak yenilenir
const REPAIR_COOLDOWN := 120.0
const REPAIR_FX_TIME := 4.0      # tamir drone animasyonunun suresi
const ENC_RATE := 0.10           # ENC: lazerle verilen govde hasarinin %10'u kendi HP'ne
const ENC_TIME := 300.0          # ENC: etki suresi (sn) - bekleme, etki BITINCE baslar

# "price" = her kullanimda dusen Uridium, "cd" = bekleme (sn)
const DEFS := {
	"E-NB-01": {"name": "Nükleer", "icon": "nukleer", "anim": "nukleer", "cd": 30.0, "price": 300,
		"tip": "Nükleer (E-NB-01)\nYakındaki düşmanların gövde canına %15 hasar verir.\nBekleme: 30 sn   Fiyat: 300 Uridium / kullanım"},
	"E-WS-02": {"name": "3 Saniyelik Koruma", "icon": "3saniye", "anim": "3saniye", "cd": 25.0, "price": 300,
		"tip": "3 Saniyelik Koruma (E-WS-02)\nGemiyi 3 saniye boyunca hasardan korur.\nBekleme: 25 sn   Fiyat: 300 Uridium / kullanım"},
	"E-EMP-03": {"name": "EMA", "icon": "ema", "anim": "ema", "cd": 40.0, "price": 300,
		"tip": "EMA (E-EMP-03)\nDüşmanın hedef kilidini bozar; 3 saniye boyunca hedeflenemezsin.\nBekleme: 40 sn   Fiyat: 300 Uridium / kullanım"},
	"E-FR-05": {"name": "10'lu Tamir", "icon": "10luk", "anim": "10luk", "cd": 120.0, "price": 300,
		"tip": "10'lu Tamir (E-FR-05)\nHer basışta 10.000 HP yeniler. 10 kullanım hakkı; haklar bitince 120 sn bekleme.\nFiyat: 300 Uridium / basış"},
	"E-ENT-06": {"name": "ENC", "icon": "enc", "anim": "enc", "cd": 120.0, "price": 500,
		"tip": "ENC (E-ENT-06)\nLazerle verdiğin gövde hasarının %10'unu canına aktarır (300 sn).\nBekleme: 120 sn (etki bitince)   Fiyat: 500 Uridium / etkinleştirme"},
}

var game = null                  # main.gd
var cd := {}                     # id -> kalan bekleme (sn)
var shield_t := 0.0
var ema_t := 0.0
var enc_t := 0.0
var _fx: Array = []              # aktif efektler
var _frames_cache := {}
var _enc_pop := 0.0              # ENC ile biriken iyilesme (popup icin)
var _enc_pop_t := 0.0
var _absorb_t := 0.0
var _quad: QuadMesh = null


func _init(g = null) -> void:
	game = g
	for id in IDS:
		cd[id] = 0.0


# Animasyonlari arka planda yukle (ilk kullanimda takilma olmasin).
func preload_anims() -> void:
	# 4.7.x'te buyuk SpriteFrames'lerin load_threaded_* yuklemesi boot'ta periyodik olarak
	# "Parse Error" (uid cozumleme yariemasali) uretiyor. Thread'li yuklemeyi tamamen
	# kapatiyoruz; _get_frames ilk kullanimda load() ile zaten yukluyor.
	pass


# ------------------------------------------------------------ kayit (SV)

func _store() -> Dictionary:
	var sv: Dictionary = game.SV
	if typeof(sv.get("extras")) != TYPE_DICTIONARY:
		sv["extras"] = {}
	var d: Dictionary = sv["extras"]
	if not d.has("repair"):
		d["repair"] = REPAIR_USES
	if not d.has("repair_cd"):
		d["repair_cd"] = 0.0
	return d


func repair_left() -> int:
	if game == null or game.SV.is_empty():
		return REPAIR_USES
	return int(_store()["repair"])


# Yeni oyun / devam / olum / harita degisimi: sayaclari ve efektleri temizle.
func reset() -> void:
	shield_t = 0.0
	ema_t = 0.0
	enc_t = 0.0
	_enc_pop = 0.0
	for id in IDS:
		cd[id] = 0.0
	if game != null and not game.SV.is_empty():
		var st := _store()
		if int(st["repair"]) <= 0:
			cd["E-FR-05"] = float(st["repair_cd"]) if float(st["repair_cd"]) > 0.0 else REPAIR_COOLDOWN
	_clear_fx()


func _clear_fx() -> void:
	for f in _fx:
		var n = f.get("node")
		if is_instance_valid(n):
			n.queue_free()
	_fx.clear()


# ------------------------------------------------------------ durum sorgulari

func shield_active() -> bool:
	return shield_t > 0.0


func untargetable() -> bool:
	return ema_t > 0.0


func enc_active() -> bool:
	return enc_t > 0.0


func active_left(id: String) -> float:
	match id:
		"E-WS-02":
			return shield_t
		"E-EMP-03":
			return ema_t
		"E-ENT-06":
			return enc_t
	return 0.0


func cd_total(id: String) -> float:
	return float(DEFS[id].cd)


func cd_left(id: String) -> float:
	return float(cd.get(id, 0.0))


# HUD hucresi icin: [sayi yazisi, aktif mi, kullanilabilir mi, bekleme orani 0..1]
func cell_state(id: String) -> Array:
	var act := active_left(id)
	var cl := cd_left(id)
	var txt := ""
	var usable := cl <= 0.0 and act <= 0.0
	var frac := 0.0
	if cl > 0.0:
		frac = clampf(cl / maxf(cd_total(id), 0.01), 0.0, 1.0)
	if id == "E-FR-05":
		var left := repair_left()
		txt = str(left) if left > 0 else str(int(ceil(cl)))
		usable = usable and left > 0
	elif act > 0.0:
		txt = str(int(ceil(act)))
	elif cl > 0.0:
		txt = str(int(ceil(cl)))
	return [txt, act > 0.0, usable, frac]


func icon(id: String) -> Texture2D:
	return game._tex(DIR + str(DEFS[id].icon) + ".png")


# ------------------------------------------------------------ kullanim

func use(id: String) -> bool:
	if game == null or not game.running or game.P == null or game.SV.is_empty():
		return false
	if game.wrecked:
		return false   # enkaz gemi: tamir edilene kadar ozel esya kullanilamaz
	if not DEFS.has(id):
		return false
	var dn: String = str(DEFS[id].name)
	if active_left(id) > 0.0:
		game.toast("%s zaten aktif (%d sn)." % [dn, int(ceil(active_left(id)))])
		return false
	if cd_left(id) > 0.0:
		# bekleme suresinde ucret alinmaz
		game.toast("%s: bekleme süresi %d sn" % [dn, int(ceil(cd_left(id)))])
		return false
	var ok := false
	match id:
		"E-NB-01":
			ok = _use_nuke(id)
		"E-WS-02":
			ok = _use_shield(id)
		"E-EMP-03":
			ok = _use_ema(id)
		"E-FR-05":
			ok = _use_repair(id)
		"E-ENT-06":
			ok = _use_enc(id)
	# Basarili kullanimi ayni haritadaki diger oyunculara bildir (efekt onlarda da gorunsun)
	if ok and game.net_on:
		Net.send_extra(IDS.find(id))
	return ok


# Baska bir oyuncunun kullandigi ekstranin GORSELI (hasar/etki yok; hepsi sunucuda / kullanicida islenir).
func play_remote(idx: int, node: Node3D) -> void:
	if idx < 0 or idx >= IDS.size() or node == null or not is_instance_valid(node):
		return
	var id: String = IDS[idx]
	match id:
		"E-NB-01":
			_play(id, node, Vector3(0, 1.0, 0), 22.0, 0.0, true, 99.0, false, false)
		"E-WS-02":
			_play(id, node, Vector3(0, 1.0, 0), 11.0, 0.0, true, SHIELD_TIME, true, false, 0.4, 0.15)
		"E-EMP-03":
			_play(id, node, Vector3(0, 1.0, 0), 30.0, 0.0, true, 99.0, false, false)
		"E-FR-05":
			_play(id, node, Vector3(0, 1.0, 0), 19.2, 0.0, false, REPAIR_FX_TIME, true, false, 0.5, 0.2)
		"E-ENT-06":
			_play(id, node, Vector3(0, 1.0, 0), 10.0, 0.0, true, ENC_TIME, true, false, 1.0, 0.2)


func _start_cd(id: String) -> void:
	cd[id] = cd_total(id)


# Mesajlarda gosterilecek gercek ucret.
func _paid(id: String) -> int:
	return int(DEFS[id].price)


# Uridium kontrolu + tahsilat. Sadece kullanim BASARILI olacagi kesinlestikten sonra cagrilir.
func _charge(id: String) -> bool:
	var price: int = int(DEFS[id].price)
	if int(game.SV.uri) < price:
		game.toast("%s için yeterli Uridium yok (gerekli: %d)." % [str(DEFS[id].name), price])
		return false
	game.SV.uri = int(game.SV.uri) - price
	return true


func _use_nuke(id: String) -> bool:
	if game.in_safe:
		game.toast("Güvenli bölgede Nükleer kullanılamaz.")
		return false
	var po: Vector3 = game.P.node.position
	var rad: float = NUKE_RADIUS * DOData.S
	var hits: Array = []
	for e in game.enemies:
		if e.hp <= 0.0 or e.get("silent", false) or not is_instance_valid(e.node):
			continue
		var d: Vector3 = e.node.position - po
		d.y = 0.0
		if d.length() <= rad:
			hits.append(e)
	if hits.is_empty():
		game.toast("Nükleer: yakında düşman yok.")
		return false
	if not _charge(id):
		return false
	_start_cd(id)
	_play(id, game.P.node, Vector3(0, 1.0, 0), 22.0, 0.0, true, 99.0, false, true)
	for e in hits:
		var dmg: float = float(e.mx) * NUKE_FRAC
		e.hp -= dmg
		e.aggro = true
		e["last_hit_t"] = game.clock
		if game.net_on:
			Net.gm.hit_enemy(e, dmg)
		var dist: float = (e.node.position - po).length()
		_play(id, e.node, Vector3(0, 1.0, 0), 13.0, dist / 70.0, true, 99.0, false, false)
		game.popup_txt("-" + game._n(dmg), e.node.position, Color(1.0, 0.6, 0.15))
	game.toast("Nükleer patladı! %d düşman etkilendi.  (-%d Uridium)" % [hits.size(), _paid(id)])
	game.save_game()
	return true


func _use_shield(id: String) -> bool:
	if not _charge(id):
		return false
	_start_cd(id)
	shield_t = SHIELD_TIME
	_play(id, game.P.node, Vector3(0, 1.0, 0), 11.0, 0.0, true, SHIELD_TIME, true, true, 0.4, 0.15)
	game.popup_txt("KORUMA", game.P.node.position, Color(0.4, 0.85, 1.0))
	game.save_game()
	return true


func _use_ema(id: String) -> bool:
	if not _charge(id):
		return false
	_start_cd(id)
	ema_t = EMA_TIME
	# Dusmanlar kilidi kaybeder; ucusta olan dusman mermileri iptal olur.
	for e in game.enemies:
		e.aggro = false
	for i in range(game.bullets.size() - 1, -1, -1):
		var b: Dictionary = game.bullets[i]
		if b.tgt == null and str(b.get("kind", "")) == "enemy":
			if is_instance_valid(b.node):
				b.node.queue_free()
			game.bullets.remove_at(i)
	_play(id, game.P.node, Vector3(0, 1.0, 0), 30.0, 0.0, true, 99.0, false, true)
	game.popup_txt("EMA", game.P.node.position, Color(0.6, 0.85, 1.0))
	game.toast("EMA: düşmanların hedef kilidi bozuldu (%d sn)." % int(EMA_TIME))
	game.save_game()
	return true


func _use_repair(id: String) -> bool:
	var st := _store()
	if int(st["repair"]) <= 0:
		game.toast("10'lu Tamir: haklar bitti, bekleme sürüyor.")
		return false
	var mhp: float = game.max_hp()
	if game.P.hp >= mhp - 0.5:
		game.toast("Gövde canın zaten dolu.")
		return false
	if not _charge(id):
		return false
	var heal: float = minf(REPAIR_HP, mhp - game.P.hp)
	game.P.hp += heal
	st["repair"] = int(st["repair"]) - 1
	if int(st["repair"]) <= 0:
		# haklar bitti: 120 sn bekleme baslar, sonunda 10 hak yenilenir
		cd[id] = REPAIR_COOLDOWN
		st["repair_cd"] = REPAIR_COOLDOWN
	_play(id, game.P.node, Vector3(0, 1.0, 0), 19.2, 0.0, false, REPAIR_FX_TIME, true, true, 0.5, 0.2)
	game.popup_txt("+" + game._n(heal), game.P.node.position, Color(0.4, 1.0, 0.45))
	game.toast("10'lu Tamir: +%s HP  (kalan hak: %d)  (-%d Uridium)" % [game._n(heal), int(st["repair"]), _paid(id)])
	game.save_game()
	return true


func _use_enc(id: String) -> bool:
	if not _charge(id):
		return false
	enc_t = ENC_TIME   # bekleme etki BITINCE baslar (tick)
	_play(id, game.P.node, Vector3(0, 1.0, 0), 10.0, 0.0, true, ENC_TIME, true, true, 1.0, 0.2)
	game.popup_txt("ENC", game.P.node.position, Color(1.0, 0.4, 0.35))
	game.toast("ENC aktif: lazer gövde hasarının %%%d'u canına geçer (%d sn).  (-%d Uridium)" % [int(ENC_RATE * 100.0), int(ENC_TIME), _paid(id)])
	game.save_game()
	return true


# main.gd _bolt_hit: lazerle verilen gövde hasarı
func leech(hull_dmg: float) -> void:
	if enc_t <= 0.0 or hull_dmg <= 0.0 or game.P == null:
		return
	var mhp: float = game.max_hp()
	var heal: float = minf(hull_dmg * ENC_RATE, maxf(mhp - game.P.hp, 0.0))
	if heal <= 0.0:
		return
	game.P.hp += heal
	_enc_pop += heal


# Kalkan hasar aldiginda: mavi balon yerine projedeki 3 sn'lik "3saniye" hasar/koruma animasyonu.
# Efekt suruyorsa yeniden baslatilmaz (ust uste binmesin).
func hit_fx() -> void:
	if game == null or game.P == null or not is_instance_valid(game.P.node):
		return
	for f in _fx:
		if str(f.id) == "E-WS-02" and bool(f.owned):
			return
	_play("E-WS-02", game.P.node, Vector3(0, 1.0, 0), 11.0, 0.0, true, SHIELD_TIME, true, true, 0.4, 0.15, 0.25)   # hasar efekti: parlaklik dusuruldu (gemi gorunsun)


# main.gd hurt(): koruma acikken gelen hasar
func shield_absorb(_dmg: float) -> void:
	if _absorb_t > 0.0:
		return
	_absorb_t = 0.35
	game.popup_txt("KORUNDU", game.P.node.position, Color(0.5, 0.85, 1.0))


# ------------------------------------------------------------ her kare

func tick(dt: float) -> void:
	for id in IDS:
		if float(cd[id]) > 0.0:
			cd[id] = maxf(0.0, float(cd[id]) - dt)
	var was_shield := shield_t > 0.0
	shield_t = maxf(0.0, shield_t - dt)
	var was_ema := ema_t > 0.0
	ema_t = maxf(0.0, ema_t - dt)
	var was_enc := enc_t > 0.0
	enc_t = maxf(0.0, enc_t - dt)
	_absorb_t = maxf(0.0, _absorb_t - dt)
	if was_shield and shield_t <= 0.0:
		game.toast("3 Saniyelik Koruma sona erdi.")
	if was_ema and ema_t <= 0.0:
		game.toast("EMA sona erdi.")
	if was_enc and enc_t <= 0.0:
		game.toast("ENC sona erdi.")
		_enc_pop = 0.0
		_start_cd("E-ENT-06")
	var rst := _store()
	if int(rst["repair"]) <= 0:
		if float(cd["E-FR-05"]) <= 0.0:
			rst["repair"] = REPAIR_USES
			rst["repair_cd"] = 0.0
			game.toast("10'lu Tamir: 10 kullanım hakkı yenilendi.")
		else:
			rst["repair_cd"] = float(cd["E-FR-05"])
	if _enc_pop > 0.0:
		_enc_pop_t -= dt
		if _enc_pop_t <= 0.0:
			_enc_pop_t = 0.6
			game.popup_txt("+" + game._n(_enc_pop), game.P.node.position, Color(1.0, 0.45, 0.4))
			_enc_pop = 0.0
	_update_fx(dt)


# ------------------------------------------------------------ efektler

func _anim_frames(id: String) -> SpriteFrames:
	if _frames_cache.has(id):
		return _frames_cache[id]
	var p: String = ANIM_DIR + str(DEFS[id].anim) + ".tres"
	var sf: SpriteFrames = load(p) as SpriteFrames
	_frames_cache[id] = sf
	return sf


func _make_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 20
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.albedo_color = Color(1, 1, 1, 1)
	return m


# id: ekstra, follow: takip edilen Node3D, size: dunya birimi (kare ise kenar, yatay ise YUKSEKLIK),
# delay: baslamadan once bekleme, add: additif karisim, life: azami sure (loop'lu animasyonlar),
# loop: animasyon bitince basa sar, owned: oyuncuya ait (reset'te silinir), fade_out/fade_in: sn
func _play(id: String, follow: Node3D, off: Vector3, size: float, delay: float, add: bool,
		life: float, loop: bool, owned: bool, fade_out := 0.0, fade_in := 0.0, bright := 1.0) -> void:
	if game == null or follow == null:
		return
	var sf := _anim_frames(id)
	if sf == null or not sf.has_animation("default") or sf.get_frame_count("default") <= 0:
		return
	# ayni ekstranin onceki oyuncu efekti varsa degistir
	if owned:
		for i in range(_fx.size() - 1, -1, -1):
			if str(_fx[i].id) == id and bool(_fx[i].owned):
				var on = _fx[i].get("node")
				if on != null and is_instance_valid(on):
					on.queue_free()
				_fx.remove_at(i)
	var fr0: Texture2D = sf.get_frame_texture("default", 0)
	var aspect := 1.0
	if fr0 is AtlasTexture:
		var rg: Rect2 = (fr0 as AtlasTexture).region
		aspect = rg.size.x / maxf(rg.size.y, 1.0)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size * aspect, size) if aspect >= 1.0 else Vector2(size, size / aspect)
	mi.mesh = q
	var mat := _make_mat(add)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = delay <= 0.0
	game.add_child(mi)
	mi.global_position = follow.global_position + off
	_fx.append({"id": id, "node": mi, "mat": mat, "sf": sf, "follow": follow, "off": off, "t": -delay,
		"loop": loop, "life": life, "owned": owned, "fo": fade_out, "fi": fade_in, "br": bright, "last": mi.global_position, "idx": -1})


func _set_frame(f: Dictionary, idx: int) -> void:
	if idx == int(f.idx):
		return
	f.idx = idx
	var tex: Texture2D = (f.sf as SpriteFrames).get_frame_texture("default", idx)
	var mat: StandardMaterial3D = f.mat
	if tex is AtlasTexture:
		var at := tex as AtlasTexture
		var sheet: Texture2D = at.atlas
		if sheet == null:
			return
		var sz := Vector2(sheet.get_width(), sheet.get_height())
		mat.albedo_texture = sheet
		mat.uv1_scale = Vector3(at.region.size.x / sz.x, at.region.size.y / sz.y, 1.0)
		mat.uv1_offset = Vector3(at.region.position.x / sz.x, at.region.position.y / sz.y, 0.0)
	else:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3.ONE
		mat.uv1_offset = Vector3.ZERO


func _update_fx(dt: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var mi = f.get("node")
		if not is_instance_valid(mi):
			_fx.remove_at(i)
			continue
		f.t = float(f.t) + dt
		var t: float = f.t
		if t < 0.0:
			continue
		var sf: SpriteFrames = f.sf
		var n: int = sf.get_frame_count("default")
		var fps: float = maxf(sf.get_animation_speed("default"), 1.0)
		var raw := int(t * fps)
		var done := false
		var life: float = f.life
		# sure sinirli efekt (koruma/ENC/tamir) ya da animasyon sonu
		if bool(f.loop):
			if t >= life:
				done = true
		else:
			if raw >= n or t >= life:
				done = true
		if done:
			mi.queue_free()
			_fx.remove_at(i)
			continue
		var idx := raw % n if bool(f.loop) else mini(raw, n - 1)
		_set_frame(f, idx)
		mi.visible = true
		# takip
		var fol = f.get("follow")
		if is_instance_valid(fol):
			f.last = (fol as Node3D).global_position + f.off
		mi.global_position = f.last
		# solma
		var a := 1.0
		if float(f.fi) > 0.0:
			a = minf(a, t / float(f.fi))
		if float(f.fo) > 0.0 and life < 90.0:
			a = minf(a, (life - t) / float(f.fo))
		(f.mat as StandardMaterial3D).albedo_color = Color(1, 1, 1, clampf(a * float(f.get("br", 1.0)), 0.0, 1.0))

