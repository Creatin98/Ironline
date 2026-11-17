class_name Weapon
extends Node3D
## Runtime state of one hitscan weapon: ammo, firing, spread, recoil, reload, pump.
## The 3D model comes from WeaponData.model_scene and must contain a "Muzzle" node.
## Optional model nodes: "Pump" (shotgun slide), "Slide" (pistol slide).

## RELOAD_EXIT: a single-shell reload was interrupted by a shot; the weapon is brought back into the aim and fires.
enum State { HOLSTERED, DRAWING, IDLE, RELOADING, PUMPING, RELOAD_EXIT }

const RELOAD_EXIT_TIME := 0.2
const ADS_BLOOM := 0.4 # share of the spread bloom (spread_bonus) that applies while aiming down the sights
const HIT_MASK := 1 | 2 # World + Players
const IMPACT_SCENE := preload("res://scenes/effects/bullet_impact.tscn")
const MUZZLE_FLASH_SCENE := preload("res://scenes/effects/muzzle_flash.tscn")

var data: WeaponData
var player: Player
var is_local: bool = false
var magazine: int = 0
var reserve: int = 0
var state: int = State.HOLSTERED
var fire_cooldown: float = 0.0
var spread_bonus: float = 0.0
var last_fire_msec: int = 0

# procedural animation outputs read by WeaponManager
var anim_offset: Vector3 = Vector3.ZERO
var anim_rotation: Vector3 = Vector3.ZERO

var model: Node3D
var muzzle: Node3D
var pump_node: Node3D
var slide_node: Node3D
var muzzle_flash: Node3D

var _state_timer: float = 0.0
var _state_duration: float = 1.0
var rig: ReloadRig # reload animation of the first-person model
var _reload_total: float = 0.0
var _reload_elapsed: float = 0.0
var _shell_inserted: bool = false # the shell of the running cycle is already in the tube
var _cycle_index: int = 0 # shell cycles since the reload started
## > 0: a shot was requested while a reload was being interrupted; fired as soon as the weapon is ready (see take_queued_fire)
var fire_queue_t: float = 0.0
var _slide_timer: float = 0.0
var _pump_rest: Vector3 = Vector3.ZERO


func setup(new_data: WeaponData, new_player: Player, local: bool) -> void:
	data = new_data
	player = new_player
	is_local = local
	magazine = data.magazine_size
	reserve = data.reserve_ammo
	if data.model_scene:
		model = data.model_scene.instantiate()
		add_child(model)
		muzzle = model.get_node_or_null("Muzzle")
		pump_node = model.get_node_or_null("Pump")
		slide_node = model.get_node_or_null("Slide")
		if pump_node:
			_pump_rest = pump_node.position
		rig = ReloadRig.create(model, data.reload_style)
		if local:
			# the first-person view gets IK arms (FirstPersonArms); the model's built-in sleeves would end in mid-air
			rig.show_sleeves = false
			for n in model.find_children("*Forearm", "MeshInstance3D", true, false):
				if n.name == "LeftForearm" or n.name == "RightForearm":
					(n as Node3D).visible = false
	if muzzle == null:
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, 0, -0.6)
		add_child(muzzle)
	muzzle_flash = MUZZLE_FLASH_SCENE.instantiate()
	muzzle.add_child(muzzle_flash)


func fill_ammo() -> void:
	magazine = data.magazine_size
	reserve = data.reserve_ammo
	spread_bonus = 0.0
	fire_cooldown = 0.0


func is_reloading() -> bool:
	return state == State.RELOADING or state == State.RELOAD_EXIT


func draw() -> void:
	visible = is_local # only the owner sees the first-person model
	_set_state(State.DRAWING, data.draw_time)


func holster() -> void:
	if rig:
		rig.reset()
	visible = false
	_set_state(State.HOLSTERED, 0.0)
	anim_offset = Vector3.ZERO
	anim_rotation = Vector3.ZERO


func cancel_actions() -> void:
	if state == State.RELOADING or state == State.PUMPING or state == State.RELOAD_EXIT:
		_set_state(State.IDLE, 0.0)
	fire_queue_t = 0.0
	_reload_total = 0.0
	if rig:
		rig.reset()
	anim_offset = Vector3.ZERO
	anim_rotation = Vector3.ZERO
	if pump_node:
		pump_node.position = _pump_rest


func _set_state(new_state: int, duration: float) -> void:
	state = new_state
	_state_timer = duration
	_state_duration = maxf(duration, 0.0001)


