extends Node
## Autoload "GameSettings": persistent player settings stored in user://settings.cfg.
## All gameplay/UI systems read from here; call save() after changing values.

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

# Controls
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var fov: float = 80.0

# Video
var resolution: Vector2i = Vector2i(1920, 1080)
var fullscreen: bool = true
var graphics_quality: int = 2 # 0 = niedrig, 1 = mittel, 2 = hoch

# Audio (0..1 linear)
var master_volume: float = 1.0
var music_volume: float = 0.6
var sfx_volume: float = 1.0

# HUD / Kamera
var hud_scale: float = 1.0
var camera_bob: bool = true
var weapon_sway: bool = true
var screen_shake: bool = true
var show_fps: bool = false

# Spieler
var player_name: String = "Spieler"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = cfg.get_value("controls", "fov", fov)
	resolution = cfg.get_value("video", "resolution", resolution)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	graphics_quality = cfg.get_value("video", "graphics_quality", graphics_quality)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	hud_scale = cfg.get_value("hud", "hud_scale", hud_scale)
	camera_bob = cfg.get_value("hud", "camera_bob", camera_bob)
	weapon_sway = cfg.get_value("hud", "weapon_sway", weapon_sway)
	screen_shake = cfg.get_value("hud", "screen_shake", screen_shake)
	show_fps = cfg.get_value("hud", "show_fps", show_fps)
	player_name = cfg.get_value("player", "name", player_name)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("hud", "hud_scale", hud_scale)
	cfg.set_value("hud", "camera_bob", camera_bob)
	cfg.set_value("hud", "weapon_sway", weapon_sway)
	cfg.set_value("hud", "screen_shake", screen_shake)
	cfg.set_value("hud", "show_fps", show_fps)
	cfg.set_value("player", "name", player_name)
	cfg.save(SAVE_PATH)
	apply()


func apply() -> void:
	_apply_window()
	_apply_audio()
	_apply_graphics()
	settings_changed.emit()


func _apply_window() -> void:
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
	if not fullscreen:
		DisplayServer.window_set_size(resolution)
		var screen_size := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen_size - resolution) / 2)


func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("UI", sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _apply_graphics() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	match graphics_quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.scaling_3d_scale = 0.8
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(8192, true)


func get_resolution_index() -> int:
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i] == resolution:
			return i
	return 2
