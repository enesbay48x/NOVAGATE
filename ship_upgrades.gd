class_name ShipUpgrades
extends RefCounted

# Satilan gemilere ek kanat, neon kenar rengi, kanat ucu isiklari ve UCARKEN gemiye ozel duman.
# Sadece markette satilan gemiler (DOData.MARKET_HIDDEN disindakiler) etkilenir.
# Istatistiklere (hp/hiz/lazer) dokunmaz; sadece gorsel. Kapatmak icin ENABLED = false.
#
# Olcu birimleri (hepsi gemi govdesine oranli):
#   z    : burun yonunde konum (+0.5 burun, -0.5 kuyruk)  -> govde uzunlugu orani
#   x    : merkezden kanat kokune uzaklik                  -> govde genisligi orani
#   span : kanadin disari uzanimi                          -> govde genisligi orani
#   root/tip : kok ve uc kanat genisligi (ilerleme yonu)   -> govde uzunlugu orani
#   sweep: kanat ucunun geriye kaymasi (negatif = one egik) -> govde uzunlugu orani
#   y    : dikey konum (-1 alt .. +1 ust)                  -> govde yuksekligi orani
#   th   : kalinlik                                        -> gemi boyutu orani
#   dih  : kanat yukari/asagi acisi (derece)
const ENABLED := true
const WINGS_ENABLED := false   # ek kanat/fin/neon seritleri: duz levha gorunumu kotu oldugu icin kapali