# ----------------------------------------------------------------------------- update

func update(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	spread_bonus = maxf(0.0, spread_bonus - data.spread_recovery * delta)
	_slide_timer = maxf(0.0, _slide_timer - delta)
	fire_queue_t = maxf(0.0, fire_queue_t - delta)
	if slide_node:
		slide_node.position.z = 0.035 if _slide_timer > 0.0 else 0.0
	match state:
		State.DRAWING:
			_state_timer -= delta
			var t := 1.0 - clampf(_state_timer / _state_duration, 0.0, 1.0)
			anim_offset = Vector3(0.0, -0.25 * (1.0 - t), 0.05 * (1.0 - t))
			anim_rotation = Vector3(-0.6 * (1.0 - t), 0.0, 0.0)
			if _state_timer <= 0.0:
				anim_offset = Vector3.ZERO
				anim_rotation = Vector3.ZERO
				_set_state(State.IDLE, 0.0)
		State.RELOADING:
			_update_reload(delta)
		State.RELOAD_EXIT:
			_state_timer -= delta
			var k := 1.0 - clampf(_state_timer / _state_duration, 0.0, 1.0)
			if rig:
				rig.blend_out(k)
				anim_offset = rig.holder_offset
				anim_rotation = rig.holder_rotation
			if _state_timer <= 0.0:
				if rig:
					rig.reset()
				anim_offset = Vector3.ZERO
				anim_rotation = Vector3.ZERO
				_reload_total = 0.0
				_set_state(State.IDLE, 0.0)
		State.PUMPING:
			_state_timer -= delta
			var t := 1.0 - clampf(_state_timer / _state_duration, 0.0, 1.0)
			var s := sin(t * PI)
			var f := data.impact_feel
			if pump_node:
				pump_node.position = _pump_rest + Vector3(0.0, 0.0, 0.08 * s * minf(f, 1.6))
			# aggressive pump: the weapon is yanked down/back and rolled with each rack
			anim_offset = Vector3(0.0, -0.02 * s * f, 0.02 * s * f)
			anim_rotation = Vector3(0.12 * s * f, 0.04 * s * (f - 1.0), 0.15 * s * f)
			if _state_timer <= 0.0:
				if pump_node:
					pump_node.position = _pump_rest
				anim_offset = Vector3.ZERO
				anim_rotation = Vector3.ZERO
				_set_state(State.IDLE, 0.0)
				if magazine <= 0:
					start_reload()
		_:
			pass


# ----------------------------------------------------------------------------- firing

func get_spread_degrees(is_aiming: bool, move_ratio: float, in_air: bool, crouching: bool) -> float:
	var spread := data.spread_ads if is_aiming else data.spread_hip
	spread += data.spread_moving_bonus * move_ratio * (0.4 if is_aiming else 1.0)
	# sustained fire blooms the spread; through the sights only lightly (tapping stays precise)
	spread += spread_bonus * (ADS_BLOOM if is_aiming else 1.0)
	if in_air:
		spread += 2.5
	if crouching:
		spread *= 0.8
	return spread


func try_fire(is_aiming: bool, move_ratio: float, in_air: bool, crouching: bool) -> bool:
	if state == State.RELOADING:
		# shells are loaded one by one: whatever is already in the tube can be fired, the reload is interrupted
		if data.reload_single_shells and magazine > 0:
			_begin_reload_exit()
		return false
	if state == State.RELOAD_EXIT:
		fire_queue_t = RELOAD_EXIT_TIME + 0.25
		return false
	if state != State.IDLE or fire_cooldown > 0.0:
		return false
	if magazine <= 0:
		fire_cooldown = 0.35
		if is_local:
			AudioManager.play_2d("empty_click", -6.0)
		start_reload()
		return false

	magazine -= 1
	fire_cooldown = data.seconds_between_shots()
	var spread := get_spread_degrees(is_aiming, move_ratio, in_air, crouching)
	spread_bonus = minf(data.spread_max_bonus, spread_bonus + data.spread_per_shot)

	var origin := player.head.get_aim_origin()
	var forward := player.head.get_aim_direction()
	var hit_enemy := false
	var headshot_any := false
	var killed_any := false
	var impacts: Array = [] # [position, normal, hit_player] for the other machines
	last_fire_msec = Time.get_ticks_msec()
	player.shot_flag = true
	for i in data.pellets:
		var dir := _random_cone_direction(forward, spread)
		var result := _hit_scan(origin, dir)
		if result.is_empty():
			continue
		var collider: Object = result["collider"]
		var hit_pos: Vector3 = result["position"]
		var normal: Vector3 = result["normal"]
		impacts.append([hit_pos, normal, collider is Player])
		if collider is Player:
			var target := collider as Player
			var distance := origin.distance_to(hit_pos)
			var headshot := hit_pos.y >= target.get_headshot_y() and data.headshot_multiplier > 1.0
			var dmg := data.damage_at_distance(distance)
			if headshot:
				dmg *= data.headshot_multiplier
			var killed := target.take_damage(dmg, player.participant_id, data.weapon_id, hit_pos, headshot, origin)
			if target.team == Teams.Team.NONE or target.team != player.team:
				hit_enemy = true
				headshot_any = headshot_any or headshot
				killed_any = killed_any or killed
			_spawn_impact(hit_pos, normal, true)
		else:
			_spawn_impact(hit_pos, normal, false)

	_play_shot_feedback()
	_apply_recoil(is_aiming, crouching)
	if is_local and hit_enemy:
		GameEvents.local_player_hit_enemy.emit(headshot_any, killed_any)
	elif hit_enemy and not player.is_bot and NetworkManager.is_host():
		NetworkManager.send_hit_feedback(player.participant_id, headshot_any, killed_any)
	if NetworkManager.is_host():
		NetworkManager.broadcast_shot(player.participant_id, impacts)
	GameEvents.shot_fired.emit(player.participant_id, origin)

	if slide_node:
		_slide_timer = 0.07
	if data.pump_action:
		# pump after every shot; with an empty tube the pump state chains into reload
		_set_state(State.PUMPING, data.pump_time)
		_play_mech_sound("pump", -4.0)
	elif magazine <= 0:
		fire_cooldown = maxf(fire_cooldown, 0.15)
	return true


## True once when a shot that was requested during an interrupted reload may be fired now.
func take_queued_fire() -> bool:
	if fire_queue_t > 0.0 and state == State.IDLE:
		fire_queue_t = 0.0
		return true
	return false


func _random_cone_direction(forward: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return forward
	var angle := deg_to_rad(spread_deg) * sqrt(randf())
	var roll := randf() * TAU
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var real_up := right.cross(forward).normalized()
	var offset := (right * cos(roll) + real_up * sin(roll)) * tan(angle)
	return (forward + offset).normalized()


func _hit_scan(origin: Vector3, dir: Vector3) -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * data.max_range, HIT_MASK)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	return space.intersect_ray(query)


## Client: the server fired this player's weapon; show shot, sound and impacts.
func play_remote_shot(impacts: Array) -> void:
	last_fire_msec = Time.get_ticks_msec()
	player.shot_flag = true
	_play_shot_feedback()
	for entry in impacts:
		if typeof(entry) == TYPE_ARRAY and entry.size() >= 3:
			_spawn_impact(entry[0], entry[1], bool(entry[2]))
	GameEvents.shot_fired.emit(player.participant_id, player.get_eye_position())


func _spawn_impact(pos: Vector3, normal: Vector3, blood: bool) -> void:
	var parent := player.get_tree().get_first_node_in_group("effects_container")
	if parent == null:
		parent = player.get_tree().current_scene
	var fx := IMPACT_SCENE.instantiate()
	parent.add_child(fx)
	fx.setup(pos, normal, blood)
	if blood:
		BloodFx.burst(parent, pos, pos - player.get_eye_position(), 1.0 if data.pellets <= 1 else 0.4)


func _play_shot_feedback() -> void:
	if muzzle_flash and muzzle_flash.has_method("flash"):
		muzzle_flash.flash()
		if data.impact_feel > 1.0 and muzzle_flash is Node3D:
			(muzzle_flash as Node3D).scale = Vector3.ONE * data.impact_feel * 0.9 # a bigger fireball
	if is_local and data.impact_feel > 1.0:
		# heavy weapon: the whole picture is hit (shake + zoom punch)
		player.head.add_shake(0.35 * data.impact_feel)
		player.head.kick_fov(2.2 * data.impact_feel)
	if not is_local:
		player.weapon_manager.flash_third_person()
	if is_local:
		AudioManager.play_2d(data.shot_sound, data.shot_volume_db, 0.05)
	else:
		AudioManager.play_3d(data.shot_sound, muzzle.global_position if muzzle else player.global_position, data.shot_volume_db, 0.05, 120.0)


func _apply_recoil(is_aiming: bool, crouching: bool) -> void:
	var mult := 1.0
	if is_aiming:
		mult *= 0.55
	if crouching:
		mult *= 0.85
	player.head.add_recoil(data.recoil_vertical * mult, randf_range(-data.recoil_horizontal, data.recoil_horizontal) * mult, data.recoil_recovery)
	player.weapon_manager.apply_kick(data.recoil_kick_back * mult)


# ----------------------------------------------------------------------------- reload

func start_reload() -> bool:
	if state != State.IDLE:
		return false
	if magazine >= data.magazine_size or reserve <= 0:
		return false
	if NetworkManager.is_host():
		NetworkManager.broadcast_weapon_event(player.participant_id, "reload")
	_shell_inserted = false
	_cycle_index = 0
	fire_queue_t = 0.0
	_reload_elapsed = 0.0
	_reload_total = 0.0
	if rig:
		rig.reset()
		_update_cycle_flags()
	if not player.is_local:
		# other players: animate the third-person copy (the first-person model is hidden)
		player.weapon_manager.begin_tp_reload(true, data.magazine_size - magazine)
	if data.reload_single_shells:
		_set_state(State.RELOADING, data.shell_reload_time)
	else:
		_set_state(State.RELOADING, data.reload_time)
	return true


func _update_reload(delta: float) -> void:
	_state_timer -= delta
	_reload_elapsed += delta
	_reload_total += delta
	# pose the model (magazine, hands, handle, slide, shell); the rig reports the sounds to play
	var t := 1.0 - clampf(_state_timer / _state_duration, 0.0, 1.0)
	var tilt := 1.0
	if data.reload_single_shells:
		tilt = ReloadRig._smooth(_reload_total / 0.18) # the shotgun tilts in once, not per shell
	if rig:
		for ev in rig.apply(t, tilt):
			_play_mech_sound(ev)
		anim_offset = rig.holder_offset
		anim_rotation = rig.holder_rotation
	# the shell counts the moment it is pushed in (not at the end of the cycle): an interrupted reload keeps it
	if data.reload_single_shells and not _shell_inserted and t >= ReloadRig.SHELL_INSERT_T:
		_insert_shell()
	if _state_timer > 0.0:
		return
	# cycle complete
	if data.reload_single_shells:
		if not _shell_inserted:
			_insert_shell()
		_shell_inserted = false
		if magazine < data.magazine_size and reserve > 0:
			_cycle_index += 1
			_reload_elapsed = 0.0
			_set_state(State.RELOADING, data.shell_reload_time)
			if rig:
				_update_cycle_flags()
				rig.apply(0.0, tilt) # next shell: restart the cycle
				rig._last_t = -1.0
			return
	else:
		var needed := data.magazine_size - magazine
		var taken := mini(needed, reserve)
		magazine += taken
		reserve -= taken
	if rig:
		rig.reset()
	anim_offset = Vector3.ZERO
	anim_rotation = Vector3.ZERO
	_reload_total = 0.0
	_set_state(State.IDLE, 0.0)


func _insert_shell() -> void:
	_shell_inserted = true
	if magazine >= data.magazine_size or reserve <= 0:
		return
	magazine += 1
	reserve -= 1
	if is_local and data.impact_feel > 1.0:
		# every shell slams in: kick and shake
		player.weapon_manager.apply_kick(0.05)
		player.head.add_shake(0.24)


## Tells the rig where this cycle starts (forend or belt) and ends, so the hand does not return to the forend between shells.
func _update_cycle_flags() -> void:
	if rig == null or not data.reload_single_shells:
		return
	rig.shell_first = _cycle_index == 0
	rig.shell_last = data.magazine_size - magazine <= 1 or reserve <= 1


## A shot interrupts the shell reload: the pose blends back into the aim (RELOAD_EXIT), then the queued shot is fired.
func _begin_reload_exit() -> void:
	fire_queue_t = RELOAD_EXIT_TIME + 0.25
	if rig:
		rig.begin_exit()
	_set_state(State.RELOAD_EXIT, RELOAD_EXIT_TIME)
	if not player.is_local:
		player.weapon_manager.stop_tp_reload() # the figure other players see stops loading as well


func _play_mech_sound(sfx: String, volume_db: float = -6.0) -> void:
	if is_local:
		AudioManager.play_2d(sfx, volume_db)
	else:
		AudioManager.play_3d(sfx, player.global_position + Vector3.UP, volume_db - 4.0, 0.05, 25.0)


func get_display_name() -> String:
	return data.display_name if data else ""
