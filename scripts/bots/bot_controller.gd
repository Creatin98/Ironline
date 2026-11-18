class_name BotController
extends Node
## AI that drives a Player exactly like a human would: it only writes into the
## PlayerInputState. Runs on the authority (server/offline host) only.
##
## Behaviour: patrol the map's lanes (team-spread in TDM), spot enemies by sight
## and hearing, fight with bursts and strafing, retreat to cover when hurt,
## reload/switch when empty, throw grenades at medium range.

enum State { IDLE, PATROL, COMBAT, SEARCH, RETREAT }

const PERCEPTION_INTERVAL := 0.12
const REPATH_INTERVAL := 0.7
const WAYPOINT_REACH := 0.8
const OBJECTIVE_REACH := 1.4
const STUCK_TIME := 1.3
const GIVE_UP_STUCK_TIME := 3.0
const EYE_HEIGHT := 1.62

var player: Player
var participant: Participant
var diff: BotDifficulty
var map: BlockMap
var nav_map: RID

var state: int = State.IDLE
var state_timer: float = 0.0

# perception
var target: Player = null
var target_visible: bool = false
var last_seen_pos: Vector3 = Vector3.ZERO
var time_since_seen: float = 99.0
var reaction_timer: float = 0.0
var _perception_timer: float = 0.0
var _aim_error: Vector2 = Vector2.ZERO
var _aim_error_timer: float = 0.0

# movement
var objective: Vector3 = Vector3.ZERO
var has_objective: bool = false
var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var _repath_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _wants_move: bool = false
var _strafe_dir: float = 0.0
var _strafe_timer: float = 0.0
var _spawn_wait: float = 0.0
var preferred_lane: String = "mid"

# combat
var _burst_timer: float = 0.0
var _burst_pause_timer: float = 0.0
var _grenade_cooldown: float = 8.0
var _grenade_lob_timer: float = 0.0
var _retreat_cover: Vector3 = Vector3.ZERO

var _desired_yaw: float = 0.0
var _desired_pitch: float = 0.0
var _has_look_target: bool = false
## Seconds this bot is still blinded by a flashbang: it sees no enemies and does not shoot.
var _blind_left: float = 0.0

# human-like behaviour (does not touch the difficulty numbers: reaction time, aim error, turn speed, ranges ...)
enum Style { HOLD, PUSH, FLANK }
var _style: int = Style.HOLD
var _flank_pt: Vector3 = Vector3.INF
var _flank_done: bool = false
var _aim_cur: Vector2 = Vector2.ZERO # the aim error drifts instead of jumping
var _aim_point_s: Vector3 = Vector3.ZERO # where the crosshair really is: it travels to the enemy, it does not snap
var _aim_valid: bool = false
var _aim_head: bool = false
var _aim_head_timer: float = 0.0
var _move_s: Vector2 = Vector2.ZERO
var _glance_cd: float = 2.0
var _glance_t: float = 0.0
var _glance_yaw: float = 0.0
var _post_kill: float = 0.0 # after a kill: a short pause before the next enemy is noticed
var _short_retreat: bool = false
var _dodge_t: float = 0.0
var _crouch_t: float = 0.0
var _ads: bool = false


func setup(new_player: Player, new_participant: Participant) -> void:
	player = new_player
	participant = new_participant
	diff = BotDifficulty.preset(participant.bot_difficulty)
	process_physics_priority = -10
	var lanes := ["left", "mid", "right"]
	preferred_lane = lanes[participant.id % 3]
	player.respawned.connect(_on_respawned)
	GameEvents.shot_fired.connect(_on_shot_heard)
	GameEvents.explosion_at.connect(_on_explosion_heard)
	GameEvents.flashbang_exploded.connect(_on_flashbang)
	player.health.damaged.connect(_on_hurt)
	GameEvents.participant_killed.connect(_on_any_kill)


func _ready() -> void:
	map = get_tree().get_first_node_in_group("map") as BlockMap
	if map:
		nav_map = map.get_world_3d().navigation_map