const CONFIG := {
	"phoenix": {
		"wing": Color(0.50, 0.66, 0.92), "trim": Color(0.25, 0.65, 1.0),
		"wings": [
			{"z": -0.14, "x": 0.20, "span": 0.38, "root": 0.30, "tip": 0.08, "sweep": 0.26, "y": 0.10, "th": 0.030, "dih": 8.0},
		],
		"fins": [
			{"x": 0.0, "z": -0.30, "h": 0.20, "root": 0.26, "tip": 0.08, "sweep": 0.16, "cant": 0.0, "y": 0.7},
		],
		"smoke": {"hot": Color(0.55, 0.85, 1.0), "mid": Color(0.62, 0.68, 0.80), "cool": Color(0.30, 0.34, 0.42), "flame": Color(0.3, 0.7, 1.0), "size": 0.55, "life": 1.0, "amt": 18, "vel": 1.4, "spread": 6.0},
	},
	"yamato": {
		"wing": Color(0.80, 0.62, 0.28), "trim": Color(1.0, 0.65, 0.2),
		"wings": [
			{"z": 0.18, "x": 0.18, "span": 0.24, "root": 0.20, "tip": 0.10, "sweep": -0.10, "y": 0.0, "th": 0.026, "dih": 0.0},
			{"z": -0.20, "x": 0.22, "span": 0.38, "root": 0.32, "tip": 0.08, "sweep": 0.24, "y": 0.12, "th": 0.030, "dih": 10.0},
		],
		"fins": [],
		"smoke": {"hot": Color(1.0, 0.80, 0.40), "mid": Color(0.60, 0.52, 0.42), "cool": Color(0.30, 0.27, 0.24), "flame": Color(1.0, 0.6, 0.2), "size": 0.60, "life": 1.1, "amt": 20, "vel": 1.5, "spread": 7.0},
	},
	"leonov": {
		"wing": Color(0.82, 0.85, 0.92), "trim": Color(1.0, 0.55, 0.2),
		"wings": [
			{"z": -0.10, "x": 0.20, "span": 0.44, "root": 0.46, "tip": 0.10, "sweep": 0.34, "y": 0.0, "th": 0.032, "dih": -6.0},
		],
		"fins": [
			{"x": 0.30, "z": -0.28, "h": 0.16, "root": 0.20, "tip": 0.07, "sweep": 0.12, "cant": 18.0, "y": 0.7},
		],
		"smoke": {"hot": Color(1.0, 0.75, 0.45), "mid": Color(0.72, 0.70, 0.70), "cool": Color(0.35, 0.34, 0.36), "flame": Color(1.0, 0.55, 0.2), "size": 0.65, "life": 1.15, "amt": 22, "vel": 1.5, "spread": 7.0},
	},
	"defcom": {
		"wing": Color(0.36, 0.58, 0.40), "trim": Color(0.3, 1.0, 0.5),
		"wings": [
			{"z": 0.02, "x": 0.22, "span": 0.32, "root": 0.36, "tip": 0.22, "sweep": 0.10, "y": 0.0, "th": 0.045, "dih": 0.0},
			{"z": -0.28, "x": 0.20, "span": 0.28, "root": 0.24, "tip": 0.10, "sweep": 0.14, "y": 0.15, "th": 0.035, "dih": 6.0},
		],
		"fins": [],
		"smoke": {"hot": Color(0.6, 1.0, 0.65), "mid": Color(0.50, 0.58, 0.52), "cool": Color(0.24, 0.28, 0.25), "flame": Color(0.3, 1.0, 0.5), "size": 0.75, "life": 1.2, "amt": 24, "vel": 1.3, "spread": 8.0},
	},
	"liberator": {
		"wing": Color(0.70, 0.30, 0.30), "trim": Color(1.0, 0.3, 0.3),
		"wings": [
			{"z": -0.08, "x": 0.22, "span": 0.40, "root": 0.34, "tip": 0.08, "sweep": 0.30, "y": 0.18, "th": 0.030, "dih": 10.0},
			{"z": -0.18, "x": 0.22, "span": 0.32, "root": 0.28, "tip": 0.07, "sweep": 0.22, "y": -0.18, "th": 0.028, "dih": -10.0},
		],
		"fins": [],
		"smoke": {"hot": Color(1.0, 0.55, 0.40), "mid": Color(0.62, 0.50, 0.50), "cool": Color(0.30, 0.25, 0.25), "flame": Color(1.0, 0.3, 0.2), "size": 0.70, "life": 1.15, "amt": 22, "vel": 1.5, "spread": 7.0},
	},
	"piranha": {
		"wing": Color(0.22, 0.62, 0.68), "trim": Color(0.2, 1.0, 0.9),
		"wings": [
			{"z": -0.05, "x": 0.20, "span": 0.28, "root": 0.30, "tip": 0.10, "sweep": 0.20, "y": -0.05, "th": 0.028, "dih": -8.0},
		],
		"fins": [
			{"x": 0.0, "z": -0.12, "h": 0.30, "root": 0.34, "tip": 0.06, "sweep": 0.28, "cant": 0.0, "y": 0.7},
		],
		"smoke": {"hot": Color(0.5, 1.0, 0.95), "mid": Color(0.50, 0.66, 0.68), "cool": Color(0.22, 0.30, 0.32), "flame": Color(0.2, 1.0, 0.9), "size": 0.65, "life": 1.1, "amt": 22, "vel": 1.6, "spread": 6.0},
	},
	"nostromo": {
		"wing": Color(0.58, 0.40, 0.78), "trim": Color(0.8, 0.4, 1.0),
		"wings": [
			{"z": -0.15, "x": 0.20, "span": 0.44, "root": 0.40, "tip": 0.07, "sweep": 0.38, "y": 0.08, "th": 0.030, "dih": 4.0},
		],
		"fins": [
			{"x": 0.34, "z": -0.30, "h": 0.18, "root": 0.22, "tip": 0.07, "sweep": 0.14, "cant": 14.0, "y": 0.7},
		],
		"smoke": {"hot": Color(0.85, 0.55, 1.0), "mid": Color(0.58, 0.50, 0.66), "cool": Color(0.27, 0.24, 0.32), "flame": Color(0.8, 0.4, 1.0), "size": 0.70, "life": 1.2, "amt": 22, "vel": 1.5, "spread": 7.0},
	},
	"spearhead": {
		"wing": Color(0.34, 0.37, 0.46), "trim": Color(1.0, 0.2, 0.2),
		"wings": [
			{"z": 0.10, "x": 0.18, "span": 0.40, "root": 0.26, "tip": 0.08, "sweep": -0.22, "y": 0.05, "th": 0.024, "dih": 6.0},
			{"z": -0.25, "x": 0.20, "span": 0.24, "root": 0.20, "tip": 0.07, "sweep": 0.10, "y": 0.0, "th": 0.022, "dih": 0.0},
		],
		"fins": [],
		"smoke": {"hot": Color(1.0, 0.45, 0.35), "mid": Color(0.45, 0.42, 0.46), "cool": Color(0.20, 0.19, 0.22), "flame": Color(1.0, 0.2, 0.2), "size": 0.55, "life": 0.9, "amt": 20, "vel": 2.0, "spread": 4.0},
	},
	"vengeance": {
		"wing": Color(0.72, 0.16, 0.22), "trim": Color(1.0, 0.25, 0.3),
		"wings": [
			{"z": -0.12, "x": 0.20, "span": 0.44, "root": 0.40, "tip": 0.06, "sweep": 0.40, "y": 0.10, "th": 0.032, "dih": 8.0},
		],
		"fins": [
			{"x": 0.28, "z": -0.32, "h": 0.26, "root": 0.28, "tip": 0.06, "sweep": 0.22, "cant": 20.0, "y": 0.7},
		],
		"smoke": {"hot": Color(1.0, 0.4, 0.35), "mid": Color(0.50, 0.36, 0.38), "cool": Color(0.22, 0.17, 0.19), "flame": Color(1.0, 0.25, 0.3), "size": 0.80, "life": 1.2, "amt": 26, "vel": 1.7, "spread": 6.0},
	},
	"goliath": {
		"wing": Color(0.26, 0.48, 0.82), "trim": Color(0.3, 0.7, 1.0),
		"wings": [
			{"z": 0.0, "x": 0.24, "span": 0.40, "root": 0.44, "tip": 0.20, "sweep": 0.16, "y": 0.0, "th": 0.048, "dih": 0.0},
			{"z": -0.26, "x": 0.22, "span": 0.30, "root": 0.26, "tip": 0.08, "sweep": 0.16, "y": 0.16, "th": 0.034, "dih": 8.0},
		],
		"fins": [],
		"smoke": {"hot": Color(0.55, 0.85, 1.0), "mid": Color(0.52, 0.60, 0.72), "cool": Color(0.24, 0.28, 0.36), "flame": Color(0.3, 0.7, 1.0), "size": 0.90, "life": 1.3, "amt": 28, "vel": 1.4, "spread": 8.0},
	},
}

