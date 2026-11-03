extends Control
# DarkOrbit savas HUD'u - HUD_Paketi'ndeki GERCEK parcalarla:
#   pencere cercevesi : window.swf (8 parcali cerceve, assets/hud/frame)
#   bar ve slot       : window.swf / ui.swf bitmap'leri (assets/hud/bar, assets/hud/slot)
#   ikonlar           : featuresMenu / itemsControlMenu atlaslari (assets/hud/features, assets/hud/items)
#   yazi tipi         : Verdana / Tahoma (paketteki XML stilleri)  renkler: XML'den
#
# Sol ust: kullanici bilgisi + gorev takibi | Ust orta: hedef | Sag ust: minimap + ozellik menusu
# Alt orta: cephane / roket / ates | Sol alt: sohbet | Pencereler: Arkadaslar [F], Gorevler [Q]

const DOData = preload("res://data.gd")
const MiniMap = preload("res://minimap.gd")
const HUD := "res://assets/hud/"
const DroneForms = preload("res://drone_forms.gd")
const C_TITLE := Color(0.749, 0.749, 0.749)      # 0xBFBFBF
const C_YELLOW := Color(1.0, 0.8, 0.0)           # 0xFFCC00
const C_CAPTION := Color(0.59, 0.67, 0.73)
const C_TEXT := Color(0.93, 0.93, 0.93)          # 0xEEEEEE
const C_TAB_ON := Color(0.914, 0.886, 0.753)     # 0xE9E2C0
const C_TAB_OFF := Color(0.435, 0.698, 0.796)    # 0x6FB2CB
const C_SENDER := Color(0.0, 0.8, 1.0)           # 0x00CCFF
const C_LINE := Color(0.18, 0.518, 0.647)        # 0x2E84A5
const MAX_FRIENDS := 50
const PITCH := 43.0
const CELL := 40.0
const Extras := preload("res://extras.gd")
const MobileHud = preload("res://mobile_hud.gd")

var game = null
var mobile = null            # mobile_hud.gd (telefon arayuzu: joystick + tasinabilir butonlar)
var minimap = null
var lbl_toast: Label
var lbl_prompt: Label
var lbl_help: Label

var user_win: DOWin
var target_win: DOWin
var tracker_win: DOWin
var minimap_win: DOWin
var chat_win: DOWin
var contacts_win: DOWin
var quests_win: DOWin
var abar: Control
var top_left: Control
var top_right: Control
var menu_btns: Array = []
var cat_btns := {}
var top_cells: Array = []     # ust sira (secili kategorinin ogeleri)
var quick_cells: Array = []   # alt sira (surukleyip biraktigin hizli slotlar)
var quick: Array = []         # alt sira icerigi: her eleman {} (bos) ya da {"k":..,"id":..}
var cur_cat := "lasers"
var _cat_sig := ""
var _quick_loaded := false
var _rows_on := true

var f_reg: SystemFont
var f_bold: SystemFont

var u_logo: TextureRect
var u_name: Label
var u_lv: Label
var u_sh: DOBar
var u_hp: DOBar
var u_ep: Label
var u_hon: Label
var u_uri: Label
var u_cr: Label
var u_cfg: Label
var t_name: Label
var t_dist: Label
var t_sh: DOBar
var t_hp: DOBar
var q_title: Label
var q_bar: DOBar
var chat_out: RichTextLabel
var chat_in: LineEdit
var chat_tab_btns: Array = []
var chat_tab_ids: Array = [0, 2, 3, 1]   # buton sirasi -> sekme: GENEL, SIRKET, GRUP, SISTEM
var chat_tab := 0

# ---- Grup penceresi
var group_win: DOWin
var grp_sel := 0                 # tiklanan ayni sirket oyuncusunun peer id'si
var grp_head: Label
var grp_sel_lbl: Label
var grp_sel_btn: Button
var grp_inv_box: Control
var grp_inv_lbl: Label
var grp_inv_from := 0
var grp_inv_name := ""
var grp_box: VBoxContainer
var grp_leave_btn: Button
var _grp_sig := ""
var chat_lines: Array = [[], [], [], []]   # 0 genel, 1 sistem, 2 sirket, 3 grup
var friend_in: LineEdit
var friend_box: VBoxContainer
var friend_count: Label
var quest_box: VBoxContainer

var _logo_fac := -1
var _tick := 0.0
var _quest_sig := ""
var _friend_sig := ""
var contact_status := {}   # ad -> "online" / "away" / "busy" / "offline" (sunucu baglaninca doldurulabilir)

# ------------------------------------------------------------------ yardimci siniflar

static func _mkfont(bold: bool) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Verdana", "Tahoma", "Segoe UI", "Arial"])
	f.font_weight = 700 if bold else 400
	return f


class DOWin extends Control:
	# DarkOrbit penceresi: window.swf'in 8 parcali cercevesi (sol ust 41x36, sag ust 81x36, alt 20 px)
	const HEAD := 36.0
	const BOT := 20.0
	const BODY_COL := Color(0.02, 0.05, 0.08, 0.80)
	var title := ""
	var subtitle := ""
	var body: Control
	var moved := false
	var locked := false   # mobil: minimap gibi sabit pencereler suruklenemez
	var _tex := {}
	var _font: SystemFont
	var _drag := false
	var _drag_off := Vector2.ZERO

	func setup(t: String, sz: Vector2) -> void:
		title = t
		size = sz
		mouse_filter = Control.MOUSE_FILTER_STOP
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Verdana", "Tahoma", "Segoe UI", "Arial"])
		_font.font_weight = 700
		for k in ["tl", "t", "tr", "l", "r", "bl", "b", "br"]:
			var p := "res://assets/hud/frame/%s.png" % k
			if ResourceLoader.exists(p):
				_tex[k] = load(p)
		body = Control.new()
		body.position = Vector2(0, HEAD)
		body.size = Vector2(sz.x, sz.y - HEAD - BOT)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)
		add_child(_btn("close", Vector2(sz.x - 26.0, 9), hide))
		add_child(_btn("min", Vector2(sz.x - 48.0, 9), hide))

	func _btn(n: String, pos: Vector2, cb: Callable) -> TextureButton:
		var b := TextureButton.new()
		var p := "res://assets/hud/win/%s_%s.png"
		if ResourceLoader.exists(p % [n, "n"]):
			b.texture_normal = load(p % [n, "n"])
			b.texture_hover = load(p % [n, "h"])
			b.texture_pressed = load(p % [n, "p"])
		b.position = pos
		b.pressed.connect(cb)
		return b

	func resize_to(sz: Vector2) -> void:
		size = sz
		body.size = Vector2(sz.x, sz.y - HEAD - BOT)
		var n := 0
		for c in get_children():
			if c is TextureButton:
				c.position.x = sz.x - 26.0 - 22.0 * n
				n += 1
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.position.y < HEAD and not locked:
				_drag = true
				_drag_off = get_global_mouse_position() - global_position
			else:
				_drag = false
			accept_event()
		var mo := ev as InputEventMouseMotion
		if mo != null and _drag:
			var vs := get_viewport_rect().size
			var p := get_global_mouse_position() - _drag_off
			global_position = Vector2(clampf(p.x, 0.0, vs.x - 60.0), clampf(p.y, 0.0, vs.y - HEAD))
			moved = true
			accept_event()

	func _input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if _drag and mb != null and not mb.pressed:
			_drag = false

	func _draw() -> void:
		var sz := size
		if not _tex.has("tl"):
			draw_rect(Rect2(Vector2.ZERO, sz), BODY_COL)
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.18, 0.52, 0.65), false, 1.0)
			return
		var t_tl: Texture2D = _tex["tl"]
		var t_tr: Texture2D = _tex["tr"]
		var t_bl: Texture2D = _tex["bl"]
		var lm := float(t_tl.get_width())
		var rm := float(t_tr.get_width())
		var tm := float(t_tl.get_height())
		var bm := float(t_bl.get_height())
		draw_rect(Rect2(2.0, tm - 2.0, sz.x - 4.0, sz.y - tm - bm + 4.0), BODY_COL)
		draw_texture_rect(_tex["t"], Rect2(lm, 0, sz.x - lm - rm, tm), true)
		draw_texture_rect(_tex["b"], Rect2(lm, sz.y - bm, sz.x - lm - rm, bm), true)
		draw_texture_rect(_tex["l"], Rect2(0, tm, lm, sz.y - tm - bm), true)
		draw_texture_rect(_tex["r"], Rect2(sz.x - rm, tm, rm, sz.y - tm - bm), true)
		draw_texture(t_tl, Vector2.ZERO)
		draw_texture(t_tr, Vector2(sz.x - rm, 0))
		draw_texture(t_bl, Vector2(0, sz.y - bm))
		draw_texture(_tex["br"], Vector2(sz.x - rm, sz.y - bm))
		draw_string(_font, Vector2(14, 22), title, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 120.0, 11, Color(0.749, 0.749, 0.749))
		if subtitle != "":
			draw_string(_font, Vector2(0, 22), subtitle, HORIZONTAL_ALIGNMENT_RIGHT, sz.x - 60.0, 10, Color(0.75, 0.88, 0.95))


