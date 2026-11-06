class_name JumpGate
extends Node3D
# NOVAGATE atlama kapisi. Model dosyasi GEREKTIRMEZ: tamamen kodla cizilir ve kendi kendine animasyon yapar.
#
# Parcalar : koyu metal dis cerceve + 4 ana / 8 yardimci payanda, icte "kosan isik" halkasi,
#            ters donen isaret halkasi, dönen enerji girdabi (shader), zemin parlamasi, ici suzulen parcaciklar.
# Disaridan: set_charge(0..1)  -> atlama geri sayimi sirasinda her karede cagrilir (kapi sarj olur, hizlanir).
#            burst(guc)        -> atlama / varis patlamasi (sok dalgasi halkalari + parlama).
# set_charge bir sure cagrilmazsa sarj kendiliginden soner (atlama iptal edilirse ekstra kod gerekmez).

const SEG := 24          # kosan isik sayisi
const TICKS := 12        # donen isaret sayisi
const MOTES := 26        # girdaba suzulen parcacik sayisi

const VORTEX_SHADER := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col_a : source_color = vec4(0.05, 0.45, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(0.75, 0.97, 1.0, 1.0);
uniform float energy = 1.0;
uniform float phase = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float tw = a * 3.0 + (1.0 - r) * 9.0 - phase;
	float arms = pow(0.5 + 0.5 * sin(tw), 2.0);
	float rings = 0.5 + 0.5 * sin(r * 26.0 + phase * 1.6);
	float core = pow(1.0 - r, 1.4);
	float rim = smoothstep(0.78, 0.92, r) * (1.0 - smoothstep(0.94, 1.0, r));
	float v = arms * 0.55 * core + rings * 0.12 * core + pow(1.0 - r, 4.0) * 0.9 + rim * 0.5;
	v = v * energy + flash * pow(1.0 - r, 2.0);
	vec3 c = mix(col_a.rgb, col_b.rgb, clamp(v, 0.0, 1.0));
	ALBEDO = c * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
"

const HALO_SHADER := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform float energy = 0.5;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float g = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	ALBEDO = col.rgb * g * energy;
	ALPHA = clamp(g * energy, 0.0, 1.0);
}
"


# ---- Galaxy Gate'lere ozel girdaplar (ayni uniform'lar: col_a, col_b, energy, phase, flash) ----
# ALFA: zehirli, kabaran asit agzi
const VORTEX_ALPHA := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col_a : source_color = vec4(0.05, 0.45, 0.05, 1.0);
uniform vec4 col_b : source_color = vec4(0.8, 1.0, 0.5, 1.0);
uniform float energy = 1.0;
uniform float phase = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float w1 = 0.5 + 0.5 * sin(a * 5.0 + r * 14.0 - phase * 1.3);
	float w2 = 0.5 + 0.5 * sin(a * 9.0 - r * 21.0 + phase * 2.1);
	float cell = pow(w1 * w2, 1.4);
	float bub = smoothstep(0.80, 1.0, 0.5 + 0.5 * sin(r * 42.0 - phase * 3.2 + sin(a * 6.0) * 2.0)) * (1.0 - r);
	float core = pow(1.0 - r, 1.2);
	float rim = smoothstep(0.78, 0.92, r) * (1.0 - smoothstep(0.94, 1.0, r));
	float v = cell * 0.75 * core + bub * 0.4 + pow(1.0 - r, 5.0) * 0.85 + rim * 0.6;
	v = v * energy + flash * pow(1.0 - r, 2.0);
	vec3 c = mix(col_a.rgb, col_b.rgb, clamp(v, 0.0, 1.0));
	ALBEDO = c * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
"

