class_name MagPickupFx
extends Control
## HUD feedback for a picked-up magazine, slightly off the centre of the screen: a slim, curved rifle magazine drawn with
## fine detail (stamped ribs, base plate, feed lips, brass rounds, a thin highlight), a small "+1" and "MAGAZIN" in tiny
## letters. It slides in with a little tilt, a glint runs over the steel, then it floats up and fades.

const LIFE := 1.55
var _t: float = 0.0


func _init() -> void:
	size = Vector2(150, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(30, 60)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	var pop := clampf(_t / 0.16, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - pop, 3.0)
	scale = Vector2.ONE * lerpf(0.8, 1.0, e)
	rotation = lerpf(-0.22, 0.0, e)
	modulate.a = clampf(_t / 0.08, 0.0, 1.0) * clampf((LIFE - _t) / 0.45, 0.0, 1.0)
	position.y -= delta * 10.0 * (1.0 - _t / LIFE)
	queue_redraw()


## Centre line of the magazine (a gentle banana curve) from the feed lips (t = 0) to the base plate (t = 1).
func _centre(t: float) -> Vector2:
	return Vector2(34.0 + 22.0 * t * t + 6.0 * t, 22.0 + 76.0 * t)


func _width(t: float) -> float:
	return lerpf(11.0, 15.0, t)


func _draw() -> void:
	var n := 18
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var c := _centre(t)
		var tangent := (_centre(minf(t + 0.02, 1.0)) - _centre(maxf(t - 0.02, 0.0))).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		left.append(c - normal * _width(t))
		right.append(c + normal * _width(t))
	var poly := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n + 1:
		poly.append(left[i])
		cols.append(Color(0.62, 0.65, 0.68))
	for i in range(n, -1, -1):
		poly.append(right[i])
		cols.append(Color(0.3, 0.32, 0.35))
	draw_polygon(poly, cols)
	# stamped ribs
	for k in 6:
		var t := 0.2 + float(k) * 0.12
		var i := int(t * float(n))
		draw_line(left[i].lerp(right[i], 0.18), left[i].lerp(right[i], 0.82), Color(0.12, 0.13, 0.15, 0.8), 1.4, true)
		draw_line(left[i].lerp(right[i], 0.18) + Vector2(0, 1.5), left[i].lerp(right[i], 0.82) + Vector2(0, 1.5), Color(1, 1, 1, 0.18), 1.0, true)
	# outline and a thin highlight along the left edge
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(0.05, 0.05, 0.06, 0.95), 1.6, true)
	var hi := PackedVector2Array()
	for i in n + 1:
		hi.append(left[i].lerp(right[i], 0.14))
	draw_polyline(hi, Color(1, 1, 1, 0.4), 1.2, true)
	# base plate (darker, slightly wider) and feed lips with two staggered rounds
	var bl := left[n].lerp(right[n], -0.06) + Vector2(0, 0)
	var br := right[n].lerp(left[n], -0.06)
	draw_polygon(PackedVector2Array([bl, br, br + Vector2(1.5, 7.0), bl + Vector2(-1.5, 7.0)]), PackedColorArray([Color(0.16, 0.17, 0.19), Color(0.16, 0.17, 0.19), Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09)]))
	var top_c := _centre(0.0)
	for k in 2:
		var off := Vector2(-4.5 + float(k) * 8.0, -float(k) * 3.5 - 7.0)
		var base := top_c + off
		draw_rect(Rect2(base.x - 3.2, base.y, 6.4, 10.0), Color(0.88, 0.68, 0.28))
		draw_colored_polygon(PackedVector2Array([base + Vector2(-3.2, 0), base + Vector2(-2.4, -6), base + Vector2(0, -9), base + Vector2(2.4, -6), base + Vector2(3.2, 0)]), Color(0.72, 0.46, 0.22))
		draw_line(base + Vector2(-3.2, 5), base + Vector2(3.2, 5), Color(0.45, 0.3, 0.12), 1.0)
	draw_polyline(PackedVector2Array([left[0] + Vector2(-1, 1), left[0] + Vector2(-1.5, -1.5), right[0] + Vector2(1.5, -1.5), right[0] + Vector2(1, 1)]), Color(0.1, 0.1, 0.11), 2.0, true)
	# a glint sweeping over the steel
	var g := clampf((_t - 0.12) / 0.4, 0.0, 1.0)
	if g > 0.0 and g < 1.0:
		var i := clampi(int(g * float(n)), 0, n)
		draw_line(left[i], right[i], Color(1, 1, 1, 0.55 * sin(g * PI)), 3.0, true)
	# "+1" and a tiny caption, thin and tidy
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(78, 62), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(78, 62), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.97, 0.82, 0.4))
	draw_string_outline(font, Vector2(79, 78), "MAGAZIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(79, 78), "MAGAZIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.84, 0.86, 0.9))
	draw_line(Vector2(78, 83), Vector2(124, 83), Color(0.97, 0.82, 0.4, 0.5), 1.0)
