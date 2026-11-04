extends RefCounted
# NOVAGATE NPC atis gorselleri: her NPC turunun KENDINE OZGU, kodla cizilen (harici resim gerektirmeyen) mermisi.
#  - Dosya (assets/lasers/*.png) bulunmasa bile calisir; kirmizi kutu cizgisine DUSMEZ.
#  - Sekiller: "dart" (iglemsi enerji oku), "orb" (kuyruklu plazma topu, istege bagli halka), "shard" (kristal),
#    "zig" (elektrik carpmasi). Hepsinin sivri ucu SOLDA (u=0), kuyrugu SAGDA (u=1): main.gd'deki yon kuralinin aynisi.
#  - Boyutlar kucuk/orta tutuldu (len = dunyadaki uzunluk). Ekran kalabaligi olmasin diye genislik de ince.
# main.gd baglantisi: _laser_sprite() ve fire_bolt() "n_" anahtarini buraya yollar.

const DEFAULT_KEY := "streuner"

# shape, px = [genislik, yukseklik] (doku), len = dunya uzunlugu, glow/mid/core = dis hale / govde / cekirdek rengi.
const PROFILES := {
	# Streuner: sicak kehribar plazma igne (kucuk, hizli)
	"streuner": {"shape": "dart", "px": [128, 32], "len": 2.2, "width": 0.5, "head": 0.24, "tail": 0.85,
		"glow": Color(1.0, 0.42, 0.08), "mid": Color(1.0, 0.68, 0.2), "core": Color(1.0, 0.97, 0.82)},
	"streuner_boss": {"shape": "dart", "px": [160, 36], "len": 3.0, "width": 0.6, "head": 0.22, "tail": 0.85, "twin": true,
		"glow": Color(1.0, 0.45, 0.1), "mid": Color(1.0, 0.75, 0.3), "core": Color(1.0, 1.0, 0.9)},
	# Lordakia: yesil cift cizgili enerji oku, nabizli
	"lordakia": {"shape": "dart", "px": [160, 36], "len": 2.8, "width": 0.55, "head": 0.2, "tail": 0.88, "twin": true, "bands": 0.25,
		"glow": Color(0.15, 0.9, 0.3), "mid": Color(0.5, 1.0, 0.45), "core": Color(0.95, 1.0, 0.9)},
	"lordakium": {"shape": "dart", "px": [192, 40], "len": 4.0, "width": 0.65, "head": 0.18, "tail": 0.9, "twin": true, "bands": 0.3,
		"glow": Color(0.1, 0.85, 0.35), "mid": Color(0.6, 1.0, 0.5), "core": Color(1.0, 1.0, 0.92)},
	# Saimon: mor kuyruklu plazma topu
	"saimon": {"shape": "orb", "px": [128, 40], "len": 2.6, "cx": 0.3, "rx": 0.2, "ry": 0.7,
		"glow": Color(0.6, 0.2, 1.0), "mid": Color(0.8, 0.5, 1.0), "core": Color(1.0, 0.95, 1.0)},
	# Mordon: agir, sicak turuncu mermi (bantli)
	"mordon": {"shape": "dart", "px": [160, 40], "len": 3.4, "width": 0.78, "head": 0.16, "tail": 0.88, "bands": 0.35,
		"glow": Color(1.0, 0.3, 0.05), "mid": Color(1.0, 0.6, 0.15), "core": Color(1.0, 0.98, 0.8)},
	# Devolarium: elektrik mavisi carpma
	"devolarium": {"shape": "zig", "px": [176, 44], "len": 3.4, "width": 0.5, "head": 0.18, "tail": 0.9, "zig": 0.18,
		"glow": Color(0.15, 0.45, 1.0), "mid": Color(0.5, 0.8, 1.0), "core": Color(1.0, 1.0, 1.0)},
	# Sibelon: altin halkali plazma topu
	"sibelon": {"shape": "orb", "px": [128, 52], "len": 3.0, "cx": 0.3, "rx": 0.2, "ry": 0.75, "ring": 0.8,
		"glow": Color(1.0, 0.68, 0.1), "mid": Color(1.0, 0.85, 0.35), "core": Color(1.0, 1.0, 0.92)},
	"sibelonit": {"shape": "orb", "px": [128, 48], "len": 2.7, "cx": 0.3, "rx": 0.2, "ry": 0.72, "ring": 0.7,
		"glow": Color(0.1, 0.9, 0.8), "mid": Color(0.5, 1.0, 0.95), "core": Color(1.0, 1.0, 1.0)},
	# Kristallin / Protegit: buz mavisi kristal kiymik
	"kristallin": {"shape": "shard", "px": [96, 28], "len": 2.1, "cx": 0.3, "rx": 0.24, "ry": 0.62,
		"glow": Color(0.25, 0.75, 1.0), "mid": Color(0.65, 0.93, 1.0), "core": Color(1.0, 1.0, 1.0)},
	"protegit": {"shape": "shard", "px": [96, 26], "len": 1.8, "cx": 0.3, "rx": 0.24, "ry": 0.6,
		"glow": Color(0.3, 0.85, 1.0), "mid": Color(0.7, 0.95, 1.0), "core": Color(1.0, 1.0, 1.0)},
	"boss_kristallin": {"shape": "shard", "px": [128, 36], "len": 3.2, "cx": 0.3, "rx": 0.24, "ry": 0.66,
		"glow": Color(0.65, 0.3, 1.0), "mid": Color(0.85, 0.65, 1.0), "core": Color(1.0, 0.97, 1.0)},
	# Kristallon: agir macenta-mavi enerji oku
	"kristallon": {"shape": "dart", "px": [192, 44], "len": 4.2, "width": 0.7, "head": 0.18, "tail": 0.9, "twin": true, "bands": 0.3,
		"glow": Color(0.85, 0.2, 0.8), "mid": Color(0.62, 0.5, 1.0), "core": Color(1.0, 0.97, 1.0)},
	"boss_kristallon": {"shape": "dart", "px": [192, 48], "len": 4.8, "width": 0.78, "head": 0.18, "tail": 0.9, "twin": true, "bands": 0.35,
		"glow": Color(0.95, 0.2, 0.7), "mid": Color(0.7, 0.5, 1.0), "core": Color(1.0, 1.0, 1.0)},
	"pilot": {"shape": "dart", "px": [128, 32], "len": 2.6, "width": 0.5, "head": 0.22, "tail": 0.85,
		"glow": Color(0.2, 0.5, 1.0), "mid": Color(0.5, 0.78, 1.0), "core": Color(1.0, 1.0, 1.0)},
}

