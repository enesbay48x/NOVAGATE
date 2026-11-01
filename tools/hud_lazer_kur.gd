@tool
extends EditorScript
# DarkOrbit HUD + lazer duzeltmesi kurulum betigi.
# Kullanim: Script duzenleyicide bu dosyayi ac -> Dosya > Calistir (Ctrl+Shift+X). Sonucu "Cikti" panelinden oku.
# main.gd'yi KOMPLE DEGISTIRMEZ; sadece birkac satir ekler / degistirir. Yedek: res://main.gd.hud_yedek

const MAIN := "res://main.gd"
var _log: PackedStringArray = []


# Desenin ilk eslesmesini cb(m) sonucuyla degistirir.
func _edit(src: String, pattern: String, tag: String, cb: Callable) -> String:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		_log.append("HATA (desen): " + tag)
		return src
	var m := re.search(src)
	if m == null:
		_log.append("BULUNAMADI: " + tag)
		return src
	_log.append("tamam: " + tag)
	var rep: String = cb.call(m)
	return src.substr(0, m.get_start()) + rep + src.substr(m.get_end())


# Desenin tum eslesmelerini siler.
func _remove_all(src: String, pattern: String, tag: String) -> String:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		_log.append("HATA (desen): " + tag)
		return src
	var ms := re.search_all(src)
	if ms.is_empty():
		_log.append("BULUNAMADI: " + tag)
		return src
	_log.append("tamam: %s (%d satir)" % [tag, ms.size()])
	var out := ""
	var pos := 0
	for m in ms:
		out += src.substr(pos, m.get_start() - pos)
		pos = m.get_end()
	return out + src.substr(pos)


func _run() -> void:
	var f := FileAccess.open(MAIN, FileAccess.READ)
	if f == null:
		push_error("main.gd acilamadi: " + MAIN)
		return
	var orig := f.get_as_text()
	f.close()
	var src := orig.replace("\r\n", "\n")

	for p in ["res://hud_do.gd", "res://minimap_do.gd", "res://laser_fx.gd"]:
		if not FileAccess.file_exists(p):
			push_error("Eksik dosya: " + p + "  (zipteki tum dosyalari proje klasorune kopyala)")
			return

	# ---- preload satirlari
	if not src.contains("DOHud"):
		src = _edit(src, "(?m)^extends [^\\n]*\\n", "DOHud preload", func(m): return m.get_string() + "\nconst DOHud := preload(\"res://hud_do.gd\")\nvar dohud = null\n")
	if not src.contains("LaserFX"):
		src = _edit(src, "(?m)^extends [^\\n]*\\n", "LaserFX preload", func(m): return m.get_string() + "\nconst LaserFX := preload(\"res://laser_fx.gd\")\n")

	# ---- HUD baglantilari
	if not src.contains("_build_dohud()"):
		src = _edit(src, "(?m)^\\t_build_player_panel\\(\\)\\n", "_build_ui: yeni HUD cagrisi", func(m): return "\t_build_dohud()\n")
		src = _remove_all(src, "(?m)^\\t_build_(target_panel|minimap|slotbar|log)\\(\\)\\n", "_build_ui: eski HUD cagrilari")
		src = _edit(src, "(?m)^func _update_hud\\([^\\n]*\\n", "_update_hud", func(m): return m.get_string() + "\tif dohud != null:\n\t\tdohud.refresh(def, mhp, po)\n\t\treturn\n")
		src = _edit(src, "(?m)^func _layout_right\\([^\\n]*\\n", "_layout_right", func(m): return m.get_string() + "\tif dohud != null:\n\t\tdohud.layout_right()\n\t\treturn\n")
		src = _edit(src, "(?m)^func toast\\([^\\n]*\\n", "toast -> sohbet sistem sekmesi", func(m): return m.get_string() + "\tif dohud != null:\n\t\tdohud.log_system(t)\n")
		src += "\n\nfunc _build_dohud() -> void:\n\tdohud = DOHud.new()\n\tdohud.game = self\n\tui.add_child(dohud)\n\tdohud.build()\n\thud_nodes.append(dohud)\n\tmm = dohud.minimap\n\tlbl_toast = dohud.lbl_toast\n\tlbl_prompt = dohud.lbl_prompt\n\tlbl_help = dohud.lbl_help\n"
	else:
		_log.append("HUD zaten bagli, atlandi")

	# ---- lazer duzeltmeleri
	if not src.contains("LaserFX.pick"):
		src = _edit(src, "(?m)^([ \\t]*)if vis\\.size\\(\\) > 8:\\n[ \\t]*vis\\.resize\\(8\\)\\n", "lazer: 2'li / 4'lu atis", func(m): return m.get_string(1) + "vis = LaserFX.pick(vis)\n")
		src = _edit(src, "var lat := \\(float\\(j\\) - float\\(vis\\.size\\(\\) - 1\\) \\* 0\\.5\\) \\* [0-9.]+", "lazer: yanal dizilim", func(m): return "var lat: float = LaserFX.lat(j, vis.size())")
		src = _edit(src, "(?m)^([ \\t]*)fire_bolt\\(po \\+ dir \\* 3\\.0 \\+ side \\* lat,[^\\n]*\\n", "lazer: paralel ucus isareti", func(m): return m.get_string() + m.get_string(1) + "LaserFX.mark_parallel(self, side * lat)\n")
		src = _edit(src, "(?m)^([ \\t]*)tpos = te\\.node\\.position\\n", "lazer: paralel ucus (mermi hareketi)", func(m): return m.get_string(1) + "tpos = te.node.position + b.get(\"off\", Vector3.ZERO)\n")
		src = _edit(src, "(?m)^([ \\t]*)P\\.sh = minf\\(max_sh\\(\\), P\\.sh \\+ a\\)\\n", "SAB: kuculen halkalar", func(m): return m.get_string() + m.get_string(1) + "LaserFX.sab_ring(self, e, a)\n")
	else:
		_log.append("Lazer duzeltmesi zaten bagli, atlandi")

	var bak := FileAccess.open("res://main.gd.hud_yedek", FileAccess.WRITE)
	if bak != null:
		bak.store_string(orig)
		bak.close()
	var w := FileAccess.open(MAIN, FileAccess.WRITE)
	if w == null:
		push_error("main.gd yazilamadi")
		return
	w.store_string(src)
	w.close()
	print("=== HUD + lazer kurulumu ===")
	for l in _log:
		print(l)
	print("Bitti. Godot 'dosya degisti' diye sorarsa Yeniden Yukle de. Sorun olursa main.gd.hud_yedek yedegini geri koy.")
