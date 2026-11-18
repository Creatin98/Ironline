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
var flash_overlay: FlashOverlay
var scope_overlay: ScopeOverlay
var _cam: Camera3D # shared by killcam and last-kill replay
var _killcam_active: bool = false
var _dead_elapsed: float = 0.0
var _fade: ColorRect
var _gray: ColorRect
var _cam_cross: Control
var _cam_hit_left: float = 0.0 # hitmarker of the killer's view in killcam / last kill
var _cam_hit_total: float = 0.14
var _cam_hit_head: bool = false
var _cam_hit_kill: bool = false
# last kill cam: cinema bars (21:9) in HUD style with title and name plate
var _bars: Control
var _bar_top: PanelContainer
var _bar_bottom: PanelContainer
var _bars_anim: float = 0.0
var _plate_panel: PanelContainer
var _plate_stripe: ColorRect
var _plate_name: Label
var _plate_detail: Label
var _plate_assist: Label
var _plate_hint: Label
var _bar_title: Label
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
	if not GameDirector.is_loading():
		AudioManager.stop_music() # with a loading screen the music runs on and fades out there
	ui_layer.layer = 2
	_build_gray_layer()
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
	recorder.killer_hit.connect(_on_replay_hit)
	GameEvents.participant_killed.connect(recorder.note_kill)
	GameEvents.participant_killed.connect(_on_participant_killed_skull)
	_build_cam_overlay()
	scope_overlay = ScopeOverlay.new()
	scope_overlay.name = "ScopeOverlay"
	scope_overlay.recorder = recorder
	add_child(scope_overlay)
	flash_overlay = FlashOverlay.new()
	flash_overlay.name = "FlashOverlay"
	add_child(flash_overlay)
	AudioManager.play_2d("round_start", -2.0)

	if GameDirector.is_loading():
		await GameDirector.loading_finished
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
	hud.minimap.build_from(map)
	GameSettings.apply_scene(map)
	GameSettings.settings_changed.connect(_on_settings_changed)
	var ambience := AmbienceSystem.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(MatchManager.config.map_id)


## A teammate fell: a discreet skull floats above the body for 3 s (through walls, only for his team).
func _on_participant_killed_skull(victim_id: int, _killer_id: int, _weapon: String, _headshot: bool) -> void:
	if MatchManager.mode == null or not MatchManager.mode.uses_teams or victim_id == MatchManager.local_participant_id:
		return
	var me := MatchManager.get_local_participant()
	var v := MatchManager.get_participant(victim_id)
	if me == null or v == null or v.team != me.team or v.node == null or not is_instance_valid(v.node):
		return
	var fx := get_tree().get_first_node_in_group("effects_container")
	DeathSkull.spawn(fx if fx != null else self, (v.node as Node3D).global_position + Vector3(0.0, 1.7, 0.0))


func _on_settings_changed() -> void:
	GameSettings.apply_scene(map)


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
		var class_ids := GameDirector.get_class_ids().filter(func(id: String) -> bool: return id != "sniper") # bots do not scope
		for i in count:
			var class_id: String = class_ids[randi() % class_ids.size()]
			MatchManager.add_bot(names[i], cfg.bot_difficulty, class_id, Teams.Team.NONE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and hud.is_editing():
		hud.end_edit() # Esc leaves the HUD editor and returns to the pause menu
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump") and not _paused:
		# the last kill cam, the outro and the results cannot be skipped: nobody misses the end of the round
		if _replay_active or _outro_active:
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


## Black-and-white picture during the start countdown; the colour returns until 0.5 s before the start.
func _build_gray_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_gray = ColorRect.new()
	_gray.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float gray : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(l), gray), 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_gray.material = mat
	_gray.visible = false
	layer.add_child(_gray)


func _update_gray() -> void:
	var g := 0.0
	if MatchManager.state == MatchManager.State.WARMUP:
		g = clampf((MatchManager.warmup_left - 0.5) / maxf(0.1, MatchManager.warmup_time - 0.5), 0.0, 1.0)
	_gray.visible = g > 0.005
	if _gray.visible:
		(_gray.material as ShaderMaterial).set_shader_parameter("gray", g)


