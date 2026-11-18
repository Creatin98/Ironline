extends Node
## Autoload "AudioManager": plays sound effects from pooled players.
## Sounds are referenced by their file name (without extension) in assets/audio/sfx.

const SFX_DIR := "res://assets/audio/sfx/"
const POOL_3D_SIZE := 24
const POOL_2D_SIZE := 10

var _streams: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0

## Menu music: every mp3/ogg/wav in MUSIC_DIR is played one after another (shuffled start).
const MUSIC_DIR := "res://assets/audio/music/"
const MUSIC_DB := -4.0
var _music_player: AudioStreamPlayer
var _playlist: Array[AudioStream] = []
var _music_index := 0
var _music_wanted := false
var _music_tween: Tween

## Flashbang: everything but the player's own body sounds becomes quiet and dull while the ringing whistle is heard.
## The filters sit on the category buses (not on SFX/Master: the tinnitus and the damage sounds stay clear).
const MUFFLE_BUSES: Array[String] = ["Weapons", "Grenades", "Reload", "Handling", "Movement", "Hitmarker", "Headshot", "Kill", "Ambience", "Music"]
const MUFFLE_CUTOFF_MIN := 420.0
const MUFFLE_DROP_DB := -14.0
var _muffle_fx: Dictionary = {} # bus name -> [AudioEffectLowPassFilter, AudioEffectAmplify, index of the filter]
var _flash_level: float = 0.0
var _ring_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioCategories.ensure_buses()
	for i in POOL_3D_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 80.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_db = 3.0
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D_SIZE:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "SFX"
		add_child(p2)
		_pool_2d.append(p2)
	_ring_player = AudioStreamPlayer.new()
	_ring_player.bus = "HitOther"
	add_child(_ring_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)
	_load_playlist()


func _load_playlist() -> void:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(MUSIC_DIR):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.get_extension().to_lower() in ["mp3", "ogg", "wav"] and not names.has(n):
			names.append(n)
	names.sort()
	for n in names:
		var st := load(MUSIC_DIR + n) as AudioStream
		if st != null:
			if st is AudioStreamMP3:
				(st as AudioStreamMP3).loop = false
			_playlist.append(st)
	if not _playlist.is_empty():
		_music_index = randi() % _playlist.size()


## Starts the menu music (does nothing if it already plays or no files exist).
func play_music() -> void:
	_music_wanted = true
	if _playlist.is_empty() or _music_player.playing:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_player.stream = _playlist[_music_index % _playlist.size()]
	_music_player.volume_db = -40.0
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", MUSIC_DB, 1.5)


func stop_music(fade: float = 0.6) -> void:
	_music_wanted = false
	if not _music_player.playing:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -40.0, fade)
	_music_tween.tween_callback(_music_player.stop)


func _on_music_finished() -> void:
	if _music_wanted and not _playlist.is_empty():
		_music_index = (_music_index + 1) % _playlist.size()
		_music_player.stream = _playlist[_music_index]
		_music_player.volume_db = MUSIC_DB
		_music_player.play()


func get_stream(sfx_name: String) -> AudioStream:
	if _streams.has(sfx_name):
		return _streams[sfx_name]
	var path := SFX_DIR + sfx_name + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	else:
		push_warning("AudioManager: Sound nicht gefunden: " + path)
	_streams[sfx_name] = stream
	return stream


## Plays a positional sound. Returns the player used (or null).
func play_3d(sfx_name: String, position: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.06, max_distance: float = 80.0) -> AudioStreamPlayer3D:
	var stream := get_stream(sfx_name)
	if stream == null:
		return null
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D_SIZE
	p.stop()
	p.stream = stream
	p.bus = AudioCategories.bus_of(sfx_name) # every sound belongs to its category bus
	p.global_position = position
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
	return p


