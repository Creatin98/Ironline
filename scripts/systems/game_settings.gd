extends Node
## Autoload "GameSettings": persistent player settings stored in user://settings.cfg.
## All gameplay/UI systems read from here; call save() after changing values.

signal settings_changed

const SAVE_PATH := "user://settings.cfg"
## 2: ambience sounds became opt-in (silent by default); older files get that default where they still hold the old 100 %.
const SETTINGS_VERSION := 2

## Tests switch this off so they never overwrite the player's real settings.
var persist: bool = true

# Controls
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var fov: float = 80.0

# Video
var resolution: Vector2i = Vector2i(1920, 1080)
var window_mode: int = 0 # 0 = Vollbild, 1 = Fenster, 2 = Randlos
var fullscreen: bool = true # derived from window_mode (kept for older code)
var vsync: bool = true
var fps_limit: int = 0 # 0 = unbegrenzt
var graphics_quality: int = 2 # preset: 0 = niedrig, 1 = mittel, 2 = hoch, 3 = benutzerdefiniert
var render_scale: float = 1.0 # 3D resolution scale
var antialiasing: int = 2 # 0 = aus, 1 = MSAA 2x, 2 = MSAA 4x, 3 = MSAA 8x (always with FXAA)
var texture_quality: int = 2 # 0..2: anisotropic filtering 1x / 4x / 16x
var shadow_quality: int = 3 # 0 = aus, 1..3 = niedrig..hoch
var effects_quality: int = 2 # 0..2: amount of particles
var view_distance: int = 3 # 0..3
var post_processing: bool = true # glow, ambient occlusion, colour adjustments

# Audio: linear volume (0..1) per category id, see AudioCategories
var volumes: Dictionary = AudioCategories.default_volumes()

# HUD / Kamera
var hud_scale: float = 1.0
var hud_margin: float = 14.0 # distance of the HUD blocks to the screen edge (pixels, 1920x1080 reference)
var hud_offsets: Dictionary = {} # element name -> Vector2 offset set in the HUD editor
var camera_bob: bool = true
var weapon_sway: bool = true
var screen_shake: bool = true
var show_fps: bool = false
var killcams: bool = true # killcam after death + last kill cam at the end of a round
var show_hud: bool = true
var show_minimap: bool = true
var show_killfeed: bool = true
var show_crosshair: bool = true
var show_hit_markers: bool = true # hitmarker / kill marker
var show_damage_indicators: bool = true # arrows showing where damage came from
var show_blood_overlay: bool = true # blood splatter on the screen
var ads_sensitivity: float = 1.0 # mouse sensitivity multiplier while aiming down the sights

# Spieler
var player_name: String = "Spieler"
var preferred_team: int = 1 # Teams.Team.RED
var preferred_class_id: String = "assault"

# Netzwerk
var last_address: String = "127.0.0.1"
var last_port: int = 7777

## Boolean HUD options stored in the "hud" section.
const HUD_TOGGLES: Array[String] = ["show_hud", "show_minimap", "show_killfeed", "show_crosshair", "show_hit_markers", "show_damage_indicators", "show_blood_overlay"]
const WINDOW_MODES: Array[String] = ["Vollbild", "Fenster", "Randlos"]
const FPS_LIMITS: Array[int] = [0, 30, 60, 90, 120, 144, 165, 240]
const ANTIALIASING_NAMES: Array[String] = ["Aus", "MSAA 2x", "MSAA 4x", "MSAA 8x"]
const QUALITY_NAMES: Array[String] = ["Niedrig", "Mittel", "Hoch"]
const SHADOW_NAMES: Array[String] = ["Aus", "Niedrig", "Mittel", "Hoch"]
const VIEW_DISTANCES: Array[float] = [90.0, 160.0, 280.0, 500.0]
const VIEW_DISTANCE_NAMES: Array[String] = ["Kurz", "Mittel", "Weit", "Maximal"]
## Quality presets: values for the individual graphics options.
const GRAPHICS_PRESETS: Array[Dictionary] = [
	{"render_scale": 0.8, "antialiasing": 0, "texture_quality": 0, "shadow_quality": 1, "effects_quality": 0, "view_distance": 1, "post_processing": false},
	{"render_scale": 1.0, "antialiasing": 1, "texture_quality": 1, "shadow_quality": 2, "effects_quality": 1, "view_distance": 2, "post_processing": true},
	{"render_scale": 1.0, "antialiasing": 2, "texture_quality": 2, "shadow_quality": 3, "effects_quality": 2, "view_distance": 3, "post_processing": true},
]

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]


