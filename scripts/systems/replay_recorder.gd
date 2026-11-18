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
## The killer's shot hit an enemy in the replay (hitmarker + sounds of the killer's view).
signal killer_hit(headshot: bool, killed: bool)

const WINDOW := 12.0
const RATE := 30.0
const SLOWMO_SCALE := 0.3 # speed of the slow motion part of the last kill cam
const SLOWMO_AFTER_KILL := 0.7 # replay seconds of slow motion after the kill
const SLOWMO_RAMP := 6.0 # time scale change per real second when slowing down

var playing: bool = false
var ghost_mode: bool = false
## Killcam: how far the killer aims down the sights (0..1, smoothed); drives hands position, FOV and crosshair.
var killer_aim: float = 0.0
var _killer_aim_target: float = 0.0
var kill: Dictionary = {}

var _frames: Array = [] # {"t": float, "p": {id: [pos, yaw, pitch, crouch, alive, weapon, fired, aiming, hit_code]}}
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
var _slow_from: float = -1.0 # replay time at which the slow motion starts (< 0 = none)
var _time_changed: bool = false # we touched Engine.time_scale, so we must restore it


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
		snap[p.id] = [n.global_position, n.rotation.y, n.head.pitch, n.is_crouching, n.alive, n.weapon_manager.current_index, n.consume_shot_flag(), n.is_aiming, n.consume_hit_flag(), n.weapon_manager.get_current_weapon().is_reloading()]
	var t := _now()
	_frames.append({"t": t, "p": snap})
	while _frames.size() > 2 and float(_frames[0]["t"]) < t - WINDOW:
		_frames.pop_front()
	while _kills.size() > 0 and float(_kills[0]["t"]) < t - WINDOW - 5.0:
		_kills.pop_front()


