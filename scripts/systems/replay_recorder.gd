class_name ReplayRecorder
extends Node
## Records the visible state of every player (30 Hz, last WINDOW seconds) and plays moments back
## from the shooter's eyes. Works on every machine from what that machine sees (no network traffic).
##
## Two modes:
##  * Last kill cam (round end): the match is frozen, the real player nodes are posed directly.
##  * Killcam (after our death): the match keeps running, so the replay poses "ghost" copies of the
##    players (the real ones are hidden by the Game) and shows the last seconds of the killer's view.

signal finished

const WINDOW := 12.0
const RATE := 30.0

var playing: bool = false
var ghost_mode: bool = false
var kill: Dictionary = {}

var _frames: Array = [] # {"t": float, "p": {id: [pos, yaw, pitch, crouch, alive, weapon, fired]}}
var _kills: Array = [] # {"t", "killer", "victim", "weapon", "headshot"}
var _accum: float = 0.0
var _cursor: float = 0.0
var _prev_cursor: float = 0.0
var _end_time: float = 0.0
var _alive_state: Dictionary = {}
var _targets: Dictionary = {} # id -> Player that is posed (real node or ghost)
var _camera: Camera3D
var _killer_id: int = 0
var _victim_dead_shown: bool = false
var ghost_scene: PackedScene


func _physics_process(delta: float) -> void:
	if playing and not ghost_mode:
		return # the frozen match is being replayed, nothing new to record
	_accum += delta
	if _accum < 1.0 / RATE:
		return
	_accum = fmod(_accum, 1.0 / RATE)
	_record()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _record() -> void:
	var snap: Dictionary = {}
	for p in MatchManager.participants.values():
		var n := p.node as Player
		if n == null or not is_instance_valid(n) or n.replay_mode:
			continue
		snap[p.id] = [n.global_position, n.rotation.y, n.head.pitch, n.is_crouching, n.alive, n.weapon_manager.current_index, n.consume_shot_flag()]
	var t := _now()
	_frames.append({"t": t, "p": snap})
	while _frames.size() > 2 and float(_frames[0]["t"]) < t - WINDOW:
		_frames.pop_front()
	while _kills.size() > 0 and float(_kills[0]["t"]) < t - WINDOW - 5.0:
		_kills.pop_front()


