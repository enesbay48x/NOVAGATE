extends Node
# NOVAGATE - ARKA PLAN MUZIGI  (autoload ve class_name GEREKMEZ)
#   Kullanan dosyada:  const Music = preload("res://music_player.gd")
#   Music.start()        -> muzigi baslatir (zaten caliyorsa dokunmaz)
#   Music.set_volume(v)  -> 0.0 .. 1.0, user://music.cfg dosyasina kaydedilir
#   Music.get_volume()   -> 0.0 .. 1.0
# Muzik bitmesine LOOP_BEFORE_END saniye kala basa sarilir, boylece sessizlik olmaz.

const MUSIC_PATH := "res://music/Darkorbit Old Soundtrack.mp3"
const CFG_PATH := "user://music.cfg"
const LOOP_BEFORE_END := 1.0      # bitmesine bu kadar saniye kala basa don
const DEFAULT_VOLUME := 0.5

const SELF_PATH := "res://music_player.gd"
const SfxScript := preload("res://sfx.gd")   # Music/SFX ses kanallarini olusturur (muzik lazer seslerinin onune gecmesin)
static var _inst = null
static var _volume := DEFAULT_VOLUME
static var _volume_loaded := false

var _player: AudioStreamPlayer
var _length := 0.0
var _cooldown := 0.0


# ---------------- DISARIYA ACIK (static) ----------------
static func start() -> void:
	if DisplayServer.get_name() == "headless":
		return   # dedicated sunucuda ses yok
	_ensure_volume_loaded()
	if _inst == null or not is_instance_valid(_inst):
		_inst = (load(SELF_PATH) as GDScript).new()
		_inst.name = "MusicPlayer"
		_inst.process_mode = Node.PROCESS_MODE_ALWAYS   # menu/duraklatmada kesilmesin
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	else:
		_inst._play()


static func get_volume() -> float:
	_ensure_volume_loaded()
	return _volume


static func set_volume(v: float) -> void:
	_ensure_volume_loaded()
	_volume = clampf(v, 0.0, 1.0)
	_save_volume()
	if _inst != null and is_instance_valid(_inst):
		_inst._apply_volume()


# ---------------- IC ISLER ----------------
func _ready() -> void:
	set_process(false)
	_play()


func _play() -> void:
	if _player != null and _player.playing:
		return
	if _player == null:
		var stream: AudioStream = _load_stream()
		if stream == null:
			push_warning("[MUSIC] Muzik dosyasi yuklenemedi: " + MUSIC_PATH)
			return
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true   # yedek: sarma kacarsa dosya sonunda kendi donsun
		_length = stream.get_length()
		_player = AudioStreamPlayer.new()
		_player.stream = stream
		SfxScript.ensure_buses()
		_player.bus = SfxScript.MUSIC_BUS   # ayri kanal: efektler calinca otomatik kisilir
		_player.finished.connect(_on_finished)
		add_child(_player)
		_apply_volume()
	_player.play(0.0)
	set_process(true)


func _process(delta: float) -> void:
	if _player == null or not _player.playing:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0 or _length <= LOOP_BEFORE_END + 1.0:
		return
	if _player.get_playback_position() >= _length - LOOP_BEFORE_END:
		_player.seek(0.0)
		_cooldown = 2.0


func _on_finished() -> void:
	if _player != null:
		_player.play(0.0)


func _apply_volume() -> void:
	if _player == null:
		return
	# 0'da tamamen sessiz (muzik arka planda akmaya devam eder)
	_player.volume_db = -80.0 if _volume <= 0.001 else linear_to_db(_volume)


func _load_stream() -> AudioStream:
	if ResourceLoader.exists(MUSIC_PATH):
		var s = load(MUSIC_PATH)
		if s is AudioStream:
			return s
	# .import henuz olusmadiysa ham dosyadan dene
	var f := FileAccess.open(MUSIC_PATH, FileAccess.READ)
	if f != null:
		var mp3 := AudioStreamMP3.new()
		mp3.data = f.get_buffer(f.get_length())
		return mp3
	return null


static func _ensure_volume_loaded() -> void:
	if _volume_loaded:
		return
	_volume_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		_volume = clampf(float(cfg.get_value("audio", "music_volume", DEFAULT_VOLUME)), 0.0, 1.0)


static func _save_volume() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("audio", "music_volume", _volume)
	cfg.save(CFG_PATH)
