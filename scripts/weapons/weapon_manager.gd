class_name WeaponManager
extends Node3D
## Holds the two weapons of a player, handles switching, grenades and the
## procedural view-model motion (hip/ADS position, sway, sprint pose, kick).

enum SwitchState { READY, LOWERING, RAISING }

const GRENADE_SCENE := preload("res://scenes/weapons/grenade.tscn")
const LOWER_TIME := 0.11
const GRENADE_TOTAL_TIME := 1.0
const GRENADE_THROW_DELAY := GRENADE_TOTAL_TIME * GrenadeView.RELEASE_T
## Sound marks of a throw (share of the total time): taken out, pin pulled, spoon released.
## The pulled grenade is held ready at this point of the throw (arm cocked) as long as the key stays down.
const GRENADE_HOLD_T := 0.58
const GRENADE_SOUNDS := [[0.04, "grenade_draw", -6.0], [0.34, "grenade_pin", -3.0], [0.63, "grenade_lever", -6.0]]
const GRENADE_SPEED := 17.0
const SCOPE_OPEN_FROM := 0.5 # aim blend at which the scope picture starts to open
const SCOPE_HIDE_AT := 0.72 # the viewmodel disappears: you look through the scope

var player: Player
var is_local: bool = false
var weapons: Array[Weapon] = []
var current_index: int = 0
var grenades: int = 2
var max_grenades: int = 2
var flashbangs: int = 1
var max_flashbangs: int = 1

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
var _grenade_kind: int = Grenade.KIND_FRAG # which grenade is being thrown (frag / flashbang)
var _tp_models: Array[Node3D] = []
var _tp_rigs: Array = [] # ReloadRig per third-person model
var _tp_reload_progress: float = -1.0 # in cycles; < 0 = idle
var _tp_reload_cycles: int = 1
var _tp_reload_silent: bool = false
var _tp_flashes: Array[Node3D] = []
## True while a pulled grenade is held ready (key down): drives the crosshair ring of the HUD.
var grenade_holding: bool = false
var _grenade_hold_time: float = 0.0
var _fp_arms: FirstPersonArms
var _skin_color: Color = Color(0.88, 0.72, 0.58) # tone of the hands (set_arm_colors)
var _grenade_view: GrenadeView
var _grenade_sound_idx: int = 0
var _tp_grenade_t: float = -1.0 # remote players: time into the throw (sounds only)
var _flinch_t: float = 99.0
var _flinch_side: float = 0.0
var _flinch_amp: float = 0.0
var _last_mag: int = -1
var _last_reserve: int = -1


func setup(new_player: Player, class_data: ClassData, local: bool) -> void:
	player = new_player
	is_local = local
	if is_local and _fp_arms == null:
		_fp_arms = FirstPersonArms.new()
		_fp_arms.name = "FirstPersonArms"
		add_child(_fp_arms)
	if is_local and _grenade_view == null:
		_grenade_view = GrenadeView.new()
		_grenade_view.name = "GrenadeView"
		add_child(_grenade_view)
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
	max_flashbangs = class_data.flashbangs
	flashbangs = max_flashbangs
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
	_apply_hand_skin()
	if is_local:
		ScopeOverlay.tag_viewmodel(self) # weapons, arms, grenade view: the scope camera does not render them
	_show_weapon(current_index, true)


## The hands of every model (first-person and third-person copy) get the skin tone of the player.
func _apply_hand_skin() -> void:
	for w in weapons:
		if w.model != null:
			ReloadRig.apply_skin(w.model, _skin_color)
	for m in _tp_models:
		ReloadRig.apply_skin(m, _skin_color)


func reset_for_spawn() -> void:
	grenades = max_grenades
	flashbangs = max_flashbangs
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
	var w := get_current_weapon()
	if w != null and w.is_bolting():
		return false # working the bolt: the scope drops out, aiming resumes afterwards
	return _switch_state == SwitchState.READY and _grenade_timer <= 0.0


## How far the scope picture is open (0..1; scoped weapons only): the viewmodel is hidden from SCOPE_HIDE_AT on.
func scope_blend() -> float:
	var w := get_current_weapon()
	if w == null or not w.data.scoped or player == null:
		return 0.0
	return clampf((player.head.get_ads_blend() - SCOPE_OPEN_FROM) / (1.0 - SCOPE_OPEN_FROM), 0.0, 1.0)


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
	GameEvents.local_flashbangs_changed.emit(flashbangs)


# ----------------------------------------------------------------------------- input

