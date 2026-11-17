class_name AmbienceSystem
extends Node
## Quiet background atmosphere of a map: wind and water loops, occasional bird calls and a distant
## jet. Everything is played through the category buses (Wind, Water, Birds, Distant ...), so the
## sound settings control it. Kept far below the gameplay sounds on purpose.

## Per map: loops {sound: volume_db}, birds (sound list, chirp interval range), planes (interval range).
const PROFILES := {
	"harbor": {
		"loops": {"amb_wind": -27.0, "amb_water": -22.0},
		"birds": ["amb_gull", "amb_gull", "amb_bird_3"], "bird_interval": Vector2(7.0, 16.0),
		"plane_interval": Vector2(70.0, 140.0),
	},
	"suburb": {
		"loops": {"amb_wind": -31.0},
		"birds": ["amb_bird_1", "amb_bird_2", "amb_bird_3"], "bird_interval": Vector2(4.0, 10.0),
		"plane_interval": Vector2(60.0, 120.0),
	},
	"frontier": {
		"loops": {"amb_wind": -25.0},
		"birds": ["amb_bird_2", "amb_bird_3"], "bird_interval": Vector2(9.0, 20.0),
		"plane_interval": Vector2(80.0, 160.0),
	},
	"test_arena": {
		"loops": {"amb_wind": -32.0},
		"birds": [], "bird_interval": Vector2(10.0, 20.0),
		"plane_interval": Vector2(0.0, 0.0),
	},
}

var _profile: Dictionary = {}
var _bird_timer := 0.0
var _plane_timer := 0.0
var _players: Array[AudioStreamPlayer] = []


func setup(map_id: String) -> void:
	_profile = PROFILES.get(map_id, PROFILES["test_arena"])
	var loops: Dictionary = _profile["loops"]
	for sound in loops:
		var stream := AudioManager.get_stream(sound)
		if stream == null or not (stream is AudioStreamWAV):
			continue
		var looped := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = looped.data.size() / 2 # 16-bit mono
		var p := AudioStreamPlayer.new()
		p.stream = looped
		p.bus = AudioCategories.bus_of(sound)
		p.volume_db = float(loops[sound])
		add_child(p)
		p.play()
		_players.append(p)
	_bird_timer = randf_range(2.0, 6.0)
	var pi: Vector2 = _profile["plane_interval"]
	_plane_timer = randf_range(pi.x, pi.y) * 0.5 if pi.y > 0.0 else -1.0


func _process(delta: float) -> void:
	if _profile.is_empty():
		return
	var birds: Array = _profile["birds"]
	if not birds.is_empty():
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			var iv: Vector2 = _profile["bird_interval"]
			_bird_timer = randf_range(iv.x, iv.y)
			_play_bird(String(birds[randi() % birds.size()]))
	if _plane_timer >= 0.0:
		_plane_timer -= delta
		if _plane_timer <= 0.0:
			var pi: Vector2 = _profile["plane_interval"]
			_plane_timer = randf_range(pi.x, pi.y)
			AudioManager.play_2d("amb_plane", -24.0, 0.04)


func _play_bird(sound: String) -> void:
	var listener := get_viewport().get_camera_3d()
	if listener == null:
		return
	var angle := randf() * TAU
	var dist := randf_range(14.0, 34.0)
	var pos := listener.global_position + Vector3(cos(angle) * dist, randf_range(5.0, 12.0), sin(angle) * dist)
	AudioManager.play_3d(sound, pos, -12.0, 0.08, 60.0)
