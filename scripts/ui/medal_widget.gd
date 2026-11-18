class_name MedalWidget
extends Control
## One medal (shield with an icon, a glowing title and a subtitle), drawn entirely in code: dark metal shield with a bevelled
## rim, a coloured accent line, a soft bloom behind it and a white flash when it pops in. Kinds: headshot, oneshot, multi,
## streak, longshot, grenade, revenge. MedalHud places and ages it.

const LIFE := 2.4
const SIZE := Vector2(240, 214)

var kind: String = "headshot"
var title: String = ""
var subtitle: String = ""
var number: int = 0 # multi kill / streak count
var accent: Color = Color(0.45, 1.0, 0.55)
var age: float = 0.0
var _glow: TextureRect
var _title_label: Label
var _glow_title: Label
var _sub_label: Label
static var _glow_tex: GradientTexture2D


func setup(p_kind: String, p_title: String, p_sub: String = "", p_number: int = 0) -> void:
	kind = p_kind
	title = p_title
	subtitle = p_sub
	number = p_number
	accent = {
		"headshot": Color(0.45, 1.0, 0.55), "oneshot": Color(1.0, 0.78, 0.3), "multi": Color(1.0, 0.45, 0.25),
		"streak": Color(0.55, 0.82, 1.0), "longshot": Color(0.4, 0.95, 1.0), "grenade": Color(1.0, 0.6, 0.2), "revenge": Color(0.95, 0.3, 0.5),
	}.get(kind, Color(1, 0.8, 0.4))


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = Vector2(SIZE.x * 0.5, 72.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = TextureRect.new()
	_glow.texture = _glow_tex
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.size = Vector2(300, 300)
	_glow.position = Vector2(SIZE.x * 0.5 - 150.0, 72.0 - 150.0)
	_glow.material = add
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate = Color(accent.r, accent.g, accent.b, 0.0)
	add_child(_glow)
	_glow_title = UITheme.label(title.to_upper(), 30, Color(accent.r, accent.g, accent.b, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	_glow_title.add_theme_constant_override("outline_size", 14)
	_glow_title.add_theme_color_override("font_outline_color", Color(accent.r, accent.g, accent.b, 0.2))
	_glow_title.material = add.duplicate()
	_glow_title.position = Vector2(0, 144)
	_glow_title.size = Vector2(SIZE.x, 40)
	_glow_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow_title)
	_title_label = UITheme.label(title.to_upper(), 30, Color(0.97, 0.97, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	_title_label.add_theme_constant_override("outline_size", 6)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title_label.position = Vector2(0, 144)
	_title_label.size = Vector2(SIZE.x, 40)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)
	_sub_label = UITheme.label(subtitle, 17, Color(0.78, 0.8, 0.82, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	_sub_label.add_theme_constant_override("outline_size", 4)
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_sub_label.position = Vector2(0, 182)
	_sub_label.size = Vector2(SIZE.x, 26)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_label)


func _process(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	var pop := clampf(age / 0.2, 0.0, 1.0)
	var back := 1.0 - pow(1.0 - pop, 3.0)
	var s := lerpf(1.9, 1.0, back) + 0.05 * sin(clampf((age - 0.2) / 0.3, 0.0, 1.0) * PI)
	scale = Vector2(s, s) * scale_base
	var fade_in := clampf(age / 0.07, 0.0, 1.0)
	var fade_out := clampf((LIFE - age) / 0.5, 0.0, 1.0)
	modulate.a = fade_in * fade_out
	_glow.modulate.a = (0.62 * (1.0 - pow(clampf(age / 1.6, 0.0, 1.0), 2.0)) + 0.1 * sin(age * 6.0)) * (1.0 if age > 0.04 else 0.0)
	queue_redraw()


var scale_base: float = 1.0


func _draw() -> void:
	var c := Vector2(SIZE.x * 0.5, 72.0)
	var w := 104.0
	var h := 124.0
	var pts := _shield(c, w, h)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 5))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.55))
	# bevelled rim: light at the top, dark at the bottom
	var rim_cols := PackedColorArray()
	for p in pts:
		var t := clampf((p.y - (c.y - h * 0.5)) / h, 0.0, 1.0)
		rim_cols.append(Color(0.62, 0.64, 0.66).lerp(Color(0.16, 0.17, 0.19), t))
	draw_polygon(pts, rim_cols)
	draw_polyline(_closed(pts), Color(0, 0, 0, 0.9), 2.0, true)
	var inner := _shield(c + Vector2(0, 2), w * 0.8, h * 0.82)
	draw_colored_polygon(inner, Color(0.06, 0.07, 0.08))
	var top_tint := PackedColorArray()
	for p in inner:
		var t := clampf((p.y - (c.y - h * 0.4)) / (h * 0.8), 0.0, 1.0)
		top_tint.append(Color(accent.r, accent.g, accent.b, lerpf(0.26, 0.0, t)))
	draw_polygon(inner, top_tint)
	draw_polyline(_closed(inner), Color(accent.r, accent.g, accent.b, 0.85), 2.0, true)
	draw_polyline(_closed(_shield(c + Vector2(0, 2), w * 0.88, h * 0.9)), Color(accent.r, accent.g, accent.b, 0.22), 1.0, true)
	_icon(c + Vector2(0, 2))
	# pop flash
	var flash := clampf(1.0 - age / 0.22, 0.0, 1.0)
	if flash > 0.0:
		draw_colored_polygon(pts, Color(1, 1, 1, 0.55 * flash))


func _shield(c: Vector2, w: float, h: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	return PackedVector2Array([
		c + Vector2(-hw, -hh * 0.78), c + Vector2(-hw * 0.18, -hh * 0.78), c + Vector2(0, -hh), c + Vector2(hw * 0.18, -hh * 0.78), c + Vector2(hw, -hh * 0.78),
		c + Vector2(hw, hh * 0.18), c + Vector2(0, hh), c + Vector2(-hw, hh * 0.18),
	])


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _icon(c: Vector2) -> void:
	var bone := Color(0.9, 0.96, 0.88)
	var dark := Color(0.04, 0.05, 0.05)
	for i in 3: # soft glow behind the icon
		draw_circle(c, 34.0 - float(i) * 9.0, Color(accent.r, accent.g, accent.b, 0.08))
	match kind:
		"headshot":
			draw_circle(c + Vector2(0, -8), 20.0, bone)
			draw_rect(Rect2(c.x - 12, c.y + 4, 24, 15), bone)
			draw_circle(c + Vector2(-8, -6), 5.5, dark)
			draw_circle(c + Vector2(8, -6), 5.5, dark)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 1), c + Vector2(-3, 8), c + Vector2(3, 8)]), dark)
			for i in 4:
				draw_line(c + Vector2(-7 + i * 4.7, 11), c + Vector2(-7 + i * 4.7, 19), dark, 1.5)
			# the bullet hole with cracks, in the accent colour
			draw_circle(c + Vector2(0, -19), 3.2, dark)
			draw_circle(c + Vector2(0, -19), 3.2, accent, false, 1.5)
			for a in [-0.6, 0.5, 1.6, 2.7, 3.8]:
				draw_line(c + Vector2(0, -19) + Vector2.from_angle(a) * 3.5, c + Vector2(0, -19) + Vector2.from_angle(a) * 8.0, Color(accent.r, accent.g, accent.b, 0.8), 1.0)
		"oneshot":
			draw_arc(c, 27.0, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, 0.55), 2.0, true)
			draw_rect(Rect2(c.x - 7, c.y - 4, 14, 30), Color(0.85, 0.66, 0.28))
			draw_rect(Rect2(c.x - 7, c.y + 18, 14, 4), Color(0.55, 0.38, 0.15))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -4), c + Vector2(-5, -14), c + Vector2(0, -21), c + Vector2(5, -14), c + Vector2(7, -4)]), Color(0.78, 0.5, 0.25))
			draw_line(c + Vector2(-27, 0), c + Vector2(-17, 0), accent, 2.0)
			draw_line(c + Vector2(27, 0), c + Vector2(17, 0), accent, 2.0)
		"multi", "streak":
			for i in 3:
				var y := c.y - 22.0 + float(i) * 9.0
				var col := Color(accent.r, accent.g, accent.b, 0.35 + 0.22 * float(i))
				draw_polyline(PackedVector2Array([Vector2(c.x - 18, y + 8), Vector2(c.x, y), Vector2(c.x + 18, y + 8)]), col, 4.0, true)
			var font := ThemeDB.fallback_font
			draw_string_outline(font, Vector2(c.x - 14, c.y + 28), str(number), HORIZONTAL_ALIGNMENT_CENTER, 28, 34, 6, Color(0, 0, 0, 0.9))
			draw_string(font, Vector2(c.x - 14, c.y + 28), str(number), HORIZONTAL_ALIGNMENT_CENTER, 28, 34, Color(0.97, 0.97, 0.95))
		"longshot":
			draw_arc(c, 24.0, 0.0, TAU, 40, accent, 2.5, true)
			draw_arc(c, 12.0, 0.0, TAU, 32, Color(accent.r, accent.g, accent.b, 0.6), 2.0, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * 14.0, c + d * 32.0, accent, 2.5)
			draw_circle(c, 2.5, Color(1, 1, 1))
		"grenade":
			draw_circle(c + Vector2(0, 5), 17.0, Color(0.24, 0.3, 0.2))
			draw_arc(c + Vector2(0, 5), 17.0, 0.0, TAU, 32, Color(0.1, 0.12, 0.1), 2.0, true)
			for i in 3:
				draw_line(c + Vector2(-14, -2 + i * 7), c + Vector2(14, -2 + i * 7), Color(0.14, 0.18, 0.13), 1.5)
			draw_rect(Rect2(c.x - 5, c.y - 18, 10, 8), Color(0.62, 0.62, 0.64))
			draw_arc(c + Vector2(8, -15), 9.0, PI, PI * 1.9, 12, accent, 2.5, true)
		"revenge":
			draw_line(c + Vector2(-17, -20), c + Vector2(17, 20), Color(0.86, 0.88, 0.9), 4.0, true)
			draw_line(c + Vector2(17, -20), c + Vector2(-17, 20), Color(0.86, 0.88, 0.9), 4.0, true)
			draw_circle(c, 7.0, accent)
			draw_circle(c, 7.0, dark, false, 1.5)
		_:
			draw_circle(c, 14.0, accent)
