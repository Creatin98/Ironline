class_name MedalHud
extends Control
## Kill rewards in the style of modern shooters, kept dark and cinematic: medals (shield with icon, title, subtitle) fade in at
## the top centre and make room for each other; a glowing "+100" with the reason pops up next to the crosshair and the older
## scores rise and fade. Everything is drawn by MedalWidget / labels, no assets.

const MAX_MEDALS := 3
const SCORE_LIFE := 1.5

var _medals: Array = []
var _scores: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _k() -> float:
	return clampf(size.y / 1080.0, 0.65, 1.5)


## A medal; `number` is the count for multi kills and streaks.
func medal(kind: String, title: String, subtitle: String = "", number: int = 0) -> void:
	var w := MedalWidget.new()
	w.setup(kind, title, subtitle, number)
	w.scale_base = _k()
	add_child(w)
	_medals.append(w)
	while _medals.size() > MAX_MEDALS:
		var old = _medals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var p := AudioManager.play_2d("medal_hit", -5.0, 0.0)
	if p != null:
		p.pitch_scale = {"headshot": 1.0, "oneshot": 0.9, "multi": 1.08, "streak": 0.82, "longshot": 1.15, "grenade": 0.95, "revenge": 0.88}.get(kind, 1.0)


## Score next to the crosshair: "+100" in gold with a bloom and the reason in small letters.
func score(points: int, reason: String) -> void:
	var k := _k()
	var gold := Color(0.9, 0.74, 0.42)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(300, 60) * k
	add_child(box)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var num := "+%d" % points
	var bloom := UITheme.label(num, int(34 * k), Color(gold.r, gold.g, gold.b, 0.18), HORIZONTAL_ALIGNMENT_LEFT)
	bloom.add_theme_constant_override("outline_size", int(8 * k))
	bloom.add_theme_color_override("font_outline_color", Color(gold.r, gold.g * 0.8, gold.b * 0.5, 0.1))
	bloom.material = add
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bloom)
	var label := UITheme.label(num, int(34 * k), gold, HORIZONTAL_ALIGNMENT_LEFT)
	label.add_theme_constant_override("outline_size", int(6 * k))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var rcol := Color(0.86, 0.87, 0.88, 0.95)
	if reason == "Kopfschuss":
		rcol = Color(0.55, 1.0, 0.62)
	elif reason == "Assist":
		rcol = Color(0.55, 0.8, 1.0)
	var reason_label := UITheme.label(_reason_text(reason), int(13 * k), rcol, HORIZONTAL_ALIGNMENT_LEFT)
	reason_label.add_theme_constant_override("outline_size", int(4 * k))
	reason_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reason_label.position = Vector2(num.length() * 20.0 * k + 12.0 * k, 12.0 * k)
	box.add_child(reason_label)
	box.pivot_offset = Vector2(40, 30) * k
	box.set_meta("age", 0.0)
	_scores.append(box)
	while _scores.size() > 4:
		var old = _scores.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func _reason_text(reason: String) -> String:
	match reason:
		"Kill":
			return "ELIMINIERT"
		"Kopfschuss":
			return "KOPFSCHUSS"
		"Assist":
			return "UNTERSTÜTZUNG"
	return reason.to_upper()


func _process(delta: float) -> void:
	var k := _k()
	var center := Vector2(size.x * 0.5, 0.0)
	# medals: the newest in the middle, older ones make room to the left
	_medals = _medals.filter(func(m) -> bool: return is_instance_valid(m))
	var n := _medals.size()
	for i in n:
		var m: MedalWidget = _medals[i]
		var slot := float(n - 1 - i)
		var target := Vector2(center.x - MedalWidget.SIZE.x * 0.5 * k - slot * 215.0 * k, 64.0 * k - 72.0 * (1.0 - k))
		m.position = target if m.age < 0.05 else m.position.lerp(target, minf(1.0, delta * 9.0))
		m.scale_base = k
	# scores: above the crosshair, rising stack
	_scores = _scores.filter(func(s) -> bool: return is_instance_valid(s))
	var m2 := _scores.size()
	for i in m2:
		var s: Control = _scores[i]
		var age: float = float(s.get_meta("age")) + delta
		s.set_meta("age", age)
		if age >= SCORE_LIFE:
			s.queue_free()
			continue
		var slot := float(m2 - 1 - i)
		var base := Vector2(size.x * 0.5 + 38.0 * k, size.y * 0.5 - 150.0 * k - slot * 46.0 * k)
		var pop := clampf(age / 0.14, 0.0, 1.0)
		var sc := lerpf(1.5, 1.0, 1.0 - pow(1.0 - pop, 3.0))
		s.scale = Vector2(sc, sc)
		s.position = base - Vector2(0, 14.0 * k * clampf((age - 0.9) / 0.6, 0.0, 1.0))
		s.modulate.a = clampf(age / 0.05, 0.0, 1.0) * clampf((SCORE_LIFE - age) / 0.45, 0.0, 1.0) * (1.0 - 0.25 * slot)