func _on_respawned() -> void:
	state = State.IDLE
	state_timer = 0.0
	target = null
	target_visible = false
	time_since_seen = 99.0
	has_objective = false
	path = PackedVector3Array()
	_spawn_wait = randf_range(0.3, 0.9)
	_grenade_cooldown = randf_range(6.0, 14.0)
	_blind_left = 0.0
	_post_kill = 0.0
	_aim_valid = false
	_last_pos = player.global_position
	_stuck_timer = 0.0


## A flashbang went off: a bot that looks into it (and has no wall in between) is blinded for a while.
func _on_flashbang(center: Vector3, _thrower_id: int) -> void:
	if player == null or not player.alive or not MatchManager.is_authority():
		return
	var i := FlashMath.intensity(player.get_world_3d().direct_space_state, center, player.get_eye_position(), player.head.get_aim_direction())
	if i < 0.15:
		return
	_blind_left = maxf(_blind_left, FlashMath.blind_time(i) + FlashMath.fade_time(i) * 0.5)
	target_visible = false
	_burst_timer = 0.0


# ----------------------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if player == null or not player.alive or not MatchManager.is_authority():
		return
	if MatchManager.state != MatchManager.State.RUNNING or not player.controls_enabled:
		player.input.clear_all()
		return
	if map == null:
		map = get_tree().get_first_node_in_group("map") as BlockMap
		if map:
			nav_map = map.get_world_3d().navigation_map
	var inp := player.input
	inp.clear_all()
	_spawn_wait = maxf(0.0, _spawn_wait - delta)
	_grenade_cooldown = maxf(0.0, _grenade_cooldown - delta)
	_grenade_lob_timer = maxf(0.0, _grenade_lob_timer - delta)
	_blind_left = maxf(0.0, _blind_left - delta)
	_post_kill = maxf(0.0, _post_kill - delta)
	_dodge_t = maxf(0.0, _dodge_t - delta)
	_crouch_t = maxf(0.0, _crouch_t - delta)
	_update_perception(delta)
	_update_state(delta)
	if _spawn_wait > 0.0:
		return
	_update_movement(delta)
	_update_weapon(delta)
	_update_look(delta)
	_update_stuck(delta)


# ----------------------------------------------------------------------------- perception

func _update_perception(delta: float) -> void:
	time_since_seen += delta
	reaction_timer = maxf(0.0, reaction_timer - delta)
	if _blind_left > 0.0:
		target_visible = false # blinded: no enemy is seen
		return
	if _post_kill > 0.0:
		target_visible = false # just killed somebody: a moment before the next one is noticed
		return
	_perception_timer -= delta
	if _perception_timer > 0.0:
		return
	_perception_timer = PERCEPTION_INTERVAL + randf() * 0.04
	var best: Player = null
	var best_dist := INF
	var eye := player.get_eye_position()
	var forward := -player.global_transform.basis.z
	var cos_half_fov := cos(deg_to_rad(diff.fov_deg * 0.5))
	var space := player.get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as Player
		if other == null or other == player or not other.alive:
			continue
		if not _is_enemy(other):
			continue
		var to := other.get_center() - eye
		var dist := to.length()
		if dist > diff.view_range:
			continue
		var dir := to / maxf(dist, 0.001)
		if dist > 3.0 and forward.dot(dir) < cos_half_fov:
			continue
		if not _has_line_of_sight(space, eye, other):
			continue
		if dist < best_dist:
			best_dist = dist
			best = other
	if best != null:
		if best != target:
			target = best
			# a human needs a different moment every time, and longer when the enemy appears far off the view axis
			var off_axis := acos(clampf(forward.dot((best.get_center() - eye).normalized()), -1.0, 1.0))
			reaction_timer = diff.reaction_time * randf_range(0.8, 1.3) + off_axis / PI * 0.25
			_aim_valid = false
			_pick_style()
		target_visible = true
		last_seen_pos = best.global_position
		time_since_seen = 0.0
	else:
		target_visible = false


