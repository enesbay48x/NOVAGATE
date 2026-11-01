extends SceneTree
# Oyun-ici gorsel test: lazerleri gercek savas ortaminda ucurup ekran goruntusu alir.
# Calistirma (headless DEGIL): godot --path . --script res://test_gorsel.gd
# Ciktilar: ekran_lazer_1/2/3.png (proje klasorune kaydedilir).

var M = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var ps: PackedScene = load("res://main.tscn")
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	M = _find_main(root)
	if M == null:
		push_error("main.gd scriptli node bulunamadi")
		quit(2)
		return
	M.new_game(1)   # ana menuyue atlamadan savasa gir (menu _start_run icinde gizlenir)
	await _wait(90)   # harita, gemiler ve NPC'lerin kurulmasi

	# en DAYANIKLI dusmani hedef sec (salvo sirasinda olmesin)
	var best = null
	for e in M.enemies:
		if not is_instance_valid(e.node):
			continue
		if best == null or float(e["mx"]) > float(best["mx"]):
			best = e
	if best == null:
		push_error("haritada dusman yok")
		quit(3)
		return
	M.running = true
	M.SV.ammo["x2"] = 5000    # gozle gorunur mavi mermim
	M.select_ammo("x2")
	M.target = best
	# oyuncuyu lazer menziline tasi (laser menzil = 700 * 0.04 = 28 birim)
	var dir: Vector3 = Vector3(M.P.node.position) - Vector3(best.node.position)
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	M.P.node.position = Vector3(best.node.position) + dir * 22.0
	M.dest = null
	M.fire = true
	M.P.cd = 0.0

	await _wait(8)
	_shot("ekran_lazer_1.png")   # ilk salvo ucusurken
	await _wait(22)
	_shot("ekran_lazer_2.png")   # isabet/trail dagilimi
	await _wait(65)
	_shot("ekran_lazer_3.png")   # ikinci salvo (1.0 sn aralik)
	print("GORSEL TEST BITTI - bolts havada=%d" % M.bullets.size())
	quit(0)


func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://" + nm))
	print("ekran goruntusu kaydedildi: " + nm)


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _find_main(n: Node):
	if n.get_script() != null and str((n.get_script() as Script).resource_path).ends_with("main.gd"):
		return n
	for c in n.get_children():
		var r = _find_main(c)
		if r != null:
			return r
	return null