func note_kill(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	_kills.append({"t": _now(), "killer": killer_id, "victim": victim_id, "weapon": weapon_id, "headshot": headshot})


## The most recent kill that counts for the winner (team or player) and is still covered by the recording.
func find_final_kill(winner_team: int, winner_id: int) -> Dictionary:
	if _frames.size() < 2:
		return {}
	var first_t: float = _frames[0]["t"]
	for i in range(_kills.size() - 1, -1, -1):
		var k: Dictionary = _kills[i]
		var killer := MatchManager.get_participant(int(k["killer"]))
		var victim := MatchManager.get_participant(int(k["victim"]))
		if killer == null or victim == null or killer.id == victim.id or not killer.is_enemy_of(victim):
			continue
		var counts := false
		if MatchManager.mode.uses_teams:
			counts = winner_team != Teams.Team.NONE and killer.team == winner_team
		else:
			counts = winner_id != 0 and killer.id == winner_id
		if not counts:
			continue
		if float(k["t"]) - 1.0 < first_t:
			return {} # recording does not reach back far enough
		return k
	return {}


## The latest kill of `killer_id` on `victim_id` (the one that just killed us).
func find_kill(victim_id: int, killer_id: int) -> Dictionary:
	if _frames.size() < 2:
		return {}
	for i in range(_kills.size() - 1, -1, -1):
		var k: Dictionary = _kills[i]
		if int(k["victim"]) == victim_id and int(k["killer"]) == killer_id:
			return k
	return {}


## Last kill cam: poses the real (frozen) player nodes.
func start(final_kill: Dictionary, camera: Camera3D, pre: float = 3.0, post: float = 1.6) -> bool:
	return _begin(final_kill, camera, false, null, pre, post)


## Killcam: poses ghost copies, `parent` receives them.
func start_ghost_replay(final_kill: Dictionary, camera: Camera3D, parent: Node3D, pre: float = 5.0, post: float = 0.9) -> bool:
	return _begin(final_kill, camera, true, parent, pre, post)


func _begin(final_kill: Dictionary, camera: Camera3D, ghosts: bool, parent: Node3D, pre: float, post: float) -> bool:
	if final_kill.is_empty() or _frames.size() < 2:
		return false
	var first_t: float = _frames[0]["t"]
	var kill_t: float = final_kill["t"]
	if kill_t - first_t < 1.0:
		return false
	var killer := MatchManager.get_participant(int(final_kill["killer"]))
	if killer == null:
		return false
	kill = final_kill
	_killer_id = int(kill["killer"])
	_camera = camera
	ghost_mode = ghosts
	_cursor = maxf(first_t, kill_t - pre)
	_prev_cursor = _cursor
	_end_time = kill_t + post
	_alive_state.clear()
	_victim_dead_shown = false
	_targets.clear()
	var start_frame: Dictionary = _frames[_index_at(_cursor)]
	for id in start_frame["p"]:
		var p := MatchManager.get_participant(int(id))
		if p == null:
			continue
		var node: Player = null
		if ghosts:
			node = _make_ghost(p, parent)
		elif p.node != null and is_instance_valid(p.node):
			node = p.node as Player
		if node != null:
			node.enter_replay_mode(int(id) == _killer_id)
			_targets[int(id)] = node
	if not _targets.has(_killer_id):
		_clear_targets()
		return false
	camera.current = true
	playing = true
	_apply(_cursor, true)
	return true


func _make_ghost(p: Participant, parent: Node3D) -> Player:
	if ghost_scene == null:
		return null
	var g: Player = ghost_scene.instantiate()
	parent.add_child(g)
	g.setup(p, GameDirector.get_class_data(p.class_id), false)
	g.remove_from_group("players") # bots, grenades and hitscans must not see the replay copies
	g.collision_layer = 0
	g.collision_mask = 0
	g.human_controller.deactivate()
	return g


func _clear_targets() -> void:
	if ghost_mode:
		for id in _targets:
			var n: Player = _targets[id]
			if n != null and is_instance_valid(n):
				n.queue_free()
	_targets.clear()


func skip() -> void:
	if playing:
		_finish()


## Stops a running replay without emitting `finished` (the caller restores the scene itself).
func abort() -> void:
	if not playing:
		return
	playing = false
	_clear_targets()


func _process(delta: float) -> void:
	if not playing:
		return
	_cursor += delta
	if _cursor >= _end_time:
		_finish()
		return
	_apply(_cursor, false)


func _finish() -> void:
	playing = false
	_clear_targets()
	finished.emit()


## Index of the last frame with time <= t.
func _index_at(t: float) -> int:
	var lo := 0
	var hi := _frames.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(_frames[mid]["t"]) <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _apply(t: float, first: bool) -> void:
	var i := _index_at(t)
	var a: Dictionary = _frames[i]
	var b: Dictionary = _frames[mini(i + 1, _frames.size() - 1)]
	var span := float(b["t"]) - float(a["t"])
	var w := clampf((t - float(a["t"])) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	for id in a["p"]:
		var n: Player = _targets.get(int(id))
		if n == null or not is_instance_valid(n):
			continue
		var sa: Array = a["p"][id]
		var sb: Array = b["p"].get(id, sa)
		n.replay_pose((sa[0] as Vector3).lerp(sb[0], w), lerp_angle(float(sa[1]), float(sb[1]), w), lerpf(float(sa[2]), float(sb[2]), w), bool(sa[3]))
		var alive: bool = sa[4]
		if first or _alive_state.get(id) != alive:
			var was_alive: bool = _alive_state.has(id) and bool(_alive_state[id])
			n.replay_set_alive(alive, first or not (was_alive and not alive))
			_alive_state[id] = alive
		n.weapon_manager.set_remote_weapon_index(int(sa[5]))
	# fire events (muzzle flash + sound) of the frames we passed since the last call
	if not first:
		for f in range(_index_at(_prev_cursor) + 1, i + 1):
			var fr: Dictionary = _frames[f]
			for id in fr["p"]:
				if bool((fr["p"][id] as Array)[6]):
					var shooter: Player = _targets.get(int(id))
					if shooter != null and is_instance_valid(shooter):
						shooter.replay_shot()
	_prev_cursor = t
	# the recording may end right at the kill: make sure the victim goes down on screen
	if t >= float(kill["t"]) and not _victim_dead_shown:
		_victim_dead_shown = true
		var victim: Player = _targets.get(int(kill["victim"]))
		if victim != null and is_instance_valid(victim) and bool(_alive_state.get(int(kill["victim"]), true)):
			victim.replay_set_alive(false, false)
			_alive_state[int(kill["victim"])] = false
	# the camera sits in the killer's eyes (holds the last pose if the data ends)
	if a["p"].has(_killer_id) and _targets.has(_killer_id):
		var s: Array = a["p"][_killer_id]
		var sb2: Array = b["p"].get(_killer_id, s)
		var kpos: Vector3 = (s[0] as Vector3).lerp(sb2[0], w)
		var kyaw := lerp_angle(float(s[1]), float(sb2[1]), w)
		var kpitch := lerpf(float(s[2]), float(sb2[2]), w)
		var eye := (Player.CROUCH_HEIGHT if bool(s[3]) else Player.STAND_HEIGHT) - Player.EYE_BELOW_TOP
		_camera.global_transform = Transform3D(Basis.from_euler(Vector3(kpitch, kyaw, 0.0), EULER_ORDER_YXZ), kpos + Vector3(0.0, eye, 0.0))