## Plays a non-positional sound (local player's own weapon, UI, feedback).
## `bus` empty = the bus of the sound's category (see AudioCategories).
func play_2d(sfx_name: String, volume_db: float = 0.0, pitch_variation: float = 0.04, bus: String = "") -> AudioStreamPlayer:
	var stream := get_stream(sfx_name)
	if stream == null:
		return null
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D_SIZE
	p.stop()
	p.stream = stream
	p.bus = bus if bus != "" else AudioCategories.bus_of(sfx_name)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
	return p


## Plays the sample of a category (volume slider feedback in the sound settings).
## Confirmation tick of a volume slider: the same soft sound for every category, played on that category's bus
## (so it also shows the new level) and far quieter than the game sounds.
const SLIDER_CONFIRM_SOUND := "kill_confirm"
const SLIDER_CONFIRM_DB := -27.0


func play_preview(category_id: String) -> void:
	var entry := AudioCategories.get_entry(category_id)
	if entry.is_empty():
		return
	play_2d(SLIDER_CONFIRM_SOUND, SLIDER_CONFIRM_DB, 0.0, String(entry["bus"]))


func play_ui(sfx_name: String, volume_db: float = 0.0) -> void:
	play_2d(sfx_name, volume_db, 0.0, "UI")


## 0..1 = how deaf the player is (1 = completely muffled). Smooth callers ramp it; 0 switches everything off again.
func set_flash_effect(level: float) -> void:
	level = clampf(level, 0.0, 1.0)
	if level <= 0.0 and _flash_level <= 0.0:
		return
	if _muffle_fx.is_empty():
		_build_muffle()
	_flash_level = level
	var cutoff := lerpf(20500.0, MUFFLE_CUTOFF_MIN, pow(level, 0.55))
	for bus in _muffle_fx:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var fx: Array = _muffle_fx[bus]
		(fx[0] as AudioEffectLowPassFilter).cutoff_hz = cutoff
		(fx[1] as AudioEffectAmplify).volume_db = MUFFLE_DROP_DB * level
		var on := level > 0.003
		AudioServer.set_bus_effect_enabled(idx, int(fx[2]), on)
		AudioServer.set_bus_effect_enabled(idx, int(fx[2]) + 1, on)
	# the ringing follows the same level
	if level < 0.01:
		if _ring_player.playing:
			_ring_player.stop()
	else:
		if not _ring_player.playing and _ring_player.stream != null:
			_ring_player.play()
		_ring_player.volume_db = lerpf(-40.0, -9.0, pow(level, 0.7))


func get_flash_effect() -> float:
	return _flash_level


## A new flashbang hit us: the ringing starts again from its beginning.
func restart_flash_ring() -> void:
	if _ring_player.stream == null:
		_ring_player.stream = get_stream("flash_ring")
	if _ring_player.stream != null:
		_ring_player.volume_db = -40.0
		_ring_player.play()


func _build_muffle() -> void:
	for bus in MUFFLE_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20500.0
		lp.db = AudioEffectFilter.FILTER_24DB
		AudioServer.add_bus_effect(idx, lp)
		var lp_idx := AudioServer.get_bus_effect_count(idx) - 1
		var amp := AudioEffectAmplify.new()
		AudioServer.add_bus_effect(idx, amp)
		AudioServer.set_bus_effect_enabled(idx, lp_idx, false)
		AudioServer.set_bus_effect_enabled(idx, lp_idx + 1, false)
		_muffle_fx[bus] = [lp, amp, lp_idx]


## Stops every pooled player (scene change, quit, tests).
func stop_all() -> void:
	set_flash_effect(0.0)
	for p in _pool_3d:
		p.stop()
	for p2 in _pool_2d:
		p2.stop()


## Attaches a looping/long sound to a node (e.g. explosion follows nothing, but
## reload sounds should follow the player). Returns the created player.
func play_attached(sfx_name: String, parent: Node3D, volume_db: float = 0.0, pitch_variation: float = 0.05) -> AudioStreamPlayer3D:
	var stream := get_stream(sfx_name)
	if stream == null or not is_instance_valid(parent):
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = AudioCategories.bus_of(sfx_name)
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = 40.0
	p.unit_size = 4.0
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.play()
	return p
