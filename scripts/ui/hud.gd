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
var health_ticks_bar: Control
var compass_bar: Control
var health_label: Label
var ammo_label: Label
var weapon_label: Label
var silhouette: WeaponSilhouette
var _spectator: bool = false
var _banner: Label
var _banner_tween: Tween
var grenade_label: Label
var _grenade_count: int = 2
var _flash_count: int = 1
var score_box: VBoxContainer
var timer_label: Label
var killfeed_box: VBoxContainer
var center_label: Label
var sub_label: Label
var medal_hud: MedalHud
var _multi_count: int = 0
var _last_kill_t: float = -100.0
var _last_killer_of_me: int = 0
var damage_fx: DamageFx # all visual damage feedback (vignette, lens blood, critical health)
var fps_label: Label
var hint_label: Label

var _player: Player
var reload_hint: Label # "R ZUM NACHLADEN" when the magazine is nearly empty
var _hint_alpha: float = 0.0
var _hint_age: float = 0.0
## Share of the magazine (at least 2 rounds) below which the reload hint appears.
const RELOAD_HINT_FRACTION := 0.25
const RELOAD_HINT_MIN := 2
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
	GameEvents.local_ammo_picked.connect(_on_ammo_picked)
	GameEvents.training_hit.connect(_on_training_hit)
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
	_kill_flash = ColorRect.new()
	_kill_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kill_flash.color = Color(1.0, 0.95, 0.85, 0.0)
	_kill_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kill_flash)
	damage_fx = DamageFx.new() # own canvas layer below the HUD: stays visible while the HUD is hidden (killcam)
	damage_fx.name = "DamageFx"
	add_child(damage_fx)

	# --- crosshair / hitmarker ---
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)

	reload_hint = UITheme.label("", 26, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	reload_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	reload_hint.size = Vector2(520, 50)
	reload_hint.pivot_offset = Vector2(260, 25)
	reload_hint.modulate.a = 0.0
	reload_hint.add_theme_constant_override("outline_size", 6)
	add_child(reload_hint)

	# --- top left: score (schlankes CoD-Layout ohne dicken Kasten) ---
	var score_panel := Control.new()
	score_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	score_panel.custom_minimum_size = Vector2(210, 95)
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_box = UITheme.vbox(3)
	score_panel.add_child(score_box)
	add_child(score_panel)
	_blocks["score"] = {"node": score_panel, "corner": Vector2(0, 0), "label": "Punkte"}

	# --- top center: timer + taktischer Kompass ---
	var top_center := UITheme.vbox(2)
	top_center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_center.custom_minimum_size = Vector2(360, 72)
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	timer_label = UITheme.label("", 26, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.custom_minimum_size = Vector2(360, 32)
	timer_label.add_theme_constant_override("outline_size", 5)
	top_center.add_child(timer_label)

	compass_bar = Control.new()
	compass_bar.custom_minimum_size = Vector2(360, 36)
	compass_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_bar.draw.connect(_draw_compass)
	top_center.add_child(compass_bar)

	add_child(top_center)
	_blocks["timer"] = {"node": top_center, "corner": Vector2(0.5, 0), "label": "Zeit & Kompass"}

	# --- top right: killfeed ---
	killfeed_box = UITheme.vbox(4)
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	killfeed_box.custom_minimum_size = Vector2(420, 64)
	killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(killfeed_box)
	_blocks["killfeed"] = {"node": killfeed_box, "corner": Vector2(1, 0), "label": "Killfeed"}

	# --- bottom left: segmentierte CoD-HP-Bar (40 feine Striche) ---
	var health_panel := Control.new()
	health_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	health_panel.custom_minimum_size = Vector2(300, 68)
	health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hv := UITheme.vbox(4)
	health_panel.add_child(hv)

	var hh := UITheme.hbox(8)
	hv.add_child(hh)
	health_label = UITheme.label("100%", 36, UITheme.TEXT)
	health_label.add_theme_constant_override("outline_size", 5)
	hh.add_child(health_label)
	var hl := UITheme.label("HP", 14, Color(0.75, 0.82, 0.88, 0.85))
	hl.size_flags_vertical = Control.SIZE_SHRINK_END
	hl.add_theme_constant_override("outline_size", 4)
	hh.add_child(hl)

	health_ticks_bar = Control.new()
	health_ticks_bar.custom_minimum_size = Vector2(280, 16)
	health_ticks_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_ticks_bar.draw.connect(_draw_health_ticks)
	hv.add_child(health_ticks_bar)

	health_bar_fill = ColorRect.new()
	health_bar_fill.visible = false
	health_panel.add_child(health_bar_fill)

	add_child(health_panel)
	_blocks["health"] = {"node": health_panel, "corner": Vector2(0, 1), "label": "Gesundheit"}

	# --- bottom right: offenes CoD-Waffen- & Munitions-HUD ---
	var ammo_panel := Control.new()
	ammo_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ammo_panel.custom_minimum_size = Vector2(360, 120)
	ammo_panel.size = Vector2(360, 120)
	ammo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av := UITheme.vbox(2)
	av.custom_minimum_size = Vector2(360, 0)
	ammo_panel.add_child(av)

	var top_wep_row := UITheme.hbox(10)
	top_wep_row.alignment = BoxContainer.ALIGNMENT_END
	av.add_child(top_wep_row)

	silhouette = WeaponSilhouette.new()
	top_wep_row.add_child(silhouette)

	ammo_label = UITheme.label("30 | 90", 42, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_label.add_theme_constant_override("outline_size", 6)
	top_wep_row.add_child(ammo_label)

	var line := ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.25)
	line.custom_minimum_size = Vector2(260, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(line)

	var bottom_wep_row := UITheme.hbox(12)
	bottom_wep_row.alignment = BoxContainer.ALIGNMENT_END
	av.add_child(bottom_wep_row)

	weapon_label = UITheme.label("AK-47", 15, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	weapon_label.add_theme_constant_override("outline_size", 4)
	bottom_wep_row.add_child(weapon_label)

	grenade_label = UITheme.label("G: 2  •  B: 1", 15, Color(0.85, 0.85, 0.85, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
	grenade_label.add_theme_constant_override("outline_size", 4)
	bottom_wep_row.add_child(grenade_label)

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
	# medals (top centre) and score popups (next to the crosshair)
	medal_hud = MedalHud.new()
	add_child(medal_hud)

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
	_update_reload_hint(delta)
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
	if visible and compass_bar != null:
		compass_bar.queue_redraw()
	minimap.player = _player
	# respawn countdown
	if _respawn_time_left >= 0.0:
		_respawn_time_left -= delta
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
	if health_ticks_bar != null:
		health_ticks_bar.queue_redraw()
	_on_weapon_changed(_player.weapon_manager.get_current_weapon())
	_on_grenades_changed(_player.weapon_manager.grenades)
	_on_flashbangs_changed(_player.weapon_manager.flashbangs)


func _on_local_died(_killer_id: int, respawn_delay: float) -> void:
	# no "Getötet von ..." / "Respawn in ..." text over the death camera (the killcam shows both in its own bars)
	center_label.text = ""
	sub_label.text = ""
	_respawn_time_left = respawn_delay


func _on_local_damaged(amount: float, source_position: Vector3) -> void:
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
	medal_hud.score(points, reason)
	if reason == "Assist":
		AudioManager.play_2d("hitmarker", -13.0, 0.0).pitch_scale = 1.5


## Medals for the local player's kills: headshot (with "One Shot One Kill" for the sniper), longshot, grenade, revenge,
## multi kills within 4 s and kill streaks. They appear one after the other.
func _evaluate_medals(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	var me := MatchManager.get_local_participant()
	if me == null:
		return
	if victim_id == me.id:
		_last_killer_of_me = killer_id
		_multi_count = 0
		return
	var victim := MatchManager.get_participant(victim_id)
	if killer_id != me.id or victim == null or victim_id == killer_id or not me.is_enemy_of(victim):
		return
	var now := Time.get_ticks_msec() / 1000.0
	_multi_count = _multi_count + 1 if now - _last_kill_t < 4.0 else 1
	_last_kill_t = now
	var medals: Array = []
	if headshot:
		medals.append(["headshot", "Headshot!", "One Shot One Kill" if weapon_id == "sniper" else "", 0])
	elif weapon_id == "sniper":
		medals.append(["oneshot", "One Shot One Kill", "", 0])
	if weapon_id == "grenade":
		medals.append(["grenade", "Granatenkill", "", 0])
	if me.node != null and victim.node != null and is_instance_valid(me.node) and is_instance_valid(victim.node):
		var dist := (me.node as Node3D).global_position.distance_to((victim.node as Node3D).global_position)
		if dist >= 45.0 and weapon_id != "grenade":
			medals.append(["longshot", "Longshot", "%d m" % int(dist), 0])
	if _last_killer_of_me == victim_id:
		medals.append(["revenge", "Revenge", "Rache genommen", 0])
		_last_killer_of_me = 0
	if _multi_count >= 2:
		var names := {2: "Double Kill", 3: "Triple Kill", 4: "Multi Kill"}
		medals.append(["multi", String(names.get(_multi_count, "Mega Kill")), "", _multi_count])
	if me.killstreak in [5, 7, 10, 15, 20]:
		medals.append(["streak", "Killstreak", "%d ohne zu sterben" % me.killstreak, me.killstreak])
	# the most important ones first (at most three, in order of the list)
	for i in mini(medals.size(), 3):
		var m: Array = medals[i]
		if i > 0:
			await get_tree().create_timer(0.45).timeout
			if not is_inside_tree():
				return
		medal_hud.medal(String(m[0]), String(m[1]), String(m[2]), int(m[3]))


func _on_weapon_changed(weapon: Node) -> void:
	var w := weapon as Weapon
	if w == null:
		return
	weapon_label.text = w.data.display_name.to_upper()
	silhouette.set_weapon(w.data.weapon_id)
	_show_weapon_banner(w.data.display_name)
	_on_ammo_changed(w.magazine, w.reserve)


## Rounds at or below which the reload hint shows for this weapon.
static func reload_hint_threshold(w: Weapon) -> int:
	return maxi(RELOAD_HINT_MIN, ceili(w.data.magazine_size * RELOAD_HINT_FRACTION))


## Classic "press R to reload": fades in when the magazine is nearly empty (red and pulsing when empty), gone at once
## while reloading, after the reload and when the weapon is switched.
func _update_reload_hint(delta: float) -> void:
	var w: Weapon = null
	if _player != null and is_instance_valid(_player) and _player.alive:
		w = _player.weapon_manager.get_current_weapon()
	var want := w != null and not w.is_reloading() and w.state != Weapon.State.DRAWING and w.reserve > 0 \
			and w.magazine <= reload_hint_threshold(w) and not _player.weapon_manager.is_throwing_grenade() and MatchManager.state == MatchManager.State.RUNNING
	var before := _hint_alpha
	_hint_alpha = move_toward(_hint_alpha, 1.0 if want else 0.0, delta * (6.0 if want else 12.0))
	if _hint_alpha <= 0.0:
		reload_hint.visible = false
		_hint_age = 0.0
		return
	reload_hint.visible = true
	if before <= 0.0:
		_hint_age = 0.0
	_hint_age += delta
	var key := "R"
	var evs := InputMap.action_get_events("reload")
	if not evs.is_empty() and evs[0] is InputEventKey:
		key = (evs[0] as InputEventKey).as_text_physical_keycode().to_upper()
	reload_hint.text = "%s ZUM NACHLADEN" % key
	var empty := w != null and w.magazine <= 0
	var pulse := 0.5 + 0.5 * sin(_hint_age * 7.0)
	var col := UITheme.DANGER.lerp(Color(1.0, 0.45, 0.35), pulse) if empty else Color(0.97, 0.85, 0.6)
	reload_hint.add_theme_color_override("font_color", col)
	reload_hint.add_theme_font_size_override("font_size", 36 if empty else 26)
	var k := crosshair.size.y / 1080.0
	reload_hint.scale = Vector2.ONE * (1.0 + 0.3 * maxf(0.0, 1.0 - _hint_age * 5.0)) * maxf(k, 0.5) # pops in
	reload_hint.position = Vector2(crosshair.size.x * 0.5 - 260.0, crosshair.size.y * 0.66)
	reload_hint.modulate.a = _hint_alpha * (0.75 + 0.25 * pulse if empty else 0.9)


## The weapon name drops in above the ammo panel, stays a moment and slides away again (round start, weapon change).
## Spectator: no health, ammo or crosshair, only the scores, the killfeed and the map.
func set_spectator(on: bool) -> void:
	_spectator = on
	for k in ["health", "ammo"]:
		(_blocks[k]["node"] as Control).visible = not on
	crosshair.visible = not on
	if on:
		hint_label.text = "ZUSCHAUER   WASD fliegen  •  Leertaste hoch  •  Strg runter  •  Shift schnell  •  Mausrad Tempo  •  F1 HUD aus/an"
		get_tree().create_timer(12.0).timeout.connect(func() -> void: if is_instance_valid(hint_label): hint_label.text = "")


const ZONE_NAMES := {"head": "KOPF", "chest": "BRUST", "belly": "BAUCH", "upper_arm": "OBERARM", "forearm": "UNTERARM", "thigh": "OBERSCHENKEL", "shin": "WADE", "foot": "FUSS"}
var _train_label: Label
var _train_tween: Tween


## Training: zone, damage and distance of the last hit on a dummy (below the crosshair) and a number that floats up at the dummy.
func _on_training_hit(zone: String, amount: float, distance: float, world_pos: Vector3, killed: bool) -> void:
	if _train_label == null:
		_train_label = UITheme.label("", 26, Color(0.95, 0.95, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
		_train_label.set_anchors_preset(Control.PRESET_CENTER)
		_train_label.custom_minimum_size = Vector2(700, 40)
		_train_label.position = Vector2(-350, 120)
		add_child(_train_label)
	var zn: String = ZONE_NAMES.get(zone, zone.to_upper())
	_train_label.text = "%s   −%d%s   •   %d m" % [zn, int(round(amount)), "   TÖDLICH" if killed else "", int(round(distance))]
	_train_label.modulate = Color(1.0, 0.45, 0.35) if zone == "head" else Color.WHITE
	if _train_tween != null:
		_train_tween.kill()
	_train_label.modulate.a = 1.0
	_train_tween = create_tween()
	_train_tween.tween_interval(1.6)
	_train_tween.tween_property(_train_label, "modulate:a", 0.0, 0.5)
	var l3 := Label3D.new()
	l3.text = "%s %d" % [zn, int(round(amount))]
	l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l3.no_depth_test = true
	l3.pixel_size = 0.004
	l3.font_size = 48
	l3.outline_size = 10
	l3.modulate = Color(1.0, 0.5, 0.35) if zone == "head" else Color(0.95, 0.95, 0.9)
	var parent := get_tree().get_first_node_in_group("effects_container")
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(l3)
	l3.global_position = world_pos + Vector3(0, 0.3, 0)
	var tw := l3.create_tween().set_parallel(true)
	tw.tween_property(l3, "position:y", l3.position.y + 0.9, 1.0)
	tw.tween_property(l3, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.chain().tween_callback(l3.queue_free)


func _show_weapon_banner(text: String) -> void:
	if _spectator:
		return
	var panel: Control = _blocks["ammo"]["node"]
	if _banner == null:
		_banner = UITheme.label("", 22, Color(0.92, 0.92, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
		_banner.add_theme_constant_override("outline_size", 5)
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_banner)
	_banner.text = text.to_upper()
	_banner.size = Vector2(panel.size.x, 30)
	var rest := panel.global_position - global_position + Vector2(-12, -34)
	_banner.position = rest + Vector2(0, 26)
	_banner.modulate.a = 0.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "position:y", rest.y, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.parallel().tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(1.5)
	_banner_tween.tween_property(_banner, "position:y", rest.y + 22.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.parallel().tween_property(_banner, "modulate:a", 0.0, 0.3)


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	ammo_label.text = "%d | %d" % [magazine, reserve]
	ammo_label.add_theme_color_override("font_color", UITheme.DANGER if magazine == 0 else (UITheme.ACCENT if magazine <= 5 else UITheme.TEXT))


## Feedback for a picked-up magazine: a small magazine with "+1" pops up beside the ammo display (and the display glows).
func _on_ammo_picked(_amount: int) -> void:
	var fx := MagPickupFx.new()
	add_child(fx)
	var kk := clampf(size.y / 1080.0, 0.7, 1.5)
	fx.scale = Vector2.ONE * kk * 1.25
	fx.global_position = Vector2(size.x * 0.5 + 95.0 * kk, size.y * 0.5 + 38.0 * kk) # a little off the crosshair
	ammo_label.pivot_offset = Vector2(ammo_label.size.x, ammo_label.size.y * 0.5)
	ammo_label.modulate = Color(0.65, 1.0, 0.75)
	ammo_label.scale = Vector2(1.1, 1.1)
	var tw := ammo_label.create_tween().set_parallel(true)
	tw.tween_property(ammo_label, "modulate", Color.WHITE, 0.7)
	tw.tween_property(ammo_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)


func _on_grenades_changed(count: int) -> void:
	_grenade_count = count
	_refresh_grenade_label()


func _on_flashbangs_changed(count: int) -> void:
	_flash_count = count
	_refresh_grenade_label()


func _refresh_grenade_label() -> void:
	grenade_label.text = "GRANATEN  %d    BLENDGRANATE  %d" % [_grenade_count, _flash_count]


func _on_participant_killed(victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	_evaluate_medals(victim_id, killer_id, weapon_id, headshot)
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
func _draw_health_ticks() -> void:
	var total_ticks := 40
	var active_ticks := int(round(_health_ratio * float(total_ticks)))
	var w := health_ticks_bar.size.x
	var h := health_ticks_bar.size.y
	var step := w / float(total_ticks)
	var tick_w := maxf(2.0, step * 0.55)
	var active_col := Color(0.95, 0.97, 1.0, 0.95) if _health_ratio > 0.3 else UITheme.DANGER
	var dim_col := Color(1.0, 1.0, 1.0, 0.16)
	for i in total_ticks:
		var x := float(i) * step
		var rect := Rect2(Vector2(x, 2.0), Vector2(tick_w, h - 4.0))
		health_ticks_bar.draw_rect(rect, active_col if i < active_ticks else dim_col)


func _draw_compass() -> void:
	var w := compass_bar.size.x
	var cx := w * 0.5
	var yaw_deg := 0.0
	if _player != null and is_instance_valid(_player):
		yaw_deg = fposmod(-rad_to_deg(_player.rotation.y), 360.0)

	var font := ThemeDB.fallback_font
	compass_bar.draw_line(Vector2(cx, 0.0), Vector2(cx, 6.0), UITheme.ACCENT, 2.0)
	compass_bar.draw_string(font, Vector2(cx - 18.0, 18.0), "%03d°" % int(round(yaw_deg)), HORIZONTAL_ALIGNMENT_CENTER, 36.0, 12, UITheme.ACCENT)

	var dirs := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	var px_per_deg := 2.4
	for offset_deg in range(-75, 76, 5):
		var deg := int(posmod(roundi(yaw_deg) + offset_deg, 360))
		var x := cx + float(offset_deg) * px_per_deg
		var edge_fade := 1.0 - clampf(absf(float(offset_deg)) / 75.0, 0.0, 1.0)
		if deg % 45 == 0 and dirs.has(deg):
			var label: String = dirs[deg]
			var is_cardinal := label.length() == 1
			compass_bar.draw_string(font, Vector2(x - 12.0, 32.0), label, HORIZONTAL_ALIGNMENT_CENTER, 24.0, 14 if is_cardinal else 11, Color(1, 1, 1, 0.95 * edge_fade))
		elif deg % 15 == 0:
			compass_bar.draw_line(Vector2(x, 22.0), Vector2(x, 29.0), Color(1, 1, 1, 0.55 * edge_fade), 1.5)
		else:
			compass_bar.draw_line(Vector2(x, 25.0), Vector2(x, 29.0), Color(1, 1, 1, 0.25 * edge_fade), 1.0)
