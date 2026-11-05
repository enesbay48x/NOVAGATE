extends Node
# NOVAGATE - SES EFEKTLERI: lazer + NPC atis sesleri  (autoload GEREKMEZ)
#   const Sfx = preload("res://sfx.gd")
#   Sfx.start()                              -> ses sistemini hazirlar (Music.start() ile birlikte cagrilir)
#   Sfx.play("x3")                           -> KENDI atisimiz: tam ses
#   Sfx.play("x2", atan_konumu, bizim_konum) -> baska oyuncu / NPC atisi: mesafeye gore kisilir, cok uzaksa duyulmaz
#   Sfx.set_volume(v) / Sfx.get_volume()     -> efekt sesi 0.0 .. 1.0 (user://sfx.cfg)
#
# Ses kimlikleri: x1 x2 x3 x4 rsb (oyuncu lazerleri), npc (tum NPC atislari).
# Dosyasi olmayan kimlik (ornegin "sab") SESSIZ gecilir, hata vermez.
#
# MUZIK / EFEKT DENGESI:
#   - Muzik artik "Music" kanalindan calar, efektler "SFX" kanalindan (ikisi de Master'a gider).
#   - Music kanali sabit olarak MUSIC_HEADROOM_DB kadar kisiktir.
#   - Her lazer/NPC sesinde muzik ayrica DUCK_DB kadar daha kisilir, ses bitince yavasca geri gelir.
#   Boylece muzik hicbir zaman lazer seslerinin onune gecmez.

const SELF_PATH := "res://sfx.gd"
const CFG_PATH := "user://sfx.cfg"

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MUSIC_HEADROOM_DB := -6.0     # muzik kanalinin kalici kisikligi
const DUCK_DB := -7.0               # ses efekti calarken muzigin ek kisilmasi
const DUCK_ATTACK_DB_PER_S := 120.0   # muzik ne kadar hizli kisilir (dB/sn): neredeyse aninda
const DUCK_RELEASE_DB_PER_S := 14.0   # muzik ne kadar yavas geri gelir (dB/sn)
const DUCK_MIN_GAIN_DB := -12.0     # bundan daha kisik (uzak) sesler muzigi kisamaz

const SOUNDS := {
	"x1": "res://sounds/laser_x1.wav",
	"x2": "res://sounds/laser_x2.wav",
	"x3": "res://sounds/laser_x3.wav",
	"x4": "res://sounds/laser_x4.wav",
	"rsb": "res://sounds/laser_rsb.wav",
	"npc": "res://sounds/npc.wav",
}
# Ses basina ince ayar (dB). Bir ses fazla yuksek/kisik geliyorsa BURADAN oynayin.
const TRIM_DB := {
	"x1": 0.0, "x2": 0.0, "x3": 0.0, "x4": 0.0, "rsb": 0.0, "npc": -2.0,
}
const MAX_DUCK_HOLD := 0.45       # uzun seslerde (rsb 1.9 sn) muzik en fazla bu kadar sure kisik tutulur

# Baska oyuncu/NPC atislari icin duyulma mesafesi (Godot birimi; lazer menzili ~28).
const HEAR_NEAR := 18.0           # bu mesafeye kadar tam ses
const HEAR_FAR := 70.0            # bundan uzakta hic ses yok
const MIN_GAP := 0.045            # ayni sesin art arda tekrari icin asgari aralik (sn): kalabalikta sesler ust uste binmesin
const POOL_SIZE := 14

static var _inst = null
static var _volume := 1.0
static var _volume_loaded := false
static var _streams := {}

var _pool: Array = []
var _next := 0
var _last := {}
var _duck_hold := 0.0
var _duck_cur := 0.0              # 0 = kisma yok, DUCK_DB = tam kisik


# ---------------- DISARIYA ACIK (static) ----------------
static func start() -> void:
	if DisplayServer.get_name() == "headless":
		return   # dedicated sunucuda ses yok
	_ensure_volume_loaded()
	ensure_buses()
	if _inst == null or not is_instance_valid(_inst):
		_inst = (load(SELF_PATH) as GDScript).new()
		_inst.name = "SfxPlayer"
		_inst.process_mode = Node.PROCESS_MODE_ALWAYS
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)