# Ozel adi olmayan turler (uber_*, cubikon) en yakin ana profile esler.
const ALIAS := {
	"uber_lordakium": "lordakium", "uber_sibelonit": "sibelonit", "uber_kristallin": "boss_kristallin",
	"uber_kristallon": "boss_kristallon", "cubikon": "kristallon",
}

static var _cache := {}


static func _id_of(key: String) -> String:
	var id := key
	if id.begins_with("n_"):
		id = id.substr(2)
	if ALIAS.has(id):
		id = str(ALIAS[id])
	if not PROFILES.has(id):
		id = DEFAULT_KEY
	return id


static func profile(key: String) -> Dictionary:
	return PROFILES[_id_of(key)]


# Merminin ana rengi (iz efekti ve carpma efekti icin).
static func color(key: String) -> Color:
	var p: Dictionary = profile(key)
	return (p.glow as Color).lerp(p.mid as Color, 0.35)


# {"mesh": PlaneMesh, "mat": StandardMaterial3D} -- main.gd'deki _laser_sprite() ile ayni donus bicimi.
static func sprite(key: String) -> Dictionary:
	var id := _id_of(key)
	if _cache.has(id):
		return _cache[id]
	var p: Dictionary = PROFILES[id]
	var w: int = int((p.px as Array)[0])
	var h: int = int((p.px as Array)[1])
	var ln: float = float(p.len)
	var pm := PlaneMesh.new()
	pm.size = Vector2(ln, ln * float(h) / float(w))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _make_tex(p)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var res := {"mesh": pm, "mat": m}
	_cache[id] = res
	return res


# Namlu parlamasi: NPC'nin rengine ve buyuklugune gore.
static func flash(g, from: Vector3, key: String) -> void:
	var p: Dictionary = profile(key)
	var s: float = clampf(float(p.len) / 2.8, 0.7, 1.6)
	var c: Color = (p.mid as Color).lerp(Color(1, 1, 1), 0.35)
	g._fx_sphere(from, c, 0.28 * s, 1.15 * s, 0.12, 0.9)


static func _make_tex(p: Dictionary) -> ImageTexture:
	var w: int = int((p.px as Array)[0])
	var h: int = int((p.px as Array)[1])
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var glow: Color = p.glow
	var mid: Color = p.mid
	var core: Color = p.core
	var shape: String = str(p.shape)
	for y in h:
		var v: float = ((float(y) + 0.5) / float(h)) * 2.0 - 1.0
		for x in w:
			var u: float = (float(x) + 0.5) / float(w)
			var ig := 0.0   # hale
			var im := 0.0   # govde
			var ic := 0.0   # cekirdek
			match shape:
				"orb":
					var r := _orb(p, u, v)
					ig = r.x
					im = r.y
					ic = r.z
				"shard":
					var r := _shard(p, u, v)
					ig = r.x
					im = r.y
					ic = r.z
				_:
					var r := _dart(p, u, v, shape == "zig")
					ig = r.x
					im = r.y
					ic = r.z
			# kenarlarda yanal sizinti olmasin
			var fade: float = (1.0 - smoothstep(0.86, 1.0, absf(v))) * (1.0 - smoothstep(0.93, 1.0, u)) * smoothstep(0.0, 0.025, u)
			var rr: float = glow.r * ig + mid.r * im + core.r * ic
			var gg: float = glow.g * ig + mid.g * im + core.g * ic
			var bb: float = glow.b * ig + mid.b * im + core.b * ic
			var aa: float = clampf(ig * 0.9 + im + ic, 0.0, 1.0)
			img.set_pixel(x, y, Color(clampf(rr * fade, 0.0, 1.0), clampf(gg * fade, 0.0, 1.0), clampf(bb * fade, 0.0, 1.0), aa * fade))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Iglemsi enerji oku (zig = true: elektrik dalgasi).