class DOBar extends Control:
	# window.swf'in gercek bar izi (127) + dolgu (170'ten renklendirilmis)
	var value := 1.0
	var text := ""
	var _track: StyleBoxTexture = null
	var _fill: StyleBoxTexture = null
	var _font: SystemFont
	var smooth_up := false   # dolarken bar yumusakca yukselir (tamir animasyonu); dusus anlik
	var rep := false          # tamir aktif: yesil parlama + kucuk "+" simgesi
	var shown := 1.0

	func setup(kind: String) -> void:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Verdana", "Tahoma", "Segoe UI", "Arial"])
		_font.font_weight = 700
		_track = _sb("res://assets/hud/bar/track.png", 12, 8)
		_fill = _sb("res://assets/hud/bar/fill_%s.png" % kind, 8, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)   # yalnizca tamir animasyonu sirasinda calisir (FPS etkisi yok)

	func _sb(path: String, mh: int, mv: int) -> StyleBoxTexture:
		if not ResourceLoader.exists(path):
			return null
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		sb.texture_margin_left = mh
		sb.texture_margin_right = mh
		sb.texture_margin_top = mv
		sb.texture_margin_bottom = mv
		return sb

	func set_val(v: float, t: String) -> void:
		if absf(v - value) > 0.0005 or t != text:
			value = v
			text = t
			if not smooth_up or v < shown:
				shown = v
			queue_redraw()
		set_process(smooth_up and (rep or shown < value - 0.001))

	func set_rep(on: bool) -> void:
		if on != rep:
			rep = on
			queue_redraw()
		set_process(smooth_up and (rep or shown < value - 0.001))

	func _process(dt: float) -> void:
		if shown < value:
			shown = minf(value, shown + dt * 0.9)
		if not rep and shown >= value - 0.001:
			shown = value
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var s := size
		if _track != null:
			draw_style_box(_track, Rect2(Vector2.ZERO, s))
		else:
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.04, 0.06))
		var w := (s.x - 6.0) * clampf(shown if smooth_up else value, 0.0, 1.0)
		if w >= 10.0 and _fill != null:
			draw_style_box(_fill, Rect2(3.0, 3.0, w, s.y - 6.0))
		elif w > 0.0:
			draw_rect(Rect2(3.0, 3.0, w, s.y - 6.0), Color(0.3, 0.7, 0.3))
		if smooth_up and (rep or shown < value - 0.001):
			var pul := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			if w > 0.0:
				draw_rect(Rect2(3.0, 3.0, w, s.y - 6.0), Color(0.6, 1.0, 0.65, 0.12 + 0.18 * pul))
			# kucuk tamir simgesi (+): barin sag ucunda
			var c := Vector2(s.x - 11.0, s.y * 0.5)
			var ic := Color(0.45, 1.0, 0.55, 0.65 + 0.35 * pul)
			draw_rect(Rect2(c.x - 4.0, c.y - 1.0, 8.0, 2.0), ic)
			draw_rect(Rect2(c.x - 1.0, c.y - 4.0, 2.0, 8.0), ic)
		var fs := 10
		var p := Vector2(0, s.y * 0.5 + fs * 0.38)
		draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_CENTER, s.x, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_CENTER, s.x, fs, Color(1, 1, 1))


class DOIconBtn extends Control:
	# DarkOrbit'in koseleri kesik (sekizgen) ikon dugmesi; secili = altin cerceve
	signal pressed
	var icon: Texture2D = null
	var icon_h: Texture2D = null
	var glyph := ""          # "up" / "down" (ok dugmeleri icin)
	var selected := false
	var _hover := false
	var _down := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)

	func _on_enter() -> void:
		_hover = true
		queue_redraw()

	func _on_exit() -> void:
		_hover = false
		_down = false
		queue_redraw()

	func set_sel(v: bool) -> void:
		if v != selected:
			selected = v
			queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = true
			elif _down:
				_down = false
				pressed.emit()
			queue_redraw()
			accept_event()

	func _oct(s: Vector2, c: float, inset: float) -> PackedVector2Array:
		var i := inset
		return PackedVector2Array([
			Vector2(c, i), Vector2(s.x - c, i), Vector2(s.x - i, c), Vector2(s.x - i, s.y - c),
			Vector2(s.x - c, s.y - i), Vector2(c, s.y - i), Vector2(i, s.y - c), Vector2(i, c)])

	func _draw() -> void:
		var s := size
		var c := 7.0 if s.x > 34.0 else 6.0
		var fill := Color(0.05, 0.09, 0.12, 0.93)
		if _down:
			fill = Color(0.03, 0.06, 0.08, 0.96)
		elif _hover:
			fill = Color(0.09, 0.15, 0.2, 0.95)
		draw_colored_polygon(_oct(s, c, 0.0), fill)
		draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.45, s.y), Vector2(s.x, s.y * 0.45), Vector2(s.x, s.y - c), Vector2(s.x - c, s.y)]), Color(1, 1, 1, 0.035))
		var bc := Color(0.92, 0.74, 0.22) if selected else (Color(0.3, 0.7, 0.9) if _hover else Color(0.16, 0.5, 0.66))
		var o := _oct(s, c, 0.5)
		o.append(o[0])
		draw_polyline(o, bc, 1.5 if selected else 1.0, true)
		var o2 := _oct(s, c - 1.0, 2.5)
		o2.append(o2[0])
		draw_polyline(o2, Color(bc.r, bc.g, bc.b, 0.3), 1.0, true)
		var ic: Texture2D = icon_h if (_hover and icon_h != null) else icon
		if ic != null:
			draw_texture_rect(ic, Rect2(Vector2.ZERO, s), false)
		if glyph != "":
			var cx := s.x * 0.5
			var cy := s.y * 0.5
			var gc := Color(0.55, 0.82, 0.95)
			if glyph == "up":
				draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, cy + 1), Vector2(cx + 7, cy + 1), Vector2(cx, cy - 6)]), gc)
				draw_line(Vector2(cx - 7, cy + 5), Vector2(cx + 7, cy + 5), gc, 2.0)
			else:
				draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, cy - 1), Vector2(cx + 7, cy - 1), Vector2(cx, cy + 6)]), gc)
				draw_line(Vector2(cx - 7, cy - 5), Vector2(cx + 7, cy - 5), gc, 2.0)


