extends Node3D
## Match scene root: loads the map, builds the roster, spawns/respawns
## participants and wires the HUD, scoreboard, pause and end screens.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BotControllerScript := preload("res://scripts/bots/bot_controller.gd")

@onready var map_container: Node3D = $MapContainer
@onready var players_container: Node3D = $Players
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


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_load_map()
	spawn_system = SpawnSystem.new(get_tree())
	_create_roster()
	GameEvents.match_state_changed.connect(_on_match_state_changed)
	GameEvents.match_ended.connect(_on_match_ended)
	match_end.next_round_requested.connect(_on_next_round)
	match_end.leave_requested.connect(_leave_to_menu)
	pause_menu.resumed.connect(_close_pause)
	pause_menu.leave_requested.connect(_leave_to_menu)
	AudioManager.play_2d("round_start", -2.0)
	MatchManager.begin_warmup()
	# everyone spawns during the warmup countdown with controls locked
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
	var local_id := multiplayer.get_unique_id()
	MatchManager.local_participant_id = local_id
	MatchManager.add_human(local_id, GameSettings.player_name, cfg.local_team, cfg.local_class_id)
	if cfg.bots_enabled and MatchManager.is_authority():
		var count := clampi(cfg.bot_count, 0, cfg.max_participants() - 1)
		var names := GameDirector.random_bot_names(count)
		var class_ids := GameDirector.get_class_ids()
		for i in count:
			var class_id: String = class_ids[randi() % class_ids.size()]
			MatchManager.add_bot(names[i], cfg.bot_difficulty, class_id, Teams.Team.NONE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and MatchManager.state != MatchManager.State.ENDED:
		if _paused:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
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
			if not p.alive:
				_spawn_participant(p)
			elif p.node:
				(p.node as Player).set_controls_enabled(not _paused or not (p.node as Player).is_local)


func _spawn_participant(p: Participant) -> void:
	var player: Player = p.node as Player
	if player == null or not is_instance_valid(player):
		player = PLAYER_SCENE.instantiate()
		players_container.add_child(player)
		var local := p.id == MatchManager.local_participant_id
		player.setup(p, GameDirector.get_class_data(p.class_id), local)
		if p.is_bot:
			var bc: BotController = BotControllerScript.new()
			bc.name = "BotController"
			player.add_child(bc)
			bc.setup(player, p)
		player.died.connect(_on_player_died)
		if local:
			local_player = player
			player.add_to_group("local_player")
	var t := spawn_system.pick_spawn(p, MatchManager.mode.uses_teams)
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


func _on_player_died(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	MatchManager.report_kill(victim_id, killer_id, weapon_id, headshot)
	if MatchManager.state == MatchManager.State.RUNNING:
		_respawn_queue[victim_id] = MatchManager.mode.respawn_delay
	if victim_id == MatchManager.local_participant_id:
		GameEvents.local_player_died.emit(killer_id, MatchManager.mode.respawn_delay)
		_death_camera(killer_id)


func _death_camera(killer_id: int) -> void:
	if local_player == null:
		return
	var killer := MatchManager.get_participant(killer_id)
	if killer == null or killer.node == null or killer_id == MatchManager.local_participant_id:
		return
	var target: Vector3 = (killer.node as Player).get_eye_position()
	local_player.face_towards(target)


# ----------------------------------------------------------------------------- match end / pause

func _on_match_ended(_winner_team: int, _winner_id: int) -> void:
	_respawn_queue.clear()
	for p in MatchManager.participants.values():
		if p.node:
			(p.node as Player).set_controls_enabled(false)
	if _paused:
		pause_menu.close()
		_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	if MatchManager.is_draw():
		AudioManager.play_2d("round_lose", -4.0)
	elif MatchManager.local_player_won():
		AudioManager.play_2d("round_win", -2.0)
	else:
		AudioManager.play_2d("round_lose", -2.0)
	match_end.show_results()


func _on_next_round() -> void:
	GameDirector.start_match(MatchManager.config)


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
