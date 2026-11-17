class_name UITheme
## Shared colours and small factory helpers so every screen looks the same.

const ACCENT := Color(0.97, 0.63, 0.16)
const ACCENT_DIM := Color(0.97, 0.63, 0.16, 0.6)
const TEXT := Color(0.94, 0.94, 0.92)
const TEXT_DIM := Color(0.7, 0.72, 0.75)
const BG := Color(0.06, 0.07, 0.09, 0.82)
const BG_SOLID := Color(0.08, 0.09, 0.11, 1.0)
const BG_LIGHT := Color(0.14, 0.16, 0.19, 0.9)
const DANGER := Color(0.9, 0.2, 0.15)
const SUCCESS := Color(0.35, 0.8, 0.4)


static func panel_style(bg: Color = BG, radius: int = 4, border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_width)
	s.border_color = border
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func label(text: String, size: int = 20, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4 if size >= 28 else 3)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, size: int = 22, min_width: float = 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 48)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	var normal := panel_style(BG_LIGHT, 3, Color(1, 1, 1, 0.08), 1)
	var hover := panel_style(Color(0.2, 0.22, 0.26, 0.95), 3, ACCENT, 1)
	var pressed := panel_style(Color(0.25, 0.2, 0.12, 1.0), 3, ACCENT, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(func() -> void: AudioManager.play_ui("ui_click"))
	b.mouse_entered.connect(func() -> void: AudioManager.play_ui("ui_hover", -8.0))
	return b


static func panel(bg: Color = BG, radius: int = 4) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, radius))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func option(items: Array, selected: int = 0, min_width: float = 260.0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = selected
	o.custom_minimum_size = Vector2(min_width, 44)
	o.add_theme_font_size_override("font_size", 20)
	o.add_theme_stylebox_override("normal", panel_style(BG_LIGHT, 3, Color(1, 1, 1, 0.08), 1))
	o.add_theme_stylebox_override("hover", panel_style(Color(0.2, 0.22, 0.26, 0.95), 3, ACCENT, 1))
	o.add_theme_stylebox_override("pressed", panel_style(Color(0.25, 0.2, 0.12, 1.0), 3, ACCENT, 1))
	o.add_theme_stylebox_override("focus", panel_style(Color(0.2, 0.22, 0.26, 0.95), 3, ACCENT, 1))
	return o


## Class dropdown: items in GameDirector order, current class preselected.
static func class_option(current_class_id: String, min_width: float = 320.0) -> OptionButton:
	var names: Array = []
	for id in GameDirector.get_class_ids():
		names.append(GameDirector.get_class_data(id).display_name)
	var o := option(names, maxi(0, GameDirector.get_class_ids().find(current_class_id)), min_width)
	return o


static func hslider(min_value: float, max_value: float, step: float, value: float, min_width: float = 260.0) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(min_width, 32)
	return s


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func format_time(seconds: float) -> String:
	var s := int(ceil(maxf(0.0, seconds)))
	return "%d:%02d" % [s / 60, s % 60]
