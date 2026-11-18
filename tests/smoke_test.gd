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
	MatchManager.runout_time = 0.15 # real value (1.7 s) is checked in the last-kill-cam test
	GameSettings.killcams = false # the main simulations expect the results screen right at the end
	_scan("res://")
	_instantiate_core_scenes()
	await _check_loading_screen()
	await _check_end_screen_sequence()
	_check_death_skull()
	_check_first_person_arms()
	await _check_settings_and_audio()
	await _simulate_match()
	_check_reload_rigs()
	await _simulate_reloads()
	_check_spread_values()
	await _check_shotgun_interrupt()
	await _check_flashbang()
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


## MP5/AK: noticeable spread from the hip, only a little through the sights (and a light bloom when spraying).
func _check_spread_values() -> void:
	for pair in [["assault", 3.5, 4.6], ["smg", 2.8, 3.8]]:
		var wd: WeaponData = GameDirector.get_class_data(String(pair[0])).primary
		var w := Weapon.new()
		w.data = wd
		var hip := w.get_spread_degrees(false, 0.0, false, false)
		var ads := w.get_spread_degrees(true, 0.0, false, false)
		w.spread_bonus = wd.spread_max_bonus
		var ads_spray := w.get_spread_degrees(true, 0.0, false, false)
		var hip_spray := w.get_spread_degrees(false, 0.0, false, false)
		w.free()
		if hip < float(pair[1]) or hip > float(pair[2]):
			_fail("%s: Huefte-Streuung %.2f ausserhalb %.1f-%.1f" % [wd.weapon_id, hip, float(pair[1]), float(pair[2])])
		if ads < 0.45 or ads > 0.8:
			_fail("%s: Streuung im Visier %.2f (kein Laser, aber nur leicht: 0.45-0.8)" % [wd.weapon_id, ads])
		if ads_spray <= ads or ads_spray > 1.6:
			_fail("%s: Streuungs-Bloom im Visier unpassend (%.2f -> %.2f)" % [wd.weapon_id, ads, ads_spray])
		if hip_spray <= hip:
			_fail("%s: Dauerfeuer vergroessert die Huefte-Streuung nicht" % wd.weapon_id)
	print("Streuung MP5/AK: Huefte etwas ungenauer, im Visier leichte Streuung")


## Shotgun: a shot while loading shells interrupts the reload (shells already in the tube count),
## the weapon blends back into the aim and the queued shot is fired.
func _check_shotgun_interrupt() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_FFA
	cfg.map_id = "test_arena"
	cfg.bots_enabled = false
	cfg.time_limit = 0.0
	cfg.local_class_id = "shotgun"
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
	for i in 70:
		await get_tree().physics_frame
	var w := local.weapon_manager.get_current_weapon()
	if not w.data.pump_action or not w.data.reload_single_shells:
		_fail("Schrotflinte erwartet (Pump-Action, einzelne Patronen), gefunden: " + w.data.weapon_id)
	# 1) empty tube: nothing to fire, the reload keeps running
	w.magazine = 0
	w.start_reload()
	if w.try_fire(false, 0.0, false, false) or w.state != Weapon.State.RELOADING:
		_fail("Schrotflinte: leere Waffe darf das Nachladen nicht per Schuss abbrechen")
	# wait for the first shell (it counts the moment it is pushed in, before the cycle ends)
	var frames := 0
	while w.magazine < 1 and frames < 120:
		await get_tree().physics_frame
		frames += 1
	if w.magazine != 1 or w.state != Weapon.State.RELOADING:
		_fail("Schrotflinte: erste Patrone sollte beim Einschieben zaehlen (Magazin %d, Status %d)" % [w.magazine, w.state])
	# 2) a shell has just been pushed in: a shot interrupts at once, smooth exit, then the shot is fired
	w.cancel_actions()
	w.magazine = 2
	w.start_reload()
	frames = 0
	while w.magazine < 3 and frames < 120:
		await get_tree().physics_frame
		frames += 1
	if w.magazine != 3 or w.state != Weapon.State.RELOADING:
		_fail("Schrotflinte: Patrone sollte beim Einschieben zaehlen (Magazin %d, Status %d)" % [w.magazine, w.state])
	var reserve_before := w.reserve
	if w.try_fire(false, 0.0, false, false):
		_fail("Schrotflinte: der unterbrechende Schuss darf erst nach dem Anlegen fallen")
	if w.state != Weapon.State.RELOAD_EXIT:
		_fail("Schrotflinte: Schuss im Nachladen sollte abbrechen (Status %d)" % w.state)
	if not w.is_reloading():
		_fail("Schrotflinte: der Abbruch muss als Nachladen zaehlen (Sprint/Granate)")
	local.input.fire_pressed = true # second click during the exit: only queued, no double shot
	var shots := 0
	var mag_before := w.magazine
	var pump_hand := w.model.get_node_or_null("LeftHand") as Node3D
	var pump_travel := 0.0
	for i in 60:
		await get_tree().physics_frame
		if w.magazine < mag_before - shots:
			shots += 1
		if pump_hand != null and w.state == Weapon.State.PUMPING:
			pump_travel = maxf(pump_travel, pump_hand.position.z - w._pump_hand_rest.z)
	if pump_travel < 0.04:
		_fail("Schrotflinte: die linke Hand bewegt sich beim Repetieren nicht mit (%.3f m)" % pump_travel)
	if w.magazine != mag_before - 1:
		_fail("Schrotflinte: nach dem Abbruch genau ein Schuss erwartet (Magazin %d statt %d)" % [w.magazine, mag_before - 1])
	if w.reserve != reserve_before:
		_fail("Schrotflinte: Reserve veraendert sich beim Abbruch (%d statt %d)" % [w.reserve, reserve_before])
	if w.fire_queue_t > 0.0:
		_fail("Schrotflinte: vorgemerkter Schuss wurde nicht verbraucht")
	# 3) afterwards the weapon is in the rest pose (hand back on the forend) and reloads normally again
	var lh := w.model.get_node_or_null("LeftHand") as Node3D
	for i in 60:
		await get_tree().physics_frame
	if w.state != Weapon.State.IDLE:
		_fail("Schrotflinte: nach Schuss und Pumpen sollte sie bereit sein (Status %d)" % w.state)
	if lh != null and not lh.visible:
		_fail("Schrotflinte: Hand nach dem Abbruch unsichtbar")
	w.magazine = 4
	if not w.start_reload():
		_fail("Schrotflinte: Nachladen nach einem Abbruch nicht moeglich")
	frames = 0
	while w.is_reloading() and frames < 400:
		await get_tree().physics_frame
		frames += 1
	if w.magazine != w.data.magazine_size:
		_fail("Schrotflinte: Nachladen nach Abbruch unvollstaendig (%d/%d)" % [w.magazine, w.data.magazine_size])
	game.free()
	await get_tree().process_frame
	print("Schrotflinte: Schuss unterbricht das Nachladen (eingelegte Patrone zaehlt, sanfter Abbruch, genau ein Schuss)")


