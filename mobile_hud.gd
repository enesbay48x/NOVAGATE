extends Control
# NOVAGATE - MOBIL HUD  (mobile_hud.gd)
#
# Telefon / tablet acilinca otomatik devreye girer, PC'de hicbir sey degismez.
#   Sol joystick : gemiyi surer (hareket)
#   Sol joystick : SABIT DEGIL. Sol tarafta parmagini nereye koyarsan joystick orada acilir (elinin altinda).
#   Sag joystick : NISAN. Basili tutup surukledikce geminin onunde yari saydam bir nisan konisi acilir.
#                  Koniye dusman girince turkuaz -> kirmizi olur. Parmagi BIRAKINCA hedef kilitlenir ve ates baslar.
#                  ATES butonu yok. Ates sadece nisan joystick'i birakilinca baslar (acikken joystick'e kisa dokunus = ates durur).
#   Butonlar     : X1 X2 X3 X4 SAB RSB, Roket, 5 Ozel esya, ATLA, DIZILIM, MENU (=Oyun Merkezi), HUD DUZENI, CHAT (yazisiz ikonlar)
#                  Hepsi "HUD DUZENLE" modunda surukleyip istedigin yere tasinir, boyutlari ayarlanir.
#   Minimap      : sag ustte yuvarlak radar. Dokununca ekranin ortasinda buyuk harita acilir;
#                  haritada bir noktaya dokununca gemi oraya gider ve harita hemen kapanir.
#   Dunya dokunusu: bos yere dokunmak GITMEZ. Sadece bonus kutuya dokun = gidip toplar, NPC'ye dokun = hedef secer.
#   Iki parmakla yakinlastir / uzaklastir = kamera zoom.
#
# Test icin PC'de F10 ile mobil arayuz acilip kapatilir (ya da oyunu "--mobil" parametresiyle baslat).

const DOData = preload("res://data.gd")
const Extras = preload("res://extras.gd")

const CFG_PATH := "user://mobile_ui.cfg"
const MapBg := preload("res://map_bg.gd")
const MiniMapGrid := preload("res://minimap.gd")   # ortak koordinat izgarasi (sector_name / draw_coord_grid)
const SKIN_DIR := "res://assets/mobile/"
const MOUSE_ID := -1000
const TAP_MOVE := 16.0        # dokunus bu kadar piksel icinde kalirsa "tap" sayilir
const TAP_TIME := 0.35        # ve bu sureden kisa surerse
const DEAD := 0.08            # joystick olu bolge
const SMOOTH_MOVE := 20.0      # hareket joystick'i yumusatma hizi (buyuk = daha tepkili)
const SMOOTH_AIM := 28.0       # nisan joystick'i yumusatma hizi
const AIM_MIN := 0.30          # nisan joystick'i en az bu kadar itilince koni acilir
const AIM_HALF_DEG := 24.0     # nisan konisinin yari acisi
const AIM_RANGE_MUL := 1.8     # nisan konisinin boyu = lazer menzili x bu (uzaktaki hedefe gemi yaklasip ates eder)
const CONE_STEPS := 14         # koni yayinin parca sayisi
const CONE_BANDS := 7          # koni icindeki menzil seritleri
const FLOAT_X := 0.45          # ekranin sol bu kadari: hareket joystick'i parmagin altinda acilir
const FLOAT_Y := 0.22          # ve ekranin ust bu kadari haric
const LAYOUT_VER := 2          # varsayilan yerlesim surumu (degisince eski kayitli konumlar silinir)
const LASERS := ["x1", "x2", "x3", "x4", "sab", "rsb"]
const LASER_LBL := ["X1", "X2", "X3", "X4", "SAB", "RSB"]
const ALPHAS := [0.55, 0.75, 0.95]

var game = null
var hud = null
var active := false
var edit_mode := false
var alpha := 0.85
var gscale := 1.0
var font: Font = null
var skin_n: Texture2D = null
var skin_p: Texture2D = null
var skin_d: Texture2D = null

var ctls := {}                 # id -> MCtl (joystick + butonlar)
var _order: Array = []         # isabet sirasi (sondaki en ustte)
var _txt_btns := {}            # id -> MTxt (duzenleme / menu yazi butonlari)
var stick_move: MStick = null
var stick_aim: MStick = null

var _ptr := {}                 # parmak id -> {ctl, start, t, moved, pos}
var _mouse_swallow := false
var _use_mouse := false
var _menu_open := false
var _sel := ""
var _cfg := ConfigFile.new()
var _acc := 0.0
var _aim_t := 0.0
var _driving := false
var _pinch_prev := -1.0
var _icon_t := 0.0
var _state_set := false
var _aim_lock_prev := false
var _map_preserved_move_touch := -1   # harita acilirken hareket stick'ine basili parmak (touch index)
var _map_preserved_move_active := false
var _down := {}                # touch index -> ekran konumu (o an basili tum parmaklar)
var _resume_move_id := -1      # arayuz kapaninca (panel/harita) birakilan hareket parmagi; hala basiliysa geri alinir

var ws: float = DOData.S                # 1 DO birimi = ws Godot birimi (ic siniflar icin)
var safe_r: float = DOData.SAFE_RADIUS
var vision_do: float = MapBg.vision_do()   # SABIT gorus menzili (DO birimi, map_bg.gd): zoom bunu degistirmez. Gizleme main.gd'de yapilir.
var _vision_pts := PackedVector2Array()
var _vision_on := false
var minimap_btn: MMini = null
var mapview: MMapView = null
var _map_open := false
var _pc_minimap_vis := true
var _swallow_until := 0.0
var _aim_show := false
var _aim_prev = null
var _aim_target = null
var _cone_apex := Vector2.ZERO
var _cone_rings: Array = []
var _cone_hot := false
var _reticle := Vector2(-1.0, -1.0)


# ------------------------------------------------------------------ ic siniflar

