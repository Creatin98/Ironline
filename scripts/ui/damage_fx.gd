class_name DamageFx
extends CanvasLayer
## The one place for the visual damage feedback (below the HUD, above the 3D world):
##  * a single full-screen shader (assets/shaders/damage_screen.gdshader): red flash, bloody dirty edges, and below
##    25 % health tunnel vision, desaturation, chromatic aberration and a slow pulse - strength follows the health;
##  * blood, dirt and scratches on the "lens": organic procedural textures, they flash in on a hit, drip a little
##    and fade away;
##  * a short FOV kick of the camera on a hit (it returns exactly; the aim is never touched).
## Driven only by GameEvents (damage, health, death, spawn); nothing runs while the screen is clean.

const SHADER := preload("res://assets/shaders/damage_screen.gdshader")
const LIFETIME := 8.0
const MAX_SPLATS := 48
var _beat_t: float = 0.0
var _dazed_set: float = 0.0
const CRIT_RATIO := 0.25

var screen: ColorRect
var canvas: Control
## Shader inputs (smoothed): impulse of hits, hurt level, critical level.
var hit: float = 0.0
var low: float = 0.0
var crit: float = 0.0
var splats: Array = []

var _mat: ShaderMaterial
var _health_ratio: float = 1.0
var _time: float = 0.0
static var _tex: Dictionary = {}


func _ready() -> void:
	layer = 1 # behind the HUD (UI layer 2): the HUD is never covered
	screen = ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	screen.material = _mat
	screen.visible = false
	add_child(screen)
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_splats)
	add_child(canvas)
	GameEvents.local_player_damaged.connect(_on_damaged)
	GameEvents.local_health_changed.connect(_on_health)
	GameEvents.local_player_died.connect(_on_died)
	GameEvents.local_player_spawned.connect(_on_spawned)
	set_process(false)


# ----------------------------------------------------------------------------- events

func _on_damaged(amount: float, _source: Vector3) -> void:
	if not GameSettings.show_blood_overlay:
		return
	# stacking hits intensify the flash but are capped: never a permanently covered screen
	hit = minf(1.0, maxf(hit, 0.6) + 0.18 + amount / 260.0)
	_spawn_splats(amount)
	var me := MatchManager.get_local_participant()
	if me != null and me.node != null and is_instance_valid(me.node):
		(me.node as Player).head.kick_fov(clampf(1.6 + amount / 28.0, 1.6, 5.0)) # snappy; returns by itself
	set_process(true)


func _on_health(current: float, maximum: float) -> void:
	_health_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	set_process(true)


func _on_died(_killer: int, _delay: float) -> void:
	for sp in splats:
		sp["age"] = maxf(float(sp["age"]), LIFETIME - 0.4) # nothing in the death view / killcam
	hit = 0.0
	set_process(true)


func _on_spawned(_player: Node) -> void:
	reset()


## Back to a clean screen (respawn).
func reset() -> void:
	splats.clear()
	hit = 0.0
	low = 0.0
	crit = 0.0
	_health_ratio = 1.0
	if _dazed_set > 0.0:
		_dazed_set = 0.0
		AudioManager.set_flash_effect(0.0)
	screen.visible = false
	canvas.queue_redraw()
	set_process(false)


