extends Node3D

const SCI_FONT = preload("res://fonts/Orbitron-Regular.ttf")
const DOData = preload("res://data.gd")
const MAP_TEX := "res://assets/maps/%s.jpg"
const SPAWN_ASTEROIDS := false   # gri 3D asteroit kayalari: false = haritalarda hic olmaz
const MapBg := preload("res://map_bg.gd")
const SpaceFog := preload("res://space_fog.gd")
const UI_TEX := "res://assets/ui/%s.png"
const MiniMap := preload("res://minimap.gd")
const DOHud := preload("res://hud_do.gd")
const ControlPanelScript := preload("res://control_panel.gd")
const LaserFX := preload("res://laser_fx.gd")
const Extras := preload("res://extras.gd")
const SkillTree := preload("res://skill_tree.gd")
const SPACE_BG_SHADER := """
shader_type canvas_item;
uniform vec2 cam = vec2(0.0);
uniform vec2 vp = vec2(1280.0, 720.0);
uniform float stars_on = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec3 star_layer(vec2 px, float cell, float density, float rad, float seed) {
	vec2 g = floor(px / cell);
	vec2 f = fract(px / cell);
	float h = h21(g + seed);
	if (h > density) {
		return vec3(0.0);
	}
	vec2 pos = vec2(h21(g + seed + 17.3), h21(g + seed + 91.7)) * 0.7 + 0.15;
	float d = length((f - pos) * cell);
	float core = smoothstep(rad, 0.0, d);
	float glow = smoothstep(rad * 4.0, 0.0, d) * 0.18;
	float br = 0.45 + 0.55 * h21(g + seed + 5.1);
	br *= 0.8 + 0.2 * sin(TIME * (0.8 + h * 5.0) + h * 60.0);
	float t = h21(g + seed + 33.3);
	vec3 tint = mix(vec3(0.65, 0.78, 1.0), vec3(1.0, 0.86, 0.68), t);
	return tint * (core + glow) * br;
}
void fragment() {
	vec2 px = UV * vp;
	vec3 col = vec3(0.008, 0.01, 0.02);   // sade uzay: yalnizca yildizlar
	// Paralaks yildizlar (uzaktan yakina)
	if (stars_on > 0.5) {
		col += star_layer(px + cam * 0.04, 34.0, 0.55, 0.9, 1.0) * 0.7;
		col += star_layer(px + cam * 0.09, 58.0, 0.45, 1.1, 7.0) * 0.9;
		col += star_layer(px + cam * 0.18, 96.0, 0.35, 1.5, 13.0);
		col += star_layer(px + cam * 0.34, 170.0, 0.25, 2.1, 29.0) * 1.2;
	}
	// Kenarlari hafif karart
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.55;
	COLOR = vec4(col, 1.0);
}
""" 
const RAD_MARGIN := 3000.0     # radyasyon alaninin harita disina uzanma genisligi (DO birimi)
const RAD_MIN_PCT := 0.01      # alana girince saniyede max HP'nin %1'i
const RAD_MAX_PCT := 0.05      # en derinde saniyede max HP'nin %5'i
const HULL_TEX := "res://assets/fx/hull_detail.png"
const CMS_FACTION_COLORS := {
	1: Color("#6C3D23"),
	2: Color("#5A7A9C"),
	3: Color("#409349"),
}
const CMS_HOME_MAP_LIGHTS := ["1-1", "2-1", "3-1"]
const CMS_HOME_KEY_LIGHT := Color("#A3FFFF")
const CMS_HOME_AMBIENT := Color("#FF855C")
const QUESTS := [
	{"id": "q_streuner", "title": "Avcı Eğitimi", "npc": "streuner", "target": 5, "xp": 1200, "cr": 2500, "uri": 0},
	{"id": "q_lordakia", "title": "Sınır Devriyesi", "npc": "lordakia", "target": 3, "xp": 3000, "cr": 5000, "uri": 5},
	{"id": "q_mordon", "title": "Mordon Tehdidi", "npc": "mordon", "target": 2, "xp": 8000, "cr": 12000, "uri": 10},
]

# DarkOrbit hissi icin gemi kontrol sabitleri
const TURN_RATE := 7.0        # rad/sn gemi donus hizi
const ACCEL := 3.0            # max hizin kati / sn (hizlanma)
const BRAKE := 4.5            # max hizin kati / sn (yavaslama)
const ARRIVE_DIST := 0.7      # hedefe varis mesafesi (Godot birimi)

var cam: Camera3D
var world: Node3D
var dust_node: MeshInstance3D
var bullet_mesh: BoxMesh
var mat_player: StandardMaterial3D
var mat_enemy: StandardMaterial3D
var maps: Dictionary
var cur := ""
var map_gen := 0
var SV: Dictionary = {}
var P = null
var enemies: Array = []
var boxes: Array = []
var collect_box = null   # tıklanan, toplanmakta olan bonus kutu
var collect_t := 0.0
const BOX_COLLECT_TIME := 1.5   # toplama animasyonu suresi (sn)
var portals: Array = []
var base_pos = null
var bullets: Array = []
var fxs: Array = []
var pops: Array = []
var target = null
var fire := false
var dest = null
var holding := false
var running := false
var zoom := 1.0
var save_t := 0.0
var jump_t := -1.0
var jump_to = null
const JUMP_TOTAL := 2.0         # atlama geri sayimi (sn)
const JUMP_PULL := 1.2          # son kac saniyede gemi kapinin merkezine cekilir
var jump_flash = null           # tam ekran flas (ColorRect)
var jump_flash_a := 0.0
var jump_arrive_t := -1.0       # varis animasyonu sayaci (-1 = yok)
var jump_arrive_from := Vector3.ZERO
var jump_arrive_to := Vector3.ZERO
var jump_ring_cd := 0.0
var toasts: Array = []
const SafeZone := preload("res://safe_zone.gd")
var in_safe := false          # GERCEK koruma aktif mi (guvenli bolge / gecici gecis korumasi); prot_kind != 0 ile ayni
var prot_kind := 0            # SafeZone.NONE / BASE / PORTAL / ARRIVAL
var net_prot := 0             # cok oyunculu: SUNUCUNUN bildirdigi koruma (istemci yalnizca kaybedebilir, veremez)
var lock_until := -1.0e9      # saldiri kilidi: bu ana kadar koruma geri gelmez (tek oyunculu)
var arrive_until := -1.0e9    # gecici gecis korumasi bitisi (tek oyunculu; varsayilan kapali)
var combat_until := -1.0e9    # catisma zamanlayicisi: kapi kilidi icin (tek oyunculu; hasar almaktan ayri)
var jump_wait_until := -1.0   # sunucudan atlama onayi bekleniyor (cok oyunculu)
var lbl_safe: Label           # "GUVENLI BOLGE" / "GECIS KORUMASI" yazisi (ust-orta)
var lbl_safe_warn: Label      # "GUVENLI BOLGE KALKTI" kisa uyari
var safe_warn_t := 0.0
var rad_acc := 0.0
var rad_in := false
var rad_label: Label
var last_hit := 0.0
# ---- REP-4 otomatik HP tamiri (tum gemilerde varsayilan, donanim/envanter gerektirmez) ----
const REP_DELAY := 10.0        # son hasardan bu kadar sn sonra tamir baslar
const REP_RATE := 10000.0      # saniyede tamir edilen HP (max HP'yi asmaz)
const REP_ATTACK_PAUSE := 1.0  # saldiri bu sureden yeni degilse tamir calisir (ates ederken durur)
var last_attack := -1.0e9
var repairing := false         # HUD: tamir simgesi / yukselis animasyonu
var clock := 0.0
var spd_cur := 0.0
# Otomatik kamera (DarkOrbit gibi: hizlanirken uzaklasir, dururken yaklasir, hedefi cerceveler)
var cam_focus := Vector3.ZERO
var cam_focus_ready := false
var cam_auto := 1.0
var cam_fov_cur := 50.0
const CAM_AUTO_MIN := 0.95    # dururken (hafif yakin)
const CAM_AUTO_MAX := 1.22    # tam hizda (hafif uzak)
const CAM_PITCH_DEG := 58.0   # yerden yukselme acisi (DarkOrbit'in ustten-izometrik bakisina yakin)
const CAM_DIST := 38.0        # zoom=1.0 iken kamera-gemi mesafesi
const CAM_FOLLOW := 7.0       # takip yumusakligi (buyuk = siki)
const CAM_LEAD := 2.5         # giderken geminin onune bakma (Godot birimi)
const CAM_FRAME := 0.22       # hedef varken odagi hedefe dogru kaydirma orani
const CAM_FOV_NEAR := 40.0    # yakin zoom'da dar FOV (daha sinematik)
const CAM_FOV_FAR := 52.0     # uzak zoom'da genis FOV (daha iyi gorus)
var zoom_cur := 1.0
# Kitlenme: ates acik + hedef canliyken gemi burnu HER ZAMAN hedefe bakar, hareket yonu bagimsizdir.
# (false yaparsan gemi hareket ederken gittigi yone bakar, durunca hedefe doner)
const AIM_WHILE_MOVING := true
const AIM_TURN := 9.0         # rad/sn burnun hedefe donus hizi
var move_yaw := 0.0           # geminin GITTIGI yon (burun yonunden ayri tutulur)
var view_rect := Rect2()
var tex_cache := {}
var ship_prev_cache := {}   # market / hangar gemi onizlemeleri (SubViewport dokulari)
var stars_on := true
var star_a: TextureRect
var star_b: TextureRect

var bg_tex: Texture2D = null
var bg_rect: TextureRect
var space_fog   # space_fog.gd (hareketli uzay sisi)
var dest_mark: MeshInstance3D
var target_ring: MeshInstance3D      # hedef halkasi: ince, hedefin boyutuna oturan
var ring_mat: StandardMaterial3D
const RING_SCALE := Vector3(5.0, 1.0, 5.0)   # hedef halkasi: TUM NPC'lerde ayni, sabit boyut

var ui: Control
var menu: Control
var base_menu: Control
var base_list: VBoxContainer
var base_money: Label
var lbl_prompt: Label
var lbl_toast: Label
var lbl_help: Label
var tpanel: Control
var gal_panel: Control
var gal_marks := {}
var mm = null
var mm_strip: Control
var hud := {}
var dohud = null
var hud_nodes: Array = []
var slots: Array = []
var fire_btn: Button
var sb_slot_n: StyleBoxFlat
var sb_slot_sel: StyleBoxFlat
var slot_sel_cache := ""
var last_nammo := -10.0
var fire_cache := false
var drone_nodes: Array = []
var drone_sig := ""
var drone_mats := {}
var fx2: Array = []
var fx_sphere: SphereMesh
var fx_spark: BoxMesh
var bolt_meshes := {}
var bolt_mats := {}
var scene_environment: Environment
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var space_rect: ColorRect
var space_material: ShaderMaterial
var cfg_cool := 0.0
var last_nolaser := -10.0
var rocket_cd := 0.0
var rsb_cd := 0.0           # RSB-75 yeniden kullanim beklemesi (sn)
var rsb_prev := ""          # RSB'den onceki muhimmat: RSB atildiktan sonra otomatik buna donulur
var extras = null           # Ozel esyalar (extras.gd): Nukleer, Koruma, EMA, Tamir, ENC
# --- COK OYUNCULU ---
var net_wanted: bool = true      # oyun tamamen cevrimici
var net_addr: String = ""
var net_on: bool:
	get:
		return Net.online
var rocket_count_label: Label


func w2g(x: float, y: float) -> Vector3:
	return Vector3(x * DOData.S, 0.0, y * DOData.S)


func ship_def() -> Dictionary:
	if SV.is_empty() or not SV.has("ship"):
		return DOData.SHIPS[0]
	for s in DOData.SHIPS:
		if s.id == SV.ship:
			return s
	return DOData.SHIPS[0]


func max_sh() -> float:
	var t := 0.0
	var c := cfg()
	for id in c.gen:
		var g: Dictionary = DOData.GENS[id]
		if g.type == "sh":
			t += float(g.val)
	for id in drone_items(c):
		if DOData.GENS.has(id) and str(DOData.GENS[id].type) == "sh":
			t += float(DOData.GENS[id].val)
	return maxf(0.0, t * (1.0 + drone_bonus("sh") + skill_bonus("shield_pct")))


func skill_rank(id: String) -> int:
	var ranks: Dictionary = SV.get("skills", {})
	return int(ranks.get(id, 0))


# Pilot Bio: ayni etki (effect) icin I/II yeteneklerinden EN YUKSEK bonus gecerlidir (toplanmaz).
func skill_bonus(effect: String) -> float:
	var best := 0.0
	for sk in SkillTree.SKILLS:
		if str(sk.effect) != effect:
			continue
		var r := clampi(skill_rank(str(sk.id)), 0, int(sk.pts))
		if r <= 0:
			continue
		best = maxf(best, float(sk.bonus) * float(r) / float(sk.pts))
	return best


# Azami can = gemi cani + Ship Hull bonusu
func max_hp() -> float:
	return float(ship_def().hp) + skill_bonus("hp_flat")


# Isabet sansi: lazer temel %88 (+Electro-Optics), roket temel %90 (+Heat Seeking) -> en fazla %100
func hit_chance(rocket: bool) -> float:
	if rocket:
		return clampf(0.90 + skill_bonus("rocket_acc"), 0.0, 1.0)
	return clampf(0.88 + skill_bonus("laser_acc"), 0.0, 1.0)


# Market / hangar karti icin gemiyi oyundaki GUNCEL 3D modelinden (renk + ek kanatlar dahil) cizer.
# Her gemi icin bir kez kucuk bir SubViewport kurulur ve tek kare render edilir; sonuc onbellekte tutulur.
func ship_preview_tex(id: String) -> Texture2D:
	if Net.is_server:
		return null
	if ship_prev_cache.has(id):
		return ship_prev_cache[id]
	var ship := make_ship(id, 6.0, ship_faction_tint())
	if ship == null:
		ship_prev_cache[id] = null
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	vp.add_child(ship)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 10.5, -6.5), Vector3.ZERO, Vector3.UP)
	cam.current = true
	var tex: Texture2D = vp.get_texture()
	ship_prev_cache[id] = tex
	return tex


func _tex(path: String) -> Texture2D:
	if tex_cache.has(path):
		return tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	tex_cache[path] = t
	return t


func _ready() -> void:
	if Net.is_server:
		# Dedicated sunucu sureci: oyun arayuzu/dunyasi kurulmaz (sunucu mantigi net_server.gd'de)
		set_process(false)
		set_process_unhandled_input(false)
		return
	Net.attach(self)
	# SV'yi her zaman başlat (eksik anahtar hatasını önler)
	if SV.is_empty():
		SV = {"faction": 1, "cr": 5000, "uri": 0, "xp": 0.0, "hon": 0.0, "ship": "phoenix", "owned": ["phoenix"], "sel": "x1",
		"ammo": {"x1": 5000, "x2": 500, "x3": 200, "x4": 0, "sab": 0}, "rockets": 50,
		"map": "1-1", "px": 0.0, "pz": 0.0, "kills": 0, "callsign": "Gezgin",
		"inv": {"lf1": 4, "sg3n-a01": 1}, "forms": ["std"], "loads": {}, "cfgi": 0, "free": false,
		"quests": {}, "skills": {}, "skill_points": 0, "maps_visited": [], "route_to": "",
		"settings": {"stars": true, "zoom": 1.0, "graphics": 2},
		"reg_ts": Time.get_unix_time_from_system(), "pvp_kills": 0, "rank_pen": 0.0}
		ensure_campaign_data()
		ensure_loadout()
	ThemeDB.fallback_font = SCI_FONT
	ThemeDB.fallback_font_size = 16
	extras = Extras.new(self)
	extras.preload_anims()
		
	# --- DARK GLASS UI THEME ---
	var theme = Theme.new()
	theme.default_font = SCI_FONT
	
	# Butonlar için cam efekti
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.05, 0.1, 0.15, 0.85)
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = Color(0.2, 0.5, 0.8, 0.6)
	btn_normal.set_corner_radius_all(4)
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.1, 0.2, 0.3, 0.95)
	btn_hover.border_color = Color(0.4, 0.8, 1.0, 1.0)
	
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_normal)
	theme.set_color("font_color", "Button", Color(0.8, 0.9, 1.0))
	
	# Paneller için cam efekti
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.05, 0.1, 0.9) 
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.2, 0.5, 0.8, 0.8)
	panel_style.set_corner_radius_all(6)
	theme.set_stylebox("panel", "Panel", panel_style)
	
	if has_node("CanvasLayer"):
		get_node("CanvasLayer").theme = theme

	randomize()
	maps = DOData.make_maps()
	scene_environment = Environment.new()
	scene_environment.background_mode = Environment.BG_CANVAS
	scene_environment.background_canvas_max_layer = -1
	scene_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene_environment.ambient_light_color = Color(0.7, 0.8, 1.0)
	scene_environment.ambient_light_energy = 1.0
		
	# Bloom (Parlama) Ayarları
	scene_environment.glow_enabled = true
	scene_environment.glow_intensity = 0.6
	scene_environment.glow_bloom = 0.05
	scene_environment.glow_hdr_threshold = 1.0
	scene_environment.tonemap_exposure = 0.8
	scene_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	scene_environment.ssao_enabled = true
	
	var we := WorldEnvironment.new()
	we.environment = scene_environment
	add_child(we)
	
	# Uzayın soğuk, karanlık havasını hissettirecek yönlü ışık
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(0.6, 0.7, 1.0)
	add_child(sun)
	
	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-55, 30, 0)
	sun_light.light_energy = 0.8
	add_child(sun_light)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-35, -150, 0)
	fill_light.light_energy = 0.55
	fill_light.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill_light)
	
	# Ana ışık kaynagi - gemi ve cevredaki nesneleri aydinlatir
	var key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45, 30, 0)
	key_light.light_energy = 0.8
	key_light.light_color = Color(0.9, 0.95, 1.0)
	key_light.shadow_enabled = false
	add_child(key_light)
	
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	bullet_mesh = BoxMesh.new()
	bullet_mesh.size = Vector3(0.25, 0.25, 2.2)
	mat_player = _unshaded(Color(0.4, 1.0, 0.8))
	mat_enemy = _unshaded(Color(1.0, 0.3, 0.35))
	fx_sphere = SphereMesh.new()
	fx_sphere.radius = 0.5
	fx_sphere.height = 1.0
	fx_sphere.radial_segments = 16
	fx_sphere.rings = 8
	fx_spark = BoxMesh.new()
	fx_spark.size = Vector3(0.08, 0.08, 0.6)
	_build_background()
	_build_markers()
	_build_ui()
	bg_tex = _tex(MAP_TEX % "1-1")
	_update_bg()
	run_damage_tests()


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _build_background() -> void:
	var bl := CanvasLayer.new()
	bl.layer = -1
	add_child(bl)
	bg_rect = TextureRect.new()
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bl.add_child(bg_rect)
	var smat := CanvasItemMaterial.new()
	smat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	star_a = _star_rect("res://assets/fx/stars_a.png", smat, bl)
	star_b = _star_rect("res://assets/fx/stars_b.png", smat, bl)
	star_b.modulate = Color(1, 1, 1, 0.3)
	# Procedural uzay arka plani: 4 katmanli paralaks yildiz (resim gerektirmez)
	bg_rect.visible = false
	star_a.visible = false
	star_b.visible = false
	var sh := Shader.new()
	sh.code = MapBg.SHADER
	space_material = ShaderMaterial.new()
	space_material.shader = sh
	space_rect = ColorRect.new()
	space_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space_rect.material = space_material
	space_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bl.add_child(space_rect)
	bl.move_child(space_rect, 0)
	# Uzay sisi: arka plan katmaninda (3D dunyanin ARKASINDA), uzay shader'indan sonra cizilir.
	space_fog = SpaceFog.new()
	bl.add_child(space_fog)
	space_fog.attach(self)
	var wl := CanvasLayer.new()
	wl.layer = 60
	add_child(wl)
	rad_label = Label.new()
	rad_label.text = "!  RADYASYON ALANI  !\nHaritaya geri dön"
	rad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rad_label.add_theme_font_size_override("font_size", 26)
	rad_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	rad_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rad_label.add_theme_constant_override("outline_size", 6)
	rad_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rad_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	rad_label.offset_left = -260.0
	rad_label.offset_right = 260.0
	rad_label.offset_top = 90.0
	rad_label.visible = false
	wl.add_child(rad_label)


func _star_rect(path: String, mat: CanvasItemMaterial, bl: CanvasLayer) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _tex(path)
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = mat
	bl.add_child(r)
	return r


func ship_faction_tint(faction := -1) -> Color:
	var active_faction := faction
	if active_faction < 1:
		active_faction = int(SV.get("faction", 0))
	if not CMS_FACTION_COLORS.has(active_faction):
		return Color.WHITE
	return Color.WHITE.lerp(CMS_FACTION_COLORS[active_faction], 0.32)


func _apply_map_color_theme(map_name: String, map_data: Dictionary) -> void:
	if map_name in CMS_HOME_MAP_LIGHTS:
		sun_light.light_color = Color(0.1, 0.1, 0.15)
		fill_light.light_color = Color(0.1, 0.1, 0.15)
		scene_environment.ambient_light_color = Color(0.1, 0.1, 0.15)
		scene_environment.ambient_light_energy = 0.2
		sun_light.light_energy = 0.2
		fill_light.light_energy = 0.2
	else:
		sun_light.light_color = Color(0.1, 0.1, 0.15)
		fill_light.light_color = Color(0.1, 0.1, 0.15)
		scene_environment.ambient_light_color = Color(0.1, 0.1, 0.15)
		scene_environment.ambient_light_energy = 0.2
		sun_light.light_energy = 0.2
		fill_light.light_energy = 0.2


func _update_bg() -> void:
	if space_material == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var sc := Vector2.ZERO
	if P != null:
		sc = Vector2(P.node.position.x, P.node.position.z)
	space_material.set_shader_parameter("cam", sc * 14.0)
	space_material.set_shader_parameter("vp", vs)
	space_material.set_shader_parameter("stars_on", 1.0 if stars_on else 0.0)
	MapBg.update(self, space_material)


func _build_markers() -> void:
	# Hedef halkasi: tek ince serit (torus), yari saydam turuncu/kirmizi, golgesiz.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.97
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 4
	ring_mat = _unshaded(Color(1.0, 0.5, 0.15, 0.75))
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_ring = MeshInstance3D.new()
	target_ring.mesh = tm
	target_ring.material_override = ring_mat
	target_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target_ring.visible = false
	target_ring.top_level = true   # ebeveyn donusunden etkilenmesin; global konumla yerlestirilir
	target_ring.scale = RING_SCALE
	add_child(target_ring)
	var dm := TorusMesh.new()
	dm.inner_radius = 0.82
	dm.outer_radius = 1.0
	dest_mark = MeshInstance3D.new()
	dest_mark.mesh = dm
	dest_mark.material_override = _unshaded(Color(0.4, 1.0, 0.45))
	dest_mark.visible = false
	add_child(dest_mark)


