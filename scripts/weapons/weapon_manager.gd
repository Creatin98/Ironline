class_name WeaponManager
extends Node3D
## Holds the two weapons of a player, handles switching, grenades and the
## procedural view-model motion (hip/ADS position, sway, sprint pose, kick).

enum SwitchState { READY, LOWERING, RAISING }

const GRENADE_SCENE := preload("res://scenes/weapons/grenade.tscn")
const LOWER_TIME := 0.11
const GRENADE_THROW_DELAY := 0.28
const GRENADE_TOTAL_TIME := 0.75
const GRENADE_SPEED := 17.0

var player: Player
var is_local: bool = false
var weapons: Array[Weapon] = []
var current_index: int = 0
var grenades: int = 2
var max_grenades: int = 2

@onready var holder: Node3D = $Holder

var _switch_state: int = SwitchState.READY
var _switch_timer: float = 0.0
var _pending_index: int = -1
var _sway: Vector2 = Vector2.ZERO
var _kick: float = 0.0
var _kick_rot: float = 0.0
var _sprint_blend: float = 0.0
var _slide_blend: float = 0.0
var _ads_blend: float = 0.0
var _lower_blend: float = 0.0
var _walk_amp: float = 0.0
var _grenade_timer: float = 0.0
var _grenade_thrown: bool = true
var _tp_models: Array[Node3D] = []
var _tp_rigs: Array = [] # ReloadRig per third-person model
var _tp_reload_progress: float = -1.0 # in cycles; < 0 = idle
var _tp_reload_cycles: int = 1
var _tp_reload_silent: bool = false
var _tp_flashes: Array[Node3D] = []
var _flinch_t: float = 99.0
var _flinch_side: float = 0.0
var _flinch_amp: float = 0.0
var _last_mag: int = -1
var _last_reserve: int = -1


func setup(new_player: Player, class_data: ClassData, local: bool) -> void:
	player = new_player
	is_local = local
	if is_local and not GameEvents.local_player_damaged.is_connected(_on_owner_damaged):
		GameEvents.local_player_damaged.connect(_on_owner_damaged)
	for w in weapons:
		w.queue_free()
	weapons.clear()
	for m in _tp_models:
		m.queue_free()
	_tp_models.clear()
	_tp_rigs.clear()
	_tp_reload_progress = -1.0
	_tp_flashes.clear()
	max_grenades = class_data.grenades
	grenades = max_grenades
	for data in [class_data.primary, class_data.secondary]:
		var weapon := Weapon.new()
		weapon.name = data.weapon_id
		holder.add_child(weapon)
		weapon.setup(data, player, is_local)
		weapon.visible = false
		weapons.append(weapon)
		# third-person copy in the hands of the body
		var tp: Node3D = data.model_scene.instantiate()
		tp.visible = false
		player.hands.add_child(tp)
		_tp_models.append(tp)
		_tp_rigs.append(ReloadRig.create(tp, data.reload_style))
		var tp_muzzle := tp.get_node_or_null("Muzzle")
		if tp_muzzle != null:
			var flash: Node3D = Weapon.MUZZLE_FLASH_SCENE.instantiate()
			tp_muzzle.add_child(flash)
			_tp_flashes.append(flash)
		else:
			_tp_flashes.append(null)
	current_index = 0
	_switch_state = SwitchState.READY
	_show_weapon(current_index, true)


func reset_for_spawn() -> void:
	grenades = max_grenades
	for w in weapons:
		w.fill_ammo()
		w.holster()
	current_index = 0
	_pending_index = -1
	_switch_state = SwitchState.READY
	_grenade_timer = 0.0
	_grenade_thrown = true
	_show_weapon(current_index, true)
	_emit_local_state()


func on_owner_died() -> void:
	_stop_tp_reload()
	for w in weapons:
		w.cancel_actions()
	visible = false
	for m in _tp_models:
		m.visible = false


func get_current_weapon() -> Weapon:
	if weapons.is_empty():
		return null
	return weapons[current_index]


