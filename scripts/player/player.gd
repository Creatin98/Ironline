class_name Player
extends CharacterBody3D
## First-person character shared by humans and bots. Movement, crouch, sprint,
## damage and death live here; weapons live in WeaponManager; input comes from
## a controller node that writes into `input`.

signal died(victim_id: int, killer_id: int, weapon_id: String, headshot: bool)
signal respawned

const WALK_SPEED := 5.6
const SPRINT_SPEED := 7.7
const CROUCH_SPEED := 2.9
const JUMP_VELOCITY := 5.6
const GRAVITY := 15.0
const GROUND_ACCEL := 14.0
const GROUND_DECEL := 16.0
const AIR_ACCEL := 3.5
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const EYE_BELOW_TOP := 0.18
const HEADSHOT_ZONE := 0.36
const SPRINT_FIRE_DELAY := 0.22
const LAND_SOUND_SPEED := 4.0

var participant_id: int = 0
var team: int = Teams.Team.NONE
var is_local: bool = false
var is_bot: bool = false
var display_name: String = "Spieler"
var class_data: ClassData

var input: PlayerInputState = PlayerInputState.new()
var alive: bool = false
var controls_enabled: bool = true
var is_sprinting: bool = false
var is_crouching: bool = false
var is_aiming: bool = false
var current_height: float = STAND_HEIGHT
var last_look_delta: Vector2 = Vector2.ZERO
var horizontal_speed: float = 0.0
var _look_accum: Vector2 = Vector2.ZERO

# --- networking ---
## Server: last input sequence number processed for this (remote) player.
var remote_input_seq: int = 0
## Client (local player): sequence number of the input sent this tick.
var pending_input_seq: int = 0
var _remote_move: Vector2 = Vector2.ZERO
var _remote_yaw: float = 0.0
var _remote_pitch: float = 0.0
var _remote_held: int = 0
var _remote_actions: int = 0
var _remote_last_msec: int = 0
var _remote_has_input: bool = false
var _pos_history: Dictionary = {} # seq -> position (client prediction history)
var _net_has: bool = false
var _net_pos: Vector3 = Vector3.ZERO
var _net_vel: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0
var _net_pitch: float = 0.0
var _net_on_floor: bool = true
var _net_time: float = 0.0

@onready var head: PlayerCamera = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_manager: WeaponManager = $Head/Camera3D/WeaponManager
@onready var health: Health = $Health
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var body: Node3D = $Body
@onready var torso_mesh: MeshInstance3D = $Body/Torso
@onready var head_mesh: MeshInstance3D = $Body/HeadMesh
@onready var hands: Node3D = $Body/Hands
@onready var name_label: Label3D = $Body/NameLabel
@onready var human_controller: HumanController = $HumanController

var _was_on_floor: bool = true
var _prev_vertical_velocity: float = 0.0
var _step_distance: float = 0.0
var _sprint_block_timer: float = 0.0
var _team_material: StandardMaterial3D
var _death_tween: Tween


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1 | 2
	# each player needs its own capsule so crouching one does not shrink all
	collision_shape.shape = collision_shape.shape.duplicate()
	_set_height(STAND_HEIGHT)
	_team_material = StandardMaterial3D.new()
	_team_material.roughness = 0.8
	torso_mesh.material_override = _team_material
	head_mesh.material_override = _team_material
	set_physics_process(false)
	set_process(false)
	body.visible = false


## Called once right after instancing.
func setup(participant: Participant, new_class: ClassData, local: bool) -> void:
	participant_id = participant.id
	team = participant.team
	is_bot = participant.is_bot
	display_name = participant.display_name
	is_local = local
	class_data = new_class
	name = "Player_%d" % participant_id
	_team_material.albedo_color = Teams.color_of(team)
	name_label.text = display_name
	name_label.modulate = Teams.color_of(team)
	name_label.visible = not is_local
	head.setup_local(is_local)
	weapon_manager.setup(self, class_data, is_local)
	if is_local:
		# own body: only its shadow is rendered so the camera never clips into it
		torso_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		head_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		hands.visible = false
		human_controller.activate()
	else:
		human_controller.deactivate()
	health.died.connect(_on_health_died)
	health.health_changed.connect(_on_health_changed)
	set_process(true)


## True if this machine simulates the movement of this player (the local player,
## and on the server/offline host also every bot and every remote human).
func has_movement_authority() -> bool:
	if is_local:
		return true
	return MatchManager.is_authority() and (is_bot or NetworkManager.is_host())


## Server only: a human on another machine, driven by received input.
func is_remote_human_on_server() -> bool:
	return not is_local and not is_bot and NetworkManager.is_host()


# ----------------------------------------------------------------------------- spawn / death