# pos/listener verilmezse "kendi atisimiz" sayilir (tam ses). Ikisi de verilirse mesafeye gore kisilir.
static func play(id: String, pos = null, listener = null) -> void:
	if DisplayServer.get_name() == "headless" or not SOUNDS.has(id):
		return
	if _inst == null or not is_instance_valid(_inst):
		start()
		return   # ilk cagrida ornek henuz agaca eklenmedi; sonraki atistan itibaren calar
	_inst._play(id, pos, listener)


static func get_volume() -> float:
	_ensure_volume_loaded()
	return _volume


static func set_volume(v: float) -> void:
	_ensure_volume_loaded()
	_volume = clampf(v, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("audio", "sfx_volume", _volume)
	cfg.save(CFG_PATH)


# Music + SFX kanallarini (yoksa) olusturur. music_player.gd de bunu cagirir.
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		AudioServer.add_bus()
		var mi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(mi, MUSIC_BUS)
		AudioServer.set_bus_send(mi, "Master")
		AudioServer.set_bus_volume_db(mi, MUSIC_HEADROOM_DB)
	if AudioServer.get_bus_index(SFX_BUS) == -1:
		AudioServer.add_bus()
		var si := AudioServer.bus_count - 1
		AudioServer.set_bus_name(si, SFX_BUS)
		AudioServer.set_bus_send(si, "Master")
		AudioServer.set_bus_volume_db(si, 0.0)
		# Cok sayida ses ayni anda calinca patlama/bozulma olmasin
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(si, lim)


# ---------------- IC ISLER ----------------
func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_pool.append(p)


func _process(delta: float) -> void:
	_duck_hold = maxf(0.0, _duck_hold - delta)
	var target := DUCK_DB if _duck_hold > 0.0 else 0.0
	if target < _duck_cur:
		_duck_cur = maxf(target, _duck_cur - DUCK_ATTACK_DB_PER_S * delta)
	else:
		_duck_cur = minf(target, _duck_cur + DUCK_RELEASE_DB_PER_S * delta)
	var mi := AudioServer.get_bus_index(MUSIC_BUS)
	if mi != -1:
		AudioServer.set_bus_volume_db(mi, MUSIC_HEADROOM_DB + _duck_cur)


func _play(id: String, pos, listener) -> void:
	if _pool.is_empty():
		return
	var stream: AudioStream = _get_stream(id)
	if stream == null:
		return
	var gain_db: float = float(TRIM_DB.get(id, 0.0))
	if _volume <= 0.001:
		return
	gain_db += linear_to_db(_volume)
	var remote := pos != null and listener != null
	if remote:
		var pv: Vector3 = pos
		var lv: Vector3 = listener
		var d: float = pv.distance_to(lv)
		if d >= HEAR_FAR:
			return
		var t: float = clampf(inverse_lerp(HEAR_NEAR, HEAR_FAR, d), 0.0, 1.0)
		var g: float = (1.0 - t) * (1.0 - t)    # yaklastikca hizli, uzaklastikca yumusak azalir
		if g < 0.03:
			return
		gain_db += linear_to_db(g)
	# Ayni sesin ayni karede tekrarini engelle (kalabalik NPC grubunda tek ses gibi dursun)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -10.0)) < MIN_GAP:
		return
	_last[id] = now
	# bos oynatici bul; yoksa siradakini (en eski) kes
	var pl: AudioStreamPlayer = null
	for q in _pool:
		if not (q as AudioStreamPlayer).playing:
			pl = q
			break
	if pl == null:
		pl = _pool[_next]
		_next = (_next + 1) % _pool.size()
	pl.stream = stream
	pl.volume_db = gain_db
	pl.pitch_scale = 1.0 + (randf_range(-0.04, 0.04) if remote else 0.0)
	pl.play()
	# Muzigi kis (cok uzaktan gelen kisik sesler muzigi kismaz)
	if gain_db > DUCK_MIN_GAIN_DB:
		_duck_hold = maxf(_duck_hold, minf(stream.get_length(), MAX_DUCK_HOLD))


func _get_stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var path: String = SOUNDS[id]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStream:
			s = r
	if s == null:
		push_warning("[SFX] Ses dosyasi yuklenemedi: " + path + "  (Godot editorunde projeyi bir kez acin: dosyalar otomatik import edilir)")
	_streams[id] = s
	return s


static func _ensure_volume_loaded() -> void:
	if _volume_loaded:
		return
	_volume_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