class MCtl extends Control:
	var cid := ""
	var kind := "btn"
	var base := 80.0
	var uscale := 1.0
	var cpos := Vector2.ZERO
	var ui = null
	var pressed := false
	var edit_sel := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit(p: Vector2) -> bool:
		if not visible:
			return false
		var c := position + size * 0.5
		return p.distance_to(c) <= size.x * 0.5 + 6.0

	func set_pressed(v: bool) -> void:
		if pressed != v:
			pressed = v
			queue_redraw()

	func _txt(s: String, pos: Vector2, fs: int, col: Color, al: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
		var f: Font = ui.font
		if f == null or s == "":
			return
		draw_string_outline(f, pos, s, al, w, fs, 4, Color(0, 0, 0, 0.9 * ui.alpha))
		draw_string(f, pos, s, al, w, fs, col)

	func _edit_outline() -> void:
		if not ui.edit_mode:
			return
		var c := size * 0.5
		var r := size.x * 0.5
		draw_arc(c, r + 2.0, 0.0, TAU, 48, Color(0.4, 0.9, 1.0, 0.85), 2.0, true)
		if edit_sel:
			draw_arc(c, r + 5.0, 0.0, TAU, 48, Color(1.0, 0.8, 0.0, 1.0), 4.0, true)


class MBtn extends MCtl:
	var item := {}
	var label := ""
	var glyph := ""
	var icon: Texture2D = null
	var txt := ""
	var sel := false
	var avail := true
	var cd := 0.0
	var _sig := ""

	func set_state(t: String, s: bool, a: bool, c: float) -> void:
		var sg := "%s|%s|%s|%d" % [t, s, a, int(c * 60.0)]
		if sg == _sig:
			return
		_sig = sg
		txt = t
		sel = s
		avail = a
		cd = c
		queue_redraw()

	func _draw() -> void:
		var a: float = ui.alpha
		var c := size * 0.5
		var r := size.x * 0.5
		var dim := 1.0 if avail else 0.4
		var is_ext := str(item.get("k", "")) == "ext"
		# vurgu rengi: normal turkuaz, secili sari, ates acikken kirmizi
		var acc := Color(0.30, 0.78, 0.95)
		if sel:
			acc = Color(1.0, 0.80, 0.20)
			if glyph == "fire":
				acc = Color(1.0, 0.36, 0.28)
		# govde
		draw_circle(c, r - 1.0, Color(0.02, 0.07, 0.11, 0.62 * a))
		if pressed:
			draw_circle(c, r - 1.0, Color(acc.r, acc.g, acc.b, 0.32 * a))
		elif sel:
			draw_circle(c, r - 1.0, Color(acc.r, acc.g, acc.b, 0.16 * a))
		var ring_a := 0.95 if (sel or pressed) else 0.62
		draw_arc(c, r - 2.0, 0.0, TAU, 56, Color(acc.r, acc.g, acc.b, ring_a * a * dim), 2.6 if sel else 2.0, true)
		draw_arc(c, r - 7.0, 0.0, TAU, 56, Color(acc.r, acc.g, acc.b, 0.16 * a), 1.0, true)
		# icerik
		if glyph != "":
			_glyph(c, r, Color(0.88, 0.97, 1.0, a * dim) if not (sel and glyph == "fire") else Color(1.0, 0.82, 0.76, a))
		elif icon != null:
			var isz := r * 1.05
			draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) * 0.5 + Vector2(0.0, -r * 0.04), Vector2(isz, isz)), false, Color(1, 1, 1, a * dim))
			if label != "" and not is_ext:
				_txt(label, Vector2(0.0, size.y * 0.25), int(size.x * 0.16), Color(0.85, 0.95, 1.0, a * dim), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		else:
			var fs := int(minf(size.x * 0.30, size.x * 1.5 / maxf(float(label.length()), 3.0)))
			_txt(label, Vector2(0.0, size.y * 0.5 + float(fs) * 0.36), fs, Color(1, 1, 1, a * dim), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		# bekleme suresi: saat yonunde dolan dilim
		if cd > 0.0:
			var sweep := TAU * clampf(cd, 0.0, 1.0)
			draw_arc(c, r * 0.5, -PI * 0.5, -PI * 0.5 + sweep, 40, Color(0.0, 0.0, 0.0, 0.55), r - 4.0, true)
		if txt != "":
			if cd > 0.0 or (sel and is_ext):
				var fb := int(size.x * 0.32)
				_txt(txt, Vector2(0.0, size.y * 0.5 + float(fb) * 0.36), fb, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)
			else:
				_txt(txt, Vector2(0.0, size.y - r * 0.16), int(size.x * 0.17), Color(1.0, 0.92, 0.55, a * dim), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_edit_outline()

	# Yazisiz, tek renkli ikonlar (butonun icine cizilir)
	func _glyph(c: Vector2, r: float, col: Color) -> void:
		var w := maxf(2.0, r * 0.075)
		match glyph:
			"fire":
				draw_arc(c, r * 0.46, 0.0, TAU, 40, col, w, true)
				draw_circle(c, r * 0.10, col)
				for k in 4:
					var ang := float(k) * PI * 0.5
					var dv := Vector2(cos(ang), sin(ang))
					draw_line(c + dv * r * 0.30, c + dv * r * 0.72, col, w, true)
			"jump":
				draw_arc(c, r * 0.52, 0.0, TAU, 40, col, w, true)
				draw_arc(c, r * 0.34, 0.0, TAU, 32, Color(col.r, col.g, col.b, col.a * 0.5), w * 0.8, true)
				for k in 2:
					var yy := c.y + r * (0.16 - 0.26 * float(k))
					draw_polyline(PackedVector2Array([Vector2(c.x - r * 0.20, yy + r * 0.10), Vector2(c.x, yy - r * 0.08), Vector2(c.x + r * 0.20, yy + r * 0.10)]), col, w, true)
			"dzl":
				var ring := PackedVector2Array()
				for k in 7:
					var ang2 := -PI * 0.5 + float(k % 6) * TAU / 6.0
					ring.append(c + Vector2(cos(ang2), sin(ang2)) * r * 0.46)
				draw_polyline(ring, Color(col.r, col.g, col.b, col.a * 0.35), w * 0.7, true)
				draw_circle(c, r * 0.11, col)
				for k in 6:
					var ang3 := -PI * 0.5 + float(k) * TAU / 6.0
					draw_circle(c + Vector2(cos(ang3), sin(ang3)) * r * 0.46, r * 0.075, col)
			"menu":
				for k in 3:
					var ly := c.y + (float(k) - 1.0) * r * 0.27
					draw_line(Vector2(c.x - r * 0.40, ly), Vector2(c.x + r * 0.40, ly), col, w * 1.3, true)
			"layout":
				draw_rect(Rect2(c + Vector2(-r * 0.46, -r * 0.40), Vector2(r * 0.92, r * 0.80)), col, false, w)
				draw_line(c + Vector2(-r * 0.46, -r * 0.14), c + Vector2(r * 0.46, -r * 0.14), col, w, true)
				draw_line(c + Vector2(-r * 0.12, -r * 0.14), c + Vector2(-r * 0.12, r * 0.40), col, w, true)
				draw_rect(Rect2(c + Vector2(r * 0.06, r * 0.04), Vector2(r * 0.26, r * 0.22)), col, true)
			"group":
				draw_circle(c + Vector2(-r * 0.34, -r * 0.14), r * 0.13, col)
				draw_circle(c + Vector2(r * 0.34, -r * 0.14), r * 0.13, col)
				draw_circle(c + Vector2(0.0, -r * 0.24), r * 0.17, col)
				draw_arc(c + Vector2(0.0, r * 0.46), r * 0.40, PI * 1.12, PI * 1.88, 16, col, w, true)
				draw_arc(c + Vector2(-r * 0.46, r * 0.26), r * 0.24, PI * 1.10, PI * 1.60, 8, col, w, true)
				draw_arc(c + Vector2(r * 0.46, r * 0.26), r * 0.24, PI * 1.40, PI * 1.90, 8, col, w, true)
			"box":
				# bonus kutusu: kupun on yuzu + kapak cizgisi + ustte kucuk parilti
				draw_rect(Rect2(c + Vector2(-r * 0.38, -r * 0.14), Vector2(r * 0.76, r * 0.56)), col, false, w)
				draw_line(c + Vector2(-r * 0.38, r * 0.04), c + Vector2(r * 0.38, r * 0.04), col, w, true)
				draw_line(c + Vector2(0.0, -r * 0.14), c + Vector2(0.0, r * 0.04), col, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.38, -r * 0.14), c + Vector2(-r * 0.22, -r * 0.36), c + Vector2(r * 0.54, -r * 0.36), c + Vector2(r * 0.38, -r * 0.14)]), col, w, true)
				draw_line(c + Vector2(r * 0.54, -r * 0.36), c + Vector2(r * 0.54, r * 0.20), col, w, true)
			"info":
				draw_arc(c, r * 0.46, 0.0, TAU, 40, col, w, true)
				draw_circle(c + Vector2(0.0, -r * 0.24), r * 0.07, col)
				draw_line(c + Vector2(0.0, -r * 0.06), c + Vector2(0.0, r * 0.26), col, w * 1.2, true)
			"chat":
				draw_rect(Rect2(c + Vector2(-r * 0.46, -r * 0.38), Vector2(r * 0.92, r * 0.58)), col, false, w)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.20, r * 0.20), c + Vector2(-r * 0.32, r * 0.46), c + Vector2(r * 0.04, r * 0.20)]), col, w, true)
				for k in 3:
					draw_circle(Vector2(c.x + (float(k) - 1.0) * r * 0.21, c.y - r * 0.09), r * 0.06, col)


class MStick extends MCtl:
	var role := "move"
	var value := Vector2.ZERO
	var thumb := Vector2.ZERO
	var active := false
	var max_dev := 0.0
	var locked := false
	var hot := false          # nisan: konide dusman var (yesil/turkuaz yerine kirmizi)
	var home := Vector2(-1.0, -1.0)   # hareket joystick'inin bos durdugu (ipucu) konum
	var sval := Vector2.ZERO          # yumusatilmis deger (oyuna giden); value ham parmak degeri

	func smooth(dt: float, k: float) -> void:
		if not active:
			sval = Vector2.ZERO
			return
		sval = sval.lerp(value, 1.0 - exp(-k * dt))

	func _init() -> void:
		kind = "stick"
		base = 170.0

	func hit(p: Vector2) -> bool:
		if not visible:
			return false
		if role == "move" and not ui.edit_mode:
			return false   # hareket joystick'i yuzer: parmak nereye konursa orada acilir
		var c := position + size * 0.5
		return p.distance_to(c) <= size.x * 0.5 * 1.3

	func begin(p: Vector2) -> void:
		active = true
		max_dev = 0.0
		drag(p)

	func drag(p: Vector2) -> void:
		var c := position + size * 0.5
		var maxr := size.x * 0.5 * 0.7
		var v := (p - c) / maxr
		if v.length() > 1.0:
			v = v.normalized()
		value = v
		thumb = v * maxr
		max_dev = maxf(max_dev, v.length())
		queue_redraw()

	func end() -> void:
		active = false
		value = Vector2.ZERO
		sval = Vector2.ZERO
		thumb = Vector2.ZERO
		hot = false
		if role == "move" and home.x >= 0.0 and not ui.edit_mode:
			position = home
			cpos = home + size * 0.5
		queue_redraw()

	func set_hot(v: bool) -> void:
		if hot != v:
			hot = v
			queue_redraw()

	func _draw() -> void:
		var a: float = ui.alpha
		var c := size * 0.5
		var r := size.x * 0.5
		if role == "move" and not active and not ui.edit_mode:
			# bos: sadece soluk bir ipucu halkasi (joystick parmagin koydugu yerde acilir)
			draw_arc(c, r - 2.0, 0.0, TAU, 64, Color(0.30, 0.78, 0.95, 0.26 * a), 2.0, true)
			draw_arc(c, r * 0.30, 0.0, TAU, 32, Color(0.30, 0.78, 0.95, 0.20 * a), 2.0, true)
			return
		var ring := Color(0.30, 0.78, 0.95, 0.80 * a)
		if role == "aim" and hot:
			ring = Color(1.0, 0.30, 0.26, 0.95 * a)
		elif role == "aim" and locked:
			ring = Color(1.0, 0.62, 0.30, 0.90 * a)
		draw_circle(c, r, Color(0.02, 0.06, 0.10, 0.30 * a))
		draw_arc(c, r - 2.0, 0.0, TAU, 64, ring, 2.5, true)
		draw_arc(c, r * 0.58, 0.0, TAU, 48, Color(ring.r, ring.g, ring.b, 0.22 * a), 1.5, true)
		for k in 4:
			var ang := float(k) * PI * 0.5
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * (r - 14.0), c + d * (r - 5.0), Color(ring.r, ring.g, ring.b, 0.65 * a), 2.5, true)
		var tp := c + thumb
		var tr := r * 0.36
		var fill := Color(0.10, 0.30, 0.42, 0.88 * a)
		if role == "aim" and hot:
			fill = Color(0.45, 0.08, 0.08, 0.90 * a)
		draw_circle(tp, tr, fill)
		draw_arc(tp, tr, 0.0, TAU, 40, Color(ring.r, ring.g, ring.b, a).lightened(0.35), 2.5, true)
		if role == "aim":
			var cr := tr * 0.55
			draw_line(tp + Vector2(-cr, 0), tp + Vector2(cr, 0), Color(1, 1, 1, 0.8 * a), 2.0, true)
			draw_line(tp + Vector2(0, -cr), tp + Vector2(0, cr), Color(1, 1, 1, 0.8 * a), 2.0, true)
		else:
			var ar := tr * 0.5
			draw_line(tp + Vector2(0, ar), tp + Vector2(0, -ar), Color(1, 1, 1, 0.8 * a), 2.0, true)
			draw_line(tp + Vector2(-ar, 0), tp + Vector2(ar, 0), Color(1, 1, 1, 0.8 * a), 2.0, true)
		_edit_outline()