# ----------------------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_time += delta
	var me := MatchManager.get_local_participant()
	var visible_state := GameSettings.show_blood_overlay and MatchManager.state != MatchManager.State.ENDED \
			and me != null and me.alive and not (me.node != null and is_instance_valid(me.node) and (me.node as Player).replay_mode)
	screen.visible = visible_state
	canvas.visible = visible_state
	if not visible_state:
		hit = maxf(0.0, hit - delta * 3.0)
		if _dazed_set > 0.0:
			_dazed_set = 0.0
			AudioManager.set_flash_effect(0.0)
		return
	hit = maxf(0.0, hit - delta * 1.9) # aggressive attack, controlled fade
	var low_target := smoothstep(0.0, 1.0, clampf((0.65 - _health_ratio) / 0.65, 0.0, 1.0)) * 0.9
	var crit_target := 0.0
	if _health_ratio < CRIT_RATIO:
		crit_target = 0.4 + 0.6 * (1.0 - _health_ratio / CRIT_RATIO) # grows towards death
	low = lerpf(low, low_target, minf(1.0, delta * (5.0 if low_target > low else 2.2))) # healing fades out gently
	crit = lerpf(crit, crit_target, minf(1.0, delta * (6.0 if crit_target > crit else 1.6)))
	var rate := 2.0 + 3.2 * crit # slow heartbeat, faster near death
	var pulse := 0.5 + 0.5 * sin(_time * rate)
	_mat.set_shader_parameter("hit", hit)
	_mat.set_shader_parameter("low", low)
	_mat.set_shader_parameter("crit", crit)
	_mat.set_shader_parameter("pulse", pulse)
	_update_dazed(delta)
	_mat.set_shader_parameter("t", _time)
	var heal_speed := 1.0 + (2.0 if _health_ratio > 0.9 else 0.0) # healed: the lens cleans up quicker
	for sp in splats:
		sp["age"] = float(sp["age"]) + delta * heal_speed
		sp["p"] = (sp["p"] as Vector2) + Vector2(0.0, float(sp["vy"]) * delta * clampf(float(sp["age"]) * 0.5, 0.0, 1.0))
	splats = splats.filter(func(sp: Dictionary) -> bool: return float(sp["age"]) < LIFETIME)
	if not splats.is_empty():
		canvas.queue_redraw()
	elif hit <= 0.002 and low <= 0.002 and crit <= 0.002 and _health_ratio >= 0.65:
		screen.visible = false
		set_process(false) # clean: no more work until the next hit


# ----------------------------------------------------------------------------- lens splatter

## Almost dead: a slow, heavy heartbeat and a slightly dulled hearing with a faint ring (never as strong as a flashbang).
func _update_dazed(delta: float) -> void:
	var level := clampf((crit - 0.35) / 0.65, 0.0, 1.0)
	_beat_t -= delta
	if level > 0.0 and _beat_t <= 0.0:
		_beat_t = lerpf(1.15, 0.62, level)
		AudioManager.play_2d("heartbeat", lerpf(-14.0, -3.0, level), 0.0)
	var want := level * 0.3
	var current := AudioManager.get_flash_effect()
	if current <= _dazed_set + 0.01: # not while a flashbang has a stronger effect
		_dazed_set = lerpf(_dazed_set, want, minf(1.0, delta * 1.5))
		AudioManager.set_flash_effect(_dazed_set)


func _spawn_splats(amount: float) -> void:
	var s := canvas.size
	var k := s.y / 1080.0
	var blobs := clampi(1 + int(amount / 45.0), 1, 3) # few, faint sprays: the grit comes from the shader
	for i in blobs + 1:
		var pos := _edge_biased(s)
		var roll := randf()
		var sp := {"p": pos, "age": 0.0, "vy": randf_range(6.0, 30.0) * k}
		if i == blobs: # one fine spray of speckles per hit
			sp["kind"] = 2
			sp["size"] = randf_range(220.0, 420.0) * k
			sp["rot"] = randf() * TAU
		else:
			sp["kind"] = 6 if roll < 0.8 else 2 # sprays only: no lone smears or blobs (they looked like fingerprints)
			sp["size"] = randf_range(180.0, 640.0) * k * (1.0 if randf() < 0.7 else 0.55)
			sp["rot"] = randf() * TAU
			sp["vy"] = 0.0
		if int(sp["kind"]) == 1:
			sp["tex_id"] = "smear" if randf() < 0.5 else "smear2"
		splats.append(sp)
	# extra sprays: coarse big drops and sometimes a second small fine mist
	for extra in 1:
		splats.append({"kind": 6, "p": _edge_biased(s), "age": 0.0, "vy": randf_range(4.0, 14.0) * k, "size": randf_range(300.0, 600.0) * k, "rot": randf() * TAU})
	if randf() < 0.15:
		splats.append({"kind": 2, "p": _edge_biased(s), "age": 0.0, "vy": randf_range(4.0, 14.0) * k, "size": randf_range(120.0, 200.0) * k, "rot": randf() * TAU})
	# a few dirt specks and fine scratches on the glass
	if randf() < 0.9:
		splats.append({"kind": 4, "p": _edge_biased(s), "age": 0.0, "vy": 0.0, "size": randf_range(120.0, 260.0) * k, "rot": randf() * TAU})
	while splats.size() > MAX_SPLATS:
		splats.pop_front()
	canvas.queue_redraw()