class DOCell extends Control:
	# Cephane / esya hucresi: ustte mavi seri, koyu cizgili zemin, kesik koseli cerceve
	# Surukle-birak: ust siradaki hucre surukleyip alt siradaki (kind == "quick") hucreye birakilir.
	signal pressed
	signal dropped(data)
	signal cleared
	var icon: Texture2D = null
	var label := ""              # ikon yoksa hucrenin ortasina yazilan kisa ad
	var payload: Dictionary = {} # bos = bos hucre
	var pts: PackedVector2Array = PackedVector2Array()  # dizilim resmi: (yana, ileri) birim noktalar
	const CELL_SZ := 40.0
	var kind := "cat"            # "cat" (ust sira) / "quick" (alt sira, hizli slot)
	var slot_index := -1
	var key := ""
	var count := ""
	var selected := false
	var has := false
	var cd_frac := 0.0           # bekleme orani (0..1): ikonun ustune inen koyu perde
	var interactive := true
	var _hover := false
	var _down := false
	var _font: SystemFont

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Verdana", "Tahoma", "Segoe UI", "Arial"])
		_font.font_weight = 700

	func _on_enter() -> void:
		_hover = true
		queue_redraw()

	func _on_exit() -> void:
		_hover = false
		queue_redraw()

	func set_state(c: String, sel: bool, h: bool) -> void:
		if c != count or sel != selected or h != has:
			count = c
			selected = sel
			has = h
			queue_redraw()

	func set_cd(f: float) -> void:
		if absf(f - cd_frac) > 0.004 or (f == 0.0 and cd_frac != 0.0):
			cd_frac = f
			queue_redraw()

	func set_item(p: Dictionary, ic: Texture2D, lb: String, tip: String, k: String, pp := PackedVector2Array()) -> void:
		payload = p
		pts = pp
		icon = ic
		label = lb
		tooltip_text = tip
		key = k
		if p.is_empty():
			count = ""
			selected = false
			has = false
			cd_frac = 0.0
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = true
			else:
				# Kullanim BIRAKINCA tetiklenir; surukleme basladiysa birakma olayi buraya gelmez.
				if _down and Rect2(Vector2.ZERO, size).has_point(mb.position) and not payload.is_empty():
					pressed.emit()
				_down = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and kind == "quick":
			cleared.emit()
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if payload.is_empty():
			return null
		_down = false
		var prev := Control.new()
		var pv := DOCell.new()
		pv.size = Vector2(CELL_SZ, CELL_SZ)
		pv.position = Vector2(-CELL_SZ * 0.5, -CELL_SZ * 0.5)
		pv.icon = icon
		pv.label = label
		pv.pts = pts
		pv.payload = payload
		pv.has = true
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pv.modulate = Color(1, 1, 1, 0.85)
		prev.add_child(pv)
		set_drag_preview(prev)
		return {"hud_item": payload.duplicate(), "from_quick": slot_index if kind == "quick" else -1}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return kind == "quick" and typeof(data) == TYPE_DICTIONARY and data.has("hud_item")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		dropped.emit(data)

	func _draw_formation(s: Vector2) -> void:
		# gemi + droid noktalari kutuya sigacak sekilde ortalanir ve olceklenir
		var mn := Vector2(0, 0)
		var mx := Vector2(0, 0)
		for p in pts:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		var span := maxf(maxf(mx.x - mn.x, mx.y - mn.y), 0.1)
		var sc := (s.x - 16.0) / span
		var mid := (mn + mx) * 0.5
		var cen := Vector2(s.x * 0.5, s.y * 0.5 + 1.0)
		var dc := Color(0.35, 0.82, 1.0) if has else Color(0.45, 0.5, 0.55)
		for p in pts:
			var q := cen + Vector2(p.x - mid.x, -(p.y - mid.y)) * sc
			draw_circle(q, 3.3, Color(0, 0, 0, 0.7))
			draw_circle(q, 2.6, dc)
		var sp := cen + Vector2(-mid.x, mid.y) * sc
		draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -5), sp + Vector2(3.5, 4), sp + Vector2(-3.5, 4)]), Color(0.95, 0.78, 0.25))

	func _draw() -> void:
		var s := size
		var c := 5.0
		var pts_oct := PackedVector2Array([Vector2(c, 0), Vector2(s.x - c, 0), Vector2(s.x, c), Vector2(s.x, s.y - c), Vector2(s.x - c, s.y), Vector2(c, s.y), Vector2(0, s.y - c), Vector2(0, c)])
		draw_colored_polygon(pts_oct, Color(0.075, 0.1, 0.125, 0.95) if not _hover else Color(0.1, 0.14, 0.18, 0.96))
		var y := 8.0
		while y < s.y - 3.0:
			draw_line(Vector2(3, y), Vector2(s.x - 3.0, y), Color(0, 0, 0, 0.22), 1.0)
			y += 3.0
		var bc := Color(0.92, 0.74, 0.22) if selected else Color(0.16, 0.5, 0.66)
		var ln := pts_oct.duplicate()
		ln.append(pts_oct[0])
		draw_polyline(ln, bc, 1.5 if selected else 1.0, true)
		draw_rect(Rect2(4, 3, s.x - 8.0, 3), Color(0.27, 0.4, 0.8) if has else Color(0.18, 0.2, 0.26))
		if icon != null:
			draw_texture_rect(icon, Rect2(Vector2(4, 7), Vector2(32, 32)), false, Color(1, 1, 1) if has else Color(0.6, 0.6, 0.6))
			if cd_frac > 0.0:
				var chh := 32.0 * clampf(cd_frac, 0.0, 1.0)
				draw_rect(Rect2(4.0, 39.0 - chh, 32.0, chh), Color(0, 0, 0, 0.62))
		elif pts.size() > 0:
			_draw_formation(s)
		elif label != "":
			draw_string_outline(_font, Vector2(2, s.y * 0.5 + 6.0), label, HORIZONTAL_ALIGNMENT_CENTER, s.x - 4.0, 9, 3, Color(0, 0, 0, 0.9))
			draw_string(_font, Vector2(2, s.y * 0.5 + 6.0), label, HORIZONTAL_ALIGNMENT_CENTER, s.x - 4.0, 9, Color(0.75, 0.92, 1.0) if has else Color(0.6, 0.6, 0.6))
		if key != "":
			draw_string_outline(_font, Vector2(4, s.y - 4.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0, 0, 0, 0.9))
			draw_string(_font, Vector2(4, s.y - 4.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.8, 0.0))
		if count != "" and not payload.is_empty():
			draw_string_outline(_font, Vector2(0, s.y - 4.0), count, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 3.0, 8, 3, Color(0, 0, 0, 0.9))
			draw_string(_font, Vector2(0, s.y - 4.0), count, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 3.0, 8, Color(1, 1, 1))

# ------------------------------------------------------------------ kurulum

func _init() -> void:
	f_reg = _mkfont(false)
	f_bold = _mkfont(true)


func build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = f_reg
	th.default_font_size = 11
	theme = th
	_build_user()
	_build_tracker()
	_build_minimap()
	_build_chat()
	_build_contacts()
	_build_quests()
	_build_group()
	_build_menu()
	_build_actionbar()
	_build_labels()
	mobile = MobileHud.new()
	mobile.game = game
	mobile.hud = self
	add_child(mobile)
	mobile.build()
	resized.connect(_layout)
	_layout()
	_log_system("NOVAGATE HUD hazir. Kisayollar: Enter sohbet, F arkadaslar, Q gorevler.")


func _win(title: String, sz: Vector2) -> DOWin:
	var w := DOWin.new()
	w.setup(title, sz)
	add_child(w)
	return w


func _lbl(parent: Node, pos: Vector2, fs: int, col: Color, w := 0.0, bold := false) -> Label:
	var l := Label.new()
	l.position = pos
	if w > 0.0:
		l.size = Vector2(w, fs + 6)
		l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f_bold if bold else f_reg)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	parent.add_child(l)
	return l


func _bar(parent: Node, pos: Vector2, sz: Vector2, kind: String) -> DOBar:
	var b := DOBar.new()
	b.position = pos
	b.size = sz
	b.setup(kind)
	parent.add_child(b)
	return b


func _stat(parent: Node, x: float, y: float, caption: String, col: Color) -> Label:
	_lbl(parent, Vector2(x, y), 10, C_CAPTION, 60.0).text = caption
	return _lbl(parent, Vector2(x + 52.0, y), 10, col, 90.0, true)


func _skin(b: Button, base: String) -> void:
	# DarkOrbit bitmap buton kaplamasi (160x62, dokuz-yama)
	for st in [["normal", base], ["hover", base + "_h"], ["pressed", base + "_h"], ["focus", base]]:
		var sb := StyleBoxTexture.new()
		sb.texture = game._tex(HUD + "win/btn_%s.png" % st[1])
		sb.texture_margin_left = 16
		sb.texture_margin_right = 16
		sb.texture_margin_top = 16
		sb.texture_margin_bottom = 16
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_font_override("font", f_bold)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.8))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 3)


func _build_user() -> void:
	user_win = _win("Gezgin", Vector2(292, 184))
	var b := user_win.body
	u_logo = TextureRect.new()
	u_logo.position = Vector2(12, 4)
	u_logo.size = Vector2(40, 22)
	u_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	u_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	u_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(u_logo)
	u_name = _lbl(b, Vector2(60, 0), 12, C_YELLOW, 200.0, true)
	u_lv = _lbl(b, Vector2(60, 16), 10, C_TITLE, 200.0)
	u_sh = _bar(b, Vector2(12, 36), Vector2(268, 18), "blue")
	u_hp = _bar(b, Vector2(12, 58), Vector2(268, 18), "green")
	u_hp.smooth_up = true
	u_ep = _stat(b, 12, 82, "EP", Color(1, 1, 1))
	u_ep.size.x = 200.0
	u_hon = _stat(b, 12, 98, "Honor", Color(1.0, 0.63, 0.24))
	u_uri = _stat(b, 146, 98, "Uridium", Color(0.84, 0.63, 1.0))
	u_cr = _stat(b, 12, 114, "Kredi", Color(1.0, 0.88, 0.4))
	u_cfg = _lbl(b, Vector2(146, 114), 10, Color(0.7, 1.0, 0.8), 134.0)