func _is_enemy(other: Player) -> bool:
	if participant.team == Teams.Team.NONE or other.team == Teams.Team.NONE:
		return true
	return other.team != participant.team


func _has_line_of_sight(space: PhysicsDirectSpaceState3D, eye: Vector3, other: Player) -> bool:
	for point in [other.get_center(), other.get_eye_position()]:
		var query := PhysicsRayQueryParameters3D.create(eye, point, 1)
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _on_shot_heard(shooter_id: int, position: Vector3) -> void:
	if player == null or not player.alive or shooter_id == participant.id:
		return
	var shooter := MatchManager.get_participant(shooter_id)
	if shooter == null or not participant.is_enemy_of(shooter):
		return
	if position.distance_to(player.global_position) > diff.hearing_range:
		return
	if not target_visible and state != State.COMBAT and state != State.RETREAT:
		last_seen_pos = position
		_enter_state(State.SEARCH)
		_set_objective(position)


func _on_explosion_heard(position: Vector3, _radius: float) -> void:
	if player == null or not player.alive:
		return
	if position.distance_to(player.global_position) < diff.hearing_range * 1.5 and state == State.PATROL and not target_visible:
		last_seen_pos = position
		_enter_state(State.SEARCH)
		_set_objective(position)


## Shot at: sometimes a human steps out of the line of fire; a kill makes the killer pause a moment.
func _on_hurt(_amount: float, attacker_id: int) -> void:
	if player == null or not player.alive or attacker_id == participant.id:
		return
	_dodge_t = 0.8
	_strafe_dir = -_strafe_dir if _strafe_dir != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	var ratio := player.health.ratio()
	if state == State.COMBAT and ratio < 0.75 and randf() < 0.4 and _pick_retreat_cover():
		_short_retreat = true
		_enter_state(State.RETREAT)


func _on_any_kill(_victim_id: int, killer_id: int, _weapon: String, _head: bool) -> void:
	if player != null and player.alive and killer_id == participant.id:
		_post_kill = randf_range(0.6, 1.3)
		target = null
		target_visible = false
		reaction_timer = maxf(reaction_timer, 0.4)


## Combat plan per enemy: hold the position and strafe, push forward aggressively or take a side route.
func _pick_style() -> void:
	var r := randf()
	var hp := player.health.ratio()
	var push_chance := 0.3 if hp > 0.8 else 0.1
	if r < push_chance:
		_style = Style.PUSH
	elif r < push_chance + 0.2:
		_style = Style.FLANK
	else:
		_style = Style.HOLD
	_flank_pt = Vector3.INF
	_flank_done = false


## A cover point to the side of the enemy (not straight ahead): the flanking route.
func _pick_flank_point() -> Vector3:
	if map == null or target == null:
		return Vector3.INF
	var w := player.weapon_manager.get_current_weapon()
	var effective: float = w.data.bot_effective_range if w else 25.0
	var me := player.global_position
	var to_target := target.global_position - me
	to_target.y = 0.0
	var best := Vector3.INF
	var best_score := -INF
	for p in map.get_cover_points():
		var dt := target.global_position.distance_to(p)
		var dm := me.distance_to(p)
		if dt < 6.0 or dt > effective * 0.95 or dm < 5.0 or dm > 30.0:
			continue
		var side: Vector3 = p - me
		side.y = 0.0
		var angle := absf(to_target.angle_to(side))
		var score := angle * 3.0 - dm * 0.05 + randf() * 1.5
		if score > best_score:
			best_score = score
			best = p
	return best


# ----------------------------------------------------------------------------- state machine

func _enter_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_timer = 0.0
	if new_state == State.PATROL:
		has_objective = false
	elif new_state == State.COMBAT:
		_strafe_timer = 0.0


