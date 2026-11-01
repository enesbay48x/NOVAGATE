# Harita arka planlari: 29 uzay gorseli, haritalara rastgele (ama sabit) dagitilmistir.
#   - Gorsel yalnizca harita siniri ICINDE gorunur; disi (radyasyon alani) karanliktir ve hafif kirmizi uyari tonu alir.
#   - Ust ve kapi cevreleri biraz kisilir, gemi / yazilar okunakli kalir.
#   - Gorsel ekranda piksel piksel gosterilir (zemine gerilmez, bulaniklasmaz) ve haritadaki konuma gore cok hafif kayar.
#   - Ayni anda yalnizca icinde bulunulan haritanin gorseli bellekte tutulur (telefon icin).
# Haritaya hangi gorselin geldigini degistirmek icin asagidaki MAP_BG sozlugunu duzenle (1..29).
extends RefCounted

const BG_DIR := "res://assets/backgrounds/bg_%02d.jpg"
const BG_COUNT := 29
const DIM_MAX := 12
const DIM_PORTAL_R := 14.0      # kapi cevresinde kisilan yaricap (Godot birimi)
const DIM_PORTAL_K := 0.55      # kisma gucu (0 = yok, 1 = tam karanlik)
const DIM_BASE_R := 22.0        # ust cevresi
const DIM_BASE_K := 0.50
const EDGE_SOFT := 10.0         # sinira yaklasirken goruntunun karardigi mesafe (Godot birimi)
const OVERSCAN := 1.12          # gorsel ekrandan bu kadar buyuk cizilir (kayma payi)
const VISION_MUL := 4.0         # SABIT gorus menzili = lazer menzili x bu. Zoom bunu degistirmez. Radar / minimap de bunu kullanir.

const MAP_BG := {
	"1-1": 18, "1-2": 16, "1-3": 12, "1-4": 7, "1-5": 26, "1-6": 27,
	"1-7": 14, "1-8": 6, "2-1": 1, "2-2": 10, "2-3": 28, "2-4": 22,
	"2-5": 15, "2-6": 19, "2-7": 20, "2-8": 17, "3-1": 5, "3-2": 11,
	"3-3": 9, "3-4": 8, "3-5": 21, "3-6": 29, "3-7": 25, "3-8": 23,
	"4-1": 2, "4-2": 13, "4-3": 4, "4-4": 3, "4-5": 24,
}

const SHADER := """
shader_type canvas_item;
uniform vec2 cam = vec2(0.0);
uniform vec2 vp = vec2(1280.0, 720.0);
uniform float stars_on = 1.0;
uniform float bg_on = 0.0;
uniform sampler2D bg_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 bg_size = vec2(2560.0, 1440.0);
uniform vec2 map_wh = vec2(840.0, 524.0);
uniform vec2 focus_n = vec2(0.5, 0.5);
uniform vec3 cam_pos = vec3(0.0, 40.0, 20.0);
uniform vec3 ray_tl = vec3(0.0, -1.0, 0.0);
uniform vec3 ray_dx = vec3(0.0, 0.0, 0.0);
uniform vec3 ray_dy = vec3(0.0, 0.0, 0.0);
uniform float edge_soft = 10.0;
uniform float overscan = 1.12;
uniform vec4 dim_pts[12];

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
	vec3 base = vec3(0.008, 0.01, 0.02);
	vec3 col = base;
	float inside = 1.0;
	if (bg_on > 0.5) {
		// Bu pikselin altindaki zemin noktasi (dunya koordinati)
		vec3 d = ray_tl + ray_dx * UV.x + ray_dy * UV.y;
		float t = -cam_pos.y / min(d.y, -0.0001);
		vec2 wp = cam_pos.xz + d.xz * t;
		float din = min(min(wp.x, map_wh.x - wp.x), min(wp.y, map_wh.y - wp.y));
		inside = smoothstep(0.0, edge_soft, din);
		// Gorsel: ekrani kaplar, haritadaki konuma gore cok hafif kayar
		vec2 sc = vp / bg_size;
		float s = max(sc.x, sc.y) * overscan;
		vec2 img_px = bg_size * s;
		vec2 slack = img_px - vp;
		vec2 off = -slack * clamp(focus_n, 0.0, 1.0);
		vec3 img = texture(bg_tex, (px - off) / img_px).rgb;
		// Parlak bolgeleri yumusat: gemi ve lazerler arka planda kaybolmasin
		float l = dot(img, vec3(0.299, 0.587, 0.114));
		img *= 0.92 / (1.0 + max(l - 0.5, 0.0) * 1.3);
		// Ust ve kapi cevresini kis
		float dimf = 0.0;
		for (int i = 0; i < 12; i++) {
			vec4 p = dim_pts[i];
			if (p.w > 0.0) {
				float dd = length(wp - p.xy);
				dimf = max(dimf, (1.0 - smoothstep(p.z * 0.35, p.z, dd)) * p.w);
			}
		}
		img *= 1.0 - dimf;
		// Radyasyon alani: karanlik, disa dogru cok hafif kirmizi uyari tonu
		vec3 rad = mix(base, vec3(0.05, 0.004, 0.006), smoothstep(0.0, 30.0, -din));
		col = mix(rad, img, inside);
	}
	if (stars_on > 0.5) {
		vec3 st = star_layer(px + cam * 0.04, 34.0, 0.55, 0.9, 1.0) * 0.7;
		st += star_layer(px + cam * 0.09, 58.0, 0.45, 1.1, 7.0) * 0.9;
		st += star_layer(px + cam * 0.18, 96.0, 0.35, 1.5, 13.0);
		st += star_layer(px + cam * 0.34, 170.0, 0.25, 2.1, 29.0) * 1.2;
		float k = 1.0;
		if (bg_on > 0.5) {
			k = mix(0.10, 0.38, inside);
		}
		col += st * k;
	}
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.55;
	// Koyu gradyanlarda bantlanmayi onleyen cok hafif titresim
	col += (h21(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
"""

