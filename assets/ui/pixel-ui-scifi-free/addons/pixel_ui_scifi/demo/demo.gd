extends Control
## The kit in use over a starfield, four screens of plain Controls styled by one Theme: the bridge
## (a ship's HUD, a systems window, a cargo hold, a comms line), the loadout (abilities by system,
## modules by rarity, hull and shield gauges either side of an ability bar cooling down), the menus
## (pause, settings with switches and steppers, key bindings, save slots, a confirm box) and play (a
## hold and its item card, toasts, a radial quick menu, a hotbar, key prompts, a comms line). The
## buttons along the bottom swap the theme and the screen.

const KIT := "res://addons/pixel_ui_scifi/"
const ALL_THEMES: Array[String] = ["cyan", "amber", "green", "magenta", "red", "steel"]
const ART_HEIGHT := 240.0
const FIRST := "cyan"
const SCREENS: Array[String] = ["bridge", "loadout", "menus", "play"]
const SYSTEMS: Array[String] = ["laser", "plasma", "ion", "cryo", "nano", "cyber", "gravity", "psi"]
const ABILITIES: Array[String] = ["beam", "burst", "barrier", "repair", "boost", "drone", "mine", "scan"]
const DOES := {"beam": "Fires a beam of %s at one target.", "burst": "A pulse of %s hits everything around you.",
	"barrier": "A barrier of %s soaks up the next hits.", "repair": "Patches the hull with %s over a few seconds.",
	"boost": "Overcharges the engines with %s for a few seconds.", "drone": "Launches a drone that fights with %s.",
	"mine": "Drops a mine that bursts into %s.", "scan": "Sweeps the area with %s and marks every foe."}
const FORCE := {"laser": "light", "plasma": "plasma", "ion": "ion charge", "cryo": "frost", "nano": "nanites",
	"cyber": "code", "gravity": "gravity", "psi": "psionic force"}

## Store capture only: switch to the next theme every this many frames.
@export var cycle_frames := 0
## The screen to open on, and the theme to open in when not FIRST.
@export_enum("bridge", "loadout", "menus", "play") var screen := "bridge"
@export var first_theme := ""

var frame := 0
var theme_buttons := {}
var pages := {}
var page: Control
var cooldowns: Array[TextureProgressBar] = []
var cooling: Array[float] = []  # each one's time to go, past 100 a rest with it ready
var picked: PanelContainer
var details: VBoxContainer


## Draws the UI at a whole-number scale so the art pixels stay square: the largest that still
## fits `art_height` pixels of art on screen.
static func pixel_scale(node: Node, art_height: float) -> void:
	var window := node.get_tree().root
	window.content_scale_factor = 1.0
	window.content_scale_factor = maxf(1.0, floorf(window.get_visible_rect().size.y / art_height))


static func themes() -> Array[String]:
	var installed: Array[String] = []
	for n in ALL_THEMES:
		if ResourceLoader.exists(KIT + "themes/%s.tres" % n):
			installed.append(n)
	return installed


## The named theme, or the first one installed.
static func kit_theme(name: String) -> Theme:
	return load(KIT + "themes/%s.tres" % (name if name in themes() else themes()[0]))


## Null when the icon isn't installed.
static func icon_texture(name: String) -> Texture2D:
	var path := KIT + "icons/%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null