func _build_tracker() -> void:
	tracker_win = _win("Gorev Takibi", Vector2(292, 96))
	var b := tracker_win.body
	q_title = _lbl(b, Vector2(12, 2), 10, C_TEXT, 268.0)
	q_bar = _bar(b, Vector2(12, 22), Vector2(268, 18), "blue")
	var hit := Button.new()
	hit.flat = true
	hit.position = Vector2.ZERO
	hit.size = Vector2(292, 44)
	hit.tooltip_text = "Gorevleri ac [Q]"
	hit.modulate = Color(1, 1, 1, 0.0)
	hit.pressed.connect(toggle_quests)
	b.add_child(hit)


func _build_minimap() -> void:
	minimap_win = _win("", Vector2(230, 214))
	minimap = MiniMap.new()
	minimap.game = game
	minimap.title_win = minimap_win
	minimap.position = Vector2(10, 2)
	minimap.move_requested.connect(game._on_minimap_move)
	minimap_win.body.add_child(minimap)
	minimap.set_map("", 21000.0, 13100.0, null)


func _ibtn(atlas: String, folder: String, tip: String, cb: Callable, sz := 38.0) -> DOIconBtn:
	var b := DOIconBtn.new()
	b.size = Vector2(sz, sz)
	b.icon = game._tex(HUD + "%s/%s_normal.png" % [folder, atlas])
	b.icon_h = game._tex(HUD + "%s/%s_hover.png" % [folder, atlas])
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _open_log() -> void:
	chat_win.show()
	_set_chat_tab(1)


func _switch_cfg() -> void:
	game.switch_cfg(1 - int(game.SV.cfgi))


func _toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _build_menu() -> void:
	# DarkOrbit ust menu: sol ust 11 dugme, sag ust 3 dugme
	top_left = Control.new()
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.size = Vector2(8 * 39, 38)
	add_child(top_left)
	var defs := [
		["log", "Sistem mesajlari", _open_log, null],
		["user", "Bilgi penceresi", toggle_info, user_win],
		["ship", "Hangar / Kontrol paneli  [B]", game.toggle_base, null],
		["group", "Arkadaslar  [F]", toggle_contacts, contacts_win],
		["minimap", "Minimap", toggle_minimap, minimap_win],
		["quests", "Gorevler  [Q]", toggle_quests, quests_win],
		["chat", "Sohbet  [Enter]", toggle_chat, chat_win],
		["pet", "Gorev takibi", toggle_tracker, tracker_win],
	]
	for i in defs.size():
		var d: Array = defs[i]
		var b := _ibtn(d[0], "features", d[1], d[2])
		b.position = Vector2(i * 39, 0)
		top_left.add_child(b)
		menu_btns.append([b, d[3]])
	top_right = Control.new()
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.size = Vector2(3 * 39, 38)
	add_child(top_right)
	var defs2 := [
		["fullscreen", "Tam ekran", _toggle_fullscreen],
		["help", "Kontroller  [H]", game.toggle_help],
		["settings", "Kontrol paneli  [B]", game.toggle_base],
	]
	for i in defs2.size():
		var d2: Array = defs2[i]
		var b2 := _ibtn(d2[0], "features", d2[1], d2[2])
		b2.position = Vector2(i * 39, 0)
		top_right.add_child(b2)


func _short(v: float) -> String:
	var n := int(maxf(v, 0.0))
	if n < 10000:
		return str(n)
	if n < 1000000:
		return "%.1fk" % (float(n) / 1000.0)
	return "%.1fM" % (float(n) / 1000000.0)


const LASER_IDS := ["x1", "x2", "x3", "x4", "sab", "rsb"]
const LASER_ICONS := ["lcb-10", "mcb-25", "mcb-50", "ucb-100", "sab-50", "rsb-75"]
const LASER_TIPS := ["x1 cephane", "x2 cephane", "x3 cephane", "x4 cephane", "SAB-50 (kalkan emici)", "RSB-75 (hizli sarj)"]
const SUPPORTED_CATS := ["lasers", "rockets", "special_items", "drone_formations"]
const QUICK_N := 10
const TOP_N := 8


func _cell(pos: Vector2) -> DOCell:
	var c := DOCell.new()
	c.position = pos
	c.size = Vector2(CELL, CELL)
	abar.add_child(c)
	return c


func _cat_na(name_: String) -> void:
	game.toast("%s bu surumde yok." % name_)


func _on_cat(cat: String, name_: String) -> void:
	if not (cat in SUPPORTED_CATS):
		_cat_na(name_)
		return
	cur_cat = cat
	_cat_sig = ""
	_rebuild_top()


func _set_rows(v: bool) -> void:
	_rows_on = v
	for c in top_cells:
		c.visible = v
	for c in quick_cells:
		c.visible = v


func _items_for(cat: String) -> Array:
	var out: Array = []
	match cat:
		"lasers":
			for id in LASER_IDS:
				out.append({"k": "las", "id": id})
		"rockets":
			out.append({"k": "rkt", "id": "r310"})
		"special_items":
			for id in Extras.IDS:
				out.append({"k": "ext", "id": id})
		"drone_formations":
			if not game.SV.is_empty():
				for code in game.SV.get("forms", ["std"]):
					out.append({"k": "frm", "id": str(code)})
	return out


func _form_name(code: String) -> String:
	if DOData.FORMS.has(code):
		var fd = DOData.FORMS[code]
		if typeof(fd) == TYPE_DICTIONARY and fd.has("name"):
			return str(fd["name"])
	return code


func _item_look(p: Dictionary) -> Dictionary:
	# {"icon": Texture2D, "label": String, "tip": String, "key": String}
	var k := str(p.get("k", ""))
	var id := str(p.get("id", ""))
	if k == "las":
		var i := LASER_IDS.find(id)
		if i >= 0:
			return {"icon": _market_icon("res://assets/ui/ammo_%s.png" % id, "ammunition_laser_" + LASER_ICONS[i]), "label": "", "tip": LASER_TIPS[i], "key": str(i + 1)}
	elif k == "rkt":
		return {"icon": _market_icon("res://assets/ui/rocket_r310.png", "ammunition_rocket_r-310"), "label": "R-310", "tip": "Roket R-310  [R]  (secili = otomatik atis)", "key": "R"}
	elif k == "ext" and Extras.DEFS.has(id):
		var ed: Dictionary = Extras.DEFS[id]
		var etex: Texture2D = game.extras.icon(id)
		return {"icon": etex, "label": str(ed.name).substr(0, 6), "tip": str(ed.tip), "key": ""}
	elif k == "frm":
		var nm := _form_name(id)
		var fkey: String = DroneForms.key_for(id, DOData.FORMS.get(id, {}))
		if DroneForms.ICONS.has(fkey):
			var ftex: Texture2D = _icon_tex("drone_formation_" + str(DroneForms.ICONS[fkey]), "")
			if ftex != null:
				return {"icon": ftex, "label": "", "tip": "Droid dizilimi: " + nm, "key": ""}
		return {"icon": null, "label": "", "tip": "Droid dizilimi: " + nm, "key": "", "pts": _form_pts(id)}
	return {"icon": null, "label": "", "tip": "", "key": ""}


