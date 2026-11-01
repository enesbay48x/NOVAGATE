extends RefCounted
# Droid dizilimleri. Koordinatlar GERCEK DarkOrbit formasyon ikonlarindan olculdu (market ekran goruntusu).
# (u, f): u = yana (+sag), f = ileri (+gemi onu). 1.0 = standart halkanin yaricapi. Gemi (0,0)'dadir.
# Daha az droid varsa gemiye en yakin noktalar once kullanilir (listeler yakindan uzaga siralidir).

# Elmasin geminin ONUNDE degil ARKASINDA durmasi gerekir; oyunda onde gorunurse true yap.
const STD_DIAMOND_FRONT := false

# Dizilim anahtari -> res://assets/hud/items/drone_formation_<ad>.png (gercek oyun ikonlari)
const ICONS := {
	"std": "default", "turtle": "f-01-tu", "arrow": "f-02-ar", "lance": "f-03-la", "star": "f-04-st",
	"pincer": "f-05-pi", "double": "f-06-da", "diamond": "f-07-di", "chevron": "f-08-ch",
	"moth": "f-09-mo", "crab": "f-10-cr", "heart": "f-11-he", "barrage": "f-12-ba",
}

static func key_for(code: String, fd) -> String:
	var nm := code
	if typeof(fd) == TYPE_DICTIONARY and fd.has("name"):
		nm = str(fd["name"])
	nm = nm.to_lower().strip_edges()
	if nm.begins_with("standart") or nm.begins_with("standard"):
		return "std"   # gercek DarkOrbit standart dizilimi (asagida)
	if nm.begins_with("kaplumba") or nm.begins_with("turtle"):
		return "turtle"
	if nm == "ok" or nm.begins_with("arrow"):
		return "arrow"
	if nm.begins_with("m\u0131zrak") or nm.begins_with("lance"):
		return "lance"
	if nm.begins_with("y\u0131ld\u0131z") or nm.begins_with("star"):
		return "star"
	if nm.begins_with("k\u0131ska\u00e7") or nm.begins_with("pincer"):
		return "pincer"
	if nm.begins_with("\u00e7ift") or nm.begins_with("double"):
		return "double"
	if nm.begins_with("elmas") or nm.begins_with("diamond"):
		return "diamond"
	if nm.begins_with("\u015fevron") or nm.begins_with("chevron"):
		return "chevron"
	if nm.begins_with("g\u00fcve") or nm.begins_with("moth"):
		return "moth"
	if nm.begins_with("yenge") or nm.begins_with("crab"):
		return "crab"
	if nm.begins_with("kalp") or nm.begins_with("heart"):
		return "heart"
	if nm.begins_with("baraj") or nm.begins_with("barrage"):
		return "barrage"
	return ""


static func points(key: String, n: int) -> Array:
	var base: Array = _full(key)
	var out: Array = []
	for i in n:
		var p: Vector2 = base[i % base.size()]
		out.append(p * (1.0 + 0.3 * float(i / base.size())))
	return out