func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = Transform3D(Basis.IDENTITY, spawn_transform.origin)
	rotation.y = spawn_transform.basis.get_euler().y
	head.set_pitch(0.0)
	head.recoil_offset = Vector2.ZERO
	velocity = Vector3.ZERO
	alive = true
	is_sprinting = false
	is_crouching = false
	is_aiming = false
	controls_enabled = true
	_set_height(STAND_HEIGHT)
	collision_layer = 2
	collision_mask = 1 | 2
	_kill_death_tween()
	body.visible = true
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	health.reset()
	weapon_manager.reset_for_spawn()
	input.clear_all()
	_pos_history.clear()
	_net_has = false
	_remote_has_input = false
	_remote_actions = 0
	set_physics_process(true)
	if is_local:
		GameEvents.local_player_spawned.emit(self)
		GameEvents.local_health_changed.emit(health.health, health.max_health)
	respawned.emit()


func _on_health_died(attacker_id: int, weapon_id: String, headshot: bool) -> void:
	if not alive:
		return
	alive = false
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	input.clear_all()
	weapon_manager.on_owner_died()
	is_aiming = false
	is_sprinting = false
	_play_death_animation()
	if is_local:
		AudioManager.play_2d("death", -2.0)
	else:
		AudioManager.play_3d("death", global_position + Vector3.UP, -4.0)
	died.emit(participant_id, attacker_id, weapon_id, headshot)