func _ready() -> void:
	load_settings()
	apply()


func load_settings(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = cfg.get_value("controls", "fov", fov)
	resolution = cfg.get_value("video", "resolution", resolution)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	window_mode = cfg.get_value("video", "window_mode", 0 if fullscreen else 1)
	vsync = cfg.get_value("video", "vsync", vsync)
	fps_limit = cfg.get_value("video", "fps_limit", fps_limit)
	graphics_quality = cfg.get_value("video", "graphics_quality", graphics_quality)
	render_scale = cfg.get_value("video", "render_scale", render_scale)
	antialiasing = cfg.get_value("video", "antialiasing", antialiasing)
	texture_quality = cfg.get_value("video", "texture_quality", texture_quality)
	shadow_quality = cfg.get_value("video", "shadow_quality", shadow_quality)
	effects_quality = cfg.get_value("video", "effects_quality", effects_quality)
	view_distance = cfg.get_value("video", "view_distance", view_distance)
	post_processing = cfg.get_value("video", "post_processing", post_processing)
	# volumes: older files stored master/music/sfx only
	var legacy := {"master": "master_volume", "music": "music_volume", "sfx": "sfx_volume"}
	for e in AudioCategories.ENTRIES:
		var id: String = e["id"]
		var fallback: float = float(cfg.get_value("audio", legacy[id], volumes[id])) if legacy.has(id) else float(volumes[id])
		volumes[id] = clampf(float(cfg.get_value("audio_volumes", id, fallback)), 0.0, 1.0)
	if int(cfg.get_value("meta", "version", 1)) < 2:
		for e in AudioCategories.ENTRIES:
			if e["group"] == "Umgebung" and e["parent"] == "Ambience" and absf(float(volumes[e["id"]]) - 1.0) < 0.001:
				volumes[e["id"]] = float(e["default"])
	hud_scale = cfg.get_value("hud", "hud_scale", hud_scale)
	hud_margin = cfg.get_value("hud", "hud_margin", hud_margin)
	hud_offsets = cfg.get_value("hud", "hud_offsets", hud_offsets)
	camera_bob = cfg.get_value("hud", "camera_bob", camera_bob)
	weapon_sway = cfg.get_value("hud", "weapon_sway", weapon_sway)
	screen_shake = cfg.get_value("hud", "screen_shake", screen_shake)
	show_fps = cfg.get_value("hud", "show_fps", show_fps)
	killcams = cfg.get_value("hud", "killcams", killcams)
	for key in HUD_TOGGLES:
		set(key, cfg.get_value("hud", key, get(key)))
	ads_sensitivity = cfg.get_value("controls", "ads_sensitivity", ads_sensitivity)
	player_name = cfg.get_value("player", "name", player_name)
	preferred_team = cfg.get_value("player", "team", preferred_team)
	preferred_class_id = cfg.get_value("player", "class_id", preferred_class_id)
	last_address = cfg.get_value("network", "last_address", last_address)
	last_port = cfg.get_value("network", "last_port", last_port)


## `path`: tests write to a separate file; the normal save goes to SAVE_PATH (only if `persist`).
func save(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "fullscreen", window_mode == 0)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "antialiasing", antialiasing)
	cfg.set_value("video", "texture_quality", texture_quality)
	cfg.set_value("video", "shadow_quality", shadow_quality)
	cfg.set_value("video", "effects_quality", effects_quality)
	cfg.set_value("video", "view_distance", view_distance)
	cfg.set_value("video", "post_processing", post_processing)
	for id in volumes:
		cfg.set_value("audio_volumes", id, volumes[id])
	cfg.set_value("hud", "hud_scale", hud_scale)
	cfg.set_value("hud", "hud_margin", hud_margin)
	cfg.set_value("hud", "hud_offsets", hud_offsets)
	cfg.set_value("hud", "camera_bob", camera_bob)
	cfg.set_value("hud", "weapon_sway", weapon_sway)
	cfg.set_value("hud", "screen_shake", screen_shake)
	cfg.set_value("hud", "show_fps", show_fps)
	cfg.set_value("hud", "killcams", killcams)
	for key in HUD_TOGGLES:
		cfg.set_value("hud", key, get(key))
	cfg.set_value("controls", "ads_sensitivity", ads_sensitivity)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "team", preferred_team)
	cfg.set_value("player", "class_id", preferred_class_id)
	cfg.set_value("network", "last_address", last_address)
	cfg.set_value("network", "last_port", last_port)
	if persist or path != SAVE_PATH:
		cfg.save(path)
	apply()


