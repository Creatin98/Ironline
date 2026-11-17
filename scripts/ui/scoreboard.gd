class_name Scoreboard
extends Control
## Tab-scoreboard: name, team, kills, deaths, score. Rebuilt on every show and
## whenever scores change while visible. Also embedded in the match end screen.

const COLUMNS := ["Spieler", "Team", "Kills", "Tode", "Assists", "K/D", "Punkte"]
const COLUMN_WIDTHS := [290, 80, 80, 80, 90, 80, 100]
## Side-by-side layout (match end): one table per team, the team is the heading, so no team column.
const TEAM_COLUMNS := ["Spieler", "Kills", "Tode", "Assists", "K/D", "Punkte"]
const TEAM_WIDTHS := [230, 66, 66, 82, 76, 88]

var panel: PanelContainer
var content: VBoxContainer
var title_label: Label
var hold_to_show: bool = true
## Two tables next to each other (winner left, loser right) instead of stacked: used on the results screen.
var side_by_side: bool = false


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


## Kills divided by deaths with two decimals (no deaths: the kills themselves, as if there was one death).
static func kd_text(kills: int, deaths: int) -> String:
	return "%.2f" % (float(kills) / float(maxi(deaths, 1)))


func rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c) # gone at once, so the panel's minimum size is right immediately
		c.queue_free()
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
	if MatchManager.mode.uses_teams and side_by_side:
		_build_side_by_side()
		return
	_add_header(content, COLUMNS, COLUMN_WIDTHS)
	_add_separator(content, 0.15)
	if MatchManager.mode.uses_teams:
		_add_rows(content, MatchManager.get_sorted_participants(Teams.Team.RED), true)
		_add_separator(content, 0.08)
		_add_rows(content, MatchManager.get_sorted_participants(Teams.Team.BLUE), true)
	else:
		_add_rows(content, MatchManager.get_sorted_participants(), true)


## Winner team on the left, the other one on the right (a draw: red left).
func _build_side_by_side() -> void:
	var left := Teams.Team.RED
	var right := Teams.Team.BLUE
	if not MatchManager.is_draw() and int(MatchManager.winner["team"]) == Teams.Team.BLUE:
		left = Teams.Team.BLUE
		right = Teams.Team.RED
	var row := UITheme.hbox(36)
	for team in [left, right]:
		var col := UITheme.vbox(6)
		var head := UITheme.hbox(10)
		var tcol := Teams.color_of(team)
		head.add_child(UITheme.label("TEAM %s" % Teams.name_of(team).to_upper(), 24, tcol))
		head.add_child(UITheme.label("%d" % MatchManager.team_scores[team], 24, UITheme.TEXT))
		if not MatchManager.is_draw() and int(MatchManager.winner["team"]) == team:
			head.add_child(UITheme.label("•  SIEGER", 18, UITheme.ACCENT))
		col.add_child(head)
		_add_header(col, TEAM_COLUMNS, TEAM_WIDTHS)
		_add_separator(col, 0.15)
		_add_rows(col, MatchManager.get_sorted_participants(team), false)
		row.add_child(col)
	content.add_child(row)


func _add_header(parent: Control, columns: Array, widths: Array) -> void:
	var header := UITheme.hbox(0)
	for i in columns.size():
		var l := UITheme.label(columns[i], 15, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(widths[i], 0)
		header.add_child(l)
	parent.add_child(header)


func _add_separator(parent: Control, alpha: float) -> void:
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, alpha)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)


func _add_rows(parent: Control, list: Array[Participant], with_team: bool) -> void:
	var widths: Array = COLUMN_WIDTHS if with_team else TEAM_WIDTHS
	for p in list:
		var row := UITheme.hbox(0)
		var is_me := p.id == MatchManager.local_participant_id
		var col := Teams.color_of(p.team) if MatchManager.mode.uses_teams else (UITheme.ACCENT if is_me else UITheme.TEXT)
		var prefix := "▶ " if is_me else ("[Bot] " if p.is_bot else "")
		var name_text := prefix + p.display_name + ("" if p.alive else "  †")
		var values: Array
		if with_team:
			values = [name_text, Teams.name_of(p.team) if MatchManager.mode.uses_teams else "-", str(p.kills), str(p.deaths), str(p.assists), kd_text(p.kills, p.deaths), str(p.score)]
		else:
			values = [name_text, str(p.kills), str(p.deaths), str(p.assists), kd_text(p.kills, p.deaths), str(p.score)]
		var colored := 2 if with_team else 1 # columns drawn in the team colour (name, team)
		for i in values.size():
			var l := UITheme.label(values[i], 18, col if i < colored else UITheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
			l.custom_minimum_size = Vector2(widths[i], 0)
			row.add_child(l)
		if is_me:
			var bg := UITheme.panel(Color(1, 1, 1, 0.06), 3)
			bg.add_child(row)
			parent.add_child(bg)
		else:
			parent.add_child(row)
