extends Panel
# ============================================================================
#  OYUN MERKEZİ  -  yeniden tasarlanmış kontrol paneli
#  main.gd:  var p = preload("res://control_panel.gd").new(); p.game = self; p.build()
#
#  Tasarım prensipleri:
#   * Tek bir Theme (tema) + theme_type_variation: stiller tek yerde, kod tekrarı yok
#   * Tamamen Container tabanlı yerleşim: sabit piksel konumu yok, taşma yok
#   * Başlıklarda Orbitron, gövde metninde okunaklı font (Türkçe karakter güvenli)
#   * Sol menü gruplu (Oyun / Çevrimiçi / Sistem), üstte kaynak çipleri, altta durum çubuğu
# ============================================================================
const DOData = preload("res://data.gd")
const RankSys = preload("res://rank_system.gd")
const SCI_FONT = preload("res://fonts/Orbitron-Regular.ttf")
const DARK_GLASS_BG := Color(0.02, 0.05, 0.1, 0.95)
const DARK_GLASS_EDGE := Color(0.25, 0.5, 0.8, 0.9)
# İstersen res://fonts/ içine Rajdhani veya Exo 2 koy: otomatik gövde fontu olarak kullanılır.
const BODY_FONT_CANDIDATES := ["res://fonts/Rajdhani-Medium.ttf", "res://fonts/Exo2-Medium.ttf", "res://fonts/Rajdhani-Regular.ttf"]

# [id, başlık, ikon, grup, çevrimiçi-kilitli]
const TABS := [
	["profile", "Bilgi", "user"],
	["stats", "İstatistikler", "group"],
	["equip", "Teçhizat", "equipment"],
	["skills", "Yetenek Ağacı", "equipment"],
	["shop", "Mağaza", "shop"],
	["auction", "Açık Artırma", "shop"],
	["missions", "Görevler", "quests"],
	["clan", "Klan", "group"],
	["galaxy", "Uzay Haritası", "spacemap"],
	["settings", "Ayarlar", "settings"],
	["help", "Yardım", "help"],
]
const SHOP_CATS := [
	["ships", "Gemiler"], ["lasers", "Lazerler"], ["gens", "Jeneratörler"], ["drones", "Droidler"],
	["forms", "Formasyonlar"], ["ammo", "Cephane"], ["rockets", "Roketler"], ["service", "Hizmetler"],
]

# ---- Renk paleti
const C_BG := Color(0.015, 0.035, 0.07, 0.98)
const C_PANEL := Color(0.035, 0.07, 0.12, 0.94)
const C_EDGE := Color(0.16, 0.30, 0.46, 0.85)
const NEON_BLUE := Color(0.25, 0.5, 0.8, 0.9)
const NEON_BLUE_BRIGHT := Color(0.4, 0.8, 1.0, 1.0)
const NEON_ORANGE := Color(1.0, 0.78, 0.3, 1.0)
const GOLD := Color(1.0, 0.82, 0.35)
const GREEN := Color(0.45, 1.0, 0.55)
const RED := Color(1.0, 0.45, 0.4)
const ICE_WHITE := Color(0.88, 0.96, 1.0)
const TEXT2 := Color(0.74, 0.83, 0.92)
const DIM := Color(0.56, 0.66, 0.78)
const MAX_HP := 550000.0
const MAX_SPD := 380.0
const MAX_LAS := 15.0
const MAX_GEN := 20.0

const HELP_KEYS := [
	["Sol tık / dokun (boş yer)", "Gemi oraya uçar."],
	["Sol tık / dokun (düşman)", "Hedef seç. Seçili hedefe tekrar tık / çift tık / Ctrl / Boşluk = ateş."],
	["Sağ tık / Esc", "Dur, ateşi kes, hedefi bırak."],
	["Tab", "Sıradaki en yakın hedef."],
	["Minimap'e tıkla", "Gemi o noktaya uçar."],
	["1..5 veya slot tık", "Cephane (x1 x2 x3 x4 SAB)."],
	["R", "Hedefe roket fırlat (HUD roket slotu da çalışır)."],
	["C", "Konfigürasyon 1 / 2 değiştir (5 sn bekleme)."],
	["J", "Kapının yanında haritadan haritaya atla."],
	["B", "Kontrol merkezi."],
	["M", "Galaksi haritası."],
	["H", "Kontrol yazısını aç/kapat."],
	["Tekerlek", "Yakınlaştır / uzaklaştır."],
]
const HELP_NOTES := [
	["HANGAR / TEÇHİZAT", "Mevcut gemileri, envanteri, lazerleri, jeneratörleri, droidleri, iki konfigürasyonu ve formasyonları yönet. Mağaza satın alımları yerel kayda yazılır. Görevler ve yetenek puanları da bu kayıt dosyasında saklanır."],
	["ÇEVRİMDIŞI SINIRI", "Bu sürümde oyun sunucusu, hesap sistemi veya ödeme altyapısı yok. Klan, açık artırma, posta/etkinlik akışı ve gerçek para paketleri bu nedenle devre dışıdır; arayüz bunları çalışıyormuş gibi göstermez."],
]

var game = null
var cur_tab := "equip"
var shop_cat := "ships"
var equip_subtab := "hangarlar"
var equip_filter := "all"
var equip_subtab_btns := {}
var sel_ship := ""
var shop_qty := 1
var selected_drone_slot := ""  # Format: "drone_id:slot_index" or ""
var pages := {}
var tab_btns := {}
var cat_btns := {}
var qty_btns := {}
var body_font: Font
var head_font: Font
var spin_pause := 0.0

var content_root: Control
var equip_content: Control
var lbl_foot: Label
var lbl_section: Label
var lbl_cr: Label
var lbl_uri: Label
var lbl_lvl: Label
var chip_test: Control

var hang_list: VBoxContainer
var hang_cfg: HFlowContainer
var hang_equip: VBoxContainer
var pv_pivot: Node3D
var pv_model: Node3D = null
var pv_id := ""
var pv_title: Label
var pv_sub: Label
var pv_stats: VBoxContainer
var pv_btn: Button

var shop_body: VBoxContainer
var shop_note: Label
var equip_body: VBoxContainer
var mission_body: VBoxContainer
var skill_body: VBoxContainer
var skill_detail: VBoxContainer
var skill_canvas: Control
var skill_bar: HBoxContainer
var auc_sub := "lots"
var auc_filter := 0
var auc_sel := 0
var auc_sel_item := ""
var auc_bid_txt := ""
var auc_sub_btns := {}
var auc_list: VBoxContainer
var auc_head: HBoxContainer
var auc_side: VBoxContainer
var auc_end_lbl: Label
var auc_bal: Label
var auc_bid_edit: LineEdit
var _sk_sel := ""
var profile_body: VBoxContainer
var stats_body: VBoxContainer
var galaxy_body: VBoxContainer
var set_body: VBoxContainer


