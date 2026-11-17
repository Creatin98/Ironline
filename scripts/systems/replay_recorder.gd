class_name ReplayRecorder
extends Node
## Records the visible state of every player (30 Hz, last WINDOW seconds) and plays
## the final kill of the winner back from the shooter's eyes ("last kill cam").
## Works on every machine from what that machine sees, so it needs no network traffic.
## The match is frozen when the replay runs, so the real player nodes are driven directly.

signal finished

const WINDOW := 12.0
const RATE := 30.0
const PRE_SECONDS := 3.0
const POST_SECONDS := 1.6

var playing: bool = false
var kill: Dictionary = {}

var _frames: Array = [] # {"t": float, "p": {id: [pos, yaw, pitch, crouch, alive, weapon, fired]}}
var _kills: Array = [] # {"t", "killer", "victim", "weapon", "headshot"}
var _accum: float = 0.0
var _cursor: float = 0.0
var _end_time: float = 0.0
var _last_index: int = 0
var _alive_state: Dictionary = {}
var _camera: Camera3D
var _killer: Player


func _physics_process(delta: float) -> void:
	if playing:
		return
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
		if n == null or not is_instance_valid(n):
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


## Starts the playback. `camera` is the Camera3D the replay moves.
func start(final_kill: Dictionary, camera: Camera3D) -> bool:
	if final_kill.is_empty() or _frames.size() < 2:
		return false
	var killer := MatchManager.get_participant(int(final_kill["killer"]))
	if killer == null or killer.node == null or not is_instance_valid(killer.node):
		return false
	kill = final_kill
	_camera = camera
	_killer = killer.node as Player
	_cursor = maxf(float(_frames[0]["t"]), float(kill["t"]) - PRE_SECONDS)
	_end_time = minf(_now(), float(kill["t"]) + POST_SECONDS)
	_last_index = _index_at(_cursor)
	_alive_state.clear()
	for p in MatchManager.participants.values():
		var n := p.node as Player
		if n != null and is_instance_valid(n):
			n.enter_replay_mode(n == _killer)
	camera.current = true
	playing = true
	_apply(_cursor, true)
	return true


func skip() -> void:
	if playing:
		_finish()


func get_duration() -> float:
	return _end_time - (float(_frames[0]["t"]) if _frames.size() > 0 else 0.0)


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
		var p := MatchManager.get_participant(int(id))
		if p == null or p.node == null or not is_instance_valid(p.node):
			continue
		var n := p.node as Player
		var sa: Array = a["p"][id]
		var sb: Array = b["p"].get(id, sa)
		var pos: Vector3 = (sa[0] as Vector3).lerp(sb[0], w)
		var yaw := lerp_angle(float(sa[1]), float(sb[1]), w)
		var pitch := lerpf(float(sa[2]), float(sb[2]), w)
		n.replay_pose(pos, yaw, pitch, bool(sa[3]))
		var alive: bool = sa[4]
		if first or _alive_state.get(id) != alive:
			n.replay_set_alive(alive, first or not alive_changed_visibly(id, alive))
			_alive_state[id] = alive
		n.weapon_manager.set_remote_weapon_index(int(sa[5]))
	# fire events (muzzle flash + sound) for frames we passed
	for f in range(_last_index + 1, i + 1):
		var fr: Dictionary = _frames[f]
		for id in fr["p"]:
			if bool((fr["p"][id] as Array)[6]):
				var p2 := MatchManager.get_participant(int(id))
				if p2 and p2.node and is_instance_valid(p2.node):
					(p2.node as Player).replay_shot()
	_last_index = i
	# the camera sits in the killer's eyes
	if _killer != null and is_instance_valid(_killer) and a["p"].has(int(kill["killer"])):
		var s: Array = a["p"][int(kill["killer"])]
		var sb2: Array = b["p"].get(int(kill["killer"]), s)
		var kpos: Vector3 = (s[0] as Vector3).lerp(sb2[0], w)
		var kyaw := lerp_angle(float(s[1]), float(sb2[1]), w)
		var kpitch := lerpf(float(s[2]), float(sb2[2]), w)
		var eye := (Player.CROUCH_HEIGHT if bool(s[3]) else Player.STAND_HEIGHT) - Player.EYE_BELOW_TOP
		_camera.global_transform = Transform3D(Basis.from_euler(Vector3(kpitch, kyaw, 0.0), EULER_ORDER_YXZ), kpos + Vector3(0.0, eye, 0.0))


func alive_changed_visibly(id: int, alive: bool) -> bool:
	# a player that was alive and now is not dies in view; everything else just switches
	return _alive_state.has(id) and bool(_alive_state[id]) and not alive
