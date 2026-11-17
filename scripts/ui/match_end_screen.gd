class_name MatchEndScreen
extends Control
## Shown when the match is over: result, final scoreboard, next round / menu.
## Next map: online a timed vote (host counts, see NetworkManager), offline a direct pick.

signal next_round_requested
signal lobby_requested
signal leave_requested
signal map_chosen(map_id: String)

var result_label: Label
var detail_label: Label
var scoreboard: Scoreboard
var buttons: HBoxContainer
var next_btn: Button
var lobby_btn: Button
var wait_label: Label
var vote_box: VBoxContainer
var vote_title: Label
var vote_row: HBoxContainer
var _vote_buttons: Dictionary = {} # map id -> Button
var _vote_time_left: float = -1.0
var _my_vote: String = ""
var _online_vote: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	var v := UITheme.vbox(12)
	v.set_anchors_preset(Control.PRESET_CENTER_TOP)
	v.position = Vector2(-400, 80)
	v.custom_minimum_size = Vector2(800, 0)
	add_child(v)
	result_label = UITheme.label("SIEG", 64, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(result_label)
	detail_label = UITheme.label("", 24, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(detail_label)
	v.add_child(UITheme.spacer(10))
	scoreboard = Scoreboard.new()
	scoreboard.hold_to_show = false
	scoreboard.custom_minimum_size = Vector2(800, 460)
	v.add_child(scoreboard)
	buttons = UITheme.hbox(20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)
	next_btn = UITheme.button("Nächste Runde", 22, 260)
	next_btn.pressed.connect(func() -> void: next_round_requested.emit())
	buttons.add_child(next_btn)
	lobby_btn = UITheme.button("Zur Lobby", 22, 220)
	lobby_btn.pressed.connect(func() -> void: lobby_requested.emit())
	lobby_btn.visible = false
	buttons.add_child(lobby_btn)
	var leave_btn := UITheme.button("Hauptmenü", 22, 220)
	leave_btn.pressed.connect(func() -> void: leave_requested.emit())
	buttons.add_child(leave_btn)
	wait_label = UITheme.label("Der Host entscheidet über die nächste Runde …", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	wait_label.visible = false
	v.add_child(wait_label)
	vote_box = UITheme.vbox(8)
	vote_box.visible = false
	vote_title = UITheme.label("", 22, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	vote_box.add_child(vote_title)
	vote_row = UITheme.hbox(14)
	vote_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vote_box.add_child(vote_row)
	v.add_child(vote_box)
	NetworkManager.vote_opened.connect(_on_vote_opened)
	NetworkManager.vote_tally_changed.connect(_on_vote_tally)
	NetworkManager.vote_closed.connect(_on_vote_closed)


func _process(delta: float) -> void:
	if _vote_time_left < 0.0:
		return
	_vote_time_left = maxf(0.0, _vote_time_left - delta)
	vote_title.text = "Nächste Karte – Abstimmung (%d)" % int(ceil(_vote_time_left))


func _build_vote_buttons(maps: Array) -> void:
	for c in vote_row.get_children():
		c.queue_free()
	_vote_buttons.clear()
	for m in maps:
		var map_id: String = m
		var b := UITheme.button(String(GameDirector.get_map_info(map_id)["name"]), 22, 200)
		b.pressed.connect(func() -> void: _on_map_button(map_id))
		vote_row.add_child(b)
		_vote_buttons[map_id] = b


func _on_map_button(map_id: String) -> void:
	if _online_vote:
		_my_vote = map_id
		NetworkManager.cast_vote(map_id)
		_on_vote_tally(_last_tally)
	else:
		map_chosen.emit(map_id)


var _last_tally: Dictionary = {}


func _on_vote_opened(maps: Array, duration: float) -> void:
	_online_vote = true
	wait_label.visible = false
	_my_vote = ""
	_vote_time_left = duration
	next_btn.visible = false
	_build_vote_buttons(maps)
	vote_box.visible = true


func _on_vote_tally(tally: Dictionary) -> void:
	_last_tally = tally
	for map_id in _vote_buttons:
		var b: Button = _vote_buttons[map_id]
		var n := int(tally.get(map_id, 0))
		var label: String = GameDirector.get_map_info(map_id)["name"]
		b.text = "%s%s%s" % ["► " if map_id == _my_vote else "", label, "  (%d)" % n if n > 0 else ""]


func _on_vote_closed() -> void:
	_vote_time_left = -1.0
	vote_title.text = "Karte gewählt – Match startet …"


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
	scoreboard.panel.position = Vector2(20, 0)
	scoreboard.rebuild()
	if not NetworkManager.is_online() and MatchManager.config.map_voting:
		# offline: pick the next map directly
		_online_vote = false
		vote_title.text = "Nächste Karte wählen"
		_build_vote_buttons(GameDirector.ROTATION_MAPS)
		for m in _vote_buttons:
			if m == MatchManager.config.map_id:
				(_vote_buttons[m] as Button).text += "  (aktuell)"
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