# ============================================================================
#  TEMA / STİL FABRİKASI
# ============================================================================
func _sb(bg: Color, bd := Color(0, 0, 0, 0), bw := 1, r := 4, m := Vector4(10, 6, 10, 6), shadow := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bd
	s.set_border_width_all(bw)
	s.set_corner_radius_all(r)
	s.content_margin_left = m.x
	s.content_margin_top = m.y
	s.content_margin_right = m.z
	s.content_margin_bottom = m.w
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 18
	return s


func _make_fonts() -> void:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Segoe UI", "Roboto", "Noto Sans", "Arial", "DejaVu Sans"])
	body_font = sys
	for path in BODY_FONT_CANDIDATES:
		if ResourceLoader.exists(str(path)):
			body_font = load(str(path))
			break
	var fv := FontVariation.new()
	fv.base_font = SCI_FONT
	fv.fallbacks = [body_font]
	head_font = fv


func _btn_defs() -> Dictionary:
	var clear := Color(0, 0, 0, 0)
	return {
		"Button": {"bg": Color(0.05, 0.10, 0.17, 0.95), "bd": Color(0.20, 0.40, 0.60, 0.85), "hbg": Color(0.08, 0.16, 0.26, 1.0), "hbd": NEON_BLUE_BRIGHT, "pbg": Color(0.12, 0.22, 0.34, 1.0), "pbd": NEON_ORANGE, "fc": ICE_WHITE, "pfc": GOLD},
		"ButtonSmall": {"bg": Color(0.05, 0.10, 0.17, 0.95), "bd": Color(0.20, 0.40, 0.60, 0.85), "hbg": Color(0.08, 0.16, 0.26, 1.0), "hbd": NEON_BLUE_BRIGHT, "pbg": Color(0.12, 0.22, 0.34, 1.0), "pbd": NEON_ORANGE, "fc": ICE_WHITE, "pfc": GOLD, "pad": Vector4(9, 4, 9, 4)},
		"ButtonPrimary": {"bg": Color(0.03, 0.13, 0.07, 0.95), "bd": Color(0.20, 0.62, 0.34, 0.9), "hbg": Color(0.05, 0.21, 0.10, 1.0), "hbd": GREEN, "pbg": Color(0.07, 0.28, 0.13, 1.0), "pbd": GREEN, "fc": ICE_WHITE, "pfc": ICE_WHITE},
		"ButtonDanger": {"bg": Color(0.16, 0.05, 0.05, 0.95), "bd": Color(0.72, 0.28, 0.28, 0.9), "hbg": Color(0.26, 0.08, 0.08, 1.0), "hbd": Color(1.0, 0.42, 0.42), "pbg": Color(0.32, 0.10, 0.10, 1.0), "pbd": Color(1.0, 0.5, 0.5), "fc": ICE_WHITE, "pfc": ICE_WHITE},
		"ButtonGold": {"bg": Color(0.16, 0.11, 0.03, 0.95), "bd": Color(1.0, 0.65, 0.15, 0.9), "hbg": Color(0.24, 0.17, 0.05, 1.0), "hbd": GOLD, "pbg": Color(0.30, 0.21, 0.06, 1.0), "pbd": GOLD, "fc": GOLD, "pfc": GOLD},
		"ButtonCurrent": {"bg": Color(0.04, 0.14, 0.08, 0.95), "bd": Color(0.3, 0.85, 0.5, 1.0), "hbg": Color(0.05, 0.2, 0.1, 1.0), "hbd": GREEN, "pbg": Color(0.05, 0.2, 0.1, 1.0), "pbd": GREEN, "fc": ICE_WHITE, "pfc": ICE_WHITE, "dis_same": true, "dfc": ICE_WHITE},
		"ButtonPvp": {"bg": Color(0.13, 0.05, 0.06, 0.95), "bd": Color(0.65, 0.25, 0.25, 0.9), "hbg": Color(0.22, 0.08, 0.08, 1.0), "hbd": Color(1.0, 0.42, 0.42), "pbg": Color(0.22, 0.08, 0.08, 1.0), "pbd": Color(1.0, 0.5, 0.5), "fc": Color(1.0, 0.8, 0.78), "pfc": ICE_WHITE},
		"NavButton": {"bg": clear, "bd": clear, "hbg": Color(0.07, 0.14, 0.23, 0.85), "hbd": NEON_BLUE, "pbg": Color(0.09, 0.19, 0.32, 0.95), "pbd": NEON_ORANGE, "fc": TEXT2, "hfc": ICE_WHITE, "pfc": NEON_ORANGE, "pad": Vector4(10, 6, 10, 6), "r": 3, "accent": true},
		"NavLocked": {"bg": clear, "bd": clear, "hbg": Color(0.07, 0.14, 0.23, 0.6), "hbd": Color(0.25, 0.4, 0.6, 0.6), "pbg": Color(0.09, 0.19, 0.32, 0.8), "pbd": Color(0.7, 0.55, 0.3, 1.0), "fc": Color(0.42, 0.49, 0.58), "hfc": Color(0.65, 0.72, 0.8), "pfc": Color(0.85, 0.7, 0.45), "pad": Vector4(10, 4, 10, 4), "r": 3, "accent": true},
		"SlotButton": {"bg": Color(0.03, 0.06, 0.10, 0.95), "bd": Color(0.18, 0.34, 0.52, 0.85), "hbg": Color(0.07, 0.13, 0.21, 1.0), "hbd": NEON_BLUE_BRIGHT, "pbg": Color(0.07, 0.13, 0.21, 1.0), "pbd": NEON_ORANGE, "fc": ICE_WHITE, "pfc": ICE_WHITE, "pad": Vector4(3, 3, 3, 3), "dbg": Color(0.02, 0.04, 0.07, 0.8), "dbd": Color(0.14, 0.24, 0.34, 0.55)},
		"SlotSelected": {"bg": Color(0.04, 0.14, 0.08, 0.95), "bd": Color(0.3, 0.85, 0.5, 1.0), "hbg": Color(0.06, 0.2, 0.11, 1.0), "hbd": GREEN, "pbg": Color(0.06, 0.2, 0.11, 1.0), "pbd": GREEN, "fc": ICE_WHITE, "pfc": ICE_WHITE, "pad": Vector4(3, 3, 3, 3), "bw": 2},
		"ShipCard": {"bg": Color(0.04, 0.08, 0.13, 0.95), "bd": Color(0.16, 0.30, 0.46, 0.8), "hbg": Color(0.07, 0.13, 0.21, 1.0), "hbd": NEON_BLUE_BRIGHT, "pbg": Color(0.07, 0.13, 0.21, 1.0), "pbd": NEON_ORANGE, "fc": ICE_WHITE, "pfc": ICE_WHITE, "pad": Vector4(8, 4, 8, 4)},
		"ShipCardSel": {"bg": Color(0.08, 0.15, 0.24, 1.0), "bd": NEON_ORANGE, "hbg": Color(0.09, 0.17, 0.27, 1.0), "hbd": GOLD, "pbg": Color(0.09, 0.17, 0.27, 1.0), "pbd": GOLD, "fc": ICE_WHITE, "pfc": ICE_WHITE, "pad": Vector4(8, 4, 8, 4)},
	}


func _apply_btn(t: Theme, type_name: String, base: String, d: Dictionary) -> void:
	if type_name != base:
		t.set_type_variation(type_name, base)
	var pad: Vector4 = d.get("pad", Vector4(14, 7, 14, 7))
	var r: int = int(d.get("r", 4))
	var bw: int = int(d.get("bw", 1))
	var accent: bool = bool(d.get("accent", false))
	var normal := _sb(d.bg, d.bd, bw, r, pad)
	var hover := _sb(d.hbg, d.hbd, bw, r, pad)
	var pressed := _sb(d.pbg, d.pbd, bw, r, pad)
	var hover_pressed := _sb(d.pbg, d.pbd, bw, r, pad)
	var disabled := _sb(d.get("dbg", Color(0.04, 0.05, 0.08, 0.75)), d.get("dbd", Color(0.18, 0.21, 0.27, 0.6)), bw, r, pad)
	if bool(d.get("dis_same", false)):
		disabled = normal.duplicate()
	if accent:
		for s in [normal, hover, pressed, hover_pressed]:
			s.border_width_left = 3
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, hover)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("hover_pressed", type_name, hover_pressed)
	t.set_stylebox("disabled", type_name, disabled)
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	var fc: Color = d.fc
	t.set_color("font_color", type_name, fc)
	t.set_color("font_hover_color", type_name, d.get("hfc", fc))
	t.set_color("font_pressed_color", type_name, d.get("pfc", fc))
	t.set_color("font_hover_pressed_color", type_name, d.get("pfc", fc))
	t.set_color("font_focus_color", type_name, fc)
	t.set_color("font_disabled_color", type_name, d.get("dfc", Color(0.42, 0.48, 0.56)))


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 14
	t.set_color("font_color", "Label", ICE_WHITE)
	t.set_constant("h_separation", "Button", 8)

	# Butonlar
	var defs := _btn_defs()
	for k in defs:
		_apply_btn(t, str(k), "Button", defs[k])
	_apply_btn(t, "OptionButton", "OptionButton", defs["Button"])

	# Paneller
	t.set_stylebox("panel", "Panel", _sb(C_PANEL, C_EDGE, 1, 4, Vector4(0, 0, 0, 0)))
	t.set_stylebox("panel", "PanelContainer", _sb(C_PANEL, C_EDGE, 1, 4, Vector4(10, 8, 10, 8)))
	var pv := {
		"PanelBar": _sb(C_PANEL, C_EDGE, 1, 5, Vector4(14, 6, 10, 6)),
		"PanelInset": _sb(Color(0.015, 0.03, 0.06, 0.85), Color(0.12, 0.22, 0.34, 0.8), 1, 5, Vector4(6, 6, 6, 6)),
		"PanelRow": _sb(C_PANEL, Color(0.14, 0.27, 0.42, 0.8), 1, 5, Vector4(12, 8, 12, 8)),
		"PanelCard": _sb(Color(0.04, 0.08, 0.14, 0.95), C_EDGE, 1, 6, Vector4(12, 10, 12, 10)),
		"PanelChip": _sb(Color(0.04, 0.09, 0.15, 1.0), C_EDGE, 1, 12, Vector4(12, 3, 12, 3)),
		"PanelNote": _sb(Color(0.14, 0.09, 0.02, 0.7), Color(1.0, 0.65, 0.15, 0.6), 1, 5, Vector4(10, 6, 10, 6)),
	}
	for k in pv:
		t.set_type_variation(str(k), "PanelContainer")
		t.set_stylebox("panel", str(k), pv[k])

	# Kaydırma çubukları (ince, modern)
	for sbt in ["VScrollBar", "HScrollBar"]:
		var m := Vector4(3, 0, 3, 0) if sbt == "VScrollBar" else Vector4(0, 3, 0, 3)
		t.set_stylebox("scroll", sbt, _sb(Color(0.02, 0.05, 0.09, 0.6), Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("scroll_focus", sbt, _sb(Color(0.02, 0.05, 0.09, 0.6), Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("grabber", sbt, _sb(Color(0.25, 0.45, 0.7, 0.8), Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("grabber_highlight", sbt, _sb(NEON_BLUE_BRIGHT, Color(0, 0, 0, 0), 0, 3, m))
		t.set_stylebox("grabber_pressed", sbt, _sb(NEON_ORANGE, Color(0, 0, 0, 0), 0, 3, m))

	# İlerleme çubuğu / slider
	t.set_stylebox("background", "ProgressBar", _sb(Color(0.02, 0.04, 0.07, 1.0), Color(0.12, 0.22, 0.34, 0.9), 1, 3, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", _sb(NEON_BLUE_BRIGHT, Color(0, 0, 0, 0), 0, 3, Vector4(0, 0, 0, 0)))
	t.set_stylebox("slider", "HSlider", _sb(Color(0.08, 0.15, 0.24, 1.0), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area", "HSlider", _sb(NEON_ORANGE, Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(GOLD, Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))

	# Metin kutusu
	t.set_stylebox("normal", "LineEdit", _sb(Color(0.02, 0.05, 0.09, 1.0), Color(0.2, 0.4, 0.6, 0.85), 1, 4, Vector4(10, 6, 10, 6)))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0.03, 0.07, 0.12, 1.0), NEON_ORANGE, 1, 4, Vector4(10, 6, 10, 6)))
	t.set_stylebox("read_only", "LineEdit", _sb(Color(0.02, 0.04, 0.07, 1.0), Color(0.15, 0.25, 0.35, 0.6), 1, 4, Vector4(10, 6, 10, 6)))
	t.set_color("font_color", "LineEdit", ICE_WHITE)
	t.set_color("caret_color", "LineEdit", NEON_ORANGE)

	# Açılır menü + tooltip
	t.set_stylebox("panel", "PopupMenu", _sb(Color(0.03, 0.06, 0.10, 0.98), C_EDGE, 1, 4, Vector4(6, 6, 6, 6)))
	t.set_stylebox("hover", "PopupMenu", _sb(Color(0.10, 0.20, 0.32, 1.0), Color(0, 0, 0, 0), 0, 3, Vector4(4, 2, 4, 2)))
	t.set_color("font_color", "PopupMenu", ICE_WHITE)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "TooltipPanel", _sb(Color(0.03, 0.06, 0.10, 0.98), NEON_BLUE, 1, 4, Vector4(8, 5, 8, 5)))
	t.set_color("font_color", "TooltipLabel", ICE_WHITE)

	# Onay anahtarları
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(k, "CheckButton", ICE_WHITE)
	return t


# ============================================================================
#  KÜÇÜK YARDIMCILAR
# ============================================================================
func _mk(text: String, fs := 14, col := ICE_WHITE, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if display or fs >= 16:
		l.add_theme_font_override("font", head_font)
	return l


func _wrap(text: String, fs := 13, col := TEXT2, display := false) -> Label:
	var l := _mk(text, fs, col, display)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(120, 0)
	return l


func _panel(variation := "PanelCard") -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme_type_variation = variation
	return pc


func _line() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.16, 0.30, 0.46, 0.55)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _flow(sep := 4) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


func _btn(text: String, kind: String, cb: Callable, min_size := Vector2(0, 32), enabled := true, fs := 13) -> Button:
	var b := Button.new()
	b.text = text
	if kind != "Button":
		b.theme_type_variation = kind
	b.custom_minimum_size = min_size
	b.disabled = not enabled
	b.add_theme_font_override("font", body_font if kind == "ButtonSmall" else head_font)
	b.add_theme_font_size_override("font_size", fs)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _bar(value: float, maxv: float, col: Color, h := 8.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = maxf(maxv, 0.001)
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(40, h)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("fill", _sb(col, Color(0, 0, 0, 0), 0, 3, Vector4(0, 0, 0, 0)))
	return pb


func _icon(tex: Texture2D, sz := 40) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(sz, sz)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _row_panel(parent: Node) -> HBoxContainer:
	var pc := _panel("PanelRow")
	parent.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	pc.add_child(h)
	return h


func _make_scroll_page(sep := 8) -> Array:
	var pg := Control.new()
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pg.add_child(sc)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", sep)
	sc.add_child(body)
	return [pg, body]


func _page_head(parent: Node, title: String, sub := "") -> void:
	parent.add_child(_mk(title, 22, NEON_ORANGE))
	if sub != "":
		parent.add_child(_wrap(sub, 13, DIM))
	parent.add_child(_line())


func _section(text: String) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_child(_mk(text, 10, Color(0.45, 0.58, 0.72)))
	return m


func _chip(caption: String, col: Color) -> Array:
	var pc := _panel("PanelChip")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var c := _mk(caption, 10, DIM)
	c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(c)
	var v := _mk("0", 14, col, true)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(v)
	return [pc, v]


func _kpi(parent: Node, caption: String, value: String, col := ICE_WHITE) -> void:
	var pc := _panel("PanelCard")
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.custom_minimum_size = Vector2(120, 0)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	v.add_child(_mk(caption, 10, DIM))
	var val := _mk(value, 16, col)
	val.clip_text = true
	v.add_child(val)


func _def(id: String) -> Dictionary:
	for s in DOData.SHIPS:
		if s.id == id:
			return s
	return DOData.SHIPS[0]


func _price_txt(s: Dictionary) -> String:
	if s.cr > 0:
		return "Liste fiyatı: %s Kredi" % game._n(s.cr)
	if s.uri > 0:
		return "Liste fiyatı: %s Uridium" % game._n(s.uri)
	return "Başlangıç gemisi"


func _ship_tex(id: String) -> Texture2D:
	# Market ve hangar: oyundaki guncel 3D modelden canli onizleme; olmazsa eski PNG ikon.
	var t: Texture2D = game.ship_preview_tex(id)
	if t != null:
		return t
	return game._tex("res://assets/items/%s.png" % DOData.ship_icon(id, int(game.SV.faction)))


func _form_tex(code: String) -> Texture2D:
	return game._tex("res://assets/items/form_%s.png" % code)


func _cost_txt(cr: int, uri: int) -> String:
	if bool(game.SV.free):
		return "ÜCRETSİZ (test)"
	if uri > 0:
		return "%s Uridium" % game._n(uri)
	if cr > 0:
		return "%s Kredi" % game._n(cr)
	return "Ücretsiz"


func _cost_col(cr: int, uri: int) -> Color:
	if game.can_pay(cr, uri):
		return GREEN if not (cr == 0 and uri == 0) else DIM
	return RED


func _compact_num(v: int) -> String:
	if v >= 1000000:
		return "%.1fM" % (float(v) / 1000000.0)
	if v >= 1000:
		return "%dK" % int(float(v) / 1000.0)
	return str(v)


func _compact_cost(cr: int, uri: int) -> String:
	if bool(game.SV.free):
		return "Ücretsiz (test)"
	if uri > 0:
		return "%s Uri" % _compact_num(uri)
	if cr > 0:
		return "%s Kr" % _compact_num(cr)
	return "Ücretsiz"


func _slot_btn(id: String, tex: Texture2D, tip: String, cb: Callable, sz := 54) -> Button:
	var b := Button.new()
	b.theme_type_variation = "SlotButton"
	b.custom_minimum_size = Vector2(sz, sz)
	b.tooltip_text = tip
	b.icon = tex
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if id == "":
		b.disabled = true
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


# ============================================================================
#  ANA İSKELET
# ============================================================================
func build() -> void:
	_make_fonts()
	theme = _make_theme()
	pivot_offset = Vector2(470, 290)
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -470.0
	offset_top = -290.0
	offset_right = 470.0
	offset_bottom = 290.0
	get_viewport().size_changed.connect(_responsive_layout)
	call_deferred("_responsive_layout")
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _sb(C_BG, NEON_BLUE, 1, 8, Vector4(0, 0, 0, 0), true))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)
	body.add_child(_build_nav())

	content_root = Control.new()
	content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.clip_contents = true
	body.add_child(content_root)
	root.add_child(_build_footer())

	pages["shop"] = _build_shop()
	pages["equip"] = _build_equip()
	pages["missions"] = _build_missions()
	pages["skills"] = _build_skills()
	pages["profile"] = _build_profile()
	pages["stats"] = _build_stats()
	pages["galaxy"] = _build_galaxy()
	pages["auction"] = _build_auction()
	pages["clan"] = _build_blocked_page("KLAN", "Klan bilgisi, üyeler, başvurular ve yetkiler sunucuya bağlıdır. Projede klan API'si veya çok oyunculu hesap altyapısı bulunmuyor; üyelik ve başvuru işlemleri kapalıdır.", "Klan sunucusu bağlı değil.")
	pages["settings"] = _build_settings()
	pages["help"] = _build_help()

	for k in pages:
		content_root.add_child(pages[k])
		pages[k].set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	visibility_changed.connect(_on_vis)
	_switch("equip")


func _build_header() -> Control:
	var pc := _panel("PanelBar")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)

	var bar := ColorRect.new()
	bar.color = NEON_ORANGE
	bar.custom_minimum_size = Vector2(4, 26)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)

	var title := _mk("OYUN MERKEZİ", 20, NEON_ORANGE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)
	lbl_section = _mk("", 14, DIM)
	lbl_section.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(lbl_section)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)

	var tp := _panel("PanelNote")
	var tl := _mk("TEST MODU", 11, NEON_ORANGE)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tp.add_child(tl)
	chip_test = tp
	h.add_child(tp)

	var c1 := _chip("KREDİ", GOLD)
	lbl_cr = c1[1]
	h.add_child(c1[0])
	var c2 := _chip("URİDYUM", Color(0.5, 0.85, 1.0))
	lbl_uri = c2[1]
	h.add_child(c2[0])
	var c3 := _chip("SEVİYE", GREEN)
	lbl_lvl = c3[1]
	h.add_child(c3[0])

	h.add_child(_btn("✕", "ButtonDanger", _close, Vector2(36, 30), true, 14))
	return pc


func _build_nav() -> Control:
	var pc := _panel("PanelInset")
	pc.custom_minimum_size = Vector2(176, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	scroll.add_child(vb)

	var grp := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.text = str(t[1])
		b.toggle_mode = true
		b.button_group = grp
		b.icon = game._tex("res://assets/ui/m_%s_normal.png" % str(t[2]))
		b.add_theme_constant_override("icon_max_width", 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_switch.bind(str(t[0])))
		vb.add_child(b)
		tab_btns[str(t[0])] = b
	return pc


func _build_footer() -> Control:
	var pc := _panel("PanelBar")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	lbl_foot = _mk("", 12, DIM)
	lbl_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_foot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_foot.clip_text = true
	h.add_child(lbl_foot)
	h.add_child(_btn("OYUNA DÖN", "ButtonPrimary", _close, Vector2(150, 30), true, 12))
	return pc


func _responsive_layout() -> void:
	if get_viewport() == null:
		return
	var screen := get_viewport_rect().size
	var fit_x := (screen.x - 24.0) / 940.0
	var fit_y := (screen.y - 24.0) / 580.0
	var factor := clampf(minf(1.0, minf(fit_x, fit_y)), 0.25, 1.0)
	scale = Vector2.ONE * factor


func _process(dt: float) -> void:
	if not visible or pv_pivot == null or cur_tab != "__yok__":
		return
	if spin_pause > 0.0:
		spin_pause -= dt
	else:
		pv_pivot.rotation.y += dt * 0.7


func _close() -> void:
	visible = false


func _open_galaxy() -> void:
	visible = false
	game.toggle_galaxy()


func _on_vis() -> void:
	if not visible:
		return
	if game == null or game.SV.is_empty():
		return
	sel_ship = str(game.SV.ship)
	_switch(cur_tab)


func _switch(tab: String) -> void:
	if tab == "pilot":
		tab = "profile"
	if tab == "hangar":
		tab = "equip"
		equip_subtab = "hangarlar"
	cur_tab = tab
	for k in pages:
		pages[k].visible = (k == tab)
	if tab_btns.has(tab):
		tab_btns[tab].button_pressed = true
	for t in TABS:
		if str(t[0]) == tab and lbl_section != null:
			lbl_section.text = "/  " + str(t[1]).to_upper()
	refresh()
	if tab == "auction" and Net.online and Net.gm != null and Net.gm.auc != null:
		Net.gm.auc.request_open()
	if pages.has(tab):
		var pg: Control = pages[tab]
		pg.modulate.a = 0.0
		create_tween().tween_property(pg, "modulate:a", 1.0, 0.14)


func refresh() -> void:
	if game == null or game.SV.is_empty():
		return
	var def: Dictionary = game.ship_def()
	var lvl: int = DOData.level_of(float(game.SV.xp))
	lbl_cr.text = str(game._n(game.SV.cr))
	lbl_uri.text = str(game._n(game.SV.uri))
	lbl_lvl.text = str(lvl)
	lbl_foot.text = "Gemi: %s     •     Harita: %s     •     Çağrı adı: %s" % [str(def.name), str(game.SV.map), str(game.SV.get("callsign", "Gezgin"))]
	match cur_tab:
		"shop":
			_refresh_shop()
		"equip":
			_refresh_equip()
		"missions":
			_refresh_missions()
		"skills":
			_refresh_skills()
		"auction":
			_refresh_auction()
		"profile":
			_refresh_profile()
		"stats":
			_refresh_stats()
		"galaxy":
			_refresh_galaxy()
		"settings":
			_refresh_settings()


# ============================================================================
#  HANGAR  (sol: gemi listesi | orta: 3B önizleme | sağ: istatistik + teçhizat)
# ============================================================================
func _glow_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.16, 0.40, 0.75, 0.42), Color(0.08, 0.2, 0.4, 0.14), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func _on_cfg_btn(i: int) -> void:
	game.switch_cfg(i)
	refresh()


# ============================================================================
#  MAĞAZA
# ============================================================================
func _build_shop() -> Control:
	var pg := VBoxContainer.new()
	pg.add_theme_constant_override("separation", 8)

	var top := _panel("PanelInset")
	pg.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	top.add_child(tv)

	var cats := _flow(4)
	tv.add_child(cats)
	var grp := ButtonGroup.new()
	for c in SHOP_CATS:
		var b := _btn(str(c[1]), "ButtonSmall", _set_cat.bind(str(c[0])), Vector2(0, 30), true, 13)
		b.toggle_mode = true
		b.button_group = grp
		cats.add_child(b)
		cat_btns[str(c[0])] = b

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	tv.add_child(info)
	shop_note = _mk("", 12, GREEN)
	shop_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shop_note.clip_text = true
	info.add_child(shop_note)
	var ql := _mk("Adet:", 12, DIM)
	ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(ql)
	var qgrp := ButtonGroup.new()
	for q in [1, 5, 10, 50]:
		var qb := _btn("x%d" % int(q), "ButtonSmall", _set_qty.bind(int(q)), Vector2(44, 26), true, 12)
		qb.toggle_mode = true
		qb.button_group = qgrp
		info.add_child(qb)
		qty_btns[int(q)] = qb

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pg.add_child(sc)
	shop_body = VBoxContainer.new()
	shop_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_body.add_theme_constant_override("separation", 6)
	sc.add_child(shop_body)

	cat_btns["ships"].button_pressed = true
	qty_btns[1].button_pressed = true
	return pg


func _set_cat(c: String) -> void:
	shop_cat = c
	_refresh_shop()


func _set_qty(n: int) -> void:
	shop_qty = n
	_refresh_shop()


func _shop_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_body.add_child(grid)
	return grid


func _shop_card(parent: Control, icon: Texture2D, title: String, lines: String, cr: int, uri: int, badge := "") -> HBoxContainer:
	var pc := _panel("PanelCard")
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.custom_minimum_size = Vector2(200, 0)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(_icon(icon, 44))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 1)
	top.add_child(tv)
	tv.add_child(_wrap(title, 14, NEON_ORANGE, true))
	if badge != "":
		tv.add_child(_mk(badge, 11, GREEN))
	v.add_child(_wrap(lines, 12, TEXT2))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	if cr > 0 or uri > 0:
		v.add_child(_mk(_cost_txt(cr, uri), 13, _cost_col(cr, uri)))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 4)
	v.add_child(btns)
	return btns


