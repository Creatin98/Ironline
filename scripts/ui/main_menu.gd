extends Control
## Main menu: Multiplayer (quick play until the lobby arrives in phase 7),
## Klassen (overview), Einstellungen, Spiel verlassen.

var _root: VBoxContainer
var _quick_panel: PanelContainer
var _classes_panel: PanelContainer
var _settings: SettingsPanel
var _mode_opt: OptionButton
var _map_opt: OptionButton
var _team_opt: OptionButton
var _class_opt: OptionButton
var _bots_check: CheckBox
var _bot_count: HSlider
var _bot_count_label: Label
var _bot_diff: OptionButton
var _map_ids: Array = []
var _class_ids: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.08, 0.1)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.custom_minimum_size = Vector2(520, 0)
	stripe.color = Color(0.04, 0.045, 0.06)
	add_child(stripe)
	var accent := ColorRect.new()
	accent.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	accent.position = Vector2(520, 0)
	accent.custom_minimum_size = Vector2(4, 0)
	accent.color = UITheme.ACCENT
	add_child(accent)

	_root = UITheme.vbox(14)
	_root.position = Vector2(80, 140)
	_root.custom_minimum_size = Vector2(360, 0)
	add_child(_root)
	_root.add_child(UITheme.label("IRONLINE", 72, UITheme.ACCENT))
	_root.add_child(UITheme.label("Arcade Multiplayer FPS", 22, UITheme.TEXT_DIM))
	_root.add_child(UITheme.spacer(40))
	_menu_button("Multiplayer", _show_quick_play)
	_menu_button("Klassen", _show_classes)
	_menu_button("Einstellungen", _show_settings)
	_menu_button("Spiel verlassen", GameDirector.quit_game)
	_root.add_child(UITheme.spacer(40))
	_root.add_child(UITheme.label("Entwicklungsstand: Gunplay, Spielmodi, drei Maps, Bots\nOnline-Lobby folgt (Phase 6/7)", 14, UITheme.TEXT_DIM))

	_build_quick_play()
	_build_classes()
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _settings.visible = false)
	add_child(_settings)


func _menu_button(text: String, callback: Callable) -> void:
	var b := UITheme.button(text, 24, 360)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	_root.add_child(b)


func _hide_panels() -> void:
	_quick_panel.visible = false
	_classes_panel.visible = false
	_settings.visible = false


# ----------------------------------------------------------------------------- quick play

func _build_quick_play() -> void:
	_quick_panel = UITheme.panel(Color(0.05, 0.06, 0.08, 0.95), 6)
	_quick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_quick_panel.position = Vector2(600, 140)
	_quick_panel.custom_minimum_size = Vector2(760, 0)
	_quick_panel.visible = false
	add_child(_quick_panel)
	var v := UITheme.vbox(12)
	_quick_panel.add_child(v)
	v.add_child(UITheme.label("MATCH ERSTELLEN", 32, UITheme.ACCENT))
	v.add_child(UITheme.label("Lokales Match gegen Bots. Online-Lobby folgt in Phase 6/7.", 16, UITheme.TEXT_DIM))
	v.add_child(UITheme.spacer(8))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)

	_mode_opt = UITheme.option(["Team Deathmatch (6 vs 6, 50 Kills)", "Free for All (8 Spieler, 25 Kills)"], 0, 420)
	_mode_opt.item_selected.connect(func(_i: int) -> void: _refresh_quick_options())
	_grid_row(grid, "Spielmodus", _mode_opt)
	_map_ids = GameDirector.get_map_ids()
	var map_names: Array = []
	for id in _map_ids:
		map_names.append(GameDirector.get_map_info(id)["name"])
	_map_opt = UITheme.option(map_names, 0, 420)
	_grid_row(grid, "Map", _map_opt)
	_team_opt = UITheme.option(["Rot", "Blau"], 0, 420)
	_grid_row(grid, "Team", _team_opt)
	_class_ids = GameDirector.get_class_ids()
	var class_names: Array = []
	for id in _class_ids:
		class_names.append(GameDirector.get_class_data(id).display_name)
	_class_opt = UITheme.option(class_names, 0, 420)
	_grid_row(grid, "Klasse", _class_opt)
	_bots_check = CheckBox.new()
	_bots_check.text = "Bots aktiv"
	_bots_check.button_pressed = true
	_bots_check.add_theme_font_size_override("font_size", 18)
	_bots_check.toggled.connect(func(_on: bool) -> void: _refresh_quick_options())
	_grid_row(grid, "Bots", _bots_check)
	var bot_row := UITheme.hbox(12)
	_bot_count = UITheme.hslider(1, 11, 1, 7, 340)
	_bot_count_label = UITheme.label("7", 18)
	_bot_count_label.custom_minimum_size = Vector2(40, 0)
	_bot_count.value_changed.connect(func(val: float) -> void: _bot_count_label.text = str(int(val)))
	bot_row.add_child(_bot_count)
	bot_row.add_child(_bot_count_label)
	_grid_row(grid, "Bot-Anzahl", bot_row)
	_bot_diff = UITheme.option(["Einfach", "Normal", "Schwer"], 1, 420)
	_grid_row(grid, "Bot-Schwierigkeit", _bot_diff)

	v.add_child(UITheme.spacer(10))
	var buttons := UITheme.hbox(20)
	var start := UITheme.button("Match starten", 24, 300)
	start.pressed.connect(_start_match)
	buttons.add_child(start)
	var back := UITheme.button("Zurück", 24, 200)
	back.pressed.connect(func() -> void: _quick_panel.visible = false)
	buttons.add_child(back)
	v.add_child(buttons)
	_refresh_quick_options()


