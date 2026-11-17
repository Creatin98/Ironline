class_name MatchEndScreen
extends Control
## Shown when the match is over: result, final scoreboard, next round / menu.
## Map voting is added in phase 7 (the "next round" button restarts with the same config).

signal next_round_requested
signal lobby_requested
signal leave_requested

var result_label: Label
var detail_label: Label
var scoreboard: Scoreboard
var buttons: HBoxContainer
var next_btn: Button
var lobby_btn: Button
var wait_label: Label


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


## Online: only the host can start the next round / return to the lobby.
func configure_for_network() -> void:
	var online := NetworkManager.is_online()
	var host := NetworkManager.is_host()
	next_btn.visible = not online or host
	lobby_btn.visible = online and host
	wait_label.visible = online and not host


func show_results() -> void:
	visible = true
	scoreboard.visible = true
	scoreboard.panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scoreboard.panel.position = Vector2(20, 0)
	scoreboard.rebuild()
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