func _form_pts(code: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var offs: Array = game.form_offsets_for(code, 10)
	var rad := 0.01
	for v in offs:
		var v3: Vector3 = v
		rad = maxf(rad, Vector2(v3.x, v3.z).length())
	for v in offs:
		var w3: Vector3 = v
		out.append(Vector2(w3.x, w3.z) / rad)
	return out


func _fill_cell(c: DOCell, p: Dictionary, with_key: bool) -> void:
	if p.is_empty():
		c.set_item({}, null, "", "", str((c.slot_index + 1) % 10) if c.kind == "quick" else "")
		return
	var lk := _item_look(p)
	var ic: Texture2D = lk["icon"]
	var lb: String = lk["label"] if ic == null else ""
	var tip: String = str(lk["tip"])
	if c.kind == "quick":
		tip += "\n(sag tik: slotu bosalt)"
	if c.kind == "cat":
		tip += "\n(alt cubuga surukle)"
	var pp := PackedVector2Array()
	if lk.has("pts"):
		pp = lk["pts"]
	c.set_item(p, ic, lb, tip, str((c.slot_index + 1) % 10) if c.kind == "quick" else "", pp)


func _use_item(p: Dictionary) -> void:
	if game.SV.is_empty():
		return
	var id := str(p.get("id", ""))
	match str(p.get("k", "")):
		"las":
			game.select_ammo(id)   # RSB kuralari (bekleyen secimini engelle + onceki muhimmadi kaydet) tek yerde isler
		"rkt":
			game.toggle_rocket_auto()
		"frm":
			game.set_form(id)
		"ext":
			game.extras.use(id)


func _item_state(p: Dictionary) -> Array:
	# [sayi yazisi, secili mi, var mi]
	var SV: Dictionary = game.SV
	var id := str(p.get("id", ""))
	match str(p.get("k", "")):
		"las":
			var n := float(SV.ammo.get(id, 0))
			var st := [_short(n), str(SV.get("sel", "")) == id, n > 0.0]
			var cdv: float = 0.0
			if "rsb_cd" in game:
				cdv = float(game.rsb_cd)
			if id == "rsb" and cdv > 0.0:
				st[0] = str(int(ceil(cdv)))   # yeniden kullanim beklemesi
				st[2] = false
			return st
		"rkt":
			var rk := float(SV.get("rockets", 0))
			return [_short(rk), bool(game.rocket_auto), rk > 0.0]
		"frm":
			return ["", str(game.cfg().form) == id, id in SV.get("forms", [])]
		"ext":
			var cs: Array = game.extras.cell_state(id)
			return [cs[0], cs[1], cs[2]]
	return ["", false, false]


func _item_cd(p: Dictionary) -> float:
	# ekstralarin bekleme orani (0 = hazir, 1 = yeni kullanildi)
	if str(p.get("k", "")) == "ext":
		var cs: Array = game.extras.cell_state(str(p.get("id", "")))
		return float(cs[3])
	return 0.0


func _rebuild_top() -> void:
	var items := _items_for(cur_cat)
	for i in top_cells.size():
		var c: DOCell = top_cells[i]
		_fill_cell(c, items[i] if i < items.size() else {}, true)
	for k in cat_btns.keys():
		cat_btns[k].set_sel(k == cur_cat)


func _load_quick() -> void:
	_quick_loaded = true
	var raw = game.SV.get("quickbar", null)
	quick.clear()
	for i in QUICK_N:
		quick.append({})
	if raw is Array:
		for i in mini(raw.size(), QUICK_N):
			var parts := str(raw[i]).split(":")
			if parts.size() == 2 and parts[0] != "":
				quick[i] = {"k": parts[0], "id": parts[1]}
	else:
		quick[0] = {"k": "rkt", "id": "r310"}
	_refresh_quick_cells()


func _save_quick() -> void:
	var arr: Array = []
	for p in quick:
		arr.append("" if p.is_empty() else "%s:%s" % [str(p["k"]), str(p["id"])])
	game.SV["quickbar"] = arr
	game.save_game()


func _refresh_quick_cells() -> void:
	for i in quick_cells.size():
		_fill_cell(quick_cells[i], quick[i], false)


func _quick_use(i: int) -> void:
	if i >= 0 and i < quick.size() and not quick[i].is_empty():
		_use_item(quick[i])


func _quick_drop(data, i: int) -> void:
	var p: Dictionary = data["hud_item"]
	var from_q := int(data.get("from_quick", -1))
	if from_q >= 0 and from_q < quick.size() and from_q != i:
		quick[from_q] = quick[i]
	quick[i] = p.duplicate()
	_save_quick()
	_refresh_quick_cells()


func _quick_clear(i: int) -> void:
	quick[i] = {}
	_save_quick()
	_refresh_quick_cells()


func _build_actionbar() -> void:
	# DarkOrbit itemsControlMenu: ust sira = secili kategorinin ogeleri / orta sira = kategoriler /
	# alt sira = hizli slotlar (ustten surukleyip birak) + ok dugmeleri
	abar = Control.new()
	abar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	abar.size = Vector2(10.0 * PITCH + 72.0, 124.0)
	add_child(abar)
	for i in TOP_N:
		var c := _cell(Vector2(i * PITCH, 0))
		c.kind = "cat"
		c.slot_index = i
		top_cells.append(c)
	var cats := [
		["lasers", "Lazerler: cephane secenekleri", _on_cat.bind("lasers", "Lazerler")],
		["rockets", "Roketler", _on_cat.bind("rockets", "Roketler")],
		["special_items", "Ozel esyalar", _on_cat.bind("special_items", "Ozel esyalar")],
		["drone_formations", "Droid dizilimleri: sec / alt cubuga surukle", _on_cat.bind("drone_formations", "Droid dizilimleri")],
		["buy_now", "Market  [B]", game.toggle_base],
	]
	for i in cats.size():
		var d: Array = cats[i]
		var b := _ibtn(d[0], "items", d[1], d[2], CELL)
		b.position = Vector2(i * PITCH, 42)
		abar.add_child(b)
		cat_btns[d[0]] = b
	cat_btns.erase("buy_now")
	for i in QUICK_N:
		var q := _cell(Vector2(i * PITCH, 84))
		q.kind = "quick"
		q.slot_index = i
		q.pressed.connect(_quick_use.bind(i))
		q.dropped.connect(_quick_drop.bind(i))
		q.cleared.connect(_quick_clear.bind(i))
		quick_cells.append(q)
	for i in QUICK_N:
		quick.append({})
	var up := DOIconBtn.new()
	up.glyph = "up"
	up.size = Vector2(30, 30)
	up.position = Vector2(10.0 * PITCH + 2.0, 89)
	up.tooltip_text = "Cubugu goster"
	up.pressed.connect(_set_rows.bind(true))
	abar.add_child(up)
	var dn := DOIconBtn.new()
	dn.glyph = "down"
	dn.size = Vector2(30, 30)
	dn.position = Vector2(10.0 * PITCH + 36.0, 89)
	dn.tooltip_text = "Cubugu gizle"
	dn.pressed.connect(_set_rows.bind(false))
	abar.add_child(dn)
	_rebuild_top()


func quick_key(i: int) -> void:
	_quick_use(i)


# Market ile ayni ikon: once market (assets/ui) ikonu, yoksa eski HUD ikonu
func _market_icon(market_path: String, hud_name: String) -> Texture2D:
	var t: Texture2D = game._tex(market_path)
	print("[NOVAGATE-IKON] ", market_path, " -> ", t != null)
	if t == null:
		t = _icon_tex(hud_name, "")
	return t


func _icon_tex(atlas_name: String, fallback: String) -> Texture2D:
	var t: Texture2D = game._tex(HUD + "items/%s.png" % atlas_name)
	if t == null and fallback != "":
		t = game._tex(fallback)
	return t


func _flat_btn(text: String, pos: Vector2, size_: Vector2) -> Button:
	var tb := Button.new()
	tb.text = text
	tb.flat = true
	tb.position = pos
	tb.size = size_
	tb.add_theme_font_override("font", f_bold)
	tb.add_theme_font_size_override("font_size", 10)
	return tb


func _build_chat() -> void:
	chat_win = _win("Sohbet", Vector2(320, 212))
	var b := chat_win.body
	var names := ["GENEL", "SIRKET", "GRUP", "SISTEM"]
	for i in names.size():
		var tb := _flat_btn(names[i], Vector2(8 + i * 62, 0), Vector2(60, 18))
		tb.pressed.connect(_set_chat_tab.bind(int(chat_tab_ids[i])))
		b.add_child(tb)
		chat_tab_btns.append(tb)
	chat_tab_btns[2].visible = false   # GRUP sekmesi yalnizca grupta iken acilir
	chat_out = RichTextLabel.new()
	chat_out.position = Vector2(8, 22)
	chat_out.size = Vector2(304, 96)
	chat_out.bbcode_enabled = true
	chat_out.scroll_following = true
	chat_out.add_theme_font_override("normal_font", f_reg)
	chat_out.add_theme_font_override("bold_font", f_bold)
	chat_out.add_theme_font_size_override("normal_font_size", 11)
	chat_out.add_theme_font_size_override("bold_font_size", 11)
	var sbx := StyleBoxFlat.new()
	sbx.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	sbx.set_content_margin_all(3)
	chat_out.add_theme_stylebox_override("normal", sbx)
	b.add_child(chat_out)
	chat_in = LineEdit.new()
	chat_in.position = Vector2(8, 122)
	chat_in.size = Vector2(304, 22)
	chat_in.placeholder_text = "Mesaj yaz, Enter (/yardim)"
	chat_in.max_length = 120
	chat_in.add_theme_font_size_override("font_size", 11)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0, 0, 0, 0.55)
	le.set_border_width_all(1)
	le.border_color = Color(0.667, 0.667, 0.667)
	le.content_margin_left = 5
	chat_in.add_theme_stylebox_override("normal", le)
	chat_in.add_theme_stylebox_override("focus", le)
	chat_in.text_submitted.connect(_chat_submit)
	b.add_child(chat_in)
	_set_chat_tab(0)
	_log_general("[color=#00ccff]Sistem:[/color] Hos geldin! Sohbet yerel moddadir (sunucu yok).")


