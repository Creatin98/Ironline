class_name PauseMenu
extends Control
## Escape menu during a match. The game keeps running (multiplayer-safe);
## only the local player's controls are disabled while it is open.

signal resumed
signal leave_requested
signal class_selected(class_id: String)

var settings_panel: SettingsPanel
var main_box: VBoxContainer
var class_opt: OptionButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	main_box = UITheme.vbox(14)
	main_box.set_anchors_preset(Control.PRESET_CENTER)
	main_box.position = Vector2(-160, -160)
	main_box.custom_minimum_size = Vector2(320, 0)
	add_child(main_box)
	main_box.add_child(UITheme.label("PAUSE", 40, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	main_box.add_child(UITheme.spacer(10))
	var resume := UITheme.button("Weiter", 22, 320)
	resume.pressed.connect(func() -> void: resumed.emit())
	main_box.add_child(resume)
	main_box.add_child(UITheme.label("Klasse (ab nächstem Respawn)", 16, UITheme.TEXT_DIM))
	class_opt = UITheme.class_option(GameSettings.preferred_class_id)
	class_opt.item_selected.connect(func(i: int) -> void: class_selected.emit(GameDirector.get_class_ids()[i]))
	main_box.add_child(class_opt)
	var settings := UITheme.button("Einstellungen", 22, 320)
	settings.pressed.connect(_open_settings)
	main_box.add_child(settings)
	var leave := UITheme.button("Match verlassen" if not NetworkManager.is_online() else "Online-Match verlassen", 22, 320)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	main_box.add_child(leave)
	settings_panel = SettingsPanel.new()
	settings_panel.visible = false
	settings_panel.closed.connect(func() -> void:
		settings_panel.visible = false
		main_box.visible = true)
	add_child(settings_panel)


func _open_settings() -> void:
	main_box.visible = false
	settings_panel.open()


func open() -> void:
	class_opt.selected = maxi(0, GameDirector.get_class_ids().find(GameSettings.preferred_class_id))
	visible = true
	main_box.visible = true
	settings_panel.visible = false


func close() -> void:
	visible = false
