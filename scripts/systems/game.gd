extends Node3D
## Match scene root: loads the map, builds the roster, spawns/respawns
## participants and wires the HUD, scoreboard, pause and end screens.
##
## Online: the host (server) builds the roster and decides every spawn; clients
## only create player nodes when the server tells them to (remote_spawn).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GRENADE_SCENE := preload("res://scenes/weapons/grenade.tscn")
const BotControllerScript := preload("res://scripts/bots/bot_controller.gd")
## Humans wait this long after dying (killcam); Space skips after KILLCAM_SKIP_AFTER seconds.
const HUMAN_RESPAWN_DELAY := 6.0
const KILLCAM_SECONDS_BEFORE := 5.0 # how much of the killer's view leads up to our death
const KILLCAM_SECONDS_AFTER := 0.9
const OUTRO_TIME := 3.2 # the camera leaves the last-kill scene and rises over the map
const OUTRO_RESULTS_DELAY := 1.6 # the scoreboard fades in while the camera is still moving
const KILLCAM_SKIP_AFTER := 0.5 # fall (~0.4 s) + fade, then Space skips at once

@onready var map_container: Node3D = $MapContainer
@onready var players_container: Node3D = $Players
@onready var projectiles_container: Node3D = $Projectiles
@onready var ui_layer: CanvasLayer = $UI
@onready var hud: HUD = $UI/HUD
@onready var scoreboard: Scoreboard = $UI/Scoreboard
@onready var match_end: MatchEndScreen = $UI/MatchEnd
@onready var pause_menu: PauseMenu = $UI/PauseMenu

var map: Node3D
var spawn_system: SpawnSystem
var local_player: Player
var _respawn_queue: Dictionary = {}
var _paused: bool = false

var recorder: ReplayRecorder
var _cam: Camera3D # shared by killcam and last-kill replay
var _killcam_active: bool = false
var _dead_elapsed: float = 0.0
var _fade: ColorRect
var _death_seq: int = 0 # invalidates a running death sequence (respawn, round end)
var _replay_active: bool = false
var _cam_ui: Control
var _cam_title: Label
var _cam_sub: Label
var _cam_hint: Label
var _cam_name: Label
var _cam_detail: Label
var _cam_assist: Label
var _outro_active: bool = false
var _outro_orbit: bool = false
var _outro_center: Vector3 = Vector3.ZERO
var _outro_dir: Vector3 = Vector3(0.0, 0.8, 0.6)
var _outro_dist: float = 60.0
var _outro_angle: float = 0.0
var _results_shown: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.stop_music()
	_load_map()
	spawn_system = SpawnSystem.new(get_tree())
	MatchManager.local_participant_id = multiplayer.get_unique_id()
	GameEvents.match_state_changed.connect(_on_match_state_changed)
	GameEvents.match_ended.connect(_on_match_ended)
	match_end.next_round_requested.connect(_on_next_round)
	match_end.lobby_requested.connect(_on_back_to_lobby)
	match_end.map_chosen.connect(_on_map_chosen)
	match_end.leave_requested.connect(_leave_to_menu)
	pause_menu.class_selected.connect(_on_class_selected)
	pause_menu.hud_edit_requested.connect(func() -> void:
		pause_menu.close()
		hud.begin_edit())
	hud.edit_finished.connect(func() -> void: pause_menu.open())
	match_end.class_selected.connect(_on_class_selected)
	pause_menu.resumed.connect(_close_pause)
	pause_menu.leave_requested.connect(_leave_to_menu)
	match_end.configure_for_network()
	recorder = ReplayRecorder.new()
	recorder.name = "ReplayRecorder"
	recorder.ghost_scene = PLAYER_SCENE
	add_child(recorder)
	recorder.finished.connect(_on_replay_finished)
	GameEvents.participant_killed.connect(recorder.note_kill)
	_build_cam_overlay()
	AudioManager.play_2d("round_start", -2.0)

	if NetworkManager.is_client():
		# the server owns the roster; wait for its state and spawn messages
		hud.center_label.text = "Verbinde mit Match …"
		NetworkManager.notify_game_loaded(self)
		return
	_create_roster()
	if NetworkManager.is_host():
		hud.center_label.text = "Warte auf Spieler …"
		NetworkManager.all_peers_loaded.connect(_begin_match_flow, CONNECT_ONE_SHOT)
		NetworkManager.notify_game_loaded(self)
	else:
		NetworkManager.notify_game_loaded(self)
		_begin_match_flow()