## Positions over the whole picture, but away from the very middle (the crosshair stays free).
func _edge_biased(s: Vector2) -> Vector2:
	var pos := Vector2.ZERO
	for attempt in 8:
		pos = Vector2(randf_range(0.02, 0.98) * s.x, randf_range(0.02, 0.98) * s.y)
		var rel := (pos - s * 0.5) / s
		if absf(rel.x) > 0.18 or absf(rel.y) > 0.22:
			break
	return pos


func _draw_splats() -> void:
	for sp in splats:
		var age := float(sp["age"])
		var fade := clampf((LIFETIME - age) / 2.2, 0.0, 1.0)
		var grow := clampf(age * 6.0, 0.0, 1.0)
		var a := fade * (0.42 - 0.14 * clampf(age / LIFETIME, 0.0, 1.0)) # faint, thin spray; blood dries: a little less opaque with time
		var p: Vector2 = sp["p"]
		var sz: float = float(sp.get("size", 0.0))
		match int(sp["kind"]):
			0:
				_draw_splash(sp["shape"], p, sz * (0.72 + 0.28 * grow), float(sp["rot"]), a)
			1:
				_stamp(_texture(String(sp.get("tex_id", "smear"))), p, sz * (0.6 + 0.4 * grow), 0.45, float(sp["rot"]), Color(0.4, 0.015, 0.015, a * 0.8))
			2:
				_stamp(_texture("speckle"), p, sz * (0.8 + 0.2 * grow), 1.0, float(sp["rot"]), Color(0.5, 0.03, 0.03, a))
			3:
				_draw_drip(sp, p, sz, age, a)
			6:
				_stamp(_texture("coarse"), p, sz * (0.8 + 0.2 * grow), 1.0, float(sp["rot"]), Color(0.46, 0.025, 0.025, a))
			4:
				_stamp(_texture("speckle"), p, sz, 1.0, float(sp["rot"]), Color(0.18, 0.1, 0.06, a * 0.75)) # dirt, brownish
			5:
				for l in sp["lines"]:
					var dir := Vector2.from_angle(float(l[0]))
					var q := p + dir.orthogonal() * float(l[2])
					canvas.draw_line(q, q + dir * float(l[1]), Color(0.92, 0.85, 0.85, a * 0.22), 1.3, true)


## Random splash geometry in unit space (-1..1): a lumpy body that is stretched in one direction, cast-off drops that
## get smaller and more elongated (tails pointing back to the body) the farther they fly, and fine mist.
static func _make_splash_shape() -> Dictionary:
	var bias := randf() * TAU
	var body := PackedVector2Array()
	var n := 22
	var base := randf_range(0.08, 0.13)
	var ph: Array[float] = []
	for k in 5:
		ph.append(randf() * TAU)
	for i in n:
		var a := TAU * float(i) / float(n)
		var r := base * (1.0 + 0.28 * sin(a * 2.0 + ph[0]) + 0.18 * sin(a * 3.0 + ph[1]) + 0.12 * sin(a * 5.0 + ph[2]))
		r += 0.14 * pow(maxf(0.0, cos(a - bias)), 4.0)
		body.append(Vector2.from_angle(a) * r)
	var drops: Array = []
	for i in randi_range(18, 30):
		var da := bias + randfn(0.0, 0.9)
		var dist := 0.28 + pow(randf(), 1.4) * 0.66
		var rad := lerpf(0.055, 0.014, dist) * randf_range(0.6, 1.4)
		var tail := rad * randf_range(0.0, 3.2) * clampf(dist * 1.5, 0.0, 1.0)
		drops.append([Vector2.from_angle(da) * dist, rad, -Vector2.from_angle(da), tail])
	for i in randi_range(18, 34):
		var da := bias + randfn(0.0, 1.2)
		drops.append([Vector2.from_angle(da) * randf_range(0.3, 0.95), randf_range(0.007, 0.016), Vector2.ZERO, 0.0])
	return {"body": body, "drops": drops}