func _set_chat_tab(i: int) -> void:
	chat_tab = i
	for k in chat_tab_btns.size():
		var tb: Button = chat_tab_btns[k]
		var col := C_TAB_ON if int(chat_tab_ids[k]) == i else C_TAB_OFF
		for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			tb.add_theme_color_override(n, col)
	_render_chat()


func _render_chat() -> void:
	chat_out.text = "\n".join(PackedStringArray(chat_lines[chat_tab]))


func _push(tab: int, line: String) -> void:
	var arr: Array = chat_lines[tab]
	arr.append(line)
	while arr.size() > 80:
		arr.remove_at(0)
	if tab == chat_tab and chat_out != null:
		_render_chat()


func _stamp() -> String:
	return Time.get_time_string_from_system().substr(0, 5)


func _log_general(line: String) -> void:
	_push(0, "[color=#6f8aa0]%s[/color] %s" % [_stamp(), line])


func _log_system(line: String) -> void:
	_push(1, "[color=#6f8aa0]%s[/color] %s" % [_stamp(), line.replace("[", "[lb]")])


func _log_company(line: String) -> void:
	_push(2, "[color=#6f8aa0]%s[/color] %s" % [_stamp(), line])


func _log_group(line: String) -> void:
	_push(3, "[color=#6f8aa0]%s[/color] %s" % [_stamp(), line])


func log_system(line: String) -> void:
	_log_system(line)


func _chat_submit(t: String) -> void:
	var msg := t.strip_edges()
	chat_in.text = ""
	chat_in.release_focus()
	if msg == "":
		return
	if msg == "/yardim":
		_log_general("[color=#00ccff]Sistem:[/color] Komutlar: /yardim, /arkadas <ad>, /sil <ad>")
		return
	if msg.begins_with("/arkadas "):
		add_friend(msg.substr(9))
		return
	if msg.begins_with("/sil "):
		remove_friend(msg.substr(5))
		return
	var ch := 0   # secili sekmeye gore kanal: GENEL=0, SIRKET=1, GRUP=2
	if chat_tab == 2:
		ch = 1
	elif chat_tab == 3:
		ch = 2
		if not (Net.online and Net.gm != null and Net.gm.in_group()):
			_log_group("[color=#00ccff]Sistem:[/color] Grupta degilsin.")
			return
	if Net.online:
		Net.send_chat(msg, ch)   # sunucu yayinlar (kendi satirimiz de geri gelir)
		return
	var nick: String = str(game.SV.get("callsign", "Gezgin"))
	if ch == 1:
		_log_company("[color=#00ccff][b]%s:[/b][/color] %s" % [nick.replace("[", "[lb]"), msg.replace("[", "[lb]")])
		return
	_log_general("[color=#00ccff][b]%s:[/b][/color] %s" % [nick.replace("[", "[lb]"), msg.replace("[", "[lb]")])


func _build_contacts() -> void:
	contacts_win = _win("Arkadaslar", Vector2(360, 420))
	var b := contacts_win.body
	friend_in = LineEdit.new()
	friend_in.position = Vector2(10, 2)
	friend_in.size = Vector2(248, 26)
	friend_in.placeholder_text = "Oyuncu adi"
	friend_in.max_length = 16
	friend_in.text_submitted.connect(_friend_submit)
	b.add_child(friend_in)
	var add := Button.new()
	add.text = "EKLE"
	add.position = Vector2(266, 0)
	add.size = Vector2(84, 30)
	add.add_theme_font_size_override("font_size", 12)
	_skin(add, "green")
	add.pressed.connect(_friend_add_pressed)
	b.add_child(add)
	friend_count = _lbl(b, Vector2(10, 36), 10, C_YELLOW, 340.0, true)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 56)
	sc.size = Vector2(340, 250)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	b.add_child(sc)
	friend_box = VBoxContainer.new()
	friend_box.custom_minimum_size = Vector2(330, 0)
	friend_box.add_theme_constant_override("separation", 3)
	sc.add_child(friend_box)
	var foot := _lbl(b, Vector2(10, 312), 9, C_CAPTION, 340.0)
	foot.text = "Sunucu baglantisi yok: liste bu cihaza kaydedilir."
	contacts_win.visible = false


func _friend_list() -> Array:
	if not game.SV.has("contacts"):
		game.SV["contacts"] = []
	return game.SV["contacts"]


func _friend_submit(t: String) -> void:
	add_friend(t)


func _friend_add_pressed() -> void:
	add_friend(friend_in.text)


func add_friend(raw: String) -> void:
	var nm := raw.strip_edges()
	friend_in.text = ""
	if nm == "":
		return
	var lst := _friend_list()
	if nm.to_lower() == str(game.SV.get("callsign", "")).to_lower():
		game.toast("Kendini arkadas olarak ekleyemezsin.")
		return
	for f in lst:
		if str(f).to_lower() == nm.to_lower():
			game.toast("%s zaten arkadas listende." % nm)
			return
	if lst.size() >= MAX_FRIENDS:
		game.toast("Arkadas listesi dolu (%d)." % MAX_FRIENDS)
		return
	lst.append(nm)
	game.toast("%s arkadas olarak eklendi." % nm)
	game.save_game()
	_refresh_friends(true)


func remove_friend(raw: String) -> void:
	var nm := raw.strip_edges().to_lower()
	var lst := _friend_list()
	for i in lst.size():
		if str(lst[i]).to_lower() == nm:
			game.toast("%s listeden silindi." % str(lst[i]))
			lst.remove_at(i)
			game.save_game()
			_refresh_friends(true)
			return
	game.toast("Listede boyle bir oyuncu yok.")


func _friend_msg(nm: String) -> void:
	chat_win.show()
	_set_chat_tab(0)
	chat_in.text = "@%s " % nm
	chat_in.grab_focus()
	chat_in.caret_column = chat_in.text.length()


func _refresh_friends(force := false) -> void:
	var lst := _friend_list()
	var sig := str(lst) + str(contact_status)
	if not force and sig == _friend_sig:
		return
	_friend_sig = sig
	for c in friend_box.get_children():
		c.queue_free()
	friend_count.text = "ARKADASLAR  %d / %d" % [lst.size(), MAX_FRIENDS]
	for f in lst:
		var nm := str(f)
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(330, 28)
		row.add_theme_constant_override("separation", 6)
		var st := str(contact_status.get(nm, "offline"))
		var ic := TextureRect.new()
		ic.texture = game._tex(HUD + "win/st_%s.png" % st)
		ic.custom_minimum_size = Vector2(18, 18)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(ic)
		var l := Label.new()
		l.text = nm
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", C_TEXT if st != "offline" else Color(0.6, 0.68, 0.75))
		row.add_child(l)
		var bm := Button.new()
		bm.text = "MESAJ"
		bm.add_theme_font_size_override("font_size", 9)
		bm.pressed.connect(_friend_msg.bind(nm))
		row.add_child(bm)
		var bd := Button.new()
		bd.text = "SIL"
		bd.add_theme_font_size_override("font_size", 9)
		bd.pressed.connect(remove_friend.bind(nm))
		row.add_child(bd)
		friend_box.add_child(row)


