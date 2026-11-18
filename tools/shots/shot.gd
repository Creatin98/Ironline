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
##   bolt_<class>_<percent>   bolt cycle pose (sniper) at that progress
##   rl_<class>_<percent>[_sec]   reload pose at that progress (first person, hip), e.g. rl_assault_40
##   map_<id>      overview render of a map (preview image for menus)
##   class_<id>    weapon render of a class (preview image for menus)
##   Optional: --nohud=1 hides the HUD.

var target: String = "menu"
var out_path: String = "/tmp/shot.png"
var wait_frames: int = 12


func _ready() -> void:
	GameDirector._skip_loading_screen = true
	MatchManager.warmup_time = 0.5
	MatchManager.runout_time = 0.15
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fov="):
			GameSettings.fov = float(arg.substr(6))
		elif arg.begins_with("--target="):
			target = arg.substr(9)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg.begins_with("--frames="):
			wait_frames = int(arg.substr(9))
	await _run()


func _run() -> void:
	var node: Node = null
	if target == "loading":
		var ls := LoadingScreen.new()
		get_tree().root.add_child.call_deferred(ls)
		await get_tree().process_frame
		ls.begin("harbor")
		ls._t = 3.6
		await get_tree().process_frame
		await get_tree().process_frame
		ls.set_process(false)
	elif target.begins_with("menu"):
		var menu: Control = (load("res://scenes/main_menu/main_menu.tscn") as PackedScene).instantiate()
		get_tree().root.add_child.call_deferred(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		match target:
			"menu_settings", "menu_settings_sound", "menu_settings_game":
				menu._show_settings()
				if target.ends_with("sound"):
					menu._settings._select_tab(1)
					await get_tree().process_frame
					await get_tree().process_frame
					menu._settings._scroll.scroll_vertical = 100000 # bottom of the page: the ambience group
				elif target.ends_with("game"):
					menu._settings._select_tab(2)
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
	elif target.begins_with("rlm_"):
		await _reload_model_view()
	elif target.begins_with("rl_"):
		await _reload_view()
	elif target.begins_with("bolt_"):
		await _reload_view(true)
	elif target.begins_with("fp_"):
		await _first_person_view()
	elif target.begins_with("game_"):
		await _game_ui(target.substr(5))
	elif target.begins_with("map_"):
		await _map_preview(target.substr(4))
	elif target.begins_with("glass"):
		await _glass_view()
	elif target.begins_with("rig"):
		await _rig_view()
	elif target.begins_with("view_"):
		await _map_view(target.substr(5))
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


## Eye-level view of a map: --pos=x,y,z --look=x,y,z (map as in the game, ground-level camera).
func _map_view(map_id: String) -> void:
	var info := GameDirector.get_map_info(map_id)
	var map: Node3D = (load(info["scene"]) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(map)
	for i in 4:
		await get_tree().process_frame
	var pos := Vector3(0, 1.7, 0)
	var look := Vector3(0, 1.5, -10)
	var fov := 78.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pos="):
			var p := arg.substr(6).split(",")
			pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
		elif arg.begins_with("--look="):
			var l := arg.substr(7).split(",")
			look = Vector3(float(l[0]), float(l[1]), float(l[2]))
		elif arg.begins_with("--fov="):
			fov = float(arg.substr(6))
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 500.0
	get_tree().root.add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.current = true
	for i in 3:
		await get_tree().process_frame
	print("RENDER draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		" objects ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		" primitives ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))


## Window glass: --stage=0 intact, 1 one hit, 2 three hits, 3 broken (--map=<id>, --win=<index>).
func _glass_view() -> void:
	var stage := 0
	var map_id := "frontier"
	var win_index := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			stage = int(arg.substr(8))
		elif arg.begins_with("--map="):
			map_id = arg.substr(6)
		elif arg.begins_with("--win="):
			win_index = int(arg.substr(6))
	var info := GameDirector.get_map_info(map_id)
	var map: Node3D = (load(info["scene"]) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(map)
	for i in 4:
		await get_tree().process_frame
	var field := GlassField.find(get_tree())
	print("GLASS windows ", field.windows.size())
	for ww in field.windows:
		print("  win ", ww.id, " pos ", ww.position, " size ", ww.pane_size)
	var w: GlassWindow = field.windows[win_index]
	var normal := w.global_transform.basis.z
	var eye := w.global_position + normal * 2.6
	var cam := Camera3D.new()
	cam.fov = 60.0
	get_tree().root.add_child(cam)
	cam.global_position = eye
	cam.look_at(w.global_position, Vector3.UP)
	cam.current = true
	var space := w.get_world_3d().direct_space_state
	var offsets := [Vector2(0.15, 0.1), Vector2(-0.3, -0.15), Vector2(0.35, -0.2), Vector2(-0.1, 0.25), Vector2(0.0, 0.0)]
	var hit_counts: Array[int] = [0, 1, 2, 40, 0]
	var hits: int = hit_counts[stage]
	if stage == 4: # debug: one strong impact in the middle of the pane
		w.apply_hit(w.global_position, -normal, 0.9, true)
	for i in hits:
		var o: Vector2 = offsets[i % offsets.size()]
		var target_point := w.to_global(Vector3(o.x * w.pane_size.x, o.y * w.pane_size.y, 0))
		field.shot(space, eye, target_point, 27.0)
		await get_tree().process_frame
		if w.broken:
			break
	print("GLASS broken ", w.broken, " hits ", w.hits.size(), " health ", snappedf(w.health, 0.1))
	if stage == 3:
		for i in 2:
			await get_tree().process_frame
		print("GLASS shard groups ", GlassShards._active.size())
		if GlassShards._active.size() > 0:
			var sh: GlassShards = GlassShards._active[0]
			print("GLASS shard0 ", sh._pos[0], " window ", w.global_position, " count ", sh._pos.size())


## Close-up of the third-person soldier (front, side and back) with outline.
func _rig_view() -> void:
	var root := Node3D.new()
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.42, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	sun.light_energy = 1.5
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	root.add_child(ground)
	for i in 3:
		var rig := HumanoidRig.new()
		rig.setup_look(11 + i * 5)
		rig.position = Vector3(-1.3 + 1.3 * i, 0, 0)
		rig.rotation_degrees.y = [0.0, 70.0, 180.0][i]
		root.add_child(rig)
		if i == 0:
			rig.set_outline_color(Color(1, 0.2, 0.15))
			rig.set_outline_visible(true)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.position = Vector3(0, 1.1, 4.6)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	cam.current = true
	for i in 3:
		await get_tree().process_frame


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
	if state == "warmup":
		# start countdown: picture still mostly grey
		MatchManager.warmup_time = 8.0
		MatchManager.warmup_left = 5.5
		for i in 5:
			await get_tree().physics_frame
		MatchManager.warmup_left = 5.5
		get_tree().paused = true
		await get_tree().process_frame
		return
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
			for other in MatchManager.participants.values():
				if other.is_bot and other != bot and me.is_enemy_of(other):
					local.take_damage(60.0, other.id, "mp5", local.get_center(), false, bot_node.global_position) # an assist
					break
			local.take_damage(9999.0, bot.id, "ak47", local.get_center(), true, bot_node.global_position)
			for i in 20:
				await get_tree().physics_frame
			var rec: ReplayRecorder = game.recorder
			rec._cursor = float(rec.kill["t"]) - 0.3 # shortly before the fatal shot
			rec._prev_cursor = rec._cursor
			rec._apply(rec._cursor, false)
			if "--reload=1" in OS.get_cmdline_user_args():
				var kn: Player = rec._targets[rec._killer_id]
				kn.weapon_manager.begin_tp_reload(true, 1)
				kn.weapon_manager._tp_reload_progress = float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--reload=1") + 0] != "") * 0.4
				var rig: ReloadRig = kn.weapon_manager._tp_rigs[kn.weapon_manager.current_index]
				rig.apply(0.4, 1.0)
			if "--aim=1" in OS.get_cmdline_user_args():
				rec._killer_aim_target = 1.0
				rec.killer_aim = 1.0
				(rec._targets[rec._killer_id] as Player).replay_aim(1.0, game._cam.global_transform)
				game._cam.fov = lerpf(GameSettings.fov, rec.killer_ads_fov(), 1.0)
				game._cam_cross.queue_redraw()
			if "--gore=1" in OS.get_cmdline_user_args():
				rec._cursor = float(rec.kill["t"]) + 0.02
				rec._apply(rec._cursor, false)
				for i in 50:
					await get_tree().physics_frame # the replayed body falls apart
			get_tree().paused = true # software rendering is slow: freeze the moment
		"outro":
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
			game.recorder.skip()
			get_tree().paused = true
			game._outro_orbit = true
			game._update_outro(0.0)
			game._results_shown = true # keep the scoreboard out of this frame
			for i in 3:
				await get_tree().process_frame
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
			var lk_wait := 0.0
			while not game._replay_active and lk_wait < 4.0: # the match runs on briefly before the replay starts
				await get_tree().process_frame
				lk_wait += get_process_delta_time()
			get_tree().paused = true
			# jump the replay to just after the kill and pose everything once
			var rec: ReplayRecorder = game.recorder
			rec._cursor = float(rec.kill["t"]) + 0.35
			rec._prev_cursor = rec._cursor - 0.05
			rec._apply(rec._cursor, false)
			game._bars_anim = 1.0
			game._update_bars(0.0)
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
	if state == "sprintcross":
		local.is_sprinting = true
		await get_tree().create_timer(0.1).timeout
		local.is_sprinting = true
		get_tree().paused = true
		game.hud.crosshair.queue_redraw()
		await get_tree().process_frame
	if state.begins_with("grenade"):
		var gt := float(int(state.substr(7))) / 100.0
		var wm: WeaponManager = local.weapon_manager
		wm._grenade_timer = WeaponManager.GRENADE_TOTAL_TIME * 5.0 # keeps the weapon lowered while we pose the view
		wm._grenade_thrown = false
		for i in 25:
			await get_tree().physics_frame
		wm._grenade_timer = 0.0001
		wm.grenade_holding = int(state.substr(7)) == 58
		game.hud.crosshair.queue_redraw()
		get_tree().paused = true
		if "--flash=1" in OS.get_cmdline_user_args():
			wm._grenade_view.set_kind(Grenade.KIND_FLASH)
		wm._grenade_view.apply(gt)
		wm._grenade_view.visible = true
		await get_tree().process_frame
	if state.begins_with("flashfx"):
		# flashed: flashfx<percent of the whole effect>, e.g. flashfx5 (white-out), flashfx40, flashfx70
		var ov: FlashOverlay = game.flash_overlay
		ov.trigger(1.0, Vector2(0.55, 0.42))
		var total := ov.blind_time + ov.fade_time * 1.3
		ov.elapsed = total * float(int(state.substr(7))) / 100.0
		get_tree().paused = true
		ov.update_visuals()
		await get_tree().process_frame
	if state == "sunflare":
		# looking towards the sun (the lens flare is drawn at full strength)
		var sp := me.node as Player
		sp.human_controller.deactivate()
		sp.rotation.y = -2.45 + 0.35
		sp.head.set_pitch(0.58)
		for i in 10:
			await get_tree().physics_frame
		for n in game.get_children():
			for c in n.get_children():
				if c is LensFlare:
					(c as LensFlare)._vis = 1.0
					(c as LensFlare).set_process(false)
					(c as LensFlare).visible = true
					(c as LensFlare).queue_redraw()
		get_tree().paused = true
		await get_tree().process_frame
	if state == "medals":
		var mh: MedalHud = game.hud.medal_hud
		mh.medal("headshot", "Headshot!", "One Shot One Kill")
		await get_tree().process_frame
		mh.medal("multi", "Double Kill", "", 2)
		mh.score(150, "Kopfschuss")
		mh.score(100, "Kill")
		for i in 4:
			await get_tree().process_frame
		for c in mh.get_children():
			if c is MedalWidget:
				c.age = 0.7
				c._process(0.0)
		for c in mh.get_children():
			if c is MedalWidget:
				c.age = 0.7
		mh._process(0.5)
		for c in mh.get_children():
			if c is MedalWidget:
				c.position = c.position # keep
		get_tree().paused = true
		await get_tree().process_frame
	if state == "mag":
		GameEvents.local_ammo_picked.emit(30)
		await get_tree().process_frame
		for c in game.hud.get_children():
			if c is MagPickupFx:
				c._t = 0.3
				c.set_process(false)
				c.modulate.a = 1.0
				c.scale = Vector2.ONE * 1.7
				c.queue_redraw()
		get_tree().paused = true
		await get_tree().process_frame
	if state == "pickup":
		# weapons lying on the floor (outline), one still falling
		var lp2 := me.node as Player
		lp2.human_controller.deactivate()
		var base := lp2.global_position + Vector3(0.0, 0.0, 4.0)
		game.spawn_pickup(901, "ak47", 12, 60, base + Vector3(-0.6, 0, 0), 0.4)
		game.spawn_pickup(902, "mp5", 20, 60, base + Vector3(0.9, 0, 0.5), -0.8)
		for i in 60:
			await get_tree().physics_frame
		get_tree().paused = true
		await get_tree().process_frame
	if state == "flashanim" or state == "flashbang":
		# flashanim: the first-person arm in front of the eyes and a flashed bot; flashbang: the detonation seen from a few metres
		var lp := me.node as Player
		lp.human_controller.deactivate()
		if state == "flashanim":
			for pp in MatchManager.participants.values():
				if pp.is_bot:
					var bn := pp.node as Player
					bn.set_process(false)
					(bn.get_node("BotController") as Node).set_physics_process(false)
					bn.global_position = lp.global_position + Vector3(2.2, 0.0, 7.0)
					bn.flash_react(1.0)
			lp.flash_react(1.0)
			for i in 40:
				await get_tree().physics_frame
			game.flash_overlay.clear() # watching only: no whiteout in the picture
		else:
			Grenade.spawn_flash_fx(get_tree(), lp.global_position + Vector3(0.5, 1.2, 9.0), 0)
			Engine.time_scale = 0.6 # software rendering is slow: the effect has to stay young
			for i in 3:
				await get_tree().process_frame
			Engine.time_scale = 1.0
			game.flash_overlay.clear() # watching only: no whiteout in the picture
		get_tree().paused = true
		await get_tree().process_frame
	if state == "gore":
		# three kills: grenade, sniper (limb), shotgun
		var gb: Array = []
		for pp in MatchManager.participants.values():
			if pp.is_bot:
				gb.append(pp.node as Player)
		for bn in gb:
			bn.set_process(false)
			(bn.get_node("BotController") as Node).set_physics_process(false)
		var gx := [-0.4, 1.6, 3.2]
		for i in mini(gb.size(), 3):
			gb[i].global_position = Vector3(gx[i] * 0.7, 0.1, -4.5)
			gb[i].rotation.y = 0.35
		local.global_position = Vector3(0.7, 0.1, -1.6)
		local.rotation.y = 0.0
		local.head.set_pitch(-0.3)
		for i in 30:
			await get_tree().physics_frame
		MatchManager.warmup_left = 0.0
		var ctr: Vector3 = gb[0].global_position + Vector3(0.3, 0.3, 0.8)
		gb[0].take_damage(9999.0, me.id, "grenade", gb[0].get_center(), false, ctr)
		if gb.size() > 1:
			gb[1].take_damage(9999.0, me.id, "sniper", gb[1].global_position + Vector3(0.3, 1.3, 0), false, local.global_position)
		if gb.size() > 2:
			gb[2].take_damage(9999.0, me.id, "shotgun", gb[2].global_position + Vector3(-0.3, 0.4, 0), false, local.global_position)
		for i in int(float(OS.get_environment("GORE_FRAMES")) if OS.get_environment("GORE_FRAMES") != "" else 80):
			await get_tree().physics_frame
		get_tree().paused = true
		await get_tree().process_frame
	if state == "ragdoll":
		# ragdoll of a shotgun headshot, a figure winding up a grenade throw, one flinching from a headshot, one aiming
		var bs: Array = []
		for pp in MatchManager.participants.values():
			if pp.is_bot:
				bs.append(pp.node as Player)
		for bn in bs:
			bn.set_process(false)
			(bn.get_node("BotController") as Node).set_physics_process(false)
		var xs := [-0.2, 1.7, 3.0, 0.9]
		for i in mini(bs.size(), 4):
			bs[i].global_position = Vector3(xs[i], 0.1, -14.2 + (i % 2) * 1.2)
			bs[i].rotation.y = 0.35
		for i in 30:
			await get_tree().physics_frame
		MatchManager.warmup_left = 0.0
		bs[0].take_damage(9999.0, me.id, "shotgun", bs[0].get_center(), true, local.global_position)
		for i in 60:
			await get_tree().physics_frame
		get_tree().paused = true
		if bs.size() > 1:
			bs[1].rig.throw_progress = 0.58
			for i in 30:
				bs[1].rig.animate(0.05, Vector3.ZERO, true, false, false, false, 0.0, Vector3.INF, Vector3.INF)
		if bs.size() > 2:
			bs[2].rig.hit_react(Vector3(0, 0, -1), true, 1.2)
			bs[2].rig.animate(0.016, Vector3.ZERO, true, false, false, false, 0.0, bs[2]._hand_target(true), bs[2]._hand_target(false))
		await get_tree().process_frame
	if state == "humanoids":
		# five figures in a row: stand, run, crouch, slide, jump (poses driven directly)
		var rows := [
			{"v": Vector3.ZERO, "ground": true, "crouch": false, "slide": false, "sprint": false},
			{"v": Vector3(0, 0, -7.0), "ground": true, "crouch": false, "slide": false, "sprint": true},
			{"v": Vector3.ZERO, "ground": true, "crouch": true, "slide": false, "sprint": false},
			{"v": Vector3(0, 0, -8.0), "ground": true, "crouch": true, "slide": true, "sprint": false},
			{"v": Vector3(0, 2, -5.0), "ground": false, "crouch": false, "slide": false, "sprint": false},
		]
		var k := 0
		for pp in MatchManager.participants.values():
			if not pp.is_bot or k >= rows.size():
				continue
			var bn := pp.node as Player
			bn.set_process(false)
			bn.set_physics_process(false)
			(bn.get_node("BotController") as Node).set_physics_process(false)
			bn.global_position = Vector3(-4.2 + k * 2.1, 0.1, -13.5)
			bn.rotation.y = 0.5
			var r: Dictionary = rows[k]
			for step in 40:
				bn.rig.animate(0.05, r["v"], r["ground"], r["crouch"], r["slide"], r["sprint"], 0.0, bn._hand_target(true), bn._hand_target(false))
			bn.hands.position = bn.rig.weapon_anchor()
			k += 1
		await get_tree().create_timer(0.3).timeout
		get_tree().paused = true
	if state.begins_with("blood"):
		# blood<health percent>: three hits, then the health value (e.g. blood100, blood20, blood8)
		var fx: DamageFx = game.hud.damage_fx
		for i in 60:
			await get_tree().physics_frame # the match has started (spawn resets the effect)
		get_tree().paused = true # software rendering is slow: freeze the moment
		for amount in [60.0, 45.0, 80.0]:
			fx._on_damaged(amount, Vector3.ZERO)
		fx._health_ratio = float(int(state.substr(5))) / 100.0
		for i in 8:
			fx._process(0.4)
		fx.hit = 0.5
		for sp in fx.splats:
			sp["age"] = 0.8
		fx._process(0.001)
		fx.canvas.queue_redraw()
		await get_tree().process_frame
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
		"endfinal", "endvote", "endwin", "endwin2":
			# end screen sequence: endfinal = big cards in the middle, endvote = one card voted, endwin / endwin2 = closing animation
			me.kills = 7
			me.deaths = 2
			me.assists = 3
			me.score = 850
			MatchManager.end_match()
			for i in 12:
				await get_tree().process_frame
			var screen: MatchEndScreen = game.match_end
			if not screen.visible:
				game._show_results()
				await get_tree().process_frame
			screen._vote_time_left = 5.0
			screen._vote_duration = 15.0
			screen._enter_final(true)
			screen._update_final(5.0)
			if state != "endfinal":
				screen._vote_for("frontier")
				screen._last_tally = {"frontier": 2, "harbor": 1}
				screen._refresh_vote_ui()
			if state in ["endwin", "endwin2"]:
				NetworkManager.vote_outcome_time = 2.8
				screen._start_outcome("frontier")
				screen._intro_tween.kill()
				screen._reveal_winner()
				var win_card: VoteCard = screen._cards["frontier"]
				var tgt: float = 0.55 if state == "endwin" else 1.0
				# freeze the moment: the winner in the middle (endwin) or halfway expanded (endwin2)
				for id in screen._cards:
					if id != "frontier":
						screen._cards[id].modulate.a = 0.0
				var grow := minf(1.4, screen.size.y * 0.6 / win_card.size.y)
				var big: Vector2 = win_card.size * grow
				win_card.size = big
				win_card.position = (screen.size - big) * 0.5 + Vector2(0.0, screen.size.y * 0.02)
				if state == "endwin2":
					win_card.position = win_card.position.lerp(Vector2.ZERO, 0.6)
					win_card.size = win_card.size.lerp(screen.size, 0.6)
					win_card.expand = 0.6
				screen._flash.color.a = 0.0
			screen._dim.color.a = 0.84
			screen.set_process(false)
			get_tree().paused = true
	for i in 20:
		await get_tree().process_frame


func _reload_view(bolt: bool = false) -> void:
	var parts := target.split("_")
	var class_id := parts[1]
	var progress := float(parts[2]) / 100.0
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
	game.hud.visible = false
	var wm := player.weapon_manager
	if parts.size() > 3 and parts[3] == "sec":
		wm.begin_switch(1)
		for i in 60:
			await get_tree().physics_frame
	var w := wm.get_current_weapon()
	if bolt:
		# bolt cycle after a shot (bolt_<class>_<percent>)
		w._set_state(Weapon.State.PUMPING, w.data.pump_time)
		await get_tree().physics_frame
		get_tree().paused = true
		w._bolt_sound_idx = 99
		w._update_bolt(progress)
		wm.holder.position = w.data.hip_position + w.anim_offset
		wm.holder.rotation = w.anim_rotation
		for i in 3:
			await get_tree().process_frame
		return
	w.magazine = 2
	w.start_reload()
	await get_tree().physics_frame
	get_tree().paused = true
	w._state_timer = (1.0 - progress) * w._state_duration
	w._reload_total = 0.4
	if "mid" in parts and w.rig != null: # a shell in the middle of a chain (hand comes from and goes to the belt)
		w.rig.shell_first = false
		w.rig.shell_last = false
	w._update_reload(0.0)
	wm.holder.position = w.data.hip_position + w.anim_offset
	wm.holder.rotation = w.anim_rotation
	for i in 3:
		await get_tree().process_frame


## The weapon model alone from its left side at a reload progress (checks mag/hand motion, no view tilt).
func _reload_model_view() -> void:
	var parts := target.split("_")
	var data := GameDirector.get_class_data(parts[1])
	var weapon_data: WeaponData = data.secondary if parts.size() > 3 and parts[3] == "sec" else data.primary
	var root := Node3D.new()
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, -50.0, 0.0)
	root.add_child(key)
	var model: Node3D = weapon_data.model_scene.instantiate()
	root.add_child(model)
	var rig := ReloadRig.create(model, weapon_data.reload_style)
	rig.apply(float(parts[2]) / 100.0, 1.0)
	var cam := Camera3D.new()
	cam.fov = 15.0
	root.add_child(cam)
	var zoom := "--zoom=1" in OS.get_cmdline_user_args()
	if zoom:
		cam.fov = 7.0
		cam.position = Vector3(-3.3, -0.08, 0.05)
		cam.look_at(Vector3(0.0, -0.08, 0.05), Vector3.UP)
	else:
		cam.position = Vector3(-3.3, -0.10, -0.12)
		cam.look_at(Vector3(0.0, -0.10, -0.12), Vector3.UP)
	cam.current = true
