extends Node
## Developer tool: renders a scene/state to a PNG (needs a display, e.g. xvfb, and
## a renderer; the headless dummy renderer cannot draw).
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##       --resolution 1920x1080 tools/shots/shot.tscn -- --target=menu_settings --out=/tmp/out.png
##
## Targets: menu, menu_settings, menu_online, menu_quick, menu_classes,
##   fp_<class>_<hip|ads>   first-person view in the test arena (class: assault, smg, shotgun)
##   game_pause | game_scoreboard | game_end | game_killcam | game_lastkill   in-game UI states (test arena, a few bots)
##   map_<id>      overview render of a map (preview image for menus)
##   class_<id>    weapon render of a class (preview image for menus)
##   Optional: --nohud=1 hides the HUD.

var target: String = "menu"
var out_path: String = "/tmp/shot.png"
var wait_frames: int = 12


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--target="):
			target = arg.substr(9)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg.begins_with("--frames="):
			wait_frames = int(arg.substr(9))
	await _run()


func _run() -> void:
	var node: Node = null
	if target.begins_with("menu"):
		var menu: Control = (load("res://scenes/main_menu/main_menu.tscn") as PackedScene).instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		match target:
			"menu_settings":
				menu._show_settings()
			"menu_online":
				menu._show_lobby()
			"menu_lobby":
				NetworkManager.host(7799)
				NetworkManager.set_local_loadout(Teams.Team.RED, "shotgun")
				menu._show_lobby()
			"menu_quick":
				menu._show_quick_play()
			"menu_classes":
				menu._show_classes()
		node = menu
	elif target.begins_with("fp_"):
		await _first_person_view()
	elif target.begins_with("game_"):
		await _game_ui(target.substr(5))
	elif target.begins_with("map_"):
		await _map_preview(target.substr(4))
	elif target.begins_with("class_"):
		await _class_preview(target.substr(6))
	for i in wait_frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("SHOT ", out_path, " ", img.get_size())
	get_tree().quit()


func _first_person_view() -> void:
	var parts := target.split("_")
	var class_id := parts[1]
	var ads := parts[2] == "ads"
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_FFA
	cfg.map_id = "test_arena"
	cfg.bots_enabled = false
	cfg.time_limit = 0.0
	cfg.local_class_id = class_id
	MatchManager.prepare_match(cfg)
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchManager.warmup_left = 0.05
	for i in 30:
		await get_tree().physics_frame
	var player: Player = MatchManager.get_local_participant().node
	player.human_controller.deactivate()
	player.global_position = Vector3(0.0, 0.1, -17.0)
	player.rotation.y = PI
	if "--nohud=1" in OS.get_cmdline_user_args():
		game.hud.visible = false
	if parts.size() > 3 and parts[3] == "sec":
		player.input.select_secondary = true
		for i in 60:
			await get_tree().physics_frame
	if ads:
		player.input.aim = true
	for i in 60:
		await get_tree().physics_frame


# ----------------------------------------------------------------------------- previews

func _map_preview(map_id: String) -> void:
	var info := GameDirector.get_map_info(map_id)
	var map: Node3D = (load(info["scene"]) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(map)
	for i in 4:
		await get_tree().process_frame
	var box := AABB()
	var first := true
	for n in map.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var a: AABB = mi.global_transform * mi.get_aabb()
		if a.size.length() > 160.0 or not mi.visible:
			continue
		box = a if first else box.merge(a)
		first = false
	var c := box.get_center()
	var radius := maxf(box.size.x, box.size.z)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.far = 800.0
	get_tree().root.add_child(cam)
	var dir := Vector3(0.0, 0.78, 0.62).normalized()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			var p := arg.substr(6).split(",")
			dir = Vector3(float(p[0]), float(p[1]), float(p[2])).normalized()
	# preview only: calmer exposure so sunlit roofs do not burn out
	for we in map.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = (we as WorldEnvironment).environment
		if e:
			e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			e.tonemap_exposure = 0.55
	for dl in map.find_children("*", "DirectionalLight3D", true, false):
		(dl as DirectionalLight3D).light_energy *= 0.75
	var fit := maxf(box.size.x / 1.7, box.size.z * 0.78 + 6.0)
	var dist := fit * 0.5 / tan(deg_to_rad(cam.fov * 0.5)) * 1.12
	cam.global_position = c + dir * dist
	cam.look_at(c, Vector3.UP)
	cam.current = true
	print("MAP ", map_id, " aabb ", box, " dist ", dist)


func _class_preview(class_id: String) -> void:
	var data := GameDirector.get_class_data(class_id)
	var root := Node3D.new()
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	key.light_energy = 1.6
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.75, 0.45)
	root.add_child(rim)
	var primary: Node3D = data.primary.model_scene.instantiate()
	root.add_child(primary)
	_hide_hands(primary)
	primary.position = Vector3(0.0, 0.05, 0.13)
	var secondary: Node3D = data.secondary.model_scene.instantiate()
	root.add_child(secondary)
	_hide_hands(secondary)
	secondary.scale = Vector3.ONE * 1.3
	secondary.position = Vector3(0.0, -0.22, 0.0)
	var cam := Camera3D.new()
	cam.fov = 12.5
	root.add_child(cam)
	cam.position = Vector3(4.2, 0.0, 0.0)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	cam.current = true
	if data.secondary.weapon_id == "pistol":
		secondary.position = Vector3(0.0, -0.20, 0.28)