func process_input(input: PlayerInputState, delta: float) -> void:
	var w := get_current_weapon()
	if w == null:
		return
	_update_switch(delta)
	_update_grenade(delta, input.flash_held if _grenade_kind == Grenade.KIND_FLASH else input.grenade_held)
	w.update(delta)

	# switching cancels a grenade that has not been thrown yet, and may interrupt the raise (spam switching)
	if _grenade_timer > 0.0 and not _grenade_thrown and (input.select_primary or input.select_secondary or input.switch_pressed):
		cancel_grenade(true)
	if _grenade_timer <= 0.0 and (_switch_state == SwitchState.READY or _switch_state == SwitchState.RAISING):
		if _switch_state == SwitchState.READY and input.grenade_pressed and grenades > 0 and not w.is_reloading():
			_begin_grenade(Grenade.KIND_FRAG)
			return
		if _switch_state == SwitchState.READY and input.flash_pressed and flashbangs > 0 and not w.is_reloading():
			_begin_grenade(Grenade.KIND_FLASH)
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
		# a shot that interrupted a shell reload is fired as soon as the weapon is back in the aim
		if w.take_queued_fire():
			wants_fire = true
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


func is_throwing_grenade() -> bool:
	return _grenade_timer > 0.0


## A reload or a grenade throw is in progress (sprint rules, see Player._update_states).
func is_action_active() -> bool:
	var w := get_current_weapon()
	return (w != null and w.is_reloading()) or _grenade_timer > 0.0


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
		if _grenade_kind == Grenade.KIND_FLASH:
			flashbangs += 1
			if is_local:
				GameEvents.local_flashbangs_changed.emit(flashbangs)
		else:
			grenades += 1
			if is_local:
				GameEvents.local_grenades_changed.emit(grenades)
	_grenade_timer = 0.0
	_grenade_thrown = true
	grenade_holding = false
	_grenade_hold_time = 0.0
	if _grenade_view != null:
		_grenade_view.apply(0.0)


func _begin_grenade(kind: int) -> void:
	_grenade_kind = kind
	if kind == Grenade.KIND_FLASH:
		flashbangs -= 1
	else:
		grenades -= 1
	_grenade_timer = GRENADE_TOTAL_TIME
	_grenade_thrown = false
	get_current_weapon().cancel_actions()
	if NetworkManager.is_host():
		NetworkManager.broadcast_weapon_event(player.participant_id, "flash" if kind == Grenade.KIND_FLASH else "grenade")
	_grenade_sound_idx = 0
	if _grenade_view != null:
		_grenade_view.set_kind(kind)
	if is_local:
		GameEvents.local_grenades_changed.emit(grenades)
		GameEvents.local_flashbangs_changed.emit(flashbangs)


func _update_grenade(delta: float, held: bool) -> void:
	if _grenade_timer <= 0.0:
		grenade_holding = false
		_grenade_hold_time = 0.0
		return
	# after the pin is pulled the grenade stays in the cocked arm as long as the key is held
	var frac_now := clampf(1.0 - _grenade_timer / GRENADE_TOTAL_TIME, 0.0, 1.0)
	grenade_holding = held and not _grenade_thrown and frac_now >= GRENADE_HOLD_T
	if grenade_holding:
		_grenade_hold_time += delta
		_grenade_timer = GRENADE_TOTAL_TIME * (1.0 - GRENADE_HOLD_T)
	else:
		_grenade_hold_time = 0.0
		_grenade_timer -= delta
	var frac := clampf(1.0 - _grenade_timer / GRENADE_TOTAL_TIME, 0.0, 1.0)
	while _grenade_sound_idx < GRENADE_SOUNDS.size() and frac >= float(GRENADE_SOUNDS[_grenade_sound_idx][0]):
		var mark: Array = GRENADE_SOUNDS[_grenade_sound_idx]
		_grenade_sound_idx += 1
		if is_local:
			AudioManager.play_2d(String(mark[1]), float(mark[2]), 0.03)
		else:
			AudioManager.play_3d(String(mark[1]), player.global_position + Vector3.UP, float(mark[2]) - 4.0, 0.04, 25.0)
	if _grenade_view != null:
		_grenade_view.apply(frac if _grenade_timer > 0.0 else 0.0, _grenade_hold_time)
	if not _grenade_thrown and _grenade_timer <= GRENADE_TOTAL_TIME - GRENADE_THROW_DELAY:
		_grenade_thrown = true
		_spawn_grenade()


func _spawn_grenade() -> void:
	if NetworkManager.is_client():
		# the server spawns the real grenade and sends it to everybody
		AudioManager.play_2d("grenade_throw", 1.0)
		return
	var container := get_tree().get_first_node_in_group("projectiles_container")
	if container == null:
		container = get_tree().current_scene
	var grenade: Grenade = GRENADE_SCENE.instantiate()
	grenade.kind = _grenade_kind # before it enters the tree: the flashbang builds its own look
	var origin := player.head.get_aim_origin()
	var dir := player.head.get_aim_direction()
	grenade.thrower_id = player.participant_id
	grenade.thrower_team = player.team
	container.add_child(grenade)
	grenade.global_position = origin + dir * 0.6 + Vector3(0.0, -0.1, 0.0)
	var launch_velocity := dir * GRENADE_SPEED + Vector3(0.0, 2.5, 0.0) + player.velocity * 0.5
	grenade.launch(launch_velocity)
	NetworkManager.register_grenade(grenade, player.participant_id, player.team, grenade.global_position, launch_velocity, _grenade_kind)
	if is_local:
		AudioManager.play_2d("grenade_throw", 1.0)
	else:
		AudioManager.play_3d("grenade_throw", origin, 0.0)


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


