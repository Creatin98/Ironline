class_name HUD
extends Control
## In-match HUD: crosshair, hitmarker, health, ammo, grenades, score, timer,
## killfeed, respawn/warmup overlays and damage feedback. Built in code so the
## layout scales with GameSettings.hud_scale.

const KILLFEED_LIFETIME := 6.0
const BLOOD_LIFETIME := 7.0
const KILLFEED_MAX := 6
const WEAPON_LABELS := {
	"ak47": "AK-47", "mp5": "MP5", "shotgun": "Shotgun", "pistol": "Pistole", "sniper": "M200",
	"grenade": "Granate", "flashbang": "Blendgranate", "world": "Umgebung",
}

var crosshair: Control
var health_bar_fill: ColorRect
var health_label: Label
var ammo_label: Label
var weapon_label: Label
var grenade_label: Label
var _grenade_count: int = 2
var _flash_count: int = 1
var score_box: VBoxContainer
var timer_label: Label
var killfeed_box: VBoxContainer
var center_label: Label
var sub_label: Label
var popup_box: VBoxContainer
var vignette: ColorRect
var damage_flash: ColorRect
var fps_label: Label
var hint_label: Label

var _player: Player
var _health_ratio: float = 1.0
var _hitmarker_time: float = 0.0
var _hitmarker_total: float = 0.14
var _hitmarker_kill: bool = false
var _hitmarker_head: bool = false
var _kill_flash: ColorRect
var _spread_display: float = 0.0
var _respawn_time_left: float = -1.0
var _killfeed_entries: Array = [] # [{node, time}]
var minimap: Minimap
var _blood_layer: Control
var _blood_splats: Array = [] # [{p: Vector2, size: float, rot: float, tex: int, age: float, vy: float}]
var _damage_dirs: Array = [] # [{dir: Vector2 (world x/z), time: float}]
var _warmup: bool = false
## name -> {"node": Control, "corner": Vector2 (0/0.5/1 = left/centre/right, top/bottom)}
var _blocks: Dictionary = {}
var _editing: bool = false
var _edit_overlay: Control
var _drag_name: String = ""

signal edit_finished


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
	GameEvents.local_flashbangs_changed.connect(_on_flashbangs_changed)
	GameEvents.local_health_changed.connect(_on_health_changed)
	GameEvents.participant_killed.connect(_on_participant_killed)
	GameEvents.scores_changed.connect(_refresh_score)
	GameEvents.time_changed.connect(_on_time_changed)
	GameEvents.match_state_changed.connect(_on_match_state_changed)
	GameSettings.settings_changed.connect(_apply_scale)
	resized.connect(_apply_scale)
	_refresh_score()
	_apply_scale()