func _process(delta: float) -> void:
	_update_gray()
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
	_drop_primary_weapon(victim_id)
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


# ----------------------------------------------------------------------------- weapons on the floor

const MAX_PICKUPS := 10
var _pickups: Dictionary = {} # id -> WeaponPickup
var _next_pickup_id: int = 1
var _pickup_root: Node3D


## Server: a dead player leaves the primary weapon (with what is left in it) on the floor.
func _drop_primary_weapon(victim_id: int) -> void:
	if not MatchManager.is_authority() or MatchManager.state != MatchManager.State.RUNNING:
		return
	var p := MatchManager.get_participant(victim_id)
	if p == null or p.node == null or not is_instance_valid(p.node):
		return
	var pl := p.node as Player
	if pl.weapon_manager.weapons.is_empty():
		return
	_drop_weapon_at(pl, pl.weapon_manager.weapons[0], pl.global_position, pl.rotation.y)


func _drop_weapon_at(pl: Player, w: Weapon, pos: Vector3, yaw: float) -> void:
	if w.magazine + w.reserve <= 0:
		return
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -3.0, 0), 1)
	var r := space.intersect_ray(q)
	var ground := pos
	if not r.is_empty():
		ground = r["position"]
	var id := _next_pickup_id
	_next_pickup_id += 1
	spawn_pickup(id, w.data.weapon_id, w.magazine, w.reserve, ground, yaw)
	NetworkManager.broadcast_pickup_spawn(id, w.data.weapon_id, w.magazine, w.reserve, ground, yaw)


## Everybody: a weapon appears on the floor.
func spawn_pickup(id: int, weapon_id: String, mag: int, res: int, pos: Vector3, yaw: float) -> void:
	if _pickups.has(id):
		return
	if _pickup_root == null:
		_pickup_root = Node3D.new()
		_pickup_root.name = "Pickups"
		add_child(_pickup_root)
	while _pickups.size() >= MAX_PICKUPS:
		var oldest_id: int = _pickups.keys()[0]
		var old: WeaponPickup = _pickups[oldest_id]
		_pickups.erase(oldest_id)
		if is_instance_valid(old):
			old.queue_free()
	var pk := WeaponPickup.create(id, weapon_id, mag, res, pos, yaw)
	_pickup_root.add_child(pk)
	pk.tree_exited.connect(func() -> void: _pickups.erase(id))
	_pickups[id] = pk


## Server: `pl` presses the use key: the nearest weapon within reach is swapped for the current primary weapon.
func try_pickup(pl: Player) -> void:
	var best: WeaponPickup = null
	var best_d := WeaponPickup.PICKUP_RANGE
	for pk in _pickups.values():
		var wp := pk as WeaponPickup
		if wp == null or not is_instance_valid(wp) or wp.age < 0.5:
			continue
		var d := wp.global_position.distance_to(pl.global_position)
		if d < best_d:
			best_d = d
			best = wp
	if best == null or pl.weapon_manager.weapons.is_empty():
		return
	var old: Weapon = pl.weapon_manager.weapons[0]
	var old_id := old.data.weapon_id
	var old_mag := old.magazine
	var old_res := old.reserve
	NetworkManager.broadcast_pickup_take(best.pickup_id, pl.participant_id, best.weapon_id, best.magazine, best.reserve)
	var pos := pl.global_position
	var yaw := pl.rotation.y
	apply_pickup_take(best.pickup_id, pl.participant_id, best.weapon_id, best.magazine, best.reserve)
	# the weapon that was carried stays behind (a little in front of the player, so it is not picked up again at once)
	if old_mag + old_res > 0:
		var fwd := -Vector3(sin(yaw), 0.0, cos(yaw))
		var id := _next_pickup_id
		_next_pickup_id += 1
		var drop_pos := pos + fwd * 0.7
		var space := pl.get_world_3d().direct_space_state
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(drop_pos + Vector3(0, 0.6, 0), drop_pos + Vector3(0, -3.0, 0), 1))
		if not r.is_empty():
			drop_pos = r["position"]
		spawn_pickup(id, old_id, old_mag, old_res, drop_pos, yaw)
		NetworkManager.broadcast_pickup_spawn(id, old_id, old_mag, old_res, drop_pos, yaw)