static func _dart(p: Dictionary, u: float, v: float, zig: bool) -> Vector3:
	var head: float = float(p.get("head", 0.2))
	var tail: float = float(p.get("tail", 0.88))
	var width: float = float(p.get("width", 0.6))
	var head_p: float = pow(smoothstep(0.0, head, u), 0.75)
	var tail_p: float = 1.0 - smoothstep(1.0 - tail, 1.0, u) * 0.92
	var hw: float = maxf(width * head_p * tail_p, 0.001)
	var vv: float = v
	if zig:
		vv = v + float(p.get("zig", 0.25)) * sin(u * 9.0 * TAU + sin(u * 31.0) * 1.5) * smoothstep(0.05, 0.3, u)
	var d: float = absf(vv) / hw
	var along: float = (1.0 - smoothstep(0.0, 1.0, u) * 0.78) * (1.0 - smoothstep(0.7, 1.0, u))
	var halo: float = exp(-pow(d * 1.15, 2.0)) * along * 0.85
	var body: float = exp(-pow(d * 2.6, 2.0)) * along
	var c: float = exp(-pow(d * 6.2, 2.0)) * (1.0 - smoothstep(0.0, 1.0, u) * 0.55)
	if bool(p.get("twin", false)):
		c = exp(-pow((absf(vv) - 0.24 * hw) / (0.07 * hw + 0.001), 2.0)) * along * 1.1
	var bands: float = float(p.get("bands", 0.0))
	if bands > 0.0:
		var pulse: float = 0.5 + 0.5 * sin(u * 16.0 * TAU)
		body *= (1.0 - bands + bands * pulse)
	var tip: float = exp(-pow((u - head * 0.55) / (head * 0.45), 2.0)) * exp(-pow(d * 3.2, 2.0)) * 1.3
	return Vector3(halo, body, clampf(c + tip, 0.0, 1.5))


# Kuyruklu plazma topu (+ istege bagli halka).
static func _orb(p: Dictionary, u: float, v: float) -> Vector3:
	var cx: float = float(p.get("cx", 0.3))
	var rx: float = float(p.get("rx", 0.2))
	var ry: float = float(p.get("ry", 0.7))
	var ring: float = float(p.get("ring", 0.0))
	var r: float = sqrt(pow((u - cx) / rx, 2.0) + pow(v / ry, 2.0))
	var halo: float = exp(-pow(r / 0.95, 2.0)) * 0.8
	var body: float = exp(-pow(r / 0.5, 2.0))
	var c: float = exp(-pow(r / 0.22, 2.0)) * 1.3
	if ring > 0.0:
		halo += ring * exp(-pow((r - 0.98) / 0.1, 2.0))
	if u > cx:
		var t: float = clampf((u - cx) / (1.0 - cx), 0.0, 1.0)
		var streak: float = exp(-pow(absf(v) / (0.3 * (1.0 - t) + 0.03), 2.0)) * pow(1.0 - t, 1.6) * smoothstep(cx - rx * 0.2, cx + rx * 0.9, u)
		halo += streak * 0.55
		body += streak * 0.45
	return Vector3(halo, body, c)


# Kristal kiymik: keskin kenarli elmas + sonuk iz.
static func _shard(p: Dictionary, u: float, v: float) -> Vector3:
	var cx: float = float(p.get("cx", 0.3))
	var rx: float = float(p.get("rx", 0.24))
	var ry: float = float(p.get("ry", 0.62))
	var l1: float = absf((u - cx) / rx) + absf(v / ry)
	var fill: float = 1.0 - smoothstep(0.82, 1.0, l1)
	var edge: float = exp(-pow((l1 - 0.92) / 0.07, 2.0))
	var halo: float = exp(-pow(l1 / 1.7, 2.0)) * 0.7
	var body: float = fill * (0.75 - l1 * 0.4)
	var c: float = edge * 0.9 + exp(-pow(l1 / 0.28, 2.0)) * 1.2
	if u > cx:
		var t: float = clampf((u - cx) / (1.0 - cx), 0.0, 1.0)
		var streak: float = exp(-pow(absf(v) / (0.22 * (1.0 - t) + 0.03), 2.0)) * pow(1.0 - t, 1.8) * smoothstep(cx - rx * 0.2, cx + rx * 0.9, u)
		halo += streak * 0.5
		body += streak * 0.35
	return Vector3(halo, body, c)
