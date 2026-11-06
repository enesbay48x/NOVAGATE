extends Control
# Rütbe rozetinin ÜSTÜNDE görünen Galaxy Gate halkaları.
#  * Her kapıyı (Alfa / Beta / Gamma) ilk bitiren oyuncu 1 halka kazanır, en fazla 3 halka olur.
#  * 1-2 halka: açık mavi/gümüş. 3 halka (3 kapının üçü de): ALTIN renk.
# Kullanım: rozet TextureRect'inin çocuğu olarak eklenir (main.gd -> _apply_rank_rings).

const GOLD := Color(1.0, 0.82, 0.2)
const SILVER := Color(0.72, 0.88, 1.0)
const RADIUS := 2.0
const GAP := 1.0

var rings: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(11.0, 5.0)
	position = Vector2(0.0, -5.0)   # rozetin hemen üstü


func set_rings(n: int) -> void:
	var v: int = clampi(n, 0, 3)
	if v == rings:
		return
	rings = v
	queue_redraw()


func _draw() -> void:
	if rings <= 0:
		return
	var col: Color = GOLD if rings >= 3 else SILVER
	var total: float = float(rings) * RADIUS * 2.0 + float(rings - 1) * GAP
	var x: float = (size.x - total) * 0.5 + RADIUS
	var y: float = size.y * 0.5
	for i in rings:
		draw_arc(Vector2(x, y), RADIUS, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.85), 2.4, true)
		draw_arc(Vector2(x, y), RADIUS, 0.0, TAU, 16, col, 1.3, true)
		x += RADIUS * 2.0 + GAP