func _buy_btn(h: Node, text: String, cb: Callable, enabled: bool, w := 120, kind := "ButtonPrimary") -> Button:
	var b := _btn(text, kind, cb, Vector2(w, 32), enabled, 12)
	h.add_child(b)
	return b


func _item_card(grid: Control, id: String, desc: String) -> void:
	var d: Dictionary = game.item_def(id)
	var have: int = game.inv_count(id)
	var badge := ""
	if have > 0:
		badge = "Envanter: %d" % have
	var unit: Array = game.item_cost(id, 1)    # droid: sıradaki droidin fiyatı
	var btns := _shop_card(grid, game.item_icon(id), str(d.name), desc, maxi(0, int(unit[0])), maxi(0, int(unit[1])), badge)
	var q := shop_qty
	var tot: Array = game.item_cost(id, q)
	var ok: bool = int(tot[0]) >= 0 and game.can_pay(int(tot[0]), int(tot[1]))
	_buy_btn(btns, "AL x%d" % q, _shop_item.bind(id, q), ok, 100)
	var sb := _buy_btn(btns, "SAT", _sell_item.bind(id), have > 0, 60, "Button")
	sb.tooltip_text = "1 adet sat (satış iadesi: %40)"


func _refresh_shop() -> void:
	if cat_btns.has(shop_cat):
		cat_btns[shop_cat].button_pressed = true
	if qty_btns.has(shop_qty):
		qty_btns[shop_qty].button_pressed = true
	_clear(shop_body)
	shop_note.text = "Satış iadesi: %40   •   Bakiyen üst çubukta"
	match shop_cat:
		"ships":
			var grid := _shop_grid()
			for s in DOData.SHIPS:
				if str(s.id) in DOData.MARKET_HIDDEN:
					continue   # bigboy / aegis / citadel marketten kaldirildi
				var owned: bool = s.id in game.SV.owned
				var lines := "Can %s   Hız %d\nLazer %d   Jeneratör %d   Droid %d" % [game._n(s.hp), s.spd, s.las, s.gen, DOData.drone_slots(s)]
				var badge := ""
				if s.id == game.SV.ship:
					badge = "KULLANIMDA"
				elif owned:
					badge = "Hangarda"
				var btns := _shop_card(grid, _ship_tex(str(s.id)), str(s.name), lines, 0 if owned else int(s.cr), 0 if owned else int(s.uri), badge)
				if s.id == game.SV.ship:
					_buy_btn(btns, "KULLANIMDA", Callable(), false, 150)
				elif owned:
					_buy_btn(btns, "KULLAN", _shop_use_ship.bind(str(s.id)), true, 150)
				else:
					_buy_btn(btns, "SATIN AL", _shop_ship.bind(str(s.id)), game.can_pay(int(s.cr), int(s.uri)), 150)
		"lasers":
			var grid := _shop_grid()
			for id in DOData.LASER_ORDER:
				var ld: Dictionary = DOData.LASERS[id]
				_item_card(grid, str(id), "Salvo hasarı: %d  (x1 cephane)\nMermi hızı: %d\n%s" % [int(ld.dmg), int(ld.spd), str(ld.desc)])
		"gens":
			var grid := _shop_grid()
			for id in DOData.GEN_ORDER:
				var g: Dictionary = DOData.GENS[id]
				var d := ("Hız bonusu: +%d" % int(g.val)) if g.type == "spd" else ("Kalkan: +%s\nEmilim: %%%d" % [game._n(g.val), int(float(g.abs) * 100.0)])
				_item_card(grid, str(id), d)
		"drones":
			var grid := _shop_grid()
			for id in DOData.DRONE_ORDER:
				_item_card(grid, str(id), str(DOData.DRONES[id].desc) + "\nSlot: gemi başına en fazla 10 droid.")
		"forms":
			var grid := _shop_grid()
			for code in DOData.FORM_ORDER:
				var f: Dictionary = DOData.FORMS[code]
				var have: bool = code in game.SV.forms
				var bon := "Hasar %+d%%   Kalkan %+d%%   Hız %+d%%" % [int(float(f.dmg) * 100.0), int(float(f.sh) * 100.0), int(float(f.spd) * 100.0)]
				var btns := _shop_card(grid, _form_tex(str(code)), str(f.name), bon + ("\nSahipsin." if have else "\nDroid formasyonu (kalıcı)."), 0 if have else int(f.cr), 0)
				if have:
					_buy_btn(btns, "SAHİPSİN", Callable(), false, 150)
				else:
					_buy_btn(btns, "SATIN AL", _shop_form.bind(str(code)), game.can_pay(int(f.cr), 0), 150)
		"ammo":
			for a in DOData.AMMO:
				var h := _row_panel(shop_body)
				h.add_child(_icon(game._tex("res://assets/ui/ammo_%s.png" % str(a.get("icon", a.id))), 40))
				var a_uri: bool = str(a.get("cur", "cr")) == "uri"
				var info := VBoxContainer.new()
				info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				info.add_child(_mk("%s  (hasar x%s)" % [str(a.name), str(a.mult)], 15, GOLD))
				info.add_child(_mk("Elinde: %s     Fiyat: %s %s / 1.000" % [int(game.SV.ammo.get(a.id, 0)), game._n(a.price), "Uridium" if a_uri else "Kredi"], 12, TEXT2))
				h.add_child(info)
				for n in [1000, 10000, 50000]:
					var cost := int(a.price * n / 1000)
					_buy_btn(h, "+%s" % game._n(n), _shop_ammo.bind(str(a.id), int(n)), game.can_pay(0 if a_uri else cost, cost if a_uri else 0), 84)
		"rockets":
			var rocket_row := _row_panel(shop_body)
			rocket_row.add_child(_icon(game._tex("res://assets/ui/rocket_r310.png"), 40))
			var rocket_info := VBoxContainer.new()
			rocket_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rocket_info.add_child(_mk("R-310 Roket   (hasar 400)", 15, GOLD))
			rocket_info.add_child(_wrap("Stok: %s   •   Soğuma: 5 sn   •   1.000 kredi / 100 roket   •   Oyunda R tuşu" % game._n(game.SV.get("rockets", 0)), 12, TEXT2))
			rocket_row.add_child(rocket_info)
			for rocket_pack in [100, 500, 1000]:
				var rocket_cost := int(ceil(float(rocket_pack) / 100.0) * 1000.0)
				_buy_btn(rocket_row, "+%d" % rocket_pack, _shop_rockets.bind(rocket_pack), game.can_pay(rocket_cost, 0), 72)
		_:
			var cost: int = game.repair_cost()
			_service_row("Tam Tamir", "Geminin canını ve kalkanını doldurur.", "TAMİR ET", _svc_repair, cost)
			_service_row("Galaksi Haritası", "Kapılara uçmadan önce haritayı aç.", "AÇ", _open_galaxy, 0)


func _service_row(title: String, desc: String, btn: String, cb: Callable, cost: int) -> void:
	var h := _row_panel(shop_body)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_mk(title, 15, GOLD))
	info.add_child(_wrap(desc, 12, TEXT2))
	h.add_child(info)
	var pr := _mk(_cost_txt(cost, 0) if cost > 0 else "Ücretsiz", 13, GREEN)
	pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(pr)
	var b := _btn(btn, "ButtonPrimary", cb, Vector2(140, 36), game.can_pay(cost, 0), 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)


func _shop_ship(id: String) -> void:
	game.buy_ship(id)
	refresh()


func _shop_use_ship(id: String) -> void:
	game.equip_ship(id)
	refresh()


func _shop_item(id: String, n: int) -> void:
	game.buy_item(id, n)
	refresh()


func _sell_item(id: String) -> void:
	game.sell_item(id)
	refresh()


func _shop_form(code: String) -> void:
	game.buy_form(code)
	refresh()


func _shop_ammo(id: String, n: int) -> void:
	game.buy_ammo(id, n)
	refresh()


func _shop_rockets(n: int) -> void:
	game.buy_rockets(n)
	refresh()


func _svc_repair() -> void:
	game.service_repair()
	refresh()


func _build_equip() -> Control:
	var r := _make_scroll_page(8)
	equip_body = r[1]

	# Üst sekme çubuğu: HANGARLAR | CEPHANE | GEMİ | DİROİTLER | KAYNAKLAR ........ Konfi 1 2
	var st_bar := HBoxContainer.new()
	st_bar.add_theme_constant_override("separation", 0)
	st_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_body.add_child(st_bar)

	var subtabs := [
		["hangarlar", "HANGARLAR"],
		["cephane", "CEPHANE"],
		["gemi", "GEMİ"],
		["droidler", "DİROİTLER"],
		["kaynaklar", "KAYNAKLAR"],
	]
	equip_subtab_btns = {}
	for st in subtabs:
		var b := _tab_btn(str(st[1]), str(st[0]) == equip_subtab, _on_equip_subtab.bind(str(st[0])))
		st_bar.add_child(b)
		equip_subtab_btns[str(st[0])] = b

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_bar.add_child(sp)

	equip_cfg_box = HBoxContainer.new()
	equip_cfg_box.add_theme_constant_override("separation", 4)
	st_bar.add_child(equip_cfg_box)
	var kl := _mk("Konfi", 12, TEXT2)
	kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	equip_cfg_box.add_child(kl)
	equip_cfg_btns = {}
	for i in 2:
		var cb := _tab_btn(str(i + 1), false, _set_config.bind(i), 30)
		equip_cfg_box.add_child(cb)
		equip_cfg_btns[i] = cb

	equip_body.add_child(_line())

	var ec := VBoxContainer.new()
	ec.add_theme_constant_override("separation", 8)
	ec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ec.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_content = ec
	equip_body.add_child(equip_content)

	_refresh_equip()
	return r[0]


func _slot_row(key: String, title: String, parent: Node = null) -> void:
	var c: Dictionary = game.cfg()
	var cap: int = game.cap_of(key)
	var target := parent if parent != null else equip_body
	target.add_child(_mk("%s   %d / %d" % [title, c[key].size(), cap], 13, GOLD))
	var fl := _flow(4)
	target.add_child(fl)
	for i in cap:
		if i < c[key].size():
			var id: String = c[key][i]
			fl.add_child(_slot_btn(id, game.item_icon(id), "%s - çıkarmak için tıkla" % str(game.item_def(id).name), _on_unequip.bind(key, i)))
		else:
			fl.add_child(_slot_btn("", game._tex("res://assets/items/hangar_slot.png"), "Boş slot", Callable()))


func _refresh_equip() -> void:
	_clear(equip_content)
	for k in equip_subtab_btns:
		_style_tab(equip_subtab_btns[k], k == equip_subtab)
	equip_cfg_box.visible = (equip_subtab == "gemi" or equip_subtab == "droidler")
	var cur := int(game.SV.get("cfgi", 0))
	for i in equip_cfg_btns:
		_style_tab(equip_cfg_btns[i], int(i) == cur)

	match equip_subtab:
		"hangarlar":
			_refresh_equip_tab_hangarlar()
		"cephane":
			_refresh_equip_tab_cephane()
		"gemi":
			_refresh_equip_tab_gemi()
		"droidler":
			_refresh_equip_tab_droidler()
		"kaynaklar":
			_refresh_equip_tab_kaynaklar()


func _on_unequip(key: String, idx: int) -> void:
	game.unequip_slot(key, idx)
	refresh()


func _on_equip(id: String) -> void:
	game.equip_item(id)
	refresh()


func _on_form(code: String) -> void:
	game.set_form(code)
	refresh()


func _on_auto() -> void:
	game.auto_equip(game.cfg(), game.active_cfg_idx())
	game._clamp_vitals()
	game.save_game()
	refresh()


func _pick_ammo(id: String) -> void:
	game.SV.sel = id
	refresh()


# ============================================================================
#  GÖREVLER
# ============================================================================
func _build_missions() -> Control:
	var r := _make_scroll_page(8)
	mission_body = r[1]
	return r[0]


func _refresh_missions() -> void:
	_clear(mission_body)
	_page_head(mission_body, "GÖREV GÜNLÜĞÜ", "NPC avı ilerlemesi yerel kayda yazılır. Tamamlanan görevin ödülünü almak için talep et.")
	for q in game.quest_list():
		var state: Dictionary = game.SV.quests.get(str(q.id), {"progress": 0, "claimed": false})
		var target: int = int(q.target)
		var progress := mini(int(state.get("progress", 0)), target)
		var claimed := bool(state.get("claimed", false))
		var done := progress >= target
		var row := _row_panel(mission_body)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 4)
		info.add_child(_mk(str(q.title), 15, NEON_ORANGE))
		var npc_name: String = str(DOData.NPCS[str(q.npc)].name)
		info.add_child(_mk("%s avı   •   İlerleme %d / %d" % [npc_name, progress, target], 12, ICE_WHITE))
		info.add_child(_bar(float(progress), float(target), GREEN if done else NEON_BLUE_BRIGHT, 8.0))
		info.add_child(_mk("Ödül: %s XP   %s kredi   %s uridium" % [game._n(q.xp), game._n(q.cr), game._n(q.uri)], 12, DIM))
		row.add_child(info)
		var claim := _btn("ALINDI" if claimed else ("ÖDÜLÜ AL" if done else "SÜRÜYOR"), "ButtonGold" if (done and not claimed) else "Button", _claim_quest.bind(str(q.id)), Vector2(128, 38), not (claimed or not done), 12)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(claim)


func _claim_quest(id: String) -> void:
	game.claim_quest(id)
	refresh()


# ============================================================================
#  YETENEK AĞACI
# ============================================================================
func _build_skills() -> Control:
	var pg := Control.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pg.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# --- ust bolum: kaydirilabilir (agac + secili yetenek ayrintisi)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	skill_body = VBoxContainer.new()
	skill_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_body.add_theme_constant_override("separation", 8)
	sc.add_child(skill_body)
	skill_body.add_child(_mk("PİLOT BIO  •  YETENEK AĞACI", 20, NEON_ORANGE))
	var cv := SkillCanvas.new()
	cv.game = game
	cv.on_pick = _pick_skill
	cv.on_buy = _spend_skill
	cv.build()
	skill_canvas = cv
	skill_body.add_child(cv)
	skill_detail = VBoxContainer.new()
	skill_body.add_child(skill_detail)
	skill_body.add_child(_wrap("Soldaki renkli şerit ve ikonun altındaki çubuk: mavi = Temel, mor = Orta, kırmızı = İleri grup.   Yeşil nokta: yükseltilebilir   •   Altın çerçeve: tamamlandı   •   Kilit: ön koşul eksik   •   Turuncu çerçeve: seçili yeteneğin ön koşulları   •   Çift tık: 1 puan yükle.", 11, DIM))
	# --- alt sabit cubuk: Ar-Ge puani + Log Disk alim dugmeleri
	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", _sb(Color(0.02, 0.06, 0.11, 0.98), Color(0.25, 0.5, 0.8, 0.9), 1, 6, Vector4(12, 8, 12, 8)))
	vb.add_child(bar_panel)
	skill_bar = HBoxContainer.new()
	skill_bar.add_theme_constant_override("separation", 14)
	bar_panel.add_child(skill_bar)
	return pg


func _refresh_skills() -> void:
	if skill_bar == null or skill_canvas == null:
		return
	var ST = game.SkillTree
	var SV: Dictionary = game.SV
	var tot: int = game.rd_total()
	var spent: int = game.rd_spent()
	var free_pts: int = game.rd_free()
	var disks: int = int(SV.get("logdisks", 0))
	var nxt: int = ST.disks_for_next(disks)
	if _sk_sel == "" or ST.find(_sk_sel).is_empty():
		_sk_sel = "hull_1"
	skill_canvas.set("sel", _sk_sel)
	skill_canvas.queue_redraw()
	_refresh_skill_detail()
	# ---- alt cubuk
	_clear(skill_bar)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_mk("AR-GE PUANI", 11, DIM))
	var big := _mk("%d" % free_pts, 24, GOLD if free_pts > 0 else TEXT2, true)
	head.add_child(big)
	var sub := _mk("boşta   •   %d / %d toplam   •   %d harcandı" % [tot, ST.MAX_POINTS, spent], 12, NEON_ORANGE)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	left.add_child(head)
	left.add_child(_bar(float(tot), float(ST.MAX_POINTS), GOLD, 6.0))
	var nxt_txt := "Maksimum Ar-Ge puanına ulaştın." if tot >= ST.MAX_POINTS else "Log Disk: %s   •   Sonraki puana %s Log Disk (%s U) kaldı" % [game._n(float(disks)), game._n(float(nxt)), game._n(float(nxt * ST.LOGDISK_URI))]
	left.add_child(_wrap(nxt_txt, 11, TEXT2))
	left.add_child(_wrap("Kredi: %s   •   Seprom: %s   •   Uridium: %s" % [game._n(float(SV.cr)), game._n(float(SV.get("seprom", 0))), game._n(float(SV.uri))], 11, DIM))
	skill_bar.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.add_child(_mk("LOG DISK SATIN AL   (1 disk = %d U)" % ST.LOGDISK_URI, 10, DIM))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	for n in [1, 10, 100]:
		var can_buy: bool = tot < ST.MAX_POINTS and (bool(SV.get("free", false)) or int(SV.uri) >= n * ST.LOGDISK_URI)
		btns.add_child(_btn("+%d DISK\n%s U" % [n, game._n(float(n * ST.LOGDISK_URI))], "ButtonGold" if can_buy else "Button", _buy_disk.bind(n), Vector2(92, 46), can_buy, 11))
	var can_reset: bool = spent > 0 and (bool(SV.get("free", false)) or int(SV.uri) >= game.reset_cost_uri())
	btns.add_child(_btn("SIFIRLA\n%s U" % game._n(float(game.reset_cost_uri())), "Button", _reset_skills, Vector2(92, 46), can_reset, 11))
	right.add_child(btns)
	skill_bar.add_child(right)