func note_kill(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	var death := {}
	var vp := MatchManager.get_participant(victim_id)
	if vp != null and vp.node != null and is_instance_valid(vp.node):
		death = (vp.node as Player).last_death.duplicate()
	_kills.append({"t": _now(), "killer": killer_id, "victim": victim_id, "weapon": weapon_id, "headshot": headshot, "assists": MatchManager.kill_assists.get(victim_id, []), "death": death})


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


## Last kill cam: poses the real (frozen) player nodes. Runs at normal speed first and switches to
## slow motion when the killing burst begins (first shot shortly before the kill) until the end.
func start(final_kill: Dictionary, camera: Camera3D, pre: float = 3.0, post: float = 1.0) -> bool:
	var ok := _begin(final_kill, camera, false, null, pre, post)
	if ok:
		_slow_from = _find_slowmo_start(float(final_kill["t"]), int(final_kill["killer"]))
	return ok


## The first shot of the killer within the last 1.2 s before the kill (at least 0.35 s before it).
func _find_slowmo_start(kill_t: float, killer_id: int) -> float:
	var start := kill_t - 0.5
	for f in _frames:
		var ft: float = f["t"]
		if ft < kill_t - 1.2 or ft > kill_t:
			continue
		var s: Variant = (f["p"] as Dictionary).get(killer_id)
		if s != null and bool((s as Array)[6]):
			start = minf(ft, kill_t - 0.35)
			break
	return maxf(start, _cursor + 0.1)


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
	Ragdoll.clear_all()
	_alive_state.clear()
	killer_aim = 0.0
	_killer_aim_target = 0.0
	_victim_dead_shown = false
	_slow_from = -1.0
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
	var glass := GlassField.find(get_tree())
	if glass != null:
		glass.replay_begin(_cursor) # the windows are shown as they were at the start of the replay
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


## Last kill cam: the view zooms towards the victim during the slow motion so the kill is easy to see
## (a distant victim is only a few pixels tall otherwise). `base_fov` is the normal FOV.
func last_kill_fov(base_fov: float) -> float:
	if ghost_mode or _slow_from < 0.0 or not _targets.has(_killer_id) or not _targets.has(int(kill["victim"])):
		return base_fov
	var killer: Player = _targets[_killer_id]
	var victim: Player = _targets[int(kill["victim"])]
	if killer == null or victim == null or not is_instance_valid(killer) or not is_instance_valid(victim):
		return base_fov
	var dist := maxf(3.0, killer.get_eye_position().distance_to(victim.global_position + Vector3(0, 0.9, 0)))
	var target := clampf(rad_to_deg(2.0 * atan(4.5 / dist)), 24.0, base_fov)
	var t := smoothstep(_slow_from - 0.5, _slow_from + 0.6, _cursor)
	return lerpf(base_fov, target, t)


## FOV the killer's weapon has when aiming down the sights.
func killer_ads_fov() -> float:
	var n: Player = _targets.get(_killer_id)
	if n != null and is_instance_valid(n):
		var w := n.weapon_manager.get_current_weapon()
		if w != null:
			return w.data.effective_ads_fov(GameSettings.fov)
	return GameSettings.fov


## Killcam: field of view of the killer's scope picture while the killer aims a scoped weapon (0 = no scope picture).
func killer_scope_fov() -> float:
	var n: Player = _targets.get(_killer_id)
	if playing and n != null and is_instance_valid(n):
		var w := n.weapon_manager.get_current_weapon()
		if w != null and w.data.scoped:
			return w.scope_fov()
	return 0.0


func _clear_targets() -> void:
	killer_aim = 0.0
	Ragdoll.clear_all() # corpses of the replay
	var glass := GlassField.find(get_tree())
	if glass != null:
		glass.replay_end() # back to the real state of the windows
	if not ghost_mode:
		for id in _targets:
			var rn: Player = _targets[id]
			if rn != null and is_instance_valid(rn):
				rn.replay_aim(0.0)
				rn.set_replay_sleeves_hidden(false)
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
	_restore_time()
	if not playing:
		return
	playing = false
	_clear_targets()


func _process(delta: float) -> void:
	if not playing:
		return
	# delta is already scaled by Engine.time_scale, so the slow motion only has to set the scale
	if _slow_from >= 0.0:
		var real_dt := delta / maxf(Engine.time_scale, 0.01)
		# slow motion from the killing burst until shortly after the kill, then normal speed again
		# so the victim can be seen falling to the ground
		var target := SLOWMO_SCALE if (_cursor >= _slow_from and _cursor < float(kill["t"]) + SLOWMO_AFTER_KILL) else 1.0
		Engine.time_scale = move_toward(Engine.time_scale, target, SLOWMO_RAMP * real_dt)
		AudioServer.playback_speed_scale = Engine.time_scale # deeper sound in slow motion
		_time_changed = true
	var real_step := delta / maxf(Engine.time_scale, 0.01)
	killer_aim = move_toward(killer_aim, _killer_aim_target, real_step * 7.0)
	_cursor += delta
	if _cursor >= _end_time:
		_finish()
		return
	_apply(_cursor, false)


func _finish() -> void:
	playing = false
	_restore_time()
	_clear_targets()
	finished.emit()


func _restore_time() -> void:
	_slow_from = -1.0
	if _time_changed:
		_time_changed = false
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0


func is_slow_motion() -> bool:
	return playing and Engine.time_scale < 0.95


func _exit_tree() -> void:
	_restore_time() # never leave the game in slow motion


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
			n.replay_set_alive(alive, first or not (was_alive and not alive), kill.get("death", {}) if int(id) == int(kill["victim"]) else {})
			_alive_state[id] = alive
		n.weapon_manager.set_remote_weapon_index(int(sa[5]))
	# fire events (muzzle flash + sound) of the frames we passed since the last call
	if not first:
		for f in range(_index_at(_prev_cursor) + 1, i + 1):
			var fr: Dictionary = _frames[f]
			for id in fr["p"]:
				var st: Array = fr["p"][id]
				if bool(st[6]):
					var shooter: Player = _targets.get(int(id))
					if shooter != null and is_instance_valid(shooter):
						shooter.replay_shot()
				# a reload that starts / ends in this frame (the killer's hands show it)
				if st.size() > 9 and f > 0:
					var prev_st: Variant = (_frames[f - 1]["p"] as Dictionary).get(id)
					if prev_st != null and (prev_st as Array).size() > 9 and bool(st[9]) != bool((prev_st as Array)[9]):
						var rp: Player = _targets.get(int(id))
						if rp != null and is_instance_valid(rp):
							rp.weapon_manager.replay_reload(bool(st[9]))
				if int(id) == _killer_id and st.size() > 8 and int(st[8]) != 0:
					var code := int(st[8])
					killer_hit.emit(code & HitFeedback.HEAD != 0, code & HitFeedback.KILL != 0)
	if not first:
		var gf := GlassField.find(get_tree())
		if gf != null:
			gf.replay_step(_prev_cursor, t) # windows cracked or shot out in this stretch
	_prev_cursor = t
	# the recording may end right at the kill: make sure the victim goes down on screen
	if t >= float(kill["t"]) and not _victim_dead_shown:
		_victim_dead_shown = true
		var victim: Player = _targets.get(int(kill["victim"]))
		if victim != null and is_instance_valid(victim) and bool(_alive_state.get(int(kill["victim"]), true)):
			victim.replay_set_alive(false, false, kill.get("death", {}))
			_alive_state[int(kill["victim"])] = false
	# the camera sits in the killer's eyes (holds the last pose if the data ends)
	if a["p"].has(_killer_id) and _targets.has(_killer_id):
		var s: Array = a["p"][_killer_id]
		var sb2: Array = b["p"].get(_killer_id, s)
		_killer_aim_target = 1.0 if (s.size() > 7 and bool(s[7])) else 0.0
		var kpos: Vector3 = (s[0] as Vector3).lerp(sb2[0], w)
		var kyaw := lerp_angle(float(s[1]), float(sb2[1]), w)
		var kpitch := lerpf(float(s[2]), float(sb2[2]), w)
		var eye := (Player.CROUCH_HEIGHT if bool(s[3]) else Player.STAND_HEIGHT) - Player.EYE_BELOW_TOP
		_camera.global_transform = Transform3D(Basis.from_euler(Vector3(kpitch, kyaw, 0.0), EULER_ORDER_YXZ), kpos + Vector3(0.0, eye, 0.0))
		var kn: Player = _targets[_killer_id]
		if kn != null and is_instance_valid(kn):
			kn.replay_viewmodel(killer_aim, _camera.global_transform)
