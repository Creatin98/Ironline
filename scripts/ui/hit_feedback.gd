class_name HitFeedback
extends RefCounted
## Hit feedback shared by the HUD and the killcam: the hitmarker graphic and its sounds.
## Hit codes (bit flags) travel in shots: BODY = hit an enemy, HEAD = headshot, KILL = the hit killed.

const BODY := 1
const HEAD := 2
const KILL := 4


## Hit feedback: white X (hit), red double cross (headshot), bigger with a burst ring on kills.
## `time_left` counts down from `total`; `canvas` is the Control that is drawing.
static func draw_marker(canvas: Control, center: Vector2, time_left: float, total: float, head: bool, kill: bool) -> void:
	var life := clampf(time_left / maxf(total, 0.001), 0.0, 1.0) # 1 -> 0
	var alpha := clampf(life * 2.5, 0.0, 1.0)
	var pop := 1.0 + (0.55 if kill else 0.3) * pow(life, 3.0) # starts big, settles
	var red := Color(1.0, 0.22, 0.16, alpha)
	var white := Color(1.0, 1.0, 1.0, alpha)
	var col := red if (head or kill) else white
	var size := 1.0
	if kill:
		size = 1.55
	elif head:
		size = 1.2
	var r1 := 6.0 * size * pop
	var r2 := 16.0 * size * pop
	var width := 4.0 if kill else 3.0
	var shadow := Color(0, 0, 0, alpha * 0.55)
	var diagonals := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for d in diagonals:
		var dn: Vector2 = d.normalized()
		canvas.draw_line(center + dn * r1 + Vector2(1, 1), center + dn * r2 + Vector2(1, 1), shadow, width + 1.0)
		canvas.draw_line(center + dn * r1, center + dn * r2, col, width)
	if head:
		# second cross (+) on top of the X: the "double cross" of a headshot
		var p1 := r1 * 1.25
		var p2 := r2 * 1.35
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			canvas.draw_line(center + d * p1 + Vector2(1, 1), center + d * p2 + Vector2(1, 1), shadow, width + 1.0)
			canvas.draw_line(center + d * p1, center + d * p2, col, width)
	if kill:
		var ring_t := 1.0 - life
		var ring_alpha := clampf(1.0 - ring_t * 1.4, 0.0, 1.0) * 0.8
		canvas.draw_arc(center, 10.0 + ring_t * 46.0, 0.0, TAU, 40, Color(1.0, 0.3, 0.2, ring_alpha), 3.0, true)


## How long the marker stays.
static func duration(head: bool, kill: bool) -> float:
	return 0.5 if kill else (0.22 if head else 0.14)


## Hit sounds: thunk (headshot: sharper), on kills additionally the kill chime that rises with the streak.
static func play_sounds(head: bool, kill: bool, streak: int = 1) -> void:
	if kill:
		var pitch := 1.0 + 0.045 * float(mini(maxi(streak, 1) - 1, 8))
		AudioManager.play_2d("hitmarker_headshot" if head else "hitmarker", -8.0, 0.0)
		var p := AudioManager.play_2d("kill_headshot" if head else "kill_confirm", -1.0, 0.0)
		if p != null:
			p.pitch_scale = pitch
	else:
		AudioManager.play_2d("hitmarker_headshot" if head else "hitmarker", -1.0 if head else -3.0, 0.03)