func _pick_skill(id: String) -> void:
	_sk_sel = id
	if skill_canvas != null:
		skill_canvas.set("sel", id)
		skill_canvas.queue_redraw()
	_refresh_skill_detail()


func _fmt_bonus(node: Dictionary, v: float) -> String:
	if str(node.effect) == "hp_flat":
		return "+%s HP" % game._n(v)
	return "+%%%s" % str(snappedf(v * 100.0, 0.1))


func _skill_icon(node: Dictionary, scale_k: float) -> Control:
	var tex = load(game.SkillTree.ATLAS)
	if tex == null:
		return Control.new()
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = game.SkillTree.icon_region(int(node.icon))
	var tr := TextureRect.new()
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(74.0, 85.0) * scale_k
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tr


func _refresh_skill_detail() -> void:
	if skill_detail == null:
		return
	_clear(skill_detail)
	var node: Dictionary = game.SkillTree.find(_sk_sel)
	if node.is_empty():
		return
	var id := str(node.id)
	var pts: int = int(node.pts)
	var rank: int = game.skill_rank(id)
	var req_ok: bool = game.skill_req_ok(node)
	var row := _row_panel(skill_detail)
	row.add_child(_skill_icon(node, 1.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	info.add_child(_mk("%s   •   %d / %d puan" % [str(node.name), rank, pts], 16, NEON_ORANGE if (req_ok or rank > 0) else DIM))
	info.add_child(_bar(float(rank), float(pts), GOLD, 6.0))
	info.add_child(_wrap(str(node.desc), 12, TEXT2))
	var now_b: float = float(node.bonus) * float(rank) / float(pts)
	info.add_child(_mk("Şu an: %s   •   Azami: %s   •   Grup: %s" % [_fmt_bonus(node, now_b), _fmt_bonus(node, float(node.bonus)), str(game.SkillTree.TIERS[str(node.tier)].name)], 11, GREEN if rank > 0 else DIM))
	var reqs: Dictionary = node.req
	if reqs.is_empty():
		info.add_child(_mk("Ön koşul: yok", 11, DIM))
	else:
		var parts: PackedStringArray = []
		for k in reqs.keys():
			parts.append("%s %d puan (şu an %d)" % [_skill_name(str(k)), int(reqs[k]), game.skill_rank(str(k))])
		info.add_child(_wrap("Ön koşul: " + ", ".join(parts), 11, DIM if req_ok else RED))
	row.add_child(info)
	var maxed: bool = rank >= pts
	var cost_txt := ""
	var can_spend := false
	if not maxed:
		var cst: Dictionary = game.SkillTree.level_cost(node, rank + 1)
		cost_txt = "\n%s Kr" % game._n(float(cst.cr))
		if int(cst.sep) > 0:
			cost_txt += " + %s Sp" % game._n(float(cst.sep))
		var rich: bool = bool(game.SV.get("free", false)) or (int(game.SV.cr) >= int(cst.cr) and int(game.SV.get("seprom", 0)) >= int(cst.sep))
		can_spend = req_ok and game.rd_free() > 0 and rich
	var spend := _btn("TAMAMLANDI" if maxed else "1 PUAN YÜKLE" + cost_txt, "ButtonGold" if can_spend else "Button", _spend_skill.bind(id), Vector2(150, 50), can_spend, 11)
	spend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spend)


# Profesyonel yetenek agaci: 3 cerceveli panel (Saldiri / Savunma / Ekonomi),
# her panelde 3 sira = Temel (mavi) / Orta (mor) / Ileri (kirmizi) grup.
class SkillCanvas extends Control:
	const TIER_ORDER := ["basic", "mid", "adv"]
	const TIER_COL := {
		"basic": Color(0.30, 0.62, 1.0),
		"mid": Color(0.74, 0.38, 0.98),
		"adv": Color(1.0, 0.32, 0.30),
	}
	const BR_COL := {
		"atk": Color(1.0, 0.56, 0.44),
		"def": Color(0.55, 0.82, 1.0),
		"eco": Color(1.0, 0.84, 0.40),
	}
	const BR_TITLE := {"atk": "SALDIRI", "def": "SAVUNMA", "eco": "KAYNAK  &  EKONOMİ"}
	const CELL_MAX := 84.0
	const PAD := 8.0
	const GAP := 10.0
	const INNER := 6.0
	const HEAD_H := 30.0
	var game
	var sel := ""
	var on_pick: Callable
	var on_buy: Callable
	var atlas: Texture2D = null
	var pos := {}          # id -> sol ust kose
	var panels: Array = [] # {rect, key}
	var tile := Vector2(60.0, 68.0)
	var hover := ""
	var _t := 0.0
	var _font: Font
	var _branches: Array = []

	func build() -> void:
		var ST = game.SkillTree
		atlas = load(ST.ATLAS) as Texture2D
		_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_branches.clear()
		for br in ST.BRANCHES:
			var tiers: Array = [[], [], []]
			for sk in ST.SKILLS:
				if str(sk.branch) == str(br[0]):
					var ti: int = TIER_ORDER.find(str(sk.tier))
					if ti >= 0:
						(tiers[ti] as Array).append(sk)
			var cols := 3
			for t in tiers:
				cols = maxi(cols, (t as Array).size())
			_branches.append({"key": str(br[0]), "cols": cols, "tiers": tiers})
		_relayout()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_relayout()
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			if hover != "":
				hover = ""
				tooltip_text = ""
				queue_redraw()

	func _process(dt: float) -> void:
		if is_visible_in_tree():
			_t += dt
			queue_redraw()

	func _relayout() -> void:
		if _branches.is_empty():
			return
		var total := 0
		for b in _branches:
			total += int(b.cols)
		var nb: int = _branches.size()
		var w: float = size.x if size.x > 100.0 else 700.0
		var avail: float = w - 2.0 * PAD - GAP * float(nb - 1) - 2.0 * INNER * float(nb)
		var cell: float = minf(CELL_MAX, avail / float(total))
		var tw: float = maxf(34.0, cell - 6.0)
		tile = Vector2(tw, tw * 85.0 / 74.0)
		var row_h: float = tile.y + 16.0
		var ph: float = HEAD_H + 3.0 * row_h + 12.0
		var used: float = cell * float(total) + (GAP + 2.0 * INNER) * float(nb) - GAP
		var x: float = maxf(PAD, (w - used) * 0.5)
		pos.clear()
		panels.clear()
		for b in _branches:
			var pw: float = cell * float(b.cols) + 2.0 * INNER
			panels.append({"rect": Rect2(x, PAD, pw, ph), "key": str(b.key)})
			for ti in range(3):
				var items: Array = b.tiers[ti]
				var row_w: float = cell * float(items.size())
				var rx: float = x + (pw - row_w) * 0.5 + (cell - tile.x) * 0.5
				for i in range(items.size()):
					pos[str(items[i].id)] = Vector2(rx + cell * float(i), PAD + HEAD_H + 6.0 + row_h * float(ti))
			x += pw + GAP
		custom_minimum_size = Vector2(0.0, ph + 2.0 * PAD)

	func _can_buy(sk: Dictionary) -> bool:
		var rank: int = game.skill_rank(str(sk.id))
		if rank >= int(sk.pts) or not game.skill_req_ok(sk) or game.rd_free() <= 0:
			return false
		var cst: Dictionary = game.SkillTree.level_cost(sk, rank + 1)
		return bool(game.SV.get("free", false)) or (int(game.SV.cr) >= int(cst.cr) and int(game.SV.get("seprom", 0)) >= int(cst.sep))

	func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y),
			Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.end.y - c),
			Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
			Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])

	func _draw_panel(r: Rect2, key: String) -> void:
		var poly := _chamfer(r, 9.0)
		draw_colored_polygon(poly, Color(0.02, 0.055, 0.11, 0.92))
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, Color(0.25, 0.5, 0.8, 0.95), 1.5, true)
		var inner := _chamfer(r.grow(-4.0), 6.0)
		var inner_closed := PackedVector2Array(inner)
		inner_closed.append(inner[0])
		draw_polyline(inner_closed, Color(0.16, 0.30, 0.46, 0.55), 1.0, true)
		var col: Color = BR_COL.get(key, Color.WHITE)
		draw_string(_font, Vector2(r.position.x, r.position.y + 21.0), str(BR_TITLE.get(key, key)), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, col)
		draw_line(Vector2(r.position.x + 14.0, r.position.y + HEAD_H), Vector2(r.end.x - 14.0, r.position.y + HEAD_H), Color(col.r, col.g, col.b, 0.45), 1.5, true)
		draw_circle(Vector2(r.position.x + 14.0, r.position.y + HEAD_H), 2.5, col)
		draw_circle(Vector2(r.end.x - 14.0, r.position.y + HEAD_H), 2.5, col)
		var row_h: float = tile.y + 16.0
		for ti in range(3):
			var y: float = r.position.y + HEAD_H + 6.0 + row_h * float(ti)
			var tc: Color = TIER_COL[TIER_ORDER[ti]]
			draw_rect(Rect2(r.position.x + 6.0, y + 4.0, 3.0, tile.y - 8.0), Color(tc.r, tc.g, tc.b, 0.85), true)

	func _draw() -> void:
		if game == null or game.SV.is_empty():
			return
		var ST = game.SkillTree
		for p in panels:
			_draw_panel(p.rect, str(p.key))
		var sel_req := {}
		if sel != "":
			var sn: Dictionary = ST.find(sel)
			if not sn.is_empty():
				sel_req = sn.req
		var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
		var fsz: int = clampi(int(tile.x * 0.21), 9, 13)
		for sk in ST.SKILLS:
			var id := str(sk.id)
			if not pos.has(id):
				continue
			var p: Vector2 = pos[id]
			var rank: int = game.skill_rank(id)
			var pts: int = int(sk.pts)
			var unlocked: bool = game.skill_req_ok(sk)
			var rect := Rect2(p, tile)
			var tc: Color = TIER_COL[str(sk.tier)]
			draw_rect(rect, Color(0.03, 0.06, 0.1, 1.0), true)
			if atlas != null:
				draw_texture_rect_region(atlas, rect, ST.icon_region(int(sk.icon)), Color.WHITE if (unlocked or rank > 0) else Color(0.42, 0.42, 0.48, 1.0))
			else:
				draw_rect(rect, Color(0.12, 0.16, 0.22), true)
				draw_string(_font, p + Vector2(4.0, tile.y * 0.5), str(sk.name).substr(0, 8), HORIZONTAL_ALIGNMENT_LEFT, tile.x - 6.0, 10, Color.WHITE)
			if not unlocked and rank == 0:
				draw_rect(rect, Color(0.0, 0.0, 0.0, 0.42), true)
				var c := rect.get_center() - Vector2(0.0, tile.y * 0.1)
				draw_rect(Rect2(c + Vector2(-7.0, -1.0), Vector2(14.0, 11.0)), Color(0.82, 0.87, 0.96, 0.92), true)
				draw_arc(c + Vector2(0.0, -1.0), 5.0, PI, TAU, 12, Color(0.82, 0.87, 0.96, 0.92), 2.0, true)
			if id == hover:
				draw_rect(rect, Color(1.0, 1.0, 1.0, 0.10), true)
			# puan yazisi (ikonun alt plakasi)
			var txt := "%d/%d" % [rank, pts]
			var tcol := Color(1.0, 0.85, 0.35) if rank >= pts else (Color(0.75, 0.95, 1.0) if rank > 0 else Color(0.78, 0.82, 0.88))
			var tpos := p + Vector2(0.0, tile.y - 6.0)
			draw_string_outline(_font, tpos, txt, HORIZONTAL_ALIGNMENT_CENTER, tile.x, fsz, 4, Color(0.0, 0.0, 0.0, 0.9))
			draw_string(_font, tpos, txt, HORIZONTAL_ALIGNMENT_CENTER, tile.x, fsz, tcol)
			# ilerleme cubugu (ikonun altinda, grup renginde)
			var by: float = p.y + tile.y + 5.0
			draw_rect(Rect2(p.x, by, tile.x, 4.0), Color(0.08, 0.12, 0.18, 1.0), true)
			draw_rect(Rect2(p.x, by, tile.x * float(rank) / float(maxi(pts, 1)), 4.0), Color(1.0, 0.82, 0.3) if rank >= pts else tc, true)
			if rank >= pts:
				draw_rect(rect.grow(-1.0), Color(1.0, 0.82, 0.3, 0.95), false, 2.5)
			if sel_req.has(id):
				draw_rect(rect.grow(3.0), Color(1.0, 0.7, 0.2, 0.95), false, 1.5)
			if id == sel:
				draw_rect(rect.grow(6.0), Color(0.6, 0.95, 1.0, 0.25), false, 3.0)
				draw_rect(rect.grow(3.0), Color(0.6, 0.95, 1.0, 1.0), false, 2.0)
			if _can_buy(sk):
				var dc := p + Vector2(tile.x - 8.0, 9.0)
				draw_circle(dc, 7.0 + 2.5 * pulse, Color(0.3, 1.0, 0.45, 0.20 + 0.25 * pulse))
				draw_circle(dc, 5.0, Color(0.3, 1.0, 0.45, 1.0))
				draw_arc(dc, 5.0, 0.0, TAU, 20, Color(0.0, 0.25, 0.1, 1.0), 1.5, true)

	func _hit(at: Vector2) -> String:
		for id in pos.keys():
			if Rect2(pos[id], tile).has_point(at):
				return str(id)
		return ""

	func _tip(id: String) -> String:
		if id == "":
			return ""
		var sk: Dictionary = game.SkillTree.find(id)
		if sk.is_empty():
			return ""
		return "%s   %d / %d\n%s" % [str(sk.name), game.skill_rank(id), int(sk.pts), str(sk.desc)]

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var h := _hit(ev.position)
			if h != hover:
				hover = h
				tooltip_text = _tip(h)
				queue_redraw()
			return
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			var id := _hit(ev.position)
			if id == "":
				return
			if ev.pressed and ev.double_click:
				if on_buy.is_valid():
					on_buy.call(id)
			elif not ev.pressed:
				if on_pick.is_valid():
					on_pick.call(id)
			accept_event()
		elif ev is InputEventScreenTouch and not ev.pressed:
			var id2 := _hit(ev.position)
			if id2 != "":
				if on_pick.is_valid():
					on_pick.call(id2)
				accept_event()


func _buy_disk(n: int) -> void:
	game.buy_logdisk(n)
	refresh()


func _reset_skills() -> void:
	game.reset_skills()
	refresh()


func _skill_name(id: String) -> String:
	for node in game.skill_tree():
		if str(node.id) == id:
			return str(node.name)
	return id


func _spend_skill(id: String) -> void:
	game.spend_skill_point(id)
	refresh()


# ============================================================================
#  PİLOT PROFİLİ
# ============================================================================
func _build_profile() -> Control:
	var r := _make_scroll_page(8)
	profile_body = r[1]
	_refresh_profile()
	return r[0]