## Public: the figure's reload stops (shot while loading shells).
func stop_tp_reload() -> void:
	_stop_tp_reload()


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
	rig.shell_first = int(floorf(_tp_reload_progress)) == 0
	rig.shell_last = int(floorf(_tp_reload_progress)) >= _tp_reload_cycles - 1
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
		if _tp_grenade_t >= 0.0:
			_tp_grenade_t += delta
			var tf := _tp_grenade_t / GRENADE_TOTAL_TIME
			# only draw + pin by time: the release of a held grenade is announced by the spawn of the grenade itself
			while _grenade_sound_idx < GRENADE_SOUNDS.size() and tf >= float(GRENADE_SOUNDS[_grenade_sound_idx][0]):
				var m: Array = GRENADE_SOUNDS[_grenade_sound_idx]
				_grenade_sound_idx += 1
				if String(m[1]) != "grenade_lever":
					AudioManager.play_3d(String(m[1]), player.global_position + Vector3.UP, float(m[2]) - 4.0, 0.04, 25.0)
			if tf >= 1.0:
				_tp_grenade_t = -1.0
		return
	var w := get_current_weapon()
	if w == null:
		return
	# blends
	_ads_blend = player.head.get_ads_blend()
	holder.visible = not (w.data.scoped and _ads_blend > SCOPE_HIDE_AT)
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
	_update_arms(w)


## Arms of the first-person view: from the shoulders (camera space) to the wrists of the weapon's hands.
## Hidden while the grenade view brings its own hands.
func _update_arms(w: Weapon) -> void:
	if _fp_arms == null:
		return
	var throwing := _grenade_view != null and _grenade_view.visible
	_fp_arms.visible = not throwing and not (w.data.scoped and _ads_blend > SCOPE_HIDE_AT)
	if throwing or w.model == null:
		return
	_fp_arms.update(_wrist(w.model, "RightHand", Vector3(0.004, -0.028, 0.044)), _wrist(w.model, "LeftHand", Vector3(-0.006, -0.018, 0.040)))


func _wrist(model: Node3D, hand_name: String, offset: Vector3) -> Vector3:
	var hand := model.get_node_or_null(hand_name) as Node3D
	if hand == null:
		return Vector3.INF
	return to_local(hand.to_global(offset))


## Skin and shirt colour of the first-person arms (those of the player's own figure).
func set_arm_colors(skin: Color, shirt: Color) -> void:
	_skin_color = skin
	_apply_hand_skin()
	if _fp_arms != null:
		_fp_arms.set_colors(skin, shirt)
	if _grenade_view != null:
		_grenade_view.set_colors(skin)


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
		_stop_tp_reload() # a shot ends a reload that is still running on the figure (shells: interrupted)
		w.play_remote_shot(impacts)


func play_remote_event(event: String) -> void:
	var pos := player.global_position + Vector3.UP
	match event:
		"reload":
			var w := get_current_weapon()
			begin_tp_reload(false, 3 if w != null and w.data.reload_single_shells else 1)
		"switch":
			AudioManager.play_3d("weapon_switch", pos, -10.0)
		"grenade", "flash":
			_tp_grenade_t = 0.0
			_grenade_sound_idx = 0


## Local client: take the server's ammo values when we are not in the middle of an action.
func apply_server_ammo(weapon_index: int, magazine: int, reserve: int, new_grenades: int, new_flashbangs: int = -1) -> void:
	var w := get_current_weapon()
	if w and weapon_index == current_index and w.state == Weapon.State.IDLE and Time.get_ticks_msec() - w.last_fire_msec > 500:
		w.magazine = magazine
		w.reserve = reserve
	if _grenade_timer <= 0.0 and new_grenades != grenades:
		grenades = new_grenades
		if is_local:
			GameEvents.local_grenades_changed.emit(grenades)
	if _grenade_timer <= 0.0 and new_flashbangs >= 0 and new_flashbangs != flashbangs:
		flashbangs = new_flashbangs
		if is_local:
			GameEvents.local_flashbangs_changed.emit(flashbangs)


func apply_kick(amount: float) -> void:
	_kick = minf(_kick + amount, 0.26)
	_kick_rot = minf(_kick_rot + amount * 1.8, 0.42)


func get_ammo_text() -> String:
	var w := get_current_weapon()
	if w == null:
		return ""
	return "%d / %d" % [w.magazine, w.reserve]
