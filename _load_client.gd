extends Node
# LOAD TEST istemcisi (deploy: sadece test, kalici degil)
# Baglanir, katilir, haritaya girer, hold suresi boyunca 5 Hz hareket + state gonderir,
# sonra duzenli sekilde cikar. Sonuc STDOUT'a yazar (SSM/orchestrator okur).

var _idx: int = 0
var _addr: String = ""
var _map: String = "1-1"
var _hold: float = 120.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(a).trim_prefix("--").split("=")
		match str(kv[0]):
			"idx":
				_idx = int(kv[1])
			"hold":
				_hold = float(kv[1])
			"map":
				_map = str(kv[1])
	_addr = OS.get_environment("NOVAGATE_SERVER")
	if _addr.strip_edges() == "":
		print("LR-JOIN-FAIL idx=", _idx, " err=NOVAGATE_SERVER-bos")
		get_tree().quit(1)
		return
	var start_ms: int = Time.get_ticks_msec()
	var ok: bool = await Net.connect_and_join(_addr, {"name": "L%03d" % _idx,
		"faction": (_idx % 3) + 1, "ship": "phoenix"})
	var dt: int = Time.get_ticks_msec() - start_ms
	if not ok:
		print("LR-JOIN-FAIL idx=", _idx, " dt=", dt, " err=", Net.last_error)
		get_tree().quit(1)
		return
	print("LR-JOIN-OK idx=", _idx, " join_ms=", dt, " id=", Net.my_id)
	# yayilmis konum: safe zone disi, (1-1 haritasi icin 21000x13100)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var x: float = rng.randf_range(3000.0, 19000.0)
	var z: float = rng.randf_range(1000.0, 12000.0)
	Net.enter_map(_map, x, z)
	await get_tree().create_timer(1.0).timeout
	var t: float = 0.0
	while t < _hold:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
		x += rng.randf_range(-40.0, 40.0)
		z += rng.randf_range(-40.0, 40.0)
		x = clampf(x, 1000.0, 20000.0)
		z = clampf(z, 500.0, 12500.0)
		Net.send_state(x, z, 0.0, 4000.0, 4000.0, 1000.0, 1000.0, 320.0, false)
	Net.disconnect_from_server()
	await get_tree().create_timer(0.3).timeout
	print("LR-DONE idx=", _idx)
	get_tree().quit(0)
