class_name PlayerCamera
extends Node3D
## The "Head" node: pitch, camera bobbing, recoil, landing dip, screen shake and FOV.
## The Camera3D child is only `current` for the local player.

const PITCH_LIMIT := 1.5533 # 89 Grad in Radiant
const BOB_FREQUENCY := 2.5 # quicker steps ...
const BOB_AMOUNT := 0.026 # ... but a much smaller sway
const SPRINT_FOV_BONUS := 6.0
const SPRINT_BLEND_SPEED := 3.2 # 0 -> 1 in about 0.3 s, same pace as the weapon lowering

@onready var camera: Camera3D = $Camera3D

var player: Player
var pitch: float = 0.0

# Recoil (grad) accumulated by weapons, recovers over time
var recoil_offset: Vector2 = Vector2.ZERO
var recoil_recovery: float = 9.0

var _bob_time: float = 0.0
var _bob_roll: float = 0.0
var _sprint_blend: float = 0.0
var lean: float = 0.0 # corner lean (-1 left .. +1 right): the head moves sideways and tilts


func get_sprint_blend() -> float:
	return _sprint_blend

var _bob_offset: Vector3 = Vector3.ZERO
var _land_dip: float = 0.0
var _land_velocity: float = 0.0
var _shake: float = 0.0
var _fov_kick: float = 0.0
var _ads_blend: float = 0.0
var _base_eye_height: float = 1.62


func _ready() -> void:
	player = get_parent() as Player
	position.y = _base_eye_height


func setup_local(is_local: bool) -> void:
	camera.current = is_local


func apply_look(delta_look: Vector2) -> void:
	# yaw lives on the body, pitch here
	if player:
		player.rotate_y(-delta_look.x)
	pitch = clampf(pitch - delta_look.y, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.x = pitch


func set_pitch(value: float) -> void:
	pitch = clampf(value, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.x = pitch


func add_recoil(vertical_deg: float, horizontal_deg: float, recovery: float) -> void:
	recoil_offset.x = minf(recoil_offset.x + vertical_deg, 6.0) # the view never climbs out of the picture
	recoil_offset.y += horizontal_deg
	recoil_recovery = recovery


func add_shake(strength: float) -> void:
	if GameSettings.screen_shake:
		_shake = maxf(_shake, strength)


## Short zoom-out punch (kill confirmation); decays by itself.
func kick_fov(amount: float) -> void:
	_fov_kick = maxf(_fov_kick, amount)


func on_landed(fall_speed: float) -> void:
	_land_velocity = -clampf(fall_speed * 0.012, 0.0, 0.16)


## Set by the player each frame: knee slide lowers the view and tilts it a little.
var sliding: bool = false
## Death fall (0..1): the view drops to the floor and tips over, driven by a tween in Player.
var fall: float = 0.0
var _slide_blend: float = 0.0


func update_camera(delta: float, horizontal_speed: float, on_floor: bool, eye_height: float, is_aiming: bool, ads_fov: float, ads_time: float, sprinting: bool) -> void:
	# --- eye height (crouch) ---
	camera.far = GameSettings.view_distance_m()
	_slide_blend = move_toward(_slide_blend, 1.0 if sliding else 0.0, delta * 4.0)
	var slide_s := _slide_blend * _slide_blend * (3.0 - 2.0 * _slide_blend)
	position.y = lerpf(position.y, lerpf(eye_height - 0.2 * slide_s, 0.22, fall), 1.0 - exp(-delta * (8.0 if (sliding or slide_s > 0.01) else 14.0)))

	# --- bobbing ---
	var bob_target := Vector3.ZERO
	var roll_target := 0.0
	if GameSettings.camera_bob and on_floor and horizontal_speed > 0.5 and not sliding:
		var speed_ratio := clampf(horizontal_speed / 7.5, 0.0, 1.2)
		_bob_time += delta * BOB_FREQUENCY * (0.8 + speed_ratio * 1.6) * (1.0 + 0.25 * _sprint_blend) * TAU
		var ads_scale := 0.3 if is_aiming else 1.0
		var amount := BOB_AMOUNT * speed_ratio * ads_scale * (1.0 + 0.9 * _sprint_blend)
		bob_target = Vector3(cos(_bob_time * 0.5) * amount * 0.7, sin(_bob_time) * amount, 0.0)
		roll_target = cos(_bob_time * 0.5) * 0.006 * speed_ratio * ads_scale * (1.0 + 1.6 * _sprint_blend)
	else:
		_bob_time = fmod(_bob_time, TAU)
	_bob_roll = lerpf(_bob_roll, roll_target, minf(1.0, delta * 9.0))
	_bob_offset = _bob_offset.lerp(bob_target, minf(1.0, delta * 10.0))

	# --- landing dip (spring) ---
	_land_velocity += (-_land_dip * 220.0) * delta
	_land_velocity *= maxf(0.0, 1.0 - delta * 18.0)
	_land_dip += _land_velocity * delta * 10.0

	# --- recoil recovery ---
	recoil_offset = recoil_offset.lerp(Vector2.ZERO, minf(1.0, delta * recoil_recovery))

	# --- shake ---
	var shake_offset := Vector3.ZERO
	var shake_rot := Vector3.ZERO
	if _shake > 0.001:
		shake_offset = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.03
		shake_rot = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.01
		_shake = maxf(0.0, _shake - delta * 4.0)

	camera.position = _bob_offset + Vector3(lean * 0.13, _land_dip - absf(lean) * 0.02, 0.0) + shake_offset
	camera.rotation = Vector3(deg_to_rad(recoil_offset.x) - 0.3 * fall, deg_to_rad(recoil_offset.y), _bob_roll - 0.04 * slide_s + 1.3 * fall - lean * 0.075) + shake_rot

	# --- FOV ---
	var ads_target := 1.0 if is_aiming else 0.0
	_ads_blend = move_toward(_ads_blend, ads_target, delta / maxf(0.05, ads_time))
	# the sprint zoom eases in and out instead of snapping when sprinting starts/stops
	_sprint_blend = move_toward(_sprint_blend, 1.0 if sprinting else 0.0, delta * SPRINT_BLEND_SPEED)
	var sprint_ease := _sprint_blend * _sprint_blend * (3.0 - 2.0 * _sprint_blend)
	var base_fov := GameSettings.fov + SPRINT_FOV_BONUS * sprint_ease + 5.0 * slide_s
	camera.fov = lerpf(base_fov, ads_fov, _ads_blend) - _fov_kick
	_fov_kick = move_toward(_fov_kick, 0.0, delta * 38.0)


func get_bob_phase() -> float:
	return _bob_time


func get_ads_blend() -> float:
	return _ads_blend


func get_aim_origin() -> Vector3:
	return camera.global_position


func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z