func _hide_hands(model: Node3D) -> void:
	for n in model.get_children():
		if n.name.begins_with("Left") or n.name.begins_with("Right"):
			(n as Node3D).visible = false


func _game_ui(state: String) -> void:
	wait_frames = 1 # software rendering is slow: game time runs on between frames
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM
	cfg.map_id = "test_arena"
	cfg.bots_enabled = true
	cfg.bot_count = 5
	cfg.time_limit = 0.0
	MatchManager.prepare_match(cfg)
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchManager.warmup_left = 0.05
	for i in 90:
		await get_tree().physics_frame
	var me := MatchManager.get_local_participant()
	(me.node as Player).human_controller.deactivate()
	var bot: Participant = null
	for p in MatchManager.participants.values():
		if p.is_bot and me.is_enemy_of(p):
			bot = p
			break
	var bot_node: Player = bot.node as Player
	(bot_node.get_node("BotController") as Node).set_physics_process(false)
	for other in MatchManager.participants.values():
		if other.is_bot and other != bot:
			(other.node as Player).global_position = Vector3(25.0, 0.1, 15.0)
			((other.node as Player).get_node("BotController") as Node).set_physics_process(false)
	var local := me.node as Player
	local.global_position = Vector3(0.0, 0.1, -17.0)
	local.rotation.y = PI
	bot_node.global_position = Vector3(0.0, 0.1, -11.0)
	bot_node.rotation.y = 0.0 # faces the local player
	match state:
		"killcam":
			for i in 30:
				await get_tree().physics_frame
			local.take_damage(9999.0, bot.id, "ak47", local.get_center(), false, bot_node.global_position)
			for i in 20:
				await get_tree().physics_frame
			var rec: ReplayRecorder = game.recorder
			rec._cursor = float(rec.kill["t"]) - 0.3 # shortly before the fatal shot
			rec._prev_cursor = rec._cursor
			rec._apply(rec._cursor, false)
			get_tree().paused = true # software rendering is slow: freeze the moment
		"lastkill":
			bot_node.health.max_health = 100000.0 # survives the shots until the explicit kill
			bot_node.health.health = 100000.0
			local.input.fire_held = true
			for i in 150:
				await get_tree().physics_frame
			bot_node.health.health = 10.0
			bot_node.take_damage(9999.0, me.id, "ak47", bot_node.get_center(), true, local.global_position)
			for i in 5:
				await get_tree().physics_frame
			local.input.fire_held = false
			MatchManager.end_match()
			get_tree().paused = true
			# jump the replay to just after the kill and pose everything once
			var rec: ReplayRecorder = game.recorder
			rec._cursor = float(rec.kill["t"]) + 0.35
			rec._last_index = rec._index_at(rec._cursor - 0.05)
			rec._apply(rec._cursor, false)
			for i in 4:
				await get_tree().process_frame
	if state.begins_with("hit"):
		# hit feedback close-up: hit | headshot | kill | headkill
		var head := state in ["hithead", "hitheadkill"]
		var kill := state in ["hitkill", "hitheadkill"]
		game.hud.show_hitmarker(head, kill)
		game.hud._hitmarker_time = game.hud._hitmarker_total * 0.7
		if kill:
			me.killstreak = 3
			game.hud._on_scored(125 if head else 100, "Kopfschuss" if head else "Kill")
			game.hud._kill_flash.color.a = 0.0
		get_tree().paused = true
		game.hud.crosshair.queue_redraw()
	if state == "popups":
		me.killstreak = 3
		me.kills = 7
		me.assists = 2
		me.score = 850
		game.hud._on_scored(100, "Kopfschuss")
		game.hud._on_scored(50, "Assist")
		for lbl in game.hud.popup_box.get_children():
			lbl.modulate.a = 1.0
			lbl.scale = Vector2.ONE
			lbl.get_tree().paused = false
		get_tree().paused = true
	match state:
		"hud":
			get_tree().paused = true
		"hudedit":
			GameSettings.hud_offsets = {"health": Vector2(60, -40), "ammo": Vector2(-90, 0)}
			game._open_pause()
			game.pause_menu.close()
			game.hud.begin_edit()
			get_tree().paused = true
		"pause":
			game._open_pause()
		"scoreboard":
			game.scoreboard.visible = true
			game.scoreboard.rebuild()
		"end":
			me.kills = 7
			me.deaths = 2
			me.assists = 3
			me.score = 850
			MatchManager.end_match()
	for i in 20:
		await get_tree().process_frame