## Everybody: pickup `id` was taken, the participant now carries `weapon_id` as primary weapon.
func apply_pickup_take(id: int, participant_id: int, weapon_id: String, mag: int, res: int) -> void:
	var pk: WeaponPickup = _pickups.get(id)
	_pickups.erase(id)
	if pk != null and is_instance_valid(pk):
		AudioManager.play_3d("weapon_switch", pk.global_position, -4.0, 0.05, 30.0)
		pk.queue_free()
	var p := MatchManager.get_participant(participant_id)
	if p != null and p.node != null and is_instance_valid(p.node):
		(p.node as Player).swap_primary(weapon_id, mag, res)


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
uniform float strength = 1.0;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.9);
	float d = length(p);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.16, 0.62, d) * strength);
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
	_cam_cross = Control.new()
	_cam_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cam_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_cross.draw.connect(_draw_cam_cross)
	_cam_ui.add_child(_cam_cross)
	_build_bars()
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	ui_layer.add_child(_fade)
	_fade.move_to_front()


## Cinema bars of the last kill cam: translucent panels in HUD style. Top: "LETZTER ABSCHUSS",
## bottom: name plate of the shooter (team colour stripe), weapon and victim.
func _build_bars() -> void:
	_bars = Control.new()
	_bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.visible = false
	_cam_ui.add_child(_bars)
	var bar_bg := Color(0.05, 0.06, 0.08, 0.74)
	_bar_top = PanelContainer.new()
	_bar_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_style := UITheme.panel_style(bar_bg, 0)
	top_style.border_width_bottom = 3
	top_style.border_color = UITheme.ACCENT
	_bar_top.add_theme_stylebox_override("panel", top_style)
	_bars.add_child(_bar_top)
	var title_row := UITheme.hbox(26)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for side in 3:
		if side == 1:
			_bar_title = UITheme.label("LETZTER ABSCHUSS", 56, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
			title_row.add_child(_bar_title)
		else:
			var rule := ColorRect.new()
			rule.color = Color(0.97, 0.63, 0.16, 0.7)
			rule.custom_minimum_size = Vector2(160, 3)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			title_row.add_child(rule)
	_bar_top.add_child(title_row)
	_bar_bottom = PanelContainer.new()
	_bar_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom_style := UITheme.panel_style(bar_bg, 0)
	bottom_style.border_width_top = 3
	bottom_style.border_color = UITheme.ACCENT
	_bar_bottom.add_theme_stylebox_override("panel", bottom_style)
	_bars.add_child(_bar_bottom)
	var center := CenterContainer.new()
	_bar_bottom.add_child(center)
	_plate_panel = PanelContainer.new()
	_plate_panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.07, 0.08, 0.1, 0.94), 5, Color(1, 1, 1, 0.18), 2))
	center.add_child(_plate_panel)
	var row := UITheme.hbox(16)
	_plate_panel.add_child(row)
	_plate_stripe = ColorRect.new()
	_plate_stripe.custom_minimum_size = Vector2(8, 0)
	row.add_child(_plate_stripe)
	var col := UITheme.vbox(2)
	col.custom_minimum_size = Vector2(420, 0)
	row.add_child(col)
	_plate_name = UITheme.label("", 38, UITheme.TEXT)
	col.add_child(_plate_name)
	_plate_detail = UITheme.label("", 20, UITheme.TEXT_DIM)
	col.add_child(_plate_detail)
	_plate_assist = UITheme.label("", 17, Color(0.5, 0.78, 1.0))
	col.add_child(_plate_assist)
	_plate_hint = UITheme.label("", 17, UITheme.TEXT_DIM)
	col.add_child(_plate_hint)


