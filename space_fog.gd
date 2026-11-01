# NOVAGATE - UZAY SISI (DarkOrbit tarzi, canli ve bagimsiz hareketli nebula bulutlari)
#
# NASIL CALISIR
#   - Sis, main.gd'deki arka plan CanvasLayer'ina (layer -1) uzay shader'indan HEMEN SONRA eklenir.
#     Environment BG_CANVAS (max layer -1) oldugu icin bu katman 3D dunyanin ARKASINDA cizilir:
#     gemiler, NPC'ler, lazerler, roketler, efektler ve HUD sisin altinda KALMAZ, sis hicbir zaman onlarin ustune binemez.
#     (Z-fighting / seffaflik siralamasi sorunu da olmaz; sis hic 3D derinlik tamponuna girmez.)
#   - Hareket tamamen delta zamanina baglidir: gemi dursa da, kamera donmese de bulutlar suzulur,
#     doner, nefes alir (olcek) ve yogunlugu cok hafif dalgalanir.
#   - 3 derinlik katmani (uzak / orta / yakin): farkli yon, hiz, olcek ve parlaklik -> derinlik hissi.
#   - Sis oyuncunun/kameranin konumundan, ucusundan ve durusundan HICBIR sekilde etkilenmez (kamera okunmaz).
#   - Bulut ekran disina tamamen ciktiginda karsi taraftan girer (gorunmezken tasinir): ani belirme/kaybolma yok.
#   - Eklemeli (additive) karisim: renkli, yari saydam, gaz gibi parlar; beyaz bogucu sis olusmaz.
#   - Yalnizca bu haritanin sis dokulari bellekte tutulur (telefon icin).
#
# AYARLAR (asagidaki 'AYARLAR' bolumu ya da calisirken kod ile):
#   fog.set_enabled(true/false)   fog.set_intensity(0..2)   fog.set_speed(0..3)   fog.set_quality(0 kapali / 1 dusuk / 2 yuksek)
#   Klavye: F8 = sisi ac/kapat,  Shift+F8 = kalite (yuksek -> dusuk -> kapali). Secim user://novagate_fog.cfg dosyasina kaydedilir.
extends Node2D

const TEX_PATH := "res://assets/fog/cloud_%02d.png"
const CFG_PATH := "user://novagate_fog.cfg"

# ------------------------------------------------------------------ AYARLAR
var enabled: bool = true
var intensity: float = 1.25     # genel yogunluk carpani (0 = yok, 1 = varsayilan, 2 = iki kat)
var speed: float = 1.0          # genel hareket hizi carpani
var quality: int = 2            # 0 = kapali, 1 = dusuk (mobil: uzak+orta, daha az bulut), 2 = yuksek (3 katman)

const FADE_IN := 2.5            # harita acilinca sis bu kadar saniyede yavasca belirir
const PULSE_AMOUNT := 0.18      # yogunluk dalgalanmasi (+-%18)
const BREATH_AMOUNT := 0.04     # olcek "nefesi" (+-%4)
const OVERLAP_SAFE := 1.08      # sarma yaricapi payi (bulut tamamen disarida iken tasinsin)

# Katmanlar: par = KULLANILMIYOR (sis kameradan bagimsiz), scale/alpha/speed/rot = [en az, en cok]
# speed: piksel/sn (cok yavas), rot: radyan/sn.  tex: kullanilabilecek doku numaralari (1..10)
const LAYERS := [
	{"n": 4, "par": 0.05, "scale": [1.5, 2.3], "alpha": [0.10, 0.17], "speed": [3.0, 7.0],
		"rot": [0.002, 0.006], "tex": [1, 2, 4, 10, 7]},
	{"n": 5, "par": 0.10, "scale": [1.0, 1.6], "alpha": [0.11, 0.20], "speed": [5.0, 11.0],
		"rot": [0.004, 0.012], "tex": [6, 9, 7, 10, 2]},
	{"n": 4, "par": 0.17, "scale": [0.8, 1.3], "alpha": [0.08, 0.15], "speed": [8.0, 15.0],
		"rot": [0.006, 0.016], "tex": [3, 6, 8, 5, 9]},
]

# Renk paleti: mor, mavi, turkuaz, hafif pembe (ek: agirlik -> pembe nadir)
const TINTS := [
	Color(0.50, 0.28, 0.95),
	Color(0.22, 0.45, 1.00),
	Color(0.10, 0.85, 0.90),
	Color(0.95, 0.42, 0.80),
]
const TINT_WEIGHTS := [3.0, 3.0, 2.0, 1.0]

