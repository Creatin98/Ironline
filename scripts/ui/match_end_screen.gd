class_name MatchEndScreen
extends Control
## Shown when the match is over: result, final scoreboard, class choice, buttons and the vote for the next map.
##
## The map vote follows one fixed sequence on one clock (NetworkManager.vote_time, 15 s):
##   RESULTS (first 10 s)  scoreboard with the three map cards small at the bottom; the vote is already open.
##   FINAL   (last 5 s)    the scoreboard fades away and shrinks, the cards glide into the middle of the
##                         screen, grow and move apart: the final vote with a big countdown.
##   OUTCOME (after it)    the two other maps vanish, the winner moves to the middle and fills the screen
##                         (the same picture the loading screen shows) -> loading screen -> next round.
## Online the host owns the clock and the result (NetworkManager); offline the screen runs the same
## sequence by itself. Without map voting the scoreboard simply stays until a button is pressed.

signal next_round_requested
signal lobby_requested
signal leave_requested
signal map_chosen(map_id: String)
signal class_selected(class_id: String)

enum Phase { NONE, RESULTS, FINAL, OUTCOME }

const FINAL_VOTE_TIME := 5.0
## The closing animation is written for this length and scaled to NetworkManager.vote_outcome_time.
const OUTCOME_BASE_TIME := 2.8

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