func apply() -> void:
	fullscreen = window_mode == 0
	_apply_window()
	_apply_audio()
	_apply_graphics()
	settings_changed.emit()


func _apply_window() -> void:
	var mode := window_mode
	var wanted := DisplayServer.WINDOW_MODE_FULLSCREEN if mode == 0 else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != wanted:
		DisplayServer.window_set_mode(wanted)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == 2)
	if mode == 1:
		DisplayServer.window_set_size(resolution)
		var screen_size := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen_size - resolution) / 2)
	elif mode == 2:
		DisplayServer.window_set_size(DisplayServer.screen_get_size())
		DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit


## Sets the volume of one sound category (0..1) and applies it to its bus at once.
func set_volume(id: String, value: float) -> void:
	volumes[id] = clampf(value, 0.0, 1.0)
	_set_bus_volume(String(AudioCategories.get_entry(id).get("bus", "")), float(volumes[id]))


func get_volume(id: String) -> float:
	return float(volumes.get(id, AudioCategories.get_entry(id).get("default", 1.0)))


func _apply_audio() -> void:
	AudioCategories.ensure_buses()
	for e in AudioCategories.ENTRIES:
		_set_bus_volume(String(e["bus"]), get_volume(String(e["id"])))


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
	match antialiasing:
		0: vp.msaa_3d = Viewport.MSAA_DISABLED
		1: vp.msaa_3d = Viewport.MSAA_2X
		2: vp.msaa_3d = Viewport.MSAA_4X
		_: vp.msaa_3d = Viewport.MSAA_8X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	match texture_quality:
		0: vp.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED
		1: vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
		_: vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	var atlas: int = [2048, 2048, 4096, 8192][clampi(shadow_quality, 0, 3)]
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	var soft: int = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][clampi(shadow_quality, 0, 3)]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	apply_scene(get_tree().current_scene)


## Applies shadow and post-processing settings to the lights/environment found below `root`
## (a map or the game scene). Original values are remembered, so switching back restores them.
func apply_scene(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is DirectionalLight3D:
			var l := n as DirectionalLight3D
			if not l.has_meta("orig_shadow"):
				l.set_meta("orig_shadow", l.shadow_enabled)
			l.shadow_enabled = bool(l.get_meta("orig_shadow")) and shadow_quality > 0
		elif n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			var env := (n as WorldEnvironment).environment
			if not env.has_meta("orig_post"):
				env.set_meta("orig_post", [env.glow_enabled, env.ssao_enabled, env.adjustment_enabled])
			var orig: Array = env.get_meta("orig_post")
			env.glow_enabled = bool(orig[0]) and post_processing
			env.ssao_enabled = bool(orig[1]) and post_processing and graphics_quality != 0
			env.adjustment_enabled = bool(orig[2]) and post_processing


## Scale for particle counts (impacts, blood, explosions).
func effects_scale() -> float:
	return [0.4, 0.7, 1.0][clampi(effects_quality, 0, 2)]


func view_distance_m() -> float:
	return VIEW_DISTANCES[clampi(view_distance, 0, VIEW_DISTANCES.size() - 1)]


## Fills the individual graphics options from a preset (0..2).
func apply_graphics_preset(preset: int) -> void:
	if preset < 0 or preset >= GRAPHICS_PRESETS.size():
		return
	graphics_quality = preset
	for key in GRAPHICS_PRESETS[preset]:
		set(key, GRAPHICS_PRESETS[preset][key])


func get_resolution_index() -> int:
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i] == resolution:
			return i
	return 2