## Last kill cam vs. killcam: which labels are shown.
func _set_cam_mode(last_kill: bool) -> void:
	# both cams use the cinema bars with the plate of the shooter; only the title differs
	_bars.visible = true
	for l in [_cam_title, _cam_name, _cam_detail, _cam_assist, _cam_hint]:
		l.visible = false
	_bar_title.text = "LETZTER ABSCHUSS" if last_kill else "KILLCAM"
	_plate_hint.text = ""
	_bars_anim = 0.0


func _fill_plate(kill: Dictionary) -> void:
	var killer := MatchManager.get_participant(int(kill["killer"]))
	var victim := MatchManager.get_participant(int(kill["victim"]))
	var col := Teams.color_of(killer.team) if killer else UITheme.TEXT
	_plate_stripe.color = col
	_plate_name.text = killer.display_name if killer else "?"
	_plate_name.add_theme_color_override("font_color", col)
	var detail := String(HUD.WEAPON_LABELS.get(String(kill["weapon"]), String(kill["weapon"])))
	if bool(kill["headshot"]):
		detail += "   •   KOPFSCHUSS"
	if victim != null:
		detail += "   ▸   %s" % victim.display_name
	_plate_detail.text = detail
	_plate_detail.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if bool(kill["headshot"]) else UITheme.TEXT_DIM)
	var names: Array[String] = []
	for aid in kill.get("assists", []):
		var a := MatchManager.get_participant(int(aid))
		if a != null:
			names.append(a.display_name)
	_plate_assist.text = ("Assist: %s" % ", ".join(names)) if not names.is_empty() else ""
	_plate_panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.07, 0.08, 0.1, 0.94), 5, col.darkened(0.2), 2))


## Bars slide in (in real time, also during the slow motion) and always frame a 21:9 picture.
func _update_bars(delta: float) -> void:
	if not _bars.visible:
		return
	_bars_anim = move_toward(_bars_anim, 1.0, delta / maxf(Engine.time_scale, 0.05) * 2.2)
	var vp := _cam_ui.size
	var wide := vp.x / (21.0 / 9.0)
	var bar_h := maxf(150.0, (vp.y - wide) * 0.5)
	var k := _bars_anim * _bars_anim * (3.0 - 2.0 * _bars_anim)
	_bar_top.custom_minimum_size = Vector2(0, bar_h)
	_bar_bottom.custom_minimum_size = Vector2(0, bar_h)
	_bar_top.offset_bottom = bar_h * k
	_bar_top.offset_top = -bar_h * (1.0 - k)
	_bar_bottom.offset_top = -bar_h * k
	_bar_bottom.offset_bottom = bar_h * (1.0 - k)


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
	_set_cam_mode(false)
	_fill_plate(kill)
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


## Crosshair of the killer's view in the killcam / last kill (a dot only while aiming down the sights).
func _draw_cam_cross() -> void:
	if not recorder.playing:
		return
	var c := _cam_cross.size * 0.5
	if _cam_hit_left > 0.0 and GameSettings.show_hit_markers:
		HitFeedback.draw_marker(_cam_cross, c, _cam_hit_left, _cam_hit_total, _cam_hit_head, _cam_hit_kill)
	var aim := recorder.killer_aim
	var a := 1.0 - clampf((aim - 0.5) * 2.0, 0.0, 1.0)
	var col := Color(1, 1, 1, 0.9)
	_cam_cross.draw_circle(c, 1.6, col)
	if a > 0.01:
		var line_col := Color(1, 1, 1, 0.9 * a)
		var shadow := Color(0, 0, 0, 0.6 * a)
		for off in [Vector2.ZERO, Vector2(1, 1)]:
			var lc := shadow if off != Vector2.ZERO else line_col
			for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_cam_cross.draw_line(c + off + d * 6.0, c + off + d * 15.0, lc, 2.0)