var _content: VBoxContainer
var _dim: ColorRect
var _stage: Control
var _stage_title: Label
var _stage_count: Label
var _stage_bar_bg: ColorRect
var _stage_bar: ColorRect
var _stage_hint: Label
var _stage_leave: Button
var _flash: ColorRect
var _cards: Dictionary = {} # map id -> VoteCard
var _vote_maps: Array = []
var _phase: int = Phase.NONE
var _vote_time_left: float = -1.0
var _vote_duration: float = 0.0
var _my_vote: String = ""
var _online_vote: bool = false
var _last_tally: Dictionary = {}
var _last_second: int = -1
var _winner: String = ""
var _intro_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.6)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_content = UITheme.vbox(8)
	_content.custom_minimum_size = Vector2(900, 0)
	center.add_child(_content)
	var v := _content
	result_label = UITheme.label("SIEG", 54, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(result_label)
	detail_label = UITheme.label("", 22, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(detail_label)
	scoreboard = Scoreboard.new()
	scoreboard.hold_to_show = false
	scoreboard.custom_minimum_size = Vector2(860, 300)
	v.add_child(scoreboard)

	# next map: vote (online / offline) - small cards while the scoreboard is shown
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
	_build_stage()
	NetworkManager.vote_opened.connect(_on_vote_opened)
	NetworkManager.vote_tally_changed.connect(_on_vote_tally)
	NetworkManager.vote_closed.connect(_on_vote_closed)
	resized.connect(_on_resized)


## Free layer above the scoreboard: the big vote cards, the countdown and the flash of the reveal.
func _build_stage() -> void:
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.visible = false
	add_child(_stage)
	_stage_title = UITheme.label("NÄCHSTE KARTE WÄHLEN", 54, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_stage_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_title.modulate.a = 0.0
	_stage.add_child(_stage_title)
	_stage_count = UITheme.label("", 120, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_stage_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_count.modulate.a = 0.0
	_stage.add_child(_stage_count)
	_stage_bar_bg = ColorRect.new()
	_stage_bar_bg.color = Color(1, 1, 1, 0.12)
	_stage_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_bar_bg.modulate.a = 0.0
	_stage.add_child(_stage_bar_bg)
	_stage_bar = ColorRect.new()
	_stage_bar.color = UITheme.ACCENT
	_stage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_bar_bg.add_child(_stage_bar)
	_stage_hint = UITheme.label("Klicke auf eine Karte, um abzustimmen – die meisten Stimmen entscheiden", 22, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_stage_hint.modulate.a = 0.0
	_stage.add_child(_stage_hint)
	_stage_leave = UITheme.button("Hauptmenü", 18, 180)
	_stage_leave.pressed.connect(func() -> void: leave_requested.emit())
	_stage_leave.modulate.a = 0.0
	_stage.add_child(_stage_leave)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_flash)


func _process(delta: float) -> void:
	if _phase == Phase.OUTCOME or _vote_time_left < 0.0:
		return
	_vote_time_left = maxf(0.0, _vote_time_left - delta)
	var final_time := minf(FINAL_VOTE_TIME, _vote_duration * 0.34)
	if _phase == Phase.RESULTS:
		vote_title.text = "Nächste Karte – Abstimmung (%d)" % int(ceil(_vote_time_left))
		if visible and _vote_time_left <= final_time:
			_enter_final()
	elif _phase == Phase.FINAL:
		_update_final(final_time)
	if _vote_time_left <= 0.0 and not _online_vote and _phase != Phase.NONE:
		_finish_offline_vote()


# ----------------------------------------------------------------------------- vote (state)

func _start_vote_clock(duration: float) -> void:
	_vote_duration = maxf(duration, 0.1)
	_vote_time_left = _vote_duration
	_phase = Phase.RESULTS
	_last_second = -1


func _build_vote_cards(maps: Array) -> void:
	_vote_maps = maps.duplicate()
	var items: Array = []
	for m in maps:
		items.append({"id": m, "title": GameDirector.get_map_info(m)["name"], "texture": GameDirector.get_map_preview(m)})
	vote_picker.selected_id = ""
	vote_picker.disabled = false
	vote_picker.modulate = Color.WHITE
	vote_picker.setup(items, Vector2(190, 107), 18)


func _on_map_picked(map_id: String) -> void:
	_vote_for(map_id)


func _on_card_pressed(map_id: String) -> void:
	AudioManager.play_ui("ui_click")
	_vote_for(map_id)


func _vote_for(map_id: String) -> void:
	if _phase == Phase.NONE or _phase == Phase.OUTCOME or not _vote_maps.has(map_id):
		return
	_my_vote = map_id
	if _online_vote:
		NetworkManager.cast_vote(map_id)
	else:
		_last_tally = {map_id: 1} # offline: only our own vote counts
	_refresh_vote_ui()


## Badges (vote counts), the own pick and dimming on the small and on the big cards.
func _refresh_vote_ui() -> void:
	for id in _vote_maps:
		var n := int(_last_tally.get(id, 0))
		var text := ""
		if n > 0:
			text = "%d Stimme%s" % [n, "" if n == 1 else "n"]
		elif not _online_vote and id == MatchManager.config.map_id:
			text = "aktuell"
		vote_picker.set_badge(id, text)
		if _cards.has(id):
			var card: VoteCard = _cards[id]
			card.set_badge(text)
			card.set_selected(id == _my_vote)
			card.set_dimmed(_my_vote != "" and id != _my_vote)
	if _my_vote != "":
		vote_picker.set_selected(_my_vote)


func _on_vote_opened(maps: Array, duration: float) -> void:
	_online_vote = true
	wait_label.visible = false
	next_btn.visible = false
	_my_vote = ""
	_last_tally = {}
	_start_vote_clock(duration)
	_build_vote_cards(maps)
	vote_box.visible = true


func _on_vote_tally(tally: Dictionary) -> void:
	_last_tally = tally
	_refresh_vote_ui()


## Online: the host closed the vote and tells us the winner.
func _on_vote_closed(winner_map: String) -> void:
	if _online_vote:
		_start_outcome(winner_map)


## Offline: nobody else votes - our pick wins, without a pick a random map of the rotation.
func _finish_offline_vote() -> void:
	if _vote_maps.is_empty():
		_vote_time_left = -1.0
		return
	var winner := _my_vote
	if winner == "" or not _vote_maps.has(winner):
		winner = String(_vote_maps[randi() % _vote_maps.size()])
	_start_outcome(winner)


# ----------------------------------------------------------------------------- final vote (centre of the screen)

func _final_rects() -> Array[Rect2]:
	var n := maxi(1, _vote_maps.size())
	var w := clampf(size.x * 0.27, 240.0, 620.0)
	var gap := clampf(size.x * 0.045, 20.0, 100.0)
	var h := w / VoteCard.ASPECT
	var total := n * w + (n - 1) * gap
	var x0 := (size.x - total) * 0.5
	var y := size.y * 0.57 - h * 0.5
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(Vector2(x0 + i * (w + gap), y), Vector2(w, h)))
	return out


func _layout_stage() -> void:
	var rects := _final_rects()
	var s := size
	var top := rects[0].position.y
	var h := rects[0].size.y
	_stage_title.add_theme_font_size_override("font_size", clampi(int(s.y * 0.05), 26, 64))
	_stage_title.position = Vector2(0.0, top - s.y * 0.285)
	_stage_title.size = Vector2(s.x, s.y * 0.07)
	_stage_count.add_theme_font_size_override("font_size", clampi(int(s.y * 0.115), 48, 150))
	_stage_count.position = Vector2(0.0, top - s.y * 0.2)
	_stage_count.size = Vector2(s.x, s.y * 0.17)
	_stage_count.pivot_offset = _stage_count.size * 0.5
	var bar_w := s.x * 0.3
	_stage_bar_bg.position = Vector2((s.x - bar_w) * 0.5, top + h + s.y * 0.035)
	_stage_bar_bg.size = Vector2(bar_w, 6.0)
	_stage_hint.position = Vector2(0.0, _stage_bar_bg.position.y + 22.0)
	_stage_hint.size = Vector2(s.x, 36.0)
	_stage_leave.position = Vector2(24.0, s.y - 24.0 - _stage_leave.size.y)


func _make_card(id: String) -> VoteCard:
	var card := VoteCard.new()
	_stage.add_child(card)
	card.setup(id, String(GameDirector.get_map_info(id)["name"]), GameDirector.get_map_preview(id))
	card.pressed.connect(_on_card_pressed)
	return card


## Scoreboard gives way, the small cards turn into big ones in the middle of the screen.
func _enter_final(instant: bool = false) -> void:
	if _phase != Phase.RESULTS or _vote_maps.is_empty():
		return
	_phase = Phase.FINAL
	_last_second = -1
	_stage.visible = true
	_layout_stage()
	var targets := _final_rects()
	var animate := visible and not instant
	var tw := create_tween().set_parallel(true)
	_intro_tween = tw
	for i in _vote_maps.size():
		var id: String = _vote_maps[i]
		var card := _make_card(id)
		_cards[id] = card
		var target: Rect2 = targets[i]
		if animate:
			# start exactly over the small card, then glide to the middle, grow and move apart
			var rect: Rect2 = vote_picker.card_global_rect(id)
			card.position = rect.position - _stage.global_position
			card.size = Vector2(rect.size.x, rect.size.x / VoteCard.ASPECT)
			card.modulate.a = 0.0
			tw.tween_property(card, "modulate:a", 1.0, 0.15)
			tw.tween_property(card, "position", target.position, 0.95).set_delay(0.07 * i).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "size", target.size, 0.95).set_delay(0.07 * i).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		else:
			card.position = target.position
			card.size = target.size
	_stage.move_child(_flash, -1)
	_refresh_vote_ui()
	vote_picker.disabled = true
	vote_picker.modulate.a = 0.0 # keeps its space, so the scoreboard does not jump while it fades
	if animate:
		AudioManager.play_ui("ui_back", -4.0)
		_content.pivot_offset = _content.size * 0.5
		tw.tween_property(_content, "scale", Vector2(0.86, 0.86), 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(_content, "position:y", _content.position.y - 40.0, 0.75)
		tw.tween_property(_content, "modulate:a", 0.0, 0.6)
		tw.tween_property(_dim, "color:a", 0.84, 0.7)
		for l in [_stage_title, _stage_count, _stage_bar_bg, _stage_hint, _stage_leave]:
			tw.tween_property(l, "modulate:a", 1.0, 0.5).set_delay(0.35)
		tw.chain().tween_callback(_hide_content)
	else:
		_hide_content()
		_dim.color.a = 0.84
		for l in [_stage_title, _stage_count, _stage_bar_bg, _stage_hint, _stage_leave]:
			l.modulate.a = 1.0


func _hide_content() -> void:
	_content.visible = false


func _update_final(final_time: float) -> void:
	var secs := int(ceil(_vote_time_left))
	_stage_count.text = str(secs)
	_stage_bar.size = Vector2(_stage_bar_bg.size.x * clampf(_vote_time_left / maxf(final_time, 0.01), 0.0, 1.0), _stage_bar_bg.size.y)
	if secs != _last_second:
		_last_second = secs
		if secs >= 1 and secs <= 3:
			AudioManager.play_ui("countdown_tick", -2.0)
		_stage_count.scale = Vector2(1.3, 1.3)
		create_tween().tween_property(_stage_count, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_resized() -> void:
	if _phase != Phase.FINAL or _stage == null:
		return
	_layout_stage()
	if _intro_tween != null and _intro_tween.is_valid() and _intro_tween.is_running():
		return
	var targets := _final_rects()
	for i in _vote_maps.size():
		var card: VoteCard = _cards.get(_vote_maps[i])
		if card != null:
			card.position = targets[i].position
			card.size = targets[i].size


# ----------------------------------------------------------------------------- outcome animation

## The losing maps vanish, the winner moves to the middle, flashes and fills the screen.
func _start_outcome(winner_map: String) -> void:
	if _phase == Phase.OUTCOME or _phase == Phase.NONE or _vote_maps.is_empty():
		return
	if _phase == Phase.RESULTS:
		_enter_final(true)
	_phase = Phase.OUTCOME
	_vote_time_left = -1.0
	_winner = winner_map if _cards.has(winner_map) else String(_vote_maps[0])
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	# settle the layout of an interrupted intro
	_layout_stage()
	var targets := _final_rects()
	for i in _vote_maps.size():
		var c: VoteCard = _cards[_vote_maps[i]]
		c.position = targets[i].position
		c.size = targets[i].size
		c.modulate.a = 1.0
		c.disabled = true
	_hide_content()
	_dim.color.a = 0.84
	_stage_leave.visible = false
	var k := maxf(NetworkManager.vote_outcome_time, 0.3) / OUTCOME_BASE_TIME
	var win_card: VoteCard = _cards[_winner]
	_stage.move_child(win_card, -1)
	_stage.move_child(_flash, -1)
	var tw := create_tween().set_parallel(true)
	_intro_tween = tw
	for l in [_stage_count, _stage_bar_bg, _stage_hint]:
		tw.tween_property(l, "modulate:a", 0.0, 0.25 * k)
	# the other maps shrink away to the sides
	for id in _vote_maps:
		if id == _winner:
			continue
		var card: VoteCard = _cards[id]
		card.pivot_offset = card.size * 0.5
		var dir := signf(card.position.x + card.size.x * 0.5 - size.x * 0.5)
		tw.tween_property(card, "scale", Vector2(0.55, 0.55), 0.7 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(card, "modulate:a", 0.0, 0.55 * k).set_delay(0.12 * k)
		tw.tween_property(card, "position", card.position + Vector2(dir * size.x * 0.1, size.y * 0.08), 0.7 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# the winner moves to the middle and grows
	var grow := minf(1.4, size.y * 0.6 / win_card.size.y)
	var big := win_card.size * grow
	var center_pos := (size - big) * 0.5 + Vector2(0.0, size.y * 0.02)
	tw.tween_property(win_card, "position", center_pos, 0.8 * k).set_delay(0.25 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(win_card, "size", big, 0.8 * k).set_delay(0.25 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_reveal_winner).set_delay(0.95 * k)
	tw.tween_callback(_expand_winner).set_delay(1.5 * k)
	tw.tween_callback(_outcome_done).set_delay(OUTCOME_BASE_TIME * k)


func _reveal_winner() -> void:
	var k := maxf(NetworkManager.vote_outcome_time, 0.3) / OUTCOME_BASE_TIME
	_stage_title.text = "KARTE GEWÄHLT"
	_stage_title.pivot_offset = _stage_title.size * 0.5
	_stage_title.scale = Vector2(1.25, 1.25)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_stage_title, "scale", Vector2.ONE, 0.35 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flash, "color:a", 0.38, 0.06 * k)
	tw.chain().tween_property(_flash, "color:a", 0.0, 0.4 * k)
	(_cards[_winner] as VoteCard).play_shine(0.6 * k)
	AudioManager.play_ui("countdown_go", -4.0)


## The winner's picture grows to the whole screen: the loading screen shows the same picture next.
func _expand_winner() -> void:
	var k := maxf(NetworkManager.vote_outcome_time, 0.3) / OUTCOME_BASE_TIME
	var card: VoteCard = _cards[_winner]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position", Vector2.ZERO, 0.95 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "size", size, 0.95 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "expand", 1.0, 0.95 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_stage_title, "modulate:a", 0.0, 0.4 * k)
	AudioManager.play_ui("round_start", -8.0)


func _outcome_done() -> void:
	if not NetworkManager.is_online():
		map_chosen.emit(_winner) # offline: the screen starts the round itself; online the host does it right now


# ----------------------------------------------------------------------------- results

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
		# offline: the same vote sequence, our own pick decides
		_online_vote = false
		_my_vote = ""
		_last_tally = {}
		_start_vote_clock(NetworkManager.vote_time)
		_build_vote_cards(GameDirector.ROTATION_MAPS)
		_refresh_vote_ui()
		next_btn.visible = false
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
		detail_label.text += "   |   Du: %d Kills, %d Tode, %d Assists, %d Punkte" % [me.kills, me.deaths, me.assists, me.score]
