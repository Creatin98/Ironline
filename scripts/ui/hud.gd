class_name HUD
extends Control
## In-match HUD: crosshair, hitmarker, health, ammo, grenades, score, timer,
## killfeed, respawn/warmup overlays and damage feedback. Built in code so the
## layout scales with GameSettings.hud_scale.

const KILLFEED_LIFETIME := 6.0
const KILLFEED_MAX := 6
const WEAPON_LABELS := {
	"ak47": "AK-47", "mp5": "MP5", "shotgun": "Shotgun", "pistol": "Pistole",
	"grenade": "Granate", "world": "Umgebung",
}

var crosshair: Control
var health_bar_fill: ColorRect
var health_label: Label
var ammo_label: Label
var weapon_label: Label
var grenade_label: Label
var score_box: VBoxContainer
var timer_label: Label
var killfeed_box: VBoxContainer
var center_label: Label
var sub_label: Label
var score_popup: Label
var vignette: ColorRect
var damage_flash: ColorRect
var fps_label: Label
var hint_label: Label

var _player: Player
var _health_ratio: float = 1.0
var _hitmarker_time: float = 0.0
var _hitmarker_kill: bool = false
var _spread_display: float = 0.0
var _respawn_time_left: float = -1.0
var _popup_time: float = 0.0
var _killfeed_entries: Array = [] # [{node, time}]
var _warmup: bool = false
var _hud_scale_nodes: Array = []
var _hud_pivots: Dictionary = {} # Control -> pivot fraction (0..1, 0..1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameEvents.local_player_spawned.connect(_on_local_spawned)
	GameEvents.local_player_died.connect(_on_local_died)
	GameEvents.local_player_damaged.connect(_on_local_damaged)
	GameEvents.local_player_hit_enemy.connect(_on_hit_enemy)
	GameEvents.local_player_scored.connect(_on_scored)
	GameEvents.local_weapon_changed.connect(_on_weapon_changed)
	GameEvents.local_ammo_changed.connect(_on_ammo_changed)
	GameEvents.local_grenades_changed.connect(_on_grenades_changed)
	GameEvents.local_health_changed.connect(_on_health_changed)
	GameEvents.participant_killed.connect(_on_participant_killed)
	GameEvents.scores_changed.connect(_refresh_score)
	GameEvents.time_changed.connect(_on_time_changed)
	GameEvents.match_state_changed.connect(_on_match_state_changed)
	GameSettings.settings_changed.connect(_apply_scale)
	_refresh_score()
	_apply_scale()