# BETA: dikey gozbebekli, damarli, alev renkli CEHENNEM GOZU
const VORTEX_BETA := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col_a : source_color = vec4(0.6, 0.1, 0.0, 1.0);
uniform vec4 col_b : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform float energy = 1.0;
uniform float phase = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float pw = 0.085 + 0.04 * sin(phase * 0.5);
	float slit = (1.0 - smoothstep(pw * 0.7, pw, abs(p.x) + 0.12 * p.y * p.y)) * (1.0 - smoothstep(0.50, 0.58, abs(p.y)));
	float veins = pow(0.5 + 0.5 * sin(a * 24.0 + sin(r * 10.0 - phase * 0.8) * 2.5), 5.0) * smoothstep(0.12, 0.7, r) * (1.0 - smoothstep(0.85, 1.0, r));
	float fire = 0.5 + 0.5 * sin(r * 20.0 - phase * 2.2 + a * 4.0);
	float iris = (1.0 - smoothstep(0.55, 0.98, r)) * (0.35 + 0.45 * fire);
	float glow_edge = (1.0 - smoothstep(0.0, 0.07, abs(abs(p.x) - pw))) * (1.0 - smoothstep(0.5, 0.6, abs(p.y))) * 0.9;
	float rim = smoothstep(0.80, 0.93, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float v = iris + veins * 0.7 + glow_edge + rim * 0.6;
	v = v * (1.0 - slit * 0.95);
	v = v * energy + flash * pow(1.0 - r, 2.0);
	vec3 c = mix(col_a.rgb, col_b.rgb, clamp(v, 0.0, 1.0));
	ALBEDO = c * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
"

# GAMMA: orta bos karadelik, kan kirmizisi catlaklar ve simsekler
const VORTEX_GAMMA := "
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col_a : source_color = vec4(0.5, 0.0, 0.02, 1.0);
uniform vec4 col_b : source_color = vec4(1.0, 0.5, 0.4, 1.0);
uniform float energy = 1.0;
uniform float phase = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float ang1 = a * 7.0 + sin(r * 12.0 - phase * 0.5) * 1.4;
	float crack1 = pow(1.0 - abs(sin(ang1)), 16.0) * smoothstep(0.12, 0.8, r);
	float ang2 = a * 13.0 - sin(r * 22.0 + phase) * 1.8;
	float crack2 = pow(1.0 - abs(sin(ang2)), 24.0) * smoothstep(0.35, 1.0, r);
	float ring = smoothstep(0.27, 0.33, r) * (1.0 - smoothstep(0.33, 0.52, r));
	float rim = smoothstep(0.80, 0.93, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float v = crack1 * 0.9 + crack2 * 0.6 + ring * (0.7 + 0.3 * sin(phase * 1.5)) + rim * 0.7;
	v = v * smoothstep(0.1, 0.28, r);
	v = v * energy + flash * pow(1.0 - r, 2.0) * smoothstep(0.1, 0.3, r);
	vec3 c = mix(col_a.rgb, col_b.rgb, clamp(v, 0.0, 1.0));
	ALBEDO = c * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
"

static var _vortex_shader: Shader = null
static var _style_shaders: Dictionary = {}
static var _halo_shader: Shader = null
static var _shock_mesh: TorusMesh = null

var col := Color("#36D5FF")
var style := ""            # "", "alpha", "beta", "gamma": Galaxy Gate'lere ozel korkunc gorunum
var _anim: Array = []      # ozel dekorun her karede oynayan parcalari
var _gamma_eye_mat: StandardMaterial3D = null
var _flicker := 0.0

var _t := 0.0
var _charge := 0.0
var _charge_goal := 0.0
var _since_set := 10.0
var _burst := 0.0
var _spin := 0.0
var _ring_spin := 0.0

var _vortex_mat: ShaderMaterial = null
var _halo_mat: ShaderMaterial = null
var _halo_node: MeshInstance3D = null
var _trim_mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _tick_root: Node3D = null
var _tick_mat: StandardMaterial3D = null
var _mote_mat: StandardMaterial3D = null
var _seg_mats: Array = []
var _motes: Array = []
var _shocks: Array = []


func setup(c: Color, st: String = "") -> JumpGate:
	col = c
	style = st
	_build()
	return self


# ---------------------------------------------------------------- yardimcilar
func _add_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	return m


func _metal(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.85
	m.roughness = rough
	return m


func _place(n: Node3D, ang: float, radius: float, y: float) -> void:
	n.position = Vector3(cos(ang) * radius, y, sin(ang) * radius)
	n.rotation.y = -ang   # yerel +X ekseni disa bakar


func _mesh_node(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _torus(major: float, tube: float, rings: int, segs: int) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = major - tube
	t.outer_radius = major + tube
	t.rings = rings
	t.ring_segments = segs
	return t


func _bone(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = c * 0.22
	return m


# Tabani parent'in orijininde, ucu +Y'ye bakan koni.
func _cone(r: float, h: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	var mi := _mesh_node(cm, mat, parent)
	mi.position.y = h * 0.5
	return mi


# ---------------------------------------------------------------- yapim
func _build() -> void:
	var bright := col.lerp(Color.WHITE, 0.55)

	# zemin parlamasi
	if _halo_shader == null:
		_halo_shader = Shader.new()
		_halo_shader.code = HALO_SHADER
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = _halo_shader
	_halo_mat.set_shader_parameter("col", col)
	var halo_plane := PlaneMesh.new()
	halo_plane.size = Vector2(24.0, 24.0)
	_halo_node = _mesh_node(halo_plane, _halo_mat, self)
	_halo_node.position.y = 0.01

	# girdabin arkasindaki koyu derinlik diski
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	match style:
		"alpha":
			dark.albedo_color = Color(0.0, 0.05, 0.0, 0.72)
		"beta":
			dark.albedo_color = Color(0.07, 0.01, 0.0, 0.72)
		"gamma":
			dark.albedo_color = Color(0.04, 0.0, 0.01, 0.92)
		_:
			dark.albedo_color = Color(0.0, 0.025, 0.07, 0.62)
	var disc := CylinderMesh.new()
	disc.top_radius = 4.9
	disc.bottom_radius = 4.9
	disc.height = 0.01
	disc.radial_segments = 48
	disc.rings = 1
	var dn := _mesh_node(disc, dark, self)
	dn.position.y = 0.04

	# enerji girdabi
	var vcode: String = VORTEX_SHADER
	match style:
		"alpha":
			vcode = VORTEX_ALPHA
		"beta":
			vcode = VORTEX_BETA
		"gamma":
			vcode = VORTEX_GAMMA
	var vsh: Shader = _style_shaders.get(style)
	if vsh == null:
		vsh = Shader.new()
		vsh.code = vcode
		_style_shaders[style] = vsh
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = vsh
	_vortex_mat.set_shader_parameter("col_a", col.darkened(0.35))
	_vortex_mat.set_shader_parameter("col_b", bright)
	var vp := PlaneMesh.new()
	vp.size = Vector2(9.8, 9.8)
	var vn := _mesh_node(vp, _vortex_mat, self)
	vn.position.y = 0.09

	# dis metal cerceve
	var steel_c := Color(0.15, 0.19, 0.26)
	var plate_c := Color(0.30, 0.37, 0.47)
	match style:
		"alpha":
			steel_c = Color(0.07, 0.15, 0.08)
			plate_c = Color(0.16, 0.30, 0.14)
		"beta":
			steel_c = Color(0.20, 0.08, 0.04)
			plate_c = Color(0.38, 0.16, 0.06)
		"gamma":
			steel_c = Color(0.06, 0.02, 0.03)
			plate_c = Color(0.20, 0.04, 0.05)
	var steel := _metal(steel_c, 0.38)
	var plate := _metal(plate_c, 0.25)
	var frame := _mesh_node(_torus(6.0, 0.42, 64, 14), steel, self)
	frame.position.y = 0.32
	frame.scale = Vector3(1.0, 0.7, 1.0)
	var rim_hi := _mesh_node(_torus(6.0, 0.06, 64, 6), _add_mat(Color(bright.r, bright.g, bright.b, 0.5)), self)
	rim_hi.position.y = 0.58

	# ic ince isik halkasi
	_trim_mat = _add_mat(Color(col.r, col.g, col.b, 0.7))
	var trim := _mesh_node(_torus(4.95, 0.05, 64, 6), _trim_mat, self)
	trim.position.y = 0.2

	# 4 ana payanda (kardinal noktalar) + parlayan yarik
	var slit_mat := _add_mat(Color(bright.r, bright.g, bright.b, 0.9))
	for i in 4:
		var a: float = float(i) * PI * 0.5
		var pyl := Node3D.new()
		add_child(pyl)
		_place(pyl, a, 6.15, 0.0)
		var body := BoxMesh.new()
		body.size = Vector3(2.0, 1.15, 2.7)
		var bn := _mesh_node(body, steel, pyl)
		bn.position.y = 0.55
		var cap := BoxMesh.new()
		cap.size = Vector3(1.3, 0.16, 2.1)
		var cn := _mesh_node(cap, plate, pyl)
		cn.position = Vector3(0.1, 1.17, 0.0)
		var slit := BoxMesh.new()
		slit.size = Vector3(0.1, 0.1, 1.9)
		var sn := _mesh_node(slit, slit_mat, pyl)
		sn.position = Vector3(-0.98, 0.7, 0.0)

	# 8 yardimci kelepce
	for i in 8:
		var a2: float = (float(i) + 0.5) * PI * 0.25
		var cl := Node3D.new()
		add_child(cl)
		_place(cl, a2, 6.05, 0.0)
		var cb := BoxMesh.new()
		cb.size = Vector3(1.0, 0.85, 1.35)
		var cbn := _mesh_node(cb, plate, cl)
		cbn.position.y = 0.4

	# kosan isik segmentleri
	for i in SEG:
		var a3: float = float(i) / float(SEG) * TAU
		var sg := BoxMesh.new()
		sg.size = Vector3(0.26, 0.1, 0.95)
		var smat := _add_mat(Color(col.r, col.g, col.b, 0.3))
		var sgn := _mesh_node(sg, smat, self)
		_place(sgn, a3, 5.32, 0.5)
		_seg_mats.append(smat)

	# ters donen isaret halkasi
	_tick_root = Node3D.new()
	_tick_root.position.y = 0.16
	add_child(_tick_root)
	_tick_mat = _add_mat(Color(bright.r, bright.g, bright.b, 0.55))
	for i in TICKS:
		var a4: float = float(i) / float(TICKS) * TAU
		var tk := BoxMesh.new()
		tk.size = Vector3(0.5, 0.06, 0.16)
		var tkn := _mesh_node(tk, _tick_mat, _tick_root)
		_place(tkn, a4, 4.45, 0.0)
	var tring := _mesh_node(_torus(4.45, 0.025, 64, 4), _tick_mat, _tick_root)
	tring.position.y = 0.0

	# girdaba suzulen parcaciklar
	_mote_mat = _add_mat(Color(bright.r, bright.g, bright.b, 0.85))
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 8
	sph.rings = 4
	for i in MOTES:
		var mn := _mesh_node(sph, _mote_mat, self)
		_motes.append({
			"node": mn,
			"ang": randf() * TAU,
			"rad": randf_range(0.6, 5.4),
			"spd": randf_range(0.7, 1.3),
			"dir": 1.0 if (i % 2 == 0) else -1.0,
		})

	# isik
	_light = OmniLight3D.new()
	_light.light_color = col.lerp(Color.WHITE, 0.2)
	_light.omni_range = 18.0
	_light.light_energy = 0.4
	_light.shadow_enabled = false
	_light.position.y = 3.0
	add_child(_light)

	match style:
		"alpha":
			_decor_alpha()
		"beta":
			_decor_beta()
		"gamma":
			_decor_gamma()


# ALFA - ZEHIRLI AGIZ: halkanin ic kenarinda nefes alip veren dis sirasi + disa dogru dikenler
func _decor_alpha() -> void:
	var bone := _bone(Color(0.66, 0.82, 0.46))
	var thorn := _metal(Color(0.05, 0.12, 0.06), 0.4)
	for i in 18:
		var a: float = float(i) / 18.0 * TAU
		var piv := Node3D.new()
		add_child(piv)
		_place(piv, a, 5.55, 0.35)
		var arm := Node3D.new()
		piv.add_child(arm)
		var big: bool = (i % 2 == 0)
		_cone(0.42 if big else 0.28, 2.6 if big else 1.6, bone, arm)
		arm.rotation.z = deg_to_rad(62.0)
		_anim.append({"k": "fang", "node": arm, "ph": float(i) * 0.5})
	for i in 6:
		var a2: float = (float(i) + 0.5) / 6.0 * TAU
		var tp := Node3D.new()
		add_child(tp)
		_place(tp, a2, 6.7, 0.2)
		var ta := Node3D.new()
		tp.add_child(ta)
		ta.rotation.z = deg_to_rad(-28.0)
		_cone(0.5, 3.4, thorn, ta)


# BETA - CEHENNEM GOZU: egri boynuzlar + titreyen alev sutunlari
func _decor_beta() -> void:
	var horn := _metal(Color(0.12, 0.05, 0.04), 0.45)
	var flame_mat := _add_mat(Color(1.0, 0.45, 0.08, 0.55))
	var flame_core := _add_mat(Color(1.0, 0.85, 0.35, 0.6))
	for i in 6:
		var a: float = (float(i) + 0.25) / 6.0 * TAU
		var piv := Node3D.new()
		add_child(piv)
		_place(piv, a, 6.5, 0.2)
		var arm1 := Node3D.new()
		piv.add_child(arm1)
		arm1.rotation.z = deg_to_rad(-20.0)
		_cone(0.62, 2.6, horn, arm1)
		var arm2 := Node3D.new()
		arm1.add_child(arm2)
		arm2.position.y = 2.6
		arm2.rotation.z = deg_to_rad(52.0)
		_cone(0.4, 2.0, horn, arm2)
	for i in 14:
		var a2: float = float(i) / 14.0 * TAU
		var fp := Node3D.new()
		add_child(fp)
		_place(fp, a2, 6.9, 0.0)
		_cone(0.55, 2.4, flame_mat, fp)
		_cone(0.26, 1.5, flame_core, fp)
		_anim.append({"k": "flame", "node": fp, "ph": randf() * TAU})


# GAMMA - KAN YARIGI: halkanin etrafinda yukari bakan, kirmizi gozlu 8 kafatasi + uzun kemik dikenler
func _decor_gamma() -> void:
	var bone := _bone(Color(0.80, 0.76, 0.66))
	var hole := StandardMaterial3D.new()
	hole.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole.albedo_color = Color(0.0, 0.0, 0.0)
	_gamma_eye_mat = _add_mat(Color(1.0, 0.08, 0.05, 0.95))
	var spike := _metal(Color(0.10, 0.02, 0.03), 0.4)
	for i in 8:
		var a: float = float(i) / 8.0 * TAU
		var piv := Node3D.new()
		add_child(piv)
		_place(piv, a, 6.7, 0.5)
		var sk := Node3D.new()
		sk.position = Vector3(0.0, 0.7, 0.0)
		piv.add_child(sk)
		var cr := SphereMesh.new()
		cr.radius = 0.95
		cr.height = 1.8
		cr.radial_segments = 16
		cr.rings = 8
		var crn := _mesh_node(cr, bone, sk)
		crn.scale = Vector3(1.0, 0.95, 0.9)
		var jaw := BoxMesh.new()
		jaw.size = Vector3(0.9, 0.35, 0.9)
		var jn := _mesh_node(jaw, bone, sk)
		jn.position = Vector3(0.85, -0.2, 0.0)
		var nose := BoxMesh.new()
		nose.size = Vector3(0.25, 0.1, 0.22)
		var nn := _mesh_node(nose, hole, sk)
		nn.position = Vector3(0.55, 0.62, 0.0)
		for sgn in [-1.0, 1.0]:
			var eye := SphereMesh.new()
			eye.radius = 0.3
			eye.height = 0.6
			eye.radial_segments = 10
			eye.rings = 5
			var en := _mesh_node(eye, hole, sk)
			en.position = Vector3(0.2, 0.7, 0.42 * float(sgn))
			var gl := SphereMesh.new()
			gl.radius = 0.15
			gl.height = 0.3
			gl.radial_segments = 8
			gl.rings = 4
			var gn := _mesh_node(gl, _gamma_eye_mat, sk)
			gn.position = Vector3(0.2, 0.86, 0.42 * float(sgn))
		_anim.append({"k": "skull", "node": sk, "ph": float(i) * 0.9})
	for i in 8:
		var a2: float = (float(i) + 0.5) / 8.0 * TAU
		var sp := Node3D.new()
		add_child(sp)
		_place(sp, a2, 6.5, 0.2)
		var sa := Node3D.new()
		sp.add_child(sa)
		sa.rotation.z = deg_to_rad(-32.0)
		_cone(0.36, 3.8, spike, sa)


# ---------------------------------------------------------------- disaridan kullanim
func set_charge(v: float) -> void:
	_charge_goal = clampf(v, 0.0, 1.0)
	_since_set = 0.0


func burst(strength: float = 1.0) -> void:
	_burst = maxf(_burst, clampf(strength, 0.0, 1.0))
	if _shock_mesh == null:
		_shock_mesh = TorusMesh.new()
		_shock_mesh.inner_radius = 0.47
		_shock_mesh.outer_radius = 0.5
		_shock_mesh.rings = 64
		_shock_mesh.ring_segments = 6
	var n := 3 if strength > 0.6 else 1
	for i in n:
		var mt := _add_mat(Color(col.r, col.g, col.b, 0.0))
		var mi := _mesh_node(_shock_mesh, mt, self)
		mi.position.y = 0.3
		mi.scale = Vector3.ONE * 10.0
		mi.visible = false
		_shocks.append({"node": mi, "mat": mt, "t": -0.18 * float(i), "life": 0.85, "pow": strength})


# ---------------------------------------------------------------- animasyon
func _animate_decor(dt: float, c: float, b: float) -> void:
	for d in _anim:
		var nd: Node3D = d.node
		if nd == null or not is_instance_valid(nd):
			continue
		var ph: float = float(d.ph)
		match str(d.k):
			"fang":
				nd.rotation.z = deg_to_rad(58.0 + 20.0 * sin(_t * (1.4 + 2.2 * c) + ph) - 12.0 * b)
			"flame":
				nd.scale = Vector3(1.0, (0.55 + 0.75 * absf(sin(_t * 5.0 + ph))) * (1.0 + 0.8 * c + 0.6 * b), 1.0)
			"skull":
				nd.position.y = 0.7 + 0.14 * sin(_t * 2.0 + ph)
				nd.rotation.y = 0.18 * sin(_t * 1.3 + ph)
	if style == "gamma":
		if _gamma_eye_mat != null:
			_gamma_eye_mat.albedo_color.a = clampf(0.65 + 0.35 * sin(_t * 4.0) + 0.3 * c, 0.0, 1.0)
		if randf() < 0.03:
			_flicker = 1.0
		_flicker = maxf(0.0, _flicker - dt * 6.0)
		_light.light_energy += _flicker * 2.5
	elif style == "alpha":
		_light.light_energy += 0.15 * sin(_t * 1.5)


func _process(dt: float) -> void:
	if _vortex_mat == null:
		return
	dt = minf(dt, 0.05)
	_t += dt
	_since_set += dt

	var goal: float = _charge_goal if _since_set < 0.25 else 0.0
	_charge = move_toward(_charge, goal, dt * (3.0 if goal > _charge else 1.2))
	_burst = maxf(0.0, _burst - dt * 1.5)
	var c: float = _charge
	var b: float = _burst

	_spin += dt * (0.8 + 7.0 * c + 6.0 * b)
	_ring_spin += dt * (0.25 + 1.8 * c)
	_tick_root.rotation.y = -_ring_spin

	var pulse: float = 0.5 + 0.5 * sin(_t * 2.1)
	_vortex_mat.set_shader_parameter("phase", _spin)
	_vortex_mat.set_shader_parameter("energy", 0.72 + 0.12 * pulse + 1.0 * c + 0.9 * b)
	_vortex_mat.set_shader_parameter("flash", b * 1.6)

	_halo_mat.set_shader_parameter("energy", 0.55 + 0.15 * pulse + 0.5 * c + 0.9 * b)
	_halo_node.scale = Vector3.ONE * (1.0 + 0.1 * c + 0.25 * b)

	var hot: Color = col.lerp(Color.WHITE, clampf(0.3 * c + 0.5 * b, 0.0, 1.0))
	var chase: float = 0.4 + 1.6 * c
	for i in _seg_mats.size():
		var w: float = 0.5 + 0.5 * cos(TAU * (float(i) / float(SEG) * 3.0 - _t * chase))
		var inten: float = 0.16 + 0.84 * pow(w, 3.0) * (0.6 + 0.4 * c) + 0.5 * b
		var sm: StandardMaterial3D = _seg_mats[i]
		sm.albedo_color = Color(hot.r, hot.g, hot.b, clampf(inten, 0.0, 1.0))

	_trim_mat.albedo_color.a = clampf(0.5 + 0.2 * pulse + 0.35 * c + 0.4 * b, 0.0, 1.0)
	_tick_mat.albedo_color.a = clampf(0.4 + 0.4 * c + 0.3 * b, 0.0, 1.0)
	_light.light_energy = 0.35 + 0.8 * c + 1.6 * b + 0.1 * pulse
	_animate_decor(dt, c, b)

	# parcaciklar: girdaba dogru sarmal cizerek akar; sarj arttikca hizlanir ve cogalir
	var shown: int = 6 + int(c * float(MOTES - 6)) + int(b * 6.0)
	for i in _motes.size():
		var m: Dictionary = _motes[i]
		var mn: MeshInstance3D = m.node
		if i >= shown:
			mn.visible = false
			continue
		mn.visible = true
		var rad: float = float(m.rad) - dt * (0.45 + 4.5 * c) * float(m.spd)
		var ang: float = float(m.ang) + dt * float(m.dir) * (0.6 + 3.5 * (1.1 - clampf(rad / 6.0, 0.0, 1.0))) * (1.0 + 2.0 * c)
		if rad < 0.4:
			rad = 5.4
			ang = randf() * TAU
		m.rad = rad
		m.ang = ang
		mn.position = Vector3(cos(ang) * rad, 0.35 + 0.2 * sin(_t * 3.0 + float(i)), sin(ang) * rad)
		mn.scale = Vector3.ONE * (0.12 + 0.14 * clampf(rad / 5.0, 0.0, 1.0)) * (1.0 + 0.5 * c)

	# sok dalgasi halkalari
	for i in range(_shocks.size() - 1, -1, -1):
		var s: Dictionary = _shocks[i]
		s.t = float(s.t) + dt
		var sn: MeshInstance3D = s.node
		if float(s.t) < 0.0:
			continue
		var k: float = float(s.t) / float(s.life)
		if k >= 1.0:
			sn.queue_free()
			_shocks.remove_at(i)
			continue
		sn.visible = true
		sn.scale = Vector3.ONE * lerpf(10.0, 27.0, 1.0 - pow(1.0 - k, 2.0))
		var sm2: StandardMaterial3D = s.mat
		sm2.albedo_color = Color(hot.r, hot.g, hot.b, 0.85 * float(s.pow) * pow(1.0 - k, 1.5))
