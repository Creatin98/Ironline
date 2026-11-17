class_name PreviewPicker
extends HBoxContainer
## Row of selectable cards (preview image + title + optional badge).
## Used for maps and classes in the menus and for the map vote.

signal selected(id: String)

var selected_id: String = ""
var disabled: bool = false

var _cards: Dictionary = {} # id -> {"panel": PanelContainer, "badge": Label}
var _thumb: Vector2 = Vector2(200, 112)


## items: [{"id": String, "title": String, "texture": Texture2D (optional)}]
func setup(items: Array, thumb: Vector2 = Vector2(200, 112), title_size: int = 18) -> void:
	_thumb = thumb
	add_theme_constant_override("separation", 12)
	for c in get_children():
		c.queue_free()
	_cards.clear()
	for item in items:
		var id: String = item["id"]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.add_theme_stylebox_override("panel", _style(false, false))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(box)
		var tex := TextureRect.new()
		tex.custom_minimum_size = thumb
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if item.get("texture") != null:
			tex.texture = item["texture"]
		else:
			var ph := ColorRect.new()
			ph.color = Color(0.12, 0.14, 0.18)
			ph.custom_minimum_size = thumb
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(ph)
		box.add_child(tex)
		box.add_child(UITheme.label(String(item["title"]), title_size, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var badge := UITheme.label("", maxi(12, title_size - 4), UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
		box.add_child(badge)
		panel.gui_input.connect(func(event: InputEvent) -> void: _on_card_input(event, id))
		panel.mouse_entered.connect(func() -> void: _set_hover(id, true))
		panel.mouse_exited.connect(func() -> void: _set_hover(id, false))
		add_child(panel)
		_cards[id] = {"panel": panel, "badge": badge}
	if selected_id != "" and _cards.has(selected_id):
		set_selected(selected_id)


func _style(is_selected: bool, hover: bool) -> StyleBoxFlat:
	var border := UITheme.ACCENT if is_selected else (Color(1, 1, 1, 0.35) if hover else Color(1, 1, 1, 0.08))
	var bg := Color(0.20, 0.17, 0.12, 0.95) if is_selected else UITheme.BG_LIGHT
	var s := UITheme.panel_style(bg, 4, border, 3 if is_selected else 1)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func set_selected(id: String) -> void:
	selected_id = id
	for key in _cards:
		(_cards[key]["panel"] as PanelContainer).add_theme_stylebox_override("panel", _style(key == id, false))


func set_badge(id: String, text: String) -> void:
	if _cards.has(id):
		(_cards[id]["badge"] as Label).text = text


## Screen rectangle of a card (the end screen starts its big vote cards exactly over the small ones).
func card_global_rect(id: String) -> Rect2:
	if _cards.has(id):
		return (_cards[id]["panel"] as Control).get_global_rect()
	return Rect2()


func set_disabled(value: bool) -> void:
	disabled = value
	modulate = Color(1, 1, 1, 0.55) if value else Color.WHITE


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