# Yuvarlak radar minimap: gemi merkezde, yakindaki dusman / kapi / ust gorunur. Dokununca buyuk harita acilir.
class MMini extends MCtl:
	func _init() -> void:
		base = 150.0

	func _draw() -> void:
		var a: float = ui.alpha
		var c := size * 0.5
		var r := size.x * 0.5
		var cy := Color(0.30, 0.78, 0.95)
		if pressed:
			cy = Color(0.60, 0.95, 1.0)
		draw_circle(c, r - 1.0, Color(0.0, 0.0, 0.0, 0.88 * a))
		if pressed:
			draw_circle(c, r - 1.0, Color(cy.r, cy.g, cy.b, 0.18 * a))
		# izgara
		draw_arc(c, (r - 6.0) * 0.5, 0.0, TAU, 40, Color(cy.r, cy.g, cy.b, 0.14 * a), 1.0, true)
		draw_line(c + Vector2(-(r - 6.0), 0.0), c + Vector2(r - 6.0, 0.0), Color(cy.r, cy.g, cy.b, 0.10 * a), 1.0)
		draw_line(c + Vector2(0.0, -(r - 6.0)), c + Vector2(0.0, r - 6.0), Color(cy.r, cy.g, cy.b, 0.10 * a), 1.0)
		var g = ui.game
		if g != null and g.P != null and is_instance_valid(g.P.node):
			var pp: Vector3 = g.P.node.position
			var rad_u: float = float(ui.vision_do) * float(ui.ws)
			var k: float = (r - 8.0) / rad_u
			# guvenli bolge (ust)
			if g.base_pos != null:
				var bd := Vector2(g.base_pos.x - pp.x, g.base_pos.z - pp.z)
				var bq := bd * k
				var srad: float = float(ui.safe_r) * float(ui.ws) * k
				if bd.length() < rad_u * 1.6:
					if bq.length() < r - 8.0:
						draw_rect(Rect2(c + bq - Vector2(3, 3), Vector2(6, 6)), Color(0.40, 1.0, 0.55, a))
					if srad > 3.0 and bq.length() < r + srad:
						draw_arc(c + bq, srad, 0.0, TAU, 40, Color(0.40, 1.0, 0.55, 0.25 * a), 1.0, true)
			# kapilar: menzil disindaysa kenara yapisir
			for p in g.portals:
				var pd := Vector2(p.pos.x - pp.x, p.pos.z - pp.z)
				var pq := pd * k
				if pq.length() > r - 8.0:
					pq = pd.normalized() * (r - 8.0)
				draw_arc(c + pq, 3.6, 0.0, TAU, 14, Color(0.30, 0.95, 1.0, a), 1.6, true)
			# dusmanlar
			for e in g.enemies:
				if not is_instance_valid(e.node):
					continue
				var ed := Vector2(e.node.position.x - pp.x, e.node.position.z - pp.z)
				if ed.length() > rad_u:
					continue
				var col := Color(1.0, 0.25, 0.25, a)
				if bool(e.get("aggro", false)) and not bool(e.get("player", false)):
					col = Color(1.0, 0.55, 0.10, a)   # dusman oyuncu her zaman kirmizi
				draw_circle(c + ed * k, 2.4, col)
			# ayni sirketten yakindaki oyuncular: beyaz
			if Net.online and Net.gm != null:
				for fe in Net.gm.players.values():
					if not bool(fe.get("friendly", false)) or not is_instance_valid(fe.node):
						continue
					var fd := Vector2(fe.node.position.x - pp.x, fe.node.position.z - pp.z)
					if fd.length() > rad_u:
						continue
					draw_circle(c + fd * k, 2.6, Color(1, 1, 1, a))
			# grup arkadaslari: menzil siniri yok; uzaktakiler radarin kenarina yapisir
			if Net.online and Net.gm != null:
				for ge in Net.gm.group_ents():
					var gd := Vector2(ge.node.position.x - pp.x, ge.node.position.z - pp.z)
					var gq := gd * k
					if gq.length() > r - 8.0:
						gq = gd.normalized() * (r - 8.0)
					draw_rect(Rect2(c + gq - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0.35, 1.0, 0.45, a))
					draw_rect(Rect2(c + gq - Vector2(3.5, 3.5), Vector2(7, 7)), Color(1, 1, 1, a), false, 1.2)
			# hedef
			if g.target != null and is_instance_valid(g.target.node):
				var td := Vector2(g.target.node.position.x - pp.x, g.target.node.position.z - pp.z)
				if td.length() <= rad_u:
					draw_arc(c + td * k, 5.0, 0.0, TAU, 14, Color(1.0, 0.95, 0.30, a), 1.5, true)
			# gidilecek nokta
			if g.dest != null:
				var dd := Vector2(g.dest.x - pp.x, g.dest.z - pp.z)
				if dd.length() <= rad_u:
					draw_arc(c + dd * k, 3.5, 0.0, TAU, 12, Color(0.40, 1.0, 0.40, a), 1.4, true)
			# gemi
			var yaw: float = g.P.node.rotation.y
			var fwd := Vector2(sin(yaw), cos(yaw))
			var side := Vector2(fwd.y, -fwd.x)
			var tip := c + fwd * 7.0
			var lw := c - fwd * 4.0 + side * 4.5
			var rw := c - fwd * 4.0 - side * 4.5
			draw_colored_polygon(PackedVector2Array([tip, lw, c - fwd * 1.5, rw]), Color(1, 1, 1, a))
		# bulundugun sektor (A1..F8)
		if g != null and g.P != null and is_instance_valid(g.P.node) and ui.font != null and ui.hud != null and ui.hud.minimap != null:
			var mm2 = ui.hud.minimap
			var sec: String = MiniMapGrid.sector_name(g.P.node.position.x / (float(mm2.map_w) * float(ui.ws)), g.P.node.position.z / (float(mm2.map_h) * float(ui.ws)))
			draw_string(ui.font, Vector2(0.0, c.y + r * 0.62), sec, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(maxf(11.0, r * 0.2)), Color(0.75, 0.92, 1.0, 0.55 * a))
		draw_arc(c, r - 2.0, 0.0, TAU, 64, Color(cy.r, cy.g, cy.b, 0.90 * a), 2.6, true)
		draw_arc(c, r - 7.0, 0.0, TAU, 64, Color(cy.r, cy.g, cy.b, 0.15 * a), 1.0, true)
		for k2 in 4:
			var ang := float(k2) * PI * 0.5
			var dv := Vector2(cos(ang), sin(ang))
			draw_line(c + dv * (r - 9.0), c + dv * (r - 2.0), Color(cy.r, cy.g, cy.b, 0.9 * a), 2.0, true)
		_edit_outline()