func _play_death_animation() -> void:
	_kill_death_tween()
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	var dir := 1.0 if randf() > 0.5 else -1.0
	_death_tween.tween_property(body, "rotation", Vector3(0.0, 0.0, deg_to_rad(88.0 * dir)), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(body, "position", Vector3(0.0, 0.25, 0.0), 0.45)
	_death_tween.chain().tween_interval(4.0)
	# the respawn (3 s) comes before this; never hide a living body
	_death_tween.chain().tween_callback(func() -> void:
		if not alive:
			body.hide())


func _kill_death_tween() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null


## Authoritative damage entry point used by weapons and grenades.
## Returns true if this damage killed the player.
func take_damage(amount: float, attacker_id: int, weapon_id: String, hit_position: Vector3, headshot: bool, source_position: Vector3) -> bool:
	if not alive or not MatchManager.is_authority():
		return false
	if MatchManager.state != MatchManager.State.RUNNING:
		return false
	if MatchManager.state == MatchManager.State.ENDED:
		return false
	var attacker := MatchManager.get_participant(attacker_id)
	var me := MatchManager.get_participant(participant_id)
	if attacker != null and me != null and attacker_id != participant_id and not attacker.is_enemy_of(me):
		return false # kein Friendly Fire
	var killed := health.apply_damage(amount, attacker_id, weapon_id, headshot)
	if is_local:
		GameEvents.local_player_damaged.emit(amount, source_position)
		head.add_shake(0.35)
		if not killed:
			AudioManager.play_2d("hurt", -6.0, 0.1)
	elif not is_bot and NetworkManager.is_host():
		NetworkManager.send_damage_feedback(participant_id, amount, source_position, health.health)
	return killed


func _on_health_changed(current: float, maximum: float) -> void:
	if is_local:
		GameEvents.local_health_changed.emit(current, maximum)


## World y above which a hit counts as a headshot.
func get_headshot_y() -> float:
	return global_position.y + current_height - HEADSHOT_ZONE


func get_center() -> Vector3:
	return global_position + Vector3(0.0, current_height * 0.55, 0.0)


func get_eye_position() -> Vector3:
	return head.global_position


func get_ads_sensitivity_scale() -> float:
	if weapon_manager == null or not is_aiming:
		return 1.0
	var w := weapon_manager.get_current_weapon()
	if w == null:
		return 1.0
	return clampf(w.data.ads_fov / GameSettings.fov, 0.45, 1.0)


# ----------------------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if not alive or not has_movement_authority():
		return
	if is_remote_human_on_server():
		_apply_remote_input()
	if not controls_enabled:
		input.clear_all()
	_update_states(delta)
	if input.look_delta != Vector2.ZERO:
		# bots (and later remote input) deliver look deltas per physics tick
		apply_look(input.look_delta)
	_move(delta)
	weapon_manager.process_input(input, delta)
	input.clear_one_shot()
	if is_local and NetworkManager.is_client():
		_pos_history[pending_input_seq] = global_position
		if _pos_history.size() > 240:
			_pos_history.erase(_pos_history.keys()[0])


## Immediate look rotation (used by the mouse every render frame for zero latency).
func apply_look(delta_look: Vector2) -> void:
	if not alive or not controls_enabled:
		return
	head.apply_look(delta_look)
	_look_accum += delta_look


func _process(delta: float) -> void:
	if head == null:
		return
	if alive and not has_movement_authority():
		_interpolate_remote(delta)
	last_look_delta = _look_accum
	_look_accum = Vector2.ZERO
	var w := weapon_manager.get_current_weapon()
	var ads_fov := w.data.ads_fov if w else GameSettings.fov
	var ads_time := w.data.ads_time if w else 0.2
	head.update_camera(delta, horizontal_speed, is_on_floor(), current_height - EYE_BELOW_TOP, is_aiming, ads_fov, ads_time, is_sprinting)


func _update_states(delta: float) -> void:
	_sprint_block_timer = maxf(0.0, _sprint_block_timer - delta)
	if input.fire_held or input.fire_pressed:
		_sprint_block_timer = SPRINT_FIRE_DELAY
	# crouch
	if input.crouch and not is_crouching:
		is_crouching = true
		_set_height(CROUCH_HEIGHT)
	elif not input.crouch and is_crouching and _can_stand_up():
		is_crouching = false
		_set_height(STAND_HEIGHT)
	# sprint: nur vorwaerts, nicht geduckt, nicht beim Zielen/Schiessen
	var wants_sprint := input.sprint and input.move.y > 0.4 and not is_crouching and not input.aim and _sprint_block_timer <= 0.0
	wants_sprint = wants_sprint and not weapon_manager.is_busy()
	is_sprinting = wants_sprint
	# aim
	is_aiming = input.aim and not is_sprinting and weapon_manager.can_aim()


func _move(delta: float) -> void:
	var yaw_basis := Basis(Vector3.UP, rotation.y)
	var wish_dir := Vector3.ZERO
	if input.move.length_squared() > 0.001:
		wish_dir = (yaw_basis * Vector3(input.move.x, 0.0, -input.move.y)).normalized()
	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
	var w := weapon_manager.get_current_weapon()
	if w:
		speed *= w.data.move_speed_multiplier
		if is_aiming:
			speed *= w.data.ads_speed_multiplier
	var target := wish_dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var on_floor := is_on_floor()
	if on_floor:
		var accel := GROUND_ACCEL if wish_dir.length_squared() > 0.0 else GROUND_DECEL
		horizontal = horizontal.move_toward(target, accel * speed * delta)
	else:
		horizontal = horizontal.move_toward(target, AIR_ACCEL * delta * speed)
		velocity.y -= GRAVITY * delta
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if on_floor and input.jump_pressed:
		velocity.y = JUMP_VELOCITY
		if is_local:
			AudioManager.play_2d("jump", -8.0)
		else:
			AudioManager.play_3d("jump", global_position, -8.0)
	_prev_vertical_velocity = velocity.y
	move_and_slide()
	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	_handle_landing()
	_handle_footsteps(delta, is_on_floor())


func _handle_landing() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var fall_speed := -_prev_vertical_velocity
		head.on_landed(fall_speed)
		if fall_speed > LAND_SOUND_SPEED:
			if is_local:
				AudioManager.play_2d("land", -6.0)
			else:
				AudioManager.play_3d("land", global_position, -6.0)
	_was_on_floor = on_floor


func _handle_footsteps(delta: float, on_floor: bool) -> void:
	if not on_floor or horizontal_speed < 1.0:
		_step_distance = 0.0
		return
	_step_distance += horizontal_speed * delta
	var stride := 2.6 if is_sprinting else 2.1
	if is_crouching:
		stride = 1.7
	if _step_distance >= stride:
		_step_distance = 0.0
		var sfx := "footstep_%d" % (randi() % 4 + 1)
		var vol := -14.0 if is_crouching else -7.0
		AudioManager.play_3d(sfx, global_position, vol, 0.1, 30.0)


func _set_height(h: float) -> void:
	current_height = h
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = h
	collision_shape.position.y = h * 0.5
	torso_mesh.scale.y = h / STAND_HEIGHT
	torso_mesh.position.y = (h - 0.3) * 0.5
	head_mesh.position.y = h - 0.18


func _can_stand_up() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, CROUCH_HEIGHT - 0.1, 0.0)
	var to := global_position + Vector3(0.0, STAND_HEIGHT + 0.05, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


## Smoothly turns the view towards a world position (death camera).
func face_towards(target: Vector3) -> void:
	var dir := (target - head.global_position)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := asin(clampf(dir.y, -1.0, 1.0))
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(func(v: float) -> void: rotation.y = v, rotation.y, lerp_angle(rotation.y, yaw, 1.0), 0.5)
	tween.tween_method(head.set_pitch, head.pitch, pitch, 0.5)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		input.clear_all()
		is_sprinting = false
		is_aiming = false


# ----------------------------------------------------------------------------- networking

## Server: store the latest input packet of the owning client.
func set_remote_input(seq: int, move: Vector2, yaw: float, pitch: float, held: int) -> void:
	if not (is_finite(move.x) and is_finite(move.y) and is_finite(yaw) and is_finite(pitch)):
		return
	_remote_move = move.limit_length(1.0)
	_remote_yaw = yaw
	_remote_pitch = clampf(pitch, -PlayerCamera.PITCH_LIMIT, PlayerCamera.PITCH_LIMIT)
	_remote_held = held
	_remote_last_msec = Time.get_ticks_msec()
	_remote_has_input = true
	remote_input_seq = seq


func add_remote_actions(actions: int) -> void:
	_remote_actions |= actions


func _apply_remote_input() -> void:
	if not _remote_has_input:
		return
	var stale := Time.get_ticks_msec() - _remote_last_msec > 300
	input.move = Vector2.ZERO if stale else _remote_move
	var held := 0 if stale else _remote_held
	input.sprint = held & NetworkManager.HELD_SPRINT != 0
	input.crouch = held & NetworkManager.HELD_CROUCH != 0
	input.aim = held & NetworkManager.HELD_AIM != 0
	input.fire_held = held & NetworkManager.HELD_FIRE != 0
	rotation.y = _remote_yaw
	head.set_pitch(_remote_pitch)
	var a := _remote_actions
	_remote_actions = 0
	if a & NetworkManager.ACT_FIRE:
		input.fire_pressed = true
	if a & NetworkManager.ACT_JUMP:
		input.jump_pressed = true
	if a & NetworkManager.ACT_RELOAD:
		input.reload_pressed = true
	if a & NetworkManager.ACT_GRENADE:
		input.grenade_pressed = true
	if a & NetworkManager.ACT_SWITCH:
		input.switch_pressed = true
	if a & NetworkManager.ACT_PRIMARY:
		input.select_primary = true
	if a & NetworkManager.ACT_SECONDARY:
		input.select_secondary = true


## Client: a snapshot of another player (or a bot) arrived.
func push_snapshot(pos: Vector3, yaw: float, pitch: float, vel: Vector3, flags: int, weapon_index: int) -> void:
	_net_pos = pos
	_net_vel = vel
	_net_yaw = yaw
	_net_pitch = pitch
	_net_on_floor = flags & NetworkManager.SNAP_ON_FLOOR != 0
	_net_time = Time.get_ticks_msec() / 1000.0
	is_sprinting = flags & NetworkManager.SNAP_SPRINT != 0
	is_aiming = flags & NetworkManager.SNAP_AIM != 0
	var crouch := flags & NetworkManager.SNAP_CROUCH != 0
	if crouch != is_crouching:
		is_crouching = crouch
		_set_height(CROUCH_HEIGHT if crouch else STAND_HEIGHT)
	weapon_manager.set_remote_weapon_index(weapon_index)
	if not _net_has:
		_net_has = true
		global_position = pos
		rotation.y = yaw


func _interpolate_remote(delta: float) -> void:
	if not _net_has:
		return
	var age := clampf(Time.get_ticks_msec() / 1000.0 - _net_time, 0.0, 0.12)
	var target := _net_pos + _net_vel * age
	if global_position.distance_to(target) > 4.0:
		global_position = target
	else:
		var f := 1.0 - exp(-14.0 * delta)
		global_position = global_position.lerp(target, f)
	rotation.y = lerp_angle(rotation.y, _net_yaw, 1.0 - exp(-16.0 * delta))
	head.set_pitch(lerpf(head.pitch, _net_pitch, 1.0 - exp(-16.0 * delta)))
	horizontal_speed = Vector2(_net_vel.x, _net_vel.z).length()
	_handle_footsteps(delta, _net_on_floor)


## Client: the server's position of the local player; correct prediction errors.
func reconcile_with_server(seq: int, server_pos: Vector3, server_vel: Vector3) -> void:
	if not alive or not _pos_history.has(seq):
		return
	var err: Vector3 = server_pos - _pos_history[seq]
	var d := err.length()
	if d > 3.0:
		global_position += err
		velocity = server_vel
		_pos_history.clear()
	elif d > 0.25:
		global_position += err * 0.25


## Client: health/ammo values owned by the server (10 Hz).
func apply_owner_state(new_health: float, magazine: int, reserve: int, grenades: int, weapon_index: int) -> void:
	if not alive:
		return
	health.set_remote_health(new_health)
	weapon_manager.apply_server_ammo(weapon_index, magazine, reserve, grenades)


## Client: the server says we took damage (feedback only, health comes from the server).
func remote_damage_feedback(amount: float, source_position: Vector3, new_health: float) -> void:
	if not alive:
		return
	health.set_remote_health(new_health)
	GameEvents.local_player_damaged.emit(amount, source_position)
	head.add_shake(0.35)
	AudioManager.play_2d("hurt", -6.0, 0.1)