func _grid_row(grid: GridContainer, title: String, control: Control) -> void:
	var l := UITheme.label(title, 20, UITheme.TEXT)
	l.custom_minimum_size = Vector2(200, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	grid.add_child(control)


func _refresh_quick_options() -> void:
	var tdm := _mode_opt.selected == 0
	_team_opt.disabled = not tdm
	var max_bots := 11 if tdm else 7
	_bot_count.max_value = max_bots
	_bot_count.editable = _bots_check.button_pressed
	_bot_diff.disabled = not _bots_check.button_pressed


func _show_quick_play() -> void:
	_hide_panels()
	_quick_panel.visible = true


func _start_match() -> void:
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM if _mode_opt.selected == 0 else MatchConfig.MODE_FFA
	cfg.map_id = _map_ids[_map_opt.selected]
	cfg.local_team = Teams.Team.RED if _team_opt.selected == 0 else Teams.Team.BLUE
	cfg.local_class_id = _class_ids[_class_opt.selected]
	cfg.bots_enabled = _bots_check.button_pressed
	cfg.bot_count = int(_bot_count.value)
	cfg.bot_difficulty = _bot_diff.selected
	cfg.time_limit = 600.0
	GameDirector.start_match(cfg)


# ----------------------------------------------------------------------------- classes

func _build_classes() -> void:
	_classes_panel = UITheme.panel(Color(0.05, 0.06, 0.08, 0.95), 6)
	_classes_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_classes_panel.position = Vector2(600, 140)
	_classes_panel.custom_minimum_size = Vector2(760, 0)
	_classes_panel.visible = false
	add_child(_classes_panel)
	var v := UITheme.vbox(14)
	_classes_panel.add_child(v)
	v.add_child(UITheme.label("KLASSEN", 32, UITheme.ACCENT))
	for id in GameDirector.get_class_ids():
		var data := GameDirector.get_class_data(id)
		var card := UITheme.panel(UITheme.BG_LIGHT, 4)
		var cv := UITheme.vbox(4)
		card.add_child(cv)
		var title := UITheme.hbox(10)
		var swatch := ColorRect.new()
		swatch.color = data.icon_color
		swatch.custom_minimum_size = Vector2(8, 28)
		title.add_child(swatch)
		title.add_child(UITheme.label(data.display_name, 24, UITheme.TEXT))
		cv.add_child(title)
		cv.add_child(UITheme.label("Primär: %s   •   Sekundär: %s   •   Granaten: %d" % [data.primary.display_name, data.secondary.display_name, data.grenades], 16, UITheme.ACCENT_DIM))
		var desc := UITheme.label(data.description, 16, UITheme.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(700, 0)
		cv.add_child(desc)
		var stats := UITheme.label("Schaden %d–%d  •  %d Schuss/min  •  Magazin %d  •  Nachladen %.1fs" % [int(data.primary.min_damage), int(data.primary.damage), int(data.primary.rpm), data.primary.magazine_size, data.primary.reload_time if not data.primary.reload_single_shells else data.primary.shell_reload_time * data.primary.magazine_size], 14, UITheme.TEXT_DIM)
		cv.add_child(stats)
		v.add_child(card)
	var back := UITheme.button("Zurück", 22, 200)
	back.pressed.connect(func() -> void: _classes_panel.visible = false)
	v.add_child(back)


func _show_classes() -> void:
	_hide_panels()
	_classes_panel.visible = true


func _show_settings() -> void:
	_hide_panels()
	_settings.open()
