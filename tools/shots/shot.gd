extends Node
## Developer tool: renders a scene/state to a PNG (needs a display, e.g. xvfb, and
## a renderer; the headless dummy renderer cannot draw).
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##       --resolution 1920x1080 tools/shots/shot.tscn -- --target=menu_settings --out=/tmp/out.png
##
## Targets: menu, menu_settings, menu_online, menu_quick, menu_classes,
##   fp_<class>_<hip|ads>   first-person view in the test arena (class: assault, smg, shotgun)
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
			"menu_quick":
				menu._show_quick_play()
			"menu_classes":
				menu._show_classes()
		node = menu
	elif target.begins_with("fp_"):
		await _first_person_view()
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