## The icons are white: a TextureRect takes the theme's colour through `self_modulate`, which
## `tint` sets from the Button icon colour of the theme in effect.
static func icon(name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(name)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.add_to_group(&"tinted")
	return t


static func tint(root: Node) -> void:
	for node in root.get_tree().get_nodes_in_group(&"tinted"):
		if root.is_ancestor_of(node) or node == root:
			var c := node as Control
			c.self_modulate = c.get_theme_color(&"icon_normal_color", &"Button")


## A titled window; add its content to the returned VBox.
static func window(parent: Control, title: String, at: Vector2, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"WindowPanel"
	panel.position = at
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"Title"
	box.add_child(label)
	return box


static func row(parent: Control, separation := 3) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	parent.add_child(h)
	return h


static func bar(parent: Control, colour: String, value: float, width: float) -> ProgressBar:
	var b := ProgressBar.new()
	if colour != "":
		b.theme_type_variation = StringName(colour + "Bar")
	b.show_percentage = false
	b.value = value
	b.custom_minimum_size = Vector2(width, 8)
	parent.add_child(b)
	return b


static func slider(parent: Control, label: String, value: float, width := 36.0) -> void:
	var r := row(parent)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = width
	r.add_child(l)
	var s := HSlider.new()
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(s)


static func label(parent: Control, text: String, variation := &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	parent.add_child(l)
	return l


## Whether the theme has the game pieces (MenuItem, ItemSlot, KeyCap ...): the free sampler's hasn't.
static func has_game_pieces(t: Theme) -> bool:
	return t.get_type_variation_base(&"KeyCap") == &"Label"


## A line of a menu: the band and pointer show on the one picked (pressed in its ButtonGroup).
static func menu_item(parent: Control, text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_group = group
	parent.add_child(b)
	return b


## A toggle switch, its text on the left and the switch at the right end.
static func switch(parent: Control, text: String, on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	parent.add_child(c)
	return c


## A label, then < value > stepping through the options.
static func stepper(parent: Control, text: String, options: Array, index: int, width := 36.0) -> Label:
	var r := row(parent, 2)
	label(r, text).custom_minimum_size.x = width
	var left := Button.new()
	left.theme_type_variation = &"StepLeft"
	r.add_child(left)
	var value := label(r, options[index])
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := Button.new()
	right.theme_type_variation = &"StepRight"
	r.add_child(right)
	var step := func(by: int) -> void:
		value.text = options[(options.find(value.text) + by + options.size()) % options.size()]
	left.pressed.connect(step.bind(-1))
	right.pressed.connect(step.bind(1))
	return value


## Keys on their caps, then what they do.
static func prompt(parent: Control, keys: Array, text: String) -> HBoxContainer:
	var r := row(parent, 2)
	for k in keys:
		label(r, k, &"KeyCap")
	if text != "":
		label(r, text).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## A 24x24 item slot (ItemSlot, or ItemSlotSelected when `picked`) with the item's icon and its count
## above 1 in the corner.
static func slot(parent: Control, item: String, count := 1, picked := false) -> PanelContainer:
	var s := PanelContainer.new()
	s.theme_type_variation = &"ItemSlotSelected" if picked else &"ItemSlot"
	s.custom_minimum_size = Vector2(24, 24)
	parent.add_child(s)
	if item == "" or icon_texture(item) == null:
		return s
	var art := icon(item)
	art.tooltip_text = item.capitalize()
	s.add_child(art)
	if count > 1:
		var n := label(art, str(count), &"Count")
		n.position = Vector2(19, 10) - Vector2(n.get_minimum_size().x, 0)
	return s


## A notice: an icon and a line in a ToastPanel.
static func toast(parent: Control, item: String, text: String) -> PanelContainer:
	var t := PanelContainer.new()
	t.theme_type_variation = &"ToastPanel"
	parent.add_child(t)
	var r := row(t, 4)
	r.add_child(icon(item))
	label(r, text).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## An icon at twice its size in a PortraitPanel.
static func portrait(parent: Control, item: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PortraitPanel"
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face := icon(item)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.custom_minimum_size = Vector2(32, 32)
	p.add_child(face)
	parent.add_child(p)
	return p


## The installed ability icons' names, system by system.
static func abilities() -> Array[String]:
	var installed: Array[String] = []
	for system in SYSTEMS:
		for a in ABILITIES:
			if icon_texture("abilities/%s_%s" % [system, a]):
				installed.append("%s_%s" % [system, a])
	return installed


## A 20x20 ability frame (`SkillSlot`) round an ability icon, or empty for "". The ability icons are
## coloured, so they are not tinted.
static func ability(parent: Control, name: String) -> PanelContainer:
	var s := PanelContainer.new()
	s.theme_type_variation = &"SkillSlot"
	s.custom_minimum_size = Vector2(20, 20)
	parent.add_child(s)
	if name != "":
		var art := TextureRect.new()
		art.texture = icon_texture("abilities/" + name)
		art.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		s.add_child(art)
		s.tooltip_text = name.capitalize()
	return s


## A 24x24 slot rimmed in a rarity's colour (`CommonSlot` ... `LegendarySlot`) round an item's icon.
static func rarity_slot(parent: Control, item: String, rarity: String) -> PanelContainer:
	var s := PanelContainer.new()
	s.theme_type_variation = StringName(rarity.capitalize() + "Slot")
	s.custom_minimum_size = Vector2(24, 24)
	s.tooltip_text = "%s %s" % [rarity.capitalize(), item.capitalize()]
	parent.add_child(s)
	if icon_texture(item):
		s.add_child(icon(item))
	return s


## A 32x28 hexagonal gauge filled `value` percent from the bottom with bars/gauge_<colour>.png, under
## bars/gauge_glass.png, in the frame of whichever kit theme it is under.
static func gauge(parent: Control, colour: String, value: float) -> TextureProgressBar:
	var g := TextureProgressBar.new()
	g.fill_mode = TextureProgressBar.FILL_BOTTOM_TO_TOP
	g.texture_progress = load(KIT + "bars/gauge_%s.png" % colour)
	g.texture_progress_offset = Vector2(5, 4)
	g.texture_over = load(KIT + "bars/gauge_glass.png")
	g.value = value
	g.theme_changed.connect(func() -> void:  # each theme's gauge.png sits by its skill_slot.png
		var frame := g.get_theme_stylebox(&"panel", &"SkillSlot") as StyleBoxTexture
		if frame and frame.texture:
			g.texture_under = load(frame.texture.resource_path.get_base_dir().path_join("gauge.png")))
	parent.add_child(g)
	return g


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST  # project.godot's, for a project without it
	pixel_scale(self, ART_HEIGHT)
	add_child(Starfield.new())
	theme = kit_theme(first_theme if first_theme != "" else FIRST)
	var shown: Array[String] = ["bridge", "loadout"]
	if has_game_pieces(theme):
		shown = SCREENS.duplicate()
	for s in shown:
		pages[s] = Control.new()
		pages[s].set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pages[s].mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pages[s])
	page = pages["bridge"]
	_hud()
	_systems()
	_cargo()
	_target()
	_comms()
	page = pages["loadout"]
	_abilities()
	_modules()
	_action_bar()
	if "menus" in pages:
		page = pages["menus"]
		_menus()
		page = pages["play"]
		_play()
	var switcher := row(self, 2)
	switcher.position = Vector2(6, 222)
	var group := ButtonGroup.new()
	for name in themes():
		var b := Button.new()
		b.text = name.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = name == theme.resource_path.get_file().get_basename()
		b.toggled.connect(func(on: bool) -> void:
			if on:
				theme = kit_theme(name)
				tint(self))
		switcher.add_child(b)
		theme_buttons[name] = b
	if shown.size() > 1:
		var screens := row(self, 2)
		var screen_group := ButtonGroup.new()
		for s in shown:
			var b := Button.new()
			b.text = s.capitalize()
			b.toggle_mode = true
			b.button_group = screen_group
			b.button_pressed = s == screen
			b.toggled.connect(func(on: bool) -> void: if on: _show(s))
			screens.add_child(b)
		screens.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
		screens.position.y = switcher.position.y
	_show(screen if screen in pages else "bridge")
	tint(self)


func _show(which: String) -> void:
	for s in pages:
		pages[s].visible = s == which


func _process(delta: float) -> void:
	for i in cooldowns.size():  # each ability comes round at its own pace, with a rest between
		cooling[i] = fposmod(cooling[i] - delta * 100.0 / (2.0 + i), 160.0)
		cooldowns[i].value = cooling[i] if cooling[i] <= 100.0 else 0.0
	if cycle_frames <= 0:
		return
	frame += 1
	if frame % cycle_frames == 0:
		var names := themes()
		var start := first_theme if first_theme != "" else FIRST
		var next: String = names[(maxi(0, names.find(start)) + frame / cycle_frames) % names.size()]
		theme_buttons[next].button_pressed = true


func _hud() -> void:
	var rows := VBoxContainer.new()
	rows.position = Vector2(6, 5)
	rows.add_theme_constant_override("separation", 1)
	page.add_child(rows)
	for pair in [["heart", "Red", 72], ["shield", "Blue", 48], ["energy", "Gold", 90]]:
		var r := row(rows, 2)
		r.add_child(icon(pair[0]))
		var b := bar(r, pair[1], pair[2], 70)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var money := row(page, 1)
	money.position = Vector2(290, 5)
	for pair in [["credit", "4096"], ["crystal", "12"], ["fuel", "68%"]]:
		money.add_child(icon(pair[0]))
		label(money, pair[1])
		var gap := Control.new()
		gap.custom_minimum_size.x = 4
		money.add_child(gap)


func _systems() -> void:
	var box := window(page, "SHIP SYSTEMS", Vector2(6, 62), 150)
	slider(box, "Thrust", 70)
	slider(box, "Shields", 40)
	var auto := CheckBox.new()
	auto.text = "Autopilot"
	auto.button_pressed = true
	box.add_child(auto)
	var cloak := CheckBox.new()
	cloak.text = "Cloak"
	box.add_child(cloak)
	var mode := OptionButton.new()
	for m in ["Cruise", "Combat", "Stealth"]:
		mode.add_item(m)
	box.add_child(mode)
	var callsign := LineEdit.new()
	callsign.placeholder_text = "Callsign"
	box.add_child(callsign)
	var buttons := row(box)
	for t in ["Abort", "Engage"]:
		var b := Button.new()
		b.text = t
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)


func _cargo() -> void:
	var box := window(page, "CARGO HOLD", Vector2(164, 28), 258)
	var tabs := TabContainer.new()
	box.add_child(tabs)
	var items := GridContainer.new()
	items.name = "Items"
	items.columns = 9
	items.add_theme_constant_override("h_separation", 2)
	items.add_theme_constant_override("v_separation", 2)
	tabs.add_child(items)
	var stock := [["fuel", 3], ["battery", 2], ["crystal", 12], ["chip", 4], ["keycard", 1], ["health", 5],
		["laser", 1], ["rocket", 2], ["cargo", 6], ["wrench", 1], ["satellite", 0], ["asteroid", 9], ["radar", 0],
		["robot", 0], ["alien", 0], ["star", 0], ["energy", 0], ["planet", 0]]
	stock = stock.filter(func(pair: Array) -> bool: return icon_texture(pair[0]) != null).slice(0, 16)
	for i in 18:
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"InsetPanel"
		slot.custom_minimum_size = Vector2(24, 24)
		items.add_child(slot)
		if i >= stock.size():
			continue
		var pair: Array = stock[i]
		var art := icon(pair[0])
		art.tooltip_text = String(pair[0]).capitalize()
		slot.add_child(art)
		if pair[1] > 1:
			var count := Label.new()
			count.text = str(pair[1])
			count.add_theme_color_override("font_shadow_color", Color.BLACK)
			art.add_child(count)
			count.position = Vector2(19, 10) - Vector2(count.get_minimum_size().x, 0)
	var crew := VBoxContainer.new()
	crew.name = "Crew"
	tabs.add_child(crew)
	for pair in [["astronaut", "Cmdr. Vega"], ["robot", "Unit K-9"]]:
		var r := row(crew)
		r.add_child(icon(pair[0]))
		var l := label(r, pair[1])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.text = "Assign"
		r.add_child(b)
	var hold := row(box)
	hold.add_child(icon("cargo"))
	label(hold, "Hold 60%")
	var fill := bar(hold, "", 60, 0)
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var actions := row(box)
	for pair in [["check", "Use"], ["trash", "Jettison"], ["info", "Scan"]]:
		var b := Button.new()
		b.text = pair[1]
		b.icon = icon_texture(pair[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)


func _target() -> void:
	var frame_panel := PanelContainer.new()
	frame_panel.theme_type_variation = &"BracketPanel"
	frame_panel.position = Vector2(100, 4)
	frame_panel.custom_minimum_size = Vector2(56, 52)
	page.add_child(frame_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	frame_panel.add_child(box)
	var reticle := TextureRect.new()
	reticle.texture = load(KIT + "hud/reticle_lock.png")
	reticle.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	reticle.add_to_group(&"tinted")
	box.add_child(reticle)
	label(box, "LOCKED").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _comms() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(6, 187)
	panel.custom_minimum_size.x = 416
	page.add_child(panel)
	var r := row(panel, 6)
	var face := PanelContainer.new()
	face.theme_type_variation = &"InsetPanel"
	face.add_child(icon("astronaut"))
	r.add_child(face)
	var text := label(r, "Incoming transmission from Outpost 7.\nDock at bay 3 and mind the asteroids.")
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var next := Button.new()
	next.icon = icon_texture("arrow_right")
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(next)


## Every installed ability, a row per system; pointing at one shows it in the details window.
func _abilities() -> void:
	var box := window(page, "ABILITIES", Vector2(6, 6), 0)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	var known := abilities()
	for system in SYSTEMS:
		if not known.any(func(n: String) -> bool: return n.begins_with(system + "_")):
			continue
		label(grid, system.capitalize()).custom_minimum_size.x = 32
		for a in ABILITIES:
			var name := "%s_%s" % [system, a]
			var cell := ability(grid, name if name in known else "")
			if name in known:
				cell.mouse_entered.connect(_pick.bind(cell, name))
	details = window(page, "ABILITY", Vector2(232, 6), 189)
	if not known.is_empty():
		_pick(grid.get_child(1) as PanelContainer, known[0])


## Shows an ability in the details window and lights its frame.
func _pick(cell: PanelContainer, name: String) -> void:
	if picked:
		picked.theme_type_variation = &"SkillSlot"
	picked = cell
	cell.theme_type_variation = &"ActiveSkillSlot"
	for c in details.get_children().slice(1):
		c.queue_free()
	var system := name.get_slice("_", 0)
	var kind := name.get_slice("_", 1)
	var level := ABILITIES.find(kind)
	var top := row(details, 6)
	var face := PanelContainer.new()
	face.theme_type_variation = &"PortraitPanel"
	var art := TextureRect.new()
	art.texture = icon_texture("abilities/" + name)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.custom_minimum_size = Vector2(32, 32)
	face.add_child(art)
	top.add_child(face)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 1)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(titles)
	label(titles, name.capitalize(), &"Nameplate").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label(titles, "%s system" % system.capitalize())
	label(titles, "Mk %d / 4" % (level % 4 + 1))
	var text: String = DOES[kind] % FORCE[system]
	var about := label(details, text)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	about.custom_minimum_size.x = 177
	var cost := row(details, 3)
	for pair in [["battery", "%d energy" % (8 + level * 4)], ["power", "%ds cooldown" % (2 + level * 3)]]:
		cost.add_child(icon(pair[0]))
		label(cost, pair[1]).custom_minimum_size.x = 64
	tint(details)
	var buttons := row(details)
	for pair in [["plus", "Install"], ["arrow_down", "Assign"]]:
		var b := Button.new()
		b.text = pair[1]
		b.icon = icon_texture(pair[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)


## The ship's modules, one of each rarity.
func _modules() -> void:
	var r := row(page, 2)
	r.position = Vector2(232, 146)
	label(r, "MODULES").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for it in [["wrench", "common"], ["battery", "uncommon"], ["shield", "rare"], ["chip", "epic"], ["crystal", "legendary"]]:
		rarity_slot(r, it[0], it[1])


## The hull and shield gauges either side of a bar of abilities cooling down.
func _action_bar() -> void:
	var known := abilities()
	var keys: Array[String] = []
	for name in ["laser_beam", "cryo_burst", "nano_repair", "ion_barrier", "gravity_drone"]:
		if name in known:
			keys.append(name)
	for name in known:
		if keys.size() < 5 and name not in keys:
			keys.append(name)
	var line := row(page, 3)
	line.position = Vector2(232, 178)
	_meter(line, "red", 72, "Hull")
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(panel)
	var r := row(panel, 2)
	for i in 5:
		var s := ability(r, keys[i] if i < keys.size() else "")
		if i < keys.size():
			var c := TextureProgressBar.new()
			c.fill_mode = TextureProgressBar.FILL_CLOCKWISE
			c.texture_progress = load(KIT + "bars/cooldown.png")
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s.add_child(c)
			cooldowns.append(c)
			cooling.append(150.0 - i * 37)
		if s.get_child_count():
			label(s.get_child(0), str(i + 1), &"Count").position = Vector2(-2, -3)
	_meter(line, "blue", 45, "Shield")


## A gauge with its name under it.
func _meter(parent: Control, colour: String, value: float, text: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	gauge(box, colour, value).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label(box, text).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _menus() -> void:
	var pause := window(page, "PAUSED", Vector2(6, 6), 84)
	var group := ButtonGroup.new()
	for t in ["Resume", "Save", "Load", "Settings", "Controls", "Quit"]:
		menu_item(pause, t, group).button_pressed = t == "Settings"
	var quit := window(page, "ABORT?", Vector2(6, 118), 84)
	label(quit, "Progress since\nthe last save\nwill be lost.")
	var answer := row(quit)
	for t in ["Yes", "No"]:
		var b := Button.new()
		b.text = t
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		answer.add_child(b)

	var box := window(page, "SETTINGS", Vector2(96, 6), 160)
	slider(box, "Music", 70, 44)
	slider(box, "Sound", 40, 44)
	switch(box, "Vsync", true)
	switch(box, "Subtitles", false)
	stepper(box, "Difficulty", ["Easy", "Normal", "Hard"], 1, 44)
	stepper(box, "Window", ["Windowed", "Fullscreen", "Borderless"], 1, 44)
	box.add_child(HSeparator.new())
	var buttons := row(box)
	for t in ["Back", "Apply"]:
		var b := Button.new()
		b.text = t
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)

	var keys := window(page, "CONTROLS", Vector2(262, 6), 159)
	for pair in [["Thrust", ["W", "A", "S", "D"]], ["Fire", ["Space"]], ["Dock", ["E"]], ["Pause", ["Esc"]]]:
		var r := row(keys, 2)
		label(r, pair[0]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prompt(r, pair[1], "")

	var rebind := window(page, "PRESS A KEY", Vector2(96, 150), 160)
	label(rebind, "Press a key for Fire").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt(rebind, ["Esc"], "Cancel").alignment = BoxContainer.ALIGNMENT_CENTER

	var saves := window(page, "LOAD GAME", Vector2(262, 100), 159)
	var picked := ButtonGroup.new()
	for s in [["ship", "Kepler Station", "Sector 7  2h 14m"], ["planet", "Red Moon", "Sector 4  1h 02m"],
			["plus", "New game", ""]]:
		var b := Button.new()
		b.theme_type_variation = &"SaveSlot"
		b.text = s[1] + "\n" + s[2]
		b.icon = icon_texture(s[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = picked
		b.button_pressed = s[1] == "Kepler Station"
		saves.add_child(b)


func _play() -> void:
	var hold := window(page, "HOLD", Vector2(6, 6), 0)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	hold.add_child(grid)
	var stock := [["laser", 1], ["battery", 3], ["shield", 1], ["fuel", 5], ["rocket", 4], ["keycard", 2],
		["crystal", 12], ["health", 2], ["chip", 30], ["wrench", 1]]
	for i in 18:
		slot(grid, stock[i][0] if i < stock.size() else "", stock[i][1] if i < stock.size() else 0, i == 1)

	var card := PanelContainer.new()
	card.theme_type_variation = &"TooltipPanel"
	card.position = Vector2(176, 6)
	card.custom_minimum_size.x = 110
	page.add_child(card)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 3)
	card.add_child(lines)
	var top := row(lines, 3)
	top.add_child(icon("battery"))
	label(top, "Power cell", &"Nameplate").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var about := label(lines, "Restores 40 energy to the ship's shields.")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	about.custom_minimum_size.x = 100
	var worth := row(lines, 2)
	worth.add_child(icon("credit"))
	label(worth, "15").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var use := row(lines, 6)
	prompt(use, ["E"], "Use")
	prompt(use, ["Q"], "Drop")

	var toasts := VBoxContainer.new()
	toasts.add_theme_constant_override("separation", 2)
	page.add_child(toasts)
	for pair in [["star", "Mission updated"], ["credit", "+50 credits"], ["save", "Game saved"]]:
		toast(toasts, pair[0], pair[1])
	toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)

	_radial(Vector2(362, 146), 44)

	var talk := PanelContainer.new()
	talk.position = Vector2(6, 112)
	talk.custom_minimum_size.x = 290
	page.add_child(talk)
	var r := row(talk, 6)
	portrait(r, "astronaut")
	var said := VBoxContainer.new()
	said.add_theme_constant_override("separation", 2)
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(said)
	label(said, "Cmdr. Vega", &"Nameplate").size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label(said, "Outpost 7 has lost power. Bring\nthree power cells to the relay.")
	prompt(said, ["E"], "Next").size_flags_horizontal = Control.SIZE_SHRINK_END

	var hotbar := PanelContainer.new()
	hotbar.position = Vector2(6, 176)
	page.add_child(hotbar)
	var keys := row(hotbar, 2)
	var items := ["laser", "rocket", "shield", "health", "battery", "keycard", "wrench", "crystal"]
	for i in items.size():
		var s := slot(keys, items[i], 1, i == 2)
		label(s.get_child(0), str(i + 1), &"Count").position = Vector2(-2, -3)

	var hints := VBoxContainer.new()
	hints.add_theme_constant_override("separation", 2)
	hints.position = Vector2(232, 180)
	page.add_child(hints)
	prompt(hints, ["Tab"], "Hold")
	prompt(hints, ["Esc"], "Menu")


## A quick-pick wheel: slots round a centre naming the one picked.
func _radial(centre: Vector2, radius: float) -> void:
	var items := ["laser", "rocket", "shield", "health", "battery", "fuel", "keycard", "crystal"]
	for i in items.size():
		var a := -PI / 2 + TAU * i / items.size()
		var s := slot(page, items[i], 1, i == 3)
		s.position = (centre + Vector2(cos(a), sin(a)) * radius - Vector2(12, 12)).round()
	var name := label(page, "Med pack")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size.x = 60
	name.position = centre - Vector2(30, 12)
	prompt(page, ["Q"], "").position = centre - Vector2(5, -1)


## Stars and a planet behind the UI, so the panels show they let a little through.
class Starfield extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 140:
			var p := Vector2(rng.randi_range(0, 427), rng.randi_range(0, 240))
			var v := rng.randf_range(0.25, 1.0)
			draw_rect(Rect2(p, Vector2.ONE), Color(v, v, v * 1.1))
		draw_circle(Vector2(330, 180), 70, Color(0.09, 0.1, 0.2))
		draw_circle(Vector2(318, 170), 58, Color(0.12, 0.14, 0.27))