## Being shot makes the view model jerk (also while aiming down the sights).
func _on_owner_damaged(amount: float, source_position: Vector3) -> void:
	if player == null or not player.alive:
		return
	var to := source_position - player.global_position
	var local_dir := Basis(Vector3.UP, player.rotation.y).inverse() * to
	_flinch_side = clampf(local_dir.x / maxf(0.5, absf(local_dir.x) + absf(local_dir.z)), -1.0, 1.0)
	if absf(_flinch_side) < 0.15:
		_flinch_side = randf_range(-0.5, 0.5)
	_flinch_amp = clampf(amount / 35.0, 0.5, 1.6)
	_flinch_t = 0.0


func is_busy() -> bool:
	## Busy = reloading / switching / throwing; blocks sprint start.
	var w := get_current_weapon()
	if w and w.is_reloading():
		return true
	return _switch_state != SwitchState.READY or _grenade_timer > 0.0


## Sprint may start unless the weapon is being lowered (raising is fine).
func is_switch_ready_for_sprint() -> bool:
	return _switch_state != SwitchState.LOWERING


func can_aim() -> bool:
	return _switch_state == SwitchState.READY and _grenade_timer <= 0.0


func _show_weapon(index: int, instant: bool) -> void:
	visible = is_local
	for i in weapons.size():
		if i != index:
			weapons[i].holster()
		if i < _tp_models.size():
			_tp_models[i].visible = i == index
	var w := weapons[index]
	w.draw()
	if is_local:
		GameEvents.local_weapon_changed.emit(w)
		GameEvents.local_ammo_changed.emit(w.magazine, w.reserve)


func _emit_local_state() -> void:
	if not is_local:
		return
	var w := get_current_weapon()
	if w:
		GameEvents.local_weapon_changed.emit(w)
		GameEvents.local_ammo_changed.emit(w.magazine, w.reserve)
	GameEvents.local_grenades_changed.emit(grenades)


# ----------------------------------------------------------------------------- input

func process_input(input: PlayerInputState, delta: float) -> void:
	var w := get_current_weapon()
	if w == null:
		return
	_update_switch(delta)
	_update_grenade(delta)
	w.update(delta)

	# switching cancels a grenade that has not been thrown yet, and may interrupt the raise (spam switching)
	if _grenade_timer > 0.0 and not _grenade_thrown and (input.select_primary or input.select_secondary or input.switch_pressed):
		cancel_grenade(true)
	if _grenade_timer <= 0.0 and (_switch_state == SwitchState.READY or _switch_state == SwitchState.RAISING):
		if _switch_state == SwitchState.READY and input.grenade_pressed and grenades > 0 and not w.is_reloading():
			_begin_grenade()
			return
		if input.select_primary and current_index != 0:
			begin_switch(0)
		elif input.select_secondary and current_index != 1:
			begin_switch(1)
		elif input.switch_pressed:
			begin_switch((current_index + 1) % weapons.size())
		if input.reload_pressed and _switch_state == SwitchState.READY:
			w.start_reload()
	if _switch_state == SwitchState.READY and _grenade_timer <= 0.0 and not player.is_sprinting:
		var wants_fire := input.fire_held if w.data.automatic else input.fire_pressed
		if wants_fire:
			var move_ratio := clampf(player.horizontal_speed / Player.SPRINT_SPEED, 0.0, 1.0)
			w.try_fire(player.is_aiming, move_ratio, not player.is_on_floor(), player.is_crouching)
	if is_local and (w.magazine != _last_mag or w.reserve != _last_reserve):
		_last_mag = w.magazine
		_last_reserve = w.reserve
		GameEvents.local_ammo_changed.emit(w.magazine, w.reserve)