static var _soft_tex: GradientTexture2D = null
static var _mat_cache := {}


static func is_upgraded(id: String) -> bool:
	return CONFIG.has(id) and not (id in DOData.MARKET_HIDDEN)


# make_ship() sonunda cagrilir. Efektler geminin "tilt" dugumune eklenir (burun = +Z, merkez = govde merkezi).
static func apply(id: String, pivot: Node3D, holder: Node3D, hull: AABB, engines: Array, yaw: float, k: float, tint: Color) -> void:
	if not ENABLED or not is_upgraded(id):
		return
	var tilt: Node3D = pivot.get_parent() as Node3D
	if tilt == null:
		return
	var cfg: Dictionary = CONFIG[id]
	var sy: float = absf(sin(yaw))
	var cy: float = absf(cos(yaw))
	var len_u: float = (sy * hull.size.x + cy * hull.size.z) * k
	var wid_u: float = (cy * hull.size.x + sy * hull.size.z) * k
	var hgt_u: float = hull.size.y * k
	var ref_u: float = maxf(len_u, wid_u)
	if ref_u < 0.001:
		return

	var fx := Node3D.new()
	fx.name = "UpgradeFX"
	tilt.add_child(fx)

	var wing_col: Color = (cfg["wing"] as Color).lerp(tint, 0.25)
	var trim_col: Color = cfg["trim"]
	var wing_mat := _wing_mat(wing_col)
	var trim_mat := _trim_mat(trim_col)

	if WINGS_ENABLED:
		for w in cfg["wings"]:
			_add_wing(fx, w, len_u, wid_u, hgt_u, ref_u, wing_mat, trim_mat, trim_col)
		for f in cfg["fins"]:
			_add_fin(fx, f, len_u, wid_u, hgt_u, ref_u, wing_mat)

	# Duman cikis noktalari: modeldeki engine_* isaretcileri, yoksa kuyruga iki nokta.
	var tp: Transform3D = pivot.transform * holder.transform
	var pts: Array = []
	for ec in engines:
		var p: Vector3 = tp * (ec as Vector3)
		p.z -= len_u * 0.02
		var dup := false
		for q in pts:
			if (q as Vector3).distance_to(p) < ref_u * 0.12:
				dup = true
				break
		if not dup:
			pts.append(p)
	if pts.size() > 4:
		pts.sort_custom(func(a, b): return (a as Vector3).x < (b as Vector3).x)
		var pick: Array = []
		for i in 4:
			pick.append(pts[int(round(float(i) * float(pts.size() - 1) / 3.0))])
		pts = pick
	if pts.is_empty():
		pts.append(Vector3(wid_u * 0.14, 0.0, -len_u * 0.5))
		pts.append(Vector3(-wid_u * 0.14, 0.0, -len_u * 0.5))
	_build_smoke(fx, cfg["smoke"], pts, ref_u)


