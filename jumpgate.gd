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

static var _vortex_shader: Shader = null
static var _halo_shader: Shader = null
static var _shock_mesh: TorusMesh = null

var col := Color("#36D5FF")

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


func setup(c: Color) -> JumpGate:
	col = c
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
	if _vortex_shader == null:
		_vortex_shader = Shader.new()
		_vortex_shader.code = VORTEX_SHADER
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = _vortex_shader
	_vortex_mat.set_shader_parameter("col_a", col.darkened(0.35))
	_vortex_mat.set_shader_parameter("col_b", bright)
	var vp := PlaneMesh.new()
	vp.size = Vector2(9.8, 9.8)
	var vn := _mesh_node(vp, _vortex_mat, self)
	vn.position.y = 0.09

	# dis metal cerceve
	var steel := _metal(Color(0.15, 0.19, 0.26), 0.38)
	var plate := _metal(Color(0.30, 0.37, 0.47), 0.25)
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