# ---------- ortak yardimcilar (Bilgi + Istatistikler) ----------
func _rank_icon(icon_id: int, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = game._tex(RankSys.ICON_PATH % icon_id)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _stat_card(caption: String, value: String, col: Color) -> Control:
	var pc := _panel("PanelInset")
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	v.add_child(_mk(caption.to_upper(), 10, DIM))
	v.add_child(_mk(value, 18, col, true))
	return pc


func _fill_bar(frac: float, col: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(frac, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.05, 0.09, 1.0)
	bg.border_color = Color(0.16, 0.30, 0.46, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


func _logo_rect(px: int) -> TextureRect:
	var fk: String = str(game.FACTION_SM_LOGO.get(int(game.SV.get("faction", 0)), ""))
	var t := TextureRect.new()
	if fk != "":
		t.texture = game._tex("res://assets/ui/logo_sm_%s.png" % fk)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _refresh_profile() -> void:
	_clear(profile_body)
	var sv: Dictionary = game.SV
	var xp: float = float(sv.xp)
	var hon: float = float(sv.hon)
	var lv: int = DOData.level_of(xp)
	var cr: int = int(sv.cr)
	var uri: int = int(sv.uri)
	var info: Dictionary = RankSys.summary(game)
	var me: Dictionary = info.me
	var rk: Dictionary = RankSys.display(me)
	var fac: String = str(DOData.FACTIONS.get(int(sv.get("faction", 1)), {}).get("name", "-"))
	var days: int = maxi(0, int((Time.get_unix_time_from_system() - float(sv.get("reg_ts", Time.get_unix_time_from_system()))) / 86400.0))
	var npc_kills: int = int(sv.get("kills", 0))
	var qdone := 0
	var qd = sv.get("quests", {})
	if typeof(qd) == TYPE_DICTIONARY:
		for k in qd:
			if typeof(qd[k]) == TYPE_DICTIONARY and bool(qd[k].get("claimed", false)):
				qdone += 1

	# ---- Kimlik karti: logo | isim + rutbe | seviye / XP cubugu
	var hero := _panel("PanelCard")
	profile_body.add_child(hero)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 14)
	hero.add_child(hh)
	hh.add_child(_logo_rect(56))
	var idv := VBoxContainer.new()
	idv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idv.add_theme_constant_override("separation", 3)
	hh.add_child(idv)
	idv.add_child(_mk(str(sv.get("callsign", "Gezgin")), 22, ICE_WHITE, true))
	idv.add_child(_mk("%s   •   %s   •   Harita %s" % [fac, str(game.ship_def().name), str(sv.get("map", "-"))], 12, DIM))
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 8)
	idv.add_child(rr)
	rr.add_child(_rank_icon(int(rk.icon), 24))
	var rl := _mk(str(rk.name), 15, GOLD)
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rr.add_child(rl)
	var rp := _mk("•  %s rütbe puanı" % RankSys.fmt_pts(float(me.pts)), 12, DIM)
	rp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rr.add_child(rp)

	var lvb := VBoxContainer.new()
	lvb.custom_minimum_size = Vector2(240, 0)
	lvb.add_theme_constant_override("separation", 4)
	hh.add_child(lvb)
	lvb.add_child(_mk("SEVİYE %d" % lv, 16, GREEN, true))
	var lo: float = 0.0 if lv <= 1 else 10000.0 * pow(2.0, float(lv - 2))
	var hi: float = 10000.0 * pow(2.0, float(lv - 1))
	if lv >= 30:
		lvb.add_child(_fill_bar(1.0, GREEN))
		lvb.add_child(_mk("Azami seviye", 11, DIM))
	else:
		lvb.add_child(_fill_bar((xp - lo) / maxf(hi - lo, 1.0), GREEN))
		lvb.add_child(_mk("%s / %s EP" % [game._n(xp), game._n(hi)], 11, DIM))

	# ---- Istatistik kartlari
	profile_body.add_child(_section("GENEL"))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_body.add_child(g)
	g.add_child(_stat_card("Deneyim", game._n(xp), ICE_WHITE))
	g.add_child(_stat_card("Onur", game._n(hon), NEON_ORANGE))
	g.add_child(_stat_card("Seviye", str(lv), GOLD))
	g.add_child(_stat_card("Bitcoin", game._n(cr) + " BTC", GOLD))
	g.add_child(_stat_card("Platin", game._n(uri) + " PLT", Color(0.5, 0.85, 1.0)))
	g.add_child(_stat_card("Kargo", "0 / 100", TEXT2))
	profile_body.add_child(_section("SAVAŞ KAYDI"))
	var g2 := GridContainer.new()
	g2.columns = 3
	g2.add_theme_constant_override("h_separation", 8)
	g2.add_theme_constant_override("v_separation", 8)
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_body.add_child(g2)
	g2.add_child(_stat_card("İmha edilen NPC", game._n(npc_kills), RED))
	g2.add_child(_stat_card("Tamamlanan görev", str(qdone), GREEN))
	g2.add_child(_stat_card("Kayıt süresi", "%d gün" % days, TEXT2))


# ============================================================================
#  İSTATİSTİKLER  (rütbe, rütbe puanı, sıralama, puan dökümü, ilk 10)
# ============================================================================
func _build_stats() -> Control:
	var r := _make_scroll_page(8)
	stats_body = r[1]
	return r[0]


func _col(txt: String, w: int, fs := 13, col := ICE_WHITE, right := false) -> Label:
	var l := _mk(txt, fs, col)
	l.custom_minimum_size = Vector2(w, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _refresh_stats() -> void:
	_clear(stats_body)
	var info: Dictionary = RankSys.summary(game)
	var me: Dictionary = info.me
	var rk: Dictionary = RankSys.display(me)
	var is_adm: bool = bool(me.admin)
	var fac_name := func(f: int) -> String: return str(DOData.FACTIONS.get(f, {}).get("name", "-"))

	_page_head(stats_body, "İSTATİSTİKLER", "Rütbe puanın şirketindeki diğer oyuncularla kıyaslanır; rozetin sıralamandaki yüzdelik dilime göre belirlenir.")

	# ---- Rutbe karti
	var hero := _panel("PanelCard")
	stats_body.add_child(hero)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 16)
	hero.add_child(hh)
	hh.add_child(_rank_icon(int(rk.icon), 64))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	hh.add_child(v)
	v.add_child(_mk("RÜTBE", 10, DIM))
	v.add_child(_mk(str(rk.name), 24, GOLD, true))
	v.add_child(_mk("%s   •   %s" % [str(me.name), fac_name.call(int(me.faction))], 12, DIM))
	if is_adm:
		var adm := _wrap("Admin rozeti sıralamaya girmez. Oyuncu olsaydın: %s  (şirket sırası #%d / %d)" % [str(RankSys.RANKS_TOP[int(me.idx)][0]), int(me.pos), int(me.n)], 12, NEON_ORANGE)
		v.add_child(adm)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	hh.add_child(cards)
	var pos_txt: String = "—" if is_adm else "#%d / %d" % [int(me.pos), int(me.n)]
	var pct_txt: String = "—" if is_adm else "İlk %%%s" % String.num(float(me.pos) / float(maxi(int(me.n), 1)) * 100.0, 2).replace(".", ",")
	var c1 := _stat_card("Rütbe puanı", RankSys.fmt_pts(float(me.pts)), GOLD)
	var c2 := _stat_card("Şirket sırası", pos_txt, ICE_WHITE)
	var c3 := _stat_card("Dilim", pct_txt, GREEN)
	for c in [c1, c2, c3]:
		c.custom_minimum_size = Vector2(112, 0)
		cards.add_child(c)

	# ---- Puan dokumu
	stats_body.add_child(_section("RÜTBE PUANI DÖKÜMÜ"))
	var brk := _panel("PanelCard")
	stats_body.add_child(brk)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 5)
	brk.add_child(bv)
	for p in me.parts:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(_col(str(p.label), 170, 13, TEXT2))
		var d := _col(str(p.detail), 0, 12, DIM)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(d)
		h.add_child(_col("+" + RankSys.fmt_pts(float(p.value)), 90, 13, ICE_WHITE, true))
		bv.add_child(h)
	if float(me.penalty) > 0.0:
		var hp := HBoxContainer.new()
		hp.add_child(_col("Ceza", 170, 13, RED))
		var dp := _col("Kendi şirketinden oyuncu vurma / radyasyon bölgesinde ölme", 0, 12, DIM)
		dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp.add_child(dp)
		hp.add_child(_col("-" + RankSys.fmt_pts(float(me.penalty)), 90, 13, RED, true))
		bv.add_child(hp)
	bv.add_child(_line())
	var ht := HBoxContainer.new()
	var tl := _col("TOPLAM", 170, 13, GOLD)
	ht.add_child(tl)
	var ts := Control.new()
	ts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ht.add_child(ts)
	ht.add_child(_col(RankSys.fmt_pts(float(me.pts)), 110, 16, GOLD, true))
	bv.add_child(ht)

	# ---- Rutbe tablosu
	stats_body.add_child(_section("RÜTBE TABLOSU  (şirketteki oyuncuların yüzdelik dilimi)"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_body.add_child(grid)
	for i in RankSys.RANKS_TOP.size():
		var mine: bool = (not is_adm) and i == int(me.idx)
		var pc := _panel("PanelNote" if mine else "PanelInset")
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		pc.add_child(h)
		h.add_child(_rank_icon(RankSys.icon_id(i), 24))
		var nm := _col(str(RankSys.RANKS_TOP[i][0]), 0, 12, GOLD if mine else ICE_WHITE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var share: String = "şirkette en fazla 1 kişi" if i == 0 else "%%%s" % String.num(float(RankSys.RANKS_TOP[i][1]), 2).replace(".", ",")
		h.add_child(_col(share, 0, 11, DIM, true))
		grid.add_child(pc)

	# ---- Ilk 10
	stats_body.add_child(_section("EN İYİ 10 OYUNCU"))
	var tp := _panel("PanelCard")
	stats_body.add_child(tp)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tp.add_child(tv)
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 10)
	hd.add_child(_col("#", 28, 11, DIM))
	hd.add_child(_col("", 24, 11, DIM))
	var hn := _col("OYUNCU", 0, 11, DIM)
	hn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(hn)
	hd.add_child(_col("RÜTBE", 150, 11, DIM))
	hd.add_child(_col("ŞİRKET", 56, 11, DIM))
	hd.add_child(_col("PUAN", 100, 11, DIM, true))
	tv.add_child(hd)
	tv.add_child(_line())
	var top: Array = info.top
	if top.is_empty():
		tv.add_child(_wrap("Henüz sıralanacak oyuncu yok.", 12, DIM))
	for i in top.size():
		var e: Dictionary = top[i]
		var er: Dictionary = RankSys.display(e)
		var row := _panel("PanelNote" if bool(e.me) else "PanelInset")
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var medal: Color = [GOLD, Color(0.82, 0.88, 0.95), Color(0.85, 0.55, 0.3)][i] if i < 3 else DIM
		h.add_child(_col(str(i + 1), 28, 14, medal))
		h.add_child(_rank_icon(int(er.icon), 24))
		var en := _col(str(e.name), 0, 13, GOLD if bool(e.me) else ICE_WHITE)
		en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		en.clip_text = true
		h.add_child(en)
		h.add_child(_col(str(er.name), 150, 12, TEXT2))
		h.add_child(_col(str(fac_name.call(int(e.faction))), 56, 12, DIM))
		h.add_child(_col(RankSys.fmt_pts(float(e.pts)), 100, 13, ICE_WHITE, true))
		tv.add_child(row)
	stats_body.add_child(_wrap("Sıralama bu cihazdaki hesapları kapsar; çevrimiçi sunucu bağlı olmadığı için diğer oyuncular listelenemez. Admin rozetli hesaplar sıralamaya dahil edilmez.", 11, DIM))


func _save_callsign(input: LineEdit) -> void:
	game.save_callsign(input.text)
	refresh()


# ============================================================================
#  GALAKSİ / ROTA
# ============================================================================
func _build_galaxy() -> Control:
	var r := _make_scroll_page(8)
	galaxy_body = r[1]
	return r[0]


func _refresh_galaxy() -> void:
	_clear(galaxy_body)
	var route := str(game.SV.get("route_to", ""))
	_page_head(galaxy_body, "GALAKSİ HARİTASI", "Konum: %s   •   Rota: %s" % [str(game.cur), route if route != "" else "seçilmedi"])
	if route != "":
		galaxy_body.add_child(_btn("ROTAYI İPTAL ET", "ButtonDanger", _cancel_route, Vector2(170, 34), true, 12))
	galaxy_body.add_child(_wrap("Bir hedef seç. Gemi ilk bağlantılı kapıya yönelir; kapıdan geçmek için yanına ulaşıp J tuşuna bas.", 13, TEXT2))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	galaxy_body.add_child(grid)
	var names: Array = game.maps.keys()
	names.sort()
	for map_id in names:
		var id := str(map_id)
		var map_data: Dictionary = game.maps[id]
		var is_cur: bool = id == str(game.cur)
		var pvp: bool = bool(map_data.pvp)
		var kind := "ButtonCurrent" if is_cur else ("ButtonPvp" if pvp else "Button")
		var b := _btn("%s%s\n%s" % [id, "  • MEVCUT" if is_cur else "", "PvP bölgesi" if pvp else "Kapılar ve görev hedefleri"], kind, _request_route.bind(id), Vector2(120, 60), not is_cur, 11)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)


func _request_route(map_id: String) -> void:
	game.request_map_route(map_id)
	_close()


func _cancel_route() -> void:
	game.clear_map_route()
	refresh()


# ============================================================================
#  SUNUCU GEREKTİREN SERVİSLER (kapalı sayfalar)
# ============================================================================
func _build_blocked_page(heading: String, explanation: String, status: String) -> Control:
	var r := _make_scroll_page(10)
	var body: VBoxContainer = r[1]
	var card := _panel("PanelCard")
	body.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var hl := _mk(heading, 20, NEON_ORANGE)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(hl)
	var tag := _panel("PanelChip")
	tag.add_child(_mk("ÇEVRİMDIŞI", 11, Color(1.0, 0.72, 0.4)))
	top.add_child(tag)
	v.add_child(_line())
	v.add_child(_wrap(explanation, 14, ICE_WHITE))
	var note := _panel("PanelNote")
	note.add_child(_wrap("DURUM: " + status, 13, Color(1.0, 0.72, 0.4)))
	v.add_child(note)
	var b := _btn("Sunucu bağlantısı olmadan kullanılamaz", "Button", Callable(), Vector2(320, 40), false, 12)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(b)
	return r[0]


# ============================================================================
#  AÇIK ARTIRMA EVİ  (saatlik)  -  sunucu tarafından yönetilir
# ============================================================================
const AUC_FILTERS := ["Tümü", "Lazer", "Hız Jeneratörü", "Kalkan Jeneratörü", "Droid"]
const AUC_W := [0, 92, 100, 82, 66, 66]    # sütun genişlikleri (0 = kalan alan)


func _auc() -> Variant:
	if Net.gm != null and Net.gm.auc != null:
		return Net.gm.auc
	return null


func _auc_hook() -> void:
	var A = _auc()
	if A != null and not A.changed.is_valid():
		A.changed = _on_auc_changed


func _on_auc_changed() -> void:
	if cur_tab == "auction" and is_visible_in_tree():
		_refresh_auction()


func _build_auction() -> Control:
	var pg := Control.new()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	pg.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# --- başlık + filtre
	var top := HBoxContainer.new()
	root.add_child(top)
	var ttl := _mk("AÇIK ARTIRMA EVİ", 18, GOLD, true)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ttl)
	var flt := OptionButton.new()
	for f in AUC_FILTERS:
		flt.add_item(str(f))
	flt.custom_minimum_size = Vector2(170, 28)
	flt.item_selected.connect(_auc_set_filter)
	top.add_child(flt)
	# --- üst sekme (yalnızca SAATLİK)
	var tabs := HBoxContainer.new()
	root.add_child(tabs)
	tabs.add_child(_btn("SAATLİK", "ButtonGold", Callable(), Vector2(130, 28), true, 12))
	# --- alt sekmeler + geri sayım
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	root.add_child(sub)
	for s in [["lots", "AÇIK ARTIRMA"], ["mine", "TEKLİFLERİM"], ["won", "KAZANDIKLARIM"], ["hist", "GEÇMİŞ"]]:
		var b := _btn(str(s[1]), "ButtonSmall", _auc_set_sub.bind(str(s[0])), Vector2(0, 26), true, 11)
		b.toggle_mode = true
		auc_sub_btns[str(s[0])] = b
		sub.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_child(sp)
	auc_end_lbl = _mk("", 12, GOLD)
	sub.add_child(auc_end_lbl)
	# --- gövde: tablo + sağ panel
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	root.add_child(main)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	main.add_child(left)
	auc_head = HBoxContainer.new()
	auc_head.add_theme_constant_override("separation", 4)
	left.add_child(auc_head)
	left.add_child(_line())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	auc_list = VBoxContainer.new()
	auc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auc_list.add_theme_constant_override("separation", 0)
	sc.add_child(auc_list)
	left.add_child(sc)
	var side_pc := _panel("PanelInset")
	side_pc.custom_minimum_size = Vector2(176, 0)
	auc_side = VBoxContainer.new()
	auc_side.add_theme_constant_override("separation", 6)
	side_pc.add_child(auc_side)
	main.add_child(side_pc)
	# --- alt çubuk: bakiye
	var bot := _panel("PanelBar")
	root.add_child(bot)
	auc_bal = _mk("", 12, TEXT2)
	bot.add_child(auc_bal)
	var tm := Timer.new()
	tm.wait_time = 1.0
	tm.autostart = true
	tm.timeout.connect(_auc_tick)
	pg.add_child(tm)
	return pg