# ---------------------------------------------------------------- kanat / fin

static func _add_wing(fx: Node3D, c: Dictionary, len_u: float, wid_u: float, hgt_u: float, ref_u: float, wing_mat: Material, trim_mat: Material, trim_col: Color) -> void:
	var x0: float = float(c["x"]) * wid_u
	var span: float = float(c["span"]) * wid_u
	var zc: float = float(c["z"]) * len_u
	var root: float = float(c["root"]) * len_u
	var tip: float = float(c["tip"]) * len_u
	var sweep: float = float(c["sweep"]) * len_u
	var yy: float = float(c["y"]) * hgt_u * 0.5
	var th: float = float(c["th"]) * ref_u * 0.5
	var dih: float = deg_to_rad(float(c.get("dih", 0.0)))
	var lead_r: float = zc + root * 0.5
	var lead_t: float = lead_r - sweep
	var sw: float = len_u * 0.035
	for side in [1.0, -1.0]:
		var sd: float = side
		var pts: Array = [Vector2(0.0, lead_r), Vector2(span * sd, lead_t), Vector2(span * sd, lead_t - tip), Vector2(0.0, zc - root * 0.5)]
		var hs: Array = [th, th * 0.4, th * 0.4, th]
		var mi := MeshInstance3D.new()
		mi.mesh = _slab(pts, hs)
		mi.material_override = wing_mat
		mi.position = Vector3(x0 * sd, yy, 0.0)
		mi.rotation.z = dih * sd
		fx.add_child(mi)
		# Neon on kenar seridi
		var tpts: Array = [Vector2(0.0, lead_r), Vector2(span * sd, lead_t), Vector2(span * sd, lead_t - sw), Vector2(0.0, lead_r - sw)]
		var ths: Array = [th * 1.12 + ref_u * 0.004, th * 0.4 * 1.12 + ref_u * 0.004, th * 0.4 * 1.12 + ref_u * 0.004, th * 1.12 + ref_u * 0.004]
		var tm := MeshInstance3D.new()
		tm.mesh = _slab(tpts, ths)
		tm.material_override = trim_mat
		mi.add_child(tm)
		# Kanat ucu isigi (motor parlamasiyla ayni grupta nabiz atar)
		var sp := SphereMesh.new()
		sp.radius = ref_u * 0.022
		sp.height = ref_u * 0.044
		sp.radial_segments = 8
		sp.rings = 4
		var tl := MeshInstance3D.new()
		tl.mesh = sp
		tl.material_override = trim_mat
		tl.position = Vector3(span * sd, 0.0, lead_t - tip * 0.5)
		tl.add_to_group("engine_glow")
		mi.add_child(tl)