func _build() -> void:
	# --- fullscreen overlays ---
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	_kill_flash = ColorRect.new()
	_kill_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kill_flash.color = Color(1.0, 0.95, 0.85, 0.0)
	_kill_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kill_flash)
	damage_flash = ColorRect.new()
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.color = Color(0.8, 0.05, 0.0, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)
	_blood_layer = Control.new()
	_blood_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_layer.draw.connect(_draw_blood)
	# own canvas layer: stays visible while the HUD is hidden (killcam)
	var blood_canvas := CanvasLayer.new()
	blood_canvas.layer = 1 # behind the HUD (UI layer 2): the HUD is never covered by blood
	add_child(blood_canvas)
	blood_canvas.add_child(_blood_layer)

	# --- crosshair / hitmarker ---
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)

	# --- top left: score ---
	var score_panel := UITheme.panel()
	score_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	score_box = UITheme.vbox(4)
	score_panel.add_child(score_box)
	add_child(score_panel)
	_blocks["score"] = {"node": score_panel, "corner": Vector2(0, 0), "label": "Punkte"}

	# --- top center: timer ---
	timer_label = UITheme.label("", 30, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	timer_label.custom_minimum_size = Vector2(200, 40)
	add_child(timer_label)
	_blocks["timer"] = {"node": timer_label, "corner": Vector2(0.5, 0), "label": "Zeit"}

	# --- top right: killfeed ---
	killfeed_box = UITheme.vbox(4)
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	killfeed_box.custom_minimum_size = Vector2(420, 64)
	killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(killfeed_box)
	_blocks["killfeed"] = {"node": killfeed_box, "corner": Vector2(1, 0), "label": "Killfeed"}

	# --- bottom left: health ---
	var health_panel := UITheme.panel()
	health_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var hv := UITheme.vbox(6)
	health_panel.add_child(hv)
	var hh := UITheme.hbox(10)
	hv.add_child(hh)
	health_label = UITheme.label("100%", 34, UITheme.TEXT)
	health_label.custom_minimum_size = Vector2(110, 0)
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
	_blocks["health"] = {"node": health_panel, "corner": Vector2(0, 1), "label": "Gesundheit"}

	# --- bottom right: ammo ---
	var ammo_panel := UITheme.panel()
	ammo_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ammo_panel.custom_minimum_size = Vector2(280, 0)
	var av := UITheme.vbox(2)
	ammo_panel.add_child(av)
	weapon_label = UITheme.label("AK-47", 18, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(weapon_label)
	ammo_label = UITheme.label("30 | 90", 40, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(ammo_label)
	grenade_label = UITheme.label("GRANATEN  2    BLENDGRANATE  1", 16, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(grenade_label)
	add_child(ammo_panel)
	_blocks["ammo"] = {"node": ammo_panel, "corner": Vector2(1, 1), "label": "Munition"}

	# --- minimap (top left, below the score) ---
	minimap = Minimap.new()
	add_child(minimap)
	_blocks["minimap"] = {"node": minimap, "corner": Vector2(0, 0), "label": "Minimap"}

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
	# score popups (+100 Kill, +50 Assist ...) stack below the crosshair
	popup_box = VBoxContainer.new()
	popup_box.set_anchors_preset(Control.PRESET_CENTER)
	popup_box.position = Vector2(-250, 70)
	popup_box.custom_minimum_size = Vector2(500, 0)
	popup_box.add_theme_constant_override("separation", 0)
	popup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_box)

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
	# sizes are known one frame later
	call_deferred("_layout")


## Places every HUD block in its screen corner (symmetric margins), scaled, plus the offset
## the player set in the HUD editor.
func _layout() -> void:
	var k := clampf(GameSettings.hud_scale, 0.6, 1.6)
	var m := GameSettings.hud_margin * k
	var area := size
	for block_name in _blocks:
		var info: Dictionary = _blocks[block_name]
		var c: Control = info["node"]
		var corner: Vector2 = info["corner"]
		c.pivot_offset = Vector2.ZERO
		c.scale = Vector2(k, k)
		c.visible = is_editing() or GameSettings.show_hud and (block_name != "minimap" or GameSettings.show_minimap) \
				and (block_name != "killfeed" or GameSettings.show_killfeed)
		var s := c.get_combined_minimum_size() * k
		var pos := Vector2(m + corner.x * (area.x - s.x - 2.0 * m), m + corner.y * (area.y - s.y - 2.0 * m))
		if block_name == "minimap":
			var score_node: Control = _blocks["score"]["node"]
			pos.y += score_node.get_combined_minimum_size().y * k + 8.0 * k
		pos += _offset_of(block_name)
		c.position = _clamp_to_screen(pos, s, area)
	fps_label.visible = GameSettings.show_fps
	_update_blood_visibility()
	if _edit_overlay != null:
		_edit_overlay.queue_redraw()


func _offset_of(block_name: String) -> Vector2:
	var v: Variant = GameSettings.hud_offsets.get(block_name, Vector2.ZERO)
	return v if v is Vector2 else Vector2.ZERO


func _clamp_to_screen(pos: Vector2, s: Vector2, area: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, area.x - s.x)), clampf(pos.y, 0.0, maxf(0.0, area.y - s.y)))


# ----------------------------------------------------------------------------- HUD editor

## Lets the player drag every block; "Fertig" saves, "Zurücksetzen" restores the corners.
func begin_edit() -> void:
	if _editing:
		return
	_editing = true
	_edit_overlay = Control.new()
	_edit_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edit_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_edit_overlay.draw.connect(_draw_edit_overlay)
	_edit_overlay.gui_input.connect(_edit_input)
	add_child(_edit_overlay)
	var box := UITheme.vbox(10)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-260, -90)
	_edit_overlay.add_child(box)
	var title := UITheme.label("HUD anpassen", 34, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	title.custom_minimum_size = Vector2(520, 0)
	box.add_child(title)
	var hint := UITheme.label("Elemente mit der Maus verschieben. Der Abstand zum Rand und die Größe stehen in den Einstellungen.", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	box.add_child(hint)
	var row := UITheme.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var reset := UITheme.button("Zurücksetzen", 20, 220)
	reset.pressed.connect(func() -> void:
		GameSettings.hud_offsets = {}
		_layout())
	row.add_child(reset)
	var done := UITheme.button("Fertig", 20, 220)
	done.pressed.connect(end_edit)
	row.add_child(done)
	box.add_child(row)
	_edit_overlay.queue_redraw()


func is_editing() -> bool:
	return _editing


func end_edit() -> void:
	if not _editing:
		return
	_editing = false
	_drag_name = ""
	if _edit_overlay != null:
		_edit_overlay.queue_free()
		_edit_overlay = null
	GameSettings.save()
	edit_finished.emit()


func _block_rect(block_name: String) -> Rect2:
	var c: Control = _blocks[block_name]["node"]
	return Rect2(c.position, c.get_combined_minimum_size() * c.scale)


func _draw_edit_overlay() -> void:
	_edit_overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	for block_name in _blocks:
		var r := _block_rect(block_name)
		var active: bool = block_name == _drag_name
		_edit_overlay.draw_rect(r, Color(0.97, 0.63, 0.16, 0.2 if active else 0.08))
		_edit_overlay.draw_rect(r, UITheme.ACCENT, false, 3.0 if active else 2.0)
		var font := ThemeDB.fallback_font
		_edit_overlay.draw_string(font, r.position + Vector2(6, -6), String(_blocks[block_name]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.ACCENT)


func _edit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_name = ""
			var names := _blocks.keys()
			names.reverse()
			for block_name in names:
				if _block_rect(block_name).has_point(event.position):
					_drag_name = block_name
					break
		else:
			_drag_name = ""
		_edit_overlay.queue_redraw()
	elif event is InputEventMouseMotion and _drag_name != "":
		var current: Vector2 = _offset_of(_drag_name) + (event as InputEventMouseMotion).relative
		GameSettings.hud_offsets[_drag_name] = current
		_layout()


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
	for d in _damage_dirs:
		d["time"] = float(d["time"]) - delta
	_damage_dirs = _damage_dirs.filter(func(d: Dictionary) -> bool: return float(d["time"]) > 0.0)
	crosshair.queue_redraw()
	minimap.player = _player
	_update_blood_visibility()
	for sp in _blood_splats:
		sp["age"] = float(sp["age"]) + delta
		sp["p"] = (sp["p"] as Vector2) + Vector2(0.0, float(sp["vy"]) * delta * clampf(float(sp["age"]) * 0.6, 0.0, 1.0))
	_blood_splats = _blood_splats.filter(func(sp: Dictionary) -> bool: return float(sp["age"]) < BLOOD_LIFETIME)
	if not _blood_splats.is_empty() or _blood_layer.visible:
		_blood_layer.queue_redraw()
	# damage vignette decay
	damage_flash.color.a = maxf(0.0, damage_flash.color.a - delta * 1.6)
	_kill_flash.color.a = maxf(0.0, _kill_flash.color.a - delta * 1.1)
	var target_vignette := 0.0
	if _health_ratio < 0.6:
		target_vignette = (0.6 - _health_ratio) / 0.6 * 0.55
	vignette.color.a = lerpf(vignette.color.a, target_vignette, minf(1.0, delta * 6.0))
	# respawn countdown
	if _respawn_time_left >= 0.0:
		_respawn_time_left -= delta
		sub_label.text = "Respawn in %d" % int(ceil(maxf(_respawn_time_left, 0.0)))
	# score popup
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
	var in_game := _player != null and _player.alive and GameSettings.show_hud and GameSettings.show_crosshair
	if in_game and _player.weapon_manager.is_throwing_grenade():
		_draw_grenade_cross(center, _player.weapon_manager.grenade_holding)
	elif in_game and _player.is_sprinting:
		_draw_sprint_cross(center)
	elif in_game:
		var ads := _player.head.get_ads_blend()
		var alpha := 1.0 - clampf((ads - 0.5) * 2.0, 0.0, 1.0)
		if alpha > 0.01:
			var gap := 6.0 + _spread_display * 7.0
			var arm := 9.0
			var col := Color(1, 1, 1, 0.9 * alpha)
			var shadow := Color(0, 0, 0, 0.6 * alpha)
			var cw := _player.weapon_manager.get_current_weapon()
			if cw != null and cw.data.pellets > 1:
				# shotgun: ring that shows the pellet spread
				var radius := 11.0 + _spread_display * 3.6
				crosshair.draw_arc(center + Vector2(1, 1), radius, 0.0, TAU, 48, shadow, 2.5, true)
				crosshair.draw_arc(center, radius, 0.0, TAU, 48, col, 2.0, true)
			else:
				_draw_cross_lines(center + Vector2(1, 1), gap, arm, shadow, 2.0)
				_draw_cross_lines(center, gap, arm, col, 2.0)
			crosshair.draw_circle(center, 1.5, col)
	if GameSettings.show_damage_indicators:
		_draw_damage_indicators(center)
	if _hitmarker_time > 0.0 and GameSettings.show_hit_markers:
		_draw_hitmarker(center)


func _draw_hitmarker(center: Vector2) -> void:
	HitFeedback.draw_marker(crosshair, center, _hitmarker_time, _hitmarker_total, _hitmarker_head, _hitmarker_kill)


## Red arcs around the crosshair that point towards whoever hurt us.
func _draw_damage_indicators(center: Vector2) -> void:
	if _damage_dirs.is_empty() or _player == null or not is_instance_valid(_player):
		return
	var yaw := _player.rotation.y
	var forward := Vector2(-sin(yaw), -cos(yaw))
	for d in _damage_dirs:
		var a := forward.angle_to(d["dir"])
		var alpha := clampf(float(d["time"]) / 0.6, 0.0, 1.0) * 0.85
		var radius := 150.0
		crosshair.draw_arc(center, radius, a - PI / 2.0 - 0.28, a - PI / 2.0 + 0.28, 12, Color(0.95, 0.12, 0.08, alpha), 9.0, true)


## While sprinting the crosshair shrinks to a calm dot with four tiny ticks: you always see where you look.
func _draw_sprint_cross(center: Vector2) -> void:
	var shadow := Color(0, 0, 0, 0.5)
	crosshair.draw_circle(center + Vector2(1, 1), 2.5, shadow)
	crosshair.draw_circle(center, 2.0, Color(1, 1, 1, 0.65))
	_draw_cross_lines(center + Vector2(1, 1), 11.0, 4.0, shadow, 1.6)
	_draw_cross_lines(center, 11.0, 4.0, Color(1, 1, 1, 0.42), 1.6)


## Grenade in the hand: dot with a ring; held ready (pin pulled, key down) the ring glows warm, pulses and
## gets four inward ticks ("armed").
func _draw_grenade_cross(center: Vector2, holding: bool) -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 7.0) if holding else 0.0
	var col := Color(1, 1, 1, 0.8)
	if holding:
		col = Color(1.0, 0.8, 0.45, 0.85 + 0.15 * pulse)
	var radius := 15.0 + 1.2 * pulse
	var shadow := Color(0, 0, 0, 0.5)
	crosshair.draw_arc(center + Vector2(1, 1), radius, 0.0, TAU, 40, shadow, 2.6, true)
	crosshair.draw_arc(center, radius, 0.0, TAU, 40, col, 1.8, true)
	crosshair.draw_circle(center + Vector2(1, 1), 2.5, shadow)
	crosshair.draw_circle(center, 2.0, col)
	if holding:
		for i in 4:
			var dir := Vector2.from_angle(PI * 0.5 * i)
			crosshair.draw_line(center + dir * (radius - 1.0), center + dir * (radius - 7.0), col, 1.8)


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
			hint_label.text = "WASD Bewegen  •  Shift Sprint  •  Strg Ducken  •  RMT Zielen  •  R Nachladen  •  Q/1/2 Waffe  •  G Granate  •  F Blendgranate  •  Tab Punkte"
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
	_blood_splats.clear() # no blood carried over from the previous life
	_respawn_time_left = -1.0
	center_label.text = ""
	sub_label.text = ""
	_health_ratio = 1.0
	_on_health_changed(_player.health.max_health, _player.health.max_health)
	_on_weapon_changed(_player.weapon_manager.get_current_weapon())
	_on_grenades_changed(_player.weapon_manager.grenades)
	_on_flashbangs_changed(_player.weapon_manager.flashbangs)


func _on_local_died(killer_id: int, respawn_delay: float) -> void:
	# screen blood fades out quickly on death: nothing in the death view / killcam, nothing after the respawn
	for sp in _blood_splats:
		sp["age"] = maxf(float(sp["age"]), BLOOD_LIFETIME - 0.5)
	var killer := MatchManager.get_participant(killer_id)
	if killer and killer.id != MatchManager.local_participant_id:
		center_label.text = "Getötet von %s" % killer.display_name
	else:
		center_label.text = "Du bist gestorben"
	_respawn_time_left = respawn_delay
	sub_label.text = "Respawn in %d" % int(ceil(respawn_delay))


## Screen blood only while playing: not in replays (killcam / last kill) and not at the match end.
func _update_blood_visibility() -> void:
	_blood_layer.visible = GameSettings.show_blood_overlay and MatchManager.state != MatchManager.State.ENDED \
			and not (_player != null and is_instance_valid(_player) and _player.replay_mode)


func _draw_blood() -> void:
	for sp in _blood_splats:
		var age := float(sp["age"])
		var a := clampf((BLOOD_LIFETIME - age) / 1.8, 0.0, 1.0) * 0.88
		var col := Color(0.5, 0.03, 0.03, a)
		var grow := clampf(age * 5.0, 0.0, 1.0)
		var p: Vector2 = sp["p"]
		match int(sp["kind"]):
			0:
				var sz: float = float(sp["size"]) * (0.75 + 0.25 * grow)
				_blood_layer.draw_set_transform(p, float(sp["rot"]), Vector2.ONE)
				_blood_layer.draw_texture_rect(BloodFx.splat_texture(int(sp["tex"])), Rect2(-sz * 0.5, -sz * 0.5 * 1.15, sz, sz * 1.15), false, col)
				_blood_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			1: # smear / drip: tapered streak with a drop at its end
				var d: Vector2 = sp["dir"]
				var len: float = float(sp["size"]) * grow
				var w: float = float(sp["w"])
				var n := d.orthogonal()
				var pts := PackedVector2Array([p + n * w * 0.5, p + d * len * 0.55 + n * w * 0.32, p + d * len, p + d * len * 0.55 - n * w * 0.32, p - n * w * 0.5])
				if len > 6.0:
					_blood_layer.draw_colored_polygon(pts, col)
				_blood_layer.draw_circle(p + d * len, w * 0.34, col)
				_blood_layer.draw_circle(p, w * 0.55, col)
			_: # spray / scratches: thin fan of lines with droplets at the ends
				var d2: Vector2 = sp["dir"]
				var rays: Array = sp["rays"]
				for r in rays:
					var dir := d2.rotated(float(r[0]))
					var l := float(r[1]) * grow
					_blood_layer.draw_line(p, p + dir * l, col, float(r[2]), true)
					_blood_layer.draw_circle(p + dir * l, float(r[2]) * 0.9, col)


## Blood on the screen: splats, smears/drips and thin scratch sprays, spread over the whole picture
## (kept away from the very middle). Stronger hits = more of them.
func _add_blood_splats(amount: float) -> void:
	var count := clampi(2 + int(amount / 12.0), 2, 8)
	var s := _blood_layer.size
	var k := s.y / 1080.0
	for i in count:
		var pos := Vector2.ZERO
		for attempt in 8:
			pos = Vector2(randf_range(0.03, 0.97) * s.x, randf_range(0.03, 0.97) * s.y)
			var rel := (pos - s * 0.5) / s
			if absf(rel.x) > 0.17 or absf(rel.y) > 0.2:
				break
		var kind_roll := randf()
		var sp := {"p": pos, "age": 0.0, "vy": randf_range(8.0, 40.0), "kind": 0}
		if kind_roll < 0.45:
			sp["size"] = randf_range(80.0, 200.0) * k
			sp["rot"] = randf() * TAU
			sp["tex"] = randi() % BloodFx.VARIANTS
		elif kind_roll < 0.78:
			sp["kind"] = 1
			sp["dir"] = Vector2.DOWN.rotated(randf_range(-0.7, 0.7)) if randf() < 0.7 else Vector2.from_angle(randf() * TAU)
			sp["size"] = randf_range(160.0, 420.0) * k
			sp["w"] = randf_range(16.0, 46.0) * k
		else:
			sp["kind"] = 2
			sp["dir"] = Vector2.from_angle(randf() * TAU)
			var rays: Array = []
			for r in randi_range(5, 9):
				rays.append([randf_range(-0.55, 0.55), randf_range(70.0, 260.0) * k, randf_range(2.0, 5.0) * k])
			sp["rays"] = rays
		_blood_splats.append(sp)
	while _blood_splats.size() > 26:
		_blood_splats.pop_front()


func _on_local_damaged(amount: float, source_position: Vector3) -> void:
	damage_flash.color.a = clampf(damage_flash.color.a + amount / 100.0 * 0.4, 0.0, 0.4)
	_add_blood_splats(amount)
	if _player != null and is_instance_valid(_player):
		var to := Vector2(source_position.x - _player.global_position.x, source_position.z - _player.global_position.z)
		if to.length() > 1.0:
			_damage_dirs.append({"dir": to.normalized(), "time": 1.2})
			if _damage_dirs.size() > 6:
				_damage_dirs.pop_front()


func _on_health_changed(current: float, maximum: float) -> void:
	_health_ratio = clampf(current / maximum, 0.0, 1.0)
	health_label.text = "%d%%" % int(ceil(_health_ratio * 100.0))
	health_bar_fill.size.x = 260.0 * _health_ratio
	health_bar_fill.color = UITheme.SUCCESS.lerp(UITheme.DANGER, 1.0 - _health_ratio)


func _on_hit_enemy(headshot: bool, killed: bool) -> void:
	show_hitmarker(headshot, killed)
	var streak := 1
	var me := MatchManager.get_local_participant()
	if me != null:
		streak = maxi(1, me.killstreak)
	HitFeedback.play_sounds(headshot, killed, streak)
	if killed:
		_kill_flash.color.a = 0.16 if headshot else 0.1
		if _player != null and is_instance_valid(_player):
			_player.head.kick_fov(5.5 if headshot else 3.5)
	elif headshot and _player != null and is_instance_valid(_player):
		_player.head.kick_fov(1.5)


func show_hitmarker(headshot: bool, killed: bool) -> void:
	_hitmarker_head = headshot
	_hitmarker_kill = killed
	_hitmarker_total = HitFeedback.duration(headshot, killed)
	_hitmarker_time = _hitmarker_total


func _on_scored(points: int, reason: String) -> void:
	var text := "+%d  %s" % [points, reason.to_upper()]
	var me := MatchManager.get_local_participant()
	if reason != "Assist" and me != null and me.killstreak >= 2:
		text += "   •   %d IN FOLGE" % me.killstreak
	var color := UITheme.ACCENT
	var size := 26
	match reason:
		"Kopfschuss":
			color = Color(1.0, 0.32, 0.22)
			size = 30
		"Assist":
			color = Color(0.5, 0.78, 1.0)
			size = 22
	var label := UITheme.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	label.custom_minimum_size = Vector2(500, 0)
	label.pivot_offset = Vector2(250, size * 0.7)
	label.scale = Vector2(1.7, 1.7)
	label.modulate.a = 0.0
	popup_box.add_child(label)
	while popup_box.get_child_count() > 4:
		popup_box.get_child(0).queue_free()
		popup_box.remove_child(popup_box.get_child(0))
	if reason == "Assist":
		AudioManager.play_2d("hitmarker", -13.0, 0.0).pitch_scale = 1.5
	# pops in big, settles, holds, floats up while fading
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 1.0, 0.05)
	tw.chain().tween_interval(1.0)
	tw.chain().tween_property(label, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(label.queue_free)


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
	_grenade_count = count
	_refresh_grenade_label()


func _on_flashbangs_changed(count: int) -> void:
	_flash_count = count
	_refresh_grenade_label()


func _refresh_grenade_label() -> void:
	grenade_label.text = "GRANATEN  %d    BLENDGRANATE  %d" % [_grenade_count, _flash_count]


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
	# weapon kills already played their confirmation via the hit feedback; grenades did not
	if killer_id == MatchManager.local_participant_id and victim_id != killer_id and weapon_id in ["grenade", "flashbang"]:
		AudioManager.play_2d("kill_confirm", -4.0)