## Flashbang: own slot, the same throw behaviour as the frag grenade, blinding by distance / view direction / walls,
## the white-out with muffled sound, blinded bots, and a grenade that hits an enemy hurts a little (hitmarker).
func _check_flashbang() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_FFA
	cfg.map_id = "test_arena"
	cfg.bots_enabled = true
	cfg.bot_count = 1
	cfg.time_limit = 0.0
	MatchManager.prepare_match(cfg)
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	MatchManager.warmup_left = 0.05
	var waited := 0.0
	while MatchManager.state != MatchManager.State.RUNNING and waited < 6.0:
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
	var bot_ctrl := bot_node.get_node("BotController") as Node
	bot_ctrl.set_physics_process(false)
	for i in 70:
		await get_tree().physics_frame
	var wm := local.weapon_manager
	if wm.flashbangs != 1 or wm.grenades != 2:
		_fail("Ausruestung: 2 Granaten + 1 Blendgranate erwartet (%d / %d)" % [wm.grenades, wm.flashbangs])
	var flashes := {"n": 0}
	var on_flash := func(_c: Vector3, _t: int) -> void: flashes["n"] += 1
	GameEvents.flashbang_exploded.connect(on_flash)
	# --- throw with the own key: pin, held ready while the key is down, thrown on release, goes off after its fuse
	local.input.flash_pressed = true
	await get_tree().physics_frame
	if wm.flashbangs != 0 or wm.grenades != 2 or wm._grenade_kind != Grenade.KIND_FLASH:
		_fail("Blendgranate: Taste F zieht keine Blendgranate (Blend %d, Granaten %d)" % [wm.flashbangs, wm.grenades])
	if not game.hud.grenade_label.text.ends_with("BLENDGRANATE  0"):
		_fail("HUD zeigt die Blendgranaten nicht (%s)" % game.hud.grenade_label.text)
	local.input.flash_held = true
	for i in 80:
		await get_tree().physics_frame
	var in_flight := 0
	for c in game.projectiles_container.get_children():
		if c is Grenade:
			in_flight += 1
	if not wm.grenade_holding or in_flight != 0:
		_fail("Blendgranate wird nicht wurfbereit gehalten (halten %s, in der Luft %d)" % [str(wm.grenade_holding), in_flight])
	local.input.flash_held = false
	for i in 40:
		await get_tree().physics_frame
	var thrown: Grenade = null
	for c in game.projectiles_container.get_children():
		if c is Grenade:
			thrown = c
	if thrown == null or thrown.kind != Grenade.KIND_FLASH:
		_fail("Beim Loslassen wurde keine Blendgranate geworfen")
	var fuse_wait := 0
	while int(flashes["n"]) == 0 and fuse_wait < 200:
		await get_tree().physics_frame
		fuse_wait += 1
	if int(flashes["n"]) != 1:
		_fail("Blendgranate zuendet nicht genau einmal (%d)" % int(flashes["n"]))
	GameEvents.flashbang_exploded.disconnect(on_flash)
	game.flash_overlay.clear()
	# --- strength: facing it / sideways / away / far away / behind a wall (high above the map, nothing else around)
	var space := local.get_world_3d().direct_space_state
	var eye := Vector3(0.0, 90.0, 0.0)
	var fwd := Vector3(0.0, 0.0, -1.0)
	var spot := eye + Vector3(0.0, 0.0, -4.0)
	var facing := FlashMath.intensity(space, spot, eye, fwd)
	var side := FlashMath.intensity(space, spot, eye, Vector3.RIGHT)
	var away := FlashMath.intensity(space, spot, eye, -fwd)
	var far := FlashMath.intensity(space, eye + Vector3(0.0, 0.0, -40.0), eye, fwd)
	if facing < 0.9 or not (away < side and side < facing) or away > 0.2 or far != 0.0:
		_fail("Blendstaerke: nach vorn %.2f, seitlich %.2f, abgewandt %.2f, weit weg %.2f" % [facing, side, away, far])
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 8.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = 1
	game.add_child(wall)
	wall.global_position = eye + Vector3(0.0, 0.0, -2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blocked := FlashMath.intensity(space, spot, eye, fwd)
	wall.free()
	if blocked > 0.05:
		_fail("Blendgranate hinter einer Wand blendet trotzdem (%.2f)" % blocked)
	var blind_full := FlashMath.blind_time(1.0)
	var total_full := blind_full + FlashMath.fade_time(1.0)
	if blind_full < 1.4 or blind_full > 2.4 or total_full < 4.5 or total_full > 6.5 or FlashMath.blind_time(0.3) > 0.5:
		_fail("Blenddauer unpassend (Weiss %.1f s, gesamt %.1f s)" % [blind_full, total_full])
	# --- white-out, muffled sound, ringing; a weaker flash never shortens a stronger one; everything switches off again
	var ov: FlashOverlay = game.flash_overlay
	ov.trigger(1.0)
	for i in 4:
		await get_tree().process_frame
	if not ov.is_active() or not ov.rect.visible or ov.level_at(0.5) < 0.999 or ov.level_at(blind_full + FlashMath.fade_time(1.0) + 0.1) != 0.0:
		_fail("Weissblende laeuft nicht wie geplant")
	if AudioManager.get_flash_effect() < 0.5 or not _bus_muffled("Weapons") or not _bus_muffled("Ambience"):
		_fail("Waehrend der Blendung sind die Geraeusche nicht gedaempft (%.2f)" % AudioManager.get_flash_effect())
	if _bus_muffled("HitOther") or _bus_muffled("UI"):
		_fail("Tinnitus/Oberflaeche duerfen nicht gedaempft werden")
	ov.trigger(0.2)
	if ov.intensity < 0.99:
		_fail("Ein schwaecherer Blitz hat den staerkeren ersetzt")
	ov.clear()
	if ov.rect.visible or AudioManager.get_flash_effect() != 0.0 or _bus_muffled("Weapons"):
		_fail("Blendung wird nicht sauber beendet")
	# --- bots: blinded when looking into it, unaffected with the back to it
	bot_node.global_position = Vector3(40.0, 90.0, 0.0) # free air: nothing in the line of sight
	bot_node.rotation.y = 0.0
	bot_node.head.set_pitch(0.0)
	var bot_spot := bot_node.get_eye_position() + bot_node.head.get_aim_direction() * 3.0
	bot_ctrl._on_flashbang(bot_spot, 0)
	if float(bot_ctrl._blind_left) < 1.0:
		_fail("Bot wird von einer Blendgranate vor seinen Augen nicht geblendet (%.2f s)" % float(bot_ctrl._blind_left))
	bot_ctrl._blind_left = 0.0
	bot_node.rotation.y = PI
	bot_ctrl._on_flashbang(bot_spot, 0)
	if float(bot_ctrl._blind_left) > 0.0:
		_fail("Bot mit dem Ruecken zur Blendgranate wird geblendet")
	# --- a grenade that hits an enemy: 5 damage and a hitmarker, once; the thrower is not hurt
	var hits := {"n": 0}
	var on_hit := func(_head: bool, _killed: bool) -> void: hits["n"] += 1
	GameEvents.local_player_hit_enemy.connect(on_hit)
	for kind in [Grenade.KIND_FRAG, Grenade.KIND_FLASH]:
		var g: Grenade = (load("res://scenes/weapons/grenade.tscn") as PackedScene).instantiate()
		g.kind = kind
		g.thrower_id = me.id
		g.thrower_team = me.team
		game.projectiles_container.add_child(g)
		g.global_position = Vector3(0.0, 95.0, 0.0)
		g.linear_velocity = Vector3(0.0, 0.0, -12.0)
		var hp := bot_node.health.health
		var own_hp := local.health.health
		local.hit_flag = 0
		g._direct_hit(bot_node)
		g._direct_hit(bot_node)
		g._direct_hit(local)
		if absf((hp - bot_node.health.health) - Grenade.DIRECT_HIT_DAMAGE) > 0.01:
			_fail("Direkttreffer mit der Granate (Art %d): Schaden %.1f statt %.1f" % [kind, hp - bot_node.health.health, Grenade.DIRECT_HIT_DAMAGE])
		if local.health.health < own_hp:
			_fail("Die eigene Granate verletzt den Werfer")
		if local.hit_flag & HitFeedback.BODY == 0:
			_fail("Direkttreffer setzt kein Trefferflag fuer die Killcam")
		g.free()
	GameEvents.local_player_hit_enemy.disconnect(on_hit)
	if int(hits["n"]) != 2:
		_fail("Direkttreffer: je Granate genau ein Hitmarker erwartet (%d bei 2 Granaten)" % int(hits["n"]))
	# --- dying ends the flash at once (killcam is clear)
	ov.trigger(1.0)
	local.take_damage(9999.0, bot.id, "ak47", local.get_center(), false, bot_node.global_position)
	for i in 3:
		await get_tree().process_frame
	if ov.is_active() or AudioManager.get_flash_effect() != 0.0:
		_fail("Nach dem Tod bleibt die Blendung aktiv")
	print("Blendgranate: eigener Slot, Halten/Werfen, Staerke nach Blick/Wand/Abstand, Weissblende mit Daempfung, Bots, Direkttreffer OK")
	game.free()
	await get_tree().process_frame


func _bus_muffled(bus: String) -> bool:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return false
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectLowPassFilter and AudioServer.is_bus_effect_enabled(idx, e):
			return true
	return false


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


## Settings menu and audio architecture: buses, categories, independence, persistence, panel wiring.
func _check_settings_and_audio() -> void:
	# every sound file belongs to a known category with an existing bus (nothing falls back silently)
	var dir := DirAccess.open("res://assets/audio/sfx")
	var unmapped: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".wav"):
			var n := f.get_basename()
			if AudioCategories.category_of(n) == "sfx" and not n.begins_with("none"):
				unmapped.append(n)
	if not unmapped.is_empty():
		_fail("Sounds ohne Kategorie (fallen auf SFX): %s" % ", ".join(unmapped))
	for e in AudioCategories.ENTRIES:
		var idx := AudioServer.get_bus_index(String(e["bus"]))
		if idx < 0:
			_fail("Audiobus %s fehlt" % e["bus"])
		elif e["parent"] != "" and AudioServer.get_bus_send(idx) != StringName(String(e["parent"])):
			_fail("Bus %s sendet nicht an %s" % [e["bus"], e["parent"]])
	var names := {}
	for i in AudioServer.bus_count:
		var bn := String(AudioServer.get_bus_name(i))
		if names.has(bn):
			_fail("Doppelter Audiobus: %s" % bn)
		names[bn] = true
	# categories are independent
	var snapshot := GameSettings.volumes.duplicate()
	GameSettings.set_volume("weapons", 0.5)
	var weapons_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Weapons"))
	if absf(weapons_db - linear_to_db(0.5)) > 0.1:
		_fail("Waffen-Regler stellt den Bus nicht ein (%.1f dB)" % weapons_db)
	for other in ["Grenades", "Reload", "Hitmarker", "Master", "Music", "UI"]:
		if absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(other))) > 0.5 and other != "Music":
			_fail("Waffen-Regler beeinflusst Bus %s" % other)
	GameSettings.set_volume("kill", 0.0)
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("Kill")) or AudioServer.is_bus_mute(AudioServer.get_bus_index("Headshot")):
		_fail("Kill-Regler stummt falsche Busse")
	for id in snapshot:
		GameSettings.set_volume(id, snapshot[id])
	# a played sound lands on its category bus
	var pl := AudioManager.play_2d("hitmarker_headshot")
	if pl == null or pl.bus != "Headshot":
		_fail("hitmarker_headshot spielt nicht ueber den Headshot-Bus")
	var pg := AudioManager.play_2d("explosion")
	if pg == null or pg.bus != "Grenades":
		_fail("explosion spielt nicht ueber den Granaten-Bus")
	AudioManager.stop_all()
	# persistence: save, change in memory, load again
	var path := "user://settings_test.cfg"
	GameSettings.set_volume("weapons", 0.3)
	GameSettings.set_volume("wind", 0.7)
	GameSettings.window_mode = 2
	GameSettings.fps_limit = 60
	GameSettings.vsync = false
	GameSettings.antialiasing = 1
	GameSettings.shadow_quality = 1
	GameSettings.show_minimap = false
	GameSettings.ads_sensitivity = 0.7
	GameSettings.save(path)
	GameSettings.volumes = AudioCategories.default_volumes()
	GameSettings.window_mode = 0
	GameSettings.fps_limit = 0
	GameSettings.vsync = true
	GameSettings.antialiasing = 2
	GameSettings.shadow_quality = 3
	GameSettings.show_minimap = true
	GameSettings.ads_sensitivity = 1.0
	GameSettings.load_settings(path)
	if absf(GameSettings.get_volume("weapons") - 0.3) > 0.001 or absf(GameSettings.get_volume("wind") - 0.7) > 0.001 or GameSettings.get_volume("master") != 1.0:
		_fail("Lautstaerken wurden nicht gespeichert/geladen")
	if GameSettings.window_mode != 2 or GameSettings.fps_limit != 60 or GameSettings.vsync or GameSettings.antialiasing != 1 \
			or GameSettings.shadow_quality != 1 or GameSettings.show_minimap or absf(GameSettings.ads_sensitivity - 0.7) > 0.001:
		_fail("Grafik-/Spieleinstellungen wurden nicht gespeichert/geladen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# restore defaults
	GameSettings.volumes = AudioCategories.default_volumes()
	GameSettings.window_mode = 0
	GameSettings.fps_limit = 0
	GameSettings.vsync = true
	GameSettings.antialiasing = 2
	GameSettings.shadow_quality = 3
	GameSettings.show_minimap = true
	GameSettings.ads_sensitivity = 1.0
	GameSettings.apply()
	await _check_ambience_muted_by_default()
	# the panel: presets fill the controls, manual changes switch to "benutzerdefiniert", Zurueck undoes live sound changes
	var panel := SettingsPanel.new()
	add_child(panel)
	panel.open()
	panel._on_preset_selected(0)
	if absf(float(panel._get_control(panel._find("render_scale"))) - 0.8) > 0.001 or int(panel._get_control(panel._find("shadow_quality"))) != 1:
		_fail("Grafik-Voreinstellung Niedrig fuellt die Regler nicht")
	var aa := panel._find("antialiasing")
	(aa["ctrl"] as OptionButton).select(2)
	panel._changed(aa)
	if int(panel._get_control(panel._preset_entry)) != 3:
		_fail("Manuelle Aenderung schaltet die Voreinstellung nicht auf benutzerdefiniert")
	var vol := panel._find("weapons")
	(vol["ctrl"] as HSlider).value = 20.0
	if absf(GameSettings.get_volume("weapons") - 0.2) > 0.001:
		_fail("Lautstaerke-Regler wirkt nicht sofort")
	panel._cancel()
	if absf(GameSettings.get_volume("weapons") - 1.0) > 0.001:
		_fail("Zurueck stellt die Lautstaerke nicht wieder her")
	panel.open()
	(panel._find("fps_limit")["ctrl"] as OptionButton).select(2)
	(panel._find("show_crosshair")["ctrl"] as CheckButton).button_pressed = false
	(vol["ctrl"] as HSlider).value = 40.0
	panel._apply()
	if GameSettings.fps_limit != 60 or GameSettings.show_crosshair or absf(GameSettings.get_volume("weapons") - 0.4) > 0.001:
		_fail("Uebernehmen schreibt die Panel-Werte nicht in GameSettings")
	GameSettings.fps_limit = 0
	GameSettings.show_crosshair = true
	GameSettings.volumes = AudioCategories.default_volumes()
	GameSettings.apply()
	panel.free()
	print("Einstellungen/Audio: %d Kategorien, Busse, Unabhaengigkeit, Speichern, Menue OK" % AudioCategories.ENTRIES.size())


## End screen (offline): scoreboard with small vote cards first, then the final vote in the middle of the
## screen, then the closing animation, then the chosen map is handed over (the real scene change is cut off here).
func _check_end_screen_sequence() -> void:
	NetworkManager.vote_time = 6.0
	NetworkManager.vote_outcome_time = 0.6
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
	var screen: MatchEndScreen = game.match_end
	screen.map_chosen.disconnect(game._on_map_chosen)
	var chosen := [""]
	screen.map_chosen.connect(func(id: String) -> void: chosen[0] = id)
	MatchManager.end_match()
	waited = 0.0
	while not screen.visible and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not screen.visible:
		_fail("Endscreen erschien nicht")
	var t_results := 0.0
	while screen._phase == MatchEndScreen.Phase.RESULTS and t_results < 8.0:
		if t_results < 0.3 and (screen._stage.visible or not screen.vote_box.visible or not screen.scoreboard.visible):
			_fail("Zu Beginn muessen Scoreboard und kleine Karten sichtbar sein (Stage %s)" % str(screen._stage.visible))
		if t_results < 0.3 and (screen._stage_class_host.modulate.a > 0.05 or screen._content.get_node("ClassBox").visible):
			_fail("Die Klassenwahl darf erst erscheinen, wenn das Scoreboard verschwindet")
		await get_tree().process_frame
		t_results += get_process_delta_time()
	# 6 s vote: the final phase is half of it, so it starts after 3 s (the real vote: 10 s + 10 s)
	if t_results < 2.5 or t_results > 3.8:
		_fail("Scoreboard-Phase dauerte %.1f s (erwartet ca. 3.0 s bei 6 s Abstimmung)" % t_results)
	if screen._phase != MatchEndScreen.Phase.FINAL or screen._cards.size() != 3 or not screen._stage.visible:
		_fail("Finale Abstimmung startete nicht (Phase %d, Karten %d)" % [screen._phase, screen._cards.size()])
	await get_tree().create_timer(1.4).timeout
	if screen._content.visible or screen.vote_picker.modulate.a > 0.05:
		_fail("Scoreboard und kleine Karten muessen nach dem Wechsel verschwunden sein")
	var mid := screen.size * 0.5
	if screen._stage_class_host.modulate.a < 0.9 or screen._stage_class.get_child_count() != GameDirector.get_class_ids().size():
		_fail("Die Klassenwahl erscheint in der finalen Phase nicht (Alpha %.2f)" % screen._stage_class_host.modulate.a)
	var leave_mid := screen._stage_leave.position.x + screen._stage_leave.size.x * 0.5
	if absf(leave_mid - mid.x) > 3.0:
		_fail("Hauptmenue-Knopf sitzt nicht mittig (x %.0f statt %.0f)" % [leave_mid, mid.x])
	var strip_mid := screen._stage_class.global_position.x + screen._stage_class.size.x * 0.5
	if absf(strip_mid - (screen.global_position.x + mid.x)) > 3.0:
		_fail("Klassenwahl sitzt nicht mittig (x %.0f statt %.0f)" % [strip_mid, screen.global_position.x + mid.x])
	var inside := 0
	for id in screen._cards:
		var card: VoteCard = screen._cards[id]
		if card.size.x < 200.0 or absf(card.position.y + card.size.y * 0.5 - mid.y) > screen.size.y * 0.3:
			_fail("Karte %s ist nicht gross/mittig (Groesse %s, Position %s)" % [id, str(card.size), str(card.position)])
		inside += 1
	screen._on_card_pressed("harbor")
	if not screen._cards["harbor"]._selected:
		_fail("Klick auf die grosse Karte waehlt sie nicht aus")
	var t_outcome := 0.0
	while screen._phase != MatchEndScreen.Phase.OUTCOME and t_outcome < 4.0:
		await get_tree().process_frame
		t_outcome += get_process_delta_time()
	if screen._phase != MatchEndScreen.Phase.OUTCOME or screen._winner != "harbor":
		_fail("Abstimmung endete nicht mit der gewaehlten Karte (Phase %d, Sieger %s)" % [screen._phase, screen._winner])
	var t_hand := 0.0
	while chosen[0] == "" and t_hand < 3.0:
		await get_tree().process_frame
		t_hand += get_process_delta_time()
	if chosen[0] != "harbor":
		_fail("Gewinnerkarte wurde nicht uebergeben (%s)" % chosen[0])
	if t_hand < 0.3:
		_fail("Abschluss-Animation zu kurz (%.2f s)" % t_hand)
	var win_card: VoteCard = screen._cards["harbor"]
	if win_card.expand < 0.95 or win_card.size.x < screen.size.x * 0.95:
		_fail("Gewinnerkarte fuellt am Ende nicht den Bildschirm (expand %.2f, Breite %.0f)" % [win_card.expand, win_card.size.x])
	if Scoreboard.kd_text(10, 2) != "5.00" or Scoreboard.kd_text(7, 0) != "7.00" or Scoreboard.kd_text(1, 3) != "0.33":
		_fail("K/D wird falsch berechnet (%s, %s, %s)" % [Scoreboard.kd_text(10, 2), Scoreboard.kd_text(7, 0), Scoreboard.kd_text(1, 3)])
	print("Endscreen: %.1f s Scoreboard, finale Abstimmung mit %d grossen Karten, Gewinner fuellt den Bildschirm" % [t_results, inside])
	NetworkManager.vote_time = NetworkManager.VOTE_TIME
	NetworkManager.vote_outcome_time = 2.8
	game.free()
	await get_tree().process_frame


## First-person arms: the IK chain is continuous (shoulder -> elbow -> wrist) and reaches every wrist target,
## stretched when far away - so no arm ends in mid-air at any FOV.
func _check_first_person_arms() -> void:
	var arms := FirstPersonArms.new()
	add_child(arms)
	var targets := [Vector3(0.2, -0.3, -0.3), Vector3(-0.05, -0.12, -0.75), Vector3(0.0, -0.5, -0.4), Vector3(0.3, 0.0, -0.9), Vector3(0.1, -0.2, -1.1)]
	var worst := 0.0
	for t in targets:
		var tr: Vector3 = t
		var tl := Vector3(-tr.x, tr.y, tr.z)
		arms.update(tr, tl)
		for side in 2:
			var wrist_target: Vector3 = tr if side == 0 else tl
			var upper: MeshInstance3D = arms._upper[side]
			var fore: MeshInstance3D = arms._fore[side]
			var shoulder: Vector3 = FirstPersonArms.SHOULDERS[side]
			var elbow_from_upper: Vector3 = upper.transform * Vector3(0, 0, -FirstPersonArms.UPPER)
			var wrist_from_fore: Vector3 = fore.transform * Vector3(0, 0, -FirstPersonArms.FORE)
			worst = maxf(worst, upper.transform.origin.distance_to(shoulder))
			worst = maxf(worst, elbow_from_upper.distance_to(fore.transform.origin))
			worst = maxf(worst, wrist_from_fore.distance_to(wrist_target))
	if worst > 0.003:
		_fail("Ego-Arme: Kette nicht durchgehend / Ziel nicht erreicht (Abweichung %.4f m)" % worst)
	arms.update(Vector3.INF, Vector3.INF)
	if arms._fore[0].visible or arms._fore[1].visible:
		_fail("Ego-Arme ohne Hand muessen ausgeblendet sein")
	arms.free()
	print("Ego-Arme: IK erreicht alle Ziele (max. Abweichung %.4f m)" % worst)


## Death skull marker for fallen teammates: a sprite that shows through walls and removes itself.
func _check_death_skull() -> void:
	var holder := Node3D.new()
	add_child(holder)
	DeathSkull.spawn(holder, Vector3(0, 2, 0))
	var sprite := holder.get_child(0) as Sprite3D
	if sprite == null or not sprite.no_depth_test or sprite.texture == null or sprite.texture.get_width() < 32:
		_fail("Totenkopf-Markierung fehlerhaft (nicht durch Waende sichtbar oder ohne Textur)")
	holder.free()
	print("Totenkopf-Markierung OK")


## Ambience (wind, water, birds, planes, own breathing) is silent by default but fully adjustable;
## old settings files get that default, deliberate values stay.
func _check_ambience_muted_by_default() -> void:
	var ids := ["birds", "wind", "water", "distant", "breath", "ambient_other"]
	for id in ids:
		var e := AudioCategories.get_entry(id)
		if float(e["default"]) != 0.0 or GameSettings.get_volume(id) != 0.0:
			_fail("Umgebungsgeraeusch %s ist nicht standardmaessig stumm" % id)
		if not AudioServer.is_bus_mute(AudioServer.get_bus_index(String(e["bus"]))):
			_fail("Bus %s ist nicht stumm geschaltet" % e["bus"])
	if GameSettings.get_volume("ambience") != 1.0:
		_fail("Umgebung allgemein soll auf 100 % stehen (nur die Einzelregler sind aus)")
	# migration of an old file: the old default 100 % becomes the new default, a hand-lowered value stays
	var old_path := "user://settings_old_test.cfg"
	var old := ConfigFile.new()
	old.set_value("audio_volumes", "wind", 1.0)
	old.set_value("audio_volumes", "water", 0.35)
	old.set_value("audio_volumes", "weapons", 0.4)
	old.save(old_path)
	GameSettings.load_settings(old_path)
	if GameSettings.get_volume("wind") != 0.0 or absf(GameSettings.get_volume("water") - 0.35) > 0.001 or absf(GameSettings.get_volume("weapons") - 0.4) > 0.001:
		_fail("Migration alter Einstellungen: Wind %.2f, Wasser %.2f, Waffen %.2f (erwartet 0 / 0.35 / 0.4)" % [GameSettings.get_volume("wind"), GameSettings.get_volume("water"), GameSettings.get_volume("weapons")])
	GameSettings.volumes = AudioCategories.default_volumes()
	var cur_path := "user://settings_new_test.cfg"
	GameSettings.set_volume("wind", 1.0) # deliberately 100 % in a current file
	GameSettings.save(cur_path)
	GameSettings.volumes = AudioCategories.default_volumes()
	GameSettings.load_settings(cur_path)
	if absf(GameSettings.get_volume("wind") - 1.0) > 0.001:
		_fail("Ein bewusst gesetzter Wert in einer aktuellen Datei wurde faelschlich zurueckgesetzt")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cur_path))
	GameSettings.volumes = AudioCategories.default_volumes()
	GameSettings.apply()
	# the ambience system: silent categories are paused, raising a slider (or the parent) wakes exactly those up
	var amb := AmbienceSystem.new()
	add_child(amb)
	amb.setup("harbor")
	await get_tree().process_frame
	await get_tree().process_frame
	if amb._players.size() < 2:
		_fail("Harbor sollte Wind- und Wasser-Loop anlegen (%d)" % amb._players.size())
	for p in amb._players:
		if not p.stream_paused:
			_fail("Ein Umgebungs-Loop laeuft obwohl alles stumm ist")
	GameSettings.set_volume("wind", 0.5)
	await get_tree().process_frame
	for i in amb._players.size():
		var cat: String = amb._player_categories[i]
		if cat == "wind" and amb._players[i].stream_paused:
			_fail("Wind laeuft nicht, obwohl der Regler hochgezogen wurde")
		if cat == "water" and not amb._players[i].stream_paused:
			_fail("Wasser laeuft, obwohl sein Regler auf 0 steht")
	GameSettings.set_volume("ambience", 0.0)
	await get_tree().process_frame
	for p in amb._players:
		if not p.stream_paused:
			_fail("Umgebung allgemein auf 0 muss alle Umgebungs-Loops stoppen")
	GameSettings.volumes = AudioCategories.default_volumes()
	GameSettings.apply()
	amb.free()
	print("Umgebung: standardmaessig stumm, Migration alter Dateien, Regler wecken genau ihre Kategorie")


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


