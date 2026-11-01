extends RefCounted
# DarkOrbit tarzi lazer duzeni + SAB halkalari.
#  - Salvo 2 (az lazer) veya 4 (cok lazer) paralel atisla cikar; tum atislar ayni hizda ve ayni stilde duz ilerler.
#  - SAB: dusmandan sana dogru kuculerek gelen mavi halkalar.
# main.gd'ye tools/hud_lazer_kur.gd ile baglanir.

const BOLTS_FEW := 2
const BOLTS_MANY := 4
const MANY_FROM := 7          # bu kadar veya daha fazla lazer varsa 4'lu atis
const RING_COUNT := 3
const RING_TIME := 0.6


# Gorunen atis listesini 1 / 2 / 4 atisa indirir. vis: hasara gore buyukten kucuge sirali lazer idleri.
# Hepsi en guclu lazerin stilini kullanir: boylece hiz ve gorunum ayni, atislar paralel ve duzenli gider.
# Toplam hasar bozulmaz (main.gd hasari gorunen atislara bolusturuyor).
static func pick(vis: Array) -> Array:
	var n := vis.size()
	if n <= 1:
		return vis
	var count := BOLTS_FEW if n < MANY_FROM else BOLTS_MANY
	var lead = vis[0]
	var out: Array = []
	for i in count:
		out.append(lead)
	return out


# Yanal konum: 2 atis = bir cift, 4 atis = iki cift.
static func lat(j: int, n: int) -> float:
	if n <= 1:
		return 0.0
	if n == 2:
		return -0.7 if j == 0 else 0.7
	var t := [-1.7, -0.55, 0.55, 1.7]
	return float(t[clampi(j, 0, 3)])


# fire_bolt'tan hemen sonra cagrilir: son mermiyi paralel ucus icin isaretler (hedef + yanal sapma noktasina gider).
static func mark_parallel(g, off: Vector3) -> void:
	if g.bullets.is_empty():
		return
	var b = g.bullets[g.bullets.size() - 1]
	b["off"] = off
	if is_instance_valid(b.node) and g.has_method("_fx_sphere"):
		g._fx_sphere(b.node.position, b.col, 0.25, 0.9, 0.1, 0.9)


# SAB: dusmandan oyuncuya kuculerek giden halkalar. Salvo basina bir kez (0.4 sn kilidi).
static func sab_ring(g, e, _amount: float) -> void:
	if g.world == null or g.P == null or not is_instance_valid(e.node) or not is_instance_valid(g.P.node):
		return
	if not g.is_inside_tree():
		return
	var now: float = g.clock
	if now - float(g.get_meta("sab_t", -10.0)) < 0.4:
		return
	g.set_meta("sab_t", now)
	var src: Node3D = e.node
	var r0: float = float(src.get_meta("r", 3.0)) * 1.3
	for k in RING_COUNT:
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mt.albedo_color = Color(0.45, 0.78, 1.0, 0.0)
		var tm := TorusMesh.new()
		tm.inner_radius = 0.44
		tm.outer_radius = 0.5
		tm.rings = 32
		tm.ring_segments = 8
		var ring := MeshInstance3D.new()
		ring.mesh = tm
		ring.material_override = mt
		ring.position = src.position + Vector3(0.0, 0.5, 0.0)
		ring.scale = Vector3.ONE * r0 * 2.0
		g.world.add_child(ring)
		var tw: Tween = g.create_tween()
		if k > 0:
			tw.tween_interval(0.12 * float(k))
		tw.tween_method(func(t: float) -> void: _ring_step(g, ring, mt, src, r0, t), 0.0, 1.0, RING_TIME)
		tw.tween_callback(func() -> void: _ring_end(g, ring, k))


static func _ring_step(g, ring: MeshInstance3D, mt: StandardMaterial3D, src: Node3D, r0: float, t: float) -> void:
	if not is_instance_valid(ring) or g.P == null or not is_instance_valid(g.P.node):
		return
	var from := ring.position
	if is_instance_valid(src):
		from = src.position + Vector3(0.0, 0.5, 0.0)
	var to: Vector3 = g.P.node.position + Vector3(0.0, 0.5, 0.0)
	var e := t * t * (3.0 - 2.0 * t)
	ring.position = from.lerp(to, e)
	ring.scale = Vector3.ONE * lerpf(r0 * 2.0, 0.7, e)
	mt.albedo_color.a = 0.85 * sin(clampf(t, 0.0, 1.0) * PI) + 0.1


static func _ring_end(g, ring: MeshInstance3D, k: int) -> void:
	if is_instance_valid(ring):
		ring.queue_free()
	if k == RING_COUNT - 1 and g.P != null and is_instance_valid(g.P.node) and g.extras != null:
		g.extras.hit_fx()