func begin_switch(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == current_index:
		return
	_stop_tp_reload()
	var w := get_current_weapon()
	w.cancel_actions()
	_pending_index = index
	_switch_state = SwitchState.LOWERING
	_switch_timer = LOWER_TIME
	if NetworkManager.is_host():
		NetworkManager.broadcast_weapon_event(player.participant_id, "switch")
	if is_local:
		AudioManager.play_2d("weapon_switch", -6.0)
	else:
		AudioManager.play_3d("weapon_switch", global_position, -10.0)


func _update_switch(delta: float) -> void:
	if _switch_state == SwitchState.READY:
		return
	_switch_timer -= delta
	if _switch_state == SwitchState.LOWERING and _switch_timer <= 0.0:
		get_current_weapon().holster()
		current_index = _pending_index
		_show_weapon(current_index, false)
		_switch_state = SwitchState.RAISING
		_switch_timer = get_current_weapon().data.draw_time
	elif _switch_state == SwitchState.RAISING and _switch_timer <= 0.0:
		_switch_state = SwitchState.READY


## Sprint cancels reload and grenade animations (Call-of-Duty style).
func cancel_for_sprint() -> void:
	var w := get_current_weapon()
	if w and w.is_reloading():
		w.cancel_actions()
		_stop_tp_reload()
	if _grenade_timer > 0.0:
		cancel_grenade(not _grenade_thrown)


## Ends the throw animation; a grenade that was not thrown yet is given back.
func cancel_grenade(refund: bool) -> void:
	if refund and not _grenade_thrown:
		grenades += 1
		if is_local:
			GameEvents.local_grenades_changed.emit(grenades)
	_grenade_timer = 0.0
	_grenade_thrown = true


func _begin_grenade() -> void:
	grenades -= 1
	_grenade_timer = GRENADE_TOTAL_TIME
	_grenade_thrown = false
	get_current_weapon().cancel_actions()
	if NetworkManager.is_host():
		NetworkManager.broadcast_weapon_event(player.participant_id, "grenade")
	if is_local:
		AudioManager.play_2d("grenade_pin", -8.0)
		GameEvents.local_grenades_changed.emit(grenades)


func _update_grenade(delta: float) -> void:
	if _grenade_timer <= 0.0:
		return
	_grenade_timer -= delta
	if not _grenade_thrown and _grenade_timer <= GRENADE_TOTAL_TIME - GRENADE_THROW_DELAY:
		_grenade_thrown = true
		_spawn_grenade()


func _spawn_grenade() -> void:
	if NetworkManager.is_client():
		# the server spawns the real grenade and sends it to everybody
		AudioManager.play_2d("grenade_throw", -4.0)
		return
	var container := get_tree().get_first_node_in_group("projectiles_container")
	if container == null:
		container = get_tree().current_scene
	var grenade: Grenade = GRENADE_SCENE.instantiate()
	var origin := player.head.get_aim_origin()
	var dir := player.head.get_aim_direction()
	grenade.thrower_id = player.participant_id
	grenade.thrower_team = player.team
	container.add_child(grenade)
	grenade.global_position = origin + dir * 0.6 + Vector3(0.0, -0.1, 0.0)
	var launch_velocity := dir * GRENADE_SPEED + Vector3(0.0, 2.5, 0.0) + player.velocity * 0.5
	grenade.launch(launch_velocity)
	NetworkManager.register_grenade(grenade, player.participant_id, player.team, grenade.global_position, launch_velocity)
	if is_local:
		AudioManager.play_2d("grenade_throw", -4.0)
	else:
		AudioManager.play_3d("grenade_throw", origin, -4.0)


# ----------------------------------------------------------------------------- view model

## Starts the reload animation on the third-person model other players see.
## silent: the sounds are already played by the simulating Weapon (server side).
func begin_tp_reload(silent: bool, cycles: int = 1) -> void:
	if is_local or current_index >= _tp_rigs.size():
		return
	_stop_tp_reload()
	_tp_reload_progress = 0.0
	_tp_reload_cycles = maxi(1, cycles)
	_tp_reload_silent = silent
	_tp_rigs[current_index].reset()


func _stop_tp_reload() -> void:
	if _tp_reload_progress >= 0.0 and current_index < _tp_rigs.size():
		_tp_rigs[current_index].reset()
	_tp_reload_progress = -1.0


func _update_tp_reload(delta: float) -> void:
	var w := get_current_weapon()
	if w == null or current_index >= _tp_rigs.size():
		_tp_reload_progress = -1.0
		return
	if player.is_sprinting:
		_stop_tp_reload()
		return
	var cycle_time: float = w.data.shell_reload_time if w.data.reload_single_shells else w.data.reload_time
	var before := floorf(_tp_reload_progress)
	_tp_reload_progress += delta / maxf(0.05, cycle_time)
	var rig: ReloadRig = _tp_rigs[current_index]
	if int(floorf(_tp_reload_progress)) >= _tp_reload_cycles:
		_stop_tp_reload()
		return
	if floorf(_tp_reload_progress) != before:
		rig._last_t = -1.0 # next cycle (shotgun shells)
	var tilt := 1.0
	for ev in rig.apply(_tp_reload_progress - floorf(_tp_reload_progress), tilt):
		if not _tp_reload_silent:
			AudioManager.play_3d(ev, player.global_position + Vector3.UP, -9.0, 0.05, 28.0)


func _process(delta: float) -> void:
	if player == null:
		return
	if not is_local:
		if _tp_reload_progress >= 0.0:
			_update_tp_reload(delta)
		return
	var w := get_current_weapon()
	if w == null:
		return
	# blends
	_ads_blend = player.head.get_ads_blend()
	# same pace as the camera's sprint zoom (PlayerCamera.SPRINT_BLEND_SPEED), eased
	_sprint_blend = move_toward(_sprint_blend, 1.0 if player.is_sprinting else 0.0, delta * PlayerCamera.SPRINT_BLEND_SPEED)
	var sprint_s := _sprint_blend * _sprint_blend * (3.0 - 2.0 * _sprint_blend)
	var lowered := _switch_state == SwitchState.LOWERING or (_switch_state == SwitchState.RAISING and _switch_timer > w.data.draw_time * 0.5) or _grenade_timer > 0.0
	_lower_blend = move_toward(_lower_blend, 1.0 if lowered else 0.0, delta * 12.0)

	# sway from look input
	var look := player.last_look_delta
	var sway_target := Vector2.ZERO
	if GameSettings.weapon_sway:
		sway_target = Vector2(clampf(look.x * 2.0, -0.05, 0.05), clampf(look.y * 2.0, -0.05, 0.05))
		sway_target *= (0.25 if player.is_aiming else 1.0)
	_sway = _sway.lerp(sway_target, minf(1.0, delta * 9.0))

	# kick recovery
	_kick = lerpf(_kick, 0.0, minf(1.0, delta * w.data.recoil_recovery))
	_kick_rot = lerpf(_kick_rot, 0.0, minf(1.0, delta * w.data.recoil_recovery))

	var pos := w.data.hip_position.lerp(w.data.ads_position, _ads_blend)
	var rot := Vector3.ZERO
	# sprint pose
	pos += Vector3(0.07, -0.1, 0.06) * sprint_s
	rot += Vector3(-0.45, 0.55, 0.25) * sprint_s
	# knee slide: weapon tucked down and tilted
	_slide_blend = move_toward(_slide_blend, 1.0 if player.is_sliding else 0.0, delta * 5.0)
	var slide_s := _slide_blend * _slide_blend * (3.0 - 2.0 * _slide_blend)
	pos += Vector3(0.03, -0.07, 0.05) * slide_s
	rot += Vector3(-0.25, 0.3, 0.35) * slide_s
	# hit reaction: quick jerk away from the damage source
	_flinch_t += delta
	if _flinch_t < 0.6:
		var fe := exp(-_flinch_t * 11.0) * _flinch_amp
		pos += Vector3(_flinch_side * 0.03, -0.012, 0.05) * fe
		rot += Vector3(0.16, -_flinch_side * 0.14, -_flinch_side * 0.18) * fe
	# lowered (switch / grenade)
	pos += Vector3(0.05, -0.38, 0.05) * _lower_blend
	rot += Vector3(-0.8, 0.0, 0.0) * _lower_blend
	# sway
	pos += Vector3(-_sway.x, _sway.y, 0.0)
	rot += Vector3(_sway.y * 2.0, -_sway.x * 2.0, -_sway.x * 3.0)
	# walking / sprinting: the weapon swings with the steps (less when aiming down the sights)
	var on_floor := player.is_on_floor()
	var speed_ratio := clampf(player.horizontal_speed / Player.SPRINT_SPEED, 0.0, 1.0)
	_walk_amp = lerpf(_walk_amp, speed_ratio if on_floor else 0.0, minf(1.0, delta * 7.0))
	if GameSettings.weapon_sway and _walk_amp > 0.001:
		var ph := player.head.get_bob_phase()
		var amp := _walk_amp * (1.0 - 0.8 * _ads_blend) * (1.0 + 0.7 * sprint_s) * (1.0 - slide_s)
		# sin² instead of |sin|: no hard turn at the lowest point (that made the stock flutter);
		# small rotations only, they are magnified at the far end of the weapon
		var step := sin(ph)
		pos += Vector3(cos(ph * 0.5) * 0.007, -step * step * 0.008, 0.0) * amp
		rot += Vector3(step * 0.005, cos(ph * 0.5) * 0.010, cos(ph * 0.5) * 0.010) * amp
	# weapon kick: strongly damped while aiming so the iron sight stays in view
	var kick_scale := lerpf(1.0, 0.15, _ads_blend)
	pos += Vector3(0.0, _kick * 0.25, _kick) * kick_scale
	rot += Vector3(_kick_rot, 0.0, 0.0) * kick_scale
	# weapon's own animation (reload, pump)
	pos += w.anim_offset
	rot += w.anim_rotation

	holder.position = holder.position.lerp(pos, minf(1.0, delta * 18.0))
	holder.rotation = holder.rotation.lerp(rot, minf(1.0, delta * 18.0))


# ----------------------------------------------------------------------------- network (client side)

## Remote players: show the weapon the server says they hold.
func set_remote_weapon_index(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == current_index:
		return
	_stop_tp_reload()
	get_current_weapon().cancel_actions()
	current_index = index
	_show_weapon(current_index, true)


## Muzzle flash on the third-person model (what other players see).
func flash_third_person() -> void:
	if current_index < _tp_flashes.size():
		var f := _tp_flashes[current_index]
		if f != null and f.has_method("flash"):
			f.flash()


func play_remote_shot(impacts: Array) -> void:
	var w := get_current_weapon()
	if w:
		w.play_remote_shot(impacts)


func play_remote_event(event: String) -> void:
	var pos := player.global_position + Vector3.UP
	match event:
		"reload":
			var w := get_current_weapon()
			begin_tp_reload(false, 3 if w != null and w.data.reload_single_shells else 1)
		"switch":
			AudioManager.play_3d("weapon_switch", pos, -10.0)
		"grenade":
			AudioManager.play_3d("grenade_pin", pos, -10.0, 0.05, 25.0)


## Local client: take the server's ammo values when we are not in the middle of an action.
func apply_server_ammo(weapon_index: int, magazine: int, reserve: int, new_grenades: int) -> void:
	var w := get_current_weapon()
	if w and weapon_index == current_index and w.state == Weapon.State.IDLE and Time.get_ticks_msec() - w.last_fire_msec > 500:
		w.magazine = magazine
		w.reserve = reserve
	if _grenade_timer <= 0.0 and new_grenades != grenades:
		grenades = new_grenades
		if is_local:
			GameEvents.local_grenades_changed.emit(grenades)


func apply_kick(amount: float) -> void:
	_kick = minf(_kick + amount, 0.09)
	_kick_rot = minf(_kick_rot + amount * 1.8, 0.14)


func get_ammo_text() -> String:
	var w := get_current_weapon()
	if w == null:
		return ""
	return "%d / %d" % [w.magazine, w.reserve]
