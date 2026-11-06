extends Control
const DOData = preload("res://data.gd")
const MapBg = preload("res://map_bg.gd")
# DarkOrbit tarzi minimap penceresi:
#  - ustte harita adi + gemi koordinati (baslik seridi)
#  - harita resmi, gemi (beyaz ok), dusmanlar (kirmizi), kapilar (kapi ikonu), ust (yesil kare)
#  - altta dusman / kapi sayaci seridi
#  - sol tik / surukle = gemiyi oraya gonder

signal move_requested(wx: float, wz: float)   # Godot birimi cinsinden dunya konumu

const PAD := 0.0
const HEAD := 0.0
const FOOT := 18.0
const IMG_W := 210.0

var game = null            # main.gd (Variant: dinamik erisim)
var title_win = null       # pencere cercevesi (baslikta harita adi + koordinat)
var tex: Texture2D = null
var gate_tex: Texture2D = null
var map_name := ""
var map_w := 21000.0       # DO birimi
var map_h := 13100.0
var img_h := 131.0

const REDRAW_HZ := 12.0
var _redraw_acc := 0.0


# ---- KOORDINAT IZGARASI (PC minimap + mobil buyuk harita ortak kullanir) ----
# 8 sutun (1-8) x 6 satir (A-F). Hucre adlari (A1..F8) hucre ortasinda SEFFAF yazilir,
# hucre kose kesisimlerinde kucuk "+" isaretleri, gemi konumundan gecen ince capraz cizgiler cizilir.
const GRID_COLS := 8
const GRID_ROWS := 6


static func sector_name(nx: float, nz: float) -> String:
	var c: int = clampi(int(nx * float(GRID_COLS)), 0, GRID_COLS - 1) + 1
	var r: int = clampi(int(nz * float(GRID_ROWS)), 0, GRID_ROWS - 1)
	return "%s%d" % [char(65 + r), c]