## The killer hit an enemy in the replay: the same hitmarker and sounds as in the game.
func _on_replay_hit(headshot: bool, killed: bool) -> void:
	_cam_hit_head = headshot
	_cam_hit_kill = killed
	_cam_hit_total = HitFeedback.duration(headshot, killed)
	_cam_hit_left = _cam_hit_total
	var killer := MatchManager.get_participant(int(recorder.kill.get("killer", 0)))
	HitFeedback.play_sounds(headshot, killed, maxi(1, killer.killstreak) if killer != null else 1)


func _update_killcam(delta: float) -> void:
	_update_bars(delta)
	if _cam_hit_left > 0.0:
		_cam_hit_left = maxf(0.0, _cam_hit_left - delta / maxf(Engine.time_scale, 0.05)) # real time, also in slow motion
	if local_player != null and is_instance_valid(local_player) and not local_player.alive and MatchManager.state == MatchManager.State.RUNNING:
		_dead_elapsed += delta
	else:
		_dead_elapsed = 0.0
	if _replay_active and recorder.playing:
		# no zoom towards the victim: the killer's weapon must look exactly as in the game
		_cam.fov = lerpf(GameSettings.fov, recorder.killer_ads_fov(), recorder.killer_aim)
		_cam_cross.queue_redraw()
	if not _killcam_active:
		return
	_cam.fov = lerpf(GameSettings.fov, recorder.killer_ads_fov(), recorder.killer_aim)
	_cam_cross.queue_redraw()
	var remaining := maxf(0.0, _respawn_delay_for(MatchManager.get_local_participant()) - _dead_elapsed)
	var hint := "Respawn in %d" % int(ceil(remaining))
	if _dead_elapsed >= KILLCAM_SKIP_AFTER:
		hint += "     •     Leertaste: überspringen"
	_cam_hint.text = hint
	_plate_hint.text = hint


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
func spawn_visual_grenade(thrower_id: int, team: int, origin: Vector3, velocity: Vector3, kind: int = 0) -> Node:
	var grenade: Grenade = GRENADE_SCENE.instantiate()
	grenade.kind = kind
	grenade.thrower_id = thrower_id
	grenade.thrower_team = team
	grenade.visual_only = true
	projectiles_container.add_child(grenade)
	grenade.global_position = origin
	grenade.launch(velocity)
	return grenade


func play_explosion_at(center: Vector3, kind: int = 0) -> void:
	if kind == Grenade.KIND_FLASH:
		Grenade.spawn_flash_fx(get_tree(), center, 0)
	else:
		Grenade.spawn_explosion_fx(get_tree(), center)


# ----------------------------------------------------------------------------- match end / pause

func _on_match_ended(_winner_team: int, _winner_id: int) -> void:
	_respawn_queue.clear()
	for p in MatchManager.participants.values():
		if p.node and is_instance_valid(p.node):
			(p.node as Player).set_controls_enabled(false)
			(p.node as Player).run_out = true # glide to a stop instead of freezing
	if _paused:
		pause_menu.close()
		_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_end_killcam()
	if MatchManager.is_draw():
		AudioManager.play_2d("round_lose", -4.0)
	elif MatchManager.local_player_won():
		AudioManager.play_2d("round_win", -2.0)
	else:
		AudioManager.play_2d("round_lose", -2.0)
	# the game runs on for a moment: players slow down and stand, the last victim falls; the HUD fades out
	var tw := create_tween()
	tw.tween_property(hud, "modulate:a", 0.0, minf(0.8, MatchManager.runout_time))
	await get_tree().create_timer(MatchManager.runout_time, true, false, true).timeout
	hud.visible = false
	hud.modulate.a = 1.0
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
	if not recorder.start(final_kill, _cam, 3.5, 2.4):
		return false
	_replay_active = true
	projectiles_container.visible = false
	_cam.fov = GameSettings.fov
	_set_cam_mode(true)
	_fill_plate(final_kill)
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