# Istersen haritaya ozel ana/ikincil renk sec: "harita": [ana_renk_indeksi, ikincil_indeksi]  (0 mor, 1 mavi, 2 turkuaz, 3 pembe)
# Tanimsiz haritalarda renkler harita adindan sabit (her acilista ayni) secilir.
const MAP_TINTS := {
	# "1-1": [0, 1],
}

const SHADER_CODE := """
shader_type canvas_item;
render_mode blend_add;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = mix(0.55, 1.25, t.r);
	COLOR = vec4(tint.rgb * l, t.a * tint.a);
}
"""

var main = null                  # main.gd
var _mat: ShaderMaterial
var _clouds: Array = []
var _tex_cache: Dictionary = {}
var _map_name: String = ""
var _t: float = 0.0
var _fade: float = 0.0
var _warned: bool = false


func attach(main_node) -> void:
	main = main_node
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	if OS.has_feature("mobile"):
		quality = 1   # telefon: varsayilan dusuk kalite (kayitli secim varsa o gecerli)
	_load_cfg()
	_apply_visibility()


# Harita yuklenince cagrilir (ayni haritaya yeniden dogusta bulutlar yerinde kalir, sis ziplamaz).
func set_map(map_name: String) -> void:
	if map_name == _map_name and not _clouds.is_empty():
		return
	_map_name = map_name
	_rebuild()


func set_enabled(v: bool) -> void:
	enabled = v
	_apply_visibility()
	_save_cfg()


func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 2.0)
	_save_cfg()


func set_speed(v: float) -> void:
	speed = clampf(v, 0.0, 3.0)
	_save_cfg()


func set_quality(q: int) -> void:
	q = clampi(q, 0, 2)
	if q == quality:
		return
	quality = q
	_apply_visibility()
	_rebuild()
	_save_cfg()


func _apply_visibility() -> void:
	visible = enabled and quality > 0
	set_process(visible)


# ------------------------------------------------------------------ bulut uretimi
func _rebuild() -> void:
	for c in _clouds:
		if is_instance_valid(c.sp):
			c.sp.queue_free()
	_clouds.clear()
	if _map_name == "" or quality <= 0:
		_tex_cache.clear()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_map_name)
	var main_i: int = _weighted(rng, -1)
	var acc_i: int = _weighted(rng, main_i)
	if MAP_TINTS.has(_map_name):
		main_i = int(MAP_TINTS[_map_name][0])
		acc_i = int(MAP_TINTS[_map_name][1])
	var base_ang: float = rng.randf() * TAU
	var used: Dictionary = {}
	var li := 0
	for L in LAYERS:
		if quality == 1 and li == 2:
			break   # dusuk kalite: yakin katman yok
		var n: int = int(L.n)
		if quality == 1:
			n = maxi(2, int(ceil(float(n) * 0.65)))
		# Her katman farkli yone suzulur
		var ang: float = base_ang + float(li) * 2.2 + rng.randf_range(-0.35, 0.35)
		for i in n:
			var tex_ids: Array = L.tex
			var tid: int = int(tex_ids[rng.randi() % tex_ids.size()])
			var tex: Texture2D = _get_tex(tid)
			if tex == null:
				continue
			used[tid] = true
			var sc: float = rng.randf_range(float(L.scale[0]), float(L.scale[1]))
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.material = _mat
			sp.flip_h = rng.randf() < 0.5
			sp.flip_v = rng.randf() < 0.5
			add_child(sp)
			var tc: Color = _pick_tint(rng, main_i, acc_i)
			var vdir := Vector2.from_angle(ang + rng.randf_range(-0.5, 0.5))
			var rot_dir: float = -1.0 if rng.randf() < 0.5 else 1.0
			var cl := {
				"sp": sp,
				"layer": li,
				"par": float(L.par),
				"tint": tc,
				"alpha": rng.randf_range(float(L.alpha[0]), float(L.alpha[1])),
				"scale": sc,
				"r": 0.5 * float(tex.get_width()) * sc * OVERLAP_SAFE,
				"vel": vdir * rng.randf_range(float(L.speed[0]), float(L.speed[1])),
				"rot0": rng.randf() * TAU,
				"rot_v": rot_dir * rng.randf_range(float(L.rot[0]), float(L.rot[1])),
				"pw": rng.randf_range(0.10, 0.26),    # yogunluk dalgalanma hizi (rad/sn)
				"pp": rng.randf() * TAU,
				"bw": rng.randf_range(0.05, 0.14),    # olcek nefesi hizi
				"bp": rng.randf() * TAU,
				"u": float(i) / float(n) + rng.randf() * 0.5 / float(n),   # dagilim: katman icinde esit paylasim
				"v": rng.randf(),
			}
			_clouds.append(cl)
		li += 1
	# Kullanilmayan dokulari birak
	for k in _tex_cache.keys():
		if not used.has(k):
			_tex_cache.erase(k)
	_fade = 0.0