static func _add_fin(fx: Node3D, c: Dictionary, len_u: float, wid_u: float, hgt_u: float, ref_u: float, wing_mat: Material) -> void:
	var xo: float = float(c["x"]) * wid_u
	var zc: float = float(c["z"]) * len_u
	var h: float = float(c["h"]) * ref_u
	var root: float = float(c["root"]) * len_u
	var tip: float = float(c["tip"]) * len_u
	var sweep: float = float(c["sweep"]) * len_u
	var cant: float = deg_to_rad(float(c.get("cant", 0.0)))
	var yb: float = float(c.get("y", 0.7)) * hgt_u * 0.5
	var th: float = ref_u * 0.014
	var lead_r: float = zc + root * 0.5
	var lead_t: float = lead_r - sweep
	# mesh yerel x ekseni = fin yuksekligi (Z etrafinda 90 derece donunce dunya +Y olur)
	var pts: Array = [Vector2(0.0, lead_r), Vector2(h, lead_t), Vector2(h, lead_t - tip), Vector2(0.0, zc - root * 0.5)]
	var hs: Array = [th, th * 0.4, th * 0.4, th]
	var mesh := _slab(pts, hs)
	var sides: Array = [0.0] if absf(xo) < 0.0001 else [1.0, -1.0]
	for side in sides:
		var sd: float = side
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = wing_mat
		mi.position = Vector3(xo * sd, yb, 0.0)
		mi.rotation.z = PI * 0.5 - cant * sd   # sd = 0 (orta fin) iken egim yok
		fx.add_child(mi)


# Konveks cokgeni (x, z duzleminde) y ekseninde kalinlastirir. hs = her kose icin yarim kalinlik.
static func _slab(pts: Array, hs: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = pts.size()
	var cen := Vector2.ZERO
	for p in pts:
		cen += p as Vector2
	cen /= float(n)
	for i in range(1, n - 1):
		_tri(st, _vtx(pts, hs, 0, 1.0), _vtx(pts, hs, i, 1.0), _vtx(pts, hs, i + 1, 1.0), Vector3.UP)
		_tri(st, _vtx(pts, hs, 0, -1.0), _vtx(pts, hs, i, -1.0), _vtx(pts, hs, i + 1, -1.0), Vector3.DOWN)
	for i in n:
		var j: int = (i + 1) % n
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		var d: Vector2 = b - a
		if d.length() < 0.0001:
			continue
		var nn := Vector2(d.y, -d.x).normalized()
		if nn.dot((a + b) * 0.5 - cen) < 0.0:
			nn = -nn
		var out := Vector3(nn.x, 0.0, nn.y)
		var at: Vector3 = _vtx(pts, hs, i, 1.0)
		var bt: Vector3 = _vtx(pts, hs, j, 1.0)
		var bb: Vector3 = _vtx(pts, hs, j, -1.0)
		var ab: Vector3 = _vtx(pts, hs, i, -1.0)
		_tri(st, at, bt, bb, out)
		_tri(st, at, bb, ab, out)
	return st.commit()


static func _vtx(pts: Array, hs: Array, i: int, sgn: float) -> Vector3:
	var p: Vector2 = pts[i]
	return Vector3(p.x, float(hs[i]) * sgn, p.y)


# Duz normalli ucgen; sarma yonu (Godot: on yuz saat yonu) normale gore otomatik duzeltilir.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var cr: Vector3 = (b - a).cross(c - a)
	if cr.length_squared() < 1.0e-12:
		return
	var nrm: Vector3 = cr.normalized()
	if nrm.dot(hint) < 0.0:
		nrm = -nrm
	if cr.dot(nrm) > 0.0:
		var t: Vector3 = b
		b = c
		c = t
	st.set_normal(nrm)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.add_vertex(b)
	st.set_normal(nrm)
	st.add_vertex(c)


static func _wing_mat(col: Color) -> StandardMaterial3D:
	var key := "w|" + col.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.55
	m.roughness = 0.34
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


static func _trim_mat(col: Color) -> StandardMaterial3D:
	var key := "t|" + col.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.12)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------- duman

static func _soft() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