func _update_state(delta: float) -> void:
	state_timer += delta
	var health_ratio := player.health.ratio()
	var engaging := target != null and is_instance_valid(target) and target.alive and (target_visible or time_since_seen < 1.0)
	match state:
		State.IDLE:
			_enter_state(State.PATROL)
		State.PATROL:
			if engaging:
				_enter_state(State.COMBAT)
			elif not has_objective or _objective_reached():
				_choose_patrol_objective()
		State.COMBAT:
			if health_ratio < diff.retreat_health and target_visible and _pick_retreat_cover():
				_enter_state(State.RETREAT)
			elif not engaging:
				if time_since_seen < diff.memory_time and target != null:
					_enter_state(State.SEARCH)
					_set_objective(last_seen_pos)
				else:
					target = null
					_enter_state(State.PATROL)
		State.SEARCH:
			if engaging:
				_enter_state(State.COMBAT)
			elif _objective_reached() or state_timer > 6.0:
				target = null
				_enter_state(State.PATROL)
		State.RETREAT:
			if _objective_reached():
				player.input.crouch = true
			if health_ratio > 0.85 or state_timer > (2.8 if _short_retreat else 8.0):
				_short_retreat = false
				_enter_state(State.COMBAT if engaging else State.PATROL)
			elif engaging and target_visible and target.global_position.distance_to(player.global_position) < 6.0:
				_enter_state(State.COMBAT) # cornered: fight


func _objective_reached() -> bool:
	if not has_objective:
		return true
	var a := player.global_position
	var b := objective
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) < OBJECTIVE_REACH and absf(a.y - b.y) < 2.5


func _set_objective(pos: Vector3) -> void:
	objective = pos
	has_objective = true
	path = PackedVector3Array()
	path_index = 0
	_repath_timer = 0.0


## Picks a lane/cover point: prefers the own lane in TDM, far points, and points
## towards where the enemies are.
func _choose_patrol_objective() -> void:
	if map == null:
		return
	var lanes := map.get_lanes()
	var candidates: Array = []
	for lane_name in lanes:
		for p in lanes[lane_name]:
			candidates.append({"pos": p, "lane": lane_name})
	for p in map.get_cover_points():
		candidates.append({"pos": p, "lane": "cover"})
	if candidates.is_empty():
		return
	var enemy_centroid := _enemy_centroid()
	var my_pos := player.global_position
	var best: Array = []
	for c in candidates:
		var p: Vector3 = c["pos"]
		var d := my_pos.distance_to(p)
		if d < 8.0:
			continue
		var score := randf() * 10.0
		if MatchManager.mode.uses_teams and c["lane"] == preferred_lane:
			score += 8.0
		if enemy_centroid != Vector3.INF:
			# go towards the fight, but not into the enemy spawn pocket
			var de := enemy_centroid.distance_to(p)
			score += clampf(30.0 - de, 0.0, 20.0) * 0.5
		score += minf(d, 25.0) * 0.3
		best.append({"score": score, "pos": p})
	if best.is_empty():
		_set_objective(candidates[randi() % candidates.size()]["pos"])
		return
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var pick: Dictionary = best[randi() % mini(3, best.size())]
	_set_objective(pick["pos"])


func _enemy_centroid() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for p in MatchManager.participants.values():
		if p.id == participant.id or not p.alive or p.node == null or not participant.is_enemy_of(p):
			continue
		sum += (p.node as Node3D).global_position
		n += 1
	if n == 0:
		return Vector3.INF
	return sum / float(n)


func _pick_retreat_cover() -> bool:
	if map == null or target == null:
		return false
	var best := Vector3.INF
	var best_score := -INF
	var my_pos := player.global_position
	for p in map.get_cover_points():
		var d := my_pos.distance_to(p)
		if d > 22.0 or d < 1.5:
			continue
		var away := target.global_position.distance_to(p)
		var score := away - d * 0.8
		if score > best_score:
			best_score = score
			best = p
	if best == Vector3.INF:
		return false
	_retreat_cover = best
	_set_objective(best)
	return true


