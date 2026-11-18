class_name GlassWindow
extends Node3D
## One breakable pane of building glass. Visual: a thin box with the window_glass shader (reflections, impact cracks).
## Collision: a thin body on physics layer 32 (blocks walking, ignored by bullets and bots' sight, which find it with a
## glass-only ray); removed completely when the pane breaks. Which windows exist and what happens to them is decided by
## the host (GlassField); every machine draws the same result from the events.

const MAX_HITS := 8
const PANE_THICK := 0.02

static var _stub_material: StandardMaterial3D

var id: int = 0
var pane_size: Vector2 = Vector2(1.2, 1.2)
var max_health: float = 70.0
var health: float = 70.0
var broken: bool = false
var hits: Array[Vector4] = [] # logical crack records (newest MAX_HITS)
var break_time: float = INF # when the pane broke (clock of ReplayRecorder), -1 = before this machine knew
var _hist: Array = [] # every impact: {t, x, y, seed, frac, point, dir}
var _break_point: Vector3 = Vector3.ZERO
var _break_dir: Vector3 = Vector3.FORWARD
var _break_power: float = 0.5
var _stubs: MeshInstance3D
var _field: GlassField
var _hit_counter: int = 0
var _variant: float = 0.0
var _pane: MeshInstance3D
var _body: StaticBody3D
var _mat: ShaderMaterial


