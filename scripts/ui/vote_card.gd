class_name VoteCard
extends Control
## Large map card of the final map vote: preview picture, name, vote badge and a "your vote" marker.
## Free-floating (position and size are animated by the end screen) and keeps the proportions of
## picture and title at every size. `expand` = 1 turns it into a plain full-screen picture without frame
## and title - the same picture the loading screen shows, so the hand-over is seamless.

signal pressed(id: String)

## width / height: the 16:9 picture takes IMAGE_FRAC of the height, the title the rest.
const ASPECT := 1.4222
const IMAGE_FRAC := 0.8
const INSET := 6.0

var map_id: String = ""
var disabled: bool = false
## 0 = card, 1 = full-screen picture.
var expand: float = 0.0:
	set(v):
		expand = v
		_style()
		_layout()

var _frame: Panel
var _image: TextureRect
var _title: Label
var _badge_chip: PanelContainer
var _badge: Label
var _mine_chip: PanelContainer
var _shine: TextureRect
var _selected: bool = false
var _hover: bool = false


func setup(id: String, title_text: String, texture: Texture2D) -> void:
	map_id = id
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.texture = texture
	_image.clip_contents = true
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_title = UITheme.label(title_text, 30, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_title)
	_badge_chip = _chip(UITheme.ACCENT)
	_badge = _badge_chip.get_child(0) as Label
	_badge_chip.visible = false
	add_child(_badge_chip)
	_mine_chip = _chip(Color(0.5, 0.85, 0.5))
	(_mine_chip.get_child(0) as Label).text = "✓ DEINE STIMME"
	_mine_chip.visible = false
	add_child(_mine_chip)
	# a soft light bar that sweeps over the picture (played when this map wins)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	_shine = TextureRect.new()
	_shine.texture = gt
	_shine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shine.stretch_mode = TextureRect.STRETCH_SCALE
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.visible = false
	_image.add_child(_shine)
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	_style()
	_layout()


func _chip(text_color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.04, 0.05, 0.07, 0.86), 4))
	var l := UITheme.label("", 18, text_color, HORIZONTAL_ALIGNMENT_CENTER)
	chip.add_child(l)
	return chip


func set_selected(value: bool) -> void:
	_selected = value
	_mine_chip.visible = value
	_style()
	_layout()


## Darkens the card while another map is the own pick.
func set_dimmed(value: bool) -> void:
	_image.modulate = Color(0.62, 0.62, 0.66) if value else Color.WHITE


func set_badge(text: String) -> void:
	_badge.text = text
	_badge_chip.visible = text != ""
	_badge_chip.reset_size()
	_layout()


func _set_hover(value: bool) -> void:
	_hover = value
	_style()


func _style() -> void:
	if _frame == null:
		return
	var border := UITheme.ACCENT if _selected else (Color(1, 1, 1, 0.55) if _hover and not disabled else Color(1, 1, 1, 0.16))
	border.a *= 1.0 - expand
	var bg := Color(0.16, 0.13, 0.08, 0.97) if _selected else Color(0.07, 0.08, 0.1, 0.97)
	bg.a *= 1.0 - expand
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(lerpf(6.0, 0.0, expand)))
	sb.set_border_width_all(4 if _selected else 2)
	sb.border_color = border
	if _selected and expand < 0.5:
		sb.shadow_color = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.5)
		sb.shadow_size = 22
	_frame.add_theme_stylebox_override("panel", sb)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	if _frame == null:
		return
	var s := size
	var inset := lerpf(INSET, 0.0, expand)
	_frame.position = Vector2.ZERO
	_frame.size = s
	var image_bottom := lerpf(s.y * IMAGE_FRAC, s.y, expand)
	_image.position = Vector2(inset, inset)
	_image.size = Vector2(maxf(0.0, s.x - 2.0 * inset), maxf(0.0, image_bottom - inset))
	_shine.size = Vector2(_image.size.x * 0.3, _image.size.y)
	_title.position = Vector2(0.0, s.y * IMAGE_FRAC)
	_title.size = Vector2(s.x, s.y * (1.0 - IMAGE_FRAC))
	_title.modulate.a = 1.0 - expand
	_title.add_theme_font_size_override("font_size", clampi(int(s.x * 0.075), 14, 46))
	var chip_font := clampi(int(s.x * 0.04), 12, 26)
	(_badge_chip.get_child(0) as Label).add_theme_font_size_override("font_size", chip_font)
	(_mine_chip.get_child(0) as Label).add_theme_font_size_override("font_size", chip_font)
	_badge_chip.reset_size()
	_mine_chip.reset_size()
	_badge_chip.position = Vector2(s.x - _badge_chip.size.x - inset - 8.0, inset + 8.0)
	_mine_chip.position = Vector2(inset + 8.0, inset + 8.0)
	_badge_chip.modulate.a = 1.0 - expand
	_mine_chip.modulate.a = 1.0 - expand


## One light sweep over the picture.
func play_shine(duration: float = 0.7) -> void:
	_shine.visible = true
	_shine.position = Vector2(-_shine.size.x, 0.0)
	var tw := create_tween()
	tw.tween_property(_shine, "position:x", _image.size.x, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_hide_shine)


func _hide_shine() -> void:
	_shine.visible = false


func _on_gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(map_id)