# Buyuk harita: ekranin ortasinda acilir, bir noktaya dokununca gemi oraya gider ve harita kapanir.
class MMapView extends Control:
	var ui = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _t(s: String, pos: Vector2, fs: int, col: Color, al: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
		var f: Font = ui.font
		if f == null or s == "":
			return
		draw_string_outline(f, pos, s, al, w, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(f, pos, s, al, w, fs, col)

	func _draw() -> void:
		if ui == null or not ui._map_open or ui.game == null or ui.hud == null:
			return
		var g = ui.game
		var vs: Vector2 = ui.get_viewport_rect().size
		var rc: Rect2 = ui._map_rect()
		var mm = ui.hud.minimap
		var mw: float = float(mm.map_w)
		var mh: float = float(mm.map_h)
		var sc: float = float(ui.ws)
		var cy := Color(0.30, 0.78, 0.95)
		# karartma
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.0, 0.62))
		# panel
		draw_rect(rc.grow(10.0), Color(0.0, 0.03, 0.05, 0.96))
		draw_rect(rc, Color(0.0, 0.0, 0.0, 1.0))   # arka plan duz siyah
		# koordinat izgarasi: 8x6, A1..F8 seffaf adlar + gemi capraz cizgileri (PC minimap ile ayni)
		var ship_px := Vector2(-1.0, -1.0)
		var cur_sec := ""
		if g.P != null and is_instance_valid(g.P.node):
			ship_px = _w2m(g.P.node.position, rc, mw, mh, sc)
			cur_sec = MiniMapGrid.sector_name(g.P.node.position.x / (mw * sc), g.P.node.position.z / (mh * sc))
		MiniMapGrid.draw_coord_grid(self, rc, ui.font, int(clampf(rc.size.x / 8.0 * 0.30, 11.0, 24.0)), ship_px, cur_sec)
		draw_rect(rc, Color(cy.r, cy.g, cy.b, 0.95), false, 2.0)
		# ust + guvenli bolge
		if g.base_pos != null:
			var bp := _w2m(g.base_pos, rc, mw, mh, sc)
			var rr: float = float(ui.safe_r) / mw * rc.size.x
			draw_arc(bp, rr, 0.0, TAU, 48, Color(0.40, 1.0, 0.55, 0.50), 1.5, true)
			draw_rect(Rect2(bp - Vector2(6, 6), Vector2(12, 12)), Color(0.40, 1.0, 0.55))
		# kapilar
		for p in g.portals:
			var pq := _w2m(p.pos, rc, mw, mh, sc)
			draw_arc(pq, 8.0, 0.0, TAU, 20, Color(0.30, 0.95, 1.0), 2.2, true)
			draw_circle(pq, 2.5, Color(0.30, 0.95, 1.0))
		# dusmanlar: sadece gorus menzilindekiler
		var n_en := 0
		var pl3: Vector3 = Vector3.ZERO
		var has_pl: bool = g.P != null and is_instance_valid(g.P.node)
		if has_pl:
			pl3 = g.P.node.position
			# (menzil dairesi artik cizilmez)
		var vlim: float = float(ui.vision_do) * sc
		for e in g.enemies:
			if not is_instance_valid(e.node):
				continue
			if has_pl and Vector2(float(e.node.position.x) - pl3.x, float(e.node.position.z) - pl3.z).length() > vlim:
				continue
			n_en += 1
			var col := Color(1.0, 0.25, 0.25)
			if bool(e.get("aggro", false)) and not bool(e.get("player", false)):
				col = Color(1.0, 0.55, 0.10)
			draw_circle(_w2m(e.node.position, rc, mw, mh, sc), 3.2, col)
		# ayni sirketten yakindaki oyuncular: beyaz
		if Net.online and Net.gm != null:
			for fe in Net.gm.players.values():
				if not bool(fe.get("friendly", false)) or not is_instance_valid(fe.node):
					continue
				if has_pl and Vector2(float(fe.node.position.x) - pl3.x, float(fe.node.position.z) - pl3.z).length() > vlim:
					continue
				draw_circle(_w2m(fe.node.position, rc, mw, mh, sc), 3.4, Color(1, 1, 1))
		# grup arkadaslari (yesil, isimli)
		if Net.online and Net.gm != null:
			for ge in Net.gm.group_ents():
				var gp := _w2m(ge.node.position, rc, mw, mh, sc)
				draw_rect(Rect2(gp - Vector2(5, 5), Vector2(10, 10)), Color(0.35, 1.0, 0.45))
				draw_rect(Rect2(gp - Vector2(5, 5), Vector2(10, 10)), Color(1, 1, 1), false, 1.5)
				_t(str(ge.name), gp + Vector2(8, -6), 13, Color(0.6, 1.0, 0.65))
		# kamera gorus kutusu
		var vr: Rect2 = g.view_rect
		if vr.size.x > 0.0:
			var va := _w2m(Vector3(vr.position.x, 0.0, vr.position.y), rc, mw, mh, sc)
			var vb := _w2m(Vector3(vr.end.x, 0.0, vr.end.y), rc, mw, mh, sc)
			var box := Rect2(va, vb - va).intersection(rc)
			if box.size.x > 0.0 and box.size.y > 0.0:
				draw_rect(box, Color(1, 1, 1, 0.55), false, 1.5)
		# hedef + gidilecek nokta
		if g.target != null and is_instance_valid(g.target.node):
			draw_arc(_w2m(g.target.node.position, rc, mw, mh, sc), 9.0, 0.0, TAU, 20, Color(1.0, 0.95, 0.30), 2.0, true)
		if g.dest != null:
			draw_arc(_w2m(g.dest, rc, mw, mh, sc), 6.0, 0.0, TAU, 16, Color(0.40, 1.0, 0.40), 2.0, true)
		# gemi
		if g.P != null and is_instance_valid(g.P.node):
			var sp := _w2m(g.P.node.position, rc, mw, mh, sc)
			var yaw: float = g.P.node.rotation.y
			var fwd := Vector2(sin(yaw), cos(yaw))
			var side := Vector2(fwd.y, -fwd.x)
			var tip := sp + fwd * 11.0
			var lw := sp - fwd * 6.0 + side * 6.5
			var rw := sp - fwd * 6.0 - side * 6.5
			draw_colored_polygon(PackedVector2Array([tip, lw, sp - fwd * 2.0, rw]), Color(1, 1, 1))
		# baslik, ipucu, sayaclar
		var title: String = str(mm.map_name)
		if title == "":
			title = "HARİTA"
		if cur_sec != "":
			title += "   ·   " + cur_sec
		_t(title, Vector2(rc.position.x, rc.position.y - 16.0), 20, Color(1.0, 0.85, 0.30))
		_t("Gitmek istedigin noktaya dokun", Vector2(rc.position.x, rc.end.y + 30.0), 16, Color(0.85, 0.95, 1.0))
		_t("Dusman %d   Kapi %d" % [n_en, g.portals.size()], Vector2(rc.position.x, rc.end.y + 30.0), 16, Color(0.85, 0.95, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, rc.size.x)
		# kapat dugmesi
		var cc := Vector2(rc.end.x + 6.0, rc.position.y - 6.0)
		draw_circle(cc, 22.0, Color(0.02, 0.06, 0.10, 0.96))
		draw_arc(cc, 21.0, 0.0, TAU, 32, Color(cy.r, cy.g, cy.b, 0.95), 2.5, true)
		draw_line(cc + Vector2(-8, -8), cc + Vector2(8, 8), Color(1, 1, 1), 3.0, true)
		draw_line(cc + Vector2(-8, 8), cc + Vector2(8, -8), Color(1, 1, 1), 3.0, true)

	func _w2m(p: Vector3, rc: Rect2, mw: float, mh: float, sc: float) -> Vector2:
		return Vector2(rc.position.x + p.x / (mw * sc) * rc.size.x, rc.position.y + p.z / (mh * sc) * rc.size.y)


class MTxt extends MCtl:
	var text := ""
	var sb := StyleBoxFlat.new()

	func _init() -> void:
		kind = "txt"
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)

	func hit(p: Vector2) -> bool:
		if not visible:
			return false
		return Rect2(position, size).grow(4.0).has_point(p)

	func _draw() -> void:
		var a := 0.95
		sb.bg_color = Color(0.10, 0.30, 0.42, a) if pressed else Color(0.03, 0.09, 0.14, a)
		sb.border_color = Color(0.40, 0.85, 1.0, 1.0)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var f: Font = ui.font
		if f != null:
			var fs := int(minf(size.y * 0.40, size.x * 1.7 / maxf(float(text.length()), 4.0)))
			draw_string(f, Vector2(0.0, size.y * 0.5 + float(fs) * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(1, 1, 1, 1))


# ------------------------------------------------------------------ kurulum

func build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = hud.f_bold
	skin_n = _load_tex(SKIN_DIR + "btn_default.png")
	skin_p = _load_tex(SKIN_DIR + "btn_pressed.png")
	skin_d = _load_tex(SKIN_DIR + "btn_disabled.png")
	_cfg.load(CFG_PATH)
	if int(_cfg.get_value("ui", "layout_ver", 0)) != LAYOUT_VER:
		if _cfg.has_section("pos"):
			_cfg.erase_section("pos")
		if _cfg.has_section("sc"):
			_cfg.erase_section("sc")
		_cfg.set_value("ui", "layout_ver", LAYOUT_VER)
		_cfg.save(CFG_PATH)
	gscale = clampf(float(_cfg.get_value("ui", "scale", 1.0)), 0.7, 1.5)
	alpha = clampf(float(_cfg.get_value("ui", "alpha", 0.85)), 0.4, 1.0)
	_use_mouse = not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"))
	_make_controls()
	_make_txt_buttons()
	visible = false
	for c in ctls.values():
		c.visible = false
	_apply_state(_detect(), false)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _detect() -> bool:
	for a in OS.get_cmdline_args():
		if a == "--mobil" or a == "--mobile-ui":
			return true
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func mobile_on() -> bool:
	return active


func toggle_forced() -> void:
	_apply_state(not active, true)


func _add_btn(id: String, label: String, base_sz: float, item: Dictionary) -> MBtn:
	var b := MBtn.new()
	b.cid = id
	b.ui = self
	b.label = label
	b.base = base_sz
	b.item = item
	b.uscale = clampf(float(_cfg.get_value("sc", id, 1.0)), 0.6, 1.8)
	add_child(b)
	ctls[id] = b
	_order.append(b)
	return b


func _add_stick(id: String, role: String) -> MStick:
	var s := MStick.new()
	s.cid = id
	s.role = role
	s.ui = self
	s.uscale = clampf(float(_cfg.get_value("sc", id, 1.0)), 0.6, 1.8)
	add_child(s)
	ctls[id] = s
	_order.append(s)
	return s


func _make_controls() -> void:
	stick_move = _add_stick("stick_move", "move")
	stick_aim = _add_stick("stick_aim", "aim")
	for i in LASERS.size():
		_add_btn(LASERS[i], LASER_LBL[i], 76.0, {"k": "las", "id": LASERS[i]})
	_add_btn("rkt", "ROKET", 86.0, {"k": "rkt", "id": "r310"})
	for id in Extras.IDS:
		_add_btn(str(id), "", 66.0, {"k": "ext", "id": str(id)})
	_add_btn("jump", "", 76.0, {}).glyph = "jump"
	_add_btn("dzl", "", 76.0, {}).glyph = "dzl"
	_add_btn("cfg", "K1", 72.0, {})   # konfigurasyon degistir (K1 / K2)
	_add_btn("menu", "", 60.0, {}).glyph = "menu"
	_add_btn("hudedit", "", 60.0, {}).glyph = "layout"
	_add_btn("chat", "", 60.0, {}).glyph = "chat"
	_add_btn("grp", "", 60.0, {}).glyph = "group"
	_add_btn("info", "", 60.0, {}).glyph = "info"   # bilgi penceresi (oyuncu bilgisi) ac/kapat
	_add_btn("box", "", 60.0, {}).glyph = "box"     # en yakin bonus kutusunu topla (tekrar bas: iptal)
	minimap_btn = MMini.new()
	minimap_btn.cid = "minimap"
	minimap_btn.ui = self
	minimap_btn.uscale = clampf(float(_cfg.get_value("sc", "minimap", 1.0)), 0.6, 1.8)
	add_child(minimap_btn)
	ctls["minimap"] = minimap_btn
	_order.append(minimap_btn)
	mapview = MMapView.new()
	mapview.ui = self
	mapview.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(mapview)


func _add_txt(id: String, text: String, sz: Vector2) -> MTxt:
	var t := MTxt.new()
	t.cid = id
	t.ui = self
	t.text = text
	t.size = sz
	t.visible = false
	add_child(t)
	_txt_btns[id] = t
	return t


func _make_txt_buttons() -> void:
	_add_txt("edit_open", "HUD DÜZENLE", Vector2(170, 55))
	_add_txt("e_minus", "-", Vector2(110, 46))
	_add_txt("e_plus", "+", Vector2(110, 46))
	_add_txt("e_alpha", "ŞEFFAFLIK", Vector2(110, 46))
	_add_txt("e_reset", "SIFIRLA", Vector2(110, 46))
	_add_txt("e_done", "BİTTİ", Vector2(110, 46))


# Mobil arayuzu ac / kapat. Acarken PC'ye ozel pencereler sadelestirilir, kapatirken eski haline doner.
func _apply_state(v: bool, relayout: bool) -> void:
	if _state_set and v == active and not relayout:
		return
	if not v and edit_mode:
		_set_edit(false)
	_reset_pointers()
	var was_set := _state_set
	_state_set = true
	active = v
	visible = v
	for c in ctls.values():
		c.visible = v
	for t in _txt_btns.values():
		t.visible = false
	_map_open = false
	if mapview != null:
		mapview.visible = false
	if v:
		_enter_mobile()
	elif was_set:
		_leave_mobile()
	if relayout:
		hud._layout()


func _enter_mobile() -> void:
	_menu_open = false
	hud.tracker_win.visible = false
	hud.chat_win.visible = false
	hud.chat_win.scale = Vector2(1.35, 1.35)
	hud.contacts_win.scale = Vector2(1.3, 1.3)
	hud.quests_win.scale = Vector2(1.3, 1.3)
	hud.group_win.scale = Vector2(1.3, 1.3)
	hud.minimap_win.locked = true
	_pc_minimap_vis = hud.minimap_win.visible
	hud.minimap_win.visible = false
	for ch in hud.minimap_win.get_children():
		if ch is TextureButton:
			ch.visible = false
	hud.top_left.scale = Vector2(1.45, 1.45)
	hud.top_left.visible = false
	hud.top_right.visible = false
	hud.abar.visible = false
	hud.lbl_help.visible = false


func _leave_mobile() -> void:
	_show_all_world()
	_menu_open = false
	hud.tracker_win.visible = true
	hud.chat_win.visible = true
	hud.chat_win.scale = Vector2.ONE
	hud.contacts_win.scale = Vector2.ONE
	hud.quests_win.scale = Vector2.ONE
	hud.group_win.scale = Vector2.ONE
	hud.minimap_win.locked = false
	hud.minimap_win.visible = _pc_minimap_vis
	for ch in hud.minimap_win.get_children():
		if ch is TextureButton:
			ch.visible = true
	hud.top_left.scale = Vector2.ONE
	hud.top_left.visible = true
	hud.top_right.visible = true
	hud.abar.visible = true
	if not game.SV.is_empty():
		hud.lbl_help.visible = bool(game.SV.settings.get("help", false))


# ------------------------------------------------------------------ yerlesim

func _safe_rect(vs: Vector2) -> Rect2:
	var r := Rect2(Vector2.ZERO, vs)
	if not OS.has_feature("mobile"):
		return r
	var sa := DisplayServer.get_display_safe_area()
	var ws := Vector2(DisplayServer.window_get_size())
	if sa.size.x <= 0 or ws.x <= 0.0 or ws.y <= 0.0:
		return r
	var k := vs.x / ws.x
	var l := clampf(float(sa.position.x) * k, 0.0, 120.0)
	var t := clampf(float(sa.position.y) * k, 0.0, 120.0)
	var rr := clampf((ws.x - float(sa.position.x + sa.size.x)) * k, 0.0, 120.0)
	var b := clampf((ws.y - float(sa.position.y + sa.size.y)) * k, 0.0, 120.0)
	return Rect2(Vector2(l, t), vs - Vector2(l + rr, t + b))


func _polar(deg: float, rad: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * rad


func _default_center(id: String, sr: Rect2) -> Vector2:
	var l := sr.position.x
	var t := sr.position.y
	var r := sr.end.x
	var b := sr.end.y
	var cx := (l + r) * 0.5
	var aim_c := Vector2(r - 150.0, b - 135.0)      # sag joystick merkezi
	var mm_c := Vector2(r - 92.0, t + 92.0)         # yuvarlak minimap merkezi
	var i := LASERS.find(id)
	if i >= 0:
		return Vector2(cx + (float(i) - 2.5) * 84.0, b - 50.0)
	var j := Extras.IDS.find(id)
	if j >= 0:
		var n := float(Extras.IDS.size())
		return Vector2(cx + (float(j) - (n - 1.0) * 0.5) * 76.0, b - 134.0)
	match id:
		"stick_move":
			return Vector2(l + 150.0, b - 135.0)
		"stick_aim":
			return aim_c
		# sag joystick'in etrafinda yay: roket - atla - dizilim
		"rkt":
			return aim_c + _polar(180.0, 184.0)
		"jump":
			return aim_c + _polar(225.0, 184.0)
		"dzl":
			return aim_c + _polar(270.0, 184.0)
		"cfg":
			return aim_c + _polar(200.0, 270.0)
		"minimap":
			return mm_c
		"menu":
			return mm_c + Vector2(-112.0, -40.0)
		"chat":
			return mm_c + Vector2(-180.0, -40.0)
		"hudedit":
			return mm_c + Vector2(-248.0, -40.0)
		"grp":
			return mm_c + Vector2(-112.0, 36.0)
		"info":
			return mm_c + Vector2(-180.0, 36.0)
		"box":
			return mm_c + Vector2(-248.0, 36.0)
	return Vector2(cx, (t + b) * 0.5)


func _center_of(id: String, vs: Vector2, sr: Rect2) -> Vector2:
	if _cfg.has_section_key("pos", id):
		var n: Vector2 = _cfg.get_value("pos", id)
		return Vector2(n.x * vs.x, n.y * vs.y)
	return _default_center(id, sr)


func _clamp_center(c: Vector2, sz: Vector2, vs: Vector2) -> Vector2:
	var hx := sz.x * 0.5
	var hy := sz.y * 0.5
	return Vector2(clampf(c.x, hx, maxf(vs.x - hx, hx)), clampf(c.y, hy, maxf(vs.y - hy, hy)))


func apply_layout() -> void:
	if not active or hud == null:
		return
	var vs := get_viewport_rect().size
	var sr := _safe_rect(vs)
	for id in ctls:
		var c: MCtl = ctls[id]
		var d := c.base * gscale * c.uscale
		c.size = Vector2(d, d)
		c.cpos = _clamp_center(_center_of(id, vs, sr), c.size, vs)
		c.position = c.cpos - c.size * 0.5
		if c is MStick:
			(c as MStick).home = c.position
		c.queue_redraw()
	# --- PC penceresi duzeni (mobilde)
	hud.top_left.position = Vector2(sr.position.x + 10.0, sr.position.y + 8.0)
	hud.top_left.visible = _menu_open and not edit_mode
	var eo: MTxt = _txt_btns["edit_open"]
	eo.position = Vector2(sr.position.x + 10.0 + float(hud.top_left.size.x) * 1.45 + 12.0, sr.position.y + 8.0)
	eo.visible = _menu_open and not edit_mode
	hud.top_right.visible = false
	hud.abar.visible = false
	hud.lbl_help.visible = false
	hud.minimap_win.visible = false
	if mapview != null:
		mapview.position = Vector2.ZERO
		mapview.size = vs
	hud.lbl_prompt.position = Vector2(vs.x * 0.5 - 300.0, sr.end.y - 250.0)
	if not hud.chat_win.moved:
		hud.chat_win.position = Vector2(vs.x * 0.5 - float(hud.chat_win.size.x) * 0.675, sr.position.y + 70.0)
	for w in [hud.contacts_win, hud.quests_win, hud.group_win]:
		if not w.moved:
			w.position = Vector2((vs.x - float(w.size.x) * 1.3) * 0.5, maxf(8.0, (vs.y - float(w.size.y) * 1.3) * 0.5))
	_place_edit_buttons(vs)
	queue_redraw()


func _place_edit_buttons(vs: Vector2) -> void:
	var ids := ["e_minus", "e_plus", "e_alpha", "e_reset", "e_done"]
	for k in ids.size():
		var t: MTxt = _txt_btns[ids[k]]
		t.position = Vector2(vs.x * 0.5 + (float(k) - 2.0) * 120.0 - t.size.x * 0.5, 54.0)
		t.queue_redraw()


# ------------------------------------------------------------------ cizim (duzenleme modu arka plani)

func _draw() -> void:
	if _vision_on and _vision_pts.size() > 2:
		for k in range(0, _vision_pts.size() - 1, 2):
			draw_line(_vision_pts[k], _vision_pts[k + 1], Color(0.45, 0.85, 1.0, 0.22), 2.0, true)
	if _aim_show:
		_draw_aim()
	if not edit_mode or font == null:
		return
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45))
	var bar := Rect2(vs.x * 0.5 - 320.0, 6.0, 640.0, 108.0)
	draw_rect(bar, Color(0.02, 0.06, 0.10, 0.94))
	draw_rect(bar, Color(0.25, 0.65, 0.85, 1.0), false, 2.0)
	draw_string(font, Vector2(bar.position.x + 14.0, 28.0), "HUD DÜZENLE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(1.0, 0.8, 0.0))
	var info := "Surukle: tasi   |   Dokun: sec   |   -/+ : secili ogenin boyutu"
	if _sel == "" or not ctls.has(_sel):
		info = "Surukle: tasi   |   Dokun: sec   |   -/+ : secim yoksa tum arayuz boyutu"
	else:
		info = "Secili: %s   |   -/+ : bu ogenin boyutu   |   bos yere dokun: secimi kaldir" % _name_of(_sel)
	draw_string(font, Vector2(bar.position.x + 150.0, 28.0), info, HORIZONTAL_ALIGNMENT_LEFT, bar.size.x - 160.0, 12, Color(0.8, 0.92, 1.0))


func _name_of(id: String) -> String:
	match id:
		"stick_move":
			return "Hareket joystick"
		"stick_aim":
			return "Hedef joystick"
		"rkt":
			return "Roket"
		"fire":
			return "Ates"
		"minimap":
			return "Minimap"
		"jump":
			return "Atla"
		"dzl":
			return "Dizilim"
		"cfg":
			return "Konfigurasyon"
		"menu":
			return "Oyun Merkezi"
		"hudedit":
			return "HUD düzeni"
		"grp":
			return "Grup"
		"info":
			return "Bilgi"
		"box":
			return "Kutu topla"
		"chat":
			return "Chat"
	if id in LASERS:
		return LASER_LBL[LASERS.find(id)]
	if Extras.DEFS.has(id):
		return str(Extras.DEFS[id].name)
	return id


# ------------------------------------------------------------------ girdi

func _live() -> bool:
	if not active or game == null or hud == null or not game.running:
		return false
	if not is_visible_in_tree():
		return false
	if game.base_menu != null and game.base_menu.visible:
		return false
	if game.gal_panel != null and game.gal_panel.visible:
		return false
	return true


func _to_local(pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * pos


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _ctl_at(p: Vector2) -> MCtl:
	for t in _txt_btns.values():
		if t.visible and t.hit(p):
			return t
	for i in range(_order.size() - 1, -1, -1):
		var c: MCtl = _order[i]
		if c.hit(p):
			return c
	return null


func _blocked_by_gui(p: Vector2) -> bool:
	for w in [hud.user_win, hud.tracker_win, hud.target_win, hud.minimap_win, hud.chat_win, hud.contacts_win, hud.quests_win, hud.group_win, hud.top_left]:
		if w != null and w.visible and Rect2(w.global_position, w.size * w.scale).has_point(p):
			return true
	return false


func _input(ev: InputEvent) -> void:
	# Parmaklarin gercek durumu: panel/harita acikken (arayuz "canli" degilken) bile izlenir.
	# Boylece panel kapaninca hala basili olan hareket parmagi geri alinabilir.
	var st0 := ev as InputEventScreenTouch
	if st0 != null:
		if st0.pressed and not st0.canceled:
			_down[st0.index] = st0.position
		else:
			_down.erase(st0.index)
	else:
		var sd0 := ev as InputEventScreenDrag
		if sd0 != null and _down.has(sd0.index):
			_down[sd0.index] = sd0.position
	if not _live():
		return
	var st := ev as InputEventScreenTouch
	if st != null:
		var claimed := false
		if st.pressed and not st.canceled:
			claimed = _press(st.index, st.position)
		else:
			claimed = _release(st.index, st.position)
		if claimed:
			get_viewport().set_input_as_handled()
		return
	var sd := ev as InputEventScreenDrag
	if sd != null:
		if _move(sd.index, sd.position):
			get_viewport().set_input_as_handled()
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if _use_mouse:
			var claimed2 := false
			if mb.pressed:
				claimed2 = _press(MOUSE_ID, mb.position)
			else:
				claimed2 = _release(MOUSE_ID, mb.position)
			if claimed2:
				get_viewport().set_input_as_handled()
		else:
			# Dokunmadan uretilen sahte fare olayi: joystick/butona ait olanlari yut (dunya tiklamasi sanilmasin)
			if mb.pressed:
				_mouse_swallow = edit_mode or _map_open or _now() < _swallow_until or _ctl_at(_to_local(mb.position)) != null
			if _mouse_swallow:
				get_viewport().set_input_as_handled()
			if not mb.pressed:
				_mouse_swallow = false
		return
	var mo := ev as InputEventMouseMotion
	if mo != null:
		if _use_mouse:
			if _ptr.has(MOUSE_ID) and (mo.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				if _move(MOUSE_ID, mo.position):
					get_viewport().set_input_as_handled()
		elif _mouse_swallow:
			get_viewport().set_input_as_handled()


func _press(id: int, gpos: Vector2) -> bool:
	var p := _to_local(gpos)
	var now := _now()
	if _map_open:
		_map_tap(p)
		return true
	var c := _ctl_at(p)
	if edit_mode:
		var off := Vector2.ZERO
		if c != null:
			off = c.cpos - p
		_ptr[id] = {"ctl": c, "start": p, "t": now, "moved": false, "pos": p, "off": off}
		if c != null:
			c.set_pressed(true)
			if c.kind != "txt":
				_select(c.cid)
		else:
			_select("")
		return true
	if c != null:
		_ptr[id] = {"ctl": c, "start": p, "t": now, "moved": false, "pos": p, "off": Vector2.ZERO}
		c.set_pressed(true)
		if c.kind == "stick":
			(c as MStick).begin(p)
			if c.cid == "stick_move":
				game._cancel_collect()
		elif c.kind == "btn":
			_haptic(18)
			_btn_action(c.cid)
		return true
	if _blocked_by_gui(p):
		return false
	var vs := get_viewport_rect().size
	if stick_move != null and not stick_move.active and p.x < vs.x * FLOAT_X and p.y > vs.y * FLOAT_Y:
		_start_float_move(id, p, gpos, now)
		return true
	_ptr[id] = {"ctl": null, "start": p, "t": now, "moved": false, "pos": p, "off": Vector2.ZERO, "gpos": gpos}
	_update_pinch()
	return false


func _move(id: int, gpos: Vector2) -> bool:
	if not _ptr.has(id):
		return false
	var d: Dictionary = _ptr[id]
	var p := _to_local(gpos)
	d["pos"] = p
	if p.distance_to(d["start"]) > TAP_MOVE:
		d["moved"] = true
	var c = d["ctl"]
	if c == null:
		_update_pinch()
		return false
	if edit_mode:
		if c.kind != "txt":
			var vs := get_viewport_rect().size
			var ctr := _clamp_center(p + (d["off"] as Vector2), c.size, vs)
			c.cpos = ctr
			c.position = ctr - c.size * 0.5
		return true
	if c.kind == "stick":
		(c as MStick).drag(p)
	return true


func _release(id: int, gpos: Vector2) -> bool:
	if _map_open:
		# Harita acikken hareket parmagi kalkarsa joystick HEMEN birakilir (yoksa gemi bayat degerle gitmeye devam eder).
		if _ptr.has(id) and _ptr[id]["ctl"] == stick_move and stick_move != null:
			stick_move.set_pressed(false)
			stick_move.end()
			_map_preserved_move_active = false
			_map_preserved_move_touch = -1
		_ptr.erase(id)
		return true
	if not _ptr.has(id):
		return false
	var d: Dictionary = _ptr[id]
	_ptr.erase(id)
	var p := _to_local(gpos)
	var c = d["ctl"]
	if c == null:
		_update_pinch()
		if not edit_mode and not bool(d["moved"]) and _now() - float(d["t"]) <= TAP_TIME:
			_world_tap(d["gpos"])
		return false
	c.set_pressed(false)
	if edit_mode:
		if c.kind == "txt":
			if c.hit(p):
				_edit_action(c.cid)
		else:
			_commit_drag(c)
		return true
	if c.kind == "stick":
		var s: MStick = c
		var tap := not bool(d["moved"]) and _now() - float(d["t"]) <= TAP_TIME and s.max_dev < 0.3
		var shot = null
		if s.role == "aim":
			shot = _aim_target
		s.end()
		if s.role == "aim":
			_aim_show = false
			_aim_target = null
			queue_redraw()
			if s.max_dev < AIM_MIN:
				# Kisa dokunus: ates aciksa DURUR; kapaliysa en yakin NPC / dusman sirkete ates baslar.
				if game.fire:
					game._set_fire(false)
				else:
					_fire_nearest()
			elif shot != null and is_instance_valid(shot.node):
				_aim_fire(shot)
			elif not game.fire:
				# Joystick itildi ama konide kimse yoktu: yine de en yakin hedefe ates et
				_fire_nearest()
		elif s.role == "move" and tap and bool(d.get("float", false)):
			_world_tap(d["gpos"])   # sol alanda kisa dokunus: oradaki kutu / NPC'ye dokunmus olabilir
	elif c.kind == "txt":
		if c.hit(p):
			_edit_action(c.cid)
	return true


# iki parmak = kamera zoom
func _update_pinch() -> void:
	var ids: Array = []
	for k in _ptr:
		if _ptr[k]["ctl"] == null:
			ids.append(k)
	if ids.size() != 2 or edit_mode:
		_pinch_prev = -1.0
		return
	var a: Vector2 = _ptr[ids[0]]["pos"]
	var b: Vector2 = _ptr[ids[1]]["pos"]
	var dist := a.distance_to(b)
	_ptr[ids[0]]["moved"] = true
	_ptr[ids[1]]["moved"] = true
	if _pinch_prev > 8.0 and dist > 8.0:
		game.zoom = clampf(float(game.zoom) * (_pinch_prev / dist), 0.6, 1.8)
	_pinch_prev = dist


func _reset_pointers() -> void:
	for k in _ptr.keys():
		var c = _ptr[k]["ctl"]
		if c != null:
			c.set_pressed(false)
	_ptr.clear()
	_pinch_prev = -1.0
	_mouse_swallow = false
	if stick_move != null:
		stick_move.end()
	if stick_aim != null:
		stick_aim.end()
	if _aim_show or _aim_target != null:
		_aim_show = false
		_aim_target = null
		queue_redraw()
	if _driving:
		_driving = false
		if game != null and game.dest != null:
			game.dest = null


# ------------------------------------------------------------------ oyun eylemleri

func _haptic(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# Yeni mesaj eskisine eklenir, son 3 satir gorunur (ust uste binmez).
func _btn_action(id: String) -> void:
	if game.SV.is_empty():
		return
	match id:
		"x1", "x2", "x3", "x4", "sab", "rsb":
			if game == null or hud == null:
				return
			hud._use_item({"k": "las", "id": id})
		"rkt":
			game.toggle_rocket_auto()
		"cfg":
			game.switch_cfg(1 - int(game.SV.get("cfgi", 0)))
		"minimap":
			call_deferred("_open_map")
		"menu":
			# Sadece Oyun Merkezi (kontrol paneli) acilir
			call_deferred("_open_game_center")
		"hudedit":
			call_deferred("_open_hud_edit")
		"info":
			hud.toggle_info()
		"box":
			game.collect_nearest_box()
		"grp":
			hud.toggle_group()
		"chat":
			hud.toggle_chat()
		"jump":
			game._try_jump()
			if float(game.jump_t) < 0.0:
				game.toast("Atlamak icin bir kapiya yaklas.")
		"dzl":
			_cycle_form()
		_:
			if Extras.DEFS.has(id):
				hud._use_item({"k": "ext", "id": id})


func _open_game_center() -> void:
	if not active or edit_mode or game == null or not game.running:
		return
	_menu_open = false
	hud.top_left.visible = false
	_txt_btns["edit_open"].visible = false
	_reset_pointers()
	_swallow_until = _now() + 0.3
	if game.base_menu != null and not game.base_menu.visible:
		game.toggle_base()


func _open_hud_edit() -> void:
	if not active or edit_mode or _map_open:
		return
	_set_edit(true)


# Sol alanda parmak nereye konduysa hareket joystick'i orada acilir.
func _start_float_move(id: int, p: Vector2, gpos: Vector2, now: float) -> void:
	var st := stick_move
	var vs := get_viewport_rect().size
	var ctr := _clamp_center(p, st.size, vs)
	st.position = ctr - st.size * 0.5
	st.cpos = ctr
	_ptr[id] = {"ctl": st, "start": p, "t": now, "moved": false, "pos": p, "off": Vector2.ZERO, "float": true, "gpos": gpos}
	st.set_pressed(true)
	st.begin(p)
	game._cancel_collect()


# Dunyaya dokunus: bos yere dokunmak GITMEZ. Sadece NPC (hedef sec) ve bonus kutu (gidip topla) calisir.
func _world_tap(gpos: Vector2) -> void:
	var hit = game._ground_at(gpos)
	if hit == null:
		return
	var en = game._pick_enemy(hit)
	if en != null and not en.node.visible:
		en = null
	if en != null:
		game._cancel_collect()
		if not is_same(en, game.target):
			game.target = en
			_haptic(14)
		else:
			if game.fire:
				game.fire = false   # ates durur, hedef kalir
			else:
				game._set_fire(true)   # ayni hedefe tekrar dokunus: ates yeniden baslar
		return
	# Ayni sirketten oyuncu: secilir (grup penceresi acilir, gruba davet edilebilir); hedef OLMAZ, ates edilemez.
	if game.net_on and Net.gm != null:
		var fr = Net.gm.friendly_at(hit)
		if fr != null:
			game._cancel_collect()
			hud.select_friend(int(fr.peer))
			return
	var cb = game._pick_box(hit)
	if cb != null:
		if not is_same(cb, game.collect_box):
			game._cancel_collect()
			game.collect_box = cb
			game.collect_t = 0.0
		game.dest = game._clamp_map(cb.node.position)
		game.holding = false


# ATES: hedef yoksa en yakin dusmani sec ve ates ac; hedef varsa ates ac/kapat. (Artik buton yok; kullanilmiyor.)
func _fire_toggle() -> void:
	if game.target == null:
		game._select_next()
		if game.target == null:
			game.toast("Yakinda hedef yok.")
			return
		game._set_fire(true)
		return
	game._set_fire(not game.fire)


func _cycle_form() -> void:
	var forms: Array = game.SV.get("forms", ["std"])
	if forms.size() < 2:
		game.toast("Baska dizilimin yok. Marketten dizilim alabilirsin.")
		return
	var cur := str(game.cfg().form)
	var idx := forms.find(cur)
	var nxt := str(forms[(idx + 1) % forms.size()])
	game.set_form(nxt)
	game.toast("Dizilim: " + str(hud._form_name(nxt)))


# Sol joystick -> gemi hedef noktasi. Ekranda "yukari" = kameranin ileri yonu.
func _drive_move() -> void:
	var v := Vector2.ZERO
	if stick_move.active:
		v = stick_move.sval
	var mag := v.length()
	if mag > DEAD and game.P != null and is_instance_valid(game.P.node):
		var cam: Camera3D = game.cam
		var b: Basis = cam.global_transform.basis
		var right := Vector3(b.x.x, 0.0, b.x.z)
		var fwd := Vector3(-b.z.x, 0.0, -b.z.z)
		if right.length() < 0.001 or fwd.length() < 0.001:
			return
		var dir: Vector3 = right.normalized() * v.x + fwd.normalized() * (-v.y)
		if dir.length() < 0.001:
			return
		dir = dir.normalized()
		var eff := clampf((mag - DEAD) / (0.9 - DEAD), 0.0, 1.0)
		eff = maxf(eff, 0.15)
		var max_spd: float = float(game.ship_speed()) * DOData.S * DOData.SPEEDMULT
		var dist := maxf((max_spd * eff - 1.0) / 6.0, 1.2)
		_driving = true
		game.holding = false
		var po: Vector3 = game.P.node.position
		game.dest = po + dir * dist
	elif _driving:
		_driving = false
		game.dest = null


# ------------------------------------------------------------------ sabit gorus menzili

func _show_all_world() -> void:
	if game == null:
		return
	for e in game.enemies:
		if is_instance_valid(e.node):
			e.node.visible = true
	for b in game.boxes:
		if is_instance_valid(b.node):
			b.node.visible = true
	_vision_on = false
	queue_redraw()


# Uzaklasinca gorus menzilini ince kesik bir halka olarak goster (neden kaybolduklarini anlasin).
func _update_vision_ring() -> void:
	var want: bool = false and float(game.zoom_cur) > 1.2 and game.P != null and is_instance_valid(game.P.node) and game.cam != null
	if not want:
		if _vision_on:
			_vision_on = false
			queue_redraw()
		return
	var cam: Camera3D = game.cam
	var po: Vector3 = game.P.node.position
	var inv := get_global_transform_with_canvas().affine_inverse()
	var rr: float = vision_do * ws
	var pts := PackedVector2Array()
	for k in range(73):
		var t := TAU * float(k) / 72.0
		var wp := Vector3(po.x + cos(t) * rr, 0.0, po.z + sin(t) * rr)
		if cam.is_position_behind(wp):
			_vision_on = false
			return
		pts.append(inv * cam.unproject_position(wp))
	_vision_pts = pts
	_vision_on = true
	queue_redraw()


# ------------------------------------------------------------------ nisan (sag joystick)

# Sag joystick itilince geminin onunde nisan konisi acilir. Konide dusman varsa koni kirmizi olur;
# parmak birakilinca o dusman kilitlenir ve ates baslar (WarUniverse tarzi).
func _update_aim() -> void:
	var was := _aim_show
	var hot := false
	_aim_show = false
	_aim_target = null
	_reticle = Vector2(-1.0, -1.0)
	if stick_aim.active and stick_aim.sval.length() >= AIM_MIN * 0.8 and game.P != null and is_instance_valid(game.P.node) and game.cam != null:
		var cam: Camera3D = game.cam
		var po: Vector3 = game.P.node.position
		var ps := cam.unproject_position(Vector3(po.x, 0.0, po.z))
		var sv := stick_aim.sval.normalized()
		# ekrandaki yonu yere (dunya) cevir
		var probe = game._ground_at(ps + sv * 140.0)
		if probe != null:
			var wd := Vector2(float(probe.x) - po.x, float(probe.z) - po.z)
			if wd.length() > 0.001:
				wd = wd.normalized()
				_aim_target = _find_in_cone(po, wd)
				hot = _aim_target != null
				_aim_show = true
				_build_cone(cam, po, wd)
				if hot:
					_reticle = _to_local(cam.unproject_position(_aim_target.node.position))
	_cone_hot = hot
	_aim_prev = _aim_target
	stick_aim.set_hot(hot)
	if _aim_show or was:
		queue_redraw()


# Konideki en uygun dusman: merkez cizgisine en yakin, menzil icinde.
func _find_in_cone(po: Vector3, wd: Vector2):
	var range_u: float = DOData.LASER_RANGE * DOData.S * AIM_RANGE_MUL
	var half := deg_to_rad(AIM_HALF_DEG)
	var best = null
	var best_score := 1e9
	for e in game.enemies:
		if not is_instance_valid(e.node) or float(e.hp) <= 0.0 or not game.target_ok(e):
			continue
		var v := Vector2(float(e.node.position.x) - po.x, float(e.node.position.z) - po.z)
		var dist := v.length()
		var er: float = float(e.node.get_meta("r", 3.0))
		if dist > range_u + er:
			continue
		var ang := 0.0
		if dist > 0.01:
			ang = absf(wd.angle_to(v))
		if ang > half + atan2(er, maxf(dist, 0.5)):
			continue
		var score := ang + dist / range_u * 0.35
		if is_same(e, _aim_prev):
			score -= 0.15   # histerezis: konunun kenarinda hedef titremesin
		if score < best_score:
			best_score = score
			best = e
	return best


# En yakin gorunur dusmani bul (NPC ya da dusman sirket oyuncusu). Menzil siniri YOK:
# uzaktaysa gemi hedefe yaklasip ates eder. Aim stick kisa tap ile kullanilir.
func _find_nearest_enemy() -> Object:
	var best = null
	var best_dist := 1e9
	if game.P == null or not is_instance_valid(game.P.node):
		return null
	var po: Vector3 = game.P.node.position
	for e in game.enemies:
		if not is_instance_valid(e.node) or float(e.hp) <= 0.0 or not e.node.visible or not game.target_ok(e):
			continue
		var v := Vector2(float(e.node.position.x) - po.x, float(e.node.position.z) - po.z)
		var dist := v.length()
		if dist < best_dist:
			best_dist = dist
			best = e
	return best


# Hedef joystigi dokunusu: en yakin dusmani sec ve atesi baslat.
func _fire_nearest() -> void:
	# Zaten gecerli bir hedef isaretliyse (elle secilmis ya da onceki atesten kalmis) onu DEGISTIRME:
	# yalnizca atesi yeniden baslat. Hedef yoksa / olduyse en yakin dusman NPC ya da oyuncu secilir.
	var cur = game.target
	if cur != null and is_instance_valid(cur.node) and float(cur.hp) > 0.0 and cur.node.visible and game.target_ok(cur):
		game._cancel_collect()
		_haptic(30)
		game._set_fire(true)
		return
	var t = _find_nearest_enemy()
	if t == null or not is_instance_valid(t.node):
		game.toast("Yakinda hedef yok.")
		return
	game._cancel_collect()
	game.target = t
	_haptic(30)
	game._set_fire(true)


# Koninin ekrandaki sekli: dunya uzayinda yay uzerinden, kameradan gecirilerek hesaplanir (perspektife uyar).
# _cone_rings[i] = i. serit sinirinin yayi (CONE_BANDS adet; sonuncusu menzilin ucu).
func _build_cone(cam: Camera3D, po: Vector3, wd: Vector2) -> void:
	var range_u: float = DOData.LASER_RANGE * DOData.S * AIM_RANGE_MUL
	var half := deg_to_rad(AIM_HALF_DEG)
	var inv := get_global_transform_with_canvas().affine_inverse()
	_cone_apex = inv * cam.unproject_position(Vector3(po.x, 0.0, po.z))
	_cone_rings.clear()
	for ri in CONE_BANDS:
		var rr := range_u * float(ri + 1) / float(CONE_BANDS)
		var pts := PackedVector2Array()
		for k in range(CONE_STEPS + 1):
			var t := lerpf(-half, half, float(k) / float(CONE_STEPS))
			var dv := wd.rotated(t) * rr
			pts.append(inv * cam.unproject_position(Vector3(po.x + dv.x, 0.0, po.z + dv.y)))
		_cone_rings.append(pts)


# WarUniverse tarzi: dolgun yari saydam kama + menzil seritleri (acik/koyu dönüşümlü) + net kenar cizgileri.
func _draw_aim() -> void:
	if _cone_rings.size() < CONE_BANDS:
		return
	var a := clampf(alpha + 0.15, 0.6, 1.0)
	var bc := Color(0.12, 0.74, 0.80)
	if _cone_hot:
		bc = Color(0.95, 0.14, 0.12)
	# seritler
	for bi in CONE_BANDS:
		var ring: PackedVector2Array = _cone_rings[bi]
		var fade := 1.0 - 0.40 * float(bi) / float(CONE_BANDS - 1)
		var al := (0.42 if bi % 2 == 0 else 0.28) * fade * a
		var col := Color(bc.r, bc.g, bc.b, al)
		var cols4 := PackedColorArray([col, col, col, col])
		for k in range(CONE_STEPS):
			if bi == 0:
				draw_primitive(PackedVector2Array([_cone_apex, ring[k], ring[k + 1]]), PackedColorArray([col, col, col]), PackedVector2Array())
			else:
				var prev: PackedVector2Array = _cone_rings[bi - 1]
				draw_primitive(PackedVector2Array([prev[k], prev[k + 1], ring[k + 1], ring[k]]), cols4, PackedVector2Array())
	# serit sinirlari (ince) ve menzil ucu (kalin)
	for bi in CONE_BANDS:
		var rg: PackedVector2Array = _cone_rings[bi]
		var last := bi == CONE_BANDS - 1
		draw_polyline(rg, Color(bc.r, bc.g, bc.b, (0.95 if last else 0.40) * a), 3.0 if last else 1.3, true)
	# yan kenarlar
	var first: PackedVector2Array = _cone_rings[0]
	var outer: PackedVector2Array = _cone_rings[CONE_BANDS - 1]
	var edge := Color(bc.r, bc.g, bc.b, 0.95 * a)
	draw_line(_cone_apex, first[0], edge, 2.5, true)
	draw_line(_cone_apex, first[CONE_STEPS], edge, 2.5, true)
	draw_line(first[0], outer[0], edge, 2.5, true)
	draw_line(first[CONE_STEPS], outer[CONE_STEPS], edge, 2.5, true)
	# ince merkez cizgisi
	draw_line(_cone_apex, outer[int(CONE_STEPS * 0.5)], Color(1, 1, 1, 0.22 * a), 1.2, true)
	# hedef isareti
	if _reticle.x >= 0.0:
		for k in 4:
			var s0 := float(k) * PI * 0.5 + PI * 0.25 - 0.4
			draw_arc(_reticle, 30.0, s0, s0 + 0.8, 10, Color(1.0, 0.25, 0.22, a), 3.5, true)
		draw_circle(_reticle, 3.0, Color(1.0, 0.25, 0.22, a))


func _aim_fire(e) -> void:
	game._cancel_collect()
	game.target = e
	_haptic(30)
	game._set_fire(true)


# ------------------------------------------------------------------ buyuk harita

func _map_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var mw := 21000.0
	var mh := 13100.0
	if hud != null and hud.minimap != null:
		mw = float(hud.minimap.map_w)
		mh = float(hud.minimap.map_h)
	var asp := mw / maxf(mh, 1.0)
	var w := minf(vs.x * 0.74, vs.y * 0.70 * asp)
	var h := w / asp
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5 + 12.0, w, h)


func _open_map() -> void:
	if _map_open or edit_mode or not active:
		return
	# Hareket stick'ini koru: harita acilirken parmak cikmasin, hareket devam etsin.
	# _reset_pointers() stick_move.end() cagirir ve hareketi durdurur; bunu engelle.
	if stick_move != null and stick_move.active:
		_map_preserved_move_active = true
		for k in _ptr.keys():
			if _ptr[k]["ctl"] == stick_move:
				_map_preserved_move_touch = k
				break
	# Digel pointer'lari temizle, hareket stick'ini sonlandirma
	var to_clear := []
	for k in _ptr.keys():
		if _ptr[k]["ctl"] != stick_move:
			to_clear.append(k)
	for k in to_clear:
		var c = _ptr[k]["ctl"]
		if c != null:
			c.set_pressed(false)
		_ptr.erase(k)
	_map_open = true
	if mapview != null:
		mapview.visible = true
		mapview.queue_redraw()


func _close_map() -> void:
	_map_open = false
	_swallow_until = _now() + 0.3
	if mapview != null:
		mapview.visible = false
	# Hareket stick'ini durdur: parmak harita acilirken kalktiyorsa stick'i bitir.
	# Parmak haliyle basiliysa stick calismaya devam eder.
	if _map_preserved_move_active and stick_move != null and stick_move.active:
		if not _ptr.has(_map_preserved_move_touch):
			stick_move.end()
	_map_preserved_move_active = false
	_map_preserved_move_touch = -1


# Haritada bir noktaya dokunus: gemi oraya gider, harita kapanir. Disina ya da X'e dokunus: sadece kapanir.
func _map_tap(p: Vector2) -> void:
	var rc := _map_rect()
	if p.distance_to(Vector2(rc.end.x + 6.0, rc.position.y - 6.0)) <= 38.0:
		_close_map()
		return
	if rc.has_point(p):
		var mw := float(hud.minimap.map_w)
		var mh := float(hud.minimap.map_h)
		var wx := (p.x - rc.position.x) / rc.size.x * mw * ws
		var wz := (p.y - rc.position.y) / rc.size.y * mh * ws
		game._cancel_collect()
		game.holding = false
		game.dest = game._clamp_map(Vector3(wx, 0.0, wz))
		_haptic(20)
	_close_map()


# ------------------------------------------------------------------ duzenleme modu

func _select(id: String) -> void:
	_sel = id
	for k in ctls:
		var c: MCtl = ctls[k]
		var s: bool = (k == id)
		if c.edit_sel != s:
			c.edit_sel = s
			c.queue_redraw()
	queue_redraw()


func _set_edit(v: bool) -> void:
	edit_mode = v
	_reset_pointers()
	_menu_open = false
	hud.top_left.visible = false
	_txt_btns["edit_open"].visible = false
	for id in ["e_minus", "e_plus", "e_alpha", "e_reset", "e_done"]:
		_txt_btns[id].visible = v
	_select("")
	for c in ctls.values():
		c.queue_redraw()
	queue_redraw()
	if not v:
		_save_cfg()


func _edit_action(id: String) -> void:
	match id:
		"edit_open":
			_set_edit(true)
		"e_done":
			_set_edit(false)
		"e_minus":
			_resize_sel(-0.1)
		"e_plus":
			_resize_sel(0.1)
		"e_alpha":
			var k := 0
			var best := 9.0
			for i in ALPHAS.size():
				var dd := absf(float(ALPHAS[i]) - alpha)
				if dd < best:
					best = dd
					k = i
			alpha = float(ALPHAS[(k + 1) % ALPHAS.size()])
			_cfg.set_value("ui", "alpha", alpha)
			_save_cfg()
			for c in ctls.values():
				c.queue_redraw()
		"e_reset":
			_reset_layout()


func _resize_sel(delta: float) -> void:
	if _sel != "" and ctls.has(_sel):
		var c: MCtl = ctls[_sel]
		c.uscale = clampf(c.uscale + delta, 0.6, 1.8)
		_cfg.set_value("sc", _sel, c.uscale)
	else:
		gscale = clampf(gscale + delta, 0.7, 1.5)
		_cfg.set_value("ui", "scale", gscale)
	_save_cfg()
	apply_layout()


func _reset_layout() -> void:
	if _cfg.has_section("pos"):
		_cfg.erase_section("pos")
	if _cfg.has_section("sc"):
		_cfg.erase_section("sc")
	gscale = 1.0
	alpha = 0.85
	_cfg.set_value("ui", "scale", gscale)
	_cfg.set_value("ui", "alpha", alpha)
	for c in ctls.values():
		c.uscale = 1.0
	_save_cfg()
	_select("")
	apply_layout()
	game.toast("HUD varsayilan duzene dondu.")


func _commit_drag(c: MCtl) -> void:
	var vs := get_viewport_rect().size
	_cfg.set_value("pos", c.cid, Vector2(c.cpos.x / maxf(vs.x, 1.0), c.cpos.y / maxf(vs.y, 1.0)))
	if c is MStick:
		(c as MStick).home = c.position
	_save_cfg()


func _save_cfg() -> void:
	_cfg.save(CFG_PATH)


# ------------------------------------------------------------------ canli guncelleme

func _process(dt: float) -> void:
	if not active or hud == null:
		return
	if not _live():
		# Hareket parmagi hala basiliysa hatirla; arayuz geri gelince joystick kaldigi yerden devam etsin.
		if stick_move != null and stick_move.active and _resume_move_id < 0:
			for k in _ptr.keys():
				if _ptr[k]["ctl"] == stick_move and _down.has(k):
					_resume_move_id = int(k)
					break
		if not _ptr.is_empty() or _driving or _aim_show:
			_reset_pointers()
		if _map_open:
			_close_map()
		return
	if _resume_move_id >= 0:
		var rid := _resume_move_id
		_resume_move_id = -1
		if _down.has(rid) and not _ptr.has(rid) and not edit_mode and not _map_open and stick_move != null and not stick_move.active:
			var rg: Vector2 = _down[rid]
			_start_float_move(rid, _to_local(rg), rg, _now())
	stick_move.smooth(dt, SMOOTH_MOVE)
	stick_aim.smooth(dt, SMOOTH_AIM)
	if not edit_mode:
		_drive_move()
		_update_aim()
	_update_vision_ring()
	_acc += dt
	if _acc >= 0.1:
		_acc = 0.0
		# Radar ve buyuk harita 10 Hz cizilir (her karede cizmek telefonda agir)
		if minimap_btn != null:
			minimap_btn.queue_redraw()
		if _map_open and mapview != null:
			mapview.queue_redraw()
		_icon_t -= 0.1
		if _icon_t <= 0.0:
			_icon_t = 3.0
			_load_icons()
		_refresh()


func _load_icons() -> void:
	if game.SV.is_empty():
		return
	for id in ctls:
		var c = ctls[id]
		if c is MBtn and not c.item.is_empty() and c.icon == null:
			var lk: Dictionary = hud._item_look(c.item)
			c.icon = lk["icon"]
			if c.icon == null and str(c.item.get("k", "")) == "ext":
				c.label = str(lk["label"])
			c.queue_redraw()


func _refresh() -> void:
	if game.SV.is_empty():
		return
	hud.minimap_win.visible = false
	if minimap_btn != null:
		minimap_btn.queue_redraw()
	if _map_open and mapview != null:
		mapview.queue_redraw()
	var near_portal := false
	if game.P != null and is_instance_valid(game.P.node):
		for p in game.portals:
			if game.P.node.position.distance_to(p.pos) < DOData.PORTAL_RANGE * DOData.S:
				near_portal = true
				break
	for id in ctls:
		var c = ctls[id]
		if not (c is MBtn):
			continue
		var b: MBtn = c
		if not b.item.is_empty():
			var st: Array = hud._item_state(b.item)
			var cdv := 0.0
			var k := str(b.item.get("k", ""))
			if k == "ext":
				cdv = float(hud._item_cd(b.item))
			elif k == "rkt":
				cdv = clampf(float(game.rocket_cd) / 5.0, 0.0, 1.0)
			elif b.cid == "rsb":
				cdv = clampf(float(game.rsb_cd) / 3.0, 0.0, 1.0)
			b.set_state(str(st[0]), bool(st[1]), bool(st[2]), cdv)
			continue
		match b.cid:
			"fire":
				b.set_state("", bool(game.fire), true, 0.0)
			"menu", "hudedit":
				b.set_state("", false, true, 0.0)
			"info":
				b.set_state("", bool(hud.user_win.visible), true, 0.0)
			"box":
				b.set_state("", game.collect_box != null, true, 0.0)
			"grp":
				b.set_state("", bool(hud.group_win.visible), true, 0.0)
			"chat":
				b.set_state("", bool(hud.chat_win.visible), true, 0.0)
			"jump":
				b.set_state("", near_portal or float(game.jump_t) >= 0.0, true, 0.0)
			"dzl":
				b.set_state("", false, true, 0.0)
			"cfg":
				var ci := int(game.SV.get("cfgi", 0))
				b.label = "K%d" % (ci + 1)
				var ccd := 0.0
				if not bool(game.in_safe):
					ccd = clampf(float(game.cfg_cool) / 5.0, 0.0, 1.0)
				b.set_state("", ci == 1, true, ccd)
	var has_t: bool = game.target != null
	if has_t != _aim_lock_prev:
		_aim_lock_prev = has_t
		stick_aim.locked = has_t
		stick_aim.queue_redraw()