# ------------------------------------------------------------------ GRUP
func _build_group() -> void:
	group_win = _win("Grup", Vector2(320, 340))
	var b := group_win.body
	grp_head = _lbl(b, Vector2(10, 2), 10, C_YELLOW, 300.0, true)
	var note := _lbl(b, Vector2(10, 18), 9, C_CAPTION, 300.0)
	note.text = "NPC odulu ayni haritadaki grup uyeleri arasinda esit bolunur."
	grp_inv_box = Control.new()
	grp_inv_box.position = Vector2(10, 38)
	grp_inv_box.size = Vector2(300, 52)
	grp_inv_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grp_inv_box.visible = false
	b.add_child(grp_inv_box)
	grp_inv_lbl = _lbl(grp_inv_box, Vector2(0, 0), 11, C_YELLOW, 300.0, true)
	var yes := Button.new()
	yes.text = "KABUL"
	yes.position = Vector2(0, 22)
	yes.size = Vector2(144, 28)
	yes.add_theme_font_size_override("font_size", 12)
	_skin(yes, "green")
	yes.pressed.connect(_group_answer.bind(true))
	grp_inv_box.add_child(yes)
	var no := Button.new()
	no.text = "REDDET"
	no.position = Vector2(156, 22)
	no.size = Vector2(144, 28)
	no.add_theme_font_size_override("font_size", 12)
	no.pressed.connect(_group_answer.bind(false))
	grp_inv_box.add_child(no)
	grp_sel_lbl = _lbl(b, Vector2(10, 94), 11, C_TEXT, 300.0, true)
	grp_sel_btn = Button.new()
	grp_sel_btn.text = "GRUBA DAVET ET"
	grp_sel_btn.position = Vector2(10, 114)
	grp_sel_btn.size = Vector2(300, 28)
	grp_sel_btn.add_theme_font_size_override("font_size", 12)
	_skin(grp_sel_btn, "green")
	grp_sel_btn.pressed.connect(_group_invite_sel)
	b.add_child(grp_sel_btn)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 150)
	sc.size = Vector2(300, 98)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	b.add_child(sc)
	grp_box = VBoxContainer.new()
	grp_box.custom_minimum_size = Vector2(290, 0)
	grp_box.add_theme_constant_override("separation", 3)
	sc.add_child(grp_box)
	grp_leave_btn = Button.new()
	grp_leave_btn.text = "GRUPTAN AYRIL"
	grp_leave_btn.position = Vector2(10, 254)
	grp_leave_btn.size = Vector2(300, 26)
	grp_leave_btn.add_theme_font_size_override("font_size", 11)
	grp_leave_btn.pressed.connect(_group_leave)
	b.add_child(grp_leave_btn)
	group_win.visible = false
	_refresh_group(true)


func toggle_group() -> void:
	group_win.visible = not group_win.visible
	if group_win.visible:
		_refresh_group(true)


# Ayni sirketten bir oyuncuya tiklandi: grup penceresinde gorunur, gruba davet edilebilir (hedef OLMAZ, ates edilemez).
func select_friend(peer: int) -> void:
	grp_sel = peer
	group_win.show()
	_refresh_group(true)


func on_group_invite(from_peer: int, from_name: String) -> void:
	grp_inv_from = from_peer
	grp_inv_name = from_name
	group_win.show()
	game.toast("%s seni gruba davet ediyor." % from_name)
	_refresh_group(true)


func group_changed() -> void:
	_refresh_group(true)


func _group_answer(accept: bool) -> void:
	grp_inv_from = 0
	Net.send_group_answer(accept)
	_refresh_group(true)


func _group_invite_sel() -> void:
	if grp_sel != 0:
		Net.send_group_invite(grp_sel)


func _group_leave() -> void:
	Net.send_group_leave()


func _group_kick(peer: int) -> void:
	Net.send_group_kick(peer)


func _refresh_group(force := false) -> void:
	if group_win == null:
		return
	var gm = Net.gm if (Net.online and Net.gm != null) else null
	var in_g: bool = gm != null and gm.in_group()
	var me: int = int(Net.my_id)
	var i_lead: bool = in_g and int(gm.group_leader) == me
	# secili oyuncu hala haritada ve ayni sirketten mi?
	var sel_name := ""
	var sel_ok := false
	if gm != null and grp_sel != 0:
		var ent = gm.players.get(grp_sel)
		if ent != null and is_instance_valid(ent.node) and bool(ent.get("friendly", false)):
			sel_name = str(ent.name)
			sel_ok = true
		else:
			grp_sel = 0
	var sig := "%s|%s|%s|%s|%s|%s" % [in_g, i_lead, sel_ok, sel_name, grp_inv_from, str(gm.group_members) if gm != null else ""]
	# uyelerin can yuzdeleri de imzaya girer (5'e yuvarlanmis)
	if in_g:
		for m in gm.group_members:
			var pe = gm.players.get(int(m[0]))
			if pe != null:
				sig += "|%d" % int(roundf(float(pe.hp) / maxf(float(pe.mx), 1.0) * 20.0))
	# GRUP sohbet sekmesi: yalnizca grupta iken gorunur
	chat_tab_btns[2].visible = in_g
	if not in_g and chat_tab == 3:
		_set_chat_tab(0)
	if not force and sig == _grp_sig:
		return
	_grp_sig = sig
	if in_g:
		grp_head.text = "GRUP  %d / 5" % gm.group_members.size()
	else:
		grp_head.text = "GRUP  -  grupta degilsin"
	grp_inv_box.visible = grp_inv_from != 0
	if grp_inv_from != 0:
		grp_inv_lbl.text = "%s seni gruba davet ediyor" % grp_inv_name
	grp_sel_lbl.text = ("SECILI OYUNCU:  %s" % sel_name) if sel_ok else "Gruba almak icin ayni sirketten bir oyuncuya tikla."
	var already: bool = sel_ok and in_g and gm.is_group_peer(grp_sel)
	grp_sel_btn.visible = sel_ok and not already
	grp_sel_btn.disabled = in_g and not i_lead
	grp_sel_btn.text = "GRUBA DAVET ET" if not (in_g and not i_lead) else "YALNIZCA LIDER DAVET EDEBILIR"
	grp_leave_btn.visible = in_g
	for c in grp_box.get_children():
		c.queue_free()
	if not in_g:
		return
	for m in gm.group_members:
		var pe2 := int(m[0])
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(290, 26)
		row.add_theme_constant_override("separation", 6)
		var l := Label.new()
		var txt := "%s%s" % ["[LIDER] " if pe2 == int(gm.group_leader) else "", str(m[1])]
		if pe2 == me:
			txt += "  (sen)"
		l.text = txt
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", C_TEXT)
		row.add_child(l)
		var info := Label.new()
		var ent2 = gm.players.get(pe2)
		if pe2 == me:
			info.text = ""
		elif ent2 != null:
			info.text = "%d%%" % int(roundf(float(ent2.hp) / maxf(float(ent2.mx), 1.0) * 100.0))
		else:
			info.text = str(m[2])   # baska haritada: harita adi
		info.add_theme_font_size_override("font_size", 10)
		info.add_theme_color_override("font_color", C_CAPTION)
		row.add_child(info)
		if i_lead and pe2 != me:
			var kb := Button.new()
			kb.text = "AT"
			kb.add_theme_font_size_override("font_size", 9)
			kb.pressed.connect(_group_kick.bind(pe2))
			row.add_child(kb)
		grp_box.add_child(row)


func _build_quests() -> void:
	quests_win = _win("Gorevler", Vector2(440, 400))
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 2)
	sc.size = Vector2(420, 336)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quests_win.body.add_child(sc)
	quest_box = VBoxContainer.new()
	quest_box.custom_minimum_size = Vector2(408, 0)
	quest_box.add_theme_constant_override("separation", 6)
	sc.add_child(quest_box)
	quests_win.visible = false


func _quest_state(q: Dictionary) -> Dictionary:
	var st: Dictionary = game.SV.get("quests", {}).get(str(q.id), {})
	return {"p": int(st.get("progress", 0)), "claimed": bool(st.get("claimed", false))}


func _quest_desc(q: Dictionary) -> String:
	var nd: Dictionary = DOData.NPCS.get(str(q.npc), {})
	return "%s yok et" % str(nd.get("name", q.npc))