func _draw_splash(shape: Dictionary, p: Vector2, size: float, rot: float, a: float) -> void:
	# wet blood on glass: translucent, soft-edged (several layers, dark in the middle), drops thin and see-through
	var half := size * 0.5
	var xf := Transform2D(rot, Vector2.ONE, 0.0, p)
	var layers := [[1.0, 0.22, Color(0.5, 0.05, 0.04)], [0.8, 0.28, Color(0.42, 0.03, 0.03)], [0.58, 0.34, Color(0.32, 0.02, 0.02)], [0.34, 0.4, Color(0.22, 0.012, 0.012)]]
	for l in layers:
		var body := PackedVector2Array()
		for v in shape["body"]:
			body.append(xf * ((v as Vector2) * half * 2.0 * float(l[0])))
		var c: Color = l[2]
		c.a = a * float(l[1])
		canvas.draw_colored_polygon(body, c)
	var col := Color(0.4, 0.025, 0.02, a * 0.6)
	for dr in shape["drops"]:
		var c: Vector2 = xf * ((dr[0] as Vector2) * half * 2.0)
		var rad: float = float(dr[1]) * size
		var tail: float = float(dr[3]) * size
		if tail > rad * 0.8:
			var dir: Vector2 = xf.basis_xform(dr[2] as Vector2).normalized()
			var side := dir.orthogonal() * rad
			canvas.draw_colored_polygon(PackedVector2Array([c + side, c + dir * tail, c - side]), col)
		canvas.draw_circle(c, rad, col)
		if rad > 2.5:
			canvas.draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.22, Color(1.0, 0.8, 0.75, a * 0.35)) # glint


## A drip: a soft stain at the top, a run with a slightly wobbling edge that thins out while it creeps down,
## and a round bead with a glint at its end. The run keeps growing for a while (slower and slower).
func _draw_drip(sp: Dictionary, p: Vector2, sz: float, age: float, a: float) -> void:
	var w: float = float(sp["w"])
	var seed_f: float = float(sp["seed"])
	var run := 1.0 - pow(1.0 - clampf(age * 0.35, 0.0, 1.0), 2.2)
	var length := sz * (0.18 + 0.82 * run)
	var col := Color(0.42, 0.02, 0.02, a)
	_stamp(BloodFx.splat_texture(int(sp["tex"])), p, w * 7.0, 1.0, float(sp["rot"]), Color(0.46, 0.02, 0.02, a * 0.92))
	var steps := 20
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var end_c := p
	var end_w := w * 0.3
	for i in steps + 1:
		var t := float(i) / float(steps)
		var cx := p.x + sin(t * 5.0 + seed_f) * w * 0.45 * t + sin(t * 13.0 + seed_f * 2.0) * w * 0.08
		var cy := p.y + length * t
		var hw := w * (0.62 - 0.38 * t + 0.14 * sin(t * 15.0 + seed_f * 3.0)) * (0.55 if run < 0.15 else 1.0)
		hw = maxf(hw, w * 0.16)
		left.append(Vector2(cx - hw, cy))
		right.append(Vector2(cx + hw, cy))
		end_c = Vector2(cx, cy)
		end_w = hw
	var poly := PackedVector2Array()
	poly.append_array(left)
	right.reverse()
	poly.append_array(right)
	if length > 6.0:
		canvas.draw_colored_polygon(poly, col)
	canvas.draw_circle(end_c, end_w * 1.45, col)
	canvas.draw_circle(end_c + Vector2(-end_w * 0.35, -end_w * 0.4), end_w * 0.4, Color(0.95, 0.6, 0.55, a * 0.45)) # glint
	canvas.draw_circle(end_c + Vector2(end_w * 0.2, -length * 0.35), end_w * 0.35, Color(col.r, col.g, col.b, a * 0.8)) # a small drop that stayed behind


