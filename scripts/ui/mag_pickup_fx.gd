class_name MagPickupFx
extends Control
## HUD feedback for a picked-up magazine: a small drawn magazine with brass rounds and a "+1" beside it. It pops in,
## floats up a little and fades out (Call-of-Duty "Scavenger" style). Purely a drawing, no assets.

const LIFE := 1.5
const BASE := 1.7 # drawn at 1x, shown larger

var _t: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(110, 46)
	size = Vector2(110, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(30, 23)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	var pop := clampf(_t / 0.14, 0.0, 1.0)
	var s := lerpf(0.55, 1.0, 1.0 - pow(1.0 - pop, 3.0)) + 0.08 * sin(clampf(_t / 0.3, 0.0, 1.0) * PI)
	scale = Vector2(s, s) * BASE
	modulate.a = clampf((LIFE - _t) / 0.45, 0.0, 1.0) * clampf(_t / 0.06, 0.0, 1.0)
	position.y -= delta * 14.0 * (1.0 - _t / LIFE)
	queue_redraw()


func _draw() -> void:
	# magazine body (slightly curved, tapering), steel with a dark outline and ribs
	var body := PackedVector2Array([Vector2(10, 10), Vector2(27, 8), Vector2(33, 20), Vector2(39, 36), Vector2(40, 45), Vector2(26, 46), Vector2(22, 34), Vector2(14, 22)])
	draw_colored_polygon(body, Color(0.74, 0.77, 0.8))
	draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[5], body[6], body[7], body[0]]), Color(0.1, 0.11, 0.13), 2.0, true)
	for i in 3:
		var y := 18.0 + float(i) * 8.0
		draw_line(Vector2(15.0 + float(i) * 3.5, y), Vector2(31.0 + float(i) * 4.0, y - 2.0), Color(0.25, 0.27, 0.3), 1.5, true)
	draw_polygon(PackedVector2Array([Vector2(12, 12), Vector2(25, 10), Vector2(29, 16), Vector2(16, 18)]), PackedColorArray([Color(0.95, 0.97, 1.0, 0.45), Color(0.95, 0.97, 1.0, 0.0), Color(0.95, 0.97, 1.0, 0.0), Color(0.95, 0.97, 1.0, 0.0)]))
	# two brass rounds peeking out of the top
	for k in 2:
		var x := 14.0 + float(k) * 9.0
		draw_rect(Rect2(x, 0.0, 6.0, 10.0), Color(0.92, 0.7, 0.28))
		draw_rect(Rect2(x, 0.0, 6.0, 4.0), Color(0.72, 0.46, 0.2))
		draw_rect(Rect2(x, 0.0, 6.0, 10.0), Color(0.15, 0.1, 0.05), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(52, 36), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 5, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(52, 36), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UITheme.ACCENT)
