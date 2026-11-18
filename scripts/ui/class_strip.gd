class_name ClassStrip
extends HBoxContainer
## Row of detailed class cards in the style of the HUD (dark panel, accent frame when selected):
## picture, name, weapons, damage/rate of fire and the equipment. Used for the class choice at the end of a match.

signal selected(id: String)

var selected_id: String = ""
var disabled: bool = false

var _cards: Dictionary = {} # id -> {"panel": PanelContainer, "name": Label}


func setup(class_ids: Array) -> void:
	add_theme_constant_override("separation", 14)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_cards.clear()
	for id in class_ids:
		var cls := GameDirector.get_class_data(String(id))
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.add_theme_stylebox_override("panel", _style(false, false))
		var row := UITheme.hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(130, 73)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture = GameDirector.get_class_preview(String(id))
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
		var col := UITheme.vbox(1)
		col.custom_minimum_size = Vector2(280, 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var name_label := UITheme.label(cls.display_name.to_upper(), 20, UITheme.TEXT)
		col.add_child(name_label)
		for line in [
			[cls.primary.display_name + "  •  " + cls.secondary.display_name, 14, UITheme.TEXT_DIM],
			["%s  •  %d/min  •  %s" % [_damage_text(cls.primary), int(cls.primary.rpm), _mag_text(cls.primary)], 13, UITheme.TEXT_DIM],
			[_equipment_text(cls), 13, UITheme.ACCENT_DIM],
		]:
			var l := UITheme.label(String(line[0]), int(line[1]), line[2] as Color)
			l.clip_text = true # long weapon names never widen the card
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			col.add_child(l)
		panel.gui_input.connect(func(event: InputEvent) -> void: _on_card_input(event, String(id)))
		panel.mouse_entered.connect(func() -> void: _set_hover(String(id), true))
		panel.mouse_exited.connect(func() -> void: _set_hover(String(id), false))
		add_child(panel)
		_cards[String(id)] = {"panel": panel, "name": name_label}
	if selected_id != "":
		set_selected(selected_id)


static func _damage_text(w: WeaponData) -> String:
	if w.pellets > 1:
		return "%d×%d Schaden" % [w.pellets, int(w.damage)]
	if int(w.min_damage) == int(w.damage):
		return "Schaden %d" % int(w.damage)
	return "Schaden %d–%d" % [int(w.min_damage), int(w.damage)]


static func _mag_text(w: WeaponData) -> String:
	return "%d Schuss" % w.magazine_size


static func _equipment_text(cls: ClassData) -> String:
	var parts: Array[String] = []
	if cls.grenades > 0:
		parts.append("%d× Granate" % cls.grenades)
	if cls.flashbangs > 0:
		parts.append("%d× Blendgranate" % cls.flashbangs)
	return "  •  ".join(parts)


func _style(is_selected: bool, hover: bool) -> StyleBoxFlat:
	var border := UITheme.ACCENT if is_selected else (Color(1, 1, 1, 0.4) if hover else Color(1, 1, 1, 0.12))
	var bg := Color(0.17, 0.14, 0.09, 0.95) if is_selected else Color(0.05, 0.06, 0.08, 0.92)
	var sb := UITheme.panel_style(bg, 6, border, 3 if is_selected else 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func set_selected(id: String) -> void:
	selected_id = id
	for key in _cards:
		var on: bool = key == id
		(_cards[key]["panel"] as PanelContainer).add_theme_stylebox_override("panel", _style(on, false))
		(_cards[key]["name"] as Label).add_theme_color_override("font_color", UITheme.ACCENT if on else UITheme.TEXT)


func _set_hover(id: String, hover: bool) -> void:
	if disabled or not _cards.has(id):
		return
	(_cards[id]["panel"] as PanelContainer).add_theme_stylebox_override("panel", _style(id == selected_id, hover))


func _on_card_input(event: InputEvent, id: String) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		set_selected(id)
		AudioManager.play_ui("ui_click")
		selected.emit(id)