func _auc_set_filter(i: int) -> void:
	auc_filter = i
	_refresh_auction()


func _auc_set_sub(s: String) -> void:
	auc_sub = s
	_refresh_auction()


func _auc_pick(lot_id: int, item: String) -> void:
	if lot_id != auc_sel:
		auc_bid_txt = ""
	auc_sel = lot_id
	auc_sel_item = item
	_refresh_auction()


func _auc_tick() -> void:
	if auc_end_lbl == null or not is_visible_in_tree():
		return
	var A = _auc()
	if A == null or not Net.online or not A.has_state:
		auc_end_lbl.text = "Sunucuya bağlı değil"
		return
	var r: int = A.remaining()
	auc_end_lbl.text = "Açık artırma bitişine: %02d:%02d" % [floori(r / 60.0), r % 60]


func _auc_cell(text: String, w: int, col := ICE_WHITE, right := false) -> Label:
	var l := _mk(text, 12, col)
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if w <= 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(70, 0)
	else:
		l.custom_minimum_size = Vector2(w, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _auc_row(item: String, cells: Array, idx: int, selected: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_NONE
	var bg := Color(0.0, 0.0, 0.0, 0.92) if idx % 2 == 0 else Color(0.05, 0.10, 0.15, 0.95)
	var bd := GOLD if selected else Color(0, 0, 0, 0)
	var bwid: int = 2 if selected else 0
	b.add_theme_stylebox_override("normal", _sb(bg, bd, bwid, 0, Vector4(4, 2, 4, 2)))
	b.add_theme_stylebox_override("hover", _sb(Color(0.08, 0.16, 0.26, 1.0), bd if selected else NEON_BLUE, 1, 0, Vector4(4, 2, 4, 2)))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.10, 0.20, 0.32, 1.0), GOLD, 2, 0, Vector4(4, 2, 4, 2)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	var ic := _icon(game.item_icon(item), 34)
	h.add_child(ic)
	for i in range(cells.size()):
		var c: Array = cells[i]
		h.add_child(_auc_cell(str(c[0]), int(AUC_W[i]), c[1], i >= 3))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _auc_fmt_time(t: int) -> String:
	var tz: Dictionary = Time.get_time_zone_from_system()
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(t + int(tz.get("bias", 0)) * 60)
	return "%02d.%02d %02d:%02d" % [int(dt.day), int(dt.month), int(dt.hour), int(dt.minute)]


func _auc_head_cells(titles: Array) -> void:
	auc_head.add_child(_auc_cell("", 34, DIM))
	for i in range(titles.size()):
		auc_head.add_child(_auc_cell(str(titles[i]), int(AUC_W[i]), Color(0.55, 0.75, 0.95), i >= 3))


func _auc_note(text: String) -> void:
	var l := _wrap(text, 13, DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 40)
	m.add_child(l)
	auc_list.add_child(m)


func _refresh_auction() -> void:
	if auc_list == null or game == null or game.SV.is_empty():
		return
	_auc_hook()
	var A = _auc()
	for k in auc_sub_btns.keys():
		(auc_sub_btns[k] as Button).set_pressed_no_signal(str(k) == auc_sub)
	_clear(auc_head)
	_clear(auc_list)
	var live: bool = A != null and Net.online and A.has_state
	var is_lots: bool = auc_sub == "lots" or auc_sub == "mine"
	if is_lots:
		_auc_head_cells(["Eşya Adı", "Tür", "En Yüksek Teklif", "Güncel Teklif", "Teklifin", "Hemen Al (U)"])
	else:
		_auc_head_cells(["Eşya Adı", "Tür", "Kazanan", "Fiyat", "Zaman", "Sonuç"])
	auc_bal.text = "Kredi: %s   •   Uridium: %s" % [game._n(float(game.SV.cr)), game._n(float(game.SV.uri))]
	_auc_tick()
	if not live:
		_auc_note("Açık artırma yalnızca çok oyunculu sunucuya bağlıyken çalışır.\nMenüden \"Çok oyunculu\" ile bağlan.")
		_auc_side_build(null, {})
		return
	var sel_lot: Dictionary = {}
	if is_lots:
		var idx := 0
		for lot in A.lots:
			if auc_filter > 0 and str(lot["type"]) != str(AUC_FILTERS[auc_filter]):
				continue
			if auc_sub == "mine" and int(lot["my_top"]) <= 0:
				continue
			var lid: int = int(lot["id"])
			if lid == auc_sel:
				sel_lot = lot
			var open: bool = str(lot["state"]) == "open"
			var bidder_txt: String = str(lot["bidder"]) if str(lot["bidder"]) != "" else "-"
			var bcol: Color = GREEN if bool(lot["mine"]) else ICE_WHITE
			if int(lot["my_top"]) > 0 and not bool(lot["mine"]):
				bcol = RED       # teklifin geçildi
			var cells: Array = [
				[str(lot["name"]), ICE_WHITE], [str(lot["type"]), TEXT2], [bidder_txt, bcol],
				[game._n(float(lot["bid"])), GOLD if int(lot["bid"]) > 0 else DIM],
				[game._n(float(lot["my_top"])) if int(lot["my_top"]) > 0 else "0", ICE_WHITE if int(lot["my_top"]) > 0 else DIM],
				[game._n(float(lot["instant"])) if open else "-", ICE_WHITE]]
			auc_list.add_child(_auc_row(str(lot["item"]), cells, idx, lid == auc_sel, _auc_pick.bind(lid, str(lot["item"]))))
			idx += 1
		if idx == 0:
			_auc_note("Gösterilecek açık artırma yok." if auc_sub == "lots" else "Bu turda henüz teklif vermedin.")
	else:
		var idx2 := 0
		for e in A.hist:
			if auc_sub == "won" and not bool(e["mine"]):
				continue
			if auc_filter > 0 and str(e["type"]) != str(AUC_FILTERS[auc_filter]):
				continue
			var kind: String = str(e["kind"])
			var price_txt := "-"
			if kind == "won":
				price_txt = "%s Kr" % game._n(float(e["p"]))
			elif kind == "instant":
				price_txt = "%s U" % game._n(float(e["pu"]))
			var res_txt: String = "Açık Art." if kind == "won" else ("Hemen Al" if kind == "instant" else "Satılmadı")
			var wcol: Color = GREEN if bool(e["mine"]) else ICE_WHITE
			var cells2: Array = [
				[str(e["name"]), ICE_WHITE], [str(e["type"]), TEXT2],
				[str(e["w"]) if str(e["w"]) != "" else "-", wcol], [price_txt, GOLD],
				[_auc_fmt_time(int(e["t"])), DIM], [res_txt, DIM]]
			auc_list.add_child(_auc_row(str(e["item"]), cells2, idx2, false, Callable()))
			idx2 += 1
		if idx2 == 0:
			_auc_note("Henüz kazandığın açık artırma yok." if auc_sub == "won" else "Geçmişte tamamlanan açık artırma yok.")
	_auc_side_build(A, sel_lot)


func _auc_side_build(A, lot: Dictionary) -> void:
	_clear(auc_side)
	var box := _panel("PanelInset")
	box.custom_minimum_size = Vector2(0, 92)
	var pv := CenterContainer.new()
	box.add_child(pv)
	if not lot.is_empty():
		pv.add_child(_icon(game.item_icon(str(lot["item"])), 80))
	auc_side.add_child(box)
	if lot.is_empty():
		auc_side.add_child(_wrap("Teklif vermek için listeden bir eşya seç.", 12, DIM))
		return
	auc_side.add_child(_mk(str(lot["name"]), 14, GOLD, true))
	auc_side.add_child(_mk(str(lot["type"]), 11, TEXT2))
	var open: bool = str(lot["state"]) == "open"
	var minb: int = A.min_bid(lot)
	auc_side.add_child(_mk("Min. teklif: %s Kr" % game._n(float(minb)), 11, DIM))
	if auc_bid_txt == "":
		auc_bid_txt = str(minb)
	var ed := LineEdit.new()
	ed.text = auc_bid_txt
	ed.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ed.placeholder_text = "Kredi"
	ed.editable = open
	ed.text_changed.connect(func(t: String) -> void: auc_bid_txt = t)
	auc_side.add_child(ed)
	auc_bid_edit = ed
	var can: bool = open and not bool(game.SV.get("free", false))
	auc_side.add_child(_btn("TEKLİF VER", "ButtonPrimary", _auc_do_bid, Vector2(0, 32), can, 12))
	var sep := _line()
	auc_side.add_child(sep)
	auc_side.add_child(_mk("Hemen Al: %s U" % game._n(float(lot["instant"])), 12, ICE_WHITE))
	auc_side.add_child(_btn("HEMEN AL", "ButtonGold", _auc_do_buy, Vector2(0, 32), can, 12))
	auc_side.add_child(_mk("TEKLİF GEÇMİŞİ", 10, Color(0.45, 0.58, 0.72)))
	var bids: Array = lot["bids"]
	if bids.is_empty():
		auc_side.add_child(_mk("Henüz teklif yok.", 11, DIM))
	for i in range(bids.size() - 1, maxi(-1, bids.size() - 6), -1):
		var b: Dictionary = bids[i]
		auc_side.add_child(_mk("%s  %s" % [str(b["n"]), game._n(float(b["a"]))], 11, TEXT2))


func _auc_do_bid() -> void:
	var A = _auc()
	if A == null or auc_sel <= 0:
		return
	var amount: int = int(auc_bid_txt.replace(".", "").replace(",", "").replace(" ", "").to_int())
	A.bid(auc_sel, amount)
	refresh()


func _auc_do_buy() -> void:
	var A = _auc()
	if A == null or auc_sel <= 0:
		return
	A.buy_now(auc_sel)
	refresh()


# ============================================================================
#  AYARLAR
# ============================================================================
func _build_settings() -> Control:
	var r := _make_scroll_page(8)
	set_body = r[1]
	return r[0]


func _toggle_row(parent: Node, title: String, desc: String, value: bool, cb: Callable) -> void:
	var row := _row_panel(parent)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.add_child(_mk(title, 14, ICE_WHITE))
	if desc != "":
		v.add_child(_wrap(desc, 11, DIM))
	row.add_child(v)
	var cb_btn := CheckButton.new()
	cb_btn.set_pressed_no_signal(value)
	cb_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb_btn.toggled.connect(cb)
	row.add_child(cb_btn)


func _refresh_settings() -> void:
	_clear(set_body)
	_page_head(set_body, "AYARLAR", "Değişiklikler anında uygulanır ve yerel kayda yazılır.")

	set_body.add_child(_mk("GÖRÜNTÜ", 13, GOLD))
	_toggle_row(set_body, "Tam ekran", "", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, _set_fullscreen)
	_toggle_row(set_body, "Keskin yıldız katmanı", "Arka plandaki yıldız alanı.", bool(game.stars_on), _set_stars)
	_toggle_row(set_body, "Kontrol yazısını göster  [H]", "", bool(game.lbl_help.visible), _set_help)

	var gr := _row_panel(set_body)
	var gv := VBoxContainer.new()
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.add_theme_constant_override("separation", 0)
	gv.add_child(_mk("Grafik kalitesi", 14, ICE_WHITE))
	gv.add_child(_mk("3B kenar yumuşatma", 11, DIM))
	gr.add_child(gv)
	var graphics := OptionButton.new()
	graphics.add_item("Düşük — kapalı", 0)
	graphics.add_item("Orta — 2× MSAA", 1)
	graphics.add_item("Yüksek — 4× MSAA", 2)
	graphics.select(int(game.SV.settings.graphics))
	graphics.item_selected.connect(_set_graphics)
	graphics.custom_minimum_size = Vector2(220, 34)
	graphics.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gr.add_child(graphics)

	var zr := _row_panel(set_body)
	var zv := VBoxContainer.new()
	zv.add_theme_constant_override("separation", 0)
	zv.add_child(_mk("Kamera uzaklığı", 14, ICE_WHITE))
	zv.add_child(_mk("Yakınlaştır / uzaklaştır", 11, DIM))
	zr.add_child(zv)
	var sl := HSlider.new()
	sl.min_value = 0.4
	sl.max_value = 2.5
	sl.step = 0.05
	sl.value = game.zoom
	sl.custom_minimum_size = Vector2(240, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(_set_zoom)
	zr.add_child(sl)

	set_body.add_child(_mk("OYNANIŞ", 13, GOLD))

	set_body.add_child(_wrap("Ses ayarları yok: bu projede ses/AudioBus kaynağı bulunmuyor.   •   Masaüstü: fare + klavye   •   Dokunmatik: ekrana dokunarak hareket/hedef seçimi", 11, DIM))

	set_body.add_child(_mk("KAYIT", 13, GOLD))
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 8)
	set_body.add_child(br)
	br.add_child(_btn("OYUNU KAYDET", "ButtonPrimary", _save_now, Vector2(200, 40), true, 13))
	br.add_child(_btn("KAYDET VE ÇIK", "ButtonDanger", game._quit_game, Vector2(200, 40), true, 13))


func _set_fullscreen(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_store_setting("fullscreen", on)


func _set_stars(on: bool) -> void:
	game.stars_on = on
	_store_setting("stars", on)


func _set_help(on: bool) -> void:
	game.lbl_help.visible = on
	_store_setting("help", on)


func _set_zoom(v: float) -> void:
	game.zoom = v
	_store_setting("zoom", v)


func _set_graphics(index: int) -> void:
	var modes := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	game.get_viewport().msaa_3d = modes[clampi(index, 0, modes.size() - 1)]
	_store_setting("graphics", index)


func _store_setting(key: String, value) -> void:
	var prefs: Dictionary = game.SV.get("settings", {})
	prefs[key] = value
	game.SV.settings = prefs
	game.save_game()


func _save_now() -> void:
	game.save_game()
	game.toast("Oyun kaydedildi.")


# ============================================================================
#  YARDIM
# ============================================================================
func _build_help() -> Control:
	var r := _make_scroll_page(8)
	var body: VBoxContainer = r[1]
	_page_head(body, "YARDIM", "Kontroller ve oyun notları")

	var card := _panel("PanelCard")
	body.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(_mk("KONTROLLER", 13, GOLD))
	v.add_child(_line())
	for e in HELP_KEYS:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var kc := _panel("PanelInset")
		kc.custom_minimum_size = Vector2(200, 0)
		kc.add_child(_wrap(str(e[0]), 12, NEON_ORANGE))
		h.add_child(kc)
		var d := _wrap(str(e[1]), 13, ICE_WHITE)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(d)

	for n in HELP_NOTES:
		var nc := _panel("PanelCard")
		body.add_child(nc)
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 6)
		nc.add_child(nv)
		nv.add_child(_mk(str(n[0]), 13, GOLD))
		nv.add_child(_line())
		nv.add_child(_wrap(str(n[1]), 13, TEXT2))
	return r[0]


func _on_equip_subtab(st: String) -> void:
	equip_subtab = st
	_refresh_equip()


func _on_unequip_all() -> void:
	game._on_unequip_all_drones()
	selected_drone_slot = ""
	var guard := 0
	for key in ["las", "gen", "drn"]:
		while game.cfg()[key].size() > 0 and guard < 600:
			game.unequip_slot(key, 0)
			guard += 1
	refresh()


# ============================================================================
#  HANGAR EKRANLARI  -  Hangarlar / Cephane / Gemi / Droidler (oyun içi düzen)
# ============================================================================
const TAB_RED := Color(0.90, 0.14, 0.14)
const AMMO_BAR_COLS := [
	Color(0.80, 0.10, 0.12), Color(0.14, 0.72, 0.20), Color(0.08, 0.58, 0.95),
	Color(0.82, 0.88, 0.97), Color(0.08, 0.48, 0.60), Color(0.95, 0.50, 0.08),
]
const ROCKET_BAR_COL := Color(0.08, 0.46, 0.56)
const MOD_COL_LASER_LO := Color(0.78, 0.14, 0.14)
const MOD_COL_LASER_HI := Color(0.90, 0.62, 0.10)
const MOD_COL_GEN := Color(0.14, 0.38, 0.80)
const MOD_COL_DRN := Color(0.20, 0.62, 0.26)
const ROMAN := ["I", "II", "III", "IV", "V"]
const LONG_PRESS_SEC := 0.55
const SLOT_SZ := 38

var equip_cfg_box: HBoxContainer
var equip_cfg_btns := {}
var hangar_sort := 0          # 0 = türe göre, 1 = nadirliğe göre (Düzenlemek)
var ext_open := true
var form_open := true
var ctx_meta := {}

var context_menu: PopupMenu


func _show_context_menu_for_item(item_id: String, is_equipped: bool, slot_key: String = "", slot_index: int = -1) -> void:
	if context_menu == null:
		context_menu = PopupMenu.new()
		add_child(context_menu)
		context_menu.id_pressed.connect(_on_context_menu_action)
	ctx_meta = {"item_id": item_id, "key": slot_key, "index": slot_index}
	context_menu.clear()
	context_menu.add_item("İncele", 0)
	if is_equipped:
		context_menu.add_item("Çıkar", 1)
	else:
		context_menu.add_item("Tak", 2)
		context_menu.add_item("Sat", 3)
	context_menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _on_context_menu_action(id: int) -> void:
	var item_id := str(ctx_meta.get("item_id", ""))
	if item_id == "":
		return
	match id:
		0:
			game.toast(_item_tip(item_id, ""))
		1:
			_unequip_any(str(ctx_meta.get("key", "")), int(ctx_meta.get("index", -1)))
		2:
			if str(ctx_meta.get("key", "")) == "drone_inv":
				_equip_to_drone(item_id)
			else:
				game.equip_item(item_id)
				refresh()
		3:
			game.sell_item(item_id)
			refresh()


# ---- Üst sekme çubuğu -------------------------------------------------------
func _style_tab(b: Button, active: bool) -> void:
	var clear := Color(0, 0, 0, 0)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var s := _sb(clear, clear, 0, 0, Vector4(10, 4, 10, 4))
		s.border_width_bottom = 2
		if active or st == "pressed" or st == "hover_pressed":
			s.border_color = TAB_RED
		elif st == "hover":
			s.border_color = NEON_BLUE
		b.add_theme_stylebox_override(st, s)
	var fc := ICE_WHITE if active else TEXT2
	for k in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fc)
	b.add_theme_color_override("font_hover_color", ICE_WHITE)