## Grenade handling in a quiet match (no bots): holding G keeps the pulled grenade ready, a sprint key that is
## already down does not cancel the throw, a fresh sprint press does.
func _check_grenade_hold(game: Node, local: Player) -> void:
	# the first-person model has no sleeves of its own (the IK arms replace them), also after a reload pose
	for w in local.weapon_manager.weapons:
		if w.model == null or w.rig == null:
			continue
		w.rig.apply(0.85, 1.0)
		for n in ["LeftForearm", "RightForearm"]:
			var sleeve := w.model.get_node_or_null(n) as Node3D
			if sleeve != null and sleeve.visible:
				_fail("%s: %s des Ego-Modells muss ausgeblendet bleiben" % [w.data.weapon_id, n])
		w.rig.reset()
	local.input.clear_all()
	local.global_position = Vector3(0.0, 0.1, 0.0)
	local.velocity = Vector3.ZERO
	local.rotation.y = PI
	for i in 60:
		await get_tree().physics_frame
	var wm: WeaponManager = local.weapon_manager
	var held_before := wm.grenades
	if held_before > 0:
		var known: Dictionary = {}
		for child in game.get_node("Projectiles").get_children():
			known[child.get_instance_id()] = true
		local.input.grenade_pressed = true
		local.input.grenade_held = true
		for i in 90: # 1.5 s: longer than the whole throw would take
			await get_tree().physics_frame
		var thrown_early := 0
		for child in game.get_node("Projectiles").get_children():
			if child is Grenade and not known.has(child.get_instance_id()):
				thrown_early += 1
		if thrown_early != 0 or not wm.grenade_holding or wm.grenades != held_before - 1:
			_fail("Gehaltene Granate: geworfen (%d) oder nicht gehalten (haltend %s, Granaten %d)" % [thrown_early, str(wm.grenade_holding), wm.grenades])
		local.input.grenade_held = false # release: throw
		for i in 50:
			await get_tree().physics_frame
		var thrown := 0
		for child in game.get_node("Projectiles").get_children():
			if child is Grenade and not known.has(child.get_instance_id()):
				thrown += 1
				child.free() # harmless: it must not explode among the bots of the following tests
		if thrown != 1 or wm.grenade_holding:
			_fail("Gehaltene Granate: nach dem Loslassen %d neue Granaten (erwartet 1)" % thrown)
		print("Granate: bei gehaltener Taste wurfbereit gehalten, nach dem Loslassen geworfen")
	# --- a sprint key that is already down does not cancel the throw; pressing it during the throw does
	wm.grenades += 2
	var known2: Dictionary = {}
	for child in game.get_node("Projectiles").get_children():
		known2[child.get_instance_id()] = true
	local.input.sprint = true
	local.input.move = Vector2(0, 1)
	for i in 20:
		await get_tree().physics_frame
	local.input.grenade_pressed = true
	for i in 80:
		await get_tree().physics_frame
	var thrown_sprinting := 0
	for child in game.get_node("Projectiles").get_children():
		if child is Grenade and not known2.has(child.get_instance_id()):
			thrown_sprinting += 1
			child.free()
	if thrown_sprinting != 1:
		_fail("Granate bei gehaltener Sprinttaste wurde nicht geworfen (%d)" % thrown_sprinting)
	local.input.sprint = false
	local.input.move = Vector2.ZERO
	for i in 20:
		await get_tree().physics_frame
	local.input.grenade_pressed = true
	for i in 12:
		await get_tree().physics_frame
	var grenades_mid := wm.grenades
	local.input.sprint = true # a fresh sprint press during the throw breaks it off and gives the grenade back
	local.input.move = Vector2(0, 1)
	for i in 60:
		await get_tree().physics_frame
	local.input.sprint = false
	local.input.move = Vector2.ZERO
	if wm.grenades != grenades_mid + 1:
		_fail("Neuer Sprint-Druck brach den Wurf nicht ab (Granaten %d -> %d)" % [grenades_mid, wm.grenades])
	for child in game.get_node("Projectiles").get_children():
		if child is Grenade and not known2.has(child.get_instance_id()):
			child.free()
	print("Granate/Sprint: gehaltene Sprinttaste wirft, neuer Druck bricht ab")
	local.input.clear_all()


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
	for run in 3:
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
		elif run == 2:
			# holding sprint + forward must NOT end the slide early (only Space does)
			var ticks2 := 0
			while local.is_sliding and ticks2 < 120:
				await get_tree().physics_frame
				ticks2 += 1
			if ticks2 < 30:
				_fail("Slide endet durch gehaltenes Sprint+Vorwaerts schon nach %d Ticks (nur Leertaste darf abbrechen)" % ticks2)
			print("Slide: Sprint+Vorwaerts bricht nicht ab (%d Ticks bis zum natuerlichen Ende)" % ticks2)
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
	await _check_grenade_hold(game, local)
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
	# the killer hits us once with a real shot: the killcam must show his hitmarker
	var space := local.get_world_3d().direct_space_state
	for off in [Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 0, 5), Vector3(0, 0, -5), Vector3(3, 0, 3), Vector3(-3, 0, -3)]:
		bot_node.global_position = local.global_position + off # a spot with a clear line to us
		var los := PhysicsRayQueryParameters3D.create(bot_node.get_eye_position(), local.get_center(), 1)
		if space.intersect_ray(los).is_empty():
			break
	bot_node.face_towards(local.get_eye_position())
	for i in 40: # the turn takes 0.5 s
		await get_tree().physics_frame
	var bot_weapon := bot_node.weapon_manager.get_current_weapon()
	bot_weapon.fire_cooldown = 0.0
	bot_weapon.try_fire(true, 0.0, false, false)
	if bot_node.hit_flag & HitFeedback.BODY == 0:
		_fail("Treffer auf einen Gegner setzt kein Trefferflag (hit_flag=%d)" % bot_node.hit_flag)
	var hit_events := {"n": 0, "kill": 0}
	game.recorder.killer_hit.connect(func(_head: bool, killed: bool) -> void:
		hit_events["n"] += 1
		if killed:
			hit_events["kill"] += 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var remote_probe := bot_node.weapon_manager.get_current_weapon()
	remote_probe.play_remote_shot([[Vector3(0, 1, 0), Vector3.RIGHT, true, HitFeedback.BODY | HitFeedback.HEAD]])
	if bot_node.hit_flag != HitFeedback.BODY | HitFeedback.HEAD:
		_fail("Fremdschuss uebernimmt den Trefferstatus des Servers nicht (hit_flag=%d)" % bot_node.hit_flag)
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
	# jump the replay to the moment of the kill: the recorded hit of the killer shows up as hitmarker
	var kill_t: float = game.recorder.kill["t"]
	game.recorder._prev_cursor = kill_t - 0.6
	game.recorder._cursor = kill_t + 0.1
	await get_tree().process_frame
	if int(hit_events["n"]) < 1:
		_fail("Killcam: der Treffer des Moerders loest keinen Hitmarker aus")
	elif game._cam_hit_left <= 0.0 and game._cam_hit_total <= 0.0:
		_fail("Killcam: Hitmarker-Zustand wurde nicht gesetzt")
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
	MatchManager.runout_time = 1.7
	local.velocity = Vector3.ZERO
	local.input.move = Vector2(0, 1)
	local.input.sprint = true
	for i in 30:
		await get_tree().physics_frame
	local.input.clear_all()
	var speed_at_end := local.horizontal_speed
	MatchManager.end_match()
	await get_tree().process_frame
	if game._replay_active:
		_fail("Last-Kill-Cam startete ohne Ausklingen sofort")
	var end_wait := 0.0
	for i in 20: # 1/3 s of game time into the run-out
		await get_tree().physics_frame
	var speed_mid := local.horizontal_speed
	while not game._replay_active and end_wait < 4.0:
		await get_tree().process_frame
		end_wait += get_process_delta_time()

	if end_wait < 1.2:
		_fail("Last-Kill-Cam kam nach nur %.1f s (Ausklingen fehlt)" % end_wait)
	if speed_at_end > 3.0 and not (speed_mid > 0.2 and speed_mid < speed_at_end):
		_fail("Spieler bremst nach dem letzten Kill nicht langsam ab (Tempo %.1f -> %.1f)" % [speed_at_end, speed_mid])
	if local.horizontal_speed > 0.3:
		_fail("Spieler steht beim Start der Last-Kill-Cam noch nicht (Tempo %.1f)" % local.horizontal_speed)
	MatchManager.runout_time = 0.15
	if not game._replay_active or not game.recorder.playing:
		_fail("Last-Kill-Cam startete nicht")
	# the last kill cam cannot be skipped with Space
	var jump_ev := InputEventAction.new()
	jump_ev.action = "jump"
	jump_ev.pressed = true
	Input.parse_input_event(jump_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	if not game._replay_active or not game.recorder.playing:
		_fail("Die Last-Kill-Cam liess sich mit Leertaste ueberspringen")
	elif game.match_end.visible:
		_fail("Endbildschirm erschien schon waehrend des Replays")
	for i in 20:
		await get_tree().physics_frame
	if game._plate_name.text == "" or not game._bars.visible:
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
	# team match: the winner team's table on the left, the other one on the right, with a K/D column
	var sb: Scoreboard = game.match_end.scoreboard
	var tables := sb.content.get_child(sb.content.get_child_count() - 1)
	if not sb.side_by_side or tables.get_child_count() != 2:
		_fail("Teamergebnis: zwei Tabellen nebeneinander erwartet (side_by_side %s)" % str(sb.side_by_side))
	else:
		var first_head: Label = tables.get_child(0).get_child(0).get_child(0)
		var winner_name: String = "TEAM " + Teams.name_of(int(MatchManager.winner["team"])).to_upper()
		if first_head.text != winner_name:
			_fail("Linke Tabelle gehoert nicht dem Siegerteam (%s statt %s)" % [first_head.text, winner_name])
		var kd_found := false
		for l in tables.get_child(0).find_children("*", "Label", true, false):
			if (l as Label).text == "K/D":
				kd_found = true
		if not kd_found:
			_fail("K/D-Spalte fehlt im Endscoreboard")
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
		# no spawn point may lie inside solid geometry (player capsule free of the world)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for sp in get_tree().get_nodes_in_group("spawn_points"):
			if SpawnSystem.is_blocked(map.get_world_3d().direct_space_state, sp.global_position):
				_fail("%s: Spawnpunkt %s liegt in fester Geometrie (freie Stelle in der Naehe: %s)" % [map_id, sp.global_position, SpawnSystem.free_position_near(map.get_world_3d().direct_space_state, sp.global_position)])
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
	for i in 50:
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
	var end_waited := 0.0
	while not game.match_end.visible and end_waited < 3.0:
		await get_tree().process_frame
		end_waited += get_process_delta_time()
	if not game.match_end.visible:
		_fail("Endbildschirm nicht sichtbar")
	print("Match-Simulation: Bewegung, Schuss, Nachladen, Wechsel, Granate, Kill, Respawn, Matchende OK")
	game.free()
	await get_tree().process_frame