static func _full(key: String) -> Array:
	var l: Array = []
	match key:
		"std":
			# GERCEK DarkOrbit standart dizilimi (10 droid): yanlarda iki ucgen (3+3) + gemi arkasinda elmas (4)
			l = [Vector2(0.00, -0.85), Vector2(-0.93, -0.16), Vector2(0.93, -0.16), Vector2(-0.93, 0.29), Vector2(0.93, 0.29), Vector2(-0.23, -1.11), Vector2(0.23, -1.11), Vector2(-1.16, 0.06), Vector2(1.16, 0.06), Vector2(0.00, -1.34)]
			if STD_DIAMOND_FRONT:
				for i in l.size():
					l[i] = Vector2(l[i].x, -l[i].y)
		"turtle":
			l = [Vector2(-0.67, 0.29), Vector2(0.67, 0.29), Vector2(-0.37, 0.65), Vector2(0.37, 0.65), Vector2(-0.67, -0.46), Vector2(0.67, -0.46), Vector2(-0.35, -0.85), Vector2(0.35, -0.85), Vector2(-0.98, -0.10), Vector2(0.98, -0.10)]
		"arrow":
			l = [Vector2(-0.50, 0.25), Vector2(0.50, 0.25), Vector2(-0.29, 0.63), Vector2(0.29, 0.63), Vector2(-0.74, -0.09), Vector2(0.74, -0.09), Vector2(-0.96, -0.46), Vector2(0.96, -0.46), Vector2(-1.16, -0.84), Vector2(1.16, -0.84)]
		"lance":
			l = [Vector2(-0.76, -0.13), Vector2(0.76, -0.13), Vector2(-0.75, 0.25), Vector2(0.75, 0.25), Vector2(-0.75, -0.53), Vector2(0.75, -0.53), Vector2(-0.76, 0.65), Vector2(0.76, 0.65), Vector2(-0.79, -0.91), Vector2(0.79, -0.91)]
		"star":
			l = [Vector2(-0.46, 0.43), Vector2(0.46, 0.43), Vector2(-0.59, -0.32), Vector2(0.59, -0.32), Vector2(0.00, -0.77), Vector2(-0.94, -0.32), Vector2(0.94, -0.32), Vector2(-0.75, 0.70), Vector2(0.75, 0.70), Vector2(0.00, -1.05)]
		"pincer":
			l = [Vector2(-0.60, -0.31), Vector2(0.60, -0.31), Vector2(-0.64, -0.77), Vector2(0.64, -0.77), Vector2(-1.02, 0.15), Vector2(1.02, 0.15), Vector2(-1.03, -0.32), Vector2(1.03, -0.32), Vector2(-1.03, 0.65), Vector2(1.03, 0.65)]
		"double":
			l = [Vector2(-0.38, -0.55), Vector2(0.38, -0.55), Vector2(-0.67, -0.16), Vector2(0.67, -0.16), Vector2(-0.87, 0.25), Vector2(0.87, 0.25), Vector2(-1.16, -0.16), Vector2(1.16, -0.16), Vector2(-1.37, -0.56), Vector2(1.37, -0.56)]
		"diamond":
			l = [Vector2(0.00, 0.65), Vector2(-0.69, -0.13), Vector2(0.69, -0.13), Vector2(-0.69, 0.31), Vector2(0.69, 0.31), Vector2(-0.69, -0.59), Vector2(0.69, -0.59), Vector2(0.00, -0.96), Vector2(-1.10, -0.14), Vector2(1.10, -0.14)]
		"chevron":
			l = [Vector2(-0.38, 0.42), Vector2(0.38, 0.42), Vector2(0.00, -0.64), Vector2(0.00, 0.72), Vector2(-0.74, 0.07), Vector2(0.74, 0.07), Vector2(-0.34, -0.94), Vector2(0.34, -0.94), Vector2(-1.10, -0.24), Vector2(1.10, -0.24)]
		"moth":
			l = [Vector2(-0.68, 0.18), Vector2(0.68, 0.18), Vector2(-0.43, -0.69), Vector2(0.43, -0.69), Vector2(-0.97, 0.59), Vector2(0.97, 0.59), Vector2(-1.24, 0.18), Vector2(1.24, 0.18), Vector2(-0.79, -0.99), Vector2(0.79, -0.99)]
		"crab":
			l = [Vector2(-0.49, -0.45), Vector2(0.49, -0.45), Vector2(-0.61, 0.33), Vector2(0.61, 0.33), Vector2(-0.86, -0.06), Vector2(0.86, -0.06), Vector2(-0.87, 0.70), Vector2(0.87, 0.70), Vector2(-0.69, 1.10), Vector2(0.69, 1.10)]
		"heart":
			l = [Vector2(0.00, 0.60), Vector2(-0.47, -0.52), Vector2(0.47, -0.52), Vector2(-0.74, -0.12), Vector2(0.74, -0.12), Vector2(-0.52, 0.73), Vector2(0.52, 0.73), Vector2(0.00, -1.00), Vector2(-1.02, 0.31), Vector2(1.02, 0.31)]
		"barrage":
			l = [Vector2(-0.50, 0.56), Vector2(0.50, 0.56), Vector2(-0.25, 0.88), Vector2(0.25, 0.88), Vector2(-1.03, 0.56), Vector2(-0.77, 0.88), Vector2(0.77, 0.88), Vector2(1.03, 0.56), Vector2(-1.28, 0.88), Vector2(1.28, 0.88)]
		_:
			l = [Vector2(0.0, 1.0)]
	return l
