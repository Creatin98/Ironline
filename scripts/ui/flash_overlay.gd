class_name FlashOverlay
extends CanvasLayer
## What a flashbang does to the local player: an instant white-out (as long as the light is strong), then the
## picture comes back blurred, washed out and brightened while a dark afterimage of the light burns on the retina
## and slowly fades; at the same time the world sounds muffle and a tinnitus whistle rings (AudioManager).
## Strength and duration come from FlashMath (distance, view direction, walls in between).

const SHADER := preload("res://assets/shaders/flash_blind.gdshader")
const ATTACK_TIME := 0.04

var rect: ColorRect
var intensity: float = 0.0
## Elapsed seconds of the running effect, < 0 = none.
var elapsed: float = -1.0
var blind_time: float = 0.0
var fade_time: float = 0.0
## Current impairment 0..1 (1 = completely blind and deaf).
var level: float = 0.0

var _material: ShaderMaterial
var replay_driven: bool = false # a killcam shows the killer's flash: driven by the recording, not by the local player


func _ready() -> void:
	layer = 70
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	rect.material = _material
	rect.visible = false
	add_child(rect)
	GameEvents.flashbang_exploded.connect(_on_flashbang)


func _exit_tree() -> void:
	AudioManager.set_flash_effect(0.0) # never leave the sound muffled


func is_active() -> bool:
	return elapsed >= 0.0


func _on_flashbang(center: Vector3, _thrower_id: int) -> void:
	var me := MatchManager.get_local_participant()
	if me == null or not me.alive or me.node == null or not is_instance_valid(me.node):
		return
	var pl := me.node as Player
	if pl == null or pl.replay_mode:
		return
	var i := FlashMath.intensity(pl.get_world_3d().direct_space_state, center, pl.head.get_aim_origin(), pl.head.get_aim_direction())
	if i < FlashMath.MIN_INTENSITY:
		return
	trigger(i, _screen_position(pl, center))


## Starts (or renews) the effect with strength `i`; a weaker flash never shortens a stronger one that is still running.
func trigger(i: float, spot: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if is_active() and level >= i:
		return
	intensity = clampf(i, 0.0, 1.0)
	blind_time = FlashMath.blind_time(intensity)
	fade_time = FlashMath.fade_time(intensity)
	elapsed = 0.0
	_material.set_shader_parameter("spot", spot if spot.x >= 0.0 else Vector2(0.5, 0.5))
	_material.set_shader_parameter("spot_size", 0.12 + 0.12 * intensity)
	_material.set_shader_parameter("spot_alpha", 0.0)
	rect.visible = true
	AudioManager.restart_flash_ring()
	var me := MatchManager.get_local_participant()
	if me != null and me.node != null and is_instance_valid(me.node):
		(me.node as Player).head.add_shake(0.5 * intensity)


## Where the light was on the screen (0..1); negative = behind us (no afterimage then).
func _screen_position(pl: Player, center: Vector3) -> Vector2:
	var cam := pl.get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(center):
		return Vector2(-1.0, -1.0)
	var size := pl.get_viewport().get_visible_rect().size
	var p := cam.unproject_position(center) / size
	return Vector2(clampf(p.x, 0.05, 0.95), clampf(p.y, 0.05, 0.95))


## Killcam: the recorded flash state of the killer (age since the hit, intensity) - the same picture as in the real view.
func replay_drive(age: float, i: float) -> void:
	if age < 0.0:
		if replay_driven:
			clear()
		return
	if not replay_driven or absf(intensity - i) > 0.001:
		intensity = clampf(i, 0.0, 1.0)
		blind_time = FlashMath.blind_time(intensity)
		fade_time = FlashMath.fade_time(intensity)
		_material.set_shader_parameter("spot", Vector2(0.5, 0.4))
		_material.set_shader_parameter("spot_size", 0.12 + 0.12 * intensity)
	replay_driven = true
	elapsed = age
	rect.visible = true
	update_visuals()


func clear() -> void:
	replay_driven = false
	elapsed = -1.0
	level = 0.0
	if rect != null:
		rect.visible = false
	AudioManager.set_flash_effect(0.0)


## Impairment curve: 1 during the whiteout, then a quick drop that eases out.
func level_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < blind_time:
		return minf(1.0, t / ATTACK_TIME)
	var u := (t - blind_time) / maxf(fade_time, 0.01)
	if u >= 1.0:
		return 0.0
	return pow(1.0 - u, 1.7)


func _process(delta: float) -> void:
	if replay_driven or not is_active():
		return
	var me := MatchManager.get_local_participant()
	if me == null or not me.alive or MatchManager.state == MatchManager.State.ENDED:
		clear() # dead / round over: no flash in the killcam or on the results
		return
	elapsed += delta
	if elapsed > blind_time + fade_time * 1.3:
		clear()
		return
	update_visuals()


## Sets the shader and the sound from the current `elapsed` (also used by the screenshot tool).
func update_visuals() -> void:
	level = level_at(elapsed)
	var white := pow(clampf((level - 0.12) / 0.88, 0.0, 1.0), 0.8)
	_material.set_shader_parameter("white", white)
	_material.set_shader_parameter("blur", pow(level, 0.9))
	_material.set_shader_parameter("wash", level)
	# the afterimage appears when the white recedes and outlasts the picture's recovery
	var after_u := clampf((elapsed - blind_time * 0.7) / maxf(fade_time * 1.3, 0.01), 0.0, 1.0)
	var after := intensity * (1.0 - smoothstep(0.35, 1.0, after_u)) * smoothstep(0.0, 0.18, after_u)
	_material.set_shader_parameter("spot_alpha", clampf(after * 0.9, 0.0, 0.9))
	# sound: the muffling and the ringing last a bit longer than the sight
	var audio_u := clampf((elapsed - blind_time) / maxf(fade_time * 1.25, 0.01), 0.0, 1.0)
	var audio_level := 1.0 if elapsed < blind_time else pow(1.0 - audio_u, 1.5)
	AudioManager.set_flash_effect(audio_level * (0.35 + 0.65 * intensity))