func _tab_btn(text: String, active: bool, cb: Callable, w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 30)
	b.add_theme_font_override("font", head_font)
	b.add_theme_font_size_override("font_size", 12)
	_style_tab(b, active)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _set_config(i: int) -> void:
	game.switch_cfg(i)
	refresh()


# ---- Ortak çizim yardımcıları -----------------------------------------------
# Başlıklı çerçeve: [PanelContainer, içerik VBox]
func _sec_frame(title: String) -> Array:
	var pc := _panel("PanelInset")
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	v.add_child(_mk(title, 12, ICE_WHITE))
	v.add_child(_line())
	return [pc, v]


func _slot_grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	return g


func _corner_tag(b: Control, text: String, right: bool, fs := 10) -> void:
	var l := _mk(text, fs, ICE_WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 3)
	var ax := 1.0 if right else 0.0
	l.anchor_left = ax
	l.anchor_right = ax
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -4.0 if right else 4.0
	l.offset_right = l.offset_left
	l.offset_top = -2.0
	l.offset_bottom = -2.0
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	b.add_child(l)


func _mod_color(id: String) -> Color:
	match str(game.item_key(id)):
		"las":
			return MOD_COL_LASER_HI if _rarity(id) >= 3 else MOD_COL_LASER_LO
		"gen":
			return MOD_COL_GEN
		"drn":
			return MOD_COL_DRN
	return RARITY_COLS[_rarity(id)]


# Modül slotu: renkli kare. Tık = tak/çıkar, sağ tık veya uzun basış = menü.
func _mod_slot(id: String, on_click: Callable, sz := SLOT_SZ, badge := "", tip := "", is_equipped := false, slot_key := "", slot_index := -1) -> Button:
	var b := Button.new()
	b.theme_type_variation = "SlotButton"
	b.custom_minimum_size = Vector2(sz, sz)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	if id == "":
		if on_click.is_valid():
			b.pressed.connect(on_click)
		return b

	var col := _mod_color(id)
	b.icon = game.item_icon(id)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var hi: bool = (st == "hover" or st == "hover_pressed")
		var k := 0.30 if hi else 0.20
		var bg := Color(col.r * k, col.g * k, col.b * k, 0.97)
		b.add_theme_stylebox_override(st, _sb(bg, col.lightened(0.3) if hi else col, 2, 3, Vector4(3, 3, 3, 3)))
	if str(game.item_key(id)) == "las":
		_corner_tag(b, ROMAN[_rarity(id)], false, 9)
	if badge != "":
		_corner_tag(b, badge, true, 10)

	b.pressed.connect(_mod_pressed.bind(b, on_click))
	b.button_down.connect(_mod_down.bind(b, id, is_equipped, slot_key, slot_index))
	b.button_up.connect(_mod_up.bind(b))
	b.gui_input.connect(_mod_input.bind(id, is_equipped, slot_key, slot_index))
	return b


func _mod_pressed(b: Button, cb: Callable) -> void:
	if bool(b.get_meta("lp_fired", false)):
		b.set_meta("lp_fired", false)
		return
	if cb.is_valid():
		cb.call()


func _mod_down(b: Button, id: String, is_eq: bool, key: String, idx: int) -> void:
	var tok := Time.get_ticks_msec()
	b.set_meta("lp", tok)
	b.set_meta("lp_fired", false)
	await get_tree().create_timer(LONG_PRESS_SEC).timeout
	if is_instance_valid(b) and int(b.get_meta("lp", 0)) == tok:
		b.set_meta("lp", 0)
		b.set_meta("lp_fired", true)
		_show_context_menu_for_item(id, is_eq, key, idx)


func _mod_up(b: Button) -> void:
	b.set_meta("lp", 0)


func _mod_input(event: InputEvent, id: String, is_eq: bool, key: String, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu_for_item(id, is_eq, key, idx)


func _unequip_any(key: String, idx: int) -> void:
	if key.begins_with("drone_"):
		game._on_drone_slot_unequip(key.substr(6), idx)
	else:
		game.unequip_slot(key, idx)
	refresh()


func _drone_used(id: String) -> int:
	var n := 0
	var c: Dictionary = game.cfg()
	var de: Dictionary = c.get("drone_equip", {})
	for did in de:
		for sk in (de[did] as Dictionary):
			if str(de[did][sk]) == id:
				n += 1
	return n


func _free_n(c: Dictionary, key: String, id: String, _to_drone: bool) -> int:
	# Gemi ve droid ekipmani ayni envanterden dusulur (oyun tarafindaki tek kaynak).
	return int(game._free_count(c, key, id))


# Boşta eşyalar; tür sırası veya nadirlik sırası
func _hangar_items(kinds: Array, c: Dictionary, to_drone := false) -> Array:
	var groups := {"las": DOData.LASER_ORDER, "gen": DOData.GEN_ORDER, "drn": DOData.DRONE_ORDER}
	var ids: Array = []
	for k in kinds:
		var order: Array = (groups[k] as Array).duplicate()
		order.reverse()
		for id in order:
			var sid := str(id)
			if game.inv_count(sid) <= 0:
				continue
			if _free_n(c, str(k), sid, to_drone) <= 0:
				continue
			# Droidlere yalnizca lazer ve kalkan jeneratoru takilir (hiz jeneratoru takilmaz)
			if to_drone and not game.drone_accepts(sid):
				continue
			ids.append(sid)
	if hangar_sort == 1:
		ids.sort_custom(func(a, b): return _rarity(str(a)) > _rarity(str(b)))
	return ids


func _collapse_head(text: String, open: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = ("▼  " if open else "▶  ") + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 28)
	b.add_theme_font_size_override("font_size", 12)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var bg := Color(0.05, 0.14, 0.20, 0.95) if st == "normal" else Color(0.08, 0.20, 0.28, 1.0)
		b.add_theme_stylebox_override(st, _sb(bg, Color(0.12, 0.30, 0.40, 0.8), 1, 3, Vector4(8, 3, 8, 3)))
	b.pressed.connect(cb)
	return b


func _toggle_ext() -> void:
	ext_open = not ext_open
	_refresh_equip()


func _toggle_form() -> void:
	form_open = not form_open
	_refresh_equip()


# Hangar paneli: kaydırmalı modül ızgarası + iki toplu işlem butonu
func _hangar_panel(parent: Control, c: Dictionary, kinds: Array, to_drone: bool, rm_cb: Callable, eq_cb: Callable) -> void:
	var fr := _sec_frame("Hangar")
	parent.add_child(fr[0])
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 4 * (SLOT_SZ + 4) + 2)
	fr[1].add_child(sc)
	var g := _slot_grid(6)
	sc.add_child(g)
	var ids := _hangar_items(kinds, c, to_drone)
	var hint := "Droid slotuna takmak için tıkla / Sağ tık: menü" if to_drone else "Takmak için tıkla / Sağ tık: menü"
	for sid in ids:
		var key: String = str(game.item_key(sid))
		var nfree: int = _free_n(c, key, sid, to_drone)
		var cb: Callable = _equip_to_drone.bind(sid) if to_drone else _on_equip.bind(sid)
		g.add_child(_mod_slot(sid, cb, SLOT_SZ, "x%d" % nfree if nfree > 1 else "", _item_tip(sid, hint), false, "drone_inv" if to_drone else "", -1))
	for i in maxi(0, 24 - ids.size()):
		g.add_child(_mod_slot("", Callable(), SLOT_SZ))
	if ids.is_empty():
		fr[1].add_child(_wrap("Boşta modül yok. Market sekmesinden satın alabilirsin.", 11, DIM))
	var bb := HBoxContainer.new()
	bb.add_theme_constant_override("separation", 6)
	fr[1].add_child(bb)
	var b1 := _btn("Tüm modülleri kaldır", "ButtonSmall", rm_cb, Vector2(0, 34), true, 11)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.add_child(b1)
	var b2 := _btn("Tüm modülleri donatın", "ButtonSmall", eq_cb, Vector2(0, 34), true, 11)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.add_child(b2)


func _equip_bottom_bar(hint_text: String) -> void:
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	equip_content.add_child(bottom)
	var hint := _wrap(game.stats_text() + "\n" + hint_text, 11, DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)
	bottom.add_child(_btn("Tüm ekipmanı kaldır", "ButtonSmall", _on_unequip_all, Vector2(170, 32), true, 11))
	bottom.add_child(_btn("Düzenlemek", "ButtonSmall", _on_arrange, Vector2(130, 32), true, 11))


func _on_arrange() -> void:
	hangar_sort = (hangar_sort + 1) % 2
	game.toast("Hangar sıralaması: " + ("Nadirliğe göre" if hangar_sort == 1 else "Türe göre"))
	_refresh_equip()


# ---- Toplu işlemler ----------------------------------------------------------
func _on_unequip_mods() -> void:
	var guard := 0
	while game.cfg().las.size() > 0 and guard < 200:
		game.unequip_slot("las", 0)
		guard += 1
	while game.cfg().gen.size() > 0 and guard < 400:
		game.unequip_slot("gen", 0)
		guard += 1
	refresh()


func _on_unequip_droids_ship() -> void:
	if game.has_method("_on_unequip_all_drones"):
		game._on_unequip_all_drones()
	var guard := 0
	while game.cfg().drn.size() > 0 and guard < 200:
		game.unequip_slot("drn", 0)
		guard += 1
	refresh()


func _on_droid_modules_off() -> void:
	game._on_unequip_all_drones()
	selected_drone_slot = ""
	refresh()


func _on_droid_auto() -> void:
	game._on_auto_equip_drones()
	refresh()


# ---- Droid slot seçimi / takma ----------------------------------------------
func _select_drone_slot(sel_id: String) -> void:
	selected_drone_slot = "" if selected_drone_slot == sel_id else sel_id
	_refresh_equip()


func _drone_slot_empty(sel_id: String) -> bool:
	var parts: Array = sel_id.split(":")
	if parts.size() < 2:
		return false
	var c: Dictionary = game.cfg()
	var de: Dictionary = c.get("drone_equip", {})
	var drone_uid: String = parts[0]
	var slot_key := "slot_" + str(parts[1])
	return not (de.has(drone_uid) and (de[drone_uid] as Dictionary).has(slot_key))


func _first_empty_drone_slot() -> String:
	var c: Dictionary = game.cfg()
	for i in range(c.drn.size()):
		var drone_id := str(c.drn[i])
		# Benzersiz ID kullan
		var drone_uid := "%s_%d" % [drone_id, i]
		var slot_cap := int(DOData.DRONES[drone_id].get("slots", 1))
		for s in slot_cap:
			var sel_id := "%s:%d" % [drone_uid, s]
			if _drone_slot_empty(sel_id):
				return sel_id
	return ""


func _equip_to_drone(item_id: String) -> void:
	var target := selected_drone_slot
	if target == "" or not _drone_slot_empty(target):
		target = _first_empty_drone_slot()
	if target == "":
		game.toast("Boş droid slotu yok!")
		return
	var parts: Array = target.split(":")
	game.equip_drone_item(str(parts[0]), int(parts[1]), item_id)
	selected_drone_slot = ""
	refresh()


# ---- Kart düğmeleri (Hangarlar / Cephane) -----------------------------------
func _card_btn(sz: Vector2, selected: bool, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "ShipCardSel" if selected else "ShipCard"
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _card_body(b: Button, tex: Texture2D, title: String, status: String, status_col: Color, icon_sz := 36, fs := 10) -> void:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 3.0
	v.offset_top = 3.0
	v.offset_right = -3.0
	v.offset_bottom = -3.0
	if tex != null:
		v.add_child(_icon(tex, icon_sz))
	var t := _mk(title, fs, ICE_WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.clip_text = true
	v.add_child(t)
	var sp := PanelContainer.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_theme_stylebox_override("panel", _sb(status_col, Color(0, 0, 0, 0), 0, 2, Vector4(2, 1, 2, 1)))
	v.add_child(sp)
	var sl := _mk(status, fs - 1, Color(0.05, 0.08, 0.12) if status_col.get_luminance() > 0.6 else ICE_WHITE)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.clip_text = true
	sp.add_child(sl)


# ============================================================================
#  1) HANGARLAR  -  sahip olunan gemiler + yeni hangar (+)
# ============================================================================
func _refresh_equip_tab_hangarlar() -> void:
	var fr := _sec_frame("Hangarlar")
	equip_content.add_child(fr[0])
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	fr[1].add_child(g)
	for s in DOData.SHIPS:
		if not (s.id in game.SV.owned):
			continue
		var active: bool = (str(s.id) == str(game.SV.ship))
		var tip := "%s\nCan %s   Hız %d\nLazer %d   Jeneratör %d   Droid %d" % [str(s.name), game._n(s.hp), s.spd, s.las, s.gen, DOData.drone_slots(s)]
		tip += "\n" + ("Kullanımda" if active else "Kullanmak için tıkla")
		var b := _card_btn(Vector2(80, 80), active, tip, Callable() if active else _shop_use_ship.bind(str(s.id)))
		_card_body(b, _ship_tex(str(s.id)), str(s.name), "Aktif" if active else "Hangar", Color(0.12, 0.62, 0.30) if active else Color(0.08, 0.40, 0.50))
		g.add_child(b)
	var plus := _card_btn(Vector2(80, 80), false, "Yeni gemi satın almak için Market'i aç", _open_ship_shop)
	var pv := VBoxContainer.new()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_theme_constant_override("separation", 2)
	plus.add_child(pv)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pv.offset_left = 3.0
	pv.offset_top = 3.0
	pv.offset_right = -3.0
	pv.offset_bottom = -3.0
	var circ := PanelContainer.new()
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circ.custom_minimum_size = Vector2(36, 36)
	circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circ.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), Color(0.2, 0.7, 0.85), 2, 18, Vector4(0, 0, 0, 0)))
	var pl := _mk("+", 24, Color(0.3, 0.85, 1.0))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circ.add_child(pl)
	pv.add_child(circ)
	var pt := _mk("Hangar", 10, ICE_WHITE)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	var ps := PanelContainer.new()
	ps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ps.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.40, 0.50), Color(0, 0, 0, 0), 0, 2, Vector4(2, 1, 2, 1)))
	var psl := _mk("Satın Al", 9, ICE_WHITE)
	psl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ps.add_child(psl)
	pv.add_child(ps)
	g.add_child(plus)


func _open_ship_shop() -> void:
	shop_cat = "ships"
	_switch("shop")


# ============================================================================
#  2) CEPHANE  -  lazer / roket cephanesi (tık = cephane seç)
# ============================================================================
func _ammo_card(tex: Texture2D, title: String, count: int, col: Color, selected: bool, tip: String, cb: Callable) -> Button:
	var b := _card_btn(Vector2(62, 66), selected, tip, cb)
	_card_body(b, tex, title, game._n(count), col, 26, 9)
	return b