func _exit_tree() -> void:
	NetworkManager.notify_game_unloaded(self)


## Server/offline: everybody spawns during the warmup countdown with controls locked.
func _begin_match_flow() -> void:
	hud.center_label.text = ""
	NetworkManager.broadcast_full_state()
	MatchManager.begin_warmup()
	for p in MatchManager.participants.values():
		_spawn_participant(p)
		(p.node as Player).set_controls_enabled(false)


func _load_map() -> void:
	var info := GameDirector.get_map_info(MatchManager.config.map_id)
	var scene: PackedScene = load(info["scene"])
	map = scene.instantiate()
	map_container.add_child(map)


func _create_roster() -> void:
	var cfg := MatchManager.config
	var humans := 0
	if NetworkManager.is_host():
		var ids := NetworkManager.peers.keys()
		ids.sort()
		for id in ids:
			var info: Dictionary = NetworkManager.peers[id]
			MatchManager.add_human(int(id), String(info["name"]), int(info["team"]), String(info["class_id"]))
			humans += 1
	else:
		MatchManager.add_human(MatchManager.local_participant_id, GameSettings.player_name, cfg.local_team, cfg.local_class_id)
		humans = 1
	if cfg.bots_enabled and MatchManager.is_authority():
		var count := clampi(cfg.bot_count, 0, maxi(0, cfg.max_participants() - humans))
		var names := GameDirector.random_bot_names(count)
		var class_ids := GameDirector.get_class_ids()
		for i in count:
			var class_id: String = class_ids[randi() % class_ids.size()]
			MatchManager.add_bot(names[i], cfg.bot_difficulty, class_id, Teams.Team.NONE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and hud.is_editing():
		hud.end_edit() # Esc leaves the HUD editor and returns to the pause menu
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump") and not _paused:
		if _replay_active:
			recorder.skip()
			get_viewport().set_input_as_handled()
			return
		if _outro_active and not _results_shown:
			_show_results()
			get_viewport().set_input_as_handled()
			return
		if local_player != null and not local_player.alive and MatchManager.state == MatchManager.State.RUNNING and _dead_elapsed >= KILLCAM_SKIP_AFTER:
			NetworkManager.request_skip_respawn()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause") and MatchManager.state != MatchManager.State.ENDED:
		if _paused:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_killcam(delta)
	_update_outro(delta)
	if not MatchManager.is_authority() or MatchManager.state != MatchManager.State.RUNNING:
		return
	var ids := _respawn_queue.keys()
	for id in ids:
		_respawn_queue[id] = float(_respawn_queue[id]) - delta
		if float(_respawn_queue[id]) <= 0.0:
			_respawn_queue.erase(id)
			var p := MatchManager.get_participant(id)
			if p:
				_spawn_participant(p)


# ----------------------------------------------------------------------------- spawning

func _on_match_state_changed(state: int) -> void:
	if state == MatchManager.State.RUNNING:
		for p in MatchManager.participants.values():
			if MatchManager.is_authority() and not p.alive:
				_spawn_participant(p)
			elif p.node and is_instance_valid(p.node):
				(p.node as Player).set_controls_enabled(not _paused or not (p.node as Player).is_local)


## Creates the Player node of a participant once (server and clients).
func _ensure_player(p: Participant) -> Player:
	var player: Player = p.node as Player
	if player != null and is_instance_valid(player):
		return player
	player = PLAYER_SCENE.instantiate()
	players_container.add_child(player)
	var local := p.id == MatchManager.local_participant_id
	player.setup(p, GameDirector.get_class_data(p.class_id), local)
	if p.is_bot and MatchManager.is_authority():
		var bc: BotController = BotControllerScript.new()
		bc.name = "BotController"
		player.add_child(bc)
		bc.setup(player, p)
	player.died.connect(_on_player_died)
	if local:
		local_player = player
		player.add_to_group("local_player")
	return player


func _spawn_participant(p: Participant) -> void:
	var player := _ensure_player(p)
	_sync_class(p, player)
	var t := spawn_system.pick_spawn(p, MatchManager.mode.uses_teams)
	_finish_spawn(p, player, t)
	NetworkManager.broadcast_spawn(p.id, t.origin, t.basis.get_euler().y, p.class_id)


## A class chosen since the last spawn takes effect now.
func _sync_class(p: Participant, player: Player) -> void:
	var wanted := GameDirector.get_class_data(p.class_id)
	if player.class_data != wanted:
		player.apply_class(wanted)


func _finish_spawn(p: Participant, player: Player, t: Transform3D) -> void:
	if player.is_local:
		_end_killcam()
	player.respawn_at(t)
	MatchManager.mark_spawned(p.id, player)
	if MatchManager.state != MatchManager.State.RUNNING or (_paused and player.is_local):
		player.set_controls_enabled(false)
	if p.id == MatchManager.local_participant_id:
		AudioManager.play_2d("respawn", -8.0)
		if not _paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		AudioManager.play_3d("respawn", t.origin + Vector3.UP, -16.0, 0.0, 20.0)


## Humans get the longer killcam delay, bots respawn at the mode's normal speed.
func _respawn_delay_for(p: Participant) -> float:
	if p == null or p.is_bot:
		return MatchManager.mode.respawn_delay
	return maxf(MatchManager.mode.respawn_delay, HUMAN_RESPAWN_DELAY)


func _on_player_died(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	var assisters: Array = []
	var victim_p := MatchManager.get_participant(victim_id)
	if victim_p != null and victim_p.node != null and is_instance_valid(victim_p.node):
		assisters = (victim_p.node as Player).health.get_assisters(killer_id)
	MatchManager.report_kill(victim_id, killer_id, weapon_id, headshot, assisters)
	var delay := _respawn_delay_for(MatchManager.get_participant(victim_id))
	if MatchManager.is_authority() and MatchManager.state == MatchManager.State.RUNNING:
		_respawn_queue[victim_id] = delay
	if victim_id == MatchManager.local_participant_id:
		GameEvents.local_player_died.emit(killer_id, delay)
		_dead_elapsed = 0.0
		if _killcam_possible(killer_id):
			_death_sequence(killer_id)
		else:
			_death_camera(killer_id)


## Server: the player asks to skip the killcam wait (allowed after KILLCAM_SKIP_AFTER seconds).
func skip_respawn(id: int) -> void:
	if not MatchManager.is_authority() or not _respawn_queue.has(id):
		return
	var delay := _respawn_delay_for(MatchManager.get_participant(id))
	if float(_respawn_queue[id]) <= delay - KILLCAM_SKIP_AFTER:
		_respawn_queue[id] = 0.0


# ----------------------------------------------------------------------------- killcam

func _build_cam_overlay() -> void:
	_cam = Camera3D.new()
	_cam.name = "ReplayCamera"
	_cam.near = 0.04
	_cam.far = 600.0
	add_child(_cam)
	_cam.current = false
	_cam_ui = Control.new()
	_cam_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cam_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_ui.visible = false
	ui_layer.add_child(_cam_ui)
	_cam_ui.move_to_front()
	# dark vignette around the picture (killcam / last kill)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float strength = 0.82;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.9);
	float d = length(p);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.26, 0.74, d) * strength);
}"""
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	vignette.material = mat
	_cam_ui.add_child(vignette)
	_cam_title = UITheme.label("", 34, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cam_title.offset_top = 50.0
	_cam_title.offset_bottom = 100.0
	_cam_ui.add_child(_cam_title)
	_cam_sub = UITheme.label("", 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER) # unused, kept for compatibility
	_cam_sub.visible = false
	_cam_ui.add_child(_cam_sub)
	# bottom block: who killed us (name), with what, and who assisted
	_cam_name = UITheme.label("", 46, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_name.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cam_name.offset_top = -215.0
	_cam_name.offset_bottom = -155.0
	_cam_ui.add_child(_cam_name)
	_cam_detail = UITheme.label("", 24, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_detail.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cam_detail.offset_top = -152.0
	_cam_detail.offset_bottom = -118.0
	_cam_ui.add_child(_cam_detail)
	_cam_assist = UITheme.label("", 22, Color(0.5, 0.78, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_cam_assist.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cam_assist.offset_top = -116.0
	_cam_assist.offset_bottom = -84.0
	_cam_ui.add_child(_cam_assist)
	_cam_hint = UITheme.label("", 20, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cam_hint.offset_top = -64.0
	_cam_hint.offset_bottom = -30.0
	_cam_ui.add_child(_cam_hint)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	ui_layer.add_child(_fade)
	_fade.move_to_front()


## Fills the bottom block: killer name (team colour), weapon + headshot, assists.
func _fill_cam_info(kill: Dictionary, show_victim: bool) -> void:
	var killer := MatchManager.get_participant(int(kill["killer"]))
	var victim := MatchManager.get_participant(int(kill["victim"]))
	_cam_name.text = killer.display_name if killer else "?"
	_cam_name.add_theme_color_override("font_color", Teams.color_of(killer.team) if killer else UITheme.TEXT)
	var weapon_name: String = HUD.WEAPON_LABELS.get(String(kill["weapon"]), String(kill["weapon"]))
	var detail := weapon_name
	if bool(kill["headshot"]):
		detail += "   •   KOPFSCHUSS"
	if show_victim and victim != null:
		detail += "   ▸   %s" % victim.display_name
	_cam_detail.text = detail
	_cam_detail.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25) if bool(kill["headshot"]) else UITheme.TEXT_DIM)
	var names: Array[String] = []
	for aid in kill.get("assists", []):
		var a := MatchManager.get_participant(int(aid))
		if a != null:
			names.append(a.display_name)
	_cam_assist.text = ("Assist: %s" % ", ".join(names)) if not names.is_empty() else ""


## Killcam: replay of the last seconds of the killer's view, ending with our death.
## The real players keep playing (hidden), the replay poses ghost copies.
func _killcam_possible(killer_id: int) -> bool:
	if not GameSettings.killcams or killer_id == MatchManager.local_participant_id or _replay_active:
		return false
	return MatchManager.get_participant(killer_id) != null and not recorder.find_kill(MatchManager.local_participant_id, killer_id).is_empty()


## Fall of the camera, short fade to black, then the killcam fades in (total ~0.5 s).
func _death_sequence(killer_id: int) -> void:
	_death_seq += 1
	var seq := _death_seq
	await get_tree().create_timer(Player.DEATH_FALL_TIME - 0.04, true, false, true).timeout
	if not _death_seq_valid(seq):
		return
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.1)
	await t.finished
	if not _death_seq_valid(seq):
		return
	if not _start_killcam(killer_id):
		_death_camera(killer_id)
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.2)


func _death_seq_valid(seq: int) -> bool:
	return seq == _death_seq and local_player != null and is_instance_valid(local_player) \
			and not local_player.alive and MatchManager.state == MatchManager.State.RUNNING


func _start_killcam(killer_id: int) -> bool:
	if not _killcam_possible(killer_id):
		return false
	var killer := MatchManager.get_participant(killer_id)
	var kill := recorder.find_kill(MatchManager.local_participant_id, killer_id)
	if not recorder.start_ghost_replay(kill, _cam, self, KILLCAM_SECONDS_BEFORE, KILLCAM_SECONDS_AFTER):
		return false
	_killcam_active = true
	players_container.visible = false
	projectiles_container.visible = false
	hud.visible = false
	_cam.fov = GameSettings.fov
	_cam_title.text = "KILLCAM"
	_fill_cam_info(kill, false)
	_cam_hint.text = ""
	_cam_ui.visible = true
	return true


func _end_killcam() -> void:
	_dead_elapsed = 0.0
	_death_seq += 1
	_fade.color.a = 0.0
	if not _killcam_active:
		return
	_killcam_active = false
	recorder.abort()
	players_container.visible = true
	projectiles_container.visible = true
	hud.visible = MatchManager.state != MatchManager.State.ENDED
	_cam_ui.visible = false
	if local_player != null and is_instance_valid(local_player):
		local_player.camera.current = true


func _update_killcam(delta: float) -> void:
	if local_player != null and is_instance_valid(local_player) and not local_player.alive and MatchManager.state == MatchManager.State.RUNNING:
		_dead_elapsed += delta
	else:
		_dead_elapsed = 0.0
	if not _killcam_active:
		return
	_cam.fov = GameSettings.fov
	var remaining := maxf(0.0, _respawn_delay_for(MatchManager.get_local_participant()) - _dead_elapsed)
	var hint := "Respawn in %d" % int(ceil(remaining))
	if _dead_elapsed >= KILLCAM_SKIP_AFTER:
		hint += "     •     Leertaste: überspringen"
	_cam_hint.text = hint


func _death_camera(killer_id: int) -> void:
	if local_player == null:
		return
	var killer := MatchManager.get_participant(killer_id)
	if killer == null or killer.node == null or killer_id == MatchManager.local_participant_id:
		return
	var target: Vector3 = (killer.node as Player).get_eye_position()
	local_player.face_towards(target)


# ----------------------------------------------------------------------------- network (called by NetworkManager)

## Client: the server spawned (or respawned) a participant.
func remote_spawn(id: int, t: Transform3D, class_id: String) -> void:
	var p := MatchManager.get_participant(id)
	if p == null:
		return
	_respawn_queue.erase(id)
	p.class_id = class_id
	var player := _ensure_player(p)
	_sync_class(p, player)
	_finish_spawn(p, player, t)


## Client: the server says this player died.
func remote_death(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	var p := MatchManager.get_participant(victim_id)
	if p == null or p.node == null or not is_instance_valid(p.node):
		return
	(p.node as Player).health.kill(killer_id, weapon_id, headshot)


## Server and clients: a participant left the match.
func remove_player_node(id: int) -> void:
	_respawn_queue.erase(id)
	var p := MatchManager.get_participant(id)
	if p and p.node and is_instance_valid(p.node):
		p.node.queue_free()
		p.node = null


## Client: a grenade thrown on the server (flies visually, explodes on command).
func spawn_visual_grenade(thrower_id: int, team: int, origin: Vector3, velocity: Vector3) -> Node:
	var grenade: Grenade = GRENADE_SCENE.instantiate()
	grenade.thrower_id = thrower_id
	grenade.thrower_team = team
	grenade.visual_only = true
	projectiles_container.add_child(grenade)
	grenade.global_position = origin
	grenade.launch(velocity)
	return grenade


func play_explosion_at(center: Vector3) -> void:
	Grenade.spawn_explosion_fx(get_tree(), center)


# ----------------------------------------------------------------------------- match end / pause

func _on_match_ended(_winner_team: int, _winner_id: int) -> void:
	_respawn_queue.clear()
	for p in MatchManager.participants.values():
		if p.node and is_instance_valid(p.node):
			(p.node as Player).set_controls_enabled(false)
	if _paused:
		pause_menu.close()
		_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	_end_killcam()
	if MatchManager.is_draw():
		AudioManager.play_2d("round_lose", -4.0)
	elif MatchManager.local_player_won():
		AudioManager.play_2d("round_win", -2.0)
	else:
		AudioManager.play_2d("round_lose", -2.0)
	if not _start_last_kill_cam():
		_show_results()


func _show_results() -> void:
	if _results_shown:
		return
	_results_shown = true
	match_end.show_results()
	if NetworkManager.is_host() and MatchManager.config.map_voting:
		NetworkManager.host_open_vote(GameDirector.ROTATION_MAPS)


## Replays the final kill of the winner from the shooter's eyes before the results appear.
func _start_last_kill_cam() -> bool:
	if not GameSettings.killcams or MatchManager.is_draw():
		return false
	var final_kill := recorder.find_final_kill(int(MatchManager.winner["team"]), int(MatchManager.winner["participant_id"]))
	if final_kill.is_empty():
		return false
	var killer := MatchManager.get_participant(int(final_kill["killer"]))
	var victim := MatchManager.get_participant(int(final_kill["victim"]))
	if not recorder.start(final_kill, _cam):
		return false
	_replay_active = true
	projectiles_container.visible = false
	_cam.fov = GameSettings.fov
	_cam_title.text = "LAST KILL"
	_fill_cam_info(final_kill, true)
	_cam_hint.text = "Leertaste: überspringen"
	_cam_ui.visible = true
	return true


func _on_replay_finished() -> void:
	if _killcam_active:
		# the killcam replay is over: back to the normal death view until the respawn
		_killcam_active = false
		players_container.visible = true
		projectiles_container.visible = true
		hud.visible = MatchManager.state != MatchManager.State.ENDED
		_cam_ui.visible = false
		if local_player != null and is_instance_valid(local_player):
			local_player.camera.current = true
		return
	_replay_active = false
	_cam_ui.visible = false
	projectiles_container.visible = true
	_start_outro()


## After the last kill: the camera leaves the scene, rises over the map and the scoreboard fades in.
func _start_outro() -> void:
	var box := _map_bounds()
	var fov := 55.0
	var fit := maxf(box.size.x / 1.7, box.size.z * 0.78 + 6.0)
	_outro_center = box.get_center()
	_outro_dist = fit * 0.5 / tan(deg_to_rad(fov * 0.5)) * 1.15
	_outro_angle = 0.0
	_outro_active = true
	var from := _cam.global_transform
	var from_fov := _cam.fov
	var to_pos := _outro_center + _outro_dir.normalized() * _outro_dist
	var to := Transform3D(Basis.looking_at(_outro_center - to_pos, Vector3.UP), to_pos)
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		_cam.global_transform = from.interpolate_with(to, k)
		_cam.fov = lerpf(from_fov, fov, k), 0.0, 1.0, OUTRO_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: _outro_orbit = true)
	get_tree().create_timer(OUTRO_RESULTS_DELAY).timeout.connect(_show_results)


func _map_bounds() -> AABB:
	var box := AABB(Vector3(-30, 0, -22), Vector3(60, 6, 44))
	var first := true
	if map != null:
		for n in map.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var a: AABB = mi.global_transform * mi.get_aabb()
			if a.size.length() > 160.0 or not mi.visible:
				continue
			box = a if first else box.merge(a)
			first = false
	return box


## Slow orbit around the map while the scoreboard is shown.
func _update_outro(delta: float) -> void:
	if not _outro_orbit:
		return
	_outro_angle += delta * 0.07
	var pos := _outro_center + (Basis(Vector3.UP, _outro_angle) * _outro_dir.normalized()) * _outro_dist
	_cam.global_transform = Transform3D(Basis.looking_at(_outro_center - pos, Vector3.UP), pos)


func _on_class_selected(class_id: String) -> void:
	NetworkManager.request_class_change(class_id)
	var name: String = GameDirector.get_class_data(class_id).display_name
	hud.hint_label.text = "Klasse „%s“ ab dem nächsten Respawn" % name
	get_tree().create_timer(5.0).timeout.connect(func() -> void: hud.hint_label.text = "")


func _on_map_chosen(map_id: String) -> void:
	var cfg := MatchManager.config.duplicate_config()
	cfg.map_id = map_id
	GameDirector.start_match(cfg)


func _on_next_round() -> void:
	if NetworkManager.is_online():
		if NetworkManager.is_host():
			NetworkManager.host_start_match(MatchManager.config)
		return
	GameDirector.start_match(MatchManager.config)


func _on_back_to_lobby() -> void:
	if NetworkManager.is_host():
		NetworkManager.host_return_to_lobby()


func _leave_to_menu() -> void:
	GameDirector.return_to_main_menu()


func _open_pause() -> void:
	_paused = true
	pause_menu.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if local_player:
		local_player.set_controls_enabled(false)


func _close_pause() -> void:
	_paused = false
	pause_menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if local_player and MatchManager.state != MatchManager.State.ENDED:
		local_player.set_controls_enabled(true)