# ci: cizim yapan CanvasItem (kendi _draw'i icinde cagrilmali), rc: harita dikdortgeni,
# ship: gemi konumu (rc icinde piksel) - (-1,-1) verilirse capraz cizgi cizilmez.
static func draw_coord_grid(ci: CanvasItem, rc: Rect2, font: Font, fs: int, ship: Vector2 = Vector2(-1.0, -1.0), cur_sector: String = "") -> void:
	var cw: float = rc.size.x / float(GRID_COLS)
	var ch: float = rc.size.y / float(GRID_ROWS)
	var line_col := Color(0.4, 0.7, 0.9, 0.10)
	for i in range(1, GRID_COLS):
		var gx: float = rc.position.x + cw * float(i)
		ci.draw_line(Vector2(gx, rc.position.y), Vector2(gx, rc.end.y), line_col, 1.0)
	for j in range(1, GRID_ROWS):
		var gy: float = rc.position.y + ch * float(j)
		ci.draw_line(Vector2(rc.position.x, gy), Vector2(rc.end.x, gy), line_col, 1.0)
	# kesisim "+" isaretleri
	var arm: float = clampf(minf(cw, ch) * 0.12, 1.5, 6.0)
	var plus_col := Color(0.7, 0.9, 1.0, 0.28)
	for j in range(1, GRID_ROWS):
		for i in range(1, GRID_COLS):
			var q := Vector2(rc.position.x + cw * float(i), rc.position.y + ch * float(j))
			ci.draw_line(q - Vector2(arm, 0.0), q + Vector2(arm, 0.0), plus_col, 1.0)
			ci.draw_line(q - Vector2(0.0, arm), q + Vector2(0.0, arm), plus_col, 1.0)
	# seffaf hucre adlari (gemi hangi hucredeyse biraz daha belirgin)
	if font != null:
		for j in GRID_ROWS:
			for i in GRID_COLS:
				var lab := "%s%d" % [char(65 + j), i + 1]
				var a: float = 0.55 if lab == cur_sector else 0.20
				var base := Vector2(rc.position.x + cw * float(i), rc.position.y + ch * float(j) + ch * 0.5 + float(fs) * 0.36)
				ci.draw_string(font, base, lab, HORIZONTAL_ALIGNMENT_CENTER, cw, fs, Color(0.75, 0.9, 1.0, a))
	# gemi konumundan gecen capraz cizgiler
	if ship.x >= rc.position.x and ship.x <= rc.end.x and ship.y >= rc.position.y and ship.y <= rc.end.y:
		var cc := Color(1.0, 1.0, 1.0, 0.30)
		ci.draw_line(Vector2(rc.position.x, ship.y), Vector2(rc.end.x, ship.y), cc, 1.0)
		ci.draw_line(Vector2(ship.x, rc.position.y), Vector2(ship.x, rc.end.y), cc, 1.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(dt: float) -> void:
	if not visible or game == null or not game.running or game.P == null:
		return
	_redraw_acc += dt
	if _redraw_acc < 1.0 / REDRAW_HZ:
		return
	_redraw_acc = 0.0
	queue_redraw()


var _font: SystemFont = null


func _get_font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Verdana", "Tahoma", "Segoe UI", "Arial"])
	return _font


func panel_size() -> Vector2:
	return Vector2(IMG_W, img_h + FOOT)


func set_map(n: String, w: float, h: float, t: Texture2D) -> void:
	map_name = n
	map_w = w
	map_h = h
	tex = t
	img_h = IMG_W * h / w
	if gate_tex == null and game != null:
		gate_tex = game._tex("res://assets/hud/win/mk_gate.png")
	queue_redraw()


func _g2m(p: Vector3) -> Vector2:
	return Vector2(PAD + p.x / (map_w * DOData.S) * IMG_W, HEAD + p.z / (map_h * DOData.S) * img_h)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_emit_move(mb.position)
			accept_event()
		return
	var mo := event as InputEventMouseMotion
	if mo != null and (mo.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_emit_move(mo.position)
		accept_event()


func _emit_move(local: Vector2) -> void:
	var nx := clampf((local.x - PAD) / IMG_W, 0.0, 1.0)
	var nz := clampf((local.y - HEAD) / img_h, 0.0, 1.0)
	move_requested.emit(nx * map_w * DOData.S, nz * map_h * DOData.S)


func _draw() -> void:
	if game == null or game.P == null or not is_instance_valid(game.P.node):
		return
	var sz := panel_size()
	var font: Font = _get_font()
	var img_rect := Rect2(PAD, HEAD + 0.0, IMG_W, img_h)
	var pp: Vector3 = game.P.node.position
	var coord := "%s  %d / %d" % [sector_name(pp.x / (map_w * DOData.S), pp.z / (map_h * DOData.S)), int(pp.x / DOData.S), int(pp.z / DOData.S)]
	if title_win != null and (title_win.title != map_name or title_win.subtitle != coord):
		title_win.title = map_name
		title_win.subtitle = coord
		title_win.queue_redraw()

	# Arka plan: duz siyah (harita resmi cizilmez)
	draw_rect(img_rect, Color(0.0, 0.0, 0.0, 1.0))
	# Koordinat izgarasi (8x6, A1..F8, seffaf adlar + gemi capraz cizgileri)
	var my_sp := _g2m(pp)
	var my_sec: String = sector_name(pp.x / (map_w * DOData.S), pp.z / (map_h * DOData.S))
	draw_coord_grid(self, img_rect, font, clampi(int(IMG_W / 20.0), 8, 12), my_sp, my_sec)
	draw_rect(img_rect, Color(0.45, 0.7, 0.85, 0.85), false, 1.0)

	# Ust + guvenli bolge
	if game.base_pos != null:
		var bp := _g2m(game.base_pos)
		var rr: float = DOData.SAFE_RADIUS / map_w * IMG_W
		draw_arc(bp, rr, 0.0, TAU, 28, Color(0.4, 1.0, 0.55, 0.45), 1.0)
		draw_rect(Rect2(bp - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 1.0, 0.55))
		draw_rect(Rect2(bp - Vector2(4, 4), Vector2(8, 8)), Color(0, 0.25, 0.1), false, 1.0)

	# Kapilar
	for p in game.portals:
		var c := _g2m(p.pos)
		if gate_tex != null:
			draw_texture(gate_tex, c - gate_tex.get_size() * 0.5)
		else:
			draw_arc(c, 4.5, 0.0, TAU, 16, Color(0.3, 0.95, 1.0), 1.6)

	# Galaxy Gate kapilari: yalnizca AKTIF edilmis olanlar gorunur (aktif edilene kadar mini haritada yok)
	var n_gg := 0
	for gs in game.gg_sites:
		if not game._gate_site_active(str(gs.gate)):
			continue
		n_gg += 1
		var gc := _g2m(gs.pos)
		var gcol: Color = game.GATE_SITE_COLORS.get(str(gs.gate), Color(0.3, 0.95, 1.0))
		if gate_tex != null:
			draw_texture(gate_tex, gc - gate_tex.get_size() * 0.5)
		draw_arc(gc, 7.0, 0.0, TAU, 20, gcol, 1.6)

	# Gorus menzili siniri: yalnizca bu daire icindeki dusmanlar gorunur (zoom'dan etkilenmez)
	var vis_do: float = MapBg.vision_do()
	# (menzil dairesi artik cizilmez; gorus menzili gorunmez, yalnizca menzildeki dusmanlar gosterilir)

	# Dusmanlar (yalnizca menzildekiler)
	var lim: float = vis_do * DOData.S
	var n_en := 0
	for e in game.enemies:
		if not is_instance_valid(e.node):
			continue
		if Vector2(e.node.position.x - pp.x, e.node.position.z - pp.z).length() > lim:
			continue
		n_en += 1
		var ep := _g2m(e.node.position)
		var col := Color(1.0, 0.25, 0.25)
		if e.aggro and not bool(e.get("player", false)):
			col = Color(1.0, 0.55, 0.1)   # NPC saldirgan = turuncu; dusman OYUNCU her zaman kirmizi
		draw_rect(Rect2(ep - Vector2(1.5, 1.5), Vector2(3, 3)), col)
	# Ayni sirketten yakindaki oyuncular: BEYAZ
	if Net.online and Net.gm != null:
		for fe in Net.gm.players.values():
			if not bool(fe.get("friendly", false)) or not is_instance_valid(fe.node):
				continue
			if Vector2(fe.node.position.x - pp.x, fe.node.position.z - pp.z).length() > lim:
				continue
			var fp := _g2m(fe.node.position)
			draw_rect(Rect2(fp - Vector2(2.0, 2.0), Vector2(4, 4)), Color(1, 1, 1))

	# Klan uyeleri: YESIL NOKTA (haritadaki tum klan arkadaslari; menzil siniri yok)
	var n_clan := 0
	if Net.online and Net.gm != null and Net.gm.clan != null and Net.gm.clan.in_clan():
		for ce in Net.gm.players.values():
			if not is_instance_valid(ce.node) or not Net.gm.clan.is_clanmate(int(ce.get("peer", 0))):
				continue
			var cp := _g2m(ce.node.position)
			draw_circle(cp, 3.4, Color(0.15, 1.0, 0.3))
			draw_arc(cp, 3.4, 0.0, TAU, 14, Color(0.0, 0.3, 0.08), 1.0)
			n_clan += 1

	# Hedef
	if game.target != null and is_instance_valid(game.target.node):
		var tp := _g2m(game.target.node.position)
		draw_arc(tp, 5.0, 0.0, TAU, 14, Color(1.0, 0.95, 0.3), 1.4)

	# Gidilecek nokta
	if game.dest != null:
		var dp := _g2m(game.dest)
		draw_arc(dp, 3.0, 0.0, TAU, 12, Color(0.4, 1.0, 0.4), 1.2)

	# Kamera gorus kutusu
	var vr: Rect2 = game.view_rect
	if vr.size.x > 0.0:
		var a := _g2m(Vector3(vr.position.x, 0.0, vr.position.y))
		var b := _g2m(Vector3(vr.end.x, 0.0, vr.end.y))
		var box := Rect2(a, b - a).intersection(img_rect)
		if box.size.x > 0.0 and box.size.y > 0.0:
			draw_rect(box, Color(1, 1, 1, 0.5), false, 1.0)

	# Gemi (beyaz ok)
	var sp := _g2m(pp)
	var yaw: float = game.P.node.rotation.y
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var tip := sp + fwd * 6.0
	var l := sp - fwd * 3.0 + side * 3.5
	var r := sp - fwd * 3.0 - side * 3.5
	draw_colored_polygon(PackedVector2Array([tip, l, sp - fwd * 1.2, r]), Color(1, 1, 1))

	# Alt serit: sayaclar
	var fy := HEAD + img_h + 14.0
	draw_line(Vector2(1, HEAD + img_h + 1.0), Vector2(sz.x - 1, HEAD + img_h + 1.0), Color(0.3, 0.62, 0.85, 0.5), 1.0)
	draw_rect(Rect2(PAD, fy - 8.0, 6, 6), Color(1.0, 0.3, 0.3))
	draw_string(font, Vector2(PAD + 10.0, fy), "Dusman %d" % n_en, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.93, 1.0))
	draw_rect(Rect2(sz.x * 0.5 + 4.0, fy - 8.0, 6, 6), Color(0.3, 0.95, 1.0))
	draw_string(font, Vector2(sz.x * 0.5 + 14.0, fy), "Kapi %d" % (game.portals.size() + n_gg), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.93, 1.0))
	if n_clan > 0:
		draw_circle(Vector2(sz.x - 44.0, fy - 5.0), 3.2, Color(0.15, 1.0, 0.3))
		draw_string(font, Vector2(sz.x - 38.0, fy), "Klan %d" % n_clan, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.7))