func _refresh_equip_tab_cephane() -> void:
	var sel := str(game.SV.get("sel", ""))
	var ammo: Dictionary = game.SV.get("ammo", {})

	var fr := _sec_frame("Lazer Cephanesi")
	equip_content.add_child(fr[0])
	var fl := _flow(4)
	fr[1].add_child(fl)
	var i := 0
	for a in DOData.AMMO:
		var id := str(a.id)
		var have := int(ammo.get(id, 0))
		var tip := "%s\nStok: %s\nHasar çarpanı: %sx\nSeçmek için tıkla" % [str(a.name), game._n(have), str(a.mult)]
		fl.add_child(_ammo_card(game._tex("res://assets/ui/ammo_%s.png" % id), str(a.name), have, (a.col as Color).darkened(0.35), sel == id, tip, _pick_ammo.bind(id)))
		i += 1

	var fr2 := _sec_frame("Roket Cephanesi")
	equip_content.add_child(fr2[0])
	var fl2 := _flow(4)
	fr2[1].add_child(fl2)
	var rk := int(game.SV.get("rockets", 0))
	fl2.add_child(_ammo_card(game._tex("res://assets/ui/rocket.png"), "Roket", rk, ROCKET_BAR_COL, false, "Roket\nStok: %s\nR tuşu ile hedefe fırlatılır" % game._n(rk), Callable()))


# ============================================================================
#  3) GEMİ  -  Lazer / Jeneratörler  +  Hangar   (droidler DROİDLER sekmesinde takılır)
# ============================================================================
func _ship_slots_section(parent: Node, key: String, title: String, c: Dictionary, cols: int) -> void:
	var fr := _sec_frame(title)
	parent.add_child(fr[0])
	var cap: int = int(game.cap_of(key))
	var items: Array = c[key]
	if cap <= 0:
		fr[1].add_child(_wrap("Bu geminin bu türde yuvası yok.", 11, DIM))
		return
	var g := _slot_grid(cols)
	fr[1].add_child(g)
	for i in cap:
		if i < items.size():
			var sid := str(items[i])
			g.add_child(_mod_slot(sid, _unequip_any.bind(key, i), SLOT_SZ, "", _item_tip(sid, "Çıkarmak için tıkla / Sağ tık: menü"), true, key, i))
		else:
			g.add_child(_mod_slot("", Callable(), SLOT_SZ, "", "Boş slot"))


func _refresh_equip_tab_gemi() -> void:
	var c: Dictionary = game.cfg()
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_content.add_child(split)

	# ---- sol: takılı ekipman
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	split.add_child(left)
	_ship_slots_section(left, "las", "Lazer", c, 8)
	_ship_slots_section(left, "gen", "Jeneratörler", c, 8)

	# ---- sağ: hangar
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	split.add_child(right)
	_hangar_panel(right, c, ["las", "gen"], false, _on_unequip_mods, _on_auto)


	_equip_bottom_bar("Eşyaya tıklayarak gemiye takabilir/çıkartabilirsiniz. Ek seçenekleri görmek için uzun tıklayın/sağ tıklayın")


# ============================================================================
#  4) DROİDLER  -  droid slotları + Hangar + Formasyonlar
# ============================================================================
func _form_slot(code: String, active: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = "SlotButton"
	b.custom_minimum_size = Vector2(SLOT_SZ, SLOT_SZ)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.icon = _form_tex(code)
	var f: Dictionary = DOData.FORMS[code]
	b.tooltip_text = "%s\nHasar %+d%%   Kalkan %+d%%   Hız %+d%%\n%s" % [str(f.name), int(float(f.dmg) * 100.0), int(float(f.sh) * 100.0), int(float(f.spd) * 100.0), "Aktif" if active else "Seçmek için tıkla"]
	if active:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _sb(Color(0.04, 0.16, 0.09, 0.97), GREEN, 2, 3, Vector4(3, 3, 3, 3)))
	b.pressed.connect(_on_form.bind(code))
	return b


func _refresh_equip_tab_droidler() -> void:
	var c: Dictionary = game.cfg()
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_content.add_child(split)

	# ---- sol: gemideki droidler ve slotları
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	split.add_child(left)
	var fr := _sec_frame("Droidler")
	left.add_child(fr[0])
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 330)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr[1].add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)

	var cur_drn: Array = c.drn
	if cur_drn.is_empty():
		grid.add_child(_wrap("Gemide droid yok. Sağdaki Droidler listesinden droide tıklayarak gemiye tak.", 11, DIM))
	var drone_equip: Dictionary = c.get("drone_equip", {})
	for i in range(cur_drn.size()):
		var drone_id := str(cur_drn[i])
		var dd: Dictionary = DOData.DRONES[drone_id]
		var slot_cap := int(dd.get("slots", 1))
		# Benzersiz droid ID: "drone_type_index" (örn: "Iris_0", "Iris_1")
		var drone_uid := "%s_%d" % [drone_id, i]
		var cell := _panel("PanelInset")
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		cell.add_child(v)
		v.add_child(_mk(str(dd.name), 11, NEON_ORANGE))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		v.add_child(h)
		h.add_child(_mod_slot(drone_id, _unequip_any.bind("drn", i), 34, "", _item_tip(drone_id, "Gemiden çıkarmak için tıkla / Sağ tık: menü"), true, "drn", i))
		var fl := _flow(4)
		h.add_child(fl)
		for s in slot_cap:
			var slot_key := "slot_" + str(s)
			# sel_id artık unique ID kullanıyor: "drone_uid:slot_index"
			var sel_id := "%s:%d" % [drone_uid, s]
			if drone_equip.has(drone_uid) and (drone_equip[drone_uid] as Dictionary).has(slot_key):
				var item_id := str(drone_equip[drone_uid][slot_key])
				fl.add_child(_mod_slot(item_id, _unequip_any.bind("drone_" + drone_uid, s), 34, "", _item_tip(item_id, "Çıkarmak için tıkla / Sağ tık: menü"), true, "drone_" + drone_uid, s))
			else:
				var eb := _mod_slot("", _select_drone_slot.bind(sel_id), 34, "", "Boş droid slotu - hedef seçmek için tıkla")
				if selected_drone_slot == sel_id:
					for st in ["normal", "hover", "pressed", "hover_pressed"]:
						eb.add_theme_stylebox_override(st, _sb(Color(0.04, 0.16, 0.09, 0.97), GREEN, 2, 3, Vector4(3, 3, 3, 3)))
				fl.add_child(eb)

	# ---- sağ: hangar + formasyonlar
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	split.add_child(right)
	# Droidler gemiye DOGRUDAN takilir (uzantilarla ilgisi yok): hangardaki droidlere tikla -> gemiye takilir
	var dcap: int = int(game.cap_of("drn"))
	right.add_child(_collapse_head("Droidler   %d / %d" % [c.drn.size(), dcap], ext_open, _toggle_ext))
	if ext_open:
		var dg := _slot_grid(6)
		right.add_child(dg)
		var dids := _hangar_items(["drn"], c)
		for sid in dids:
			var dfree: int = int(game._free_count(c, "drn", sid))
			dg.add_child(_mod_slot(sid, _on_equip.bind(sid), SLOT_SZ, "x%d" % dfree if dfree > 1 else "", _item_tip(sid, "Gemiye takmak için tıkla / Sağ tık: menü")))
		for i in maxi(0, 6 - dids.size()):
			dg.add_child(_mod_slot("", Callable(), SLOT_SZ))
		right.add_child(_btn("Tüm droidleri kaldır", "ButtonSmall", _on_unequip_droids_ship, Vector2(0, 34), true, 11))

	_hangar_panel(right, c, ["las", "gen"], true, _on_droid_modules_off, _on_droid_auto)

	right.add_child(_collapse_head("Formasyonlar", form_open, _toggle_form))
	if form_open:
		var fg := _slot_grid(6)
		right.add_child(fg)
		var n := 0
		var cur_form := str(c.get("form", ""))
		for code in DOData.FORM_ORDER:
			if not (code in game.SV.forms):
				continue
			fg.add_child(_form_slot(str(code), cur_form == str(code)))
			n += 1
		for i in maxi(0, 6 - n):
			fg.add_child(_mod_slot("", Callable(), SLOT_SZ))

	_equip_bottom_bar("Eşyaya tıklayarak droide takabilir/çıkartabilirsiniz. Boş slota tıklayarak hedef seçebilirsiniz. Ek seçenekler için uzun tıklayın/sağ tıklayın")


# ============================================================================
#  TEÇHİZAT  -  nadirlik renkli slotlar, özet kartları, filtreli envanter
# ============================================================================
const RARITY_COLS := [
	Color(0.62, 0.70, 0.78),  # Sıradan
	Color(0.35, 0.85, 0.50),  # Gelişmiş
	Color(0.35, 0.65, 1.00),  # Nadir
	Color(0.75, 0.45, 1.00),  # Epik
	Color(1.00, 0.78, 0.25),  # Efsanevi
]
const RARITY_NAMES := ["Sıradan", "Gelişmiş", "Nadir", "Epik", "Efsanevi"]


func _rarity(id: String) -> int:
	var order: Array = DOData.DRONE_ORDER
	if DOData.LASERS.has(id):
		order = DOData.LASER_ORDER
	elif DOData.GENS.has(id):
		order = DOData.GEN_ORDER
	var idx: int = order.find(id)
	var top: int = maxi(order.size() - 1, 1)
	var r := int(round(float(maxi(idx, 0)) / float(top) * 4.0))
	var d: Dictionary = game.item_def(id)
	if int(d.get("uri", 0)) > 0:
		r = 4
	return clampi(r, 0, 4)


func _item_stat_text(id: String) -> String:
	var d: Dictionary = game.item_def(id)
	if DOData.LASERS.has(id):
		return "Hasar: %s / salvo" % game._n(float(d.dmg))
	if DOData.GENS.has(id):
		if str(d.type) == "spd":
			return "Hız bonusu: +%d" % int(d.val)
		return "Kalkan: +%s   Emilim: %%%d" % [game._n(float(d.val)), int(round(float(d.abs) * 100.0))]
	var parts: Array = []
	if float(d.dmg) > 0.0:
		parts.append("Hasar +%%%d" % int(round(float(d.dmg) * 100.0)))
	if float(d.sh) > 0.0:
		parts.append("Kalkan +%%%d" % int(round(float(d.sh) * 100.0)))
	return "   ".join(parts)


func _item_tip(id: String, hint: String) -> String:
	var d: Dictionary = game.item_def(id)
	var t := "%s  [%s]\n%s" % [str(d.name), RARITY_NAMES[_rarity(id)], _item_stat_text(id)]
	if d.has("desc"):
		t += "\n" + str(d.desc)
	return t + "\n" + hint


# Nadirlik renkli çerçeveli eşya slotu. id == "" ise boş slot.
func _gear_slot(id: String, cb: Callable, sz := 58, badge := "", tip := "") -> Button:
	var b := Button.new()
	b.theme_type_variation = "SlotButton"
	b.custom_minimum_size = Vector2(sz, sz)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	if id == "":
		b.icon = game._tex("res://assets/items/hangar_slot.png")
		b.disabled = true
		b.tooltip_text = "Boş slot"
		b.modulate = Color(1, 1, 1, 0.5)
		return b
	var col: Color = RARITY_COLS[_rarity(id)]
	b.icon = game.item_icon(id)
	b.tooltip_text = tip
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var hi: bool = (st == "hover" or st == "hover_pressed")
		var k := 0.26 if hi else 0.14
		var bg := Color(col.r * k, col.g * k, col.b * k, 0.97)
		b.add_theme_stylebox_override(st, _sb(bg, col.lightened(0.35) if hi else col, 2, 5, Vector4(4, 4, 4, 4)))
	if badge != "":
		var l := _mk(badge, 11, ICE_WHITE)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		l.add_theme_constant_override("outline_size", 3)
		l.anchor_left = 1.0
		l.anchor_right = 1.0
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.offset_left = -4
		l.offset_right = -4
		l.offset_top = -2
		l.offset_bottom = -2
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
		b.add_child(l)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _loadout_summary(c: Dictionary) -> Dictionary:
	var dmg := 0.0
	var spd := 0.0
	var sh := 0.0
	var dd := 0.0
	var ds := 0.0
	for id in c.las:
		dmg += float(DOData.LASERS[str(id)].dmg)
	for id in c.gen:
		var g: Dictionary = DOData.GENS[str(id)]
		if str(g.type) == "spd":
			spd += float(g.val)
		else:
			sh += float(g.val)
	for id in c.drn:
		var d: Dictionary = DOData.DRONES[str(id)]
		dd += float(d.dmg)
		ds += float(d.sh)
	return {"dmg": dmg, "spd": spd, "sh": sh, "dd": dd, "ds": ds}


# Bir ekipman türünün başlığı + doluluk çubuğu + slot ızgarası
func _cap_section(parent: Node, key: String, title: String, col: Color, c: Dictionary) -> void:
	var cap: int = game.cap_of(key)
	var used: int = (c[key] as Array).size()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)
	hb.add_child(_mk(title, 13, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(_mk("%d / %d" % [used, cap], 13, GREEN if (cap > 0 and used >= cap) else DIM))
	parent.add_child(_bar(float(used), float(maxi(cap, 1)), col, 4.0))
	if cap <= 0:
		parent.add_child(_wrap("Bu geminin bu türde yuvası yok.", 12, DIM))
		return
	var fl := _flow(6)
	parent.add_child(fl)
	for i in cap:
		if i < used:
			var sid: String = str(c[key][i])
			fl.add_child(_gear_slot(sid, _on_unequip.bind(key, i), 58, "", _item_tip(sid, "Çıkarmak için tıkla")))
		else:
			fl.add_child(_gear_slot("", Callable()))


func _filter_groups() -> Array:
	match equip_filter:
		"las":
			return [DOData.LASER_ORDER]
		"gen":
			return [DOData.GEN_ORDER]
		"drn":
			return [DOData.DRONE_ORDER]
	return [DOData.LASER_ORDER, DOData.GEN_ORDER, DOData.DRONE_ORDER]


func _on_equip_filter(f: String) -> void:
	equip_filter = f
	_refresh_equip()


func _filter_bar(parent: Node) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	parent.add_child(hb)
	var grp := ButtonGroup.new()
	for f in [["all", "HEPSİ"], ["las", "LAZER"], ["gen", "JENERATÖR"], ["drn", "DROİD"]]:
		var b := _btn(str(f[1]), "ButtonSmall", _on_equip_filter.bind(str(f[0])), Vector2(0, 28), true, 11)
		b.toggle_mode = true
		b.button_group = grp
		b.button_pressed = (equip_filter == str(f[0]))
		hb.add_child(b)


# Takılabilir (boşta) eşyaların satırları; en iyi eşya en üstte
func _inv_rows(parent: Node, groups: Array, c: Dictionary) -> void:
	var any := false
	for group in groups:
		var ids: Array = (group as Array).duplicate()
		ids.reverse()
		for id in ids:
			var sid := str(id)
			var have: int = game.inv_count(sid)
			var key: String = game.item_key(sid)
			var nfree: int = game._free_count(c, key, sid)
			if have <= 0 or nfree <= 0:
				continue
			any = true
			var col: Color = RARITY_COLS[_rarity(sid)]
			var can: bool = (c[key] as Array).size() < game.cap_of(key)
			var h := _row_panel(parent)
			h.add_theme_constant_override("separation", 10)
			h.add_child(_gear_slot(sid, _on_equip.bind(sid), 48, "x%d" % nfree if nfree > 1 else "", _item_tip(sid, "Takmak için tıkla")))
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_theme_constant_override("separation", 0)
			h.add_child(info)
			info.add_child(_mk(str(game.item_def(sid).name), 14, col))
			info.add_child(_mk(_item_stat_text(sid), 12, TEXT2))
			info.add_child(_mk("Boşta %d / %d   •   %s" % [nfree, have, RARITY_NAMES[_rarity(sid)]], 11, DIM))
			var tb := _buy_btn(h, "TAK", _on_equip.bind(sid), can, 76)
			tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not any:
		parent.add_child(_wrap("Takılabilir eşya yok. Mağaza sekmesinden satın alabilirsin.", 12, DIM))


func _on_drone_tak_clicked(item_id: String) -> void:
	if selected_drone_slot == "":
		game.toast("Önce bir droid slotu seçin!")
		return
	var parts: Array = selected_drone_slot.split(":")
	if parts.size() < 2:
		game.toast("Geçersiz slot seçimi!")
		return
	var target_drone_id: String = str(parts[0])
	var slot_index: int = int(parts[1])
	game.equip_drone_item(target_drone_id, slot_index, item_id)

func _refresh_equip_tab_kaynaklar() -> void:
	equip_content.add_child(_mk("KAYNAKLAR", 16, NEON_ORANGE))
	equip_content.add_child(_line())
	equip_content.add_child(_wrap("Kaynak rafine etme sistemi yapım aşamasındadır.", 14, DIM))
