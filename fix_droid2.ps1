$path = "C:\Users\Pc\Downloads\Yeni klasör/control_panel.gd"
$bytes = [System.IO.File]::ReadAllBytes($path)
$startTarget = [System.Text.Encoding]::UTF8.GetBytes("func _refresh_equip_tab_droidler()")
$startIdx = -1
for ($i = 0; $i -lt $bytes.Length - $startTarget.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $startTarget.Length; $j++) {
        if ($bytes[$i + $j] -ne $startTarget[$j]) { $match = $false; break }
    }
    if ($match) { $startIdx = $i; break }
}
if ($startIdx -lt 0) { Write-Host "Start not found"; exit }

$endTarget = [System.Text.Encoding]::UTF8.GetBytes("func _refresh_equip_tab_kaynaklar()")
$endIdx = -1
for ($i = 0; $i -lt $bytes.Length - $endTarget.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $endTarget.Length; $j++) {
        if ($bytes[$i + $j] -ne $endTarget[$j]) { $match = $false; break }
    }
    if ($match) { $endIdx = $i; break }
}
if ($endIdx -lt 0) { Write-Host "End not found"; exit }

Write-Host "Start: $startIdx, End: $endIdx"

# New function content
$newFunc = @"
func _refresh_equip_tab_droidler() -> void:
	_clear(equip_content)
	var c: Dictionary = game.cfg()
	var drone_equip: Dictionary = game.SV.get("drone_equip", {})
	if not drone_equip.has("flax"):
		drone_equip["flax"] = {}
	if not drone_equip.has("iris"):
		drone_equip["iris"] = {}

	equip_content.add_child(_mk("DROİDLER", 20, NEON_ORANGE, true))
	equip_content.add_child(_line())

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_content.add_child(split)

	# ===== SOL PANEL: DROİD YUVALARI =====
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)

	left.add_child(_mk("DROİD YUVALARI", 14, GOLD))
	left.add_child(_line())

	var droid_grid := GridContainer.new()
	droid_grid.columns = 2
	droid_grid.add_theme_constant_override("h_separation", 8)
	droid_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(droid_grid)

	var cur_drn: Array = c.drn
	for i in c.drn.size():
		var drone_id: String = str(c.drn[i])
		var dd: Dictionary = DOData.DRONES[drone_id]
		var slot_cap: int = dd.slots

		# Droid başlık çubuğu
		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 6)
		droid_grid.add_child(hdr)
		hdr.add_child(_icon(game.item_icon(drone_id), 28))
		var d_lbl := _mk(str(dd.name), 14, NEON_ORANGE)
		d_lbl.add_theme_font_size_override("font_size", 14)
		hdr.add_child(d_lbl)
		hdr.add_child(_mk("%d slot" % slot_cap, 11, DIM))

		# Slot ızgara - her slot tek bir hücre olarak droid_grid'e eklenir
		for si in slot_cap:
			var slot_key := "slot_" + str(si)
			var equipped_id: String = ""
			if drone_equip.has(drone_id) and drone_equip[drone_id].has(slot_key):
				equipped_id = str(drone_equip[drone_id][slot_key])

			var tip_txt: String = "Boş slot"
			if equipped_id != "":
				tip_txt = str(game.item_def(equipped_id).name) + " - çıkarmak için tıkla"

			var sb := _gear_slot(equipped_id, game._on_drone_slot_unequip.bind(drone_id, si), 44, "", tip_txt)
			droid_grid.add_child(sb)

	left.add_child(_line())

	# =====================================================
	# SAĞ PANEL: DROİD HANGARI
	# =====================================================
	var rp := _panel("PanelInset")
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(rp)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 6)
	rp.add_child(right_col)
	right_col.add_child(_mk("DROİD HANGARI", 14, NEON_ORANGE))
	right_col.add_child(_line())

	# Lazer kategorisi
	var laz_cat := VBoxContainer.new()
	right_col.add_child(laz_cat)
	laz_cat.add_child(_mk("LAZERLER", 12, NEON_ORANGE))
	laz_cat.add_child(_line())
	var laz_fl := _flow(6)
	laz_cat.add_child(laz_fl)
	var laz_any := False
	for id in DOData.LASER_ORDER:
		var sid: String = str(id)
		var have: int = int(game.SV.inv.get(sid, 0))
		if have <= 0:
			continue
		laz_any = True
		var h := _row_panel(laz_fl)
		h.add_theme_constant_override("separation", 6)
		h.add_child(_icon(game.item_icon(sid), 32))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		h.add_child(info)
		info.add_child(_mk(str(game.item_def(sid).name), 13, ICE_WHITE))
		info.add_child(_mk("Sahip: %d" % have, 11, DIM))
		var tak_btn := _buy_btn(h, "TAK", game._on_equip_drone_from_inventory.bind(sid), true, 70)
		tak_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Kalkan kategorisi
	var gen_cat := VBoxContainer.new()
	right_col.add_child(gen_cat)
	gen_cat.add_child(_mk("KALKANLAR", 12, NEON_ORANGE))
	gen_cat.add_child(_line())
	var gen_fl := _flow(6)
	gen_cat.add_child(gen_fl)
	var gen_any := False
	for id in DOData.GEN_ORDER:
		var g: Dictionary = DOData.GENS[id]
		if str(g.type) != "sh":
			continue
		var sid: String = str(id)
		var have: int = int(game.SV.inv.get(sid, 0))
		if have <= 0:
			continue
		gen_any = True
		var h := _row_panel(gen_fl)
		h.add_theme_constant_override("separation", 6)
		h.add_child(_icon(game.item_icon(sid), 32))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		h.add_child(info)
		info.add_child(_mk(str(game.item_def(sid).name), 13, ICE_WHITE))
		info.add_child(_mk("Sahip: %d" % have, 11, DIM))
		var tak_btn := _buy_btn(h, "TAK", game._on_equip_drone_from_inventory.bind(sid), true, 70)
		tak_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Drone kapatıkları kategorisi
	var drone_cat := VBoxContainer.new()
	right_col.add_child(drone_cat)
	drone_cat.add_child(_mk("DROİD KAPATIKLARI", 12, NEON_ORANGE))
	drone_cat.add_child(_line())
	var drone_fl := _flow(6)
	drone_cat.add_child(drone_fl)
	var drone_any := False
	for id in DOData.DRONE_ORDER:
		var sid: String = str(id)
		var have: int = int(game.SV.inv.get(sid, 0))
		if have <= 0:
			continue
		drone_any = True
		var h := _row_panel(drone_fl)
		h.add_theme_constant_override("separation", 6)
		h.add_child(_icon(game.item_icon(sid), 32))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		h.add_child(info)
		info.add_child(_mk(str(game.item_def(sid).name), 13, ICE_WHITE))
		info.add_child(_mk("Sahip: %d" % have, 11, DIM))
		var tak_btn := _buy_btn(h, "TAK", game._on_equip_drone_from_inventory.bind(sid), true, 70)
		tak_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if not any_avail and not gen_any and not drone_any:
		right_col.add_child(_wrap("Takılabilir eşya yok. Mağaza sekmesinden satın alabilirsin.", 12, DIM))

	equip_content.add_child(_btn("TÜMÜNÜ KALDIR", "ButtonDanger", game._on_unequip_all_drones, Vector2(170, 34), true, 12))
"@

# Replace
$newBytes = [System.Text.Encoding]::UTF8.GetBytes($newFunc)
$newContent = New-Object byte[] ($startIdx + $newBytes.Length + ($bytes.Length - $endIdx))
[Array]::Copy($bytes, 0, $newContent, 0, $startIdx)
[Array]::Copy($newBytes, 0, $newContent, $startIdx, $newBytes.Length)
[Array]::Copy($bytes, $endIdx, $newContent, $startIdx + $newBytes.Length, $bytes.Length - $endIdx)

[System.IO.File]::WriteAllBytes($path, $newContent)
Write-Host "Done! Replaced $($oldFunc.Length) bytes with $($newBytes.Length) bytes"