extends Node
## Headless smoke test: loads every script, scene and resource in the project,
## instantiates the core scenes, builds the test arena and runs a short
## simulated match (spawn, shot, grenade, kill, respawn). Runs as a normal
## scene so all autoloads are available.
##
##   godot --headless --path . tests/smoke_test.tscn
##
## Exit code 0 = ok, 1 = failures (details are printed).

var _failures: Array[String] = []
var _loaded := 0


func _ready() -> void:
	print("== Ironline Smoke Test ==")
	GameSettings.persist = false
	GameDirector._skip_loading_screen = true
	MatchManager.warmup_time = 0.5
	GameSettings.killcams = false # the main simulations expect the results screen right at the end
	_scan("res://")
	_instantiate_core_scenes()
	await _check_loading_screen()
	await _simulate_match()
	_check_reload_rigs()
	await _simulate_reloads()
	await _simulate_cams()
	await _simulate_steps()
	await _simulate_slide()
	await _check_maps()
	await _simulate_bots()
	AudioManager.stop_all()
	await get_tree().process_frame
	if _failures.is_empty():
		print("OK: %d Ressourcen geladen, keine Fehler." % _loaded)
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FEHLER: " + f)
		printerr("%d Fehler." % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("  FEHLER: " + msg)


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_fail("Ordner nicht lesbar: " + dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan(full)
		else:
			var ext := entry.get_extension()
			if ext in ["gd", "tscn", "tres"] and not full.begins_with("res://tests/"):
				_load(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _load(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res == null:
		_fail("Konnte nicht laden: " + path)
		return
	_loaded += 1


func _instantiate_core_scenes() -> void:
	for path in [
		"res://scenes/player/player.tscn",
		"res://scenes/weapons/grenade.tscn",
		"res://scenes/effects/explosion.tscn",
		"res://scenes/effects/bullet_impact.tscn",
		"res://scenes/effects/muzzle_flash.tscn",
		"res://scenes/weapons/models/ak47_model.tscn",
		"res://scenes/weapons/models/mp5_model.tscn",
		"res://scenes/weapons/models/shotgun_model.tscn",
		"res://scenes/weapons/models/pistol_model.tscn",
		"res://scenes/main_menu/main_menu.tscn",
	]:
		var scene: PackedScene = load(path)
		if scene == null:
			_fail("Szene fehlt: " + path)
			continue
		var inst := scene.instantiate()
		if inst == null:
			_fail("Szene nicht instanzierbar: " + path)
		else:
			inst.free()
	for path in ["res://resources/classes/class_assault.tres", "res://resources/classes/class_smg.tres", "res://resources/classes/class_shotgun.tres"]:
		var c: ClassData = load(path)
		if c == null or c.primary == null or c.secondary == null:
			_fail("Klassen-Ressource unvollstaendig: " + path)
		elif c.primary.model_scene == null:
			_fail("Waffenmodell fehlt fuer " + path)


## Real reloads in a running match: ammo is refilled, the animation ends in the rest pose.
func _simulate_reloads() -> void:
	for class_id in GameDirector.get_class_ids():
		var cfg := MatchConfig.new()
		cfg.mode_id = MatchConfig.MODE_FFA
		cfg.map_id = "test_arena"
		cfg.bots_enabled = false
		cfg.time_limit = 0.0
		cfg.local_class_id = class_id
		MatchManager.prepare_match(cfg)
		var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
		add_child(game)
		await get_tree().process_frame
		MatchManager.warmup_left = 0.05
		var waited := 0.0
		while MatchManager.state != MatchManager.State.RUNNING and waited < 6.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		var local: Player = MatchManager.get_local_participant().node as Player
		local.human_controller.deactivate()
		for slot in 2:
			if slot == 1:
				local.weapon_manager.begin_switch(1)
			for i in 70: # drawing the weapon takes a moment
				await get_tree().physics_frame
			var w := local.weapon_manager.get_current_weapon()
			var before := 2
			w.magazine = before
			if not w.start_reload():
				_fail("%s: Nachladen liess sich nicht starten" % w.data.weapon_id)
				continue
			var frames := 0
			while w.is_reloading() and frames < 900:
				await get_tree().physics_frame
				frames += 1
			if w.is_reloading() or w.magazine <= before:
				_fail("%s: Nachladen wurde nicht abgeschlossen (Magazin %d)" % [w.data.weapon_id, w.magazine])
			var model_ok := true
			for pr in [["Mag", w.model.get_node_or_null("Mag")], ["LeftHand", w.model.get_node_or_null("LeftHand")]]:
				if pr[1] != null and not (pr[1] as Node3D).visible:
					model_ok = false
			if not model_ok:
				_fail("%s: Teile des Modells sind nach dem Nachladen unsichtbar" % w.data.weapon_id)
		game.free()
		await get_tree().process_frame
	print("Nachladen im Spiel: alle Klassen und Waffen laden mit Animation nach")


## Reload animation: every weapon fires its sounds in order, moves its parts and returns to the rest pose.
func _check_reload_rigs() -> void:
	var expected := {
		"rifle": ["reload_release", "reload_mag_out", "reload_mag_in", "reload_slap", "reload_bolt"],
		"smg": ["reload_release", "reload_mag_out", "reload_mag_in", "reload_slap", "reload_bolt"],
		"pistol": ["reload_release", "reload_pistol_out", "reload_pistol_in", "reload_slide"],
		"shotgun": ["shell_insert"],
	}
	for class_id in GameDirector.get_class_ids():
		var cls := GameDirector.get_class_data(class_id)
		for wd in [cls.primary, cls.secondary]:
			var model: Node3D = (wd as WeaponData).model_scene.instantiate()
			add_child(model)
			var rig := ReloadRig.create(model, wd.reload_style)
			var moved := false
			var events: Array[String] = []
			var parts: Array = []
			for n in ["Mag", "LeftHand", "RightHand"]:
				var node := model.get_node_or_null(n) as Node3D
				if node:
					parts.append([node, node.position])
			for i in 101:
				events.append_array(rig.apply(float(i) / 100.0, 1.0))
				for pr in parts:
					if (pr[0] as Node3D).position.distance_to(pr[1]) > 0.02:
						moved = true
			if events != expected[wd.reload_style]:
				_fail("%s (%s): Reload-Sounds %s statt %s" % [wd.weapon_id, wd.reload_style, str(events), str(expected[wd.reload_style])])
			if not moved:
				_fail("%s: Reload-Animation bewegt keine Teile" % wd.weapon_id)
			rig.reset()
			for pr in parts:
				if (pr[0] as Node3D).position.distance_to(pr[1]) > 0.0005:
					_fail("%s: %s kehrt nach dem Reload nicht in die Ruhelage zurueck" % [wd.weapon_id, (pr[0] as Node).name])
			if wd.reload_style in ["rifle", "smg", "pistol"] and model.get_node_or_null("Mag") == null:
				_fail("%s: Modell hat kein Mag fuer den Magazinwechsel" % wd.weapon_id)
			model.free()
	print("Reload-Rigs: alle Waffen animieren, Sounds in Reihenfolge, Ruhelage nach dem Reload OK")


## Curbs: a 0.2 m edge is walked over without jumping, a 0.7 m wall still blocks.
func _simulate_steps() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_FFA
	cfg.map_id = "test_arena"
	cfg.bots_enabled = false
	cfg.time_limit = 0.0
	MatchManager.prepare_match(cfg)
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var waited := 0.0
	while MatchManager.state != MatchManager.State.RUNNING and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var local: Player = MatchManager.get_local_participant().node as Player
	local.human_controller.deactivate()
	for spec in [[Vector3(0.0, 0.1, -12.0), Vector3(6.0, 0.2, 2.0)], [Vector3(0.0, 0.35, -7.0), Vector3(6.0, 0.7, 1.0)]]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		body.position = spec[0]
		game.add_child(body)
	await get_tree().physics_frame
	local.global_position = Vector3(0.0, 0.1, -17.0)
	local.rotation.y = PI # looks towards +z
	local.velocity = Vector3.ZERO
	await get_tree().physics_frame
	local.input.move = Vector2(0, 1)
	var airborne := 0
	var max_y := 0.0
	for i in 130:
		await get_tree().physics_frame
		if not local.is_on_floor():
			airborne += 1
		max_y = maxf(max_y, local.global_position.y)
	local.input.move = Vector2.ZERO
	if local.global_position.z < -8.2 or max_y < 0.15:
		_fail("Die 0.2 m hohe Kante wurde nicht uebersprungen (z=%.2f, hoechste y=%.2f)" % [local.global_position.z, max_y])
	if local.global_position.z > -6.4:
		_fail("Die 0.7 m hohe Wand hat nicht blockiert (z=%.2f)" % local.global_position.z)
	if airborne > 12:
		_fail("Beim Ueberlaufen der Kante war der Spieler %d Ticks in der Luft (soll ohne Springen gehen)" % airborne)
	print("Stufen: Kante 0.2 m ohne Springen ueberlaufen (z=%.2f, y=%.2f, Luft-Ticks %d), 0.7 m Wand blockiert" % [local.global_position.z, max_y, airborne])
	game.free()
	await get_tree().process_frame


## Loading screen: shows for DURATION, then reports "finished" and removes itself.
func _check_loading_screen() -> void:
	var ls := LoadingScreen.new()
	add_child(ls)
	ls.begin("harbor")
	var done := [false]
	ls.finished.connect(func() -> void: done[0] = true)
	var t := 0.0
	while not done[0] and t < LoadingScreen.DURATION + 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if not done[0]:
		_fail("Ladebildschirm meldete nach %.1f s kein Ende" % t)
	elif t < LoadingScreen.DURATION - 0.5:
		_fail("Ladebildschirm war nach %.1f s schon fertig" % t)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(ls):
		_fail("Ladebildschirm blieb nach dem Ausblenden bestehen")
	print("Ladebildschirm: %.1f s, danach entfernt" % t)


## Knee slide: sprint + crouch glides ~1-2 m; Space ends it and stands up, a second Space jumps.
func _simulate_slide() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_FFA
	cfg.map_id = "test_arena"
	cfg.bots_enabled = false
	cfg.time_limit = 0.0
	MatchManager.prepare_match(cfg)
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var waited := 0.0
	while MatchManager.state != MatchManager.State.RUNNING and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var local: Player = MatchManager.get_local_participant().node as Player
	local.human_controller.deactivate()
	for run in 2:
		local.global_position = Vector3(0.0, 0.1, 0.0)
		local.rotation.y = PI
		local.velocity = Vector3.ZERO
		local._slide_cd = 0.0
		await get_tree().physics_frame
		local.input.move = Vector2(0, 1)
		local.input.sprint = true
		for i in 70:
			await get_tree().physics_frame
		if not local.is_sprinting:
			_fail("Slide-Test: Spieler sprintet nicht")
		var start_z := local.global_position.z
		local.input.crouch = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not local.is_sliding:
			_fail("Slide-Test: Sprint + Ducken startet keinen Slide (Tempo %.1f)" % local.horizontal_speed)
		if run == 0:
			local.input.move = Vector2.ZERO
			local.input.sprint = false
			var ticks := 0
			while local.is_sliding and ticks < 120:
				await get_tree().physics_frame
				ticks += 1
			var dist := absf(local.global_position.z - start_z)
			if dist < 2.2 or dist > 4.5:
				_fail("Slide-Test: Slidelaenge %.2f m ausserhalb von 2.2-4.5 m" % dist)
			if not local.is_crouching:
				_fail("Slide-Test: nach dem Slide mit gehaltener Duck-Taste soll der Spieler geduckt bleiben")
			# Space while crouched: stand up, no jump
			local.input.jump_pressed = true
			await get_tree().physics_frame
			await get_tree().physics_frame
			if local.is_crouching or not local.is_on_floor():
				_fail("Slide-Test: erstes Leertasten-Druecken soll aufstehen ohne zu springen")
			local.input.jump_pressed = true
			await get_tree().physics_frame
			await get_tree().physics_frame
			if local.is_on_floor():
				_fail("Slide-Test: zweites Leertasten-Druecken soll springen")
			print("Slide: %.2f m in %d Ticks, bleibt geduckt, Leertaste steht auf, zweite springt" % [dist, ticks])
		else:
			# Space during the slide ends it and stands up
			local.input.jump_pressed = true
			await get_tree().physics_frame
			await get_tree().physics_frame
			if local.is_sliding or local.is_crouching:
				_fail("Slide-Test: Leertaste im Slide soll aufstehen")
		local.input.clear_all()
		for i in 30:
			await get_tree().physics_frame
	# hit feedback: the four situations (hit, headshot, kill, headshot kill) play their sounds without errors
	for name in ["hitmarker", "hitmarker_headshot", "kill_confirm", "kill_headshot"]:
		var st := AudioManager.get_stream(name)
		if st == null or st.get_length() < 0.03:
			_fail("Sound %s fehlt oder ist leer" % name)
	for combo in [[false, false], [true, false], [false, true], [true, true]]:
		game.hud._on_hit_enemy(combo[0], combo[1])
		await get_tree().process_frame
	print("Hit-Feedback: Treffer, Kopfschuss, Kill, Kopfschuss-Kill ausgeloest")
	game.free()
	await get_tree().process_frame


## Killcam after death (live view of the killer, skippable) and the last-kill replay at the round end.
func _simulate_cams() -> void:
	GameSettings.killcams = true
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM
	cfg.map_id = "test_arena"
	cfg.bots_enabled = true
	cfg.bot_count = 1
	cfg.time_limit = 0.0
	MatchManager.prepare_match(cfg)
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	var waited := 0.0
	while MatchManager.state != MatchManager.State.RUNNING and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var me := MatchManager.get_local_participant()
	var local: Player = me.node as Player
	local.human_controller.deactivate()
	var bot: Participant = null
	for p in MatchManager.participants.values():
		if p.is_bot:
			bot = p
	var bot_node: Player = bot.node as Player
	(bot_node.get_node("BotController") as Node).set_physics_process(false)
	# let the recorder collect a few seconds
	for i in 200:
		await get_tree().physics_frame
	# --- killcam: we die, the view switches to the killer and can be skipped after 1.5 s
	local.take_damage(9999.0, bot.id, "ak47", local.get_center(), false, bot_node.global_position)
	await get_tree().process_frame
	if game._killcam_active:
		_fail("Killcam startete ohne Sturz-Animation sofort")
	if local.head.fall < 0.0 or not local.is_local:
		_fail("Sturz-Kamera fehlt")
	var fall_wait := 0.0
	while not game._killcam_active and fall_wait < 1.5:
		await get_tree().process_frame
		fall_wait += get_process_delta_time()
	if local.head.fall < 0.95:
		_fail("Kamera ist nicht zu Boden gefallen (fall=%.2f)" % local.head.fall)
	if not game._killcam_active:
		_fail("Killcam startete nicht")
	if not game._cam.current:
		_fail("Killcam-Kamera ist nicht aktiv")
	if not game.recorder.playing or not game.recorder.ghost_mode:
		_fail("Die Killcam spielt keinen Replay (Geister-Spieler) ab")
	if game._cam_name.text != bot.display_name:
		_fail("Killcam zeigt den Namen des Moerders nicht (%s statt %s)" % [game._cam_name.text, bot.display_name])
	if game.players_container.visible:
		_fail("Echte Spieler muessen waehrend der Killcam ausgeblendet sein")
	var real_players := get_tree().get_nodes_in_group("players").size()
	if real_players != MatchManager.participants.size():
		_fail("Geister duerfen nicht in der Gruppe players sein (%d statt %d)" % [real_players, MatchManager.participants.size()])
	NetworkManager.request_skip_respawn()
	await get_tree().physics_frame
	if me.alive:
		_fail("Respawn liess sich vor 0.5 s ueberspringen")
	for i in 60:
		await get_tree().physics_frame
	NetworkManager.request_skip_respawn()
	for i in 40:
		await get_tree().physics_frame
		if me.alive:
			break
	if not me.alive:
		_fail("Respawn nach dem Ueberspringen blieb aus")
	if game._killcam_active or not local.camera.current or not game.players_container.visible or game.recorder.playing:
		_fail("Killcam wurde nach dem Respawn nicht sauber beendet")
	# --- last kill cam: we kill the bot and end the match
	for i in 60:
		await get_tree().physics_frame
	bot_node.take_damage(9999.0, me.id, "ak47", bot_node.get_center(), false, local.global_position)
	await get_tree().physics_frame
	# the bot killed us once (1:1): one more kill so that our team wins
	MatchManager.report_kill(bot.id, me.id, "ak47", true)
	await get_tree().physics_frame
	MatchManager.end_match()
	await get_tree().process_frame
	if not game._replay_active or not game.recorder.playing:
		_fail("Last-Kill-Cam startete nicht")
	elif game.match_end.visible:
		_fail("Endbildschirm erschien schon waehrend des Replays")
	for i in 20:
		await get_tree().physics_frame
	if game._cam_name.text == "":
		_fail("Die Last-Kill-Cam zeigt den Namen des Schuetzen nicht")
	# slow motion: jump to just before the kill, the time scale must drop and be restored afterwards
	game.recorder._cursor = float(game.recorder.kill["t"]) - 0.2
	for i in 40:
		await get_tree().physics_frame
	if not game.recorder.is_slow_motion():
		_fail("Zeitlupe startete im Last-Kill-Replay nicht (Zeitskala %.2f)" % Engine.time_scale)
	game.recorder.skip()
	if Engine.time_scale != 1.0 or AudioServer.playback_speed_scale != 1.0:
		_fail("Zeitskala wurde nach dem Replay nicht zurueckgesetzt (%.2f)" % Engine.time_scale)
	await get_tree().process_frame
	if game._replay_active or not game._outro_active:
		_fail("Nach dem Replay startete der Abspann (Kamera ueber die Map) nicht")
	var outro_waited := 0.0
	while not game.match_end.visible and outro_waited < 4.0:
		await get_tree().process_frame
		outro_waited += get_process_delta_time()
	if not game.match_end.visible:
		_fail("Endbildschirm erschien nach dem Abspann nicht")
	print("Killcams: Killcam, Ueberspringen, Last-Kill-Replay OK")
	GameSettings.killcams = false
	game.free()
	await get_tree().process_frame


## Runs a Free-for-All with hard bots on Frontier at 4x speed and checks that the
## bots move, shoot and score.
func _simulate_bots() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_FFA
	cfg.map_id = "frontier"
	cfg.bots_enabled = true
	cfg.bot_count = 7
	cfg.bot_difficulty = MatchConfig.DIFFICULTY_HARD
	cfg.time_limit = 0.0
	MatchManager.prepare_match(cfg)
	var game_scene: PackedScene = load("res://scenes/game/game.tscn")
	var game := game_scene.instantiate()
	add_child(game)
	await get_tree().process_frame
	# lambdas capture by value, so count inside a shared dictionary
	var stats := {"shots": 0}
	var counter := func(_id: int, _pos: Vector3) -> void: stats["shots"] += 1
	GameEvents.shot_fired.connect(counter)
	# local player stays passive in a corner
	var me := MatchManager.get_local_participant()
	(me.node as Player).human_controller.deactivate()
	var start_positions: Dictionary = {}
	for p in MatchManager.participants.values():
		if p.is_bot:
			start_positions[p.id] = (p.node as Node3D).global_position
	Engine.time_scale = 4.0
	var sim_seconds := 40.0
	var elapsed := 0.0
	while elapsed < sim_seconds and MatchManager.state != MatchManager.State.ENDED:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	Engine.time_scale = 1.0
	var moved_total := 0.0
	var stuck_bots := 0
	var bot_kills := 0
	for p in MatchManager.participants.values():
		if not p.is_bot:
			continue
		bot_kills += p.kills
		var node := p.node as Node3D
		var d: float = node.global_position.distance_to(start_positions[p.id]) if node else 0.0
		moved_total += d
		if d < 3.0 and p.deaths == 0:
			stuck_bots += 1
	GameEvents.shot_fired.disconnect(counter)
	var shots: int = stats["shots"]
	if shots == 0:
		_fail("Bots haben nicht geschossen")
	if stuck_bots > 1:
		_fail("%d Bots haben sich nicht bewegt" % stuck_bots)
	if bot_kills == 0:
		_fail("Bots haben in %d s keinen Kill erzielt" % int(sim_seconds))
	print("Bot-Simulation (%d s, Frontier, FFA, schwer): %d Schuesse, %d Bot-Kills, Bewegung gesamt %.0f m, %d stehende Bots" % [int(sim_seconds), shots, bot_kills, moved_total, stuck_bots])
	game.free()
	await get_tree().process_frame


## Builds every registered map: spawn points, navigation mesh, lane points on the mesh.
func _check_maps() -> void:
	for map_id in GameDirector.get_map_ids():
		var info := GameDirector.get_map_info(map_id)
		var scene: PackedScene = load(info["scene"])
		if scene == null:
			_fail("Map-Szene fehlt: " + str(info["scene"]))
			continue
		var map: BlockMap = scene.instantiate()
		add_child(map)
		var nav_ok: bool = await map.wait_navigation_ready(120)
		if not nav_ok:
			_fail("%s: Navigation wurde nicht synchronisiert" % map_id)
		var spawns := 0
		var red := 0
		var blue := 0
		for sp in get_tree().get_nodes_in_group("spawn_points"):
			spawns += 1
			if sp.team == Teams.Team.RED:
				red += 1
			elif sp.team == Teams.Team.BLUE:
				blue += 1
		if red < 6 or blue < 6:
			_fail("%s: zu wenige Team-Spawns (Rot %d, Blau %d)" % [map_id, red, blue])
		# the kill zone must end well below every spawn point
		var kill_zone := map.get_node("KillZone") as Area3D
		var kill_top: float = kill_zone.global_position.y + 2.0
		for sp in get_tree().get_nodes_in_group("spawn_points"):
			if sp.global_position.y - 0.5 < kill_top:
				_fail("%s: Kill-Zone (Oberkante %.1f) reicht bis an Spawnpunkt %s" % [map_id, kill_top, sp.global_position])
				break
		var polys := map.nav_region.navigation_mesh.get_polygon_count() if map.nav_region.navigation_mesh else 0
		if polys == 0:
			_fail("%s: Navigation-Mesh ist leer" % map_id)
		var nav_map := map.get_world_3d().navigation_map
		var off_mesh := 0
		var lane_count := 0
		for p in map.get_all_lane_points():
			lane_count += 1
			var closest := NavigationServer3D.map_get_closest_point(nav_map, p + Vector3(0, 0.5, 0))
			if closest.distance_to(p + Vector3(0, 0.5, 0)) > 1.2:
				off_mesh += 1
				_fail("%s: Lane-Punkt %s liegt nicht auf dem Nav-Mesh (naechster %s)" % [map_id, p, closest])
		for sp in get_tree().get_nodes_in_group("spawn_points"):
			var sp_pos: Vector3 = sp.global_position
			var closest2 := NavigationServer3D.map_get_closest_point(nav_map, sp_pos + Vector3(0, 0.5, 0))
			if closest2.distance_to(sp_pos + Vector3(0, 0.5, 0)) > 1.2:
				_fail("%s: Spawnpunkt %s liegt nicht auf dem Nav-Mesh" % [map_id, sp_pos])
		# path check: first to last point of the mid lane must be connected
		var lanes := map.get_lanes()
		if lanes.has("mid") and lanes["mid"].size() >= 2:
			var a: Vector3 = lanes["mid"][0]
			var z: Vector3 = lanes["mid"][lanes["mid"].size() - 1]
			var path := NavigationServer3D.map_get_path(nav_map, a + Vector3(0, 0.5, 0), z + Vector3(0, 0.5, 0), true)
			if path.size() < 2 or path[path.size() - 1].distance_to(z) > 2.0:
				_fail("%s: Kein Nav-Pfad von Nord nach Sued ueber die Mitte" % map_id)
		print("%s: %d Spawns, %d Nav-Polygone, %d Lane-Punkte (%d daneben), %d Geometrieobjekte" % [map_id, spawns, polys, lane_count, off_mesh, map.geometry_root.get_child_count()])
		map.free()
		await get_tree().physics_frame


## Runs the real game scene for a few seconds and performs scripted actions.
func _simulate_match() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM
	cfg.map_id = "test_arena"
	cfg.bots_enabled = true
	cfg.bot_count = 5
	cfg.time_limit = 60.0
	MatchManager.prepare_match(cfg)
	var game_scene: PackedScene = load("res://scenes/game/game.tscn")
	if game_scene == null:
		_fail("game.tscn fehlt")
		return
	var game := game_scene.instantiate()
	add_child(game)
	await get_tree().process_frame
	var spawns := get_tree().get_nodes_in_group("spawn_points").size()
	if spawns < 12:
		_fail("Testarena hat zu wenige Spawnpunkte: %d" % spawns)
	var geometry: Node = (game.map as BlockMap).geometry_root
	print("Testarena: %d Spawnpunkte, %d Geometrieobjekte" % [spawns, geometry.get_child_count() if geometry else -1])
	if MatchManager.participants.size() != 6:
		_fail("Roster erwartet 6 Teilnehmer, hat %d" % MatchManager.participants.size())
	# wait for warmup to end (3 s) -> RUNNING
	var waited := 0.0
	while MatchManager.state != MatchManager.State.RUNNING and waited < 6.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if MatchManager.state != MatchManager.State.RUNNING:
		_fail("Match wurde nicht gestartet (state=%d)" % MatchManager.state)
		game.queue_free()
		return
	var me := MatchManager.get_local_participant()
	var local: Player = me.node as Player
	if local == null or not local.alive:
		_fail("Lokaler Spieler nicht gespawnt")
		game.queue_free()
		return
	var alive_count := 0
	for p in MatchManager.participants.values():
		if p.alive and p.node != null:
			alive_count += 1
	if alive_count != 6:
		_fail("Nicht alle Teilnehmer gespawnt: %d/6" % alive_count)
	# headless there is no captured mouse, so the HumanController would wipe
	# injected input every tick; drive the input state directly instead
	local.human_controller.deactivate()
	# --- movement: teleport to the open street first (a random spawn may face a wall)
	local.global_position = Vector3(0.0, 0.1, -17.0)
	local.rotation.y = PI
	await get_tree().physics_frame
	var start_pos := local.global_position
	local.input.move = Vector2(0, 1)
	for i in 30:
		await get_tree().physics_frame
	local.input.move = Vector2.ZERO
	if local.global_position.distance_to(start_pos) < 0.5:
		_fail("Spieler hat sich nicht bewegt")
	# --- weapon: fire one shot, check ammo
	var w := local.weapon_manager.get_current_weapon()
	if w == null:
		_fail("Keine Waffe")
	else:
		var mag_before := w.magazine
		local.input.fire_held = true
		local.input.fire_pressed = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		local.input.fire_held = false
		if w.magazine >= mag_before:
			_fail("Schuss hat keine Munition verbraucht (%d -> %d)" % [mag_before, w.magazine])
		# reload
		local.input.reload_pressed = true
		await get_tree().physics_frame
		if not w.is_reloading():
			_fail("Nachladen wurde nicht gestartet")
		# switch weapon
		local.input.select_secondary = true
		await get_tree().physics_frame
		for i in 40:
			await get_tree().physics_frame
		if local.weapon_manager.current_index != 1:
			_fail("Waffenwechsel fehlgeschlagen")
	# --- grenade (count explosions via the event bus, the effect node is short-lived)
	var explosion_stats := {"count": 0}
	var explosion_counter := func(_pos: Vector3, _radius: float) -> void: explosion_stats["count"] += 1
	GameEvents.explosion_at.connect(explosion_counter)
	var grenades_before := local.weapon_manager.grenades
	local.input.grenade_pressed = true
	await get_tree().physics_frame
	for i in 30:
		await get_tree().physics_frame
	if local.weapon_manager.grenades != grenades_before - 1:
		_fail("Granate wurde nicht geworfen")
	var grenade_nodes := 0
	for n in get_tree().get_nodes_in_group("players"):
		pass
	for child in game.get_node("Projectiles").get_children():
		if child is Grenade:
			grenade_nodes += 1
	if grenade_nodes != 1:
		_fail("Granate nicht in der Szene (%d)" % grenade_nodes)
	# --- damage & kill: shoot a bot directly through take_damage, expect kill + score
	var bot: Participant = null
	for p in MatchManager.participants.values():
		if p.is_bot and me.is_enemy_of(p):
			bot = p
			break
	if bot == null:
		_fail("Kein gegnerischer Bot")
	else:
		var bot_node: Player = bot.node as Player
		var max_hp := bot_node.health.max_health
		var killed := bot_node.take_damage(max_hp * 0.6, me.id, "ak47", bot_node.get_center(), false, local.global_position)
		if killed:
			_fail("60 %% Schaden darf nicht toeten")
		killed = bot_node.take_damage(max_hp * 0.6, me.id, "ak47", bot_node.get_center(), true, local.global_position)
		if not killed:
			_fail("120 %% Schaden muss toeten")
		await get_tree().process_frame
		if me.kills != 1 or bot.deaths != 1:
			_fail("Kill nicht gewertet (kills=%d deaths=%d)" % [me.kills, bot.deaths])
		if me.score != 100:
			_fail("Ein Kill muss 100 Punkte geben (auch per Kopfschuss), ist %d" % me.score)
		# assist: we hurt a second enemy, a teammate bot finishes it -> 1 assist = 50 points for us
		var other_enemy: Participant = null
		var helper: Participant = null
		for p2 in MatchManager.participants.values():
			if p2.is_bot and me.is_enemy_of(p2) and p2 != bot and other_enemy == null:
				other_enemy = p2
			elif p2.is_bot and not me.is_enemy_of(p2) and helper == null:
				helper = p2
		if other_enemy and helper:
			var victim_node := other_enemy.node as Player
			victim_node.take_damage(60.0, me.id, "ak47", victim_node.get_center(), false, local.global_position)
			victim_node.take_damage(5000.0, helper.id, "mp5", victim_node.get_center(), false, local.global_position)
			await get_tree().process_frame
			if me.assists != 1 or me.score != 150:
				_fail("Assist falsch gewertet (assists=%d, punkte=%d, erwartet 1 / 150)" % [me.assists, me.score])
			if helper.kills != 1 or helper.score != 100:
				_fail("Der Killer des Assists bekam nicht 100 Punkte (%d)" % helper.score)
			if other_enemy.deaths != 1:
				_fail("Tod des Assist-Opfers nicht gewertet")
		else:
			_fail("Kein zweiter Gegner/Helfer fuer den Assist-Test")
		if MatchManager.team_scores[me.team] != 2: # our kill + the teammate's kill from the assist test
			_fail("Teampunkte nicht erhoeht")
		# friendly fire must be blocked
		var mate: Participant = null
		for p in MatchManager.participants.values():
			if p.is_bot and not me.is_enemy_of(p):
				mate = p
				break
		if mate:
			var hp_before: float = (mate.node as Player).health.health
			(mate.node as Player).take_damage(50.0, me.id, "ak47", Vector3.ZERO, false, Vector3.ZERO)
			if (mate.node as Player).health.health != hp_before:
				_fail("Friendly Fire wurde nicht blockiert")
		# wait for respawn (1.5 s)
		for i in 240:
			await get_tree().physics_frame
			if bot.alive:
				break
		if not bot.alive:
			_fail("Bot ist nicht respawnt")
		# the body must stay visible after the respawn even once the old death
		# animation (4 s) would have hidden it
		for i in 150:
			await get_tree().physics_frame
		if bot.alive and not (bot.node as Player).body.visible:
			_fail("Koerper eines respawnten Spielers ist unsichtbar")
	# --- grenade should have exploded by now (fuse 2.4 s)
	await get_tree().create_timer(1.0).timeout
	GameEvents.explosion_at.disconnect(explosion_counter)
	if int(explosion_stats["count"]) < 1:
		_fail("Explosion wurde nicht erzeugt")
	# --- end match via kill limit
	for i in 60:
		MatchManager.report_kill(bot.id, me.id, "ak47", false)
		if MatchManager.state == MatchManager.State.ENDED:
			break
	if MatchManager.state != MatchManager.State.ENDED:
		_fail("Killlimit hat das Match nicht beendet")
	if not MatchManager.local_player_won():
		_fail("Lokaler Spieler sollte gewonnen haben")
	await get_tree().process_frame
	if not game.match_end.visible:
		_fail("Endbildschirm nicht sichtbar")
	print("Match-Simulation: Bewegung, Schuss, Nachladen, Wechsel, Granate, Kill, Respawn, Matchende OK")
	game.free()
	await get_tree().process_frame