static func _particle_mat(additive: bool) -> StandardMaterial3D:
	var key := "p|%s" % additive
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_mat_cache[key] = m
	return m


static func _ramp(offs: Array, cols: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	return g


static func _build_smoke(fx: Node3D, sm: Dictionary, pts: Array, ref_u: float) -> void:
	var ctl := SmokeCtl.new()
	ctl.name = "SmokeCtl"
	fx.add_child(ctl)
	var sc: float = ref_u / 6.0
	var hot: Color = sm["hot"]
	var mid: Color = sm["mid"]
	var cool: Color = sm["cool"]
	var flame: Color = sm["flame"]
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _particle_mat(false)
	var fquad := QuadMesh.new()
	fquad.size = Vector2.ONE
	fquad.material = _particle_mat(true)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.8))
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.15))
	var smoke_ramp := _ramp([0.0, 0.2, 0.65, 1.0], [
		Color(hot.r, hot.g, hot.b, 0.0),
		Color(hot.r, hot.g, hot.b, 0.55),
		Color(mid.r, mid.g, mid.b, 0.35),
		Color(cool.r, cool.g, cool.b, 0.0)])
	var flame_ramp := _ramp([0.0, 0.4, 1.0], [
		Color(1.0, 1.0, 1.0, 0.9),
		Color(flame.r, flame.g, flame.b, 0.6),
		Color(flame.r, flame.g, flame.b, 0.0)])
	for ep in pts:
		var pos: Vector3 = ep
		# Duman
		var p := CPUParticles3D.new()
		p.emitting = false
		p.amount = int(sm["amt"])
		p.lifetime = float(sm["life"])
		p.lifetime_randomness = 0.35
		p.local_coords = false
		p.direction = Vector3(0.0, 0.0, -1.0)
		p.spread = float(sm["spread"])
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = float(sm["vel"]) * 0.6
		p.initial_velocity_max = float(sm["vel"])
		p.damping_min = 0.4
		p.damping_max = 0.8
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.scale_amount_min = float(sm["size"]) * sc * 0.75
		p.scale_amount_max = float(sm["size"]) * sc * 1.1
		p.scale_amount_curve = grow
		p.color_ramp = smoke_ramp
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.05 * sc
		p.mesh = quad
		p.position = pos
		ctl.add_child(p)
		ctl.parts.append(p)
		# Kisa, parlak motor alevi
		var f := CPUParticles3D.new()
		f.emitting = false
		f.amount = 8
		f.lifetime = 0.22
		f.local_coords = false
		f.direction = Vector3(0.0, 0.0, -1.0)
		f.spread = 3.0
		f.gravity = Vector3.ZERO
		f.initial_velocity_min = 0.4
		f.initial_velocity_max = 0.9
		f.scale_amount_min = float(sm["size"]) * sc * 0.45
		f.scale_amount_max = float(sm["size"]) * sc * 0.6
		f.scale_amount_curve = shrink
		f.color_ramp = flame_ramp
		f.mesh = fquad
		f.position = pos
		ctl.add_child(f)
		ctl.parts.append(f)


# Gemi dunyada hareket ediyorsa (xz duzleminde) duman acilir, durunca kapanir; mevcut duman kendiliginden sonumlenir.
class SmokeCtl extends Node3D:
	var parts: Array = []
	var last := Vector3.ZERO
	var has_last := false
	var spd := 0.0

	func _process(dt: float) -> void:
		if dt <= 0.0 or not is_inside_tree():
			return
		var gp: Vector3 = global_position
		if not has_last:
			last = gp
			has_last = true
			return
		var dxz := Vector2(gp.x - last.x, gp.z - last.z)
		last = gp
		var s: float = dxz.length() / dt
		if s > 200.0:   # isinlanma / harita degisimi
			s = 0.0
		spd = lerpf(spd, s, 1.0 - exp(-6.0 * dt))
		var on: bool = spd > 1.0 and is_visible_in_tree()
		for p in parts:
			var cp: CPUParticles3D = p
			if cp.emitting != on:
				cp.emitting = on
