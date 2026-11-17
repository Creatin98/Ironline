class_name SettingsPanel
extends Control
## Settings UI used by the main menu and the pause menu: three tabs (Grafik, Sound, Spiel).
## Data driven: every control is registered in `_entries` with the GameSettings property it edits,
## so loading, applying, resetting and saving work the same for all of them.
## Sound sliders are applied live (and previewed); "Zurück" restores them, "Übernehmen" saves everything.

signal closed
signal hud_edit_requested

const TAB_NAMES: Array[String] = ["GRAFIK", "SOUND", "SPIEL"]
const LABEL_WIDTH := 300.0
const VALUE_WIDTH := 86.0

## Set by the pause menu: the HUD editor needs a running match.
var in_game: bool = false

var _panel: PanelContainer
var _scroll: ScrollContainer
var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _tab: int = 0
var _entries: Array[Dictionary] = [] # {kind, prop, ctrl, value_label, fmt, tab, values}
var _hud_edit_btn: Button
var _preset_entry: Dictionary = {}
var _resolution_entry: Dictionary = {}
var _loading: bool = false
var _volume_snapshot: Dictionary = {}
var _defaults: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defaults = (GameSettings.get_script() as GDScript).new() # untouched default values for "Standard"
	# dimmed backdrop (blocks clicks on the menu behind) + panel centred on screen
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UITheme.panel(Color(0.05, 0.06, 0.08, 0.98), 6)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)
	var root := UITheme.vbox(10)
	_panel.add_child(root)

	root.add_child(UITheme.label("EINSTELLUNGEN", 32, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var tabs := UITheme.hbox(6)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TAB_NAMES.size():
		var b := _tab_button(TAB_NAMES[i], group)
		var idx := i
		b.pressed.connect(func() -> void: _select_tab(idx))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 2)
	root.add_child(line)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for i in TAB_NAMES.size():
		var page := UITheme.vbox(6)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		_pages.append(page)
	_build_graphics(_pages[0])
	_build_sound(_pages[1])
	_build_game(_pages[2])

	var buttons := UITheme.hbox(16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var reset := UITheme.button("Reiter auf Standard", 18, 220)
	reset.pressed.connect(_reset_tab)
	buttons.add_child(reset)
	buttons.add_child(UITheme.spacer(30))
	var apply := UITheme.button("Übernehmen", 22, 220)
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var back := UITheme.button("Zurück", 22, 220)
	back.pressed.connect(_cancel)
	buttons.add_child(back)
	root.add_child(buttons)

	get_viewport().size_changed.connect(_resize_panel)
	_select_tab(0)
	_load_values()
	_resize_panel()


func _exit_tree() -> void:
	if _defaults != null and is_instance_valid(_defaults):
		_defaults.free()


# ----------------------------------------------------------------------------- pages

func _build_graphics(page: VBoxContainer) -> void:
	var g := _section(page, "Anzeige")
	var res_names: Array = []
	var res_values: Array = []
	for r in GameSettings.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
		res_values.append(r)
	_resolution_entry = _option(g, 0, "Auflösung (Fenstermodus)", "resolution", res_names, res_values)
	_option(g, 0, "Anzeigemodus", "window_mode", GameSettings.WINDOW_MODES, [0, 1, 2])
	_toggle(g, 0, "V-Sync", "vsync")
	var fps_names: Array = []
	for f in GameSettings.FPS_LIMITS:
		fps_names.append("Unbegrenzt" if f == 0 else "%d FPS" % f)
	_option(g, 0, "FPS-Begrenzung", "fps_limit", fps_names, GameSettings.FPS_LIMITS)
	_gap(page)
	var q := _section(page, "Qualität")
	_preset_entry = _option(q, 0, "Voreinstellung", "graphics_quality", ["Niedrig", "Mittel", "Hoch", "Benutzerdefiniert"], [0, 1, 2, 3])
	(_preset_entry["ctrl"] as OptionButton).item_selected.connect(_on_preset_selected)
	_slider(q, 0, "3D-Auflösung", "render_scale", 0.5, 1.0, 0.05, func(v: float) -> String: return "%d %%" % int(round(v * 100.0)))
	_option(q, 0, "Kantenglättung", "antialiasing", GameSettings.ANTIALIASING_NAMES, [0, 1, 2, 3])
	_option(q, 0, "Texturqualität", "texture_quality", GameSettings.QUALITY_NAMES, [0, 1, 2])
	_option(q, 0, "Schattenqualität", "shadow_quality", GameSettings.SHADOW_NAMES, [0, 1, 2, 3])
	_option(q, 0, "Effektqualität", "effects_quality", GameSettings.QUALITY_NAMES, [0, 1, 2])
	_option(q, 0, "Sichtweite", "view_distance", GameSettings.VIEW_DISTANCE_NAMES, [0, 1, 2, 3])
	_toggle(q, 0, "Post-Processing", "post_processing")


func _build_sound(page: VBoxContainer) -> void:
	var current_group := ""
	var grid: GridContainer = null
	for e in AudioCategories.ENTRIES:
		if e["group"] != current_group:
			if grid != null:
				_gap(page)
			current_group = e["group"]
			grid = _section(page, current_group)
		_volume(grid, e)
	var note := UITheme.label("Einige Umgebungsgeräusche folgen in späteren Versionen; ihre Regler sind schon vorbereitet.", 14, UITheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)


func _build_game(page: VBoxContainer) -> void:
	var p := _section(page, "Profil")
	_line(p, 2, "Spielername", "player_name")
	_gap(page)
	var c := _section(page, "Kamera")
	_slider(c, 2, "Sichtfeld (FOV)", "fov", 60.0, 110.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
	_toggle(c, 2, "Kamera-Bobbing", "camera_bob")
	_toggle(c, 2, "Waffen-Sway", "weapon_sway")
	_toggle(c, 2, "Bildschirmwackeln", "screen_shake")
	_toggle(c, 2, "Killcam", "killcams")
	_gap(page)
	var s := _section(page, "Steuerung")
	_slider(s, 2, "Maus-Empfindlichkeit", "mouse_sensitivity", 0.1, 4.0, 0.05, func(v: float) -> String: return "%.2f" % v)
	_slider(s, 2, "Empfindlichkeit beim Zielen", "ads_sensitivity", 0.3, 1.5, 0.05, func(v: float) -> String: return "%d %%" % int(round(v * 100.0)))
	_toggle(s, 2, "Y-Achse invertieren", "invert_y")
	_gap(page)
	var h := _section(page, "HUD")
	_toggle(h, 2, "HUD anzeigen", "show_hud")
	_slider(h, 2, "HUD-Skalierung", "hud_scale", 0.6, 1.6, 0.05, func(v: float) -> String: return "%d %%" % int(round(v * 100.0)))
	_slider(h, 2, "HUD-Abstand zum Rand", "hud_margin", 0.0, 120.0, 1.0, func(v: float) -> String: return "%d px" % int(v))
	_hud_edit_btn = UITheme.button("HUD anpassen …", 18, 280)
	_hud_edit_btn.pressed.connect(func() -> void: hud_edit_requested.emit())
	_row(h, "HUD verschieben", _hud_edit_btn, null)
	_toggle(h, 2, "Minimap", "show_minimap")
	_toggle(h, 2, "Killfeed", "show_killfeed")
	_toggle(h, 2, "Fadenkreuz", "show_crosshair")
	_toggle(h, 2, "Trefferanzeige (Hitmarker)", "show_hit_markers")
	_toggle(h, 2, "Schadensrichtung (Pfeile)", "show_damage_indicators")
	_toggle(h, 2, "Blut auf dem Bildschirm", "show_blood_overlay")
	_toggle(h, 2, "FPS-Anzeige", "show_fps")


# ----------------------------------------------------------------------------- widgets

func _tab_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(170, 46)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", UITheme.ACCENT)
	b.add_theme_color_override("font_focus_color", UITheme.TEXT_DIM)
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.07) if state in ["hover", "hover_pressed"] else (Color(1, 1, 1, 0.03) if state == "pressed" else Color(0, 0, 0, 0))
		sb.border_width_bottom = 4 if state in ["pressed", "hover_pressed"] else 0
		sb.border_color = UITheme.ACCENT
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func() -> void: AudioManager.play_ui("ui_click", -4.0))
	return b


func _section(page: VBoxContainer, title: String) -> GridContainer:
	page.add_child(UITheme.label(title.to_upper(), 19, UITheme.ACCENT))
	var rule := ColorRect.new()
	rule.color = Color(0.97, 0.63, 0.16, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	page.add_child(rule)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	return grid


func _gap(page: VBoxContainer) -> void:
	page.add_child(UITheme.spacer(14))


func _row(grid: GridContainer, title: String, control: Control, value_label: Label) -> void:
	var l := UITheme.label(title, 18, UITheme.TEXT)
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	if value_label == null:
		value_label = UITheme.label("", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(value_label)


func _register(e: Dictionary) -> Dictionary:
	_entries.append(e)
	return e


func _slider(grid: GridContainer, tab: int, title: String, prop: String, lo: float, hi: float, step: float, fmt: Callable) -> Dictionary:
	var s := UITheme.hslider(lo, hi, step, lo, 260)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label("", 18, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	_row(grid, title, s, val)
	var e := _register({"kind": "slider", "prop": prop, "ctrl": s, "value_label": val, "fmt": fmt, "tab": tab})
	s.value_changed.connect(func(_v: float) -> void: _changed(e))
	return e


func _toggle(grid: GridContainer, tab: int, title: String, prop: String) -> Dictionary:
	var c := UITheme.toggle("Aus")
	var e := _register({"kind": "check", "prop": prop, "ctrl": c, "tab": tab})
	c.toggled.connect(func(on: bool) -> void:
		c.text = "An" if on else "Aus"
		_changed(e))
	_row(grid, title, c, null)
	return e


func _option(grid: GridContainer, tab: int, title: String, prop: String, names: Array, values: Array) -> Dictionary:
	var o := UITheme.option(names, 0, 260)
	var e := _register({"kind": "option", "prop": prop, "ctrl": o, "values": values, "tab": tab})
	o.item_selected.connect(func(_i: int) -> void: _changed(e))
	_row(grid, title, o, null)
	return e


func _line(grid: GridContainer, tab: int, title: String, prop: String) -> Dictionary:
	var l := LineEdit.new()
	l.custom_minimum_size = Vector2(260, 40)
	l.max_length = 16
	l.add_theme_font_size_override("font_size", 19)
	var e := _register({"kind": "line", "prop": prop, "ctrl": l, "tab": tab})
	_row(grid, title, l, null)
	return e


## Volume slider 0..100 % for one sound category (applied live, previewed on release).
func _volume(grid: GridContainer, entry: Dictionary) -> void:
	var s := UITheme.hslider(0, 100, 1, 100, 260)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label("", 18, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	_row(grid, String(entry["label"]), s, val)
	var e := _register({"kind": "volume", "prop": String(entry["id"]), "ctrl": s, "value_label": val, "tab": 1})
	s.value_changed.connect(func(v: float) -> void:
		val.text = "%d %%" % int(v)
		if not _loading:
			GameSettings.set_volume(String(e["prop"]), v / 100.0))
	s.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			AudioManager.play_preview(String(e["prop"])))


# ----------------------------------------------------------------------------- behaviour

func _select_tab(i: int) -> void:
	_tab = i
	for k in _pages.size():
		_pages[k].visible = k == i
		_tab_buttons[k].set_pressed_no_signal(k == i)
	_scroll.scroll_vertical = 0


func _changed(e: Dictionary) -> void:
	_refresh_label(e)
	if _loading:
		return
	if GameSettings.GRAPHICS_PRESETS[0].has(e["prop"]):
		_set_control(_preset_entry, 3) # a manual change makes the preset "benutzerdefiniert"
	if e["prop"] == "window_mode":
		_update_enabled()


func _refresh_label(e: Dictionary) -> void:
	if e["kind"] == "slider":
		(e["value_label"] as Label).text = String((e["fmt"] as Callable).call((e["ctrl"] as HSlider).value))


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= GameSettings.GRAPHICS_PRESETS.size():
		return
	_loading = true
	var preset: Dictionary = GameSettings.GRAPHICS_PRESETS[index]
	for e in _entries:
		if preset.has(e["prop"]):
			_set_control(e, preset[e["prop"]])
	_loading = false
	_update_enabled()


func _update_enabled() -> void:
	var mode_entry := _find("window_mode")
	if not mode_entry.is_empty() and not _resolution_entry.is_empty():
		(_resolution_entry["ctrl"] as OptionButton).disabled = _get_control(mode_entry) != 1


func _find(prop: String) -> Dictionary:
	for e in _entries:
		if e["prop"] == prop:
			return e
	return {}


func _set_control(e: Dictionary, value: Variant) -> void:
	match e["kind"]:
		"slider":
			(e["ctrl"] as HSlider).value = float(value)
			_refresh_label(e)
		"volume":
			(e["ctrl"] as HSlider).value = float(value) * 100.0
			(e["value_label"] as Label).text = "%d %%" % int(round(float(value) * 100.0))
		"check":
			var c := e["ctrl"] as CheckButton
			c.set_pressed_no_signal(bool(value))
			c.text = "An" if bool(value) else "Aus"
		"option":
			var idx: int = (e["values"] as Array).find(value)
			(e["ctrl"] as OptionButton).selected = maxi(idx, 0)
		"line":
			(e["ctrl"] as LineEdit).text = String(value)


func _get_control(e: Dictionary) -> Variant:
	match e["kind"]:
		"slider":
			return (e["ctrl"] as HSlider).value
		"volume":
			return (e["ctrl"] as HSlider).value / 100.0
		"check":
			return (e["ctrl"] as CheckButton).button_pressed
		"option":
			return (e["values"] as Array)[(e["ctrl"] as OptionButton).selected]
		"line":
			var t := (e["ctrl"] as LineEdit).text.strip_edges()
			return t if t != "" else "Spieler"
	return null


func _settings_value(e: Dictionary) -> Variant:
	if e["kind"] == "volume":
		return GameSettings.get_volume(String(e["prop"]))
	return GameSettings.get(String(e["prop"]))


func _default_value(e: Dictionary) -> Variant:
	if e["kind"] == "volume":
		return float(AudioCategories.get_entry(String(e["prop"])).get("default", 1.0))
	return _defaults.get(String(e["prop"]))


func open() -> void:
	_hud_edit_btn.disabled = not in_game
	_hud_edit_btn.text = "HUD anpassen …" if in_game else "HUD anpassen (im Spiel)"
	_volume_snapshot = GameSettings.volumes.duplicate()
	_load_values()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # always cover the whole screen
	_resize_panel()
	visible = true


func _load_values() -> void:
	_loading = true
	for e in _entries:
		_set_control(e, _settings_value(e))
	_loading = false
	_update_enabled()


## "Reiter auf Standard": resets the controls of the current tab (applied when "Übernehmen" is pressed;
## sound sliders are heard at once).
func _reset_tab() -> void:
	_loading = true
	for e in _entries:
		if int(e["tab"]) == _tab:
			_set_control(e, _default_value(e))
			if e["kind"] == "volume":
				GameSettings.set_volume(String(e["prop"]), float(_default_value(e)))
	_loading = false
	_update_enabled()


func _apply() -> void:
	for e in _entries:
		if e["kind"] == "volume":
			GameSettings.set_volume(String(e["prop"]), float(_get_control(e)))
		else:
			GameSettings.set(String(e["prop"]), _get_control(e))
	GameSettings.save()
	closed.emit() # "Übernehmen" applies and closes the window


## Back without saving: sound changes that were already audible are undone.
func _cancel() -> void:
	for id in _volume_snapshot:
		GameSettings.set_volume(String(id), float(_volume_snapshot[id]))
	closed.emit()


## Panel size follows the window: never larger than the screen, scrolls when the content is taller.
func _resize_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(clampf(vp.x * 0.92, 600.0, 1060.0), clampf(vp.y * 0.9, 380.0, 940.0))