# ----------------------------------------------------------------------------- movement

func _update_movement(delta: float) -> void:
	var inp := player.input
	_wants_move = false
	match state:
		State.COMBAT:
			_combat_movement(delta)
		State.PATROL, State.SEARCH, State.RETREAT:
			if has_objective and not _objective_reached():
				_follow_path(delta, state == State.PATROL and not target_visible)
			elif state == State.RETREAT:
				inp.crouch = true


func _combat_movement(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var inp := player.input
	var w := player.weapon_manager.get_current_weapon()
	var effective: float = w.data.bot_effective_range if w else 25.0
	var dist := player.global_position.distance_to(target.global_position)
	var aim_pos := target.global_position if target_visible else last_seen_pos
	if dist > effective * 1.1 or not target_visible:
		# close the distance along the nav mesh
		if not has_objective or objective.distance_to(aim_pos) > 2.0:
			_set_objective(aim_pos)
		_follow_path(delta, false)
		return
	# flanking: first take the side route (abandoned when the enemy is close)
	if _style == Style.FLANK and not _flank_done:
		if _flank_pt == Vector3.INF:
			_flank_pt = _pick_flank_point()
			if _flank_pt == Vector3.INF:
				_flank_done = true
		if not _flank_done:
			if player.global_position.distance_to(_flank_pt) < 2.0 or state_timer > 8.0 or (target_visible and dist < effective * 0.5):
				_flank_done = true
			else:
				if not has_objective or objective.distance_to(_flank_pt) > 1.0:
					_set_objective(_flank_pt)
				_follow_path(delta, not target_visible)
				return
	# in range: strafe / hold / push
	_strafe_timer -= delta
	if _strafe_timer <= 0.0 or (_dodge_t > 0.7 and _strafe_dir == 0.0):
		_strafe_timer = randf_range(0.5, 1.4) * (0.6 if _dodge_t > 0.0 else 1.0)
		if randf() < diff.strafe_chance or _dodge_t > 0.0:
			_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		else:
			_strafe_dir = 0.0
		if _style == Style.HOLD and dist > effective * 0.5 and randf() < 0.18:
			_crouch_t = randf_range(0.8, 1.6) # a peek from a crouch
	var move := Vector2(_strafe_dir, 0.0)
	if _style == Style.PUSH:
		move.x *= 0.5
		if dist > effective * 0.3:
			move.y = 0.9
	# shotguns and SMGs push in, rifles keep distance
	elif dist < effective * 0.4:
		move.y = -0.6
	elif dist > effective * 0.8 and effective < 20.0:
		move.y = 0.8
	if _crouch_t > 0.0:
		inp.crouch = true
		move *= 0.6
	_move_s = _move_s.lerp(move, 1.0 - exp(-delta * 7.0)) # no sudden changes between standing and strafing
	inp.move = _move_s
	_wants_move = move.length() > 0.1


func _follow_path(delta: float, allow_sprint: bool) -> void:
	var inp := player.input
	_repath_timer -= delta
	if path.is_empty() or _repath_timer <= 0.0:
		_recompute_path()
	if path.is_empty():
		# no nav data yet: walk straight
		_move_towards(objective, allow_sprint)
		return
	var pos := player.global_position
	while path_index < path.size():
		var wp := path[path_index]
		if Vector2(pos.x, pos.z).distance_to(Vector2(wp.x, wp.z)) < WAYPOINT_REACH:
			path_index += 1
		else:
			break
	if path_index >= path.size():
		_move_towards(objective, allow_sprint)
		return
	_move_towards(path[path_index], allow_sprint)
	if not _has_look_target:
		var look_idx := mini(path_index + 1, path.size() - 1)
		var pt := path[look_idx] + Vector3(0, EYE_HEIGHT, 0)
		# now and then a glance to the side (checks a corner) instead of staring along the route
		_glance_cd -= delta
		if _glance_cd <= 0.0:
			_glance_cd = randf_range(2.0, 4.5)
			_glance_t = randf_range(0.5, 1.1)
			_glance_yaw = randf_range(-1.1, 1.1)
		if _glance_t > 0.0:
			_glance_t -= delta
			var eye := player.get_eye_position()
			pt = eye + (pt - eye).rotated(Vector3.UP, _glance_yaw)
		_look_at_point(pt, false)


func _recompute_path() -> void:
	_repath_timer = REPATH_INTERVAL + randf() * 0.2
	path_index = 0
	if map == null or not map.navigation_ready or not nav_map.is_valid():
		path = PackedVector3Array()
		return
	var from := player.global_position + Vector3(0, 0.3, 0)
	var to := objective + Vector3(0, 0.3, 0)
	path = NavigationServer3D.map_get_path(nav_map, from, to, true)
	if path.size() > 0:
		path_index = 1 if path.size() > 1 else 0


func _move_towards(point: Vector3, allow_sprint: bool) -> void:
	var inp := player.input
	var dir := point - player.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	var local := player.global_transform.basis.inverse() * dir
	inp.move = Vector2(local.x, -local.z).normalized()
	_wants_move = true
	var far := player.global_position.distance_to(objective) > 9.0
	inp.sprint = allow_sprint and far and state != State.RETREAT


func _update_stuck(delta: float) -> void:
	if not _wants_move:
		_stuck_timer = 0.0
		_last_pos = player.global_position
		return
	var moved := player.global_position.distance_to(_last_pos)
	if moved < 0.12 * delta * 60.0 * 0.2:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_last_pos = player.global_position
	if _stuck_timer > STUCK_TIME:
		player.input.jump_pressed = true
		_repath_timer = 0.0
	if _stuck_timer > GIVE_UP_STUCK_TIME:
		_stuck_timer = 0.0
		has_objective = false
		path = PackedVector3Array()
		if state != State.COMBAT:
			_enter_state(State.PATROL)


# ----------------------------------------------------------------------------- look & aim

func _look_at_point(point: Vector3, with_error: bool) -> void:
	var eye := player.get_eye_position()
	var dir := point - eye
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	_desired_yaw = atan2(-dir.x, -dir.z)
	_desired_pitch = asin(clampf(dir.y, -1.0, 1.0))
	if with_error:
		_desired_yaw += deg_to_rad(_aim_cur.x)
		_desired_pitch += deg_to_rad(_aim_cur.y)
	_has_look_target = true


func _update_look(delta: float) -> void:
	_aim_error_timer -= delta
	if _aim_error_timer <= 0.0:
		_aim_error_timer = randf_range(0.3, 0.6)
		var e := diff.aim_error_deg
		_aim_error = Vector2(randf_range(-e, e), randf_range(-e, e) * 0.6)
	_aim_cur = _aim_cur.lerp(_aim_error, 1.0 - exp(-delta * 5.0)) # the error drifts, it does not jump
	_aim_head_timer -= delta
	if _aim_head_timer <= 0.0:
		_aim_head_timer = randf_range(0.8, 1.8) # head or chest is decided now and then, not every frame
		_aim_head = randf() < diff.headshot_bias
	var engaging := target != null and is_instance_valid(target) and target.alive and (target_visible or time_since_seen < 1.5)
	if engaging:
		var aim_point: Vector3
		if target_visible:
			var true_point := target.get_eye_position() if _aim_head else target.get_center()
			last_seen_pos = target.global_position
			if not _aim_valid:
				# the crosshair starts where the bot looks right now and travels to the enemy
				var eye := player.get_eye_position()
				_aim_point_s = eye + player.head.get_aim_direction() * maxf(eye.distance_to(true_point), 2.0)
				_aim_valid = true
			# it follows a moving enemy with a small lag (as fast as the bot can turn)
			_aim_point_s = _aim_point_s.lerp(true_point, 1.0 - exp(-delta * diff.turn_speed * 1.3))
			aim_point = _aim_point_s
		else:
			aim_point = last_seen_pos + Vector3(0, 1.2, 0)
			_aim_valid = false
		_look_at_point(aim_point, true)
		if _grenade_lob_timer > 0.0:
			_desired_pitch += 0.35
	elif state == State.RETREAT and target != null and is_instance_valid(target):
		_look_at_point(last_seen_pos + Vector3(0, 1.2, 0), false)
	if not _has_look_target:
		return
	_has_look_target = false
	var yaw := player.rotation.y
	var pitch := player.head.pitch
	var dyaw := wrapf(_desired_yaw - yaw, -PI, PI)
	var dpitch := _desired_pitch - pitch
	var max_step := diff.turn_speed * delta
	if engaging:
		max_step *= 1.5
	# eased turn: fast while far off, calm when close (no constant-speed snapping onto the target)
	var ease_k := 1.0 - exp(-diff.turn_speed * 1.4 * delta)
	dyaw = clampf(dyaw * ease_k * 1.6, -max_step, max_step)
	dpitch = clampf(dpitch * ease_k * 1.6, -max_step, max_step)
	# PlayerCamera: rotate_y(-look.x) and pitch -= look.y
	player.input.look_delta = Vector2(-dyaw, -dpitch)


func _aligned_with_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var forward := player.head.get_aim_direction()
	var to := (target.get_center() - player.get_eye_position()).normalized()
	return forward.dot(to) > cos(deg_to_rad(diff.aim_error_deg + 4.0))


# ----------------------------------------------------------------------------- weapons

func _update_weapon(delta: float) -> void:
	var inp := player.input
	var wm := player.weapon_manager
	var w := wm.get_current_weapon()
	if w == null:
		return
	var engaging := target != null and is_instance_valid(target) and target.alive and target_visible
	var dist := target.global_position.distance_to(player.global_position) if engaging else 999.0
	# ammo management
	if w.magazine <= 0 and not w.is_reloading():
		var other_index := (wm.current_index + 1) % wm.weapons.size()
		var other := wm.weapons[other_index]
		if engaging and other.magazine > 0:
			if other_index == 0:
				inp.select_primary = true
			else:
				inp.select_secondary = true
		else:
			inp.reload_pressed = true
		return
	if not engaging and not w.is_reloading() and w.magazine < int(w.data.magazine_size * 0.45) and w.reserve > 0:
		inp.reload_pressed = true
	# switch back to the primary when it has ammo and the fight is over
	if not engaging and wm.current_index == 1 and wm.weapons[0].magazine > 0 and not w.is_reloading():
		inp.select_primary = true
	if not engaging:
		_burst_timer = 0.0
		_burst_pause_timer = 0.0
		return
	# aiming down sights at range (not with the shotgun)
	_ads = dist > (8.0 if _ads else 11.0) # with hysteresis: no flickering between hip and sights
	inp.aim = _ads and not w.data.pump_action and not player.is_sprinting
	# grenade at medium range
	if _grenade_cooldown <= 0.0 and wm.grenades > 0 and dist > 9.0 and dist < 26.0 and not w.is_reloading():
		if randf() < diff.grenade_chance * delta * 10.0:
			inp.grenade_pressed = true
			_grenade_cooldown = randf_range(12.0, 25.0)
			_grenade_lob_timer = 0.6
			return
	if reaction_timer > 0.0 or _grenade_lob_timer > 0.0:
		return
	if not _aligned_with_target():
		return
	# bursts
	if _burst_pause_timer > 0.0:
		_burst_pause_timer -= delta
		return
	if _burst_timer <= 0.0:
		var shots := w.data.bot_burst_shots
		_burst_timer = shots * w.data.seconds_between_shots() + 0.05
	_burst_timer -= delta
	if w.data.automatic:
		inp.fire_held = true
	else:
		inp.fire_pressed = true
	if _burst_timer <= 0.0:
		_burst_pause_timer = diff.burst_pause * randf_range(0.7, 1.3)