func _refresh_quests(force := false) -> void:
	var ql: Array = game.quest_list()
	var sig := ""
	for q in ql:
		var s := _quest_state(q)
		sig += "%s:%d:%s;" % [q.id, s.p, str(s.claimed)]
	var shown := false
	for q in ql:
		var s := _quest_state(q)
		if not s.claimed:
			q_title.text = "%s  -  %s" % [q.title, _quest_desc(q)]
			q_bar.set_val(float(s.p) / maxf(float(q.target), 1.0), "%d / %d" % [s.p, int(q.target)])
			shown = true
			break
	if not shown:
		q_title.text = "Tum gorevler tamamlandi"
		q_bar.set_val(1.0, "")
	if not quests_win.visible and not force:
		return
	if sig == _quest_sig and not force:
		return
	_quest_sig = sig
	for c in quest_box.get_children():
		c.queue_free()
	for q in ql:
		var s := _quest_state(q)
		var tgt := int(q.target)
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.35)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.4, 1.0, 0.5, 0.8) if (s.p >= tgt and not s.claimed) else C_LINE
		sb.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		row.add_child(v)
		var t := Label.new()
		t.text = str(q.title)
		t.add_theme_font_override("font", f_bold)
		t.add_theme_font_size_override("font_size", 12)
		t.add_theme_color_override("font_color", C_YELLOW)
		v.add_child(t)
		var d := Label.new()
		d.text = "%s  (%d / %d)" % [_quest_desc(q), s.p, tgt]
		d.add_theme_font_size_override("font_size", 10)
		v.add_child(d)
		var pb := ProgressBar.new()
		pb.max_value = tgt
		pb.value = s.p
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 8)
		v.add_child(pb)
		var h := HBoxContainer.new()
		v.add_child(h)
		var r := Label.new()
		r.text = "Odul: %s EP  %s kredi  %s uridium" % [game._n(q.xp), game._n(q.cr), game._n(q.uri)]
		r.add_theme_font_size_override("font_size", 9)
		r.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(r)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 28)
		btn.add_theme_font_size_override("font_size", 10)
		if s.claimed:
			btn.text = "TAMAMLANDI"
			btn.disabled = true
		else:
			btn.text = "ODULU AL"
			btn.disabled = s.p < tgt
			_skin(btn, "green")
			btn.pressed.connect(_claim.bind(str(q.id)))
		h.add_child(btn)
		quest_box.add_child(row)


func _claim(id: String) -> void:
	game.claim_quest(id)
	_refresh_quests(true)


func _build_labels() -> void:
	lbl_toast = _lbl(self, Vector2.ZERO, 12, Color(1, 1, 1))
	lbl_toast.size = Vector2(600, 150)
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_prompt = _lbl(self, Vector2.ZERO, 16, Color(1, 1, 1), 0.0, true)
	lbl_prompt.size = Vector2(600, 30)
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_help = _lbl(self, Vector2.ZERO, 10, Color(1, 1, 1))
	lbl_help.text = "Sol tik: git (basili tut: takip)  |  Dusmana tik: hedef, tekrar tik / Ctrl / Bosluk: ates  |  Sag tik / Esc: dur  |  Tab: sonraki hedef  |  1-6: cephane  |  R: roket  |  J: kapi  |  B: panel  |  M: harita  |  Q: gorev  |  F: arkadas  |  Enter: sohbet  |  C: konfig  |  H: bu yazi"
	lbl_help.modulate = Color(1, 1, 1, 0.6)
	lbl_help.size = Vector2(1200, 18)

# ------------------------------------------------------------------ yerlesim

func _place(w: Control, p: Vector2) -> void:
	if w is DOWin and (w as DOWin).moved:
		return
	w.position = p


func _layout() -> void:
	var vs := get_viewport_rect().size
	var msz: Vector2 = minimap.panel_size()
	minimap.size = msz
	minimap_win.resize_to(Vector2(msz.x + 20.0, DOWin.HEAD + msz.y + 4.0 + DOWin.BOT))
	top_left.position = Vector2(10, 12)
	top_right.position = Vector2(vs.x - top_right.size.x - 10.0, 12)
	var ty := 58.0
	_place(user_win, Vector2(10, ty))
	_place(tracker_win, Vector2(10, ty + user_win.size.y + 6))
	_place(minimap_win, Vector2(vs.x - minimap_win.size.x - 8.0, ty))
	abar.position = Vector2(minf(vs.x * 0.392, vs.x - abar.size.x - 8.0), vs.y - abar.size.y - 14.0)
	_place(chat_win, Vector2(10, vs.y - chat_win.size.y - 22.0))
	_place(contacts_win, Vector2((vs.x - 360.0) * 0.5, (vs.y - 420.0) * 0.5))
	_place(quests_win, Vector2((vs.x - 440.0) * 0.5, (vs.y - 400.0) * 0.5))
	_place(group_win, Vector2((vs.x - 320.0) * 0.5, maxf(8.0, (vs.y - 340.0) * 0.5)))
	lbl_toast.position = Vector2(vs.x * 0.5 - 300.0, 140.0)
	lbl_prompt.position = Vector2(abar.position.x + abar.size.x * 0.5 - 300.0, abar.position.y - 30.0)
	lbl_help.position = Vector2(10, vs.y - 18.0)
	if mobile != null:
		mobile.apply_layout()   # telefonda: joystick/butonlari ve PC pencerelerini mobil duzene sok


func mobile_ui_on() -> bool:
	return mobile != null and mobile.mobile_on()


func layout_right() -> void:
	_layout()

# ------------------------------------------------------------------ pencere acma/kapama

func toggle_quests() -> void:
	quests_win.visible = not quests_win.visible
	if quests_win.visible:
		_refresh_quests(true)


func toggle_contacts() -> void:
	contacts_win.visible = not contacts_win.visible
	if contacts_win.visible:
		_refresh_friends(true)


func toggle_info() -> void:
	user_win.visible = not user_win.visible


func toggle_tracker() -> void:
	tracker_win.visible = not tracker_win.visible


func toggle_minimap() -> void:
	minimap_win.visible = not minimap_win.visible


func toggle_chat() -> void:
	chat_win.visible = not chat_win.visible


func focus_chat() -> void:
	chat_win.show()
	_set_chat_tab(0)
	chat_in.grab_focus()


func close_popups() -> bool:
	var closed := false
	for w in [contacts_win, quests_win, group_win]:
		if w.visible:
			w.hide()
			closed = true
	return closed


func _input(ev: InputEvent) -> void:
	if chat_in == null or friend_in == null:
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed:
		for le in [chat_in, friend_in]:
			if le.has_focus() and not le.get_global_rect().has_point(mb.position):
				le.release_focus()
	var k := ev as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F10 and mobile != null:
		mobile.toggle_forced()   # PC'de mobil arayuzu denemek icin
		get_viewport().set_input_as_handled()
		return
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		for le in [chat_in, friend_in]:
			if le.has_focus():
				le.release_focus()
				get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ canli guncelleme

func _process(dt: float) -> void:
	if not visible or game == null or not game.running:
		return
	for m in menu_btns:
		var w = m[1]
		if w != null:
			m[0].set_sel(w.visible)
	_tick += dt
	if _tick >= 0.4:
		_tick = 0.0
		_refresh_quests(false)
		if contacts_win.visible:
			_refresh_friends(false)
		_refresh_group(false)


func refresh(def: Dictionary, mhp: float, po: Vector3) -> void:
	var SV: Dictionary = game.SV
	var fac := int(SV.faction)
	if fac != _logo_fac:
		_logo_fac = fac
		u_logo.texture = game._tex("res://assets/ui/logo_" + ["", "mmo", "eic", "vru"][fac] + ".png")
		user_win.title = "%s  -  %s" % [str(SV.get("callsign", "Gezgin")), str(DOData.FACTIONS[fac].name)]
		user_win.queue_redraw()
	var xp := float(SV.xp)
	var lv: int = DOData.level_of(xp)
	u_name.text = str(def.name)
	u_lv.text = "Seviye %d%s" % [lv, "     [ATES ACIK]" if game.fire else ""]
	u_sh.set_val(game.P.sh / maxf(game.max_sh(), 1.0), "%s / %s" % [game._n(game.P.sh), game._n(game.max_sh())])
	u_hp.set_val(game.P.hp / mhp, "%s / %s" % [game._n(game.P.hp), game._n(mhp)])
	u_hp.set_rep(game.repairing)
	var nxt := 10000.0 * pow(2.0, float(lv - 1))
	u_ep.text = game._n(xp) if lv >= 30 else "%s / %s" % [game._n(xp), game._n(nxt)]
	u_hon.text = game._n(SV.hon)
	u_uri.text = game._n(SV.uri)
	u_cr.text = game._n(SV.cr)
	u_cfg.text = game.loadout_text()
	if not _quick_loaded:
		_load_quick()
	var sig := cur_cat + "|" + ",".join(PackedStringArray(SV.get("forms", [])))
	if sig != _cat_sig:
		_cat_sig = sig
		_rebuild_top()
	for c in top_cells:
		var st: Array = _item_state(c.payload) if not c.payload.is_empty() else ["", false, false]
		c.set_state(st[0], st[1], st[2])
		c.set_cd(_item_cd(c.payload) if not c.payload.is_empty() else 0.0)
	for i in quick_cells.size():
		var qc: DOCell = quick_cells[i]
		var qs: Array = _item_state(quick[i]) if not quick[i].is_empty() else ["", false, false]
		qc.set_state(qs[0], qs[1], qs[2])
		qc.set_cd(_item_cd(quick[i]) if not quick[i].is_empty() else 0.0)