func setup(window_id: int, def: Dictionary) -> void:
	id = window_id
	pane_size = def["size"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9173 * (window_id + 1)
	max_health = 55.0 + 35.0 * rng.randf() # not every pane takes the same number of hits
	health = max_health
	_variant = rng.randf()
	position = def["center"]
	if not bool(def["axis_x"]):
		basis = Basis(Vector3.UP, PI * 0.5)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/window_glass.gdshader")
	_mat.set_shader_parameter("pane_size", pane_size)
	_mat.set_shader_parameter("variant", _variant)
	_mat.set_shader_parameter("tint", Vector3(0.46 + 0.08 * _variant, 0.68 + 0.04 * rng.randf(), 0.72 - 0.04 * _variant))
	_push_shader()
	_field = get_parent() as GlassField
	_pane = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(pane_size.x, pane_size.y, PANE_THICK)
	_pane.mesh = bm
	_pane.material_override = _mat
	_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pane.visibility_range_end = 85.0
	add_child(_pane)
	_body = StaticBody3D.new()
	_body.collision_layer = GlassField.LAYER
	_body.collision_mask = 0
	_body.set_meta("glass", self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(pane_size.x, pane_size.y, 0.05)
	cs.shape = bs
	_body.add_child(cs)
	add_child(_body)


func damage_fraction() -> float:
	return clampf(1.0 - health / max_health, 0.0, 1.0)


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0 # the clock of the ReplayRecorder


## Host: applies damage to the logical state. Returns true when the pane gives way (the caller then calls break_glass
## and tells everybody); otherwise the caller shows the hit with apply_hit.
func damage_by(amount: float) -> bool:
	if broken:
		return false
	health -= amount
	return health <= 0.0


## Everybody: a crack pattern at `point` (world); `frac` = overall damage of the pane after this hit (0..1).
## The logical state always changes; the picture only when no replay (killcam) is being shown.
func apply_hit(point: Vector3, dir: Vector3, frac: float, silent: bool = false, at_time: float = -2.0) -> void:
	if broken or not is_inside_tree():
		return
	var t := now() if at_time < -1.5 else at_time
	var seed_v := float((id * 31 + _hit_counter * 7) % 997) / 997.0 * 20.0 + 1.0
	_hit_counter += 1
	var local := to_local(point)
	_hist.append({"t": t, "x": clampf(local.x, -pane_size.x * 0.5, pane_size.x * 0.5), "y": clampf(local.y, -pane_size.y * 0.5, pane_size.y * 0.5),
		"seed": seed_v, "frac": frac, "point": point, "dir": dir})
	_sync_logic()
	if _field != null and _field.replaying:
		return
	vis_at(INF)
	if not silent:
		_hit_effects(point, dir)


func _hit_effects(point: Vector3, dir: Vector3) -> void:
	AudioManager.play_3d("glass_hit", point, -3.0, 0.08, 55.0)
	_chips(point, dir)


## The logical list of crack records (at most MAX_HITS, the newest ones) after the latest hit.
func _sync_logic() -> void:
	hits = _visible_hits(INF)


## The crack records (with strengths) that exist at time `t`.
func _visible_hits(t: float) -> Array[Vector4]:
	var list: Array = []
	for h in _hist:
		if float(h["t"]) <= t:
			list.append(h)
	if list.size() > MAX_HITS:
		list = list.slice(list.size() - MAX_HITS)
	var out: Array[Vector4] = []
	var n := list.size()
	if n == 0:
		return out
	var frac: float = list[n - 1]["frac"]
	for i in n:
		var h: Dictionary = list[i]
		out.append(Vector4(h["x"], h["y"], h["seed"], clampf(0.25 + frac * 0.85 - 0.06 * float(n - 1 - i), 0.25, 1.0)))
	return out


## Picture of the pane as it was at time `t` (INF = now): cracks and broken or whole. Never touches the collision.
func vis_at(t: float) -> void:
	var list := _visible_hits(t)
	var frac := 0.0
	for h in _hist:
		if float(h["t"]) <= t:
			frac = float(h["frac"])
	for i in MAX_HITS:
		_mat.set_shader_parameter("h%d" % i, list[i] if i < list.size() else Vector4.ZERO)
	_mat.set_shader_parameter("hit_count", list.size())
	_mat.set_shader_parameter("damage", frac)
	var gone := is_finite(break_time) and break_time <= t
	if _pane != null:
		_pane.visible = not gone
	if gone and _stubs == null:
		_stubs = _add_stubs()
	if _stubs != null:
		_stubs.visible = gone


## Replay: shows everything that happened to the pane in (prev, t] with its effects (cracks, sounds, shards).
func vis_step(prev: float, t: float) -> void:
	if not is_inside_tree():
		return
	for h in _hist:
		var ht: float = h["t"]
		if ht > prev and ht <= t:
			vis_at(ht)
			_hit_effects(h["point"], h["dir"])
	if is_finite(break_time) and break_time > prev and break_time <= t:
		vis_at(t)
		_break_effects(_break_point, _break_dir, _break_power)
	else:
		vis_at(t)


func _push_shader() -> void:
	for i in MAX_HITS:
		_mat.set_shader_parameter("h%d" % i, Vector4.ZERO)
	_mat.set_shader_parameter("hit_count", 0)


func _chips(point: Vector3, dir: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 7
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = -dir
	p.spread = 55.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.0, 0)
	p.mesh = GlassShards.chip_mesh()
	_effects_parent().add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(p.queue_free)


func _effects_parent() -> Node:
	var parent := get_tree().get_first_node_in_group("effects_container")
	return parent if parent != null else get_tree().current_scene


## Everybody: the pane breaks. `dir` = direction of the shot or of the pressure wave, `power` ~ 0.4 (rifle) .. 1.5 (blast next to it).
func break_glass(point: Vector3, dir: Vector3, power: float, silent: bool = false, at_time: float = -2.0) -> void:
	if broken:
		return
	broken = true
	health = 0.0
	break_time = now() if at_time < -1.5 else at_time
	_break_point = point
	_break_dir = dir
	_break_power = power
	if _body != null:
		_body.collision_layer = 0
		_body.queue_free() # no invisible collision, no hit surface
		_body = null
	if not is_inside_tree() or (_field != null and _field.replaying):
		return
	vis_at(INF)
	if not silent:
		_break_effects(point, dir, power)


func _break_effects(point: Vector3, dir: Vector3, power: float) -> void:
	GlassShards.spawn(_effects_parent(), self, point, dir, power)
	AudioManager.play_3d("glass_break", point, 2.0, 0.07, 85.0)
	get_tree().create_timer(0.35).timeout.connect(func() -> void: AudioManager.play_3d("glass_tinkle", point, -4.0, 0.08, 40.0))


## Jagged remains of the pane in the frame (a few thin triangles along the edges).
func _add_stubs() -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5531 * (id + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := pane_size.x * 0.5
	var hh := pane_size.y * 0.5
	for edge in 4:
		var length := pane_size.x if edge < 2 else pane_size.y
		var x := -length * 0.5
		while x < length * 0.5 - 0.05:
			var base := rng.randf_range(0.07, 0.2)
			var tip := rng.randf_range(0.03, 0.2) if rng.randf() > 0.25 else 0.0
			var x2 := minf(x + base, length * 0.5)
			var a: Vector3
			var b: Vector3
			var c: Vector3
			match edge:
				0: # bottom, pointing up
					a = Vector3(x, -hh, 0)
					b = Vector3(x2, -hh, 0)
					c = Vector3((x + x2) * 0.5 + rng.randf_range(-0.03, 0.03), -hh + tip, 0)
				1: # top, hanging down (longer)
					a = Vector3(x, hh, 0)
					b = Vector3(x2, hh, 0)
					c = Vector3((x + x2) * 0.5 + rng.randf_range(-0.04, 0.04), hh - tip * 1.4, 0)
				2:
					a = Vector3(-hw, x, 0)
					b = Vector3(-hw, x2, 0)
					c = Vector3(-hw + tip * 0.8, (x + x2) * 0.5, 0)
				_:
					a = Vector3(hw, x, 0)
					b = Vector3(hw, x2, 0)
					c = Vector3(hw - tip * 0.8, (x + x2) * 0.5, 0)
			for v in [a, b, c]:
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(v)
			x = x2 + rng.randf_range(0.0, 0.05)
	if _stub_material == null:
		_stub_material = GlassShards.shard_material()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _stub_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## For players who join later: [broken, health fraction, flat hit list].
func export_state() -> Array:
	var flat := PackedFloat32Array()
	for h in hits:
		flat.append_array([h.x, h.y, h.z, h.w])
	return [broken, damage_fraction(), flat, _hit_counter]


func import_state(state: Array) -> void:
	_hit_counter = int(state[3])
	_hist.clear()
	var flat: PackedFloat32Array = state[2]
	for i in range(0, flat.size(), 4):
		_hist.append({"t": -1.0, "x": flat[i], "y": flat[i + 1], "seed": flat[i + 2], "frac": float(state[1]), "point": global_position, "dir": Vector3.FORWARD})
	health = max_health * (1.0 - float(state[1]))
	_sync_logic()
	if bool(state[0]):
		break_glass(global_position, Vector3.FORWARD, 0.5, true, -1.0)
	elif not (_field != null and _field.replaying):
		vis_at(INF)