static var _tex: Texture2D = null
static var _pts := PackedVector4Array()
static var _gen := -1
static var _pn := -1


static func index_for(map_name: String) -> int:
	if MAP_BG.has(map_name):
		return clampi(int(MAP_BG[map_name]), 1, BG_COUNT)
	return 1 + (map_name.hash() % BG_COUNT)   # tanimsiz harita: sabit yedek secim


# Harita yuklenince cagrilir: yalnizca bu haritanin gorselini tutar, oncekini birakir.
static func set_map(map_name: String) -> void:
	var path: String = BG_DIR % index_for(map_name)
	_tex = null
	if ResourceLoader.exists(path):
		_tex = load(path) as Texture2D
	_gen = -1
	_pn = -1


# Her karede cagrilir (kamera guncellendikten sonra).
static func update(main, mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if _tex == null or not main.maps.has(main.cur) or main.cam == null:
		mat.set_shader_parameter("bg_on", 0.0)
		return
	var cam: Camera3D = main.cam
	var m = main.maps[main.cur]
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	var wh := Vector2(float(m.w), float(m.h)) * DOData.S
	# Ekranin 3 kosesinden zemine giden isinlar: ekran -> zemin eslemesi bunlarla dogrusal cozulur
	var fwd: Vector3 = -cam.global_transform.basis.z
	var r0: Vector3 = cam.project_ray_normal(Vector2(0.0, 0.0))
	var r1: Vector3 = cam.project_ray_normal(Vector2(vs.x, 0.0))
	var r2: Vector3 = cam.project_ray_normal(Vector2(0.0, vs.y))
	var d0: Vector3 = r0 / r0.dot(fwd)
	var d1: Vector3 = r1 / r1.dot(fwd)
	var d2: Vector3 = r2 / r2.dot(fwd)
	var foc: Vector3 = main.cam_focus
	mat.set_shader_parameter("bg_on", 1.0)
	mat.set_shader_parameter("bg_tex", _tex)
	mat.set_shader_parameter("bg_size", Vector2(float(_tex.get_width()), float(_tex.get_height())))
	mat.set_shader_parameter("map_wh", wh)
	mat.set_shader_parameter("focus_n", Vector2(foc.x / maxf(wh.x, 1.0), foc.z / maxf(wh.y, 1.0)))
	mat.set_shader_parameter("cam_pos", cam.global_position)
	mat.set_shader_parameter("ray_tl", d0)
	mat.set_shader_parameter("ray_dx", d1 - d0)
	mat.set_shader_parameter("ray_dy", d2 - d0)
	mat.set_shader_parameter("edge_soft", EDGE_SOFT)
	mat.set_shader_parameter("overscan", OVERSCAN)
	_update_points(main)
	mat.set_shader_parameter("dim_pts", _pts)


# Ust ve kapilarin konumu (harita yuklenince ya da kapi sayisi degisince yeniden hesaplanir).
static func _update_points(main) -> void:
	if _gen == int(main.map_gen) and _pn == main.portals.size():
		return
	_gen = int(main.map_gen)
	_pn = main.portals.size()
	var pts := PackedVector4Array()
	if main.base_pos != null:
		var r: float = minf(DOData.SAFE_RADIUS * DOData.S, DIM_BASE_R)
		pts.append(Vector4(main.base_pos.x, main.base_pos.z, r, DIM_BASE_K))
	for p in main.portals:
		if pts.size() >= DIM_MAX:
			break
		pts.append(Vector4(p.pos.x, p.pos.z, DIM_PORTAL_R, DIM_PORTAL_K))
	while pts.size() < DIM_MAX:
		pts.append(Vector4.ZERO)
	_pts = pts


# ---------------------------------------------------------------- sabit gorus menzili

# Menzil (DO birimi). Oyuncu yalnizca bu yaricap icindeki NPC / kutulari gorur ve secer; zoom bunu ne artirir ne azaltir.
static func vision_do() -> float:
	return DOData.LASER_RANGE * VISION_MUL


# Her karede (PC + mobil): menzil disindaki NPC ve bonus kutulari gizler. Isim ve can cubuklari dugumun cocugudur, birlikte gizlenir.
# Kilitli hedef ve toplanmakta olan kutu menzilden cikinca da kaybolmaz.
static func apply_vision(main) -> void:
	if main.P == null or not is_instance_valid(main.P.node):
		return
	var po: Vector3 = main.P.node.position
	var lim: float = vision_do() * DOData.S
	var lim2: float = lim * lim
	for e in main.enemies:
		if not is_instance_valid(e.node):
			continue
		var dx: float = float(e.node.position.x) - po.x
		var dz: float = float(e.node.position.z) - po.z
		var vis: bool = (dx * dx + dz * dz <= lim2) or is_same(e, main.target)
		if e.node.visible != vis:
			e.node.visible = vis
	for b in main.boxes:
		if not is_instance_valid(b.node):
			continue
		var bx: float = float(b.node.position.x) - po.x
		var bz: float = float(b.node.position.z) - po.z
		var bvis: bool = (bx * bx + bz * bz <= lim2) or is_same(b, main.collect_box)
		if b.node.visible != bvis:
			b.node.visible = bvis
