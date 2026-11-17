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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	p.global_position = position
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
	return p


## Plays a non-positional sound (local player's own weapon, UI, feedback).
func play_2d(sfx_name: String, volume_db: float = 0.0, pitch_variation: float = 0.04, bus: String = "SFX") -> AudioStreamPlayer:
	var stream := get_stream(sfx_name)
	if stream == null:
		return null
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D_SIZE
	p.stop()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
	return p


func play_ui(sfx_name: String, volume_db: float = 0.0) -> void:
	play_2d(sfx_name, volume_db, 0.0, "UI")


## Stops every pooled player (scene change, quit, tests).
func stop_all() -> void:
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
	p.bus = "SFX"
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = 40.0
	p.unit_size = 4.0
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.play()
	return p