func _weighted(rng: RandomNumberGenerator, skip: int) -> int:
	var total := 0.0
	for i in TINTS.size():
		if i != skip:
			total += float(TINT_WEIGHTS[i])
	var r: float = rng.randf() * total
	for i in TINTS.size():
		if i == skip:
			continue
		r -= float(TINT_WEIGHTS[i])
		if r <= 0.0:
			return i
	return 0


func _pick_tint(rng: RandomNumberGenerator, main_i: int, acc_i: int) -> Color:
	var roll: float = rng.randf()
	var idx: int = main_i
	if roll >= 0.55 and roll < 0.85:
		idx = acc_i
	elif roll >= 0.85:
		idx = rng.randi() % TINTS.size()
	var c: Color = TINTS[idx]
	return c.lerp(Color.WHITE, rng.randf_range(0.0, 0.12))


func _get_tex(id: int) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var path: String = TEX_PATH % id
	if not ResourceLoader.exists(path):
		if not _warned:
			_warned = true
			push_warning("SpaceFog: doku bulunamadi: %s (assets/fog klasorunu kopyaladin mi? Godot'ta bir kez iceri aktarilmasi gerekir.)" % path)
		return null
	var tex := load(path) as Texture2D
	if tex != null:
		_tex_cache[id] = tex
	return tex


# ------------------------------------------------------------------ her kare
func _process(delta: float) -> void:
	if _clouds.is_empty() or main == null or not is_instance_valid(main):
		return
	# Gercek zaman: oyuncu hareketinden, girislerden ve oyun hizindan bagimsiz
	var dt: float = minf(delta, 0.1)
	_t += dt * speed
	_fade = minf(1.0, _fade + dt / FADE_IN)
	var fade: float = _fade * _fade * (3.0 - 2.0 * _fade)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	for c in _clouds:
		var sp: Sprite2D = c.sp
		var r: float = c.r
		var period := Vector2(vs.x + 2.0 * r, vs.y + 2.0 * r)
		var raw: Vector2 = Vector2(float(c.u) * period.x, float(c.v) * period.y) + (c.vel as Vector2) * _t
		sp.position = Vector2(fposmod(raw.x, period.x), fposmod(raw.y, period.y)) - Vector2(r, r)
		sp.rotation = float(c.rot0) + float(c.rot_v) * _t
		var s: float = float(c.scale) * (1.0 + BREATH_AMOUNT * sin(_t * float(c.bw) + float(c.bp)))
		sp.scale = Vector2(s, s)
		var a: float = float(c.alpha) * intensity * fade * (1.0 + PULSE_AMOUNT * sin(_t * float(c.pw) + float(c.pp)))
		var tc: Color = c.tint
		sp.modulate = Color(tc.r, tc.g, tc.b, a)


# ------------------------------------------------------------------ kisayollar + kayit
func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_F8:
		return
	if not k.shift_pressed:
		set_enabled(not enabled)
		_say("Uzay sisi: %s" % ("açık" if enabled else "kapalı"))
	else:
		var nq: int = {2: 1, 1: 0, 0: 2}[quality]
		set_quality(nq)
		if nq > 0 and not enabled:
			set_enabled(true)
		_say("Sis kalitesi: %s" % ["kapalı", "düşük", "yüksek"][nq])


func _say(msg: String) -> void:
	if main != null and is_instance_valid(main) and main.has_method("toast"):
		main.toast(msg)


func _load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	enabled = bool(cf.get_value("fog", "enabled", enabled))
	intensity = clampf(float(cf.get_value("fog", "intensity", intensity)), 0.0, 2.0)
	speed = clampf(float(cf.get_value("fog", "speed", speed)), 0.0, 3.0)
	quality = clampi(int(cf.get_value("fog", "quality", quality)), 0, 2)


func _save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("fog", "enabled", enabled)
	cf.set_value("fog", "intensity", intensity)
	cf.set_value("fog", "speed", speed)
	cf.set_value("fog", "quality", quality)
	cf.save(CFG_PATH)