func _stamp(tex: Texture2D, p: Vector2, size: float, aspect: float, rot: float, col: Color) -> void:
	canvas.draw_set_transform(p, rot, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5 / aspect * (1.0 if aspect > 1.0 else 1.0), size, size / aspect), false, col)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------------------- procedural textures

static func _texture(id: String) -> ImageTexture:
	if _tex.has(id):
		return _tex[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242 + id.hash() % 1000
	var img: Image
	if id == "speckle":
		img = _make_speckle(rng, false)
	elif id == "coarse":
		img = _make_speckle(rng, true)
	else:
		img = _make_smear(rng)
	var t := ImageTexture.create_from_image(img)
	_tex[id] = t
	return t


## Fine spray: many small round drops of different sizes, a few bigger ones, soft edges.
static func _make_speckle(rng: RandomNumberGenerator, coarse: bool = false) -> Image:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for i in (46 if coarse else 150):
		var ang := rng.randf() * TAU
		var dist := pow(rng.randf(), 0.7) * 0.46
		var c := Vector2(0.5 + cos(ang) * dist, 0.5 + sin(ang) * dist) * size
		var r := (rng.randf_range(0.8, 3.0) if rng.randf() < 0.88 else rng.randf_range(4.0, 9.0)) * (1.0 - dist * 0.9)
		if coarse:
			r = (rng.randf_range(2.5, 6.0) if rng.randf() < 0.8 else rng.randf_range(8.0, 14.0)) * (1.0 - dist * 0.75)
		var stretch := Vector2(1.0, rng.randf_range(0.8, 1.5)).rotated(ang)
		for y in range(maxi(0, int(c.y - r * 2.0)), mini(size, int(c.y + r * 2.0) + 1)):
			for x in range(maxi(0, int(c.x - r * 2.0)), mini(size, int(c.x + r * 2.0) + 1)):
				var q := (Vector2(x, y) - c)
				var dd := Vector2(q.dot(stretch.normalized()) / stretch.length(), q.dot(stretch.orthogonal().normalized())).length() / r
				var a := clampf(1.0 - dd, 0.0, 1.0)
				a = clampf(a * 2.2, 0.0, 1.0)
				if a > img.get_pixel(x, y).a:
					img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## A smear: an uneven streak that thins out towards one end and has dry-brush stripes.
static func _make_smear(rng: RandomNumberGenerator) -> Image:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wob := rng.randf() * TAU
	var stripes: Array[float] = []
	for y in h:
		stripes.append(rng.randf_range(0.45, 1.0))
	for x in w:
		var u := float(x) / w
		var thick := (0.10 + 0.27 * sin(u * PI)) * (1.0 - u * 0.3)
		var head := smoothstep(0.0, 0.2, u) # the smear starts softly, no straight cut
		var centre := 0.5 + sin(u * 5.0 + wob) * 0.06
		for y in h:
			var v := float(y) / h
			var d := absf(v - centre) / maxf(thick, 0.001)
			var edge_v := smoothstep(0.0, 0.07, minf(v, 1.0 - v))
			var a := clampf(1.0 - d * d, 0.0, 1.0) * stripes[y] * smoothstep(0.0, 0.5, 1.0 - u) * head * edge_v
			if rng.randf() < 0.04:
				a *= 0.5
			if a > 0.01:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a * 1.3, 0.0, 1.0)))
	return img
