class_name MatchEndScreen
extends Control
## Shown when the match is over: result, final scoreboard, next map, class choice, buttons.
## Next map: online a timed vote (host counts, see NetworkManager), offline a direct pick.
## Map and class are chosen on picture cards (PreviewPicker).

signal next_round_requested
signal lobby_requested
signal leave_requested
signal map_chosen(map_id: String)
signal class_selected(class_id: String)

var result_label: Label
var detail_label: Label
var scoreboard: Scoreboard
var next_btn: Button
var lobby_btn: Button
var wait_label: Label
var vote_box: VBoxContainer
var vote_title: Label
var vote_picker: PreviewPicker
var class_picker: PreviewPicker

var _vote_time_left: float = -1.0
var _my_vote: String = ""
var _online_vote: bool = false
var _last_tally: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var v := UITheme.vbox(8)
	v.custom_minimum_size = Vector2(900, 0)
	center.add_child(v)
	result_label = UITheme.label("SIEG", 54, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(result_label)
	detail_label = UITheme.label("", 22, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(detail_label)
	scoreboard = Scoreboard.new()
	scoreboard.hold_to_show = false
	scoreboard.custom_minimum_size = Vector2(860, 300)
	v.add_child(scoreboard)

	# next map: vote (online) / pick (offline)
	vote_box = UITheme.vbox(6)
	vote_box.visible = false
	vote_title = UITheme.label("", 22, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	vote_box.add_child(vote_title)
	vote_picker = PreviewPicker.new()
	vote_picker.alignment = BoxContainer.ALIGNMENT_CENTER
	vote_picker.selected.connect(_on_map_picked)
	vote_box.add_child(vote_picker)
	v.add_child(vote_box)

	# bottom row: class choice (left), buttons (right)
	var bottom := UITheme.hbox(40)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	var class_box := UITheme.vbox(4)
	class_box.add_child(UITheme.label("Klasse für die nächste Runde", 16, UITheme.TEXT_DIM))
	class_picker = PreviewPicker.new()
	class_picker.selected_id = GameSettings.preferred_class_id
	class_picker.setup(GameDirector.class_picker_items(), Vector2(120, 68), 14)
	class_picker.selected.connect(func(id: String) -> void: class_selected.emit(id))
	class_box.add_child(class_picker)
	bottom.add_child(class_box)
	var buttons := UITheme.vbox(6)
	next_btn = UITheme.button("Nächste Runde", 20, 240)
	next_btn.pressed.connect(func() -> void: next_round_requested.emit())
	buttons.add_child(next_btn)
	lobby_btn = UITheme.button("Zur Lobby", 20, 240)
	lobby_btn.pressed.connect(func() -> void: lobby_requested.emit())
	lobby_btn.visible = false
	buttons.add_child(lobby_btn)
	var leave_btn := UITheme.button("Hauptmenü", 20, 240)
	leave_btn.pressed.connect(func() -> void: leave_requested.emit())
	buttons.add_child(leave_btn)
	wait_label = UITheme.label("Der Host entscheidet über die nächste Runde …", 16, UITheme.TEXT_DIM)
	wait_label.visible = false
	buttons.add_child(wait_label)
	bottom.add_child(buttons)
	NetworkManager.vote_opened.connect(_on_vote_opened)
	NetworkManager.vote_tally_changed.connect(_on_vote_tally)
	NetworkManager.vote_closed.connect(_on_vote_closed)


func _process(delta: float) -> void:
	if _vote_time_left < 0.0:
		return
	_vote_time_left = maxf(0.0, _vote_time_left - delta)
	vote_title.text = "Nächste Karte – Abstimmung (%d)" % int(ceil(_vote_time_left))


func _build_vote_cards(maps: Array) -> void:
	var items: Array = []
	for m in maps:
		items.append({"id": m, "title": GameDirector.get_map_info(m)["name"], "texture": GameDirector.get_map_preview(m)})
	vote_picker.selected_id = ""
	vote_picker.setup(items, Vector2(190, 107), 18)


func _on_map_picked(map_id: String) -> void:
	if _online_vote:
		_my_vote = map_id
		NetworkManager.cast_vote(map_id)
		_on_vote_tally(_last_tally)
	else:
		map_chosen.emit(map_id)


func _on_vote_opened(maps: Array, duration: float) -> void:
	_online_vote = true
	wait_label.visible = false
	_my_vote = ""
	_vote_time_left = duration
	next_btn.visible = false
	_build_vote_cards(maps)
	vote_box.visible = true


func _on_vote_tally(tally: Dictionary) -> void:
	_last_tally = tally
	for map_id in GameDirector.ROTATION_MAPS:
		var n := int(tally.get(map_id, 0))
		vote_picker.set_badge(map_id, "%d Stimme%s" % [n, "" if n == 1 else "n"] if n > 0 else "")
	if _my_vote != "":
		vote_picker.set_selected(_my_vote)


func _on_vote_closed() -> void:
	_vote_time_left = -1.0
	vote_title.text = "Karte gewählt – Match startet …"
	vote_picker.set_disabled(true)


## Online: only the host can start the next round / return to the lobby.
func configure_for_network() -> void:
	var online := NetworkManager.is_online()
	var host := NetworkManager.is_host()
	next_btn.visible = not online or host
	lobby_btn.visible = online and host
	wait_label.visible = online and not host and not _online_vote


func show_results() -> void:
	visible = true
	scoreboard.visible = true
	scoreboard.panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scoreboard.panel.position = Vector2(50, 0)
	scoreboard.rebuild()
	# the scoreboard panel is not layout-managed: reserve its height
	var rows := MatchManager.participants.size() + (2 if MatchManager.mode.uses_teams else 0)
	scoreboard.custom_minimum_size = Vector2(860, 130 + rows * 32)
	if not NetworkManager.is_online() and MatchManager.config.map_voting:
		# offline: pick the next map directly
		_online_vote = false
		vote_title.text = "Nächste Karte wählen"
		_build_vote_cards(GameDirector.ROTATION_MAPS)
		vote_picker.set_badge(MatchManager.config.map_id, "aktuell")
		vote_box.visible = true
	var me := MatchManager.get_local_participant()
	if MatchManager.is_draw():
		result_label.text = "UNENTSCHIEDEN"
		result_label.add_theme_color_override("font_color", UITheme.TEXT)
	elif MatchManager.local_player_won():
		result_label.text = "SIEG"
		result_label.add_theme_color_override("font_color", UITheme.ACCENT)
	else:
		result_label.text = "NIEDERLAGE"
		result_label.add_theme_color_override("font_color", UITheme.DANGER)
	if MatchManager.mode.uses_teams:
		var wt := int(MatchManager.winner["team"])
		detail_label.text = "%s gewinnt  •  Rot %d : %d Blau" % [Teams.name_of(wt) if wt != Teams.Team.NONE else "Niemand", MatchManager.team_scores[Teams.Team.RED], MatchManager.team_scores[Teams.Team.BLUE]]
	else:
		var wp := MatchManager.get_participant(int(MatchManager.winner["participant_id"]))
		detail_label.text = "%s gewinnt mit %d Kills" % [wp.display_name, wp.kills] if wp else "Kein Sieger"
	if me:
		detail_label.text += "   |   Du: %d Kills, %d Tode, %d Punkte" % [me.kills, me.deaths, me.score]
