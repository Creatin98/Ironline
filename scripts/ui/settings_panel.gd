class_name SettingsPanel
extends Control
## Settings UI used by the main menu and the pause menu. Writes to GameSettings
## and saves persistently when "Übernehmen" is pressed.

signal closed

var _sens: HSlider
var _sens_val: Label
var _invert: CheckBox
var _fov: HSlider
var _fov_val: Label
var _res: OptionButton
var _fullscreen: CheckBox
var _quality: OptionButton
var _master: HSlider
var _music: HSlider
var _sfx: HSlider
var _hud: HSlider
var _hud_val: Label
var _bob: CheckBox
var _sway: CheckBox
var _shake: CheckBox
var _fps: CheckBox
var _killcams: CheckBox
var _name: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# dimmed backdrop (blocks clicks on the menu behind) + panel centred on screen
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UITheme.panel(Color(0.05, 0.06, 0.08, 0.97), 6)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(840, 0)
	center.add_child(panel)
	var v := UITheme.vbox(10)
	panel.add_child(v)
	v.add_child(UITheme.label("EINSTELLUNGEN", 34, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UITheme.spacer(6))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(300, 40)
	_name.max_length = 16
	_name.add_theme_font_size_override("font_size", 20)
	_row(grid, "Spielername", _name, null)

	_sens = UITheme.hslider(0.1, 4.0, 0.05, GameSettings.mouse_sensitivity, 300)
	_sens_val = UITheme.label("", 18)
	_sens.value_changed.connect(func(v2: float) -> void: _sens_val.text = "%.2f" % v2)
	_row(grid, "Maus-Sensitivität", _sens, _sens_val)
	_invert = _check("Y-Achse invertieren")
	_row(grid, "Maus-Invertierung", _invert, null)
	_fov = UITheme.hslider(60, 110, 1, GameSettings.fov, 300)
	_fov_val = UITheme.label("", 18)
	_fov.value_changed.connect(func(v2: float) -> void: _fov_val.text = "%d°" % int(v2))
	_row(grid, "Sichtfeld (FOV)", _fov, _fov_val)

	var res_names: Array = []
	for r in GameSettings.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
	_res = UITheme.option(res_names, GameSettings.get_resolution_index(), 300)
	_row(grid, "Auflösung", _res, null)
	_fullscreen = _check("Vollbild")
	_row(grid, "Anzeigemodus", _fullscreen, null)
	_quality = UITheme.option(["Niedrig", "Mittel", "Hoch"], GameSettings.graphics_quality, 300)
	_row(grid, "Grafikqualität", _quality, null)

	_master = UITheme.hslider(0, 1, 0.01, GameSettings.master_volume, 300)
	_row(grid, "Lautstärke", _master, null)
	_music = UITheme.hslider(0, 1, 0.01, GameSettings.music_volume, 300)
	_row(grid, "Musik", _music, null)
	_sfx = UITheme.hslider(0, 1, 0.01, GameSettings.sfx_volume, 300)
	_row(grid, "Effekte", _sfx, null)

	_hud = UITheme.hslider(0.6, 1.6, 0.05, GameSettings.hud_scale, 300)
	_hud_val = UITheme.label("", 18)
	_hud.value_changed.connect(func(v2: float) -> void: _hud_val.text = "%d %%" % int(round(v2 * 100.0)))
	_row(grid, "HUD-Skalierung", _hud, _hud_val)
	_bob = _check("Aktiv")
	_row(grid, "Kamera-Bobbing", _bob, null)
	_sway = _check("Aktiv")
	_row(grid, "Weapon-Sway", _sway, null)
	_shake = _check("Aktiv")
	_row(grid, "Bildschirmwackeln", _shake, null)
	_fps = _check("Anzeigen")
	_row(grid, "FPS-Anzeige", _fps, null)
	_killcams = _check("Aktiv")
	_row(grid, "Killcam", _killcams, null)

	v.add_child(UITheme.spacer(10))
	var buttons := UITheme.hbox(20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var apply := UITheme.button("Übernehmen", 22, 240)
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var back := UITheme.button("Zurück", 22, 240)
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)
	v.add_child(buttons)
	_load_values()


func _check(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 18)
	return c


func _row(grid: GridContainer, title: String, control: Control, value_label: Label) -> void:
	var l := UITheme.label(title, 19, UITheme.TEXT)
	l.custom_minimum_size = Vector2(240, 36)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	grid.add_child(control)
	if value_label == null:
		value_label = UITheme.label("", 18)
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(value_label)


func open() -> void:
	_load_values()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # always cover the whole screen
	visible = true


func _load_values() -> void:
	_name.text = GameSettings.player_name
	_sens.value = GameSettings.mouse_sensitivity
	_sens_val.text = "%.2f" % GameSettings.mouse_sensitivity
	_invert.button_pressed = GameSettings.invert_y
	_fov.value = GameSettings.fov
	_fov_val.text = "%d°" % int(GameSettings.fov)
	_res.selected = GameSettings.get_resolution_index()
	_fullscreen.button_pressed = GameSettings.fullscreen
	_quality.selected = GameSettings.graphics_quality
	_master.value = GameSettings.master_volume
	_music.value = GameSettings.music_volume
	_sfx.value = GameSettings.sfx_volume
	_hud.value = GameSettings.hud_scale
	_hud_val.text = "%d %%" % int(round(GameSettings.hud_scale * 100.0))
	_bob.button_pressed = GameSettings.camera_bob
	_sway.button_pressed = GameSettings.weapon_sway
	_shake.button_pressed = GameSettings.screen_shake
	_fps.button_pressed = GameSettings.show_fps
	_killcams.button_pressed = GameSettings.killcams


func _apply() -> void:
	GameSettings.player_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Spieler"
	GameSettings.mouse_sensitivity = _sens.value
	GameSettings.invert_y = _invert.button_pressed
	GameSettings.fov = _fov.value
	GameSettings.resolution = GameSettings.RESOLUTIONS[_res.selected]
	GameSettings.fullscreen = _fullscreen.button_pressed
	GameSettings.graphics_quality = _quality.selected
	GameSettings.master_volume = _master.value
	GameSettings.music_volume = _music.value
	GameSettings.sfx_volume = _sfx.value
	GameSettings.hud_scale = _hud.value
	GameSettings.camera_bob = _bob.button_pressed
	GameSettings.weapon_sway = _sway.button_pressed
	GameSettings.screen_shake = _shake.button_pressed
	GameSettings.show_fps = _fps.button_pressed
	GameSettings.killcams = _killcams.button_pressed
	GameSettings.save()
