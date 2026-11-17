class_name Scoreboard
extends Control
## Tab-scoreboard: name, team, kills, deaths, score. Rebuilt on every show and
## whenever scores change while visible. Also embedded in the match end screen.

const COLUMNS := ["Spieler", "Team", "Kills", "Tode", "Punkte"]
const COLUMN_WIDTHS := [300, 90, 90, 90, 110]

var panel: PanelContainer
var content: VBoxContainer
var title_label: Label
var hold_to_show: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = UITheme.panel(Color(0.05, 0.06, 0.08, 0.92), 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 200)
	panel.position = Vector2(-380, -260)
	add_child(panel)
	content = UITheme.vbox(6)
	panel.add_child(content)
	visible = false
	GameEvents.scores_changed.connect(func() -> void:
		if visible:
			rebuild())


func _process(_delta: float) -> void:
	if not hold_to_show:
		return
	var want := Input.is_action_pressed("scoreboard") and MatchManager.state != MatchManager.State.ENDED
	if want and not visible:
		rebuild()
	visible = want


func rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	var header := UITheme.hbox(0)
	var mode_name := MatchManager.mode.display_name
	var map_name: String = GameDirector.get_map_info(MatchManager.config.map_id)["name"]
	title_label = UITheme.label("%s  •  %s" % [mode_name, map_name], 24, UITheme.ACCENT)
	content.add_child(title_label)
	if MatchManager.mode.uses_teams:
		var tl := UITheme.label("ROT %d   :   %d BLAU  (Ziel %d)" % [MatchManager.team_scores[Teams.Team.RED], MatchManager.team_scores[Teams.Team.BLUE], MatchManager.mode.kill_limit], 18, UITheme.TEXT_DIM)
		content.add_child(tl)
	else:
		var fl := UITheme.label("Ziel: %d Kills" % MatchManager.mode.kill_limit, 18, UITheme.TEXT_DIM)
		content.add_child(fl)
	content.add_child(UITheme.spacer(6))
	for i in COLUMNS.size():
		var l := UITheme.label(COLUMNS[i], 15, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
		header.add_child(l)
	content.add_child(header)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.15)
	sep.custom_minimum_size = Vector2(0, 1)
	content.add_child(sep)
	if MatchManager.mode.uses_teams:
		_add_rows(MatchManager.get_sorted_participants(Teams.Team.RED))
		var sep2 := ColorRect.new()
		sep2.color = Color(1, 1, 1, 0.08)
		sep2.custom_minimum_size = Vector2(0, 1)
		content.add_child(sep2)
		_add_rows(MatchManager.get_sorted_participants(Teams.Team.BLUE))
	else:
		_add_rows(MatchManager.get_sorted_participants())


func _add_rows(list: Array[Participant]) -> void:
	for p in list:
		var row := UITheme.hbox(0)
		var is_me := p.id == MatchManager.local_participant_id
		var col := Teams.color_of(p.team) if MatchManager.mode.uses_teams else (UITheme.ACCENT if is_me else UITheme.TEXT)
		var prefix := "▶ " if is_me else ("[Bot] " if p.is_bot else "")
		var name_text := prefix + p.display_name + ("" if p.alive else "  †")
		var values := [name_text, Teams.name_of(p.team) if MatchManager.mode.uses_teams else "-", str(p.kills), str(p.deaths), str(p.score)]
		for i in values.size():
			var l := UITheme.label(values[i], 18, col if i < 2 else UITheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
			l.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
			row.add_child(l)
		if is_me:
			var bg := UITheme.panel(Color(1, 1, 1, 0.06), 3)
			bg.add_child(row)
			content.add_child(bg)
		else:
			content.add_child(row)