func _build() -> void:
	# --- fullscreen overlays ---
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	damage_flash = ColorRect.new()
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.color = Color(0.8, 0.05, 0.0, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

	# --- crosshair / hitmarker ---
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)

	# --- top left: score ---
	var score_panel := UITheme.panel()
	score_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	score_panel.position = Vector2(24, 24)
	score_box = UITheme.vbox(4)
	score_panel.add_child(score_box)
	add_child(score_panel)
	_hud_scale_nodes.append(score_panel)

	# --- top center: timer ---
	timer_label = UITheme.label("", 30, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-100, 20)
	timer_label.custom_minimum_size = Vector2(200, 40)
	add_child(timer_label)

	# --- top right: killfeed ---
	killfeed_box = UITheme.vbox(4)
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	killfeed_box.position = Vector2(-444, 24)
	killfeed_box.custom_minimum_size = Vector2(420, 0)
	killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(killfeed_box)
	_hud_scale_nodes.append(killfeed_box)
	_hud_pivots[killfeed_box] = Vector2(1, 0)

	# --- bottom left: health ---
	var health_panel := UITheme.panel()
	health_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	health_panel.position = Vector2(24, -96)
	_hud_pivots[health_panel] = Vector2(0, 1)
	var hv := UITheme.vbox(6)
	health_panel.add_child(hv)
	var hh := UITheme.hbox(10)
	hv.add_child(hh)
	health_label = UITheme.label("200", 34, UITheme.TEXT)
	health_label.custom_minimum_size = Vector2(70, 0)
	hh.add_child(health_label)
	var hl := UITheme.label("GESUNDHEIT", 14, UITheme.TEXT_DIM)
	hl.size_flags_vertical = Control.SIZE_SHRINK_END
	hh.add_child(hl)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.5)
	bar_bg.custom_minimum_size = Vector2(260, 10)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(bar_bg)
	health_bar_fill = ColorRect.new()
	health_bar_fill.color = UITheme.SUCCESS
	health_bar_fill.size = Vector2(260, 10)
	health_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(health_bar_fill)
	add_child(health_panel)
	_hud_scale_nodes.append(health_panel)

	# --- bottom right: ammo ---
	var ammo_panel := UITheme.panel()
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_panel.position = Vector2(-304, -120)
	ammo_panel.custom_minimum_size = Vector2(280, 0)
	_hud_pivots[ammo_panel] = Vector2(1, 1)
	var av := UITheme.vbox(2)
	ammo_panel.add_child(av)
	weapon_label = UITheme.label("AK-47", 18, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(weapon_label)
	ammo_label = UITheme.label("30 | 90", 40, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(ammo_label)
	grenade_label = UITheme.label("GRANATEN  2", 16, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(grenade_label)
	add_child(ammo_panel)
	_hud_scale_nodes.append(ammo_panel)

	# --- center messages ---
	center_label = UITheme.label("", 44, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.position = Vector2(-500, -150)
	center_label.custom_minimum_size = Vector2(1000, 60)
	add_child(center_label)
	sub_label = UITheme.label("", 24, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sub_label.set_anchors_preset(Control.PRESET_CENTER)
	sub_label.position = Vector2(-500, -90)
	sub_label.custom_minimum_size = Vector2(1000, 40)
	add_child(sub_label)
	score_popup = UITheme.label("", 22, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	score_popup.set_anchors_preset(Control.PRESET_CENTER)
	score_popup.position = Vector2(-150, 40)
	score_popup.custom_minimum_size = Vector2(300, 30)
	score_popup.modulate.a = 0.0
	add_child(score_popup)

	# --- bottom center: hint ---
	hint_label = UITheme.label("", 15, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-400, -40)
	hint_label.custom_minimum_size = Vector2(800, 24)
	add_child(hint_label)

	fps_label = UITheme.label("", 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fps_label.position = Vector2(-124, -28)
	fps_label.custom_minimum_size = Vector2(100, 20)
	add_child(fps_label)


func _apply_scale() -> void:
	# pivots depend on the laid-out size, so apply one frame later
	call_deferred("_apply_scale_deferred")


func _apply_scale_deferred() -> void:
	var s := clampf(GameSettings.hud_scale, 0.6, 1.6)
	for n in _hud_scale_nodes:
		var c := n as Control
		var frac: Vector2 = _hud_pivots.get(c, Vector2.ZERO)
		c.pivot_offset = Vector2(c.size.x * frac.x, c.size.y * frac.y)
		c.scale = Vector2(s, s)
	fps_label.visible = GameSettings.show_fps


# ----------------------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_hitmarker_time = maxf(0.0, _hitmarker_time - delta)
	if _player and _player.alive:
		var w := _player.weapon_manager.get_current_weapon()
		var target_spread := 0.0
		if w:
			var move_ratio := clampf(_player.horizontal_speed / Player.SPRINT_SPEED, 0.0, 1.0)
			target_spread = w.get_spread_degrees(_player.is_aiming, move_ratio, not _player.is_on_floor(), _player.is_crouching)
		_spread_display = lerpf(_spread_display, target_spread, minf(1.0, delta * 12.0))
	crosshair.queue_redraw()
	# damage vignette decay
	damage_flash.color.a = maxf(0.0, damage_flash.color.a - delta * 1.6)
	var target_vignette := 0.0
	if _health_ratio < 0.6:
		target_vignette = (0.6 - _health_ratio) / 0.6 * 0.55
	vignette.color.a = lerpf(vignette.color.a, target_vignette, minf(1.0, delta * 6.0))
	# respawn countdown
	if _respawn_time_left >= 0.0:
		_respawn_time_left -= delta
		sub_label.text = "Respawn in %d" % int(ceil(maxf(_respawn_time_left, 0.0)))
	# score popup
	if _popup_time > 0.0:
		_popup_time -= delta
		score_popup.modulate.a = clampf(_popup_time / 0.5, 0.0, 1.0)
		score_popup.position.y = 40 - (1.5 - _popup_time) * 12.0
	# killfeed ageing
	var now := Time.get_ticks_msec() / 1000.0
	var i := 0
	while i < _killfeed_entries.size():
		var e: Dictionary = _killfeed_entries[i]
		var age: float = now - float(e["time"])
		if age > KILLFEED_LIFETIME:
			(e["node"] as Node).queue_free()
			_killfeed_entries.remove_at(i)
		else:
			(e["node"] as Control).modulate.a = clampf((KILLFEED_LIFETIME - age) / 1.0, 0.0, 1.0)
			i += 1
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _warmup and MatchManager.state == MatchManager.State.WARMUP:
		center_label.text = "Match beginnt in %d" % int(ceil(MatchManager.warmup_left))


# ----------------------------------------------------------------------------- crosshair

func _draw_crosshair() -> void:
	var center := crosshair.size * 0.5
	var show_cross := _player != null and _player.alive and not _player.is_sprinting
	if show_cross:
		var ads := _player.head.get_ads_blend()
		var alpha := 1.0 - clampf((ads - 0.5) * 2.0, 0.0, 1.0)
		if alpha > 0.01:
			var gap := 6.0 + _spread_display * 7.0
			var arm := 9.0
			var col := Color(1, 1, 1, 0.9 * alpha)
			var shadow := Color(0, 0, 0, 0.6 * alpha)
			_draw_cross_lines(center + Vector2(1, 1), gap, arm, shadow, 2.0)
			_draw_cross_lines(center, gap, arm, col, 2.0)
			crosshair.draw_circle(center, 1.5, col)
	if _hitmarker_time > 0.0:
		var a := clampf(_hitmarker_time / 0.12, 0.0, 1.0)
		var col2 := Color(1, 0.25, 0.2, a) if _hitmarker_kill else Color(1, 1, 1, a)
		var r1 := 5.0
		var r2 := 13.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			crosshair.draw_line(center + d * r1, center + d * r2, col2, 2.5)


func _draw_cross_lines(center: Vector2, gap: float, arm: float, col: Color, width: float) -> void:
	crosshair.draw_line(center + Vector2(gap, 0), center + Vector2(gap + arm, 0), col, width)
	crosshair.draw_line(center - Vector2(gap, 0), center - Vector2(gap + arm, 0), col, width)
	crosshair.draw_line(center + Vector2(0, gap), center + Vector2(0, gap + arm), col, width)
	crosshair.draw_line(center - Vector2(0, gap), center - Vector2(0, gap + arm), col, width)


# ----------------------------------------------------------------------------- score

func _refresh_score() -> void:
	for c in score_box.get_children():
		c.queue_free()
	var info := MatchManager.get_score_for_hud()
	if info["teams"]:
		_add_score_row("ROT", int(info["red"]), Teams.color_of(Teams.Team.RED), info["my_team"] == Teams.Team.RED)
		_add_score_row("BLAU", int(info["blue"]), Teams.color_of(Teams.Team.BLUE), info["my_team"] == Teams.Team.BLUE)
	else:
		_add_score_row("DU", int(info["me"]), UITheme.ACCENT, true)
		_add_score_row(String(info["leader_name"]), int(info["leader_kills"]), UITheme.TEXT_DIM, false)
		if String(info["second_name"]) != "-":
			_add_score_row(String(info["second_name"]), int(info["second_kills"]), UITheme.TEXT_DIM, false)
	var limit := UITheme.label("Ziel: %d Kills" % int(info["limit"]), 13, UITheme.TEXT_DIM)
	score_box.add_child(limit)


func _add_score_row(title: String, value: int, color: Color, highlight: bool) -> void:
	var row := UITheme.hbox(10)
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(6, 26)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var name_l := UITheme.label(title, 18, UITheme.TEXT if highlight else UITheme.TEXT_DIM)
	name_l.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_l)
	var val_l := UITheme.label(str(value), 24, color, HORIZONTAL_ALIGNMENT_RIGHT)
	val_l.custom_minimum_size = Vector2(50, 0)
	row.add_child(val_l)
	score_box.add_child(row)


func _on_time_changed(seconds_left: float) -> void:
	timer_label.text = UITheme.format_time(seconds_left)
	if seconds_left <= 10.0:
		timer_label.add_theme_color_override("font_color", UITheme.DANGER)


# ----------------------------------------------------------------------------- events

func _on_match_state_changed(state: int) -> void:
	match state:
		MatchManager.State.WARMUP:
			_warmup = true
			center_label.text = "Match beginnt in %d" % int(ceil(MatchManager.warmup_left))
			sub_label.text = "%s  •  %s" % [MatchManager.mode.display_name, GameDirector.get_map_info(MatchManager.config.map_id)["name"]]
			hint_label.text = "WASD Bewegen  •  Shift Sprint  •  Strg Ducken  •  RMT Zielen  •  R Nachladen  •  Q/1/2 Waffe  •  G Granate  •  Tab Punkte"
		MatchManager.State.RUNNING:
			_warmup = false
			center_label.text = "KAMPF!"
			sub_label.text = ""
			AudioManager.play_2d("countdown_go", -4.0)
			_clear_center_after(1.5)
			get_tree().create_timer(6.0).timeout.connect(func() -> void: hint_label.text = "")
		MatchManager.State.ENDED:
			center_label.text = ""
			sub_label.text = ""
			_respawn_time_left = -1.0
	if MatchManager.config.time_limit > 0.0:
		timer_label.text = UITheme.format_time(MatchManager.time_left)
	else:
		timer_label.text = ""


func _clear_center_after(seconds: float) -> void:
	var expected := center_label.text
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if center_label.text == expected:
			center_label.text = "")


func _on_local_spawned(player: Node) -> void:
	_player = player as Player
	_respawn_time_left = -1.0
	center_label.text = ""
	sub_label.text = ""
	_health_ratio = 1.0
	_on_health_changed(_player.health.max_health, _player.health.max_health)
	_on_weapon_changed(_player.weapon_manager.get_current_weapon())
	_on_grenades_changed(_player.weapon_manager.grenades)


func _on_local_died(killer_id: int, respawn_delay: float) -> void:
	var killer := MatchManager.get_participant(killer_id)
	if killer and killer.id != MatchManager.local_participant_id:
		center_label.text = "Getötet von %s" % killer.display_name
	else:
		center_label.text = "Du bist gestorben"
	_respawn_time_left = respawn_delay
	sub_label.text = "Respawn in %d" % int(ceil(respawn_delay))


func _on_local_damaged(amount: float, _source_position: Vector3) -> void:
	damage_flash.color.a = clampf(damage_flash.color.a + amount / 100.0 * 0.8, 0.0, 0.7)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_ratio = clampf(current / maximum, 0.0, 1.0)
	health_label.text = str(int(ceil(current)))
	health_bar_fill.size.x = 260.0 * _health_ratio
	health_bar_fill.color = UITheme.SUCCESS.lerp(UITheme.DANGER, 1.0 - _health_ratio)


func _on_hit_enemy(headshot: bool, killed: bool) -> void:
	_hitmarker_time = 0.14
	_hitmarker_kill = killed
	AudioManager.play_2d("hitmarker_headshot" if headshot else "hitmarker", -6.0, 0.02)


func _on_scored(points: int, reason: String) -> void:
	score_popup.text = "+%d  %s" % [points, reason]
	_popup_time = 1.5


func _on_weapon_changed(weapon: Node) -> void:
	var w := weapon as Weapon
	if w == null:
		return
	weapon_label.text = w.data.display_name.to_upper()
	_on_ammo_changed(w.magazine, w.reserve)


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	ammo_label.text = "%d | %d" % [magazine, reserve]
	ammo_label.add_theme_color_override("font_color", UITheme.DANGER if magazine == 0 else (UITheme.ACCENT if magazine <= 5 else UITheme.TEXT))


func _on_grenades_changed(count: int) -> void:
	grenade_label.text = "GRANATEN  %d" % count


func _on_participant_killed(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	var victim := MatchManager.get_participant(victim_id)
	var killer := MatchManager.get_participant(killer_id)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(420, 26)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	rt.add_theme_constant_override("outline_size", 4)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var victim_name := victim.display_name if victim else "?"
	var victim_col := Teams.color_of(victim.team).to_html(false) if victim else "ffffff"
	var weapon_name: String = WEAPON_LABELS.get(weapon_id, weapon_id)
	var text := ""
	if killer and killer_id != victim_id:
		var killer_col := Teams.color_of(killer.team).to_html(false)
		text = "[right][color=#%s]%s[/color]  [color=#aaaaaa][%s%s][/color]  [color=#%s]%s[/color][/right]" % [killer_col, killer.display_name, weapon_name, " • Kopf" if headshot else "", victim_col, victim_name]
	else:
		text = "[right][color=#%s]%s[/color]  [color=#aaaaaa]hat sich selbst ausgeschaltet[/color][/right]" % [victim_col, victim_name]
	rt.text = text
	killfeed_box.add_child(rt)
	_killfeed_entries.append({"node": rt, "time": Time.get_ticks_msec() / 1000.0})
	while _killfeed_entries.size() > KILLFEED_MAX:
		var old: Dictionary = _killfeed_entries.pop_front()
		(old["node"] as Node).queue_free()
	if killer_id == MatchManager.local_participant_id and victim_id != killer_id:
		AudioManager.play_2d("kill_confirm", -4.0)
