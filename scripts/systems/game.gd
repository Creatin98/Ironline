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
const HUMAN_RESPAWN_DELAY := 3.0
const KILLCAM_SKIP_AFTER := 1.5

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
var _killcam_target: Player
var _killcam_active: bool = false
var _dead_elapsed: float = 0.0
var _replay_active: bool = false
var _cam_ui: Control
var _cam_title: Label
var _cam_sub: Label
var _cam_hint: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
		if not _start_killcam(killer_id):
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
	_cam_title = UITheme.label("", 40, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cam_title.offset_top = 60.0
	_cam_title.offset_bottom = 110.0
	_cam_ui.add_child(_cam_title)
	_cam_sub = UITheme.label("", 24, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cam_sub.offset_top = 112.0
	_cam_sub.offset_bottom = 150.0
	_cam_ui.add_child(_cam_sub)
	_cam_hint = UITheme.label("", 20, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cam_hint.offset_top = -120.0
	_cam_hint.offset_bottom = -80.0
	_cam_ui.add_child(_cam_hint)


## Live view through the eyes of whoever killed us. Returns false if that is not possible.
func _start_killcam(killer_id: int) -> bool:
	_dead_elapsed = 0.0
	if not GameSettings.killcams or killer_id == MatchManager.local_participant_id or _replay_active:
		return false
	var killer := MatchManager.get_participant(killer_id)
	if killer == null or killer.node == null or not is_instance_valid(killer.node) or not (killer.node as Player).alive:
		return false
	_killcam_target = killer.node as Player
	_set_target_view(_killcam_target, true)
	_killcam_active = true
	_cam.current = true
	_cam_title.text = "KILLCAM"
	_cam_sub.text = killer.display_name
	_cam_sub.add_theme_color_override("font_color", Teams.color_of(killer.team))
	_cam_hint.text = ""
	_cam_ui.visible = true
	return true


func _end_killcam() -> void:
	_dead_elapsed = 0.0
	if not _killcam_active:
		return
	_killcam_active = false
	if _killcam_target != null and is_instance_valid(_killcam_target):
		_set_target_view(_killcam_target, false)
	_killcam_target = null
	_cam_ui.visible = false
	if local_player != null and is_instance_valid(local_player):
		local_player.camera.current = true


## Hides the watched player's own head/torso so the camera does not sit inside the model.
func _set_target_view(target: Player, first_person: bool) -> void:
	target.torso_mesh.visible = not first_person
	target.head_mesh.visible = not first_person
	target.name_label.visible = not first_person and not target.is_local


func _update_killcam(delta: float) -> void:
	if local_player != null and is_instance_valid(local_player) and not local_player.alive and MatchManager.state == MatchManager.State.RUNNING:
		_dead_elapsed += delta
	else:
		_dead_elapsed = 0.0
	if not _killcam_active:
		return
	if _killcam_target == null or not is_instance_valid(_killcam_target) or not _killcam_target.alive:
		_end_killcam() # the killer died as well: back to the normal death view
		return
	_cam.global_transform = _killcam_target.camera.global_transform
	_cam.fov = GameSettings.fov
	_cam_hint.text = "Leertaste: überspringen" if _dead_elapsed >= KILLCAM_SKIP_AFTER else ""


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
	_cam_sub.text = "%s  ▸  %s" % [killer.display_name, victim.display_name]
	_cam_sub.add_theme_color_override("font_color", Teams.color_of(killer.team))
	_cam_hint.text = "Leertaste: überspringen"
	_cam_ui.visible = true
	return true


func _on_replay_finished() -> void:
	_replay_active = false
	_cam_ui.visible = false
	projectiles_container.visible = true
	if local_player != null and is_instance_valid(local_player):
		local_player.camera.current = true
	_show_results()


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
