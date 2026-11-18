class_name LobbyPanel
extends PanelContainer
## Online lobby: create or join a game, see the players, choose team/class and
## (host only) the match settings. Talks exclusively to NetworkManager.

signal closed

var _connect_box: VBoxContainer
var _lobby_box: VBoxContainer
var _status: Label
var _port_host: LineEdit
var _address: LineEdit
var _port_join: LineEdit
var _address_hint: Label
var _player_list: VBoxContainer
var _team_opt: OptionButton
var _class_picker: PreviewPicker
var _mode_opt: OptionButton
var _map_picker: PreviewPicker
var _bots_check: CheckBox
var _bot_count: HSlider
var _bot_count_label: Label
var _bot_diff: OptionButton
var _start_btn: Button
var _info_label: Label
var _updating: bool = false


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.06, 0.08, 0.95), 6))
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2(560, 20)
	custom_minimum_size = Vector2(860, 0)
	var root := UITheme.vbox(10)
	add_child(root)
	root.add_child(UITheme.label("ONLINE", 32, UITheme.ACCENT))
	_status = UITheme.label("", 16, UITheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(760, 0)
	root.add_child(_status)
	_build_connect(root)
	_build_lobby(root)
	NetworkManager.lobby_updated.connect(_refresh)
	NetworkManager.joined_lobby.connect(_refresh)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.disconnected.connect(_on_disconnected)
	_refresh()


# ----------------------------------------------------------------------------- build

func _build_connect(root: VBoxContainer) -> void:
	_connect_box = UITheme.vbox(12)
	root.add_child(_connect_box)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	_connect_box.add_child(grid)

	grid.add_child(_row_label("Lobby erstellen"))
	var host_row := UITheme.hbox(10)
	host_row.add_child(UITheme.label("Port", 18, UITheme.TEXT_DIM))
	_port_host = _line(str(GameSettings.last_port), 100)
	host_row.add_child(_port_host)
	grid.add_child(host_row)
	var host_btn := UITheme.button("Hosten", 20, 200)
	host_btn.pressed.connect(_on_host_pressed)
	grid.add_child(host_btn)

	grid.add_child(_row_label("Beitreten"))
	var join_row := UITheme.hbox(10)
	_address = _line(GameSettings.last_address, 240)
	join_row.add_child(_address)
	join_row.add_child(UITheme.label("Port", 18, UITheme.TEXT_DIM))
	_port_join = _line(str(GameSettings.last_port), 100)
	join_row.add_child(_port_join)
	grid.add_child(join_row)
	var join_btn := UITheme.button("Beitreten", 20, 200)
	join_btn.pressed.connect(_on_join_pressed)
	grid.add_child(join_btn)

	var hint := UITheme.label("Mitspieler im selben Netzwerk geben die IP-Adresse des Hosts ein. Über das Internet muss der Host den UDP-Port (Standard 7777) am Router freigeben.", 14, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(760, 0)
	_connect_box.add_child(hint)
	var back := UITheme.button("Zurück", 22, 200)
	back.pressed.connect(func() -> void: closed.emit())
	_connect_box.add_child(back)


func _build_lobby(root: VBoxContainer) -> void:
	_lobby_box = UITheme.vbox(10)
	root.add_child(_lobby_box)
	_address_hint = UITheme.label("", 16, UITheme.ACCENT)
	_lobby_box.add_child(_address_hint)
	_lobby_box.add_child(UITheme.label("SPIELER", 20, UITheme.TEXT))
	_player_list = UITheme.vbox(4)
	_lobby_box.add_child(_player_list)
	_lobby_box.add_child(UITheme.spacer(6))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	_lobby_box.add_child(grid)

	_team_opt = UITheme.option(["Rot", "Blau"], 0, 360)
	_team_opt.item_selected.connect(func(_i: int) -> void: _on_loadout_changed())
	_grid_row(grid, "Dein Team", _team_opt)

	_mode_opt = UITheme.option(["Team Deathmatch (bis 12, 50 Kills)", "Free for All (bis 8, 25 Kills)"], 0, 360)
	_mode_opt.item_selected.connect(func(_i: int) -> void: _on_settings_changed())
	_grid_row(grid, "Spielmodus", _mode_opt)
	_bots_check = CheckBox.new()
	_bots_check.text = "Freie Plätze mit Bots füllen"
	_bots_check.button_pressed = true
	_bots_check.add_theme_font_size_override("font_size", 18)
	_bots_check.toggled.connect(func(_on: bool) -> void: _on_settings_changed())
	_grid_row(grid, "Bots", _bots_check)
	var bot_row := UITheme.hbox(12)
	_bot_count = UITheme.hslider(0, 11, 1, 6, 280)
	_bot_count_label = UITheme.label("6", 18)
	_bot_count_label.custom_minimum_size = Vector2(40, 0)
	_bot_count.value_changed.connect(func(val: float) -> void:
		_bot_count_label.text = str(int(val))
		_on_settings_changed())
	bot_row.add_child(_bot_count)
	bot_row.add_child(_bot_count_label)
	_grid_row(grid, "Bot-Anzahl (max.)", bot_row)
	_bot_diff = UITheme.option(["Einfach", "Normal", "Schwer"], 1, 360)
	_bot_diff.item_selected.connect(func(_i: int) -> void: _on_settings_changed())
	_grid_row(grid, "Bot-Schwierigkeit", _bot_diff)

	_lobby_box.add_child(UITheme.label("Map (Host wählt)", 18, UITheme.TEXT))
	_map_picker = PreviewPicker.new()
	_map_picker.setup(GameDirector.map_picker_items(), Vector2(176, 99), 17)
	_map_picker.selected.connect(func(_id: String) -> void: _on_settings_changed())
	_lobby_box.add_child(_map_picker)
	_lobby_box.add_child(UITheme.label("Deine Klasse", 18, UITheme.TEXT))
	_class_picker = PreviewPicker.new()
	_class_picker.setup(GameDirector.class_picker_items(), Vector2(150, 84), 17)
	_class_picker.selected.connect(func(_id: String) -> void: _on_loadout_changed())
	_lobby_box.add_child(_class_picker)
	_info_label = UITheme.label("", 16, UITheme.TEXT_DIM)
	_lobby_box.add_child(_info_label)
	var buttons := UITheme.hbox(20)
	_start_btn = UITheme.button("Match starten", 24, 300)
	_start_btn.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_btn)
	var leave := UITheme.button("Lobby verlassen", 22, 260)
	leave.pressed.connect(_on_leave_pressed)
	buttons.add_child(leave)
	_lobby_box.add_child(buttons)


func _row_label(text: String) -> Label:
	var l := UITheme.label(text, 20, UITheme.TEXT)
	l.custom_minimum_size = Vector2(180, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _grid_row(grid: GridContainer, title: String, control: Control) -> void:
	grid.add_child(_row_label(title))
	grid.add_child(control)


func _line(text: String, width: float) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(width, 40)
	e.add_theme_font_size_override("font_size", 20)
	return e


# ----------------------------------------------------------------------------- state

func open() -> void:
	visible = true
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var online := NetworkManager.is_online()
	var in_lobby := online and not NetworkManager.peers.is_empty()
	_connect_box.visible = not in_lobby and not (online and NetworkManager.is_client())
	_lobby_box.visible = in_lobby
	if NetworkManager.pending_message != "" and not online:
		_status.text = NetworkManager.pending_message
		NetworkManager.pending_message = ""
	elif online and not in_lobby:
		_status.text = "Verbinde …"
	if not in_lobby:
		return
	_updating = true
	var cfg := NetworkManager.lobby_config
	var is_host := NetworkManager.is_host()
	_status.text = "Du bist Host." if is_host else "Verbunden mit %s. Der Host startet das Match." % GameSettings.last_address
	if is_host:
		var addrs: Array[String] = []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
				addrs.append(a)
		_address_hint.text = "Mitspieler verbinden sich mit: %s  (Port %d)" % [", ".join(addrs) if not addrs.is_empty() else "deine IP-Adresse", GameSettings.last_port]
	else:
		_address_hint.text = ""
	# player list
	for c in _player_list.get_children():
		c.queue_free()
	var ids := NetworkManager.peers.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = NetworkManager.peers[id]
		var tdm := cfg.mode_id == MatchConfig.MODE_TDM
		var team_text := "  [%s]" % Teams.name_of(int(info["team"])) if tdm and int(info["team"]) != Teams.Team.NONE else ""
		var text := "%s%s  –  %s" % [info["name"], team_text, GameDirector.get_class_data(String(info["class_id"])).display_name]
		if int(id) == 1:
			text += "  (Host)"
		if int(id) == NetworkManager.local_peer_id():
			text += "  ◀ du"
		var col := Teams.color_of(int(info["team"])) if tdm else UITheme.TEXT
		_player_list.add_child(UITheme.label(text, 18, col))
	# own loadout
	var mine: Dictionary = NetworkManager.peers.get(NetworkManager.local_peer_id(), NetworkManager.local_info())
	_team_opt.selected = 1 if int(mine.get("team", 1)) == Teams.Team.BLUE else 0
	_class_picker.set_selected(String(mine.get("class_id", "assault")))
	_team_opt.disabled = cfg.mode_id != MatchConfig.MODE_TDM
	# match settings (editable by the host only)
	_mode_opt.selected = 0 if cfg.mode_id == MatchConfig.MODE_TDM else 1
	_map_picker.set_selected(cfg.map_id)
	_map_picker.set_disabled(not is_host)
	_bots_check.button_pressed = cfg.bots_enabled
	_bot_count.max_value = cfg.max_participants() - 1
	_bot_count.value = cfg.bot_count
	_bot_count_label.text = str(int(_bot_count.value))
	_bot_diff.selected = cfg.bot_difficulty
	for c in [_mode_opt, _bots_check, _bot_count, _bot_diff]:
		if c is OptionButton:
			(c as OptionButton).disabled = not is_host
		elif c is CheckBox:
			(c as CheckBox).disabled = not is_host
		elif c is HSlider:
			(c as HSlider).editable = is_host and cfg.bots_enabled
	_bot_diff.disabled = not is_host or not cfg.bots_enabled
	_start_btn.visible = is_host
	var humans := NetworkManager.human_count()
	var bots := 0
	if cfg.bots_enabled:
		bots = clampi(cfg.bot_count, 0, maxi(0, cfg.max_participants() - humans))
	_info_label.text = "%d Spieler + %d Bots, maximal %d Teilnehmer." % [humans, bots, cfg.max_participants()]
	_updating = false


func _on_connection_failed(reason: String) -> void:
	_status.text = reason
	_refresh()


func _on_disconnected(reason: String) -> void:
	_status.text = reason
	_refresh()


# ----------------------------------------------------------------------------- actions

func _on_host_pressed() -> void:
	var port := int(_port_host.text)
	if port < 1024 or port > 65535:
		_status.text = "Ungültiger Port (1024–65535)."
		return
	GameSettings.last_port = port
	GameSettings.save()
	var err := NetworkManager.host(port)
	if err != OK:
		_status.text = "Lobby konnte nicht erstellt werden (Port %d belegt?)." % port
		return
	_on_loadout_changed()
	_refresh()


func _on_join_pressed() -> void:
	var port := int(_port_join.text)
	var address := _address.text.strip_edges()
	if address == "" or port < 1 or port > 65535:
		_status.text = "Bitte Adresse und gültigen Port eingeben."
		return
	GameSettings.last_address = address
	GameSettings.last_port = port
	GameSettings.save()
	var err := NetworkManager.join(address, port)
	if err != OK:
		_status.text = "Verbindung konnte nicht gestartet werden."
		return
	_status.text = "Verbinde mit %s:%d …" % [address, port]
	_refresh()


func _on_loadout_changed() -> void:
	if _updating:
		return
	var team := Teams.Team.RED if _team_opt.selected == 0 else Teams.Team.BLUE
	NetworkManager.set_local_loadout(team, _class_picker.selected_id)
	GameSettings.save()


func _on_settings_changed() -> void:
	if _updating or not NetworkManager.is_host():
		return
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM if _mode_opt.selected == 0 else MatchConfig.MODE_FFA
	cfg.map_id = _map_picker.selected_id
	cfg.bots_enabled = _bots_check.button_pressed
	cfg.bot_count = int(_bot_count.value)
	cfg.bot_difficulty = _bot_diff.selected
	cfg.time_limit = 600.0
	NetworkManager.host_set_config(cfg)


func _on_start_pressed() -> void:
	if not NetworkManager.is_host():
		return
	_on_settings_changed()
	NetworkManager.host_start_match(NetworkManager.lobby_config, true)


func _on_leave_pressed() -> void:
	NetworkManager.leave()
	_status.text = ""
	closed.emit()