func tag(text: String, pos: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.pixel_size = 0.02 * BAR_FS   # fixed_size: birim "1 birim uzaklikta" olculur, bu yuzden kucuk carpan
	l.modulate = col
	l.position = pos
	l.no_depth_test = true
	l.fixed_size = true
	return l


# Kapi / ust yazilari icin sade, okunakli etiket: kucuk puntolu, koyu kontur, buyuk harf. (Gemi/NPC isimleri tag() ile aynen devam eder.)
func label_pro(text: String, pos: Vector3, col: Color, fs: int = 34) -> Label3D:
	var l := tag(text, pos, col)
	l.font_size = fs
	l.outline_size = 10
	l.outline_modulate = Color(0.02, 0.05, 0.1, 0.95)
	l.render_priority = 2
	l.outline_render_priority = 1
	return l


# Modelin EN UST noktasini gemilerin ucus duzleminin (y=0) altina indirir: gemi artik modelin ALTINDA degil USTUNDE gorunur.
# Node sahneye eklenmis olmali (global donusum kullanilir).
func _sink_below_plane(root: Node3D, margin: float) -> void:
	var top := -1.0e9
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		top = maxf(top, bb.end.y)
	if top > -1.0e8 and top + margin > 0.0:
		root.position.y -= top + margin


var STYLES := {
	"phoenix": [Color(0.55, 0.70, 0.95), 0.65, 0.30, Color(0.25, 0.65, 1.0), 0.30],
	"yamato": [Color(0.95, 0.75, 0.35), 0.70, 0.28, Color(1.0, 0.65, 0.2), 0.30],
	"leonov": [Color(0.85, 0.88, 0.95), 0.60, 0.30, Color(1.0, 0.55, 0.2), 0.25],
	"defcom": [Color(0.34, 0.38, 0.46), 0.60, 0.34, Color(1.0, 0.55, 0.15), 0.30],
	"liberator": [Color(0.80, 0.35, 0.35), 0.60, 0.32, Color(1.0, 0.3, 0.3), 0.30],
	"piranha": [Color(0.25, 0.75, 0.80), 0.60, 0.30, Color(0.2, 1.0, 0.9), 0.30],
	"nostromo": [Color(0.68, 0.48, 0.90), 0.60, 0.30, Color(0.8, 0.4, 1.0), 0.30],
	"bigboy": [Color(0.95, 0.55, 0.22), 0.55, 0.35, Color(1.0, 0.5, 0.1), 0.30],
	"spearhead": [Color(0.45, 0.48, 0.58), 0.75, 0.25, Color(1.0, 0.2, 0.2), 0.45],
	"vengeance": [Color(0.85, 0.18, 0.25), 0.65, 0.28, Color(1.0, 0.25, 0.3), 0.40],
	"goliath": [Color(0.30, 0.55, 0.95), 0.65, 0.28, Color(0.3, 0.7, 1.0), 0.40],
	"aegis": [Color(0.78, 0.90, 1.0), 0.55, 0.28, Color(0.5, 0.9, 1.0), 0.40],
	"citadel": [Color(0.45, 0.52, 0.65), 0.75, 0.30, Color(0.4, 0.8, 1.0), 0.35],
	"streuner": [Color("#D9854D"), 0.35, 0.45, Color("#FF762E"), 0.52],
	"lordakia": [Color("#62D94F"), 0.35, 0.40, Color("#67FF38"), 0.62],
	"saimon": [Color("#E8D24E"), 0.40, 0.40, Color("#FFE760"), 0.55],
	"mordon": [Color("#B44ADE"), 0.45, 0.38, Color("#D44FFF"), 0.58],
	"devolarium": [Color("#42C6E6"), 0.45, 0.35, Color("#45E9FF"), 0.60],
	"sibelon": [Color("#E85C32"), 0.45, 0.38, Color("#FF4A1F"), 0.60],
	"kristallin": [Color("#4CBAEE"), 0.20, 0.12, Color("#42C9FF"), 1.00],
	"kristallon": [Color("#AD72F2"), 0.20, 0.12, Color("#9C55FF"), 1.00],
	"devourer": [Color("#A84646"), 0.40, 0.45, Color("#FF3929"), 0.58],
	"jumpgate-regular": [Color("#42A6F5"), 0.60, 0.30, Color("#36D5FF"), 1.70],
	"building-base-mmo": [Color(1, 1, 1), 0.50, 0.40, Color(0, 0, 0), 0.0],
	"building-base-eic": [Color(1, 1, 1), 0.50, 0.40, Color(0, 0, 0), 0.0],
	"building-base-vru": [Color(1, 1, 1), 0.50, 0.40, Color(0, 0, 0), 0.0],
	"asset-mmo-asteroid": [Color(0.55, 0.47, 0.40), 0.05, 0.92, Color(0.0, 0.0, 0.0), 0.0],
	"asset-mmo-asteroid-b": [Color(0.50, 0.44, 0.40), 0.05, 0.92, Color(0.0, 0.0, 0.0), 0.0],
}
var DEFAULT_STYLE := [Color(0.75, 0.78, 0.85), 0.55, 0.38, Color(0.3, 0.55, 0.9), 0.15]
var glow_mats := {}


func _style_mat(n: String, tint: Color) -> StandardMaterial3D:
	var st: Array = STYLES.get(n, DEFAULT_STYLE)
	var d := StandardMaterial3D.new()
	d.albedo_color = (st[0] as Color) * tint
	d.metallic = st[1]
	d.metallic_specular = 0.8
	d.roughness = st[2]
	# Gövde emission'ı kapalı (beyaz patlaması düzeltmesi); motor parlaması ayrı _glow_mat kürelerinde.
	d.emission_enabled = false
	d.emission_energy_multiplier = 0.0
	d.rim_enabled = true
	d.rim = 0.5
	d.rim_tint = 0.6
	var real := "res://assets/tex/%s_diffuse.png" % n
	if ResourceLoader.exists(real):
		d.albedo_texture = load(real)
		d.uv1_scale = Vector3.ONE
		d.albedo_color = tint
		# *_glow.png emission dokusu artık gövdede kullanılmıyor (aşırı parlama).
	return d


var ship_mat_cache := {}


func _ship_mat(n: String, mi: MeshInstance3D, s: int, tint: Color) -> Material:
	var orig: Material = mi.mesh.surface_get_material(s)
	if n.begins_with("building-base-") and orig != null:
		return orig   # sirket usleri: modelin kendi materyalleri aynen kalir
	if orig is BaseMaterial3D and (orig as BaseMaterial3D).albedo_texture != null:
		var key := "%d|%s" % [orig.get_instance_id(), tint.to_html()]
		if ship_mat_cache.has(key):
			return ship_mat_cache[key]
		var m: BaseMaterial3D = (orig as BaseMaterial3D).duplicate()
		m.albedo_color = Color.WHITE.lerp(tint, 0.4)
		m.metallic = 0.12
		m.roughness = 0.5
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.5
		m.emission_enabled = false
		m.emission_energy_multiplier = 0.0
		ship_mat_cache[key] = m
		return m
	return _style_mat(n, tint)


# ---------- 3D can/kalkan barı (oyuncu + NPC ortak) ----------
var player_bar: Dictionary = {}


# Barlar kamera mesafesinden bagimsiz EKRANDA SABIT boyutta kalir (material.fixed_size = true).
# fixed_size acikken geometri "kameraya 1 birim uzaklikta" olculur; BAR_FS bu yuzden kucuk bir carpandir.
# Tum geometri (konum ofsetleri dahil) mesh icinde (center_offset) tutulur; node'lar hep (0,0,0)'dadir.
const BAR_W := 2.1
const BAR_FS := 1.0 / 38.0
const BAR_PAD := 0.0    # bar ile gemi kenari arasindaki sabit ekran boslugu (bar birimi)
# Bar / isim mesafesi = geminin EKRANDAKI dikey yari yuksekligi * katsayi (alt sinirli):
# yakinlasinca referanstaki gibi genis, uzaklasinca gemiye yapisik; boyutlari ise sabit.
const BAR_K := 1.8
const NAME_K := 1.8
const BAR_MIN_PX := 16.0
const NAME_MIN_PX := 15.0


# Ekranda gemi merkezinden sabit piksel ofsetli dunya noktasi (gemi ile ayni derinlikte; FOV/zoom'dan bagimsiz).
func _screen_off_pos(world: Vector3, off_px: Vector2) -> Vector3:
	var depth: float = (world - cam.global_position).dot(-cam.global_transform.basis.z)
	if depth <= 0.01:
		return world
	return cam.project_position(cam.unproject_position(world) + off_px, depth)


func _off_px(world: Vector3, node: Node3D, k: float, min_px: float) -> float:
	var r: float = float(node.get_meta("r", 3.0)) * 0.6   # gemi dikey yari yuksekligi (dunya birimi)
	var a: Vector2 = cam.unproject_position(world)
	var b: Vector2 = cam.unproject_position(world + cam.global_transform.basis.y * r)
	return maxf(absf(a.y - b.y) * k, min_px)


func _bar_mat(c: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.fixed_size = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.render_priority = prio
	return m


func _bar_quad(sz: Vector2, c: Color, prio: int, center: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = sz
	q.center_offset = center
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _bar_mat(c, prio)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 100.0
	return mi


# Gemiye bagli ama donusunden etkilenmeyen (top_level) DarkOrbit tarzi bar:
# ince, duz, iki satir: ustte can (yesil), altta kalkan (mavi). Ekranda sabit boyutlu.
# Donen: {root, hp_fill, sh_fill, w, off_y}
func _make_bar3d(ship: Node3D, w: float, off_y: float) -> Dictionary:
	var bh: float = maxf(w * 0.045, 0.12)
	var gap: float = bh * 0.55
	var root := Node3D.new()
	root.top_level = true
	ship.add_child(root)
	var res := {"root": root, "w": w, "off_y": off_y}
	var rows := [["hp_fill", (bh + gap) * 0.5, Color(0.3, 0.9, 0.2, 1.0)], ["sh_fill", -(bh + gap) * 0.5, Color(0.25, 0.65, 1.0, 1.0)]]
	for r in rows:
		var y: float = float(r[1]) + BAR_PAD
		var slot := _bar_quad(Vector2(w, bh) * BAR_FS, Color(0.08, 0.09, 0.1, 0.55), 11, Vector3(0.0, y * BAR_FS, 0.0))
		root.add_child(slot)
		var fill := _bar_quad(Vector2(w, bh) * BAR_FS, r[2], 12, Vector3(0.0, y * BAR_FS, 0.0))
		fill.set_meta("bw", w)
		fill.set_meta("bh", bh)
		fill.set_meta("by", y)
		root.add_child(fill)
		res[r[0]] = fill
	return res


func _set_bar3d_ratio(fill: MeshInstance3D, ratio: float, w: float) -> void:
	if fill == null or not is_instance_valid(fill):
		return
	var r: float = clampf(ratio, 0.0, 1.0)
	fill.visible = r > 0.002
	var q := fill.mesh as QuadMesh
	if q == null:
		return
	var bh: float = float(fill.get_meta("bh", 0.18))
	var by: float = float(fill.get_meta("by", 0.0))
	var wr: float = maxf(w * r, 0.0001)
	q.size = Vector2(wr, bh) * BAR_FS
	q.center_offset = Vector3((-w * 0.5 + wr * 0.5) * BAR_FS, by * BAR_FS, 0.0)


func _ui_blocking() -> bool:
	return (base_menu != null and is_instance_valid(base_menu) and base_menu.visible) \
		or (gal_panel != null and is_instance_valid(gal_panel) and gal_panel.visible)


# Her karede: oyuncu + NPC barlarının konumu / oranı / görünürlüğü. Kontrol Merkezi veya harita açıkken hepsi gizlenir.
func _update_bars3d() -> void:
	var blocked: bool = _ui_blocking()
	var show_world: bool = running and not blocked
	_update_plate(show_world)
	if not player_bar.is_empty():
		var pr = player_bar.get("root")
		if pr != null and is_instance_valid(pr):
			var ok: bool = show_world and P != null and is_instance_valid(P.node)
			pr.visible = ok
			if ok:
				pr.global_position = _screen_off_pos(P.node.global_position, Vector2(0.0, -_off_px(P.node.global_position, P.node, BAR_K, BAR_MIN_PX)))
				var mhp_p: float = maxf(max_hp(), 1.0)
				var msh_p: float = maxf(max_sh(), 1.0)
				_set_bar3d_ratio(player_bar.get("hp_fill"), float(P.hp) / mhp_p, float(player_bar.w))
				_set_bar3d_ratio(player_bar.get("sh_fill"), float(P.sh) / msh_p, float(player_bar.w))
	for e in enemies:
		var nt = e.get("name_tag")
		if e.get("plate") != null:
			var alive_p: bool = is_instance_valid(e.node) and e.hp > 0
			update_remote_plate(e.get("plate"), e.node if is_instance_valid(e.node) else null, alive_p and running and not blocked)
			if nt != null and is_instance_valid(nt):
				nt.visible = false
		elif nt != null and is_instance_valid(nt):
			var alive: bool = is_instance_valid(e.node) and e.hp > 0
			nt.visible = alive and running and not blocked
			if alive:
				nt.global_position = _screen_off_pos(e.node.global_position, Vector2(0.0, _off_px(e.node.global_position, e.node, NAME_K, NAME_MIN_PX) + 6.0))
		var hb = e.get("hp_back")
		if hb == null or not is_instance_valid(hb):
			continue
		if not is_instance_valid(e.node) or e.hp <= 0 or blocked or not running:
			hb.visible = false
			continue
		var is_target: bool = (e == target)
		hb.visible = is_target
		if is_target:
			var w: float = float(e.get("bar_w", 4.0))
			hb.global_position = _screen_off_pos(e.node.global_position, Vector2(0.0, -_off_px(e.node.global_position, e.node, BAR_K, BAR_MIN_PX)))
			_set_bar3d_ratio(e.get("hp_fill"), e.hp / maxf(e.mx, 1.0), w)
			_set_bar3d_ratio(e.get("sh_fill"), e.sh / maxf(e.msh, 1.0), w)


func _glow_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if glow_mats.has(key):
		return glow_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	glow_mats[key] = m
	return m


var ship_yaw_logged := {}


func _rel_xf(nd: Node3D, stop: Node) -> Transform3D:
	var t: Transform3D = nd.transform
	var p: Node = nd.get_parent()
	while p != null and p != stop and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _is_unit_model(n: String) -> bool:
	return not (n.begins_with("asset-") or n.begins_with("building") or n.begins_with("jumpgate"))


# Sirket usleri: yeni ad bulunamazsa yuklenen orijinal dosya adlari da denenir.
const BASE_MODEL_ALIASES := {
	"building-base-mmo": ["sci-fi_space_station"],
	"building-base-eic": ["sci-fi_space_station_2"],
	"building-base-vru": ["sci-fi_space_station_rotor_nexus"],
}


func _load_model(n: String):
	var names: Array = [n]
	names.append_array(BASE_MODEL_ALIASES.get(n, []))
	for nm in names:
		var path := "res://models/%s.glb" % nm
		if ResourceLoader.exists(path):
			var r = load(path)
			if r != null:
				return r
	return null


func make_ship(n: String, size: float, tint: Color) -> Node3D:
	var root := Node3D.new()
	var tilt := Node3D.new()
	root.add_child(tilt)
	root.set_meta("tilt", tilt)
	var pivot := Node3D.new()
	tilt.add_child(pivot)
	var res = _load_model(n)
	if res == null:
		push_warning("Model bulunamadi: " + n)
		if n.begins_with("building-base-"):
			print("[UYARI] Sirket usu modeli yuklenemedi: res://models/%s.glb yok ya da Godot henuz import etmedi." % n)
		return root
	var holder := Node3D.new()
	pivot.add_child(holder)
	var model: Node3D = res.instantiate()
	holder.add_child(model)
	var hull := AABB()
	var have := false
	var front := Vector3.ZERO
	var has_front := false
	var side_sum := Vector3.ZERO
	var side_n := 0
	var engines: Array = []
	var laserpoints: Array = []   # geminin gercek lazer silah noktalari (laserpoint_* node'lari)
	var all_nodes: Array = [model]
	all_nodes.append_array(model.find_children("*", "Node3D", true, false))
	for item in all_nodes:
		var node3: Node3D = item as Node3D
		if node3 == null:
			continue
		var nm: String = str(node3.name)
		var xf: Transform3D = _rel_xf(node3, holder)
		var mi: MeshInstance3D = node3 as MeshInstance3D
		var bb := AABB()
		var has_bb := false
		if mi != null and mi.mesh != null:
			bb = xf * mi.get_aabb()
			has_bb = true
		if nm.begins_with("laserpoint") or nm.begins_with("light_position") or nm.begins_with("engine"):
			node3.visible = false
			if nm.begins_with("laserpoint"):
				laserpoints.append(node3)
			var mpos: Vector3 = xf.origin
			if has_bb:
				mpos = bb.get_center()
			if nm.begins_with("laserpoint_centerFront"):
				front = mpos
				has_front = true
			elif nm.begins_with("laserpoint") and nm.contains("Front"):
				side_sum += mpos
				side_n += 1
			elif nm.begins_with("engine"):
				engines.append(mpos)
		elif has_bb:
			hull = bb if not have else hull.merge(bb)
			have = true
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, _ship_mat(n, mi, s, tint))
	root.set_meta("lpts", laserpoints)   # atis zamaninda gercek cikis noktalari okunur
	if not have:
		return root
	var c := hull.get_center()
	var tol: float = maxf(hull.size.x, hull.size.z) * 0.06
	var have_dir := false
	var hv := Vector2.ZERO
	if has_front:
		var d1 := front - c
		if Vector2(d1.x, d1.z).length() > tol:
			hv = Vector2(d1.x, d1.z)
			have_dir = true
	if not have_dir and side_n > 0:
		var d2: Vector3 = side_sum / float(side_n) - c
		if Vector2(d2.x, d2.z).length() > tol:
			hv = Vector2(d2.x, d2.z)
			have_dir = true
	if not have_dir and engines.size() > 0:
		var eng_c := Vector3.ZERO
		for ec in engines:
			eng_c += ec
		eng_c /= float(engines.size())
		var d3 := c - eng_c
		if Vector2(d3.x, d3.z).length() > tol:
			hv = Vector2(d3.x, d3.z)
			have_dir = true
	var yaw := 0.0
	if have_dir:
		yaw = snappedf(atan2(hv.x, hv.y), PI * 0.5)
	elif _is_unit_model(n):
		yaw = PI
	yaw += deg_to_rad(float(DOData.MODEL_YAW_FIX.get(n, 0.0)))
	if not ship_yaw_logged.has(n):
		ship_yaw_logged[n] = true
		print("[make_ship] %s: burun yonu %s, donus=%d derece" % [n, ("isaretciden" if have_dir else "varsayilan"), roundi(rad_to_deg(yaw))])
	var k: float = size / maxf(maxf(hull.size.x, hull.size.z), 0.001)
	var st: Array = STYLES.get(n, DEFAULT_STYLE)
	var gc: Color = st[3]
	if engines.size() > 0 and (gc.r + gc.g + gc.b) > 0.0:
		var gr: float = maxf(hull.size.x, hull.size.z) * 0.04
		for ec in engines:
			var g := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = gr
			sp.height = gr * 2.0
			g.mesh = sp
			g.material_override = _glow_mat(gc)
			g.position = ec
			g.add_to_group("engine_glow")
			holder.add_child(g)
	holder.scale = Vector3.ONE * k
	holder.position = -c * k
	pivot.rotation.y = -yaw
	ShipUpgrades.apply(n, pivot, holder, hull, engines, yaw, k, tint)   # satilan gemilere ek kanat / duman
	root.set_meta("r", size * 0.5)
	return root


func _n(v: float) -> String:
	var s := str(maxi(0, int(v)))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out


func _do_style(bg := Color(0.02, 0.05, 0.1, 0.6), border := Color(0.28, 0.55, 0.72, 0.95)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# Buyuk HUD panelleri icin glassmorphism stil: yari seffaf koyu zemin + yumusak neon kenar
func _glass_style(bg := Color(0.015, 0.045, 0.09, 0.74), border := Color(0.32, 0.62, 0.88, 0.9)) -> StyleBoxFlat:
	var sb := _do_style(bg, border)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	return sb


func _do_panel(parent: Node, pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_theme_stylebox_override("panel", _do_style())
	parent.add_child(p)
	return p


func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _lbl(pos: Vector2, parent: Node, size := 15) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", SCI_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l


func _col_lbl(pos: Vector2, parent: Node, size: int, col: Color) -> Label:
	var l := _lbl(pos, parent, size)
	l.add_theme_color_override("font_color", col)
	return l


func _hbar(parent: Control, pos: Vector2, sz: Vector2, col: Color, tag := "") -> Dictionary:
	var back := Panel.new()
	back.position = pos
	back.size = sz
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := _do_style(Color(0.02, 0.03, 0.05, 0.92), Color(0.3, 0.48, 0.6, 0.9))
	bs.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", bs)
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.color = col
	fill.position = Vector2(2, 2)
	fill.size = Vector2(sz.x - 4.0, sz.y - 4.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	# Dinamik dolgu/ metin; varsa HP/SHIELD etiketi sol tarafta sabit durur, metin merkezde kalir.
	var l := Label.new()
	var left := 62.0 if tag != "" else 0.0
	l.position = Vector2(left, 0)
	l.size = Vector2(sz.x - left - 6.0, sz.y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", SCI_FONT)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	back.add_child(l)
	if tag != "":
		var t := Label.new()
		t.position = Vector2(8, 0)
		t.size = Vector2(52, sz.y)
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_theme_font_override("font", SCI_FONT)
		t.add_theme_font_size_override("font_size", 10)
		t.add_theme_color_override("font_color", col.lightened(0.55))
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		t.add_theme_constant_override("outline_size", 4)
		back.add_child(t)
	return {"fill": fill, "lbl": l, "w": sz.x - 4.0, "h": sz.y - 4.0}


func _set_bar(b: Dictionary, v: float, txt: String) -> void:
	var f: ColorRect = b.fill
	f.size = Vector2(float(b.w) * clampf(v, 0.0, 1.0), float(b.h))
	var l: Label = b.lbl
	l.text = txt


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = SCI_FONT
	th.set_stylebox("normal", "Button", _do_style(Color(0.06, 0.1, 0.15, 0.95), Color(0.25, 0.45, 0.6)))
	th.set_stylebox("hover", "Button", _do_style(Color(0.1, 0.2, 0.3, 0.95), Color(0.4, 0.75, 0.95)))
	th.set_stylebox("pressed", "Button", _do_style(Color(0.15, 0.3, 0.4, 1.0), Color(1.0, 0.78, 0.3)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.85, 0.93, 1.0))
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", Color(1.0, 0.85, 0.4))
	th.set_font_size("font_size", "Button", 14)
	return th


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	layer.add_child(ui)
	_build_dohud()
	_build_galaxy_map()
	_build_base_menu(ui)
	_build_main_menu(ui)
	for n in hud_nodes:
		n.visible = false


func _build_dohud() -> void:
	# DarkOrbit tarzi yeni HUD (hud_do.gd): bilgi, hedef, minimap, ozellik menusu, cephane cubugu, sohbet, arkadas, gorev
	dohud = DOHud.new()
	dohud.game = self
	ui.add_child(dohud)
	dohud.build()
	hud_nodes.append(dohud)
	mm = dohud.minimap
	lbl_toast = dohud.lbl_toast
	lbl_prompt = dohud.lbl_prompt
	lbl_help = dohud.lbl_help
	# v3 HUD'da ATES dugmesi yok (ates: Ctrl / Bosluk / hedefe tekrar tik); fire_btn artik bagli degil.


func _layout_right() -> void:
	if dohud == null:
		return
	dohud.layout_right()
	for n in hud_nodes:
		if is_instance_valid(n) and n != base_menu and n != gal_panel:
			n.visible = true


func _on_minimap_move(wx: float, wz: float) -> void:
	if not running or base_menu.visible or gal_panel.visible:
		return
	dest = _clamp_map(Vector3(wx, 0.0, wz))


func _quit_game() -> void:
	save_game()
	get_tree().quit()


func _toggle_fire_btn() -> void:
	_set_fire(not fire)


func _build_galaxy_map() -> void:
	var p := _do_panel(ui, Vector2.ZERO, Vector2(800, 500))
	_anchor(p, 0.5, 0.5, 0.5, 0.5, -400.0, -250.0, 400.0, 250.0)
	p.visible = false
	gal_panel = p
	var t := _col_lbl(Vector2(14, 8), p, 18, Color(1.0, 0.78, 0.3))
	t.text = "GALAKSI HARITASI   (M / Esc: kapat)"
	var rows := [1, 2, 3, 4]
	for r in rows.size():
		var f: int = rows[r]
		var y := 40 + r * 112
		if f <= 3:
			var key: String = ["", "mmo", "eic", "vru"][f]
			var lg := TextureRect.new()
			lg.texture = _tex(UI_TEX % ("logo_" + key))
			lg.position = Vector2(14, y + 20)
			lg.size = Vector2(80, 44)
			lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(lg)
			var fl := _col_lbl(Vector2(14, y + 66), p, 14, Color(0.8, 0.92, 1.0))
			fl.text = DOData.FACTIONS[f].name
		else:
			var fl2 := _col_lbl(Vector2(14, y + 30), p, 14, Color(1.0, 0.6, 0.5))
			fl2.text = "Savas\nbolgeleri"
		for i in 4:
			var nm := "%d-%d" % [f, i + 1]
			var tp := Panel.new()
			tp.position = Vector2(110 + i * 170, y)
			tp.size = Vector2(160, 100)
			tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tp.add_theme_stylebox_override("panel", _do_style(Color(0, 0, 0, 0.9), Color(0.25, 0.42, 0.55)))
			p.add_child(tp)
			var im := TextureRect.new()
			im.texture = _tex(MAP_TEX % nm)
			im.position = Vector2(2, 2)
			im.size = Vector2(156, 96)
			im.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			im.stretch_mode = TextureRect.STRETCH_SCALE
			im.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tp.add_child(im)
			var nl := _col_lbl(Vector2(6, 74), tp, 14, Color(1.0, 0.85, 0.4))
			nl.text = nm + (" (PvP)" if nm == "4-4" else "")
			gal_marks[nm] = tp


func toggle_galaxy() -> void:
	if not running:
		return
	if gal_panel.visible:
		gal_panel.visible = false
		return
	base_menu.visible = false
	for k in gal_marks:
		var pn: Panel = gal_marks[k]
		if k == cur:
			pn.add_theme_stylebox_override("panel", _do_style(Color(0, 0, 0, 0.9), Color(0.4, 1.0, 0.5)))
		else:
			pn.add_theme_stylebox_override("panel", _do_style(Color(0, 0, 0, 0.9), Color(0.25, 0.42, 0.55)))
	gal_panel.visible = true


func toggle_help() -> void:
	lbl_help.visible = not lbl_help.visible
	if not SV.is_empty():
		SV.settings.help = lbl_help.visible
		save_game()


# ---------- NOVAGATE: KAYIT OL / GIRIS YAP + SIRKET SECIMI ----------
# Hesaplar bu cihazda yerel olarak tutulur (user://novagate_accounts.json); sifre tuzlu SHA-256 ile saklanir.
# Sirket YALNIZCA kayit sirasinda bir kez secilir ve hesaba kilitlenir.
const ACCOUNTS_PATH := "user://novagate_accounts.json"
const FACTION_SM_LOGO := {1: "mmo", 2: "eic", 3: "vru"}   # assets/ui/logo_sm_<anahtar>.png (isim yanindaki kucuk logo)

var save_path: String = ""          # giris yapan hesabin kayit dosyasi
var account_name: String = ""       # giris yapan hesabin gorunen adi
var account_faction: int = 0        # hesabin kilitli sirketi (1=MMO, 2=EIC, 3=VRU)
var auth_box: VBoxContainer
var company_box: VBoxContainer
var le_user: LineEdit
var le_pass: LineEdit
var le_pass2: LineEdit
var lbl_auth_mode: Label
var lbl_auth_msg: Label
var btn_auth_action: Button
var btn_auth_switch: Button
var auth_register: bool = false
var pending_name: String = ""
var pending_pass: String = ""
var plate_layer: CanvasLayer
const RankSys = preload("res://rank_system.gd")
var plate_rank: TextureRect   # nick solundaki rutbe rozeti
var plate_box: HBoxContainer
var plate_name: Label
var plate_logo: TextureRect


# ---------- GIRIS / SIRKET SECIMI ARAYUZU (gorunum katmani; hesap mantigi asagidaki _auth_* / _on_company_chosen'da) ----------
const LG_GOLD := Color(1.0, 0.78, 0.30)
const LG_CYAN := Color(0.45, 0.80, 1.0)
const LG_TEXT := Color(0.88, 0.94, 1.0)
const LG_MUTED := Color(0.52, 0.65, 0.80)
const LG_CARD := Color(0.030, 0.050, 0.090, 0.94)
const LG_EDGE := Color(0.18, 0.40, 0.72, 0.55)
const LG_ERR := Color(1.0, 0.48, 0.42)
# Sirket tanitimi yalnizca atmosfer metnidir (oyun avantaji iddiasi icermez). Renkler kart vurgusu icin.
const FACTION_INFO := {
	1: {"full": "MARS MINING OPERATIONS", "col": Color(1.0, 0.32, 0.26), "desc": "Kızıl gezegenin madenci ve savaşçı birlikleri. Sert, dirençli, geri adım atmaz."},
	2: {"full": "EARTH INDUSTRIES CORPORATION", "col": Color(0.30, 0.62, 1.0), "desc": "Dünya'nın sanayi devi. Disiplinli filolar ve gelişmiş teknoloji."},
	3: {"full": "VENUS RESOURCES UNLIMITED", "col": Color(0.42, 0.92, 0.48), "desc": "Venüs'ün sınırsız kaynak ağı. Hızlı, esnek ve fırsatçı pilotlar."},
}

var lbl_auth_sub: Label
var blk_pass2: Control
var company_sel: int = 0
var company_cards: Dictionary = {}
var btn_company_confirm: Button


func _lg_font(spacing: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = SCI_FONT
	fv.spacing_glyph = spacing
	return fv


func _lg_box(bg: Color, border: Color, bw: int = 1, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	return sb


func _lg_glow(sb: StyleBoxFlat, col: Color, size: int) -> StyleBoxFlat:
	sb.shadow_color = col
	sb.shadow_size = size
	return sb


func _lg_pad(sb: StyleBoxFlat, px: int, py: int) -> StyleBoxFlat:
	sb.content_margin_left = px
	sb.content_margin_right = px
	sb.content_margin_top = py
	sb.content_margin_bottom = py
	return sb


func _lg_label(text: String, fs: int, col: Color, spacing: int = 0, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	if spacing != 0:
		l.add_theme_font_override("font", _lg_font(spacing))
	else:
		l.add_theme_font_override("font", SCI_FONT)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _lg_field(le: LineEdit, hint: String) -> void:
	le.placeholder_text = hint
	le.custom_minimum_size = Vector2(0, 46)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_override("font", SCI_FONT)
	le.add_theme_font_size_override("font_size", 15)
	le.add_theme_color_override("font_color", LG_TEXT)
	le.add_theme_color_override("font_placeholder_color", Color(0.40, 0.52, 0.66, 0.8))
	le.add_theme_color_override("caret_color", LG_GOLD)
	le.add_theme_color_override("selection_color", Color(0.25, 0.50, 0.90, 0.45))
	var bg := Color(0.015, 0.030, 0.060, 0.95)
	var n := _lg_pad(_lg_box(bg, Color(0.16, 0.30, 0.50, 0.7), 1, 4), 14, 8)
	var f := _lg_pad(_lg_box(bg, Color(LG_GOLD.r, LG_GOLD.g, LG_GOLD.b, 0.9), 1, 4), 14, 8)
	_lg_glow(f, Color(LG_GOLD.r, LG_GOLD.g, LG_GOLD.b, 0.18), 8)
	le.add_theme_stylebox_override("normal", n)
	le.add_theme_stylebox_override("focus", f)
	le.add_theme_stylebox_override("read_only", n)


# side: 0 = yok, 1 = "GOSTER" dugmesi (sifre), 2 = ayni genislik icin bos yer tutucu
func _lg_field_block(parent: Control, caption: String, le: LineEdit, side: int) -> Control:
	var blk := VBoxContainer.new()
	blk.add_theme_constant_override("separation", 6)
	blk.add_child(_lg_label(caption, 11, LG_MUTED, 2, HORIZONTAL_ALIGNMENT_LEFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(le)
	if side == 1:
		var eye := Button.new()
		eye.text = "GÖSTER"
		eye.focus_mode = Control.FOCUS_NONE
		eye.custom_minimum_size = Vector2(92, 46)
		_lg_btn_ghost(eye, 11)
		eye.pressed.connect(_lg_toggle_reveal.bind(eye))
		row.add_child(eye)
	elif side == 2:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(92, 46)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
	blk.add_child(row)
	parent.add_child(blk)
	return blk


func _lg_toggle_reveal(btn: Button) -> void:
	var hide_it: bool = not le_pass.secret
	le_pass.secret = hide_it
	le_pass2.secret = hide_it
	btn.text = "GÖSTER" if hide_it else "GİZLE"


func _lg_btn_primary(b: Button, fs: int, accent: Color = LG_GOLD) -> void:
	b.add_theme_font_override("font", _lg_font(3))
	b.add_theme_font_size_override("font_size", fs)
	var dark := Color(0.05, 0.07, 0.12)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, dark)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.52, 0.62))
	var glow := Color(accent.r, accent.g, accent.b, 0.30)
	var n := _lg_pad(_lg_glow(_lg_box(accent, accent.lightened(0.25), 1, 4), glow, 12), 16, 10)
	var h := _lg_pad(_lg_glow(_lg_box(accent.lightened(0.18), Color(1, 1, 1, 0.8), 1, 4), Color(accent.r, accent.g, accent.b, 0.5), 18), 16, 10)
	var p := _lg_pad(_lg_box(accent.darkened(0.18), accent, 1, 4), 16, 10)
	var d := _lg_pad(_lg_box(Color(0.10, 0.14, 0.22, 0.9), Color(0.20, 0.28, 0.40, 0.6), 1, 4), 16, 10)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _lg_btn_ghost(b: Button, fs: int, col: Color = LG_MUTED) -> void:
	b.add_theme_font_override("font", _lg_font(2))
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", LG_TEXT)
	b.add_theme_color_override("font_pressed_color", LG_GOLD)
	var n := _lg_pad(_lg_box(Color(0.05, 0.09, 0.15, 0.6), Color(0.18, 0.34, 0.56, 0.7), 1, 4), 12, 8)
	var h := _lg_pad(_lg_box(Color(0.10, 0.20, 0.35, 0.55), Color(LG_CYAN.r, LG_CYAN.g, LG_CYAN.b, 0.9), 1, 4), 12, 8)
	var p := _lg_pad(_lg_box(Color(0.12, 0.22, 0.32, 0.9), LG_GOLD, 1, 4), 12, 8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _lg_btn_link(b: Button, fs: int) -> void:
	b.flat = true
	b.add_theme_font_override("font", SCI_FONT)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
	b.add_theme_color_override("font_hover_color", LG_GOLD)
	b.add_theme_color_override("font_pressed_color", LG_GOLD)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# Ust kenarda ince vurgu seridi olan cam kart; icerik VBox'ini dondurur.
func _lg_card(parent: Control, width: float, accent: Color) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	pc.add_theme_stylebox_override("panel", _lg_glow(_lg_box(LG_CARD, LG_EDGE, 1, 6), Color(0.20, 0.50, 1.0, 0.16), 28))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	pc.add_child(outer)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(0, 3)
	outer.add_child(bar)
	var mc := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 32)
	mc.add_theme_constant_override("margin_top", 22)
	mc.add_theme_constant_override("margin_bottom", 20)
	outer.add_child(mc)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	mc.add_child(inner)
	parent.add_child(pc)
	return inner


const MENU_BG := "res://novagate_bg.jpg"   # giris / sirket secimi arka plani
const MENU_TOP_PAD := 130.0                # kartlari arka plandaki logonun altina iten bosluk (px)


func _build_main_menu(layer: Control) -> void:
	menu = ColorRect.new()
	(menu as ColorRect).color = Color(0.0, 0.01, 0.03, 0.80)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)

	# Giris / sirket secimi arka plani: NovaGate gorseli (ekrani kaplar, orani korunur).
	var bg_tex: Texture2D = _tex(MENU_BG)
	if bg_tex != null:
		var bgr := TextureRect.new()
		bgr.texture = bg_tex
		bgr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bgr.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.add_child(bgr)
		(menu as ColorRect).color = Color(0.0, 0.01, 0.03, 0.18)   # yazilar okunsun diye hafif karartma

	# kenarlari karartan vinyet (merkez acik, kenarlar koyu)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.08, 0.18, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.78)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var vg := TextureRect.new()
	vg.texture = gt
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(vg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	if bg_tex != null:
		center.offset_top = MENU_TOP_PAD   # kart, gorseldeki NovaGate logosunun altinda kalsin
	menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

	# --- Marka basligi ---
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.visible = bg_tex == null   # arka plan gorselinde logo zaten var; yazi basligi tekrar edilmez
	col.add_child(head)
	var t := _lg_label("NOVAGATE", 46, LG_GOLD, 10)
	t.add_theme_color_override("font_outline_color", Color(0.40, 0.20, 0.0, 0.85))
	t.add_theme_constant_override("outline_size", 3)
	t.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	t.add_theme_constant_override("shadow_offset_y", 4)
	head.add_child(t)
	var subrow := HBoxContainer.new()
	subrow.alignment = BoxContainer.ALIGNMENT_CENTER
	subrow.add_theme_constant_override("separation", 14)
	head.add_child(subrow)
	for k in 3:
		if k == 1:
			subrow.add_child(_lg_label("THE ULTIMATE SPACE COMBAT EXPERIENCE", 12, Color(LG_CYAN.r, LG_CYAN.g, LG_CYAN.b, 0.85), 3))
		else:
			var ln := ColorRect.new()
			ln.color = Color(LG_CYAN.r, LG_CYAN.g, LG_CYAN.b, 0.45)
			ln.custom_minimum_size = Vector2(70, 1)
			ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			subrow.add_child(ln)

	# --- Giris / Kayit karti ---
	auth_box = VBoxContainer.new()
	col.add_child(auth_box)
	var inner := _lg_card(auth_box, 440.0, LG_GOLD)
	var hd := VBoxContainer.new()
	hd.add_theme_constant_override("separation", 6)
	inner.add_child(hd)
	lbl_auth_mode = _lg_label("GİRİŞ YAP", 22, LG_TEXT, 4)
	hd.add_child(lbl_auth_mode)
	lbl_auth_sub = _lg_label("Hesabına giriş yap ve galaksiye dön.", 12, LG_MUTED)
	hd.add_child(lbl_auth_sub)
	le_user = LineEdit.new()
	_lg_field(le_user, "Kullanıcı adınız")
	le_user.max_length = 16
	_lg_field_block(inner, "KULLANICI ADI", le_user, 2)
	le_pass = LineEdit.new()
	_lg_field(le_pass, "Şifreniz")
	le_pass.secret = true
	_lg_field_block(inner, "ŞİFRE", le_pass, 1)
	le_pass2 = LineEdit.new()
	_lg_field(le_pass2, "Şifrenizi tekrar girin")
	le_pass2.secret = true
	blk_pass2 = _lg_field_block(inner, "ŞİFRE (TEKRAR)", le_pass2, 2)
	blk_pass2.visible = false
	lbl_auth_msg = _lg_label("", 12, LG_ERR)
	lbl_auth_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_auth_msg.custom_minimum_size = Vector2(0, 18)
	inner.add_child(lbl_auth_msg)
	btn_auth_action = Button.new()
	btn_auth_action.text = "GİRİŞ YAP"
	btn_auth_action.custom_minimum_size = Vector2(0, 54)
	_lg_btn_primary(btn_auth_action, 16)
	btn_auth_action.pressed.connect(_auth_submit)
	inner.add_child(btn_auth_action)
	btn_auth_switch = Button.new()
	btn_auth_switch.text = "Hesabın yok mu?  KAYIT OL"
	_lg_btn_link(btn_auth_switch, 12)
	btn_auth_switch.pressed.connect(_auth_toggle_mode)
	inner.add_child(btn_auth_switch)
	le_user.text_submitted.connect(func(_t: String) -> void: le_pass.grab_focus())
	le_pass.text_submitted.connect(func(_t: String) -> void:
		if auth_register:
			le_pass2.grab_focus()
		else:
			_auth_submit())
	le_pass2.text_submitted.connect(func(_t: String) -> void: _auth_submit())

	# --- Sirket secimi (yalnizca kayit sirasinda, bir kez) ---
	company_box = VBoxContainer.new()
	company_box.add_theme_constant_override("separation", 14)
	company_box.visible = false
	col.add_child(company_box)
	company_box.add_child(_lg_label("ŞİRKETİNİ SEÇ", 24, LG_TEXT, 5))
	var warn := PanelContainer.new()
	warn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	warn.add_theme_stylebox_override("panel", _lg_pad(_lg_box(Color(LG_GOLD.r, LG_GOLD.g, LG_GOLD.b, 0.08), Color(LG_GOLD.r, LG_GOLD.g, LG_GOLD.b, 0.5), 1, 4), 16, 8))
	warn.add_child(_lg_label("Bu seçim yalnızca bir kez yapılır ve sonradan değiştirilemez.", 12, LG_GOLD))
	company_box.add_child(warn)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 20)
	company_box.add_child(crow)
	company_cards.clear()
	company_sel = 0
	for f in [1, 2, 3]:
		crow.add_child(_lg_company_card(f))
	var cbar := HBoxContainer.new()
	cbar.alignment = BoxContainer.ALIGNMENT_CENTER
	cbar.add_theme_constant_override("separation", 14)
	company_box.add_child(cbar)
	var back := Button.new()
	back.text = "GERİ"
	back.custom_minimum_size = Vector2(140, 50)
	_lg_btn_ghost(back, 13)
	back.pressed.connect(_company_back)
	cbar.add_child(back)
	btn_company_confirm = Button.new()
	btn_company_confirm.text = "BİR ŞİRKET SEÇ"
	btn_company_confirm.custom_minimum_size = Vector2(340, 50)
	btn_company_confirm.disabled = true
	_lg_btn_primary(btn_company_confirm, 14)
	btn_company_confirm.pressed.connect(_company_confirm)
	cbar.add_child(btn_company_confirm)
	_lg_card_refresh()

	col.add_child(_lg_label("© 2026 NOVAGATE  ·  Tüm hakları saklıdır", 10, Color(0.40, 0.50, 0.62, 0.6), 2))

	# giris animasyonu: kart yumusakca belirir, baslik hafifce nefes alir
	auth_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(auth_box, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var pulse := create_tween().set_loops()
	pulse.tween_property(t, "modulate:a", 0.82, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(t, "modulate:a", 1.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _lg_company_card(f: int) -> PanelContainer:
	var info: Dictionary = FACTION_INFO[f]
	var acc: Color = info["col"]
	var keys := ["", "mmo", "eic", "vru"]
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(280, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.mouse_entered.connect(_lg_card_hover.bind(f, true))
	pc.mouse_exited.connect(_lg_card_hover.bind(f, false))
	pc.gui_input.connect(_lg_card_input.bind(f))
	var mc := MarginContainer.new()
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 22)
	mc.add_theme_constant_override("margin_top", 18)
	mc.add_theme_constant_override("margin_bottom", 16)
	pc.add_child(mc)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 8)
	mc.add_child(vb)
	var logo := TextureRect.new()
	logo.texture = _tex(UI_TEX % ("logo_" + str(keys[f])))
	logo.custom_minimum_size = Vector2(0, 96)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(logo)
	vb.add_child(_lg_label(str(DOData.FACTIONS[f].name), 30, acc, 6))
	var full := _lg_label(str(info["full"]), 10, LG_MUTED, 1)
	full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(full)
	var ln := ColorRect.new()
	ln.color = Color(acc.r, acc.g, acc.b, 0.45)
	ln.custom_minimum_size = Vector2(0, 1)
	ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ln)
	var desc := _lg_label(str(info["desc"]), 11, Color(LG_TEXT.r, LG_TEXT.g, LG_TEXT.b, 0.82))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.custom_minimum_size = Vector2(0, 60)
	vb.add_child(desc)
	vb.add_child(_lg_label("ÜS HARİTASI  ·  %s" % str(DOData.FACTIONS[f].home), 11, acc, 2))
	var pick := Button.new()
	pick.text = "SEÇ"
	pick.custom_minimum_size = Vector2(0, 40)
	_lg_btn_ghost(pick, 13, acc)
	pick.pressed.connect(_company_select.bind(f))
	vb.add_child(pick)
	company_cards[f] = pc
	return pc


func _lg_card_style(f: int, state: int) -> StyleBoxFlat:
	var acc: Color = FACTION_INFO[f]["col"]
	var sb: StyleBoxFlat
	if state == 2:
		sb = _lg_box(Color(acc.r * 0.10 + 0.03, acc.g * 0.10 + 0.04, acc.b * 0.10 + 0.07, 0.97), acc, 2, 8)
		_lg_glow(sb, Color(acc.r, acc.g, acc.b, 0.40), 26)
	elif state == 1:
		sb = _lg_box(Color(0.045, 0.070, 0.120, 0.97), Color(acc.r, acc.g, acc.b, 0.70), 1, 8)
		_lg_glow(sb, Color(acc.r, acc.g, acc.b, 0.18), 18)
	else:
		sb = _lg_box(LG_CARD, Color(0.18, 0.32, 0.55, 0.5), 1, 8)
	return sb


func _lg_card_refresh() -> void:
	for f in company_cards.keys():
		var pc: PanelContainer = company_cards[f]
		var st := 0
		if int(f) == company_sel:
			st = 2
		elif bool(pc.get_meta("hover", false)):
			st = 1
		pc.add_theme_stylebox_override("panel", _lg_card_style(int(f), st))


func _lg_card_hover(f: int, on: bool) -> void:
	if company_cards.has(f):
		(company_cards[f] as PanelContainer).set_meta("hover", on)
		_lg_card_refresh()


func _lg_card_input(ev: InputEvent, f: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_company_select(f)


# Karti secer; kalici secim ancak "DEVAM ET" ile onaylaninca yapilir (geri alinamaz oldugu icin).
func _company_select(f: int) -> void:
	company_sel = f
	_lg_card_refresh()
	btn_company_confirm.disabled = false
	btn_company_confirm.text = "%s İLE DEVAM ET" % str(DOData.FACTIONS[f].name)
	_lg_btn_primary(btn_company_confirm, 14, FACTION_INFO[f]["col"])


func _company_confirm() -> void:
	if company_sel >= 1 and company_sel <= 3:
		_on_company_chosen(company_sel)


func _auth_toggle_mode() -> void:
	_auth_set_mode(not auth_register)


func _auth_set_mode(reg: bool) -> void:
	auth_register = reg
	lbl_auth_mode.text = "KAYIT OL" if reg else "GİRİŞ YAP"
	lbl_auth_sub.text = "Yeni pilot hesabı oluştur. Sonraki adımda şirketini seçeceksin." if reg else "Hesabına giriş yap ve galaksiye dön."
	btn_auth_action.text = "DEVAM ET" if reg else "GİRİŞ YAP"
	btn_auth_switch.text = "Zaten hesabın var mı?  GİRİŞ YAP" if reg else "Hesabın yok mu?  KAYIT OL"
	blk_pass2.visible = reg
	le_pass2.text = ""
	lbl_auth_msg.text = ""


func _acc_load() -> Dictionary:
	var out := {"users": {}}
	if not FileAccess.file_exists(ACCOUNTS_PATH):
		return out
	var f := FileAccess.open(ACCOUNTS_PATH, FileAccess.READ)
	if f == null:
		return out
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY and typeof((d as Dictionary).get("users")) == TYPE_DICTIONARY:
		return d
	return out


func _acc_store(d: Dictionary) -> bool:
	var f := FileAccess.open(ACCOUNTS_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	return true


func _acc_hash(salt: String, pw: String) -> String:
	var h := salt + ":" + pw
	for i in 1500:
		h = (h + salt).sha256_text()
	return h


func _acc_key(nm: String) -> String:
	return nm.strip_edges().to_lower()


func _name_valid(nm: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_.\\-ÇĞİÖŞÜçğıöşü]{3,16}$")
	return re.search(nm) != null


func _auth_submit() -> void:
	var nm := le_user.text.strip_edges()
	var pw := le_pass.text
	lbl_auth_msg.text = ""
	if nm == "" or pw == "":
		lbl_auth_msg.text = "Kullanıcı adı ve şifre gerekli."
		return
	if auth_register:
		# Kayit: yerel dogrulama + sunucuya hesap olusturma
		if not _name_valid(nm):
			lbl_auth_msg.text = "Kullanıcı adı 3-16 karakter olmalı (harf, rakam, _ - .)."
			return
		if pw.length() < 4:
			lbl_auth_msg.text = "Şifre en az 4 karakter olmalı."
			return
		if pw != le_pass2.text:
			lbl_auth_msg.text = "Şifreler aynı değil."
			return
		pending_name = nm
		pending_pass = pw
		auth_box.visible = false
		company_box.visible = true
		return
	# Giris: TLS ile auth_service'ye gonder
	lbl_auth_msg.text = "Sunucuya dogrulaniyor..."
	Net.login_via_tls(nm, pw)


# ------------------------------------------------------------------ TLS AUTH CALLBACK
func _on_auth_result(ok: bool, msg: String, acct_id: int = 0, callsign: String = "", faction: int = 1, token: String = "") -> void:
	"""
	Net.login_via_tls'den gelen sonuc.
	Basariliysa ENet sunucusuna token ile baglanir.
	"""
	if not ok:
		lbl_auth_msg.text = msg
		menu.modulate = Color(1, 1, 1, 1)
		menu.show()
		auth_box.visible = true
		company_box.visible = false
		return
	account_name = callsign
	account_faction = faction
	Net.session_token = token
	Net.account_id = acct_id
	# ENet sunucusuna token ile baglan
	lbl_auth_msg.text = "Oyun sunucusuna baglaniliyor..."
	# Giris akisinda ENet baglantisi henuz yok (kayit akisi onceden baglaniyor): once baglan.
	if not Net.online:
		var conn_ok: bool = await Net.connect_only(Net.SERVER_ADDR)
		if not conn_ok:
			lbl_auth_msg.text = "Sunucuya baglanilamadi: " + Net.last_error
			menu.modulate = Color(1, 1, 1, 1)
			menu.show()
			auth_box.visible = true
			company_box.visible = false
			return
	Net.attach_token(token)


# ------------------------------------------------------------------ ENET ATTACH CALLBACK
func _on_attach_result(ok: bool, msg: String, acct_id: int = 0, callsign: String = "", faction: int = 1, player_state_json: String = "") -> void:
	"""
	Net.c_attach_token'dan gelen sonuc.
	Basariliysa SV'i sunucudan gelen verilerle doldurur ve oyunu baslatir.
	"""
	print("[ISTEMCI] _on_attach_result cagrildi: ok=%s, msg=%s, acct_id=%d" % [ok, msg, acct_id])
	if not ok:
		lbl_auth_msg.text = msg
		menu.modulate = Color(1, 1, 1, 1)
		menu.show()
		auth_box.visible = true
		company_box.visible = false
		return
	account_name = callsign
	account_faction = faction
	Net.account_id = acct_id

	# SV'i sunucudan gelen verilerle doldur (istemci tarafindaki SV sadece gorunum kopyasi)
	var ps: Dictionary = JSON.parse_string(player_state_json)
	SV = {
		"faction": int(ps.get("faction", faction)),
		"is_admin": int(ps.get("is_admin", 0)),
		"cr": int(ps.get("cr", 0)),
		"uri": int(ps.get("uri", 0)),
		"xp": float(ps.get("xp", 0.0)),
		"hon": float(ps.get("hon", 0.0)),
		"seprom": int(ps.get("sep", 0)),
		"pvp_kills": int(ps.get("pvp_kills", 0)),
		"rank_pen": float(ps.get("rank_pen", 0.0)),
		"ship": str(ps.get("ship", "phoenix")),
		"map": str(ps.get("map", "1-1")),
		"px": float(ps.get("px", 0.0)),
		"pz": float(ps.get("pz", 0.0)),
		"kills": int(ps.get("kills", 0)),
		"callsign": str(ps.get("callsign", callsign)),
		"sel": str(ps.get("selected_ammo", "x1")),
		"inv": ps.get("inv", {}),
		"ammo": ps.get("ammo", {}),
		"rockets": int(ps.get("rockets", 50)),
		"owned": ps.get("owned", [str(ps.get("ship", "phoenix"))]),
		"forms": ps.get("forms", ["std"]),
		"loads": ps.get("loads", {}),
		"cfgi": int(ps.get("cfg_index", 0)),
		"free": bool(ps.get("free_mode", false)),
		"quests": ps.get("quests", {}),
		"skills": ps.get("skills", {}),
		"skill_points": int(ps.get("skill_points", 0)),
		"maps_visited": ps.get("maps_visited", []),
		"route_to": str(ps.get("route_to", "")),
		"settings": ps.get("settings", {}),
		"drone_equip": ps.get("drone_equip", {}),
		"reg_ts": int(ps.get("reg_ts", Time.get_unix_time_from_system())),
	}
	# JSON alanlarini coz (sunucu bazi alanlari string, bazilarini sozluk dondurebilir)
	if typeof(SV.settings) == TYPE_STRING:
		SV.settings = JSON.parse_string(SV.settings)
	if typeof(SV.drone_equip) == TYPE_STRING:
		SV.drone_equip = JSON.parse_string(SV.drone_equip)
	if typeof(SV.settings) != TYPE_DICTIONARY:
		SV.settings = {}
	if typeof(SV.drone_equip) != TYPE_DICTIONARY:
		SV.drone_equip = {}
	SV.forms = Array(SV.get("forms", ["std"]))
	if SV.forms.is_empty():
		SV.forms = ["std"]
	if typeof(SV.loads) != TYPE_DICTIONARY:
		SV.loads = {}
	if typeof(SV.quests) != TYPE_DICTIONARY:
		SV.quests = {}
	if typeof(SV.skills) != TYPE_DICTIONARY:
		SV.skills = {}
	if typeof(SV.maps_visited) != TYPE_ARRAY:
		SV.maps_visited = []

	print("[ISTEMCI] SV hazirlandi: account_id=%d, callsign=%s, ship=%s" % [acct_id, callsign, ps.get("ship", "phoenix")])
	# Oyunu baslat (zaten ENet baglantisi var, sadece oyun baslat)
	_start_run(false, true)


func _company_back() -> void:
	company_box.visible = false
	auth_box.visible = true
	pending_pass = ""
	company_sel = 0
	if btn_company_confirm != null:
		btn_company_confirm.disabled = true
		btn_company_confirm.text = "BİR ŞİRKET SEÇ"
		_lg_btn_primary(btn_company_confirm, 14)
	_lg_card_refresh()


# Kayit tamamlanir: hesap ancak sirket secildikten sonra olusur ve sirket kilitlenir.
func _on_company_chosen(f: int) -> void:
	# Oncece sunucuya kayit (TLS /register)
	var reg_body: String = JSON.stringify({
		"username": pending_name,
		"password": pending_pass,
		"faction": f,
		"callsign": pending_name
	})
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var url := "https://%s:%d/register" % [Net.AUTH_HOST, Net.AUTH_HTTPS_PORT]
	var req := HTTPRequest.new()
	add_child(req)
	if Net.tls_opts != null:
		req.set_tls_options(Net.tls_opts)
	var reg_pass: String = pending_pass   # kayit sonrasi girisde kullanilacak (pending_pass asagida siliniyor)
	req.request_completed.connect(func(_result, _code, _headers, _body: PackedByteArray):
		if _result != HTTPRequest.RESULT_SUCCESS or _code != 200:
			lbl_auth_msg.text = "Sunucu kayit hatasi (kod %d/%d)." % [_result, _code]
			_company_back()
			return
		var data: Dictionary = JSON.parse_string(_body.get_string_from_utf8())
		if not data.has("ok") or data["ok"] == false:
			lbl_auth_msg.text = str(data.get("error", "kayit basarisiz"))
			_company_back()
			return
		# Sunucu kayit basarili: yerel dosyaya da kaydet (geri uyumluluk)
		var db := _acc_load()
		var users: Dictionary = db["users"]
		var key := _acc_key(pending_name)
		if users.has(key):
			_company_back()
			lbl_auth_msg.text = "Bu kullanıcı adı zaten alınmış."
			return
		var salt: String = Crypto.new().generate_random_bytes(12).hex_encode()
		var file := "user://novagate_save_%s.json" % key.sha256_text().substr(0, 16)
		users[key] = {"name": pending_name, "salt": salt, "hash": _acc_hash(salt, pending_pass), "faction": f, "file": file}
		db["users"] = users
		if not _acc_store(db):
			_company_back()
			lbl_auth_msg.text = "Hesap kaydedilemedi."
			return
		pending_pass = ""
		account_name = pending_name
		account_faction = f
		save_path = file
		# Kayit sonrasi once ENet baglantisi kur, sonra TLS ile giris yapip token al
		var conn_ok: bool = await Net.connect_only(Net.SERVER_ADDR)
		if not conn_ok:
			lbl_auth_msg.text = "Sunucuya baglanilamadi: " + Net.last_error
			_company_back()
			return
		Net.login_via_tls(pending_name, reg_pass)
	)
	req.request(url, headers, HTTPClient.METHOD_POST, reg_body)


# Gemi altindaki isim plakasi: oyuncu adi + yaninda (sagda) secilen sirketin logosu.
func _build_plate() -> void:
	if plate_layer != null and is_instance_valid(plate_layer):
		plate_layer.queue_free()
	plate_layer = CanvasLayer.new()
	plate_layer.layer = 0
	add_child(plate_layer)
	plate_box = HBoxContainer.new()
	plate_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate_box.add_theme_constant_override("separation", 3)
	plate_box.visible = false
	plate_layer.add_child(plate_box)
	plate_rank = TextureRect.new()
	plate_rank.custom_minimum_size = Vector2(11, 11)
	plate_rank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate_rank.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate_rank.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate_rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate_rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate_box.add_child(plate_rank)
	plate_name = Label.new()
	plate_name.text = str(SV.get("callsign", "Gezgin"))
	plate_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate_name.add_theme_font_override("font", SCI_FONT)
	plate_name.add_theme_font_size_override("font_size", 9)
	plate_name.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0))
	plate_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	plate_name.add_theme_constant_override("outline_size", 3)
	plate_box.add_child(plate_name)
	plate_logo = TextureRect.new()
	plate_logo.custom_minimum_size = Vector2(9, 9)
	plate_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plate_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fk: String = str(FACTION_SM_LOGO.get(int(SV.get("faction", 0)), ""))
	var lt: Texture2D = null
	if fk != "":
		lt = _tex("res://assets/ui/logo_sm_%s.png" % fk)
	plate_logo.texture = lt
	plate_logo.visible = lt != null
	plate_box.add_child(plate_logo)
	_refresh_plate_rank()
	plate_box.reset_size()


# Diger oyunculara ait 2D isim plakasi: [sirket logosu] + isim. (Kendi plakanla ayni mantik; logo_sm yoksa logo_<sirket> kullanilir.)
func make_remote_plate(nm: String, fac: int, col: Color, is_admin: bool = false) -> Control:
	if plate_layer == null or not is_instance_valid(plate_layer):
		return null
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	box.visible = false
	# Isim once (solda)
	var lb := Label.new()
	lb.text = nm
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_override("font", SCI_FONT)
	lb.add_theme_font_size_override("font_size", 10)
	lb.add_theme_color_override("font_color", col)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lb.add_theme_constant_override("outline_size", 3)
	# Rutbe rozeti (admin -> rank_21.png) - isimden ONCE
	if bool(is_admin):
		var ar := TextureRect.new()
		ar.custom_minimum_size = Vector2(11, 11)
		ar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ar.texture = _tex(RankSys.ICON_PATH % RankSys.ADMIN_ICON)
		box.add_child(ar)
	# Isim (ortada)
	box.add_child(lb)
	# Sirket logosu en sagda
	var fk: String = str(FACTION_SM_LOGO.get(fac, ""))
	if fk != "":
		var lt: Texture2D = _tex("res://assets/ui/logo_sm_%s.png" % fk)
		if lt == null:
			lt = _tex("res://assets/ui/logo_%s.png" % fk)
		if lt != null:
			var lg := TextureRect.new()
			lg.custom_minimum_size = Vector2(13, 13)
			lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			lg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			lg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lg.texture = lt
			box.add_child(lg)
	plate_layer.add_child(box)
	box.reset_size()
	return box


func update_remote_plate(box, node: Node3D, show: bool) -> void:
	if box == null or not is_instance_valid(box):
		return
	var ok: bool = show and cam != null and is_instance_valid(node)
	if ok:
		var wp: Vector3 = node.global_position
		if cam.is_position_behind(wp):
			ok = false
		else:
			var sp: Vector2 = cam.unproject_position(wp)
			var sz: Vector2 = (box as Control).get_combined_minimum_size()
			(box as Control).position = Vector2(sp.x - sz.x * 0.5, sp.y + _off_px(wp, node, NAME_K, NAME_MIN_PX) + 6.0)
	(box as Control).visible = ok


# Nick solundaki rutbe rozeti: siralamadaki gercek rutbe (kurulurken ve her kayitta yenilenir).
func _refresh_plate_rank() -> void:
	if plate_rank == null or not is_instance_valid(plate_rank) or SV.is_empty():
		return
	if bool(SV.get("is_admin", 0)):
		plate_rank.texture = _tex(RankSys.ICON_PATH % RankSys.ADMIN_ICON)
	else:
		var rk: Dictionary = RankSys.display(RankSys.summary(self).me)
		plate_rank.texture = _tex(RankSys.ICON_PATH % int(rk.icon))
	plate_rank.visible = plate_rank.texture != null


func _update_plate(show_world: bool) -> void:
	if plate_box == null or not is_instance_valid(plate_box):
		return
	var ok: bool = show_world and P != null and is_instance_valid(P.node) and cam != null
	if ok:
		var wp: Vector3 = P.node.global_position
		if cam.is_position_behind(wp):
			ok = false
		else:
			var sp: Vector2 = cam.unproject_position(wp)
			var sz: Vector2 = plate_box.get_combined_minimum_size()
			plate_box.position = Vector2(sp.x - sz.x * 0.5, sp.y + _off_px(wp, P.node, NAME_K, NAME_MIN_PX))
	plate_box.visible = ok



func _start_transition(callback: Callable) -> void:
	menu.modulate = Color(1, 1, 1, 1)
	var tween = create_tween()
	tween.tween_property(menu, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_on_transition_finished.bind(callback))

func _on_transition_finished(callback: Callable) -> void:
	callback.call()


func _build_base_menu(layer: Control) -> void:
	var p = ControlPanelScript.new()
	p.game = self
	layer.add_child(p)
	p.build()
	p.visible = false
	base_menu = p
	base_menu.visibility_changed.connect(_on_base_menu_visibility_changed)


func refresh_base() -> void:
	base_menu.refresh()


func toggle_base() -> void:
	if not running:
		return
	if base_menu.visible:
		base_menu.visible = false
		for n in hud_nodes:
			if is_instance_valid(n):
				n.visible = true
		_layout_right()
	else:
		gal_panel.visible = false
		base_menu.visible = true
		for n in hud_nodes:
			if is_instance_valid(n):
				n.visible = false

# visibility_changed sinyali argüman göndermez; panelin anlık durumunu base_menu.visible'dan okuyoruz.
# Böylece X / "OYUNA DÖN" / Esc ile panel kapanınca HUD da güvenle geri gelir.
func _on_base_menu_visibility_changed() -> void:
	if not base_menu.visible:
		for n in hud_nodes:
			if is_instance_valid(n):
				n.visible = true
		_layout_right()


func _empty_cfg() -> Dictionary:
	return {"las": [], "gen": [], "drn": [], "form": "std", "drone_equip": {}}


func ensure_campaign_data() -> void:
	if typeof(SV.get("quests")) != TYPE_DICTIONARY:
		SV["quests"] = {}
	else:
		SV["quests"] = SV.get("quests")
	if typeof(SV.get("skills")) != TYPE_DICTIONARY:
		SV["skills"] = {}
	else:
		SV["skills"] = SV.get("skills")
	if typeof(SV.get("settings")) != TYPE_DICTIONARY:
		SV["settings"] = {}
	else:
		SV["settings"] = SV.get("settings")
	if typeof(SV.get("maps_visited")) != TYPE_ARRAY:
		SV["maps_visited"] = []
	else:
		SV["maps_visited"] = SV.get("maps_visited")
	if not SV.has("skill_points"):
		SV.skill_points = 0
	if not SV.has("seprom"):
		SV.seprom = 0
	if not SV.has("logdisks"):
		SV.logdisks = 0
	if not SV.has("rd_resets"):
		SV.rd_resets = 0
	# eski yetenek agacinin kayitlari (laser_focus vb.) silinir; yalniz yeni agactaki yetenekler kalir
	var clean_sk := {}
	for sk in SkillTree.SKILLS:
		var rk := clampi(int((SV.skills as Dictionary).get(str(sk.id), 0)), 0, int(sk.pts))
		if rk > 0:
			clean_sk[str(sk.id)] = rk
	SV.skills = clean_sk
	if not SV.has("rockets"):
		SV.rockets = 0
	if not SV.has("ammo") or not SV.ammo.has("rsb"):
		SV.ammo = SV.get("ammo", {})
		SV.ammo["rsb"] = 0
	if not SV.has("callsign") or str(SV.callsign).strip_edges() == "":
		SV.callsign = "Gezgin"
	if not SV.has("route_to"):
		SV.route_to = ""
	if not SV.has("drone_equip"):
		SV.drone_equip = {}
	if not SV.has("reg_ts"):
		SV.reg_ts = Time.get_unix_time_from_system()   # rutbe: kayit suresi bu andan sayilir
	if not SV.has("pvp_kills"):
		SV.pvp_kills = 0
	if not SV.has("rank_pen"):
		SV.rank_pen = 0.0
	if not SV.has("ship_equip"):
		SV.ship_equip = {}
	SV.skill_points = maxi(0, int(SV.skill_points))
	SV.rockets = maxi(0, int(SV.rockets))
	var settings: Dictionary = SV.settings
	settings["stars"] = bool(settings.get("stars", true))
	settings["zoom"] = clampf(float(settings.get("zoom", 1.0)), 0.4, 2.5)
	settings["graphics"] = int(clampi(int(settings.get("graphics", 2)), 0, 2))
	settings["fullscreen"] = bool(settings.get("fullscreen", false))
	settings["help"] = bool(settings.get("help", true))
	SV.settings = settings
	for quest in QUESTS:
		var quest_id := str(quest.id)
		var state = SV.quests.get(quest_id, {})
		if typeof(state) != TYPE_DICTIONARY:
			state = {}
		state["progress"] = clampi(int(state.get("progress", 0)), 0, int(quest.target))
		state["claimed"] = bool(state.get("claimed", false))
		SV.quests[quest_id] = state
	if not SV.maps_visited.has(str(SV.map)):
		SV.maps_visited.append(str(SV.map))


func quest_list() -> Array:
	return QUESTS


func skill_tree() -> Array:
	return SkillTree.SKILLS


func claim_quest(quest_id: String) -> bool:
	for quest in QUESTS:
		if str(quest.id) != quest_id:
			continue
		var state: Dictionary = SV.quests.get(quest_id, {})
		if bool(state.get("claimed", false)) or int(state.get("progress", 0)) < int(quest.target):
			toast("Görev henüz tamamlanmadı veya ödülü alındı.")
			return false
		state["claimed"] = true
		SV.quests[quest_id] = state
		award_xp(int(quest.xp))
		SV.cr += int(quest.cr)
		SV.uri += int(quest.uri)
		toast("Görev ödülü: +%s XP, +%s kredi, +%s uridium" % [str(quest.xp), str(quest.cr), str(quest.uri)])
		save_game()
		return true
	toast("Görev bulunamadı.")
	return false


# ---------- Pilot Bio (Yetenek Agaci) ----------
func rd_total() -> int:
	return mini(SkillTree.MAX_POINTS, SkillTree.points_for_disks(int(SV.get("logdisks", 0))))


func rd_spent() -> int:
	var n := 0
	for sk in SkillTree.SKILLS:
		n += clampi(skill_rank(str(sk.id)), 0, int(sk.pts))
	return n


func rd_free() -> int:
	return maxi(0, rd_total() - rd_spent())


func skill_req_ok(sk: Dictionary) -> bool:
	for k in (sk.req as Dictionary).keys():
		if skill_rank(str(k)) < int((sk.req as Dictionary)[k]):
			return false
	return true


func buy_logdisk(n: int) -> bool:
	if SV.is_empty() or n <= 0:
		return false
	var have := int(SV.get("logdisks", 0))
	var cap: int = int(SkillTree.CUM[SkillTree.MAX_POINTS]) - have
	n = mini(n, cap)
	if n <= 0:
		toast("Zaten 50 Ar-Ge puanına ulaştın.")
		return false
	if not pay(0, n * SkillTree.LOGDISK_URI):
		return false
	var before := rd_total()
	SV.logdisks = have + n
	toast("+%d Log Disk  (Ar-Ge puanı: %d → %d)" % [n, before, rd_total()])
	save_game()
	return true


func spend_skill_point(skill_id: String) -> bool:
	var sk := SkillTree.find(skill_id)
	if sk.is_empty():
		return false
	var rank := skill_rank(skill_id)
	if rank >= int(sk.pts):
		return false
	if rd_free() <= 0:
		toast("Ar-Ge puanın yok. Log Disk satın al (1 Log Disk = %d Uridium)." % SkillTree.LOGDISK_URI)
		return false
	if not skill_req_ok(sk):
		toast("Önce ön koşul yeteneklerini geliştir.")
		return false
	var cost := SkillTree.level_cost(sk, rank + 1)
	var is_free := bool(SV.get("free", false))
	if not is_free:
		if int(SV.cr) < int(cost.cr) or int(SV.get("seprom", 0)) < int(cost.sep):
			toast("Yetersiz bakiye: %s Kredi + %s Seprom gerekli." % [_n(float(cost.cr)), _n(float(cost.sep))])
			return false
		SV.cr -= int(cost.cr)
		SV.seprom = int(SV.get("seprom", 0)) - int(cost.sep)
	var old_hp := max_hp()
	SV.skills[skill_id] = rank + 1
	if P != null:
		P.hp = minf(P.hp + maxf(0.0, max_hp() - old_hp), max_hp())
	_clamp_vitals()
	toast("%s yeteneği %d / %d" % [str(sk.name), rank + 1, int(sk.pts)])
	save_game()
	return true


func reset_cost_uri() -> int:
	return SkillTree.RESET_BASE_URI * (1 << clampi(int(SV.get("rd_resets", 0)), 0, 20))


func reset_skills() -> bool:
	if rd_spent() <= 0:
		toast("Sıfırlanacak yetenek yok.")
		return false
	if not pay(0, reset_cost_uri()):
		return false
	SV.skills = {}
	SV.rd_resets = int(SV.get("rd_resets", 0)) + 1
	if P != null:
		P.hp = minf(P.hp, max_hp())
	_clamp_vitals()
	toast("Pilot Bio sıfırlandı. Ar-Ge puanların yeniden dağıtılabilir.")
	save_game()
	return true


func save_callsign(_value: String) -> void:
	# Oyuncu adi = hesap kullanici adi; sonradan degistirilemez.
	toast("Oyuncu adı hesabına bağlıdır, değiştirilemez.")


func _ship_loads() -> Array:
	if SV.is_empty() or not SV.has("loads"):
		return []
	var v = SV.loads.get(SV.get("ship", "phoenix"), [])
	return v if typeof(v) == TYPE_ARRAY else []


func active_cfg_idx() -> int:
	var ship_loads := _ship_loads()
	if ship_loads.is_empty():
		return -1
	# SV.cfgi JSON'dan float gelebilir; clamp ile 0/1 aralığına sabitlenir.
	return clampi(int(SV.get("cfgi", 0)), 0, ship_loads.size() - 1)


func cfg() -> Dictionary:
	var ship_loads := _ship_loads()
	if ship_loads.is_empty():
		return _empty_cfg()
	var idx := active_cfg_idx()
	return ship_loads[idx] if idx >= 0 else _empty_cfg()


func cap_of(key: String) -> int:
	var d := ship_def()
	match key:
		"las":
			return int(d.las)
		"gen":
			return int(d.gen)
	return DOData.drone_slots(d)


func item_def(id: String) -> Dictionary:
	if DOData.LASERS.has(id):
		return DOData.LASERS[id]
	if DOData.GENS.has(id):
		return DOData.GENS[id]
	if DOData.DRONES.has(id):
		return DOData.DRONES[id]
	return {}


func item_key(id: String) -> String:
	if DOData.LASERS.has(id):
		return "las"
	if DOData.GENS.has(id):
		return "gen"
	return "drn"


# Droidler ayri envanterde (SV.drone_inv) tutulur; lazer/jenerator SV.inv'de kalir.
func inv_dict(id: String) -> Dictionary:
	if not SV.has("drone_inv"):
		SV["drone_inv"] = {}
	return SV.drone_inv if DOData.DRONES.has(id) else SV.inv


func inv_count(id: String) -> int:
	return int(inv_dict(id).get(id, 0))


func item_icon(id: String) -> Texture2D:
	var path := "res://assets/items/"
	if DOData.LASERS.has(id):
		path += "weapon_" + id
	elif DOData.GENS.has(id):
		path += "generator_" + id
	else:
		path += "drone_" + id
	return _tex(path + ".png")


func ensure_loadout() -> void:
	if not SV.has("inv"):
		SV.inv = {}
	if typeof(SV.get("drone_inv")) != TYPE_DICTIONARY:
		SV["drone_inv"] = {}
	# Eski kayit: droidler SV.inv icindeydi -> ayri droid envanterine tasi
	for did in DOData.DRONE_ORDER:
		if SV.inv.has(did):
			SV.drone_inv[did] = int(SV.drone_inv.get(did, 0)) + int(SV.inv[did])
			SV.inv.erase(did)
	if not SV.has("forms"):
		SV.forms = ["std"]
	if not SV.has("loads"):
		SV.loads = {}
	if not SV.has("cfgi"):
		SV.cfgi = 0
	if not SV.has("free"):
		SV.free = false
	SV.cfgi = clampi(int(SV.cfgi), 0, 1)
	var fresh := false
	var ship_id := str(SV.get("ship", "phoenix"))
	var cur = SV.loads.get(ship_id, null)
	if typeof(cur) == TYPE_DICTIONARY and (cur as Dictionary).has("las"):
		# Eski tek-loadout kaydı: aktif veri Konfi 1'e taşınır, Konfi 2 boş başlar.
		SV.loads[ship_id] = [cur, _empty_cfg()]
	elif typeof(cur) != TYPE_ARRAY or (cur as Array).is_empty():
		SV.loads[ship_id] = [_empty_cfg(), _empty_cfg()]
		fresh = true
	var ship_loads: Array = SV.loads[ship_id]
	while ship_loads.size() < 2:
		# Eksik konfigürasyon kopyalanmaz, boş eklenir → iki loadout bağımsız kalır.
		ship_loads.append(_empty_cfg())
	for i in ship_loads.size():
		var c: Dictionary = ship_loads[i]
		for key in ["las", "gen", "drn"]:
			var cap := cap_of(key)
			var used := {}
			var clean := []
			for id in c[key]:
				var sid := str(id)
				used[sid] = int(used.get(sid, 0)) + 1
				# Diğer konfigürasyonda rezerve edilmişler bu konfigürasyonda sayılmaz;
				# böylece aynı eşya iki loadout'ta birden takılı kalamaz.
				var reserved := 0 if key == "drn" else _reserved_elsewhere(i, key, sid)
				if clean.size() < cap and used[sid] <= inv_count(sid) - reserved and not item_def(sid).is_empty():
					clean.append(sid)
			c[key] = clean
		if not (str(c.form) in SV.forms):
			c.form = "std"
		if fresh:
			# Yalnızca kendi indeksine göre otomatik donat: Konfi 1 önce alır,
			# Konfi 1'e gidenler Konfi 2 için "boşta" sayılmaz.
			auto_equip(c, i)
	# Tek seferlik duzeltme: eski kayitlarda bos kalmis konfigurasyonu ortak esyalarla doldur.
	if not bool(SV.get("cfg_shared_v2", false)):
		SV["cfg_shared_v2"] = true
		for i in ship_loads.size():
			var c2: Dictionary = ship_loads[i]
			if (c2.las as Array).is_empty() and (c2.gen as Array).is_empty():
				auto_equip(c2, i)
	_sync_drn_all()
	_sanitize_drone_equip()


func _sync_drn_all() -> void:
	# Droidler gemiye aittir: iki konfigurasyonda da ayni droid listesi kullanilir
	# (droid ekipmani 'drone_equip' konfigurasyona ozel kalir).
	var loads := _ship_loads()
	if loads.size() < 2:
		return
	var master: Dictionary = loads[0]
	for l in loads:
		if (l.drn as Array).size() > (master.drn as Array).size():
			master = l
	for l in loads:
		if not is_same(l, master):
			l.drn = (master.drn as Array).duplicate()


func _reserved_elsewhere(self_idx: int, key: String, id: String) -> int:
	# DarkOrbit gibi: lazer/jenerator iki konfigurasyonda da AYNI ANDA takili olabilir (konfigler ortak esyayi kullanir).
	# Eskiden diger konfigde takili esya burada "dolu" sayilip Konfi 2 bos kaliyordu.
	if key == "las" or key == "gen":
		return 0
	var n := 0
	for i in _ship_loads().size():
		if i == self_idx:
			continue
		var other: Dictionary = _ship_loads()[i]
		n += (other.get(key, []) as Array).count(id)
	return n


func _free_count(c: Dictionary, key: String, id: String, self_idx := -1) -> int:
	# Boşta sayısı = envanter - bu konfigürasyondakiler - DİĞER konfigürasyonlarda rezerve olanlar.
	# Böylece Konfi 1'e takılan bir lazer Konfi 2'de boşta görünmez (bağımsız loadout, ortak envanter).
	if key == "drn":
		# Droid iki konfigurasyon arasinda ortaktir; ayni droid her ikisinde de kullanilir.
		return maxi(0, inv_count(id) - (c[key] as Array).count(id))
	if self_idx == -1:
		self_idx = active_cfg_idx()
	var n := inv_count(id) - (c[key] as Array).count(id)
	n -= _reserved_elsewhere(self_idx, key, id)
	n -= _drone_used_all(id)
	return maxi(0, n)


func auto_equip(c: Dictionary, self_idx := -1) -> void:
	var lo: Array = DOData.LASER_ORDER.duplicate()
	lo.reverse()
	for id in lo:
		while c.las.size() < cap_of("las") and _free_count(c, "las", id, self_idx) > 0:
			c.las.append(id)
	var go: Array = DOData.GEN_ORDER.duplicate()
	go.reverse()
	for id in go:
		while c.gen.size() < cap_of("gen") and _free_count(c, "gen", id, self_idx) > 0:
			c.gen.append(id)
	var dd: Array = DOData.DRONE_ORDER.duplicate()
	dd.reverse()
	for id in dd:
		while c.drn.size() < cap_of("drn") and _free_count(c, "drn", id, self_idx) > 0:
			c.drn.append(id)
	for l in _ship_loads():
		if not is_same(l, c):
			l.drn = (c.drn as Array).duplicate()


func equip_item(id: String) -> bool:
	var key := item_key(id)
	var c := cfg()
	if c[key].size() >= cap_of(key):
		toast("Slot dolu! Önce bir eşyayı çıkar.")
		return false
	if _free_count(c, key, id) <= 0:
		toast("Bu eşyadan boşta kalmadı. Mağazadan al.")
		return false
	c[key].append(id)
	if key == "drn":
		_sync_drn_all()
	_clamp_vitals()
	save_game()
	if key == "drn":
		_update_drones(0.0)
	return true


func unequip_slot(key: String, idx: int) -> void:
	var c := cfg()
	if idx >= 0 and idx < c[key].size():
		if key == "drn":
			for l in _ship_loads():
				if idx < (l.drn as Array).size():
					_remap_drone_equip_on_remove(l, idx)
					(l.drn as Array).remove_at(idx)
		else:
			c[key].remove_at(idx)
		_clamp_vitals()
		save_game()
		if key == "drn":
			_update_drones(0.0)


# ---- Droid ekipmani --------------------------------------------------------------
# Her konfigurasyonun kendi "drone_equip" sozlugu vardir. Anahtar = droid ORNEGI ("tur_indeks",
# orn. "iris_1"), boylece iki ayni droid birbirinden bagimsiz slotlara sahip olur.
# Droidlere lazer ve kalkan jeneratoru takilir; hiz jeneratoru takilmaz (DarkOrbit gibi).
func drone_accepts(id: String) -> bool:
	if DOData.LASERS.has(id):
		return true
	if DOData.GENS.has(id):
		return str(DOData.GENS[id].type) == "sh"
	return false


func _cfg_drone_equip(c: Dictionary) -> Dictionary:
	if not c.has("drone_equip") or typeof(c["drone_equip"]) != TYPE_DICTIONARY:
		c["drone_equip"] = {}
	return c["drone_equip"]


func drone_uid_index(c: Dictionary, uid: String) -> int:
	var p := uid.rfind("_")
	if p <= 0:
		return -1
	var idx: int = uid.substr(p + 1).to_int()
	if idx < 0 or idx >= (c.drn as Array).size() or str(c.drn[idx]) != uid.substr(0, p):
		return -1
	return idx


func drone_items(c: Dictionary) -> Array:
	var out: Array = []
	var de := _cfg_drone_equip(c)
	for i in (c.drn as Array).size():
		var did := str(c.drn[i])
		var uid := "%s_%d" % [did, i]
		if not de.has(uid) or typeof(de[uid]) != TYPE_DICTIONARY:
			continue
		for s in int(DOData.DRONES[did].slots):
			var k := "slot_%d" % s
			if (de[uid] as Dictionary).has(k):
				out.append(str((de[uid] as Dictionary)[k]))
	return out


func _drone_used_all(id: String) -> int:
	var n := 0
	for c in _ship_loads():
		n += drone_items(c).count(id)
	return n


func drone_laser_dmg() -> float:
	var t := 0.0
	for id in drone_items(cfg()):
		if DOData.LASERS.has(id):
			t += float(DOData.LASERS[id].dmg)
	return t


func equip_drone_item(uid: String, slot_index: int, item_id: String) -> bool:
	var c := cfg()
	var idx := drone_uid_index(c, uid)
	if idx < 0:
		toast("Bu droid gemide değil.")
		return false
	var dd: Dictionary = DOData.DRONES[str(c.drn[idx])]
	if slot_index < 0 or slot_index >= int(dd.slots):
		return false
	if not drone_accepts(item_id):
		toast("Droidlere yalnızca lazer ve kalkan jeneratörü takılabilir.")
		return false
	var de := _cfg_drone_equip(c)
	if not de.has(uid):
		de[uid] = {}
	var slots: Dictionary = de[uid]
	var slot_key := "slot_%d" % slot_index
	if str(slots.get(slot_key, "")) == item_id:
		return true
	if _free_count(c, item_key(item_id), item_id) <= 0:
		toast("Bu eşyadan boşta kalmadı. Mağazadan al ya da gemiden çıkar.")
		return false
	slots[slot_key] = item_id
	_clamp_vitals()
	save_game()
	return true


func unequip_drone_item(drone_index: int, slot_index: int) -> void:
	var c := cfg()
	if drone_index < 0 or drone_index >= c.drn.size():
		return
	_on_drone_slot_unequip("%s_%d" % [str(c.drn[drone_index]), drone_index], slot_index)


func _on_equip_drone_from_inventory(id: String) -> void:
	var c := cfg()
	var de := _cfg_drone_equip(c)
	for i in c.drn.size():
		var did := str(c.drn[i])
		var uid := "%s_%d" % [did, i]
		for s in int(DOData.DRONES[did].slots):
			if not (de.get(uid, {}) as Dictionary).has("slot_%d" % s):
				if equip_drone_item(uid, s, id):
					toast("%s, %s droidine takıldı." % [str(item_def(id).name), str(DOData.DRONES[did].name)])
				return
	toast("Tüm droid slotları dolu!")


func _on_drone_slot_unequip(uid: String, slot_index: int) -> void:
	var de := _cfg_drone_equip(cfg())
	if not de.has(uid) or typeof(de[uid]) != TYPE_DICTIONARY:
		return
	(de[uid] as Dictionary).erase("slot_%d" % slot_index)
	_clamp_vitals()
	save_game()


func _on_unequip_all_drones() -> void:
	_cfg_drone_equip(cfg()).clear()
	_clamp_vitals()
	save_game()


func _remap_drone_equip_on_remove(c: Dictionary, idx: int) -> void:
	# Bir droid cikarilinca sonrakilerin indeksi kayar; ekipmanlari da onlarla birlikte kaydir.
	var de := _cfg_drone_equip(c)
	var nd := {}
	for i in (c.drn as Array).size():
		if i == idx:
			continue
		var old_uid := "%s_%d" % [str(c.drn[i]), i]
		if de.has(old_uid):
			nd["%s_%d" % [str(c.drn[i]), (i if i < idx else i - 1)]] = de[old_uid]
	c["drone_equip"] = nd


func _sanitize_drone_equip() -> void:
	# Gecersiz droid/slot/esya ve envanterde olmayan adetleri temizler (gemi ekipmani oncelikli).
	var loads := _ship_loads()
	var ship_used := {}
	for c in loads:
		for key in ["las", "gen"]:
			for id in c[key]:
				ship_used[str(id)] = int(ship_used.get(str(id), 0)) + 1
	var left := {}
	for c in loads:
		var de := _cfg_drone_equip(c)
		var clean := {}
		for i in (c.drn as Array).size():
			var did := str(c.drn[i])
			var uid := "%s_%d" % [did, i]
			if not de.has(uid) or typeof(de[uid]) != TYPE_DICTIONARY:
				continue
			var slots := {}
			for s in int(DOData.DRONES[did].slots):
				var k := "slot_%d" % s
				if not (de[uid] as Dictionary).has(k):
					continue
				var iid := str((de[uid] as Dictionary)[k])
				if not drone_accepts(iid):
					continue
				if not left.has(iid):
					left[iid] = int(SV.inv.get(iid, 0)) - int(ship_used.get(iid, 0))
				if int(left[iid]) <= 0:
					continue
				left[iid] = int(left[iid]) - 1
				slots[k] = iid
			if not slots.is_empty():
				clean[uid] = slots
		c["drone_equip"] = clean


var last_max_sh := -1.0
var sh_ratio := 1.0


func _sync_shield() -> void:
	# Azami kalkan degisince (jenerator tak/cikar, droid, formasyon, yetenek) mevcut kalkan ORANI korunur;
	# boylece takilan jeneratorun etkisi aninda barda gorunur, sokup-takarak da bedava dolum yapilamaz.
	if P == null:
		return
	var m := max_sh()
	if last_max_sh < 0.0:
		last_max_sh = m
		return
	if is_equal_approx(m, last_max_sh):
		return
	if last_max_sh > 0.0:
		sh_ratio = clampf(P.sh / last_max_sh, 0.0, 1.0)
	P.sh = minf(sh_ratio * m, m)
	last_max_sh = m


func _clamp_vitals() -> void:
	if P != null:
		_sync_shield()
		P.sh = minf(P.sh, max_sh())


func set_form(code: String) -> void:
	if code in SV.forms:
		cfg().form = code
		_clamp_vitals()
		save_game()


# Her konfigurasyonun KENDI kalkan havuzu vardir (oran olarak, 0..1). Aktif konfigurasyonun gercek
# degeri P.sh'tir; digerlerininki burada saklanir. Boylece bir konfigdeki kalkan bitince digerine
# gecildiginde oradaki kalkan (hasar almadiysa) dolu gelir.
var cfg_shr: Array = [1.0, 1.0, 1.0, 1.0]


func reset_cfg_shields() -> void:
	for k in cfg_shr.size():
		cfg_shr[k] = 1.0


func switch_cfg(i: int) -> void:
	if SV.is_empty() or P == null or i == int(SV.cfgi):
		return
	if cfg_cool > 0.0 and not in_safe:
		toast("Konfigürasyon değişimi için %d sn bekle." % ceili(cfg_cool))
		return
	var old_i := clampi(int(SV.cfgi), 0, cfg_shr.size() - 1)
	var new_i := clampi(i, 0, cfg_shr.size() - 1)
	var old_max := max_sh()
	cfg_shr[old_i] = clampf(P.sh / old_max, 0.0, 1.0) if old_max > 0.0 else 1.0
	SV.cfgi = i
	cfg_cool = 5.0
	var new_max := max_sh()
	P.sh = clampf(float(cfg_shr[new_i]), 0.0, 1.0) * new_max
	last_max_sh = new_max
	sh_ratio = float(cfg_shr[new_i])
	_clamp_vitals()
	_update_drones(0.0)   # droid dizilimi/formasyon yeni konfigurasyona hemen gecsin
	toast("Konfigürasyon %d aktif" % (i + 1))
	save_game()


func form_mod(key: String) -> float:
	return float(DOData.FORMS[str(cfg().form)][key])


func drone_bonus(key: String) -> float:
	var arr: Array = cfg().drn
	if arr.is_empty():
		return 0.0
	var t := form_mod(key)
	for id in arr:
		t += float(DOData.DRONES[id][key])
	return t


func dmg_mult() -> float:
	return maxf(0.2, 1.0 + drone_bonus("dmg"))


func ship_speed() -> float:
	var sp := float(ship_def().spd)
	for id in cfg().gen:
		var g: Dictionary = DOData.GENS[id]
		if g.type == "spd":
			sp += float(g.val)
	var f := 0.0
	if not cfg().drn.is_empty():
		f = form_mod("spd")
	return sp * (1.0 + f)


func absorb() -> float:
	var a := 0.8
	var c := cfg()
	for id in c.gen:
		var g: Dictionary = DOData.GENS[id]
		if g.type == "sh":
			a = maxf(a, float(g.abs))
	for id in drone_items(c):
		if DOData.GENS.has(id) and str(DOData.GENS[id].type) == "sh":
			a = maxf(a, float(DOData.GENS[id].abs))
	return minf(1.0, a + skill_bonus("shield_abs"))


func laser_raw_dmg() -> float:
	var t := 0.0
	for id in cfg().las:
		t += float(DOData.LASERS[id].dmg)
	return t + drone_laser_dmg()


func stats_text() -> String:
	return "Hasar %s/salvo (x1)   Hız %d   Kalkan %s   Emilim %%%d" % [_n(laser_raw_dmg() * dmg_mult()), int(ship_speed()), _n(max_sh()), int(round(absorb() * 100.0))]


func loadout_text() -> String:
	var c := cfg()
	var counts := {}
	for id in c.las:
		counts[id] = int(counts.get(id, 0)) + 1
	var parts := PackedStringArray()
	for id in DOData.LASER_ORDER:
		if counts.has(id):
			parts.append("%s x%d" % [DOData.LASERS[id].name, counts[id]])
	var lz := " ".join(parts) if parts.size() > 0 else "LAZER YOK"
	var dr := ""
	if c.drn.size() > 0:
		dr = "  |  Droid x%d" % c.drn.size()
	return "[C] Konf. %d  |  %s%s" % [int(SV.cfgi) + 1, lz, dr]


func can_pay(cr: int, uri: int) -> bool:
	return bool(SV.free) or (int(SV.cr) >= cr and int(SV.uri) >= uri)


func pay(cr: int, uri: int) -> bool:
	if bool(SV.free):
		return true
	if int(SV.cr) < cr or int(SV.uri) < uri:
		toast("Yetersiz bakiye!")
		return false
	SV.cr -= cr
	SV.uri -= uri
	return true


func buy_ship(id: String) -> bool:
	if id in SV.owned:
		return true
	var d := {}
	for s in DOData.SHIPS:
		if s.id == id:
			d = s
	if d.is_empty() or id in DOData.MARKET_HIDDEN or not pay(int(d.cr), int(d.uri)):
		return false
	SV.owned.append(id)
	toast("Satın alındı: " + str(d.name))
	save_game()
	return true


func equip_ship(id: String) -> void:
	if not (id in SV.owned) or SV.ship == id:
		return
	SV.ship = id
	ensure_loadout()
	var pos: Vector3 = P.node.position
	_make_player()
	P.node.position = pos
	drone_sig = ""
	if net_on:
		Net.send_ship(str(SV.ship))
	toast("Gemi değişti: " + ship_def().name)
	save_game()


func drones_owned() -> int:
	var n := 0
	for did in DOData.DRONE_ORDER:
		n += int(inv_dict(str(did)).get(str(did), 0))
	return n


func buy_item(id: String, qty: int) -> bool:
	var d := item_def(id)
	if DOData.DRONES.has(id) and drones_owned() + qty > DOData.MAX_DRONES:
		toast("En fazla %d droid satın alabilirsin! (Sahip olunan: %d)" % [DOData.MAX_DRONES, drones_owned()])
		return false
	if d.is_empty() or not pay(int(d.cr) * qty, int(d.uri) * qty):
		return false
	inv_dict(id)[id] = inv_count(id) + qty
	toast("Satın alındı: %s x%d" % [str(d.name), qty])
	save_game()
	return true


func sell_item(id: String) -> bool:
	var d := item_def(id)
	var have := inv_count(id)
	if d.is_empty() or have <= 0:
		return false
	for c in SV.loads[SV.ship]:
		var key := item_key(id)
		if (c[key] as Array).count(id) >= have:
			(c[key] as Array).erase(id)
	inv_dict(id)[id] = have - 1
	SV.cr += int(int(d.cr) * 0.4)
	SV.uri += int(int(d.uri) * 0.4)
	ensure_loadout()
	_clamp_vitals()
	toast("Satıldı: " + str(d.name))
	save_game()
	return true


func buy_form(code: String) -> bool:
	if code in SV.forms:
		return true
	if not pay(int(DOData.FORMS[code].cr), 0):
		return false
	SV.forms.append(code)
	toast("Formasyon açıldı: " + str(DOData.FORMS[code].name))
	save_game()
	return true


func buy_ammo(id: String, n: int) -> bool:
	var price := 0
	for a in DOData.AMMO:
		if a.id == id:
			price = int(a.price * n / 1000)
	if not pay(price, 0):
		return false
	SV.ammo[id] = int(SV.ammo.get(id, 0)) + n
	toast("+%d %s cephane" % [n, id.to_upper()])
	save_game()
	return true


func buy_rockets(n: int) -> bool:
	if n <= 0:
		return false
	var cost := int(ceil(float(n) / 100.0) * 1000.0)
	if not pay(cost, 0):
		return false
	SV.rockets = int(SV.rockets) + n
	toast("+%d R-310 roketi" % n)
	save_game()
	return true


func service_repair() -> void:
	var cost := 0 if bool(SV.free) else int((max_hp() - P.hp) / 40.0)
	if not pay(cost, 0):
		return
	P.hp = max_hp()
	P.sh = max_sh()
	reset_cfg_shields()
	toast("Gemi tamir edildi.")


func repair_cost() -> int:
	if bool(SV.free):
		return 0
	return int((max_hp() - P.hp) / 40.0)


# Muhimmat secim merkezi (HUD hucreleri ve hizli slotlar buradan gecmeli).
# RSB kurallari tek yerde isler:
#  - RSB beklemesi varken RSB secilamaz; secim degismez, cephaneyi harcamaz.
#  - Her manuel non-RSB secim "onceki muhimmat" (rsb_prev) olarak kaydedilir;
#    RSB atildiktan sonra otomatik olarak buna donulur.
func select_ammo(id: String) -> void:
	id = str(id)
	if id != "rsb":
		rsb_prev = id
		SV.sel = id
		return
	if rsb_cd > 0.0:
		toast("RSB-75 hazirlaniyor (%ds), bu surede %s kullanilmaya devam eder." % [int(ceil(rsb_cd)), str(SV.get("sel", "")).to_upper()])
		return
	if int(SV.ammo.get("rsb", 0)) <= 0:
		toast("RSB-75 cephanesi yok! Mağazadan cephane al.")
		return
	SV.sel = "rsb"


# Ekranda yalnizca ODUL yazilari gorunur (hasar sayilari ayri cizilir). Diger tum bildirimler sohbet gunlugune
# yazilir ama ekrana cikmaz. Baska bir yazi gostermek icin asagidaki _toast_visible() kosullarina ekle.
func _toast_visible(t: String) -> bool:
	return t.begins_with("Bonus kutu") or t.begins_with("Görev ödülü") or t.begins_with("Seviye ") or t.begins_with("Atlama engellendi") \
		or (t.begins_with("+") and t.contains("XP"))


func toast(t: String) -> void:
	if dohud != null:
		dohud.log_system(t)
	if not _toast_visible(t):
		return
	# DarkOrbit tarzı: ekranın üst-ortasında belirir, yukarı süzülerek silinir. Aynı anda gelenler alt alta dizilir.
	var recent := 0
	for tt in toasts:
		if float(tt.max) - float(tt.life) < 0.5:
			recent += 1
	toasts.append({"t": t, "life": 3.5, "max": 3.5, "off": 20.0 * float(recent), "lbl": null})
	if toasts.size() > 8:
		var old = toasts[0].get("lbl")
		if old != null and is_instance_valid(old):
			old.queue_free()
		toasts.remove_at(0)


func new_game(f: int) -> void:
	SV = {"faction": f, "cr": 5000, "uri": 0, "xp": 0.0, "hon": 0.0, "ship": "phoenix", "owned": ["phoenix"], "sel": "x1",
	"ammo": {"x1": 5000, "x2": 500, "x3": 200, "x4": 0, "sab": 0, "rsb": 0}, "rockets": 50,
	"map": DOData.FACTIONS[f].home, "px": 0.0, "pz": 0.0, "kills": 0, "callsign": (account_name if account_name != "" else "Gezgin"),
	"inv": {"lf1": 4, "sg3n-a01": 1}, "forms": ["std"], "loads": {}, "cfgi": 0, "free": false,
	"quests": {}, "skills": {}, "skill_points": 0, "maps_visited": [], "route_to": "",
	"settings": {"stars": true, "zoom": 1.0, "graphics": 2}, "drone_equip": {},
	"reg_ts": Time.get_unix_time_from_system(), "pvp_kills": 0, "rank_pen": 0.0}
	ensure_campaign_data()
	ensure_loadout()
	_start_run(true)


func continue_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		toast("Kayıt dosyası açılamadı.")
		return
	var d = JSON.parse_string(f.get_as_text())
	if d == null or typeof(d) != TYPE_DICTIONARY:
		new_game(account_faction if account_faction > 0 else 1)
		return
	SV = d
	SV.owned = Array(SV.owned)
	SV.faction = int(SV.faction)
	# Hesaba kilitli: sirket ve oyuncu adi kayittan degil hesaptan gelir.
	if account_faction > 0:
		SV.faction = account_faction
	if account_name != "":
		SV.callsign = account_name
	if not SV.has("inv"):
		SV.inv = {"lf2": 15, "sg3n-a01": 20}
	if not SV.ammo.has("rsb"):
		SV.ammo["rsb"] = 0
	if not SV.has("drone_equip"):
		SV.drone_equip = {}
	SV.forms = Array(SV.get("forms", ["std"]))
	if not SV.has("loads"):
		SV.loads = {}
	ensure_campaign_data()
	ensure_loadout()
	_start_run(false)


func save_game() -> void:
	if SV.is_empty() or P == null:
		return
	SV.map = cur
	SV.px = P.node.position.x
	SV.pz = P.node.position.z
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(SV))
	_refresh_plate_rank()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()   # telefonda uygulamadan cikinca ilerleme kaybolmasin
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_go_back()   # Android geri tusu


# Android geri tusu: once acik pencereyi kapat, yoksa hedefi / hareketi birak (oyundan atmaz).
func _on_go_back() -> void:
	if not running:
		return
	if dohud != null and dohud.close_popups():
		return
	if base_menu.visible:
		base_menu.visible = false
	elif gal_panel.visible:
		gal_panel.visible = false
	else:
		_stop_all()


func _make_player() -> void:
	var old = null
	if P != null:
		old = P.node
	var o := make_ship(SV.ship, 6.0, ship_faction_tint())
	add_child(o)
	if old != null:
		old.queue_free()
	P = {"node": o, "hp": max_hp(), "sh": max_sh(), "cd": 0.0}
	if not player_bar.is_empty() and is_instance_valid(player_bar.get("root")):
		player_bar.root.queue_free()
	player_bar = _make_bar3d(o, BAR_W, 0.0)
	last_max_sh = max_sh()
	sh_ratio = 1.0
	reset_cfg_shields()


func _start_run(is_new: bool, skip_connect: bool = false) -> void:
	# Oyun tamamen cevrimici: giris yapilinca her zaman sabit sunucuya baglanilir.
	print("[ISTEMCI] _start_run cagrildi: is_new=%s, skip_connect=%s" % [is_new, skip_connect])
	net_wanted = true
	net_addr = Net.SERVER_ADDR
	if net_wanted and not skip_connect:
		var ok: bool = await Net.connect_and_join(net_addr, {"name": str(SV.get("callsign", "Gezgin")),
			"faction": int(SV.get("faction", 1)), "ship": str(SV.get("ship", "phoenix"))})
		print("[ISTEMCI] connect_and_join sonucu: ok=%s, last_error=%s" % [ok, Net.last_error])
		if not ok:
			menu.modulate = Color(1, 1, 1, 1)
			menu.show()
			auth_box.visible = true
			company_box.visible = false
			lbl_auth_msg.text = "Sunucuya bağlanılamadı: " + Net.last_error
			return
	menu.hide()
	ensure_campaign_data()
	ensure_loadout()
	stars_on = bool(SV.settings.stars)
	zoom = clampf(float(SV.settings.zoom), 0.6, 1.8)
	zoom_cur = zoom
	cam_auto = 1.0
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(SV.settings.graphics)]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(SV.settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)
	lbl_help.visible = false   # alttaki kontrol yazisi kapali baslar ([H] ile acilabilir)
	for n in hud_nodes:
		n.visible = true
	P = null
	extras.reset()
	_make_player()
	_build_plate()
	var m = maps[SV.map]
	var arrive := w2g(m.w / 2.0, m.h / 2.0)
	if m.base != null:
		arrive = w2g(m.base.x, m.base.y) + Vector3(10, 0, 10)
	if not is_new and (SV.px != 0.0 or SV.pz != 0.0):
		arrive = Vector3(SV.px, 0, SV.pz)
	load_map(SV.map, arrive)
	running = true
	toast("Hoş geldin! Tıkla: hareket/hedef  |  Ctrl/Boşluk: lazer  |  R: roket  |  J: kapı  |  M: harita")


func load_map(name: String, arrive: Vector3) -> void:
	cam_focus_ready = false
	map_gen += 1
	cur = name
	repairing = false   # haritadan ayrilinca tamir sifirlanir
	rad_in = false
	rad_acc = 0.0
	if rad_label != null:
		rad_label.visible = false
	if world != null:
		world.queue_free()
	world = Node3D.new()
	add_child(world)
	# Harita degisiminde eski NPC barlarini da serbest birak; yoksa ui altinda birikir -> FPS erir.
	for e in enemies:
		for bk in ["hp_back", "sh_back"]:
			var bn = e.get(bk)
			if bn != null and is_instance_valid(bn):
				bn.queue_free()
	enemies.clear()
	if Net.gm != null:
		Net.gm.reset_map()
	boxes.clear()
	collect_box = null
	collect_t = 0.0
	portals.clear()
	bullets.clear()
	fxs.clear()
	fx2.clear()
	pops.clear()
	target = null
	dest = null
	holding = false
	fire = false
	spd_cur = 0.0
	jump_t = -1.0
	jump_wait_until = -1.0
	prot_kind = 0
	net_prot = 0     # yeni haritada koruma durumunu sunucu yeniden hesaplar (s_prot)
	base_pos = null
	var m = maps[name]
	_apply_map_color_theme(name, m)
	bg_tex = _tex(MAP_TEX % name)
	MapBg.set_map(name)
	if space_fog != null:
		space_fog.set_map(name)
	mm.set_map(m.name, m.w, m.h, bg_tex)
	_layout_right()
	_build_border(m)
	_build_dust(m)
	var size_mul := maxf(1.0, sqrt(float(m.w) * float(m.h) / (DOData.STD_MAP_W * DOData.STD_MAP_H)))
	for i in (int(10.0 * size_mul) if SPAWN_ASTEROIDS else 0):
		var o := make_ship("asset-mmo-asteroid" if randf() < 0.5 else "asset-mmo-asteroid-b", randf_range(6, 18), Color.WHITE)
		o.position = w2g(randf_range(500, m.w - 500), randf_range(500, m.h - 500))
		o.rotation = Vector3(randf() * 6.0, randf() * 6.0, randf() * 6.0)
		world.add_child(o)
	if m.base != null:
		var b := make_ship(DOData.FACTIONS[m.faction].base, 38.0, Color.WHITE)
		base_pos = w2g(m.base.x, m.base.y)
		b.position = base_pos
		world.add_child(b)
		_sink_below_plane(b, 1.5)   # gemi ussun ALTINDA kalmasin: model ucus duzleminin altina iner
		var hq_color: Color = CMS_FACTION_COLORS.get(int(m.faction), Color("#8658A8"))
		var hq_lbl := label_pro("%s ÜSSÜ" % DOData.FACTIONS[m.faction].name, base_pos + Vector3(0, 14, 0), hq_color.lightened(0.55), 36)
		world.add_child(hq_lbl)
	for p in m.portals:
		var g: Node3D
		if p.get("wormhole", false):
			g = Node3D.new()   # Solucan deligi gorunmezdir
		else:
			g = JumpGate.new().setup(Color("#36D5FF"))   # kod ile cizilen, animasyonlu NOVAGATE kapisi (jumpgate.gd)
		g.position = w2g(p.x, p.y)
		world.add_child(g)
		if not p.get("wormhole", false):
			g.add_child(label_pro("KAPI: %s" % str(p.to).to_upper(), Vector3(0, 9, 0), Color(0.78, 0.93, 1.0), 30))
		portals.append({"node": g, "to": p.to, "pos": g.position})
	# NPC dogumu: yapilandirilmis "zones" (dogus bolgeleri/koordinatlari) tercih edilir.
	if not net_on:
		_spawn_map_npcs(m)   # cok oyunculuda NPC'leri sunucu dogurur
	# Cok oyunculuda kutulari sunucu belirler (Net.gm.on_boxes); tek oyunculuda yerel dogar.
	for i in (int(35.0 * size_mul) if not net_on else 0):
		var bx := _make_bonus_box(w2g(randf_range(800, m.w - 800), randf_range(800, m.h - 800)))
		world.add_child(bx)
		boxes.append({"node": bx})
	P.node.position = arrive
	P.node.rotation = Vector3.ZERO
	if not SV.maps_visited.has(name):
		SV.maps_visited.append(name)
	toast("Harita: " + m.name)
	var route_target := str(SV.get("route_to", ""))
	if route_target == name:
		SV.route_to = ""
		toast("Rota hedefine ulaşıldı: " + name)
	elif route_target != "":
		call_deferred("_continue_map_route")
	if net_on:
		Net.enter_map(name, P.node.position.x, P.node.position.z)
	save_game()


# Bonus kutu: koyu metal kargo konteyneri, parlayan mavi seritler ve koselerde enerji sutunlari,
# yerde nabiz atan halka. Govde havada hafifce salinir (animasyon _update_game icinde).
func _make_bonus_box(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var body := Node3D.new()
	body.position.y = 0.9
	root.add_child(body)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.13, 0.17, 0.23)
	steel.metallic = 0.85
	steel.roughness = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.36, 0.44, 0.54)
	trim.metallic = 0.9
	trim.roughness = 0.22
	var glow := _unshaded(Color(0.3, 0.9, 1.0))
	var parts := [
		[Vector3(1.3, 1.3, 1.3), Vector3.ZERO, steel],                       # ana govde
		[Vector3(1.55, 0.14, 1.55), Vector3(0, 0.68, 0), trim],              # ust plaka
		[Vector3(1.55, 0.14, 1.55), Vector3(0, -0.68, 0), trim],             # alt plaka
		[Vector3(0.9, 0.1, 0.05), Vector3(0, 0.12, 0.66), glow],             # yan parlak seritler
		[Vector3(0.9, 0.1, 0.05), Vector3(0, 0.12, -0.66), glow],
		[Vector3(0.05, 0.1, 0.9), Vector3(0.66, 0.12, 0), glow],
		[Vector3(0.05, 0.1, 0.9), Vector3(-0.66, 0.12, 0), glow],
		[Vector3(0.5, 0.5, 0.05), Vector3(0, -0.2, 0.66), trim],             # on panel
		[Vector3(0.5, 0.5, 0.05), Vector3(0, -0.2, -0.66), trim],
	]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append([Vector3(0.14, 1.4, 0.14), Vector3(0.72 * sx, 0, 0.72 * sz), glow])   # kose enerji sutunlari
	for it in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = it[0]
		mi.mesh = bm
		mi.position = it[1]
		mi.material_override = it[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
	# yerde nabiz atan halka (isik havuzu)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_color = Color(0.3, 0.85, 1.0, 0.45)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.46
	tm.outer_radius = 0.5
	tm.rings = 40
	tm.ring_segments = 6
	var halo := MeshInstance3D.new()
	halo.mesh = tm
	halo.material_override = hm
	halo.scale = Vector3.ONE * 3.0
	halo.position.y = 0.05
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	root.set_meta("body", body)
	root.set_meta("halo", hm)
	return root


# Toplama bitisi: parlak flas, genisleyen halkalar, yukselen enerji halkalari ve kivilcim.
func _box_collect_burst(p: Vector3) -> void:
	var cy := Color(0.35, 0.9, 1.0)
	_fx_sphere(p + Vector3(0, 0.8, 0), Color(0.85, 0.97, 1.0), 1.5, 7.0, 0.35, 0.8)
	_fx_ring(p + Vector3(0, 0.1, 0), cy, 1.5, 9.0, 0.55, 0.9)
	_fx_ring(p + Vector3(0, 0.1, 0), Color(1, 1, 1), 1.0, 6.0, 0.4, 0.7)
	for i in 4:
		_fx_ring(p + Vector3(0, 0.3 + 0.35 * i, 0), cy, 3.2 - 0.4 * i, 1.0, 0.45 + 0.08 * i, 0.7, Vector3(0, 5.0, 0))
	spark_burst(p + Vector3(0, 0.8, 0), cy.lerp(Color(1, 1, 1), 0.4), 22, 12.0)


var fx_ring_mesh: TorusMesh = null


# Yatay, additive halka efekti (fx2 sistemine baglanir: buyur/kuculur + solar). vel verilirse yukari/asagi kayar.
func _fx_ring(pos: Vector3, col: Color, s0: float, s1: float, life: float, a0: float, vel := Vector3.ZERO) -> void:
	if world == null or fx2.size() > 260:
		return
	if fx_ring_mesh == null:
		fx_ring_mesh = TorusMesh.new()
		fx_ring_mesh.inner_radius = 0.46
		fx_ring_mesh.outer_radius = 0.5
		fx_ring_mesh.rings = 40
		fx_ring_mesh.ring_segments = 6
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(col.r, col.g, col.b, a0)
	var mi := MeshInstance3D.new()
	mi.mesh = fx_ring_mesh
	mi.material_override = mt
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.position = pos
	mi.scale = Vector3.ONE * s0
	fx2.append({"node": mi, "mat": mt, "t": 0.0, "life": life, "s0": s0, "s1": s1, "a0": a0, "vel": vel, "follow": null})


# Kucuk parlak enerji parcacigi (hizla hareket eder, kuculerek solar).
func _fx_mote(pos: Vector3, col: Color, size: float, life: float, vel: Vector3) -> void:
	if world == null or fx2.size() > 260:
		return
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(col.r, col.g, col.b, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = fx_sphere
	mi.material_override = mt
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.position = pos
	mi.scale = Vector3.ONE * size
	fx2.append({"node": mi, "mat": mt, "t": 0.0, "life": life, "s0": size, "s1": size * 0.2, "a0": 0.9, "vel": vel, "follow": null})


# Bonus kutu odulu (tek oyunculuda toplama animasyonu bitince, cok oyunculuda sunucu onayiyla verilir).
func box_reward() -> void:
	var pn: Node3D = P.node
	var po: Vector3 = pn.position
	var r := randf()
	var ptxt := ""
	var pcol := Color(1.0, 0.88, 0.4)
	if r < 0.75:
		var c := int(float(randi_range(500, 2000)) * (1.0 + skill_bonus("loot_box")))
		SV.cr += c
		toast("Bonus kutu: +%d Kredi" % c)
		ptxt = "+%s Kredi" % _n(c)
	elif r < 0.95:
		var a := randi_range(200, 1000)
		SV.ammo.x1 += a
		toast("Bonus kutu: +%d x1 cephane" % a)
		ptxt = "+%s x1" % _n(a)
		pcol = Color(0.75, 0.95, 1.0)
	else:
		var u := int(float(randi_range(5, 40)) * (1.0 + skill_bonus("box_uri")) * (1.0 + skill_bonus("loot_box")))
		SV.uri += u
		toast("Bonus kutu: +%d Uridium!" % u)
		ptxt = "+%s Uridium" % _n(u)
		pcol = Color(0.84, 0.63, 1.0)
	var bp: Vector3 = po
	if collect_box != null and is_instance_valid(collect_box.node):
		bp = collect_box.node.position
	_box_collect_burst(Vector3(bp.x, po.y, bp.z))
	popup_txt(ptxt, po + Vector3(0.0, 1.5, 0.0), pcol)
	if collect_box != null:
		if is_instance_valid(collect_box.node):
			collect_box.node.queue_free()
		boxes.erase(collect_box)
	collect_box = null
	collect_t = 0.0


func _map_route(source: String, target_map: String) -> Array:
	if not maps.has(source) or not maps.has(target_map):
		return []
	var queue: Array = [source]
	var previous: Dictionary = {}
	previous[source] = ""
	var head := 0
	while head < queue.size():
		var current := str(queue[head])
		head += 1
		if current == target_map:
			break
		for portal in maps[current].portals:
			var next_map := str(portal.to)
			if next_map == "random":
				continue
			if not previous.has(next_map):
				previous[next_map] = current
				queue.append(next_map)
	if not previous.has(target_map):
		return []
	var path: Array = []
	var cursor := target_map
	while cursor != "":
		path.push_front(cursor)
		cursor = str(previous.get(cursor, ""))
	return path


func request_map_route(target_map: String) -> void:
	if not running or not maps.has(target_map):
		return
	if target_map == cur:
		clear_map_route()
		toast("Zaten bu haritadasın.")
		return
	var path := _map_route(cur, target_map)
	if path.size() < 2:
		toast("Bu haritaya geçerli bir rota bulunamadı.")
		return
	SV.route_to = target_map
	_continue_map_route()
	save_game()


func clear_map_route() -> void:
	SV.route_to = ""
	dest = null
	holding = false
	save_game()
	toast("Harita rotası iptal edildi.")


func _continue_map_route() -> void:
	var target_map := str(SV.get("route_to", ""))
	if target_map == "" or target_map == cur:
		return
	var path := _map_route(cur, target_map)
	if path.size() < 2:
		SV.route_to = ""
		toast("Rota artık geçerli değil; iptal edildi.")
		return
	var next_map := str(path[1])
	for portal in portals:
		if str(portal.to) == next_map:
			_stop_all()
			dest = portal.pos
			toast("Rota: %s → %s. Kapıya uç ve J ile geç." % [cur, target_map])
			return
	SV.route_to = ""
	toast("Bağlantı kapısı bulunamadı; rota iptal edildi.")


func _build_border(_m: Dictionary) -> void:
	# Sinir cizgisi ve kirmizi dolgu yok: harita disi sinirsiz radyasyon alanidir (yalnizca uyari + hasar).
	pass


# Radyasyon alani: harita disinda saniyede max HP'nin %1'inden %5'ine (derinlige gore) hasar + rutbe puani kaybi.
func _radiation_tick(dt: float, pos: Vector3) -> void:
	if P == null or not maps.has(cur):
		return
	var m = maps[cur]
	var W: float = m.w * DOData.S
	var H: float = m.h * DOData.S
	var out_d: float = maxf(maxf(-pos.x, pos.x - W), maxf(-pos.z, pos.z - H))
	if out_d <= 0.0:
		rad_acc = 0.0
		if rad_label != null:
			rad_label.visible = false
		if rad_in:
			rad_in = false
			toast("Radyasyon alanından çıktın.")
		return
	if not rad_in:
		rad_in = true
		toast("RADYASYON ALANI! Haritaya geri dön, sürekli hasar alıyorsun.")
	if rad_label != null:
		rad_label.visible = true
		rad_label.modulate.a = 0.65 + 0.35 * sin(clock * 6.0)
	var depth: float = clampf(out_d / (RAD_MARGIN * DOData.S), 0.0, 1.0)
	rad_acc += dt
	if rad_acc < 1.0:
		return
	rad_acc -= 1.0
	var pct: float = lerpf(RAD_MIN_PCT, RAD_MAX_PCT, depth)
	SV.hon = maxf(0.0, float(SV.hon) - (2.0 + 8.0 * depth))
	hurt(max_hp() * pct, true)   # radyasyon kalkani es gecer, dogrudan cana islenir


func _build_dust(m: Dictionary) -> void:
	var W: float = m.w * DOData.S
	var H: float = m.h * DOData.S
	var count := int(clampf(W * H / 450.0, 800.0, 2600.0))
	var pts := PackedVector3Array()
	for i in count:
		pts.append(Vector3(randf() * W, -3.0, randf() * H))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.use_point_size = true
	mt.point_size = 1.0
	mt.albedo_color = Color(0.75, 0.85, 1.0, 0.3)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mt
	world.add_child(mi)


# ---------- YAPILANDIRILMIS NPC DOGUSU (2010 harita duzeni) ----------
const NPC_SPACING := 2200.0    # iki NPC dogma noktasi arasindaki asgari mesafe (DO birimi)


# Bir noktanin uygun dogus yeri olup olmadigini kontrol eder:
# harita sinirlari, guvenli bolge (us), portallar ve diger NPC'ler.
func _spot_free(pos: Vector3, m: Dictionary, used: Array) -> bool:
	var mx: float = float(m.w) * DOData.S
	var mz: float = float(m.h) * DOData.S
	if pos.x < 700.0 or pos.z < 700.0 or pos.x > mx - 700.0 or pos.z > mz - 700.0:
		return false
	if base_pos != null and pos.distance_to(base_pos) < DOData.SAFE_RADIUS * DOData.S * 1.05:
		return false
	for p in portals:
		if is_instance_valid(p.node) and pos.distance_to(p.pos) < DOData.PORTAL_RANGE * DOData.S * 1.5:
			return false
	for u in used:
		if Vector3(u).distance_to(pos) < NPC_SPACING * DOData.S:
			return false
	return true


# Zone verisinden uygun bir dogma koordinati secer.
# "fixed" (Cubikon) varsa o koordinat kullanilir; portal/us uzakligi saglanmiyorsa kucuk bir
# kaydirma ile guvenli noktaya oturtulur. "area" varsa bolgenin icinden denenir.
func _zone_spot(m: Dictionary, z: Dictionary, used: Array) -> Vector3:
	if z.has("fixed"):
		var fp: Vector3 = w2g(float(z["fixed"][0]), float(z["fixed"][1]))
		for gi in 24:
			if _spot_free(fp, m, used):
				return fp
			fp += Vector3(randf_range(-1600.0, 1600.0), 0.0, randf_range(-1600.0, 1600.0)) * DOData.S
		return fp
	var fa: Array = z.get("area", [1500.0, 1500.0, float(m.w) - 1500.0, float(m.h) - 1500.0])
	for gi in 48:
		var pos: Vector3 = w2g(randf_range(float(fa[0]), float(fa[2])), randf_range(float(fa[1]), float(fa[3])))
		if _spot_free(pos, m, used):
			return pos
	# uygun nokta bulunamadi: eski rastgele davranisa dus (harita bos kalmasin)
	return w2g(randf_range(1500.0, float(m.w) - 1500.0), randf_range(1500.0, float(m.h) - 1500.0))


# Haritadaki "zones" verisine gore NPC'leri dogurur (yapilandirilmis, kontrollu dagilim).
func _spawn_map_npcs(m: Dictionary) -> void:
	var zones: Array = m.get("zones", [])
	if zones.is_empty():
		for e in m.get("npcs", []):
			for i in int(e[1]):
				spawn_npc(str(e[0]))
		return
	var used: Array = []
	for zi in zones.size():
		var z: Dictionary = zones[zi]
		for i in int(z.get("n", 1)):
			var sp: Vector3 = _zone_spot(m, z, used)
			used.append(sp)
			var ne = spawn_npc(str(z.get("npc", "")), sp)
			if ne is Dictionary:
				(ne as Dictionary)["zone"] = zi


# ---------- CUBIKON + PROTEGIT SAVUNMA SISTEMI (2010) ----------
# Cubikon: sabit durur, dogrudan saldirmaz. Saldirildiginda Protegit savunma dalgasini
# baslatir ve saldiri kesilince HP'sini yeniler. Protegit'ler Cubikonu korumak icin
# oyuncuyu takip eder, etrafinda donerek ates eder; Cubikon olunce gorevi birakip
# belirlenen sure sonunda sessizce haritadan temizlenirler.

# Cubikonun anlik durumu: sabit, donusemez, dogrudan saldirmaz.
# Saldiri alinca 20-30 arasi (rastgele) Protegit cagirir; oyuncu "leash" mesafesinden fazla
# uzaklasirsa yeni Protegit cagirmaz. Olen Protegit'ler hizla yenilenir (wave/wave_gap).
func _update_cubic(e: Dictionary, en: Node3D, dvec: Vector3, L: float, dt: float) -> void:
	var C: Dictionary = DOData.CUBIKON
	if L > 0.001:
		face(en, dvec, dt)     # sadece oyuncuya bakar; KONUMU DEGISTIRMEZ
	var since_hit: float = clock - float(e.get("last_hit_t", -1.0e9))
	# HP yenileme: saldiri kesildikten regen_delay sn sonra, yapilandirilabilir hizda.
	if since_hit > float(C.regen_delay) and float(e.hp) < float(e.mx):
		e.hp = minf(float(e.mx), float(e.hp) + float(C.regen_hp) * dt)
	var leash_u: float = float(C.leash) * DOData.S
	var engaged: bool = since_hit < float(C.regen_delay) and L <= leash_u
	if engaged:
		# Ilk saldiride kadro buyuklugu belirlenir: 20-30 arasi rastgele Protegit.
		if not bool(e.get("guards_called", false)):
			e["guards_called"] = true
			e["guard_quota"] = randi_range(int(C.guard_min), int(C.guard_max))
			e["wave_t"] = 0.0
		var missing: int = int(e.get("guard_quota", 0)) - _guard_count(e)
		if missing > 0:
			e["wave_t"] = float(e.get("wave_t", 0.0)) - dt
			if float(e["wave_t"]) <= 0.0:
				e["wave_t"] = float(C.wave_gap)
				for gi in mini(int(C.wave), missing):
					_spawn_guard(e)
	elif since_hit > float(C.regen_delay):
		e["guards_called"] = false   # sakinlesti: bir sonraki saldirida kadro yeniden belirlenir


# Cubikona bagli Protegit sayisi (canli olanlar).
func _guard_count(home: Dictionary) -> int:
	var n := 0
	var hnode: Variant = home.get("node")
	for e in enemies:
		if str(e.get("id", "")) != "protegit" or not e.has("guard_home"):
			continue
		if float(e.get("hp", 0.0)) <= 0.0 or not is_instance_valid(e.get("node")):
			continue
		var h: Variant = e["guard_home"]
		if h is Dictionary and (h as Dictionary).get("node") == hnode:
			n += 1
	return n


# Cubikondan bir Protegit cikarir (gercek NPC: model, HP, kalkan, bar, etiket).
func _spawn_guard(home: Dictionary) -> void:
	var C: Dictionary = DOData.CUBIKON
	var hnode: Variant = home.get("node")
	if not is_instance_valid(hnode):
		return
	var orr: float = randf_range(float(C.swarm_r_min), float(C.swarm_r_max))
	var oa: float = randf() * TAU
	var ow: float = randf_range(float(C.swarm_w_min), float(C.swarm_w_max)) * (1.0 if randf() < 0.5 else -1.0)
	var at: Vector3 = (hnode as Node3D).position + Vector3(cos(oa) * orr, 0.0, sin(oa) * orr)
	var ne = spawn_npc("protegit", at)
	if ne is Dictionary:
		var g: Dictionary = ne
		g["guard_home"] = home
		g["home_pos"] = (hnode as Node3D).position
		g["aggro"] = true
		g["orb_r"] = orr          # Cubikon etrafindaki surunun yorunge yaricapi
		g["orb_a"] = oa           # yorunge acisi
		g["orb_w"] = ow           # yorunge acisal hizi (rad/sn, +/-)
		g["cd"] = 0.0   # ilk atis: oyuncu Cubikonun menziline girdigi an; sonrakiler NPC_FIRE_INTERVAL aralikla
		g["far_t"] = 0.0
		g["desp"] = float(C.clean_after)


# Protegit davranisi: Cubikonun etrafinda suru halinde doner, oyuncuyu TAKIP ETMEZ. Oyuncu Cubikonun
# menzilindeyken rastgele araliklarla, tek tek ates eder. Oyuncu leash disina cikarsa yok olur.
# Cubikon olduyse clean_after sn sonra sessizce temizlenir (odul/patlama yok).
func _update_guard(e: Dictionary, en: Node3D, dvec: Vector3, L: float, dt: float) -> void:
	var C: Dictionary = DOData.CUBIKON
	var home: Variant = e.get("guard_home")
	var hAlive: bool = false
	if home is Dictionary:
		hAlive = float((home as Dictionary).get("hp", 0.0)) > 0.0
	if not hAlive:
		# Cubikon yok: koruma gorevi bitti -> sessiz temizlik sayaci
		e["desp"] = float(e.get("desp", float(C.clean_after))) - dt
		if float(e["desp"]) <= 0.0:
			e["silent"] = true
			e.hp = 0.0
			return
		# Cubikonun oldugu yerde devriye: oyuncuya saldirmaz
		var hp_pos: Vector3 = Vector3(e.get("home_pos", en.position))
		e.t -= dt
		if e.t <= 0.0:
			e.t = randf_range(2, 5)
			var to_home: Vector3 = hp_pos - en.position
			to_home.y = 0.0
			e.v = to_home.normalized() if to_home.length() > 0.5 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var spd0: float = float(e.d.spd) * DOData.S * DOData.SPEEDMULT * 0.5
		en.position += e.v * spd0 * dt
		face(en, e.v, dt)
		return
	# Cubikon canli: Protegit ASLA Cubikondan "leash" mesafesinden fazla uzaklasmaz.
	var hn_v: Variant = (home as Dictionary).get("node")
	if hn_v == null or not is_instance_valid(hn_v):
		return
	var hnode: Node3D = hn_v
	var hpos: Vector3 = hnode.position
	var leash_u: float = float(C.leash) * DOData.S
	var tnode: Node3D = _guard_target(home)
	if tnode == null or not is_instance_valid(tnode):
		return
	var pflat: Vector3 = tnode.position - hpos
	pflat.y = 0.0
	if pflat.length() > leash_u:
		# Oyuncu Cubikondan cok uzaklasti: takibi birak, Cubikona don, kisa sure sonra YOK OL.
		e["far_t"] = float(e.get("far_t", 0.0)) + dt
		if float(e["far_t"]) >= float(C.leash_despawn):
			e["silent"] = true      # odul/patlama yok, sessizce silinir (queue_free)
			e.hp = 0.0
			return
		var back: Vector3 = hpos - en.position
		back.y = 0.0
		if back.length() > 1.0:
			var spd_b: float = float(e.d.spd) * DOData.S * DOData.SPEEDMULT * 0.8
			en.position += back.normalized() * spd_b * 1.15 * dt
			face(en, back, dt)
		return
	e["far_t"] = 0.0
	# SURU: Cubikonun etrafindaki kendi yorungesinde doner; oyuncuya yaklasmaz.
	var ang: float = float(e.get("orb_a", 0.0)) + float(e.get("orb_w", 0.5)) * dt
	e["orb_a"] = ang
	var orr: float = float(e.get("orb_r", float(C.swarm_r_min)))
	var slot: Vector3 = hpos + Vector3(cos(ang) * orr, 0.0, sin(ang) * orr)
	slot.y = en.position.y
	var to_slot: Vector3 = slot - en.position
	to_slot.y = 0.0
	var spd: float = float(e.d.spd) * DOData.S * DOData.SPEEDMULT * 0.8
	var stp: float = minf(to_slot.length(), spd * 1.15 * dt)
	if to_slot.length() > 0.001:
		en.position += to_slot.normalized() * stp
	# Leash kelepcesi: Cubikonun etrafindaki daire disina cikamaz.
	var goff: Vector3 = en.position - hpos
	goff.y = 0.0
	if goff.length() > leash_u:
		var gcl: Vector3 = goff.normalized() * leash_u
		en.position.x = hpos.x + gcl.x
		en.position.z = hpos.z + gcl.z
	# Ates yalnizca oyuncu Cubikonun menzilindeyken; sayac sadece menzildeyken isler (esgudum olmasin).
	var engaged: bool = pflat.length() <= float(C.engage_range) * DOData.S and L <= float(C.guard_range) * DOData.S
	if engaged and not extras.untargetable():
		face(en, d_to_player_dir(en, tnode), dt)
		var cd_prev: float = e.cd
		e.cd -= dt
		var lock_ok: bool = clock >= float((home as Dictionary).get("guard_fire_t", 0.0))
		if e.cd <= 0.0 and lock_ok:
			e.cd = DOData.rearm_cd(cd_prev, e.cd, dt, DOData.NPC_FIRE_INTERVAL)
			(home as Dictionary)["guard_fire_t"] = clock + float(C.fire_lock)
			# TEK atis olayi: tek lazer gorseli + tek hasar (hasar mermi hedefe ulasinca bir kez uygulanir)
			_npc_bolt(e, 0, DOData.npc_shot_damage(e.d), map_gen)
	else:
		face(en, to_slot, dt)


func d_to_player_dir(en: Node3D, tn: Node3D) -> Vector3:
	var v: Vector3 = tn.position - en.position
	v.y = 0.0
	return v


# "En cok hasar veren saldirgan" secimi. Cubikon "dmg_tally" kaydinda biriktirilen katkilar
# karsilastirilir; tek oyunculu surumde bu daima gecerli oyuncudur, ancak cok oyunculu
# guncellemeler icin altyapi hazirdir.
func _guard_target(home: Dictionary) -> Node3D:
	var best := ""
	var bestv := -1.0
	if home.has("dmg_tally"):
		var tally: Dictionary = home["dmg_tally"]
		for k in tally.keys():
			var v: float = float(tally[k])
			if v > bestv:
				bestv = v
				best = str(k)
	if best != "" and best != "player" and P != null:
		# Gelecekte gercek oyuncu dugumu burada cozulur; simdilik aktif oyuncu doner.
		return P.node
	if P != null:
		return P.node
	return null


# NPC modeli: Cubikon icin kendi modeli aranir (Kristallon'un gorselini KULLANMAZ).
# Sirayla res://models/ icinde bulunan ilk dosya secilir; hicbiri yoksa data.gd'deki model kullanilir.
const CUBIKON_MODELS := ["cubikon", "kucurbium-boss", "kucubium-boss", "kucurbium", "kucubium"]


const PROTEGIT_MODELS := ["protegit"]
const PROTEGIT_MAX_SIZE := 1.5   # Protegit azami gorsel boyutu (Cubikon = 20)


func _npc_model(id: String, fallback: String) -> String:
	if id == "protegit":
		for nm in PROTEGIT_MODELS:
			if ResourceLoader.exists("res://models/%s.glb" % nm):
				return nm
		return fallback   # protegit.glb yoksa data.gd'deki yedek model
	if id == "cubikon":
		for nm in CUBIKON_MODELS:
			if ResourceLoader.exists("res://models/%s.glb" % nm):
				return nm
		push_warning("Cubikon modeli bulunamadi (res://models/ icinde cubikon.glb ekle); yedek model kullaniliyor.")
	return fallback


# NPC dogumu. at: Vector3 (godot dunya konumu) verilirse o konumda dogar (yapilandirilmis
# "zones" dogusu); verilmezse eski rastgele davranis kullanilir. Donus: olusan dusman sozlugu.
func spawn_npc(id: String, at: Variant = null):
	# Uber NPC'ler YALNIZCA 4-5 haritasinda dogar; normal/PvP diger haritalara asla eklenmez.
	# Bu kural spawn sisteminde (gercek kodda) uygulanir, sadece gorsel degil.
	if str(id).begins_with("uber_") and cur != "4-5":
		return
	var d: Dictionary = DOData.NPCS[id]
	var m = maps[cur]
	var pos: Vector3
	if at is Vector3:
		pos = at
	else:
		pos = w2g(randf_range(1500, m.w - 1500), randf_range(1500, m.h - 1500))
		for i in 6:
			if base_pos != null and pos.distance_to(base_pos) < DOData.SAFE_RADIUS * DOData.S * 1.3:
				pos = w2g(randf_range(1500, m.w - 1500), randf_range(1500, m.h - 1500))
	var ship_tint := Color.WHITE
	if id == "pilot":
		ship_tint = ship_faction_tint((int(SV.get("faction", 0)) % 3) + 1)
	elif id == "protegit":
		ship_tint = Color(0.55, 1.0, 0.6)
	elif id == "cubikon":
		ship_tint = Color(0.85, 0.9, 1.0)
	# Boyut: make_ship modeli bu degere (en uzun kenar) normalize eder; ebeveyn/sahne olcegi etkilemez.
	# Protegit icin data.gd'deki deger ne olursa olsun PROTEGIT_MAX_SIZE'i asamaz (Cubikon sz=20).
	var ship_sz: float = float(d.sz)
	if id == "protegit":
		ship_sz = minf(ship_sz, PROTEGIT_MAX_SIZE)
	var o := make_ship(_npc_model(id, str(d.model)), ship_sz, ship_tint)
	o.position = pos
	world.add_child(o)
	var name_tag := tag(d.name, Vector3.ZERO, Color(1, 0.6, 0.5))
	name_tag.top_level = true
	name_tag.font_size = 32
	name_tag.outline_size = 7
	name_tag.outline_modulate = Color(0, 0, 0, 0.9)
	o.add_child(name_tag)
	enemies.append({"node": o, "id": id, "name": d.name, "hp": float(d.hp), "mx": float(d.hp), "sh": float(d.sh), "msh": float(d.sh),
		"v": Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(), "t": 0.0, "cd": 0.0, "aggro": false, "d": d})
	# Sağlık/kalkan barı: oyuncununkiyle aynı 3D (UNSHADED + BILLBOARD) bar; sadece hedefteyken görünür.
	var bw: float = BAR_W   # tum NPC barlari ekranda ayni boyutta
	var nbar := _make_bar3d(o, bw, ship_sz * 0.3)
	enemies[enemies.size() - 1]["hp_back"] = nbar.root
	enemies[enemies.size() - 1]["hp_fill"] = nbar.hp_fill
	enemies[enemies.size() - 1]["sh_fill"] = nbar.sh_fill
	enemies[enemies.size() - 1]["bar_w"] = bw
	enemies[enemies.size() - 1]["name_tag"] = name_tag
	enemies[enemies.size() - 1]["tag_dz"] = ship_sz * 0.3
	enemies[enemies.size() - 1]["bar_y"] = ship_sz * 0.3
	enemies[enemies.size() - 1]["home_pos"] = pos
	enemies[enemies.size() - 1]["zone"] = -1
	nbar.root.visible = false
	return enemies[enemies.size() - 1]


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	# Mobil arayuz acikken dunya girdisi (hareket / hedef / zoom) mobile_hud.gd tarafindan yonetilir.
	# Dokunma ayni anda sahte fare olayina da cevrildigi icin burada tekrar islenmez (cift tetikleme olmasin).
	if dohud != null and dohud.mobile_ui_on():
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			return
		var gmb := event as InputEventMouseButton
		if gmb != null and (gmb.button_index == MOUSE_BUTTON_LEFT or gmb.button_index == MOUSE_BUTTON_RIGHT):
			return
	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed:
		if base_menu.visible or gal_panel.visible:
			return
		_left_press(touch.position, false)
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if base_menu.visible or gal_panel.visible:
			return
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_left_press(mb.position, mb.double_click)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_stop_all()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = clampf(zoom - 0.08, 0.6, 1.8)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clampf(zoom + 0.08, 0.6, 1.8)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			holding = false
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		match k.keycode:
			KEY_SPACE, KEY_CTRL:
				if not base_menu.visible and not gal_panel.visible:
					_set_fire(not fire)
			KEY_ESCAPE:
				if dohud != null and dohud.close_popups():
					pass
				elif base_menu.visible:
					base_menu.visible = false
				elif gal_panel.visible:
					gal_panel.visible = false
				else:
					_stop_all()
			KEY_TAB:
				_select_next()
			KEY_B:
				toggle_base()
			KEY_M:
				toggle_galaxy()
			KEY_H:
				toggle_help()
			KEY_C:
				switch_cfg(1 - int(SV.cfgi))
			KEY_J:
				_try_jump()
			KEY_G:
				if dohud != null:
					dohud.toggle_group()
			KEY_1:
				dohud.quick_key(0)
			KEY_2:
				dohud.quick_key(1)
			KEY_3:
				dohud.quick_key(2)
			KEY_4:
				dohud.quick_key(3)
			KEY_5:
				dohud.quick_key(4)
			KEY_6:
				dohud.quick_key(5)
			KEY_7:
				dohud.quick_key(6)
			KEY_8:
				dohud.quick_key(7)
			KEY_9:
				dohud.quick_key(8)
			KEY_0:
				dohud.quick_key(9)
			KEY_R:
				toggle_rocket_auto()
			KEY_Q:
				dohud.toggle_quests()
			KEY_F:
				dohud.toggle_contacts()
			KEY_ENTER, KEY_KP_ENTER:
				dohud.focus_chat()
			KEY_F9:
				if bool(SV.get("free", false)):
					SV.cr += 1000000
					SV.uri += 200000
					toast("Test parası eklendi: +1.000.000 kredi, +200.000 uridium")
					save_game()
				else:
					toast("F9 yalnızca Ayarlar'da TEST MODU açıkken çalışır.")


func _ground_at(pos: Vector2):
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


func _clamp_map(v: Vector3) -> Vector3:
	var m = maps[cur]
	return Vector3(v.x, 0.0, v.z)   # Harita disi sinirsiz radyasyon alanidir; konum kisitlanmaz


const PICK_MIN_R := 3.5   # hedef secme icin asgari tiklama yaricapi (Godot birimi)


func _pick_enemy(hit: Vector3):
	var best = null
	var bd := 1e9
	for e in enemies:
		if not is_instance_valid(e.node) or float(e.hp) <= 0.0:
			continue
		# Kucuk gemiler (Protegit) de tiklanabilsin: tiklama yaricapi en az PICK_MIN_R.
		var r: float = maxf(float(e.node.get_meta("r", 3.0)) * 1.5, PICK_MIN_R)
		var d: float = e.node.position.distance_to(hit)
		if d < r and d < bd:
			bd = d
			best = e
	return best


func _left_press(pos: Vector2, dbl: bool) -> void:
	var hit = _ground_at(pos)
	if hit == null:
		return
	# Kilitliyken (ates acik + hedef canli) tiklama SADECE hareket ettirir:
	# hedef degismez, ates kapanmaz. Kilit; ates birakilinca (Ctrl/Bosluk/buton/sag tik/ESC)
	# ya da hedef olunce bozulur.
	if fire and target != null and target.hp > 0.0:
		_cancel_collect()
		dest = _clamp_map(hit)
		holding = true
		return
	var en = _pick_enemy(hit)
	if en == null and net_on and Net.gm != null:
		var fr = Net.gm.friendly_at(hit)
		if fr != null:
			# Ayni sirketten oyuncu: secilir (grup penceresinde gorunur, gruba davet edilebilir) ama HEDEF olmaz, ates edilemez.
			_cancel_collect()
			if dohud != null:
				dohud.select_friend(int(fr.peer))
			return
	if en == null:
		var cb = _pick_box(hit)
		if cb != null:
			# DarkOrbit gibi: kutuya TIKLA -> gemi kutuya gider -> toplama animasyonu -> ödül.
			if not is_same(cb, collect_box):
				_cancel_collect()
				collect_box = cb
				collect_t = 0.0
			dest = _clamp_map(cb.node.position)
			holding = false
			return
	if en != null:
		_cancel_collect()
		if not is_same(en, target):
			target = en
			if dbl:
				_set_fire(true)
		else:
			_set_fire(not fire)
		return
	_cancel_collect()
	dest = _clamp_map(hit)
	holding = true


func _pick_box(hit: Vector3):
	var best = null
	var bd := 2.4
	for b in boxes:
		if not is_instance_valid(b.node):
			continue
		var d: float = Vector2(b.node.position.x - hit.x, b.node.position.z - hit.z).length()
		if d < bd:
			bd = d
			best = b
	return best


# Toplama iptal: kutu olduğu yere geri döner.
func _cancel_collect() -> void:
	if collect_box != null and is_instance_valid(collect_box.node):
		if collect_t > 0.0 and collect_box.has("p0"):
			collect_box.node.position = collect_box.p0
		collect_box.node.scale = Vector3.ONE
		var cbd = collect_box.node.get_meta("body", null)
		if cbd != null:
			(cbd as Node3D).position.y = 0.9
	if collect_box != null:
		collect_box.erase("claim")
	collect_box = null
	collect_t = 0.0


func _set_fire(v: bool) -> void:
	if not running:
		return
	if v and target == null:
		toast("Once bir hedef sec (dusmana tikla / Tab)")
		return
	fire = v
	if not v:
		target = null


# Roket secimi: R tusu / roket slotu / ROKET butonu otomatik atisi acar-kapatir.
# Acikken, saldirirken (ates acik + hedef var) roket her soguma bitiminde kendiliginden atilir.
var rocket_auto := false


func toggle_rocket_auto() -> void:
	if not running or P == null:
		return
	rocket_auto = not rocket_auto
	if rocket_auto and int(SV.get("rockets", 0)) <= 0:
		rocket_auto = false
		toast("R-310 roketin kalmadı; Mağaza > Cephane'den al.")
		return
	toast("Roket otomatik atış: " + ("AÇIK" if rocket_auto else "KAPALI"))


func _auto_rocket_tick() -> void:
	if not rocket_auto or rocket_cd > 0.0 or P == null or not fire:
		return
	if target == null or not is_instance_valid(target.node):
		return
	fire_rocket(true)


func fire_rocket(silent: bool = false) -> void:
	if not running or P == null:
		return
	if target == null or not is_instance_valid(target.node):
		if not silent:
			toast("Önce bir düşman hedefle.")
		return
	if int(SV.get("rockets", 0)) <= 0:
		rocket_auto = false
		toast("R-310 roketin kalmadı; Mağaza > Cephane'den al.")
		return
	if rocket_cd > 0.0:
		if not silent:
			toast("Roket soğuma süresi: %.1f sn" % rocket_cd)
		return
	var distance: float = P.node.position.distance_to(target.node.position)
	if distance > DOData.LASER_RANGE * DOData.S:
		if not silent:
			toast("Hedef roket menzilinin dışında.")
		return
	SV.rockets -= 1
	rocket_cd = 5.0
	register_attack()   # roket atmak da korumayi kaldirir
	var damage := 400.0 * (1.0 + skill_bonus("rocket_dmg")) * randf_range(0.9, 1.1)
	var volume := {"left": 1, "sh": 0.0, "hull": 0.0, "sab": false, "flash": false, "pos": target.node.position}
	fire_bolt(P.node.position + Vector3(0.0, 0.6, 0.0), target, "rocket", Color(1.0, 0.53, 0.18), damage, volume)
	if int(SV.rockets) <= 0:
		rocket_auto = false
	if not silent or int(SV.rockets) <= 0:
		toast("R-310 fırlatıldı. Kalan: %d" % int(SV.rockets))
	save_game()


func _stop_all() -> void:
	_cancel_collect()
	dest = null
	holding = false
	fire = false
	target = null


func _select_next() -> void:
	if P == null:
		return
	var best = null
	var bd := 1e9
	for e in enemies:
		if is_same(e, target):
			continue
		var d: float = e.node.position.distance_to(P.node.position)
		if d < bd:
			bd = d
			best = e
	if best != null:
		target = best


func _try_jump() -> void:
	if jump_t >= 0.0 or clock < jump_wait_until:
		return
	for p in portals:
		if P.node.position.distance_to(p.pos) < DOData.PORTAL_RANGE * DOData.S:
			if not net_on:
				var why := SafeZone.jump_block_reason(maps[cur], clock, combat_until)
				if why != "":
					toast("Atlama engellendi: " + why)
					return
			jump_to = p
			jump_t = JUMP_TOTAL
			jump_arrive_t = -1.0
			if is_instance_valid(p.node) and p.node.has_method("burst"):
				p.node.burst(0.35)   # kapi uyanir
			toast("Atlama basladi: " + ("Solucan deligi" if str(p.to) == "random" else str(p.to)))
			return


# Tek oyunculu: atlayisi dogrudan uygular. Cok oyunculu: izni sunucu verir (Net.send_jump -> on_jump_result -> do_jump_to).
func do_jump(p: Dictionary) -> void:
	var dest_name := str(p.to)
	if dest_name == "random":
		# Solucan deligi: bulundugun harita disinda rastgele bir haritaya isinlar.
		var names: Array = maps.keys()
		names.erase(cur)
		dest_name = str(names[randi() % names.size()])
		toast("Solucan deligi seni %s haritasina isinladi!" % dest_name)
	do_jump_to(dest_name)


# ---- KAPI ATLAMA EFEKTLERI ----
# Geri sayim: kapi sarj olur (hizlanir, parlar), gemi kapinin merkezine cekilir ve kuculur, son anda ekran beyaza doner.
# Varis: yeni haritada ekran beyazdan acilir, gemi karsi kapidan kuculmus halde cikip normal boyuna doner.
func _update_jump_fx(dt: float) -> void:
	if P == null or not is_instance_valid(P.node):
		return
	var pn: Node3D = P.node
	var waiting: bool = clock < jump_wait_until
	if jump_t >= 0.0 and jump_to != null:
		var k: float = clampf(1.0 - jump_t / JUMP_TOTAL, 0.0, 1.0)
		var gp: Vector3 = jump_to.pos
		var gn = jump_to.get("node")
		if gn != null and is_instance_valid(gn) and gn.has_method("set_charge"):
			gn.set_charge(k)
		# kapiya dogru kuculen enerji halkalari (kapi gemiyi emiyor hissi)
		jump_ring_cd -= dt
		if jump_ring_cd <= 0.0:
			jump_ring_cd = lerpf(0.34, 0.12, k)
			_fx_ring(Vector3(gp.x, 0.25, gp.z), Color(0.5, 0.9, 1.0), 16.0, 3.0, 0.55, 0.4 + 0.4 * k)
		if jump_t < JUMP_PULL:
			var u: float = 1.0 - jump_t / JUMP_PULL
			dest = null
			holding = false
			spd_cur = 0.0
			var pull: float = 1.0 - exp(-dt * (2.5 + 10.0 * u))
			pn.position = pn.position.lerp(Vector3(gp.x, pn.position.y, gp.z), pull)
			var sk: float = clampf(jump_t / 0.5, 0.0, 1.0)
			pn.scale = Vector3.ONE * lerpf(0.12, 1.0, sk * sk * (3.0 - 2.0 * sk))
		jump_flash_a = maxf(jump_flash_a, 1.0 - clampf(jump_t / 0.4, 0.0, 1.0))
	elif jump_arrive_t >= 0.0:
		jump_arrive_t += dt
		var a: float = clampf(jump_arrive_t / 0.75, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - a, 3.0)
		pn.position = jump_arrive_from.lerp(jump_arrive_to, e)
		pn.scale = Vector3.ONE * lerpf(0.15, 1.0, e)
		jump_flash_a = maxf(0.0, 1.0 - jump_arrive_t / 0.9)
		if a >= 1.0:
			jump_arrive_t = -1.0
			pn.scale = Vector3.ONE
	elif not waiting:
		# iptal / reddedildi / normal durum: boyut ve flas yumusakca normale doner
		if pn.scale.x < 0.999:
			pn.scale = pn.scale.lerp(Vector3.ONE, minf(1.0, dt * 8.0))
			if pn.scale.x > 0.995:
				pn.scale = Vector3.ONE
		jump_flash_a = maxf(0.0, jump_flash_a - dt * 3.0)
	_jump_flash_apply()


func _jump_flash_apply() -> void:
	if dohud == null:
		return
	if jump_flash == null or not is_instance_valid(jump_flash):
		if jump_flash_a <= 0.001:
			return
		jump_flash = ColorRect.new()
		jump_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		jump_flash.z_index = 200
		jump_flash.color = Color(0.82, 0.96, 1.0, 0.0)
		dohud.add_child(jump_flash)
	var a: float = clampf(jump_flash_a, 0.0, 1.0)
	jump_flash.position = Vector2.ZERO
	jump_flash.size = get_viewport().get_visible_rect().size
	jump_flash.color = Color(0.82, 0.96, 1.0, a * a)
	jump_flash.visible = a > 0.003


# Yeni harita yuklendikten hemen sonra: karsi kapiyi patlat, gemiyi kapinin icinden baslat.
func _jump_arrive_fx(from_name: String) -> void:
	if P == null or not is_instance_valid(P.node):
		return
	var gpos: Vector3 = P.node.position
	for p in portals:
		if str(p.to) == from_name:
			gpos = p.pos
			if is_instance_valid(p.node) and p.node.has_method("burst"):
				p.node.burst(1.0)
			break
	jump_arrive_from = Vector3(gpos.x, P.node.position.y, gpos.z)
	jump_arrive_to = P.node.position
	jump_arrive_t = 0.0
	jump_flash_a = 1.0
	P.node.position = jump_arrive_from
	P.node.scale = Vector3.ONE * 0.15
	_fx_ring(Vector3(gpos.x, 0.3, gpos.z), Color(0.6, 0.95, 1.0), 3.0, 16.0, 0.7, 0.9)
	_fx_ring(Vector3(gpos.x, 0.3, gpos.z), Color(1.0, 1.0, 1.0), 1.5, 9.0, 0.5, 0.7)
	spark_burst(Vector3(gpos.x, 0.8, gpos.z), Color(0.6, 0.95, 1.0), 30, 16.0)


func do_jump_to(dest_name: String) -> void:
	jump_wait_until = -1.0
	if not maps.has(dest_name):
		return
	var from_name := cur
	jump_flash_a = 1.0   # ekran beyaza doner; yeni harita yuklenirken kesme gorunmez
	var tm = maps[dest_name]
	var arrive := w2g(tm.w / 2.0, tm.h / 2.0)
	var found := false
	for rp in tm.portals:
		if str(rp.to) == cur:
			var rpos := w2g(rp.x, rp.y)
			arrive = rpos + (w2g(tm.w / 2.0, tm.h / 2.0) - rpos).normalized() * 12.0
			found = true
			break
	if not found and tm.base != null:
		arrive = w2g(tm.base.x, tm.base.y) + Vector3(10, 0, 10)
	load_map(dest_name, arrive)
	_jump_arrive_fx(from_name)
	if not net_on:
		# Gecici gecis korumasi (dusman haritasi, ayarlanabilir; varsayilan 0 = kapali). Guvenli bolgeden AYRI yonetilir.
		var asec := SafeZone.arrival_seconds(tm, int(SV.faction))
		if asec > 0.0:
			arrive_until = clock + asec


# ---- GUVENLI BOLGE / CATISMA (kurallar: safe_zone.gd) ----
# Oyuncu saldirdi (lazer / roket, hedef NPC de olsa oyuncu da olsa): koruma DERHAL kalkar, kilit suresince geri gelmez.
func register_attack() -> void:
	last_attack = clock   # REP-4: saldiri yapilirken tamir durur
	repairing = false
	lock_until = SafeZone.lock_after_attack(clock)
	arrive_until = -1.0e9
	if net_on:
		net_prot = 0   # istemci yalnizca korumayi KAYBEDEBILIR; gercek durumu sunucu c_fire/c_hit ile dogrular
	if P != null:
		_update_protection(P.node.position)


func _update_protection(po: Vector3) -> void:
	var pr: int
	if net_on:
		pr = net_prot
	else:
		var zone := SafeZone.zone_kind(maps[cur], int(SV.faction), po, base_pos, portals)
		pr = SafeZone.protection(zone, lock_until, arrive_until, clock)
	if pr != prot_kind:
		if SafeZone.is_zone_protection(prot_kind) and not SafeZone.is_zone_protection(pr):
			safe_warn_t = 2.0   # guvenli bolge korumasi bitti: kisa, sabit (yanip sonmeyen) uyari
		elif SafeZone.is_zone_protection(pr):
			safe_warn_t = 0.0
		prot_kind = pr
	in_safe = prot_kind != SafeZone.NONE


# Kucuk, sade "hap" seklinde durum etiketi: yari saydam koyu zemin + ince renkli cerceve, kucuk punto.
func _make_safe_label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.07, 0.11, 0.62)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	l.add_theme_stylebox_override("normal", sb)
	l.visible = false
	dohud.add_child(l)
	return l


func _style_safe_label(l: Label, txt: String, col: Color, y: float, vs: Vector2) -> void:
	if l.text != txt:
		l.text = txt
		l.reset_size()
	l.add_theme_color_override("font_color", col)
	(l.get_theme_stylebox("normal") as StyleBoxFlat).border_color = Color(col.r, col.g, col.b, 0.55)
	l.position = Vector2(roundf(vs.x * 0.5 - l.size.x * 0.5), y)


# Ekranin ust-ortasinda yalnizca koruma GERCEKTEN aktifken kucuk etiket; gecici gecis korumasi farkli yazi/renkte.
func _update_safe_labels(dt: float) -> void:
	if dohud == null:
		return
	if lbl_safe == null or not is_instance_valid(lbl_safe):
		lbl_safe = _make_safe_label()
		lbl_safe_warn = _make_safe_label()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var txt := SafeZone.banner_text(prot_kind) if running else ""
	lbl_safe.visible = txt != ""
	if txt != "":
		var col := Color(0.55, 0.95, 0.72) if prot_kind != SafeZone.ARRIVAL else Color(0.6, 0.82, 1.0)
		_style_safe_label(lbl_safe, txt, col, 86.0, vs)
	safe_warn_t = maxf(0.0, safe_warn_t - dt)
	lbl_safe_warn.visible = running and safe_warn_t > 0.0 and txt == ""
	if lbl_safe_warn.visible:
		_style_safe_label(lbl_safe_warn, "GÜVENLİ BÖLGE KALKTI", Color(1.0, 0.72, 0.4), 86.0, vs)


func hit_entity(e: Dictionary, dmg: float) -> void:
	e["last_hit_t"] = clock
	var a := minf(e.sh, dmg * 0.8)
	e.sh -= a
	e.hp -= dmg - a
	if net_on:
		Net.gm.hit_enemy(e, dmg)


func _bolt_style(kind: String) -> Dictionary:
	if DOData.LASERS.has(kind):
		return DOData.LASERS[kind]
	if kind == "drone":
		return {"w": 0.07, "len": 1.1, "spd": 80.0}
	if kind == "rocket":
		return {"w": 0.38, "len": 3.4, "spd": 34.0}
	return {"w": 0.2, "len": 2.6, "spd": 62.0}


# ---------- DarkOrbit tarzı lazer sprite'ları ----------
# anahtar -> [dosya, genişlik_px, yükseklik_px, dünyadaki_uzunluk, (opsiyonel) ton]
# Oyuncu: seçili cephane (x1..x4, sab, rsb) hangi sprite'ı atacağını belirler. NPC: "n_<npc_id>".
const LASER_SPRITES := {
	# NOVAGATE'e ozgu, prosedurel uretilmis lazer sprite'lari (assets/lasers/nv_*.png; uretici: tools/gen_lasers.py)
	"x1": ["nv_x1", 156, 40, 4.4],       # ince kirmizi igne
	"x2": ["nv_x2", 156, 40, 4.4],       # mavi plazma
	"x3": ["nv_x3", 156, 40, 4.4],       # yesil cift cizgili enerji oku
	"x4": ["nv_x4", 156, 40, 4.5],       # beyaz-buz, kalin, nabizli
	"sab": ["nv_sab", 156, 40, 4.4],     # turkuaz dalga
	"rsb": ["nv_rsb", 156, 36, 4.6],     # altin simsek mizragi
	"n_streuner": ["nv_streuner", 132, 40, 3.6],
	"n_streuner_boss": ["nv_streuner", 132, 40, 4.4],
	"n_saimon": ["nv_streuner", 132, 40, 3.8],
	"n_mordon": ["nv_streuner", 132, 40, 4.0],
	"n_lordakia": ["nv_lordakia", 194, 74, 4.2],
	"n_lordakium": ["nv_lordakia", 194, 74, 6.0],
	"n_devolarium": ["nv_devolarium", 96, 96, 2.6],
	"n_sibelon": ["nv_sibelon", 96, 96, 3.0],
	"n_sibelonit": ["nv_sibelonit", 96, 96, 2.6],
	"n_kristallin": ["nv_protegit", 46, 14, 2.4],
	"n_boss_kristallin": ["nv_kristallin", 160, 32, 4.6],
	"n_protegit": ["nv_protegit", 46, 14, 2.2],
	"n_kristallon": ["nv_kristallon", 300, 48, 8.0],
	"n_boss_kristallon": ["nv_kristallon", 300, 48, 9.0],
	"n_cubikon": ["nv_cubikon", 300, 48, 8.0],
	"n_pilot": ["nv_x2", 156, 40, 4.4],
}
var laser_sprite_cache := {}


# Dönen: {"mesh","mat"} ya da sprite yoksa null (eski kutu lazere düşer).
# wf: mühimmat kalınlığı çarpanı (x1 ince, x4/rsb kalın); aynı kalınlık ayrı önbelleğe kaydedilir.
func _laser_sprite(key: String, wf := 1.0):
	if key == "" or not LASER_SPRITES.has(key):
		return null
	var ck := "%s|%s" % [key, snappedf(wf, 0.05)]
	if laser_sprite_cache.has(ck):
		return laser_sprite_cache[ck]
	var info: Array = LASER_SPRITES[key]
	var tex := _tex("res://assets/lasers/%s.png" % str(info[0]))
	if tex == null:
		laser_sprite_cache[ck] = null
		return null
	var ln: float = float(info[3])
	var wd: float = ln * float(info[2]) / float(info[1]) * wf
	var pm := PlaneMesh.new()
	pm.size = Vector2(ln, wd)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	if info.size() >= 5:
		var tint: Color = info[4]
		m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var res := {"mesh": pm, "mat": m}
	laser_sprite_cache[ck] = res
	return res


func _bolt_mesh(kind: String) -> BoxMesh:
	if bolt_meshes.has(kind):
		return bolt_meshes[kind]
	var st := _bolt_style(kind)
	var m := BoxMesh.new()
	m.size = Vector3(float(st.w), float(st.w), float(st.len))
	bolt_meshes[kind] = m
	return m


func _bolt_mat(col: Color, glow: bool) -> StandardMaterial3D:
	var key := "%s_%d" % [col.to_html(false), 1 if glow else 0]
	if bolt_mats.has(key):
		return bolt_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(col.r, col.g, col.b, 0.4)
	else:
		m.albedo_color = col
	bolt_mats[key] = m
	return m


func fire_bolt(from: Vector3, tgt, kind: String, col: Color, dmg: float, vol: Dictionary, sprite_key := "", wf := 1.0, off := Vector3.ZERO) -> void:
	if world == null:
		return
	var st := _bolt_style(kind)
	var b := MeshInstance3D.new()
	var spr = _laser_sprite(sprite_key, wf)
	if spr == null:
		b.mesh = _bolt_mesh(kind)
		b.material_override = _bolt_mat(col.lerp(Color(1, 1, 1), 0.55), false)
	world.add_child(b)
	b.position = from
	if spr != null:
		# Sprite lazer: görselin sivri ucu (solda) gidiş yönüne bakar.
		var sp := MeshInstance3D.new()
		sp.mesh = spr.mesh
		sp.material_override = spr.mat
		sp.rotation.y = -PI * 0.5
		sp.position.y = 0.3
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(sp)
	else:
		var glow := MeshInstance3D.new()
		glow.mesh = _bolt_mesh(kind)
		glow.material_override = _bolt_mat(col, true)
		glow.scale = Vector3(2.7, 2.7, 1.12)
		b.add_child(glow)
	if sprite_key == "sab":
		b.visible = false   # SAB: ekranda lazer cizgisi yok; sadece dusmandan gelen halkalar gorunur
	var tp: Vector3 = from
	var hr := 0.8
	if tgt != null:
		tp = tgt.node.position + off   # isine ozel bitis noktasi: isinlar yan yana isabet eder
		hr = maxf(float(tgt.node.get_meta("r", 3.0)) * 0.5, 0.9)   # kucuk gemilere de isabet
	elif P != null:
		tp = P.node.position
		hr = 1.6
	var dir := tp - from
	dir.y = 0.0
	if dir.length() > 0.01:
		b.look_at(from + dir.normalized(), Vector3.UP)
	# mermi, hedefin GERCEK konumunu takip eder (hedef kacarsa isabet noktasi guncellenir);
	# "off" sabit oldugu icin hedef hareket etse bile isinlar arasindaki yan mesafe korunur.
	bullets.append({"node": b, "tgt": tgt, "kind": kind, "col": col, "dmg": dmg, "vol": vol, "spd": float(st.spd),
		"t": 2.5, "last": tp, "hr": hr, "gen": map_gen, "off": off})


func _bolt_hit(b: Dictionary) -> void:
	if int(b.gen) != map_gen or P == null:
		return
	if bool((b.vol as Dictionary).get("vis", false)):
		impact(b.last, b.col, false, 0.5)   # baska oyuncunun/NPC'nin atisi: yalnizca gorsel
		return
	var pos: Vector3 = b.last
	var col: Color = b.col
	var vol: Dictionary = b.vol
	var am_id: String = str(vol.get("am", ""))
	if am_id == "sab":
		_sab_hit(b, pos, col, vol)
		return
	var e = b.tgt
	if e == null:
		# dusman mermisi bize ulasti
		if randf() < skill_bonus("evasion"):   # Evasive Maneuvers: isabet azalir
			popup_txt("ISKA", pos, Color(0.7, 0.85, 1.0))
			return
		impact(pos, Color(1.0, 0.4, 0.3), false, 1.0)   # kalkan varken ozel efekt/balon yok
		hurt(float(b.dmg))
		return
	if bool(vol.get("combine", false)):
		_combined_hit(b, pos, col, vol, e, am_id)
		return
	var is_rkt: bool = str(b.kind) == "rocket"
	if (am_id != "" or is_rkt) and randf() > hit_chance(is_rkt):
		# iska: Electro-Optics (lazer) / Heat Seeking (roket) isabeti artirir
		popup_txt("ISKA", pos, Color(0.78, 0.8, 0.85))
		vol.pos = pos
		vol.left -= 1
		if vol.left <= 0:
			_volley_text(vol)
		return
	var alive: bool = e.hp > 0.0 and is_instance_valid(e.node)
	if alive:
		var dmg: float = b.dmg
		var a := 0.0
		a = minf(e.sh, dmg * 0.8)
		e.sh -= a
		e.hp -= dmg - a
		vol.sh += a
		vol.hull += dmg - a
		if am_id != "":
			extras.leech(dmg - a)   # ENC: lazerle verilen govde hasarinin %10'u oyuncuya (roket sayilmaz)
		e.aggro = true
		e["last_hit_t"] = clock
		if net_on:
			Net.gm.hit_enemy(e, dmg)
		_ammo_impact(pos, col, am_id, a > 0.0)
		if a > 0.0 and not vol.flash:
			vol.flash = true
	else:
		_ammo_impact(pos, col, am_id, false)
		vol.pos = pos
	vol.left -= 1
	if vol.left <= 0:
		_volley_text(vol)


# Lazer salvosu: isinlar gorsel olarak ayri ucar ama hasar PARCA PARCA degil, salvonun TOPLAM hasari
# olarak tek seferde uygulanir (son isin ulasinca). Iska da salvo basina tek kez belirlenir.
func _combined_hit(b: Dictionary, pos: Vector3, col: Color, vol: Dictionary, e, am_id: String) -> void:
	if not vol.has("miss"):
		vol["miss"] = randf() > hit_chance(false)
	vol.pos = pos
	var alive: bool = e != null and e.hp > 0.0 and is_instance_valid(e.node)
	if alive and not bool(vol.miss):
		vol["landed"] = int(vol.get("landed", 0)) + 1
		_ammo_impact(pos, col, am_id, float(e.sh) > 1.0)
	else:
		_ammo_impact(pos, col, am_id, false)
	vol.left -= 1
	if vol.left > 0:
		return
	if bool(vol.miss):
		popup_txt("ISKA", pos, Color(0.78, 0.8, 0.85))
		return
	if not alive or int(vol.get("landed", 0)) <= 0:
		return
	var dmg: float = float(vol.total)
	var a: float = minf(float(e.sh), dmg * 0.8)
	e.sh -= a
	e.hp -= dmg - a
	vol.sh = a
	vol.hull = dmg - a
	extras.leech(dmg - a)   # ENC: govde hasarinin %10'u oyuncuya
	e.aggro = true
	e["last_hit_t"] = clock
	if net_on:
		Net.gm.hit_enemy(e, dmg)
	if a > 0.0 and not bool(vol.flash):
		vol.flash = true
	_volley_text(vol)


# Muhimmatin kendi isabet efekti: her cephane farkli boyut/ring/kivilcim davranisi gosterir.
const AMMO_HIT := {
	"x1": {"p": 0.7, "sp": 4},                          # kucuk, kisa isabet
	"x2": {"p": 0.9, "sp": 6},                          # biraz daha belirgin
	"x3": {"p": 1.1, "sp": 7, "ring": 1.8},             # sarj halkasi
	"x4": {"p": 1.5, "sp": 9, "ring": 2.2},             # belirgin patlama + halka
	"rsb": {"p": 2.2, "sp": 13, "ring": 2.8},           # guclu, buyuk, parlak
}


func _ammo_impact(pos: Vector3, col: Color, am_id: String, shield: bool) -> void:
	if world == null:
		return
	var st: Dictionary = AMMO_HIT.get(am_id, {"p": 1.0, "sp": 5})
	var p: float = float(st.p)
	var flash: Color = col.lerp(Color(1, 1, 1), 0.55)
	_fx_sphere(pos, flash, 0.45 * p, 1.9 * p, 0.15, 0.95)
	if shield:
		_fx_sphere(pos, Color(0.45, 0.8, 1.0), 0.9 * p, 3.2 * p, 0.28, 0.55)
	else:
		spark_burst(pos, col.lerp(Color(1.0, 0.6, 0.2), 0.4), int(float(st.sp) * p) + 1, 9.0 * p)
	if st.has("ring"):
		var q: float = float(st.ring)
		_fx_sphere(pos, col, q * 0.5, q * 2.1, 0.26, 0.5)


func _volley_text(vol: Dictionary) -> void:
	var pos: Vector3 = vol.pos
	if vol.sh > 0.0:
		popup_txt("-" + _n(vol.sh), pos, Color(0.5, 0.82, 1.0))
	if vol.hull > 0.0:
		popup_txt("-" + _n(vol.hull), pos, Color(1.0, 0.8, 0.35))


# SAB-50: isabet sadece hedefin kalkanini emer. Govde hasari YOK.
# Emilen enerji dusmandan oyuncuya kuculen mavi halkalar ile geri tasinir (LaserFX.sab_ring).
func _sab_hit(b: Dictionary, pos: Vector3, col: Color, vol: Dictionary) -> void:
	var e = b.tgt
	var alive: bool = e != null and e.hp > 0.0 and is_instance_valid(e.node)
	if not alive:
		vol.left -= 1
		if vol.left <= 0:
			_volley_text(vol)
		return
	var ab := 0.0
	if e.sh > 1.0 and not bool(e.get("player", false)):
		# hedefin kalkani var: kalkani em, bize ekle (maksimumu asma)
		ab = minf(e.sh, float(b.dmg))
		e.sh -= ab
		P.sh = minf(max_sh(), P.sh + ab)
		if net_on:
			Net.gm.hit_enemy(e, ab, 1)
		vol.sh += ab
		# emilim aninda kalkan uzerinde mavi dalgalanma
		_fx_sphere(pos, Color(0.45, 0.8, 1.0).lerp(col, 0.2), 0.5, 2.2, 0.2, 0.85)
	# Kalkan bitmis olsa bile SAB vurur (halka serisi gelir, ab = 0 -> sonuk tek halka),
	# ama emme olmaz ve govdeye (cana) HASAR VERMEZ.
	e.aggro = true
	e["last_hit_t"] = clock
	if not vol.flash:
		vol.flash = true
		LaserFX.sab_ring(self, e, ab)
	vol.left -= 1
	if vol.left <= 0:
		_volley_text(vol)


func _fx_sphere(pos: Vector3, col: Color, s0: float, s1: float, life: float, a0: float, follow = null) -> void:
	if world == null:
		return
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.albedo_color = Color(col.r, col.g, col.b, a0)
	var mi := MeshInstance3D.new()
	mi.mesh = fx_sphere
	mi.material_override = mt
	world.add_child(mi)
	mi.position = pos
	mi.scale = Vector3.ONE * s0
	fx2.append({"node": mi, "mat": mt, "t": 0.0, "life": life, "s0": s0, "s1": s1, "a0": a0, "vel": Vector3.ZERO, "follow": follow})


func spark_burst(pos: Vector3, col: Color, n: int, spd: float) -> void:
	if world == null or fx2.size() > 260:
		return
	for i in n:
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mt.albedo_color = col
		var sp := MeshInstance3D.new()
		sp.mesh = fx_spark
		sp.material_override = mt
		world.add_child(sp)
		sp.position = pos
		var ang := randf() * TAU
		var v := Vector3(cos(ang), randf_range(0.1, 0.6), sin(ang)) * spd * randf_range(0.5, 1.1)
		sp.look_at(pos + v, Vector3.UP)
		fx2.append({"node": sp, "mat": mt, "t": 0.0, "life": randf_range(0.25, 0.5), "s0": 1.0, "s1": 0.15, "a0": 1.0, "vel": v, "follow": null})


func impact(pos: Vector3, col: Color, shield: bool, power: float) -> void:
	if world == null:
		return
	_fx_sphere(pos, col.lerp(Color(1, 1, 1), 0.5), 0.5 * power, 1.8 * power, 0.16, 0.95)
	if shield:
		_fx_sphere(pos, Color(0.45, 0.8, 1.0), 0.9 * power, 3.2 * power, 0.28, 0.55)
	else:
		spark_burst(pos, col.lerp(Color(1.0, 0.6, 0.2), 0.4), int(5.0 * power) + 1, 9.0 * power)


func _update_fx2(dt: float) -> void:
	for i in range(fx2.size() - 1, -1, -1):
		var f = fx2[i]
		if not is_instance_valid(f.node):
			fx2.remove_at(i)
			continue
		f.t += dt
		var k: float = f.t / f.life
		if k >= 1.0:
			f.node.queue_free()
			fx2.remove_at(i)
			continue
		var fn: Node3D = f.node
		fn.scale = Vector3.ONE * lerpf(f.s0, f.s1, k)
		if f.vel != Vector3.ZERO:
			fn.position += f.vel * dt
			f.vel *= maxf(0.0, 1.0 - 2.5 * dt)
		if f.follow != null and is_instance_valid(f.follow):
			fn.position = f.follow.position
		var mt: StandardMaterial3D = f.mat
		mt.albedo_color.a = f.a0 * (1.0 - k)


func boom(pos: Vector3, s: float) -> void:
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(1.0, 0.65, 0.2, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	mi.material_override = mt
	mi.position = pos
	world.add_child(mi)
	fxs.append({"node": mi, "mat": mt, "t": 0.0, "s": s})
	_fx_sphere(pos, Color(1.0, 0.9, 0.6), s * 0.4, s * 2.4, 0.25, 0.9)
	spark_burst(pos, Color(1.0, 0.7, 0.3), 18, s * 3.5)


func animate_ship(o: Node3D, dt: float, ref_spd: float) -> void:
	if not is_instance_valid(o) or not o.has_meta("tilt") or dt <= 0.0:
		return
	var tilt: Node3D = o.get_meta("tilt")
	if not o.has_meta("prev_yaw"):
		o.set_meta("prev_yaw", o.rotation.y)
		o.set_meta("prev_pos", o.position)
		o.set_meta("prev_spd", 0.0)
		o.set_meta("phase", randf() * TAU)
	var yaw_rate: float = angle_difference(float(o.get_meta("prev_yaw")), o.rotation.y) / dt
	var spd: float = (o.position - (o.get_meta("prev_pos") as Vector3)).length() / dt
	var acc: float = (spd - float(o.get_meta("prev_spd"))) / dt
	o.set_meta("prev_yaw", o.rotation.y)
	o.set_meta("prev_pos", o.position)
	o.set_meta("prev_spd", spd)
	var sf: float = clampf(spd / maxf(ref_spd, 0.001), 0.0, 1.0)
	var ph: float = float(o.get_meta("phase"))
	var r: float = float(o.get_meta("r", 3.0))
	var bank: float = clampf(-yaw_rate * 0.10, -0.6, 0.6) * (0.35 + 0.65 * sf)
	bank += sin(clock * 1.3 + ph) * 0.035
	var pitch: float = -clampf(acc / maxf(ref_spd, 0.001) * 0.05, -0.12, 0.12) - sf * 0.04
	pitch += sin(clock * 0.9 + ph * 1.7) * 0.02
	var k: float = minf(1.0, dt * 6.0)
	tilt.rotation.z = lerpf(tilt.rotation.z, bank, k)
	tilt.rotation.x = lerpf(tilt.rotation.x, pitch, k)
	tilt.position.y = sin(clock * 1.6 + ph) * r * 0.05


func face(o: Node3D, d: Vector3, dt: float) -> void:
	if d.length_squared() < 0.0001:
		return
	o.rotation.y = lerp_angle(o.rotation.y, atan2(d.x, d.z), minf(1.0, dt * 6.0))


func popup_txt(text: String, pos: Vector3, col: Color) -> void:
	if world == null or pops.size() > 40:
		return
	var l := tag(text, pos + Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0)), col)
	l.font_size = 44
	l.outline_size = 12
	world.add_child(l)
	pops.append({"node": l, "t": 0.0})


func hurt(dmg: float, pierce_shield := false) -> void:
	if extras != null and extras.shield_active():
		extras.shield_absorb(dmg)   # 3 Saniyelik Koruma: hasar tamamen engellenir
		return
	if not net_on and in_safe:
		return   # tek oyunculu: koruma aktifken hasar yok (cok oyunculuda karari sunucu verir; s_hurt gelmisse gecerlidir)
	if not net_on and SafeZone.npc_damage_is_combat(maps[cur]):
		combat_until = clock + DOData.COMBAT_SEC   # catisma sayaci hasar almaktan AYRI tutulur; kapi kilidi bunu kullanir
	last_hit = clock   # REP-4: her hasar 10 sn'lik bekleme suresini bastan baslatir
	repairing = false
	var a := 0.0 if pierce_shield else minf(P.sh, dmg * absorb())
	P.sh -= a
	P.hp -= dmg - a
	popup_txt("-" + _n(dmg), P.node.position, Color(1.0, 0.4, 0.3) if a < dmg * 0.5 else Color(0.5, 0.8, 1.0))
	if P.hp <= 0.0:
		_die()


func _die() -> void:
	if net_on:
		Net.gm.report_death()
	extras.reset()
	repairing = false
	last_attack = -1.0e9
	boom(P.node.position, 8.0)
	toast("Gemin yok edildi! Ussa donuluyor...")
	lock_until = -1.0e9      # yeniden dogus yeni bir baslangic: kilit / catisma / gecici koruma sifirlanir
	arrive_until = -1.0e9
	combat_until = -1.0e9
	var f: Dictionary = DOData.FACTIONS[SV.faction]
	var hm = maps[f.home]
	P.hp = max_hp()
	P.sh = max_sh()
	reset_cfg_shields()
	load_map(f.home, w2g(hm.base.x, hm.base.y) + Vector3(10, 0, 10))


# Sunucu baglantisi koptu: kaydet ve ana menuye don.
func net_lost() -> void:
	running = false
	toast("Sunucu bağlantısı koptu! Menüye dönülüyor...")
	save_game()
	get_tree().create_timer(2.5).timeout.connect(func() -> void: get_tree().reload_current_scene())


func _respawn(gen: int, id: String, at: Variant = null) -> void:
	if gen == map_gen:
		spawn_npc(id, at)


# share_n: grup odulu paylasimi (NPC odulu, ayni haritadaki grup uyeleri arasinda esit bolunur; tamsayiya asagi yuvarlanir)
func give_reward(d: Dictionary, npc_id: String, share_n: int = 1) -> void:
	# Pilot Bio: Tactics (XP), Greed (kredi), Cruelty (seref), Tractor Beam I (tum NPC ganimeti)
	var loot := 1.0 + skill_bonus("loot_npc")
	var xp := int(round(float(d.xp) * (1.0 + skill_bonus("xp_npc"))))
	var cr := int(round(float(d.cr) * (1.0 + skill_bonus("cr_npc")) * loot))
	var uri := int(round(float(d.uri) * loot))
	var hon := float(d.hon) * (1.0 + skill_bonus("honor"))
	var sep := int(round(float(d.uri) * float(SkillTree.SEPROM_PER_URI) * loot))
	var gn: int = maxi(share_n, 1)
	if gn > 1:
		xp = xp / gn
		cr = cr / gn
		uri = uri / gn
		sep = sep / gn
		hon = hon / float(gn)
	award_xp(xp)
	SV.hon += hon
	SV.cr += cr
	SV.uri += uri
	SV.seprom = int(SV.get("seprom", 0)) + sep
	SV.kills += 1
	for quest in QUESTS:
		if str(quest.npc) == npc_id:
			var state: Dictionary = SV.quests.get(str(quest.id), {})
			state["progress"] = mini(int(state.get("progress", 0)) + 1, int(quest.target))
			SV.quests[str(quest.id)] = state
	toast("%s+%d XP  +%d Kredi  +%d Şeref  +%d Uridium  +%d Seprom" % ["[Grup 1/%d]  " % gn if gn > 1 else "", xp, cr, int(round(hon)), uri, sep])


func award_xp(amount: int) -> void:
	var before := DOData.level_of(float(SV.xp))
	SV.xp += amount
	var after := DOData.level_of(float(SV.xp))
	if after > before:
		toast("Seviye %d!" % after)

# Sunucu tarafindan hesaplanan odul: [cr, uri, xp, hon] zaten nihayi degerler
# Istemci sadece yetenek bonuslarini uygular.
func give_reward_cr_uri_xp_hon(cr: int, uri: int, xp: int, hon: int, npc_id: String = "") -> void:
	var loot := 1.0 + skill_bonus("loot_npc")
	xp = int(round(float(xp) * (1.0 + skill_bonus("xp_npc"))))
	cr = int(round(float(cr) * (1.0 + skill_bonus("cr_npc")) * loot))
	uri = int(round(float(uri) * loot))
	hon = float(hon) * (1.0 + skill_bonus("honor"))
	var sep := int(round(float(uri) * float(SkillTree.SEPROM_PER_URI) * loot))
	award_xp(xp)
	SV.hon += hon
	SV.cr += cr
	SV.uri += uri
	SV.seprom = int(SV.get("seprom", 0)) + sep
	SV.kills += 1
	# Quest ilerlemesi
	if npc_id != "":
		for quest in QUESTS:
			if str(quest.npc) == npc_id:
				var state: Dictionary = SV.quests.get(str(quest.id), {})
				state["progress"] = mini(int(state.get("progress", 0)) + 1, int(quest.target))
				SV.quests[str(quest.id)] = state
	toast("%s+%d XP  +%d Kredi  +%d Şeref  +%d Uridium  +%d Seprom" % ["", xp, cr, int(round(hon)), uri, sep])


# ------------------------------------------------------------------ SUNUCU DOGRULAMALI ODULLER
# Sunucu odulu DB'ye yazdiktan sonra kesin bakiyeleri (new_*) gonderir. Istemci
# bu degerleri AYNEN uygular; boylece ekranda gorunen ile kayitli veri aynidir.
func _apply_server_economy(st: Dictionary) -> void:
	if st.is_empty():
		return
	if st.has("new_cr"):
		SV.cr = int(st.new_cr)
	if st.has("new_uri"):
		SV.uri = int(st.new_uri)
	if st.has("new_xp"):
		SV.xp = float(st.new_xp)
	if st.has("new_hon"):
		SV.hon = float(st.new_hon)
	if st.has("new_sep"):
		SV.seprom = int(st.new_sep)
	if st.has("new_kills"):
		SV.kills = int(st.new_kills)
	if st.has("new_pvp_kills"):
		SV.pvp_kills = int(st.new_pvp_kills)


func apply_npc_reward(info: Dictionary) -> void:
	var npc_id: String = str(info.get("npc_id", ""))
	var cr: int = int(info.get("cr", 0))
	var uri: int = int(info.get("uri", 0))
	var xp: int = int(info.get("xp", 0))
	var hon: float = float(info.get("hon", 0.0))
	var sep: int = int(info.get("sep", 0))
	var before_level: int = DOData.level_of(float(SV.xp))
	var st: Dictionary = info.get("state", {})
	if not st.is_empty():
		_apply_server_economy(st)
	else:
		SV.cr += cr
		SV.uri += uri
		SV.xp += xp
		SV.hon += hon
		SV.seprom = int(SV.get("seprom", 0)) + sep
		SV.kills += 1
	var after_level: int = DOData.level_of(float(SV.xp))
	if after_level > before_level:
		toast("Seviye %d!" % after_level)
	# Quest ilerlemesi (odul miktarindan bagimsiz; NPC kimligi ile)
	if npc_id != "":
		for quest in QUESTS:
			if str(quest.npc) == npc_id:
				var state: Dictionary = SV.quests.get(str(quest.id), {})
				state["progress"] = mini(int(state.get("progress", 0)) + 1, int(quest.target))
				SV.quests[str(quest.id)] = state
	toast("+%d XP  +%d Kredi  +%d Şeref  +%d Uridium  +%d Seprom" % [xp, cr, int(round(hon)), uri, sep])


func apply_box_reward(id: int, info: Dictionary) -> void:
	var cr: int = int(info.get("reward_cr", info.get("cr", 0)))
	var uri: int = int(info.get("reward_uri", info.get("uri", 0)))
	var ammo: Dictionary = info.get("ammo", {}) if typeof(info.get("ammo", {})) == TYPE_DICTIONARY else {}
	var items: Dictionary = info.get("items", {}) if typeof(info.get("items", {})) == TYPE_DICTIONARY else {}
	var ptxt := ""
	var pcol := Color(1.0, 0.88, 0.4)
	if cr > 0:
		ptxt = "+%s Kredi" % _n(cr)
	elif uri > 0:
		ptxt = "+%s Uridium" % _n(uri)
		pcol = Color(0.84, 0.63, 1.0)
	elif ammo.has("x1"):
		ptxt = "+%s x1" % _n(int(ammo["x1"]))
		pcol = Color(0.75, 0.95, 1.0)
	# Sunucunun kesin bakiyelerini uygula
	_apply_server_economy(info)
	# Mermi / envanter odullerini istemciye yansit (DB'de zaten kalici)
	if not SV.has("ammo") or typeof(SV.ammo) != TYPE_DICTIONARY:
		SV.ammo = {}
	for aid in ammo.keys():
		SV.ammo[str(aid)] = int(SV.ammo.get(str(aid), 0)) + int(ammo[aid])
	if not SV.has("inv") or typeof(SV.inv) != TYPE_DICTIONARY:
		SV.inv = {}
	for iid in items.keys():
		SV.inv[str(iid)] = int(SV.inv.get(str(iid), 0)) + int(items[iid])
	# Efekt + bildirim (kutu konumu hala listede olabilir)
	var po: Vector3 = P.node.position if P != null else Vector3.ZERO
	var bp: Vector3 = po
	for b in boxes:
		if int(b.get("id", -1)) == id and is_instance_valid(b.node):
			bp = (b.node as Node3D).position
			break
	_box_collect_burst(Vector3(bp.x, po.y, bp.z))
	if ptxt != "":
		popup_txt(ptxt, po + Vector3(0.0, 1.5, 0.0), pcol)
	if cr > 0:
		toast("Bonus kutu: +%d Kredi" % cr)
	elif uri > 0:
		toast("Bonus kutu: +%d Uridium!" % uri)
	elif ammo.has("x1"):
		toast("Bonus kutu: +%d x1 cephane" % int(ammo["x1"]))


func apply_pvp_reward(_victim: int, info: Dictionary = {}) -> void:
	if not info.is_empty() and info.has("new_hon"):
		_apply_server_economy(info)
	else:
		SV.pvp_kills = int(SV.get("pvp_kills", 0)) + 1
		SV.hon = float(SV.get("hon", 0.0)) + 100.0 * (1.0 + skill_bonus("honor"))
	toast("Oyuncu yok edildi! +100 Honor")


# ---------- Gercek lazer cikis noktalari ----------
const SALVO_BEAMS := 2          # salvoda ayni anda gorunen azami isin sayisi (ortadaki isin yok)
const HP_MAX_BOLTS := 10        # DarkOrbit gibi: azami 10 lazer 10 ayrici isin
const RSB_COOLDOWN := 3.0       # RSB-75 yeniden atis beklemesi (sn) - KESINLIKLE 3 saniye
const AMMO_BOLT_W := {          # muhimmat demet kalinligi (x1 ince, x4/rsb kalin)
	"x1": 0.9, "x2": 1.0, "x3": 1.1, "x4": 1.3, "sab": 1.15, "rsb": 1.55,
}


func _ammo_col(id: String) -> Color:
	for a in DOData.AMMO:
		if a.id == id:
			return a.col
	return Color(1, 1, 1)


# Gemi modelinin gercek laserpoint node'larindan atis cikis noktalari uretir.
# Hedef yonune gore onem sirasi: burunun yakindaki (Front/center) noktalar.
# Donus sirasi simetrik: iki yandan dis->ic degiserek; boylece isinlar paralel ve dogal gorunur.
func _hp_origins(unit: Node3D, dir: Vector3) -> Array:
	var raw: Array = unit.get_meta("lpts", [])
	if raw.is_empty():
		return []
	var side := Vector3(dir.z, 0.0, -dir.x)
	var front: Array = []
	var allp: Array = []
	for hp in raw:
		if not is_instance_valid(hp):
			continue
		var rel: Vector3 = hp.global_position - unit.global_position
		var e := {"p": hp.global_position, "lat": rel.dot(side), "along": rel.dot(dir)}
		allp.append(e)
		var nm := str(hp.name)
		if nm.contains("Front") or nm.contains("center") or nm.contains("stand"):
			front.append(e)
	if front.size() < 2:
		front = allp
	if front.is_empty():
		return []
	front.sort_custom(func(a, b): return float(a.lat) < float(b.lat))
	var seq: Array = []
	var i0 := 0
	var i1 := front.size() - 1
	while i0 <= i1:
		if i0 < i1:
			seq.append(front[i0])
			seq.append(front[i1])
		else:
			seq.append(front[i0])
		i0 += 1
		i1 -= 1
	return seq


func player_volley(po: Vector3) -> void:
	var las: Array = cfg().las
	var n: int = las.size()
	if n == 0:
		if clock - last_nolaser > 4.0:
			last_nolaser = clock
			toast("Gemide lazer yok! [B] > Teçhizat'tan lazer tak (Mağaza'dan al).")
		return
	var id: String = SV.get("sel", "")
	if id == "rsb" and rsb_cd > 0.0:
		# RSB beklemesi sarken seciliyse bu salvo X1 ile gider; oyuncu istedigi an X4 gibi baska muhimmata gecebilir.
		id = "x1"
		if clock - last_nammo > 4.0:
			last_nammo = clock
			toast("RSB-75 hazirlaniyor (%ds), bu salvo X1 ile atiliyor." % int(ceil(rsb_cd)))
	if int(SV.ammo.get(id, 0)) < n:
		# Secilen muhimmat tam salvoya yetmiyorsa: DarkOrbit gibi stogu yeten en zayif muhimmata dus.
		var best = null
		for a in DOData.AMMO:
			if int(SV.ammo.get(str(a.id), 0)) >= n and (best == null or float(a.mult) < float(best.mult)):
				best = a
		if best == null:
			if clock - last_nammo > 4.0:
				last_nammo = clock
				toast("Cephane bitti! Mağazadan cephane al.")
			return
		if clock - last_nammo > 4.0:
			last_nammo = clock
			toast("%s cephanesi bitti, %s ile atiliyor." % [str(SV.get("sel", "")).to_upper(), str(best.name)])
		id = str(best.id)
	SV.ammo[id] -= n
	register_attack()   # guvenli bolgeden ates acmak korumayi derhal kaldirir (hedef NPC de olsa oyuncu da olsa)
	var total := 0.0
	for l in las:
		total += float(DOData.LASERS[l].dmg)
	total += drone_laser_dmg()
	total *= float(_ammo_mult(id)) * dmg_mult()
	total *= randf_range(0.88, 1.12)  # her salvoda hafif hasar değişimi (sabit vuruş yok)
	# Pilot Bio: oyunculara Bounty Hunter, NPC'lere Alien Hunter
	if target != null and bool(target.get("player", false)):
		total *= 1.0 + skill_bonus("laser_pvp")
	else:
		total *= 1.0 + skill_bonus("laser_npc")
	var vis: Array = las.duplicate()
	vis.sort_custom(func(x, y): return DOData.LASERS[x].dmg > DOData.LASERS[y].dmg)
	# DarkOrbit gibi: salvodaki her isin GEMININ KENDI lazer topundan cikar.
	# 1 lazer = 1 isin, 5 lazer = 5 isin, 10 lazer = 10 isin (sabit kodlu degil).
	# Salvodaki tum isinlar AYNI ANDA atilir (ayni frame'de); aralarinda bekleme YOK.
	# Salvo en fazla SALVO_BEAMS (2) isin olarak gorunur (en dis iki silah; ortadaki yok).
	# Hasar parca parca degil, TOPLAM olarak tek vurusta uygulanir (bkz. _combined_hit).
	var nb: int = mini(mini(n, HP_MAX_BOLTS), SALVO_BEAMS)
	var per: float = total / float(nb)
	var tgt = target
	var vol := {"left": nb, "sh": 0.0, "hull": 0.0, "am": id, "flash": false, "pos": tgt.node.position,
		"combine": id != "sab", "total": total, "landed": 0}
	var gen := map_gen
	# salvoda her isinin KENDI cikis + isabet noktasi (yan yana, cakismayan)
	var layout := _salvo_layout(tgt, nb)
	for j in nb:
		_spawn_player_bolt(j, vis[j % vis.size()], id, per, vol, tgt, gen, layout)
	tgt.aggro = true
	if net_on:
		Net.gm.fire_started(tgt, nb, id)
	if id == "rsb":
		rsb_cd = RSB_COOLDOWN
		# RSB otomatik donus: RSB atistiktan hemen sonra onceki secili muhimmata geri don.
		# Oyuncu bekleme sirasinda manuel secim yaparsa (select_ammo) rsb_prev guncellenir;
		# otomatik donus oyuncunun yeni secimini asla ezmez.
		var back := "x1"
		if rsb_prev != "" and rsb_prev != "rsb":
			back = rsb_prev
		SV.sel = back
		toast("RSB-75 atildi, otomatik %s secildi." % str(back).to_upper())


func _ammo_mult(id: String) -> float:
	for a in DOData.AMMO:
		if a.id == id:
			return float(a.mult)
	return 1.0


const VOLLEY_LAT := [-1.1, 1.1, -0.45, 0.45]     # laserpoint bulunamayan eski modeller icin yedek konumlar
const LASER_INTERVAL := DOData.PLAYER_FIRE_INTERVAL   # oyuncu salvo araligi (sn): ayar DOData.PLAYER_FIRE_INTERVAL (uyumluluk icin takma ad)
const HP_CONVERGE := 0.1                         # hedefteki yanal serpilme carpani (0 = tek noktada tam birlesir, 1 = paralel)
const HP_MIN_SPACING := 1.1                      # iki isinin isabet noktasi arasindaki asgari yanal mesafe


# Salvodaki her isin icin ayri cikis (gercek laserpoint) + ayri isabet ofseti uretir.
# Cakisan ofsetler kademeli serpilir; boylece isinlar yan yana ucusur, uzerlerine binmez.
func _salvo_layout(tgt, nb: int) -> Array:
	if P == null or tgt == null or not is_instance_valid(tgt.node):
		return []
	var po: Vector3 = P.node.position
	var dir: Vector3 = tgt.node.position - po
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	var hps: Array = _hp_origins(P.node, dir)
	var picks: Array = []
	for j in nb:
		var from_p: Vector3
		if hps.is_empty():
			from_p = po + dir * 3.0 + side * float(VOLLEY_LAT[j % VOLLEY_LAT.size()])
		else:
			from_p = hps[j % hps.size()]["p"]
			if j >= hps.size():
				# ayni lazerden ikinci atis: nokta hafif kaydirilir
				var sgn := 1.0 if ((j / hps.size()) % 2 == 1) else -1.0
				from_p += side * 0.5 * sgn
		picks.append(from_p)
	var placed: Array = []
	var out: Array = []
	for from_p in picks:
		var lat: float = (from_p - po).dot(side)
		var guard := 0
		while guard < 40:
			var conflict := false
			for p in placed:
				if absf(lat - float(p)) < HP_MIN_SPACING:
					conflict = true
					lat += HP_MIN_SPACING * (1.0 if lat >= float(p) else -1.0)
					lat = clampf(lat, -5.0, 5.0)
					break
			if not conflict:
				break
			guard += 1
		placed.append(lat)
		# Isinlar paralel gitmez: her silahtan cikip hedefin merkezinde (hafif serpilmeyle) BIRLESIR.
		out.append({"from": from_p, "off": side * lat * HP_CONVERGE})
	return out


func _volley_abort(vol: Dictionary) -> void:
	vol.left -= 1
	if vol.left <= 0:
		_volley_text(vol)


func _spawn_player_bolt(j: int, kind: String, ammo_id: String, dmg: float, vol: Dictionary, tgt, gen: int, layout: Array) -> void:
	if gen != map_gen or P == null or not running:
		return
	if tgt == null or tgt.hp <= 0.0 or not is_instance_valid(tgt.node):
		_volley_abort(vol)
		return
	var po: Vector3 = P.node.position
	# Cikis noktasi: geminin GERCEK lazer silahi (laserpoint node'unun dunya pozisyonu).
	# Isin end: hedefte salvoda hesaplanan KENDI ofseti (yan yana, mesafe korunarak).
	var from_p: Vector3
	var off := Vector3.ZERO
	if layout.size() > j:
		from_p = layout[j]["from"]
		off = layout[j]["off"]
	else:
		from_p = po + Vector3(0, 0.6, 0)
	var acol: Color = _ammo_col(ammo_id)
	var lcol: Color = DOData.LASERS[kind].col
	var col: Color = acol.lerp(lcol, 0.25)   # renk buyuk olcude muhimmatin
	var wf: float = float(AMMO_BOLT_W.get(ammo_id, 1.0))
	fire_bolt(from_p, tgt, kind, col, dmg, vol, ammo_id, wf, off)
	# kısa namlu flaşı: cikis noktasi gorunur ama rastgele degil (SAB'da yok)
	if ammo_id != "sab":
		_fx_sphere(from_p, acol.lerp(Color(1, 1, 1), 0.45), 0.28, 1.15, 0.11, 0.9)


func _npc_bolt(e: Dictionary, j: int, dmg: float, gen: int) -> void:
	if gen != map_gen or P == null or not running or in_safe or extras.untargetable():
		return
	if e.hp <= 0.0 or not is_instance_valid(e.node):
		return
	var en: Node3D = e.node
	var dir: Vector3 = P.node.position - en.position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	var from: Vector3
	var hps: Array = _hp_origins(en, dir)
	if hps.is_empty():
		from = en.position + dir * 1.5 + side * [-0.9, 0.9, 0.0][j % 3]
	else:
		from = hps[j % hps.size()]["p"]
	fire_bolt(from, null, "enemy", Color(1.0, 0.3, 0.35), dmg, {}, "n_" + str(e.get("id", "")))
	_fx_sphere(from, Color(1.0, 0.5, 0.4), 0.25, 1.1, 0.11, 0.9)


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	clock += dt
	if running:
		_update_jump_fx(dt)
		_update_game(dt)
	else:
		cam.look_at_from_position(Vector3(0, 80, 80), Vector3.ZERO, Vector3.UP)
	_update_bars3d()
	_update_bg()
	MapBg.apply_vision(self)
	for g in get_tree().get_nodes_in_group("engine_glow"):
		if is_instance_valid(g):
			g.scale = Vector3.ONE * (1.0 + 0.22 * sin(clock * 16.0 + float(g.get_instance_id() % 13)))
	_update_fx2(dt)
	for i in range(fxs.size() - 1, -1, -1):
		var f = fxs[i]
		f.t += dt
		f.node.scale = Vector3.ONE * (0.5 + f.t * f.s * 3.0)
		f.mat.albedo_color.a = maxf(0.0, 0.9 - f.t * 1.8)
		if f.t > 0.5:
			f.node.queue_free()
			fxs.remove_at(i)
	for i in range(pops.size() - 1, -1, -1):
		var pp = pops[i]
		if not is_instance_valid(pp.node):
			pops.remove_at(i)
			continue
		pp.t += dt
		var ln: Label3D = pp.node
		ln.position.y += dt * 4.0
		ln.modulate.a = clampf(1.2 - pp.t, 0.0, 1.0)
		if pp.t > 1.2:
			ln.queue_free()
			pops.remove_at(i)
	var tvs: Vector2 = get_viewport().get_visible_rect().size
	for i in range(toasts.size() - 1, -1, -1):
		var ts = toasts[i]
		ts.life -= dt
		var tl = ts.get("lbl")
		if ts.life <= 0.0:
			if tl != null and is_instance_valid(tl):
				tl.queue_free()
			toasts.remove_at(i)
			continue
		if tl == null or not is_instance_valid(tl):
			if dohud == null:
				continue
			tl = Label.new()
			tl.text = str(ts.t)
			tl.size = Vector2(700, 24)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tl.add_theme_font_size_override("font_size", 16)
			tl.add_theme_color_override("font_color", Color(1, 1, 1))
			tl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			tl.add_theme_constant_override("outline_size", 4)
			dohud.add_child(tl)
			ts["lbl"] = tl
		var age: float = float(ts.max) - float(ts.life)
		tl.position = Vector2(tvs.x * 0.5 - 350.0, 176.0 + float(ts.off) - age * 20.0)
		tl.modulate.a = clampf(float(ts.life) / 1.2, 0.0, 1.0)
	lbl_toast.text = ""


func _update_heading(dt: float, pn: Node3D, po: Vector3) -> void:
	# Burun yonu tek yerden belirlenir: kilitliyse hedef, degilse hareket yonu. Ikisi arasinda kalmaz.
	var want := pn.rotation.y
	var has_want := false
	if AIM_WHILE_MOVING and fire and target != null and target.hp > 0.0 and is_instance_valid(target.node):
		var d: Vector3 = target.node.position - po
		d.y = 0.0
		if d.length() > 0.5:
			want = atan2(d.x, d.z)
			has_want = true
	if not has_want and spd_cur > 0.05:
		want = move_yaw
		has_want = true
	if has_want:
		var diff := angle_difference(pn.rotation.y, want)
		var step := (AIM_TURN if fire else TURN_RATE * 1.4) * dt
		pn.rotation.y += clampf(diff, -step, step)


func _update_camera(dt: float, po: Vector3, max_spd: float, range_u: float) -> void:
	# 1) Odak noktasi: gemi + gittigi yone kucuk ileri bakis + hedef varsa hedefe dogru kayma
	var sf: float = clampf(spd_cur / maxf(max_spd, 0.001), 0.0, 1.0)
	var want: Vector3 = po + Vector3(sin(move_yaw), 0.0, cos(move_yaw)) * (CAM_LEAD * sf)
	if target != null and fire:
		var td: Vector3 = target.node.position - po
		td.y = 0.0
		want += td.limit_length(range_u) * CAM_FRAME
	if not cam_focus_ready:
		cam_focus = want
		cam_focus_ready = true
	else:
		cam_focus = cam_focus.lerp(want, 1.0 - exp(-CAM_FOLLOW * dt))
	# 2) Otomatik uzaklik: hizlanirken hafif uzaklasir, dururken yaklasir
	var auto_t: float = lerpf(CAM_AUTO_MIN, CAM_AUTO_MAX, sf)
	cam_auto = lerpf(cam_auto, auto_t, 1.0 - exp(-2.5 * dt))
	# 3) Tekerlek zoom'u anlik ziplamasin, yumusakca gelsin
	zoom_cur = lerpf(zoom_cur, zoom, 1.0 - exp(-9.0 * dt))
	# 4) Sabit aciyla konumlan
	var pitch: float = deg_to_rad(CAM_PITCH_DEG)
	var dist: float = CAM_DIST * zoom_cur * cam_auto
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * dist
	cam.look_at_from_position(cam_focus + offset, cam_focus, Vector3.UP)
	# 5) Dinamik FOV: yakinken dar, uzakken genis
	var fov_t: float = lerpf(CAM_FOV_NEAR, CAM_FOV_FAR, inverse_lerp(0.6, 1.8, zoom_cur))
	cam_fov_cur = lerpf(cam_fov_cur, fov_t, 1.0 - exp(-6.0 * dt))
	cam.fov = cam_fov_cur


func _calc_view_rect() -> void:
	var vs := get_viewport().get_visible_rect().size
	var pl := Plane(Vector3.UP, 0.0)
	var minv := Vector2(1e9, 1e9)
	var maxv := Vector2(-1e9, -1e9)
	for c in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(0, vs.y), vs]:
		var o := cam.project_ray_origin(c)
		var d := cam.project_ray_normal(c)
		var h = pl.intersects_ray(o, d)
		if h != null:
			minv.x = minf(minv.x, h.x)
			minv.y = minf(minv.y, h.z)
			maxv.x = maxf(maxv.x, h.x)
			maxv.y = maxf(maxv.y, h.z)
	if minv.x < 1e8:
		view_rect = Rect2(minv, maxv - minv)


func _update_game(dt: float) -> void:
	rocket_cd = maxf(0.0, rocket_cd - dt)
	rsb_cd = maxf(0.0, rsb_cd - dt)
	extras.tick(dt)
	_sync_shield()
	if net_on:
		Net.gm.step(dt)
	var pn: Node3D = P.node
	var po := pn.position
	var def := ship_def()
	var range_u: float = DOData.LASER_RANGE * DOData.S
	_update_protection(po)
	_update_safe_labels(dt)
	if target != null and target.hp <= 0.0:
		target = null
	if target == null:
		fire = false

	if holding:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not base_menu.visible and not gal_panel.visible:
			var hh = _ground_at(get_viewport().get_mouse_position())
			if hh != null:
				dest = _clamp_map(hh)
		else:
			holding = false

	var p_cd_prev: float = P.cd
	P.cd -= dt
	cfg_cool = maxf(0.0, cfg_cool - dt)
	var max_spd: float = ship_speed() * DOData.S * DOData.SPEEDMULT
	var tdist := 0.0
	if target != null:
		var td: Vector3 = target.node.position - po
		td.y = 0.0
		tdist = td.length()
	var goal = null
	if dest != null:
		goal = dest
	# Oto yaklasma kaldirildi: hedeften uzaklasinca gemi kendiliginden geri donmez (menzil disinda sadece ates durur).
	if goal != null:
		var gd: Vector3 = goal - po
		gd.y = 0.0
		var gl := gd.length()
		if dest != null and gl < ARRIVE_DIST:
			dest = null
			goal = null
		else:
			if spd_cur < 0.01:
				move_yaw = pn.rotation.y
			var diff := angle_difference(move_yaw, atan2(gd.x, gd.z))
			var step := TURN_RATE * dt
			move_yaw += clampf(diff, -step, step)
			var align := clampf(1.0 - absf(diff) / PI, 0.35, 1.0)
			var lim := minf(max_spd * align, gl * 6.0 + 1.0)
			var rate := ACCEL
			if lim < spd_cur:
				rate = BRAKE
			spd_cur = move_toward(spd_cur, lim, max_spd * rate * dt)
	if goal == null:
		spd_cur = move_toward(spd_cur, 0.0, max_spd * BRAKE * dt)
		if spd_cur < 0.01:
			move_yaw = pn.rotation.y
	if spd_cur > 0.001:
		pn.position += Vector3(sin(move_yaw), 0.0, cos(move_yaw)) * spd_cur * dt
	_radiation_tick(dt, pn.position)
	_update_heading(dt, pn, pn.position)
	po = pn.position

	# Oyuncu atisi: yalnizca zamanlayici belirler (PLAYER_FIRE_INTERVAL). Ucustaki onceki mermi atisi geciktirmez.
	if target != null and fire and P.cd <= 0.0 and tdist <= range_u:
		P.cd = DOData.rearm_cd(p_cd_prev, P.cd, dt, DOData.PLAYER_FIRE_INTERVAL)
		player_volley(po)
	_auto_rocket_tick()

	var mhp := max_hp()
	var rep_k := 1.0 + skill_bonus("repair")
	if prot_kind == SafeZone.BASE:   # hizli onarim yalnizca ust bolgesinde (kapi korumasi onarim vermez)
		repairing = false
		P.hp =minf(mhp, P.hp + mhp * 0.2 * rep_k * dt)
		P.sh = minf(max_sh(), P.sh + max_sh() * 0.2 * dt)
		var act_i := clampi(int(SV.get("cfgi", 0)), 0, cfg_shr.size() - 1)
		for k in cfg_shr.size():
			if k != act_i:
				cfg_shr[k] = minf(1.0, float(cfg_shr[k]) + 0.2 * dt)
	else:
		# REP-4: hasar almadan REP_DELAY sn gectiyse ve saldirmiyorsa HP REP_RATE/sn ile dolar (hareket engellemez).
		# Tek durum degiskeni (repairing) oldugu icin ayni gemide birden fazla tamir dongusu olusamaz.
		var idle: bool = clock - last_hit >= REP_DELAY and clock - last_attack >= REP_ATTACK_PAUSE
		if idle and P.hp > 0.0 and P.hp < mhp:
			repairing = true
			P.hp = minf(mhp, P.hp + REP_RATE * dt)
			if P.hp >= mhp:
				repairing = false   # maksimum HP'ye ulasinca tamir durur
		else:
			repairing = false
		if clock - last_hit > 5.0:
			P.sh = minf(max_sh(), P.sh + max_sh() * 0.01 * dt)

	var aggro_u: float = DOData.AGGRO_RANGE * DOData.S
	for e in (enemies if not net_on else []):   # cok oyunculuda NPC zekasi sunucuda
		var en: Node3D = e.node
		if en == null or not is_instance_valid(en):
			continue
		var d: Vector3 = po - en.position
		d.y = 0.0
		var L := d.length()
		var spd: float = e.d.spd * DOData.S * DOData.SPEEDMULT * 0.8
		if str(e.id) == "cubikon":
			_update_cubic(e, en, d, L, dt)   # SABIT: hareket etmez, dogrudan saldirmaz
			continue
		if e.has("guard_home"):
			_update_guard(e, en, d, L, dt)   # Cubikon korumasi: takip + yorunge donerek atis
			continue
		if not in_safe and not extras.untargetable() and ((e.d.aggr and L < aggro_u) or (e.aggro and L < aggro_u * 3.0)):
			e.aggro = true
			if L > range_u * 0.6:
				en.position += d.normalized() * spd * dt
			face(en, d, dt)
			var n_cd_prev: float = e.cd
			e.cd -= dt
			if L < range_u and e.cd <= 0.0:
				e.cd = DOData.rearm_cd(n_cd_prev, e.cd, dt, DOData.NPC_FIRE_INTERVAL)
				# TEK atis olayi: tek lazer gorseli + tek hasar (hasar mermi hedefe ulasinca bir kez uygulanir)
				_npc_bolt(e, 0, DOData.npc_shot_damage(e.d), map_gen)
		else:
			e.aggro = false
			e.t -= dt
			if e.t <= 0.0:
				e.t = randf_range(2, 5)
				e.v = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			en.position += e.v * spd * 0.3 * dt
			face(en, e.v, dt)
			var mm_ = maps[cur]
			if en.position.x < 0 or en.position.z < 0 or en.position.x > mm_.w * DOData.S or en.position.z > mm_.h * DOData.S:
				e.v = -e.v
	for i in range((enemies.size() - 1) if not net_on else -1, -1, -1):   # cok oyunculuda olumleri sunucu bildirir
		var e = enemies[i]
		if e.hp <= 0.0:
			var quiet: bool = bool(e.get("silent", false))   # leash/temizlik ile silinen: odul/patlama yok
			var dpos: Vector3 = e.node.position
			if not quiet:
				boom(dpos, e.node.get_meta("r", 3.0) * 1.6)
			e.node.queue_free()
			var bar_kill = e.get("hp_back")
			if bar_kill != null and is_instance_valid(bar_kill): bar_kill.queue_free()
			var sb_kill = e.get("sh_back")
			if sb_kill != null and is_instance_valid(sb_kill): sb_kill.queue_free()
			if not quiet:
				give_reward(e.d, str(e.id))
			enemies.remove_at(i)
			var gen := map_gen
			var id: String = e.id
			# Koruyucu Protegit'i Cubikon kendisi hizla yeniler (_update_cubic); rastgele yerde dogmaz.
			if not quiet and not e.has("guard_home"):
				var rat: Variant = null
				if id == "cubikon":
					rat = dpos   # Cubikon oldugu sabit noktada geri doner
				get_tree().create_timer(e.d.resp).timeout.connect(_respawn.bind(gen, id, rat))
			if not quiet:
				save_game()

	var arrived: Array = []
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		if not is_instance_valid(b.node):
			bullets.remove_at(i)
			continue
		var bn: Node3D = b.node
		var tpos: Vector3 = b.last
		if b.tgt != null:
			var te = b.tgt
			if te.hp > 0.0 and is_instance_valid(te.node):
				tpos = te.node.position + Vector3(b.get("off", Vector3.ZERO))
				b.last = tpos
		else:
			tpos = pn.position
			b.last = tpos
		var dv: Vector3 = tpos - bn.position
		dv.y = 0.0
		var dist := dv.length()
		var step: float = b.spd * dt
		b.t -= dt
		if dist <= step + float(b.hr) or b.t <= 0.0:
			arrived.append(b)
			bn.queue_free()
			bullets.remove_at(i)
		else:
			var mv := dv / dist
			bn.position += mv * step
			bn.look_at(bn.position + mv, Vector3.UP)
			# kisa enerji izi (trail): isinin arkasinda hizlica sonen kucuk parlayici toplar;
			# sayi esigi (fx2<=140) ve throttle (0.06 sn) ile efekt yigin degildir, FPS'ten bagimsizdir (dt tabanli).
			if fx2.size() <= 140:
				b["tr"] = float(b.get("tr", 0.0)) - dt
				if float(b["tr"]) <= 0.0:
					b["tr"] = 0.06
					var tcol: Color = Color(b.col)
					_fx_sphere(bn.position - mv * 2.0, Color(tcol.r, tcol.g, tcol.b, 1.0), 0.34, 0.05, 0.22, 0.35)
	for b in arrived:
		_bolt_hit(b)

	for bx in boxes:
		if is_instance_valid(bx.node) and not is_same(bx, collect_box):
			var bn: Node3D = bx.node
			bn.rotation.y += dt * 1.1
			var ph: float = float(bn.get_instance_id() % 17)
			var bd = bn.get_meta("body", null)
			if bd != null:
				(bd as Node3D).position.y = 0.9 + 0.14 * sin(clock * 2.0 + ph)   # havada hafif salinir
			var hmat = bn.get_meta("halo", null)
			if hmat != null:
				(hmat as StandardMaterial3D).albedo_color.a = 0.35 + 0.2 * sin(clock * 3.0 + ph)   # nabiz
	if collect_box != null and (not boxes.has(collect_box) or not is_instance_valid(collect_box.node)):
		collect_box = null
		collect_t = 0.0
	if collect_box != null:
		var cbn: Node3D = collect_box.node
		if collect_t <= 0.0:
			# Kutuya yaklaşıyor; toplanma menziline girince animasyon başlar. Otomatik toplama YOK.
			var dd: float = Vector2(cbn.position.x - po.x, cbn.position.z - po.z).length()
			if dd < 1.2:
				# Gemi kutunun tam ustunde: dur ve toplama animasyonunu baslat.
				collect_t = 0.001
				collect_box["p0"] = cbn.position
				dest = null
				holding = false
				_fx_ring(Vector3(cbn.position.x, 0.1, cbn.position.z), Color(0.4, 0.9, 1.0), 1.5, 6.0, 0.45, 0.8)
			else:
				dest = _clamp_map(cbn.position)
		else:
			var p0: Vector3 = collect_box.p0
			if Vector2(p0.x - po.x, p0.z - po.z).length() > 6.0:
				_cancel_collect()
			else:
				var prev_t: float = collect_t
				collect_t += dt
				var k: float = clampf(collect_t / BOX_COLLECT_TIME, 0.0, 1.0)
				# gemi kutunun uzerinde sabit kalir (yumusakca ortalanir)
				var kc: float = 1.0 - exp(-8.0 * dt)
				pn.position.x = lerpf(pn.position.x, p0.x, kc)
				pn.position.z = lerpf(pn.position.z, p0.z, kc)
				spd_cur = 0.0
				# kutu yerinde kalir: hizlanarak doner, gemiye dogru yukselir, parlar
				cbn.rotation.y += dt * (2.0 + 10.0 * k * k)
				var cbd = cbn.get_meta("body", null)
				if cbd != null:
					(cbd as Node3D).position.y = 0.9 + 1.0 * k * k
				var chm = cbn.get_meta("halo", null)
				if chm != null:
					(chm as StandardMaterial3D).albedo_color.a = 0.5 + 0.45 * k
				# yukari yukselen enerji halkalari (kutudan gemiye)
				if int(prev_t / 0.14) != int(collect_t / 0.14):
					_fx_ring(Vector3(p0.x, 0.2, p0.z), Color(0.4, 0.9, 1.0), 3.4, 1.4, 0.5, 0.55, Vector3(0, 3.2, 0))
				# kutuya dogru akan enerji parcaciklari
				if int(prev_t / 0.045) != int(collect_t / 0.045):
					var ang: float = randf() * TAU
					var rr: float = randf_range(1.6, 2.8)
					var off := Vector3(cos(ang) * rr, randf_range(0.1, 0.5), sin(ang) * rr)
					_fx_mote(Vector3(p0.x, 0.1, p0.z) + off, Color(0.5, 0.95, 1.0), randf_range(0.18, 0.32), 0.45, Vector3(-off.x * 2.2, 2.2 + 2.0 * k, -off.z * 2.2))
				if collect_t >= BOX_COLLECT_TIME:
					if net_on:
						# Cok oyunculu: kutuyu ilk alan kazanir; odul sunucu onayiyla (Net.gm.on_box_gone) verilir.
						if not collect_box.get("claim", false):
							collect_box["claim"] = true
							Net.send_box_take(int(collect_box.get("id", -1)))
						elif collect_t > 5.0:
							_cancel_collect()
					else:
						box_reward()

	var prompt := ""
	if jump_t >= 0.0:
		# J ile baslayan atlama IPTAL OLMAZ: gemi kapidan uzaklasmis olsa bile geri sayim biter,
		# son saniyelerde gemi kapinin merkezine cekilir (bkz. _update_jump_fx) ve atlama gerceklesir.
		jump_t -= dt
		prompt = "Atlama: %.1f" % maxf(0.0, jump_t)
		if jump_t <= 0.0:
			var jt = jump_to
			jump_t = -1.0
			if net_on:
				# Cok oyunculu: kapi izni (yakinlik + catisma kilidi) SUNUCUDA dogrulanir; onay gelince do_jump_to calisir.
				jump_wait_until = clock + 6.0
				Net.send_jump(str(jt.to))
			else:
				var why := SafeZone.jump_block_reason(maps[cur], clock, combat_until)
				if why != "":
					toast("Atlama engellendi: " + why)
				else:
					do_jump(jt)
			return
	else:
		for p in portals:
			if po.distance_to(p.pos) < DOData.PORTAL_RANGE * DOData.S:
				prompt = "[J] Solucan deliği: rastgele harita" if str(p.to) == "random" else "[J] %s haritasina atla" % p.to
	if in_safe and prompt == "":
		prompt = "GUVENLI BOLGE  -  [B] kontrol paneli"
	lbl_prompt.text = ""   # kapi / geri sayim / guvenli bolge yazilari artik gosterilmez (J ile atlama calismaya devam eder)

	animate_ship(pn, dt, max_spd)
	for e in enemies:
		animate_ship(e.node, dt, float(e.d.spd) * DOData.S * DOData.SPEEDMULT * 0.8)

	_update_camera(dt, po, max_spd, range_u)
	_calc_view_rect()

	_update_drones(dt)

	# Hedef halkasi: hedef NPC'nin tam merkezinde, tum NPC'lerde ayni sabit boyutta.
	if target != null and target.hp > 0.0 and is_instance_valid(target.node):
		var tgp: Vector3 = (target.node as Node3D).global_position
		target_ring.visible = true
		target_ring.global_position = Vector3(tgp.x, -0.3, tgp.z)
		target_ring.scale = RING_SCALE
		ring_mat.albedo_color = Color(1.0, 0.22, 0.12, 0.85) if fire else Color(1.0, 0.55, 0.18, 0.7)
	else:
		target_ring.visible = false
	# Hedef noktası dairesi kaldırıldı (DarkOrbit'te yok).
	dest_mark.visible = false

	_update_hud(def, mhp, po)
	# NPC/oyuncu 3D barları _process -> _update_bars3d() içinde güncellenir.
	save_t += dt
	if save_t > 15.0:
		save_t = 0.0
		save_game()


const DRONE_COLLAPSE := 0.4   # donerken dizilim gemiye dogru en fazla bu kadar kapanir (0.4 = %40 kuculur)
const DRONE_RATE_DEAD := 1.2  # bu donus hizinin (rad/sn) altinda hic kapanmaz (kucuk duzeltmeler etkilemez)
const DRONE_RATE_REF := 4.0   # bu donus hizinda tam kapanir
const DRONE_CLOSE := 4.0      # kapanma hizi (yuksek = aninda toplanir)
const DRONE_REOPEN := 2.5     # tekrar acilma hizi (dusuk = yavas ve gorunur sekilde acilir)
var drone_open := 1.0         # 1.0 = dizilim tam acik
var drone_prev_yaw := 0.0
var drone_prev_ok := false
var drone_rate_s := 0.0       # yumusatilmis donus hizi
const DRONE_FOLLOW := 10.0     # droidlerin gemiyi takip hizi (dusuk = daha cok gecikme/sallanma)
const DRONE_TURN := 6.0       # droid burun yonunun gemiye yetisme hizi
const DRONE_MAX_LAG := 0.7    # takip gecikmesinin en fazla uzakligi (dunya birimi)
const DRONE_MODEL_SIZE := 2.1   # 3D droid modelinin en uzun kenari (dunya birimi)
var _drone_model_cache: Dictionary = {}


func _drone_scene(id: String) -> PackedScene:
	if id == "":
		return null
	if _drone_model_cache.has(id):
		return _drone_model_cache[id]
	var path := "res://models/drone_%s_6.glb" % id
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_drone_model_cache[id] = ps
	return ps


# Gercek 3D droid modeli (flax / iris). Model yoksa eski procedural droid kullanilir.
func _make_drone_model(ps: PackedScene, tint: Color, glow: Color, glow_e: float, metal: float) -> Node3D:
	var root := Node3D.new()
	var model: Node3D = ps.instantiate() as Node3D
	if model == null:
		return root
	var bb := AABB()
	var have := false
	var nodes: Array = [model]
	nodes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	# Parlak gumus govde (uzayda koyu metal siyaha doner, bu yuzden metalik dusuk + hafif kendi isigi)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = metal
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = glow_e
	for item in nodes:
		var mi := item as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = Transform3D.IDENTITY if mi == model else _rel_xf(mi, model)
		var b: AABB = xf * mi.get_aabb()
		bb = b if not have else bb.merge(b)
		have = true
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)
	if have:
		var sz := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		var k := DRONE_MODEL_SIZE / maxf(sz, 0.001)
		model.scale = Vector3.ONE * k
		model.position = -bb.get_center() * k
	# modeller burnu -Z'ye bakacak sekilde cikiyor; gemi +Z'ye bakar -> 180 derece cevir
	var flip := Node3D.new()
	flip.rotation.y = PI
	root.add_child(flip)
	flip.add_child(model)
	return root


func _make_drone(col: Color, id := "") -> Node3D:
	var ps := _drone_scene(id)
	if ps != null:
		# flax: acik gumus (tahmin). iris: GERCEK referansa gore koyu kursun gri govde + kirmizi vurgu
		if id == "iris":
			return _make_drone_model(ps, Color(0.30, 0.31, 0.35), Color(0.85, 0.10, 0.06), 0.20, 0.35)
		return _make_drone_model(ps, Color(0.80, 0.84, 0.90), Color(0.80, 0.84, 0.90), 0.22, 0.12)
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.72
	cm.height = 0.26
	cm.radial_segments = 6
	cm.rings = 1
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.55, 0.6, 0.7)
	bm.metallic = 0.8
	bm.roughness = 0.35
	body.material_override = bm
	root.add_child(body)
	var core := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.3
	sp.height = 0.6
	core.mesh = sp
	core.material_override = _glow_mat(col)
	core.position = Vector3(0, 0.2, 0)
	root.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = fx_sphere
	halo.material_override = _bolt_mat(col, true)
	halo.scale = Vector3.ONE * 1.5
	halo.position = Vector3(0, 0.2, 0)
	root.add_child(halo)
	return root


const DroneForms = preload("res://drone_forms.gd")


# Droid dizilimi ofsetleri (gemi yerel uzayi, ileri = +Z). Olcek: standart dizilimin yaricapi.
const DRONE_MIN_GAP := 3.0     # iki droid arasi asgari mesafe (dunya birimi) - ic ice girmesin
const DRONE_SPREAD := 1.15     # tum dizilim gemiden bu oranda uzaklasir (1.0 = eski konum)
const DRONE_MIN_SHIP := 3.4    # droidin gemiye asgari uzakligi


func form_offsets_for(code: String, n: int) -> Array:
	# Formasyonun sekli korunur; yalnizca birbirine/gemiye cok yakin droidler yerel olarak itilir.
	var raw: Array = _form_offsets_raw(code, n)
	var pts: Array = []
	var y0 := 0.0
	for v in raw:
		var v3: Vector3 = v
		y0 = v3.y
		pts.append(Vector2(v3.x, v3.z))
	for it in 40:
		var moved := false
		for a in pts.size():
			var pa: Vector2 = pts[a]
			var ds := pa.length()
			if ds < DRONE_MIN_SHIP:
				var dir := pa / ds if ds > 0.001 else Vector2.RIGHT.rotated(float(a) * 2.399)
				pts[a] = dir * DRONE_MIN_SHIP
				moved = true
			for b in range(a + 1, pts.size()):
				var pb: Vector2 = pts[b]
				var diff: Vector2 = pts[a] - pb
				var d := diff.length()
				if d < DRONE_MIN_GAP:
					var dir2 := diff / d if d > 0.001 else Vector2.RIGHT.rotated(float(a + b) * 2.399)
					var push := (DRONE_MIN_GAP - d) * 0.5 + 0.01
					pts[a] = (pts[a] as Vector2) + dir2 * push
					pts[b] = pb - dir2 * push
					moved = true
		if not moved:
			break
	var out: Array = []
	for p in pts:
		var p2: Vector2 = (p as Vector2) * DRONE_SPREAD
		out.append(Vector3(p2.x, y0, p2.y))
	return out


func _form_offsets_raw(code: String, n: int) -> Array:
	var key: String = DroneForms.key_for(code, DOData.FORMS.get(code, {}))
	if key == "":
		return DOData.form_offsets(code, n)
	var base: Array = DOData.form_offsets("std", maxi(n, 1))
	var rad := 0.0
	var y0 := 0.0
	for v in base:
		var v3: Vector3 = v
		rad = maxf(rad, Vector2(v3.x, v3.z).length())
		y0 = v3.y
	if rad < 0.5:
		rad = 3.0 * DOData.S
	var out: Array = []
	for p in DroneForms.points(key, n):
		var p2: Vector2 = p
		out.append(Vector3(p2.x * rad, y0, p2.y * rad))
	return out



func _update_drones(dt: float) -> void:
	if P == null:
		return
	var c := cfg()
	var sig := "%d|%s|%s" % [P.node.get_instance_id(), str(c.form), ",".join(PackedStringArray(c.drn))]
	if sig != drone_sig:
		drone_sig = sig
		for d in drone_nodes:
			if is_instance_valid(d.node):
				d.node.queue_free()
		drone_nodes.clear()
		var offs: Array = form_offsets_for(str(c.form), c.drn.size())
		for i in c.drn.size():
			var dd: Dictionary = DOData.DRONES[c.drn[i]]
			var dn := _make_drone(dd.col, str(c.drn[i]))
			P.node.add_child(dn)
			dn.position = offs[i]
			drone_nodes.append({"node": dn, "off": offs[i], "ph": randf() * TAU, "col": dd.col, "id": c.drn[i], "spin": _drone_scene(str(c.drn[i])) == null})
	# Droidler dunya uzayinda gemiyi yumusakca takip eder: gemi donunce / hizlanince dizilim
	# gecikmeli sallanir, acilip kapanir (DarkOrbit'teki gibi); sabit bir halka gibi durmaz.
	var pn: Node3D = P.node
	var gt: Transform3D = pn.global_transform
	var ship_yaw: float = pn.global_rotation.y
	if not drone_prev_ok:
		drone_prev_yaw = ship_yaw
		drone_prev_ok = true
	var turn_rate := absf(angle_difference(drone_prev_yaw, ship_yaw)) / maxf(dt, 0.0001)
	drone_prev_yaw = ship_yaw
	drone_rate_s = lerpf(drone_rate_s, turn_rate, 1.0 - exp(-10.0 * dt))
	var amt := clampf((drone_rate_s - DRONE_RATE_DEAD) / (DRONE_RATE_REF - DRONE_RATE_DEAD), 0.0, 1.0)
	var want_open := 1.0 - amt * DRONE_COLLAPSE
	var k_open := DRONE_CLOSE if want_open < drone_open else DRONE_REOPEN
	drone_open = lerpf(drone_open, want_open, 1.0 - exp(-k_open * dt))
	var k_pos := 1.0 - exp(-DRONE_FOLLOW * dt)
	var k_rot := 1.0 - exp(-DRONE_TURN * dt)
	for d in drone_nodes:
		if not is_instance_valid(d.node):
			continue
		var nd: Node3D = d.node
		var local: Vector3 = Vector3(d.off.x * drone_open, d.off.y + 0.3 * sin(clock * 2.2 + d.ph), d.off.z * drone_open)
		var target: Vector3 = gt * local
		if not d.has("wp"):
			d["wp"] = target
			d["yaw"] = ship_yaw
		var wp: Vector3 = d["wp"]
		wp = wp.lerp(target, k_pos)
		var lag: Vector3 = wp - target
		if lag.length() > DRONE_MAX_LAG:
			wp = target + lag.normalized() * DRONE_MAX_LAG
		d["wp"] = wp
		d["yaw"] = lerp_angle(float(d["yaw"]), ship_yaw, k_rot)
		nd.global_position = wp
		if d.get("spin", true):
			nd.rotation.y += dt * 2.0   # sadece eski procedural droid doner
		else:
			nd.global_rotation = Vector3(0.0, float(d["yaw"]), 0.0)


func _update_hud(def: Dictionary, mhp: float, po: Vector3) -> void:
	dohud.refresh(def, mhp, po)


func run_damage_tests() -> void:
	print("===== HASAR TESTLERİ =====")
	
	# Tek Lazer Testleri
	print("\nTek Lazer Testleri:")
	for lid in DOData.LASER_ORDER:
		var ld: Dictionary = DOData.LASERS[lid]
		for a in DOData.AMMO:
			var dmg: float = float(ld.dmg) * float(a.mult) * dmg_mult()
			print("%s x %s: %.1f" % [ld.name, a.name, dmg])
	
	# Çoklu Lazer Testleri
	print("\nÇoklu Lazer Testleri:")
	for lid in DOData.LASER_ORDER:
		var ld: Dictionary = DOData.LASERS[lid]
		var a: Dictionary = DOData.AMMO[0]  # x1
		for n in range(1, 11):
			var dmg: float = float(ld.dmg) * float(n) * float(a.mult) * dmg_mult()
			print("%s x %d lazer: %.1f" % [ld.name, n, dmg])
	
	# Droid Testleri
	print("\nDroid Testleri (lf4 + x1):")
	var ld: Dictionary = DOData.LASERS["lf4"]
	var a: Dictionary = DOData.AMMO[0]  # x1
	for n in range(0, 11):
		var drone_dmg_bonus: float = 0.0
		if n > 0:
			drone_dmg_bonus = float(DOData.DRONES["flax"].dmg) * float(n)
		var dmg: float = float(ld.dmg) * float(a.mult) * (1.0 + drone_dmg_bonus)
		print("LF-4 + X1 + %d droid: %.1f" % [n, dmg])	
	print("===== TEST BİTTİ =====")


# Droidleri otomatik donatir: once en guclu bosta lazerler, lazer kalmazsa en guclu bosta kalkan jeneratoru.
# Envanter DUSURULMEZ; esyalar sadece "kullanimda" sayilir.
func _on_auto_equip_drones() -> void:
	var c := cfg()
	var de := _cfg_drone_equip(c)
	for i in c.drn.size():
		var did := str(c.drn[i])
		var uid := "%s_%d" % [did, i]
		for s in int(DOData.DRONES[did].slots):
			if (de.get(uid, {}) as Dictionary).has("slot_%d" % s):
				continue
			var best := ""
			var best_v := -1.0
			for lid in DOData.LASER_ORDER:
				if _free_count(c, "las", str(lid)) > 0 and float(DOData.LASERS[lid].dmg) > best_v:
					best = str(lid)
					best_v = float(DOData.LASERS[lid].dmg)
			if best == "":
				for gid in DOData.GEN_ORDER:
					if str(DOData.GENS[gid].type) == "sh" and _free_count(c, "gen", str(gid)) > 0 and float(DOData.GENS[gid].val) > best_v:
						best = str(gid)
						best_v = float(DOData.GENS[gid].val)
			if best != "":
				equip_drone_item(uid, s, best)
	_update_drones(0.0)
	toast("Droidler otomatik olarak donatıldı.")
