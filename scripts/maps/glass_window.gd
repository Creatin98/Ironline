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
var hits: Array[Vector4] = []
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


## Host: applies damage. Returns true when the pane gives way (the caller then calls break_glass and tells everybody).
func damage_by(amount: float, point: Vector3, dir: Vector3) -> bool:
	if broken:
		return false
	health -= amount
	if health <= 0.0:
		return true
	apply_hit(point, dir, damage_fraction())
	return false


## Everybody: a crack pattern at `point` (world); `frac` = overall damage of the pane after this hit (0..1).
func apply_hit(point: Vector3, dir: Vector3, frac: float, silent: bool = false) -> void:
	if broken or not is_inside_tree():
		return
	var local := to_local(point)
	var seed_v := float((id * 31 + _hit_counter * 7) % 997) / 997.0 * 20.0 + 1.0
	_hit_counter += 1
	if hits.size() >= MAX_HITS:
		hits.remove_at(0)
	hits.append(Vector4(clampf(local.x, -pane_size.x * 0.5, pane_size.x * 0.5), clampf(local.y, -pane_size.y * 0.5, pane_size.y * 0.5), seed_v, 0.3))
	_restrength(frac)
	if not silent:
		AudioManager.play_3d("glass_hit", point, -3.0, 0.08, 55.0)
		_chips(point, dir)


## The cracks of the older impacts spread with the total damage.
func _restrength(frac: float) -> void:
	var n := hits.size()
	for i in n:
		var h := hits[i]
		h.w = clampf(0.25 + frac * 0.85 - 0.06 * float(n - 1 - i), 0.25, 1.0)
		hits[i] = h
	_mat.set_shader_parameter("damage", frac)
	_push_shader()


func _push_shader() -> void:
	for i in MAX_HITS:
		_mat.set_shader_parameter("h%d" % i, hits[i] if i < hits.size() else Vector4.ZERO)
	_mat.set_shader_parameter("hit_count", hits.size())


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
func break_glass(point: Vector3, dir: Vector3, power: float, silent: bool = false) -> void:
	if broken:
		return
	broken = true
	health = 0.0
	if _pane != null:
		_pane.visible = false
	if _body != null:
		_body.collision_layer = 0
		_body.queue_free() # no invisible collision, no hit surface
		_body = null
	_add_stubs()
	if silent or not is_inside_tree():
		return
	GlassShards.spawn(_effects_parent(), self, point, dir, power)
	AudioManager.play_3d("glass_break", point, 2.0, 0.07, 85.0)
	get_tree().create_timer(0.35).timeout.connect(func() -> void: AudioManager.play_3d("glass_tinkle", point, -4.0, 0.08, 40.0))


## Jagged remains of the pane in the frame (a few thin triangles along the edges).
func _add_stubs() -> void:
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


## For players who join later: [broken, health fraction, flat hit list].
func export_state() -> Array:
	var flat := PackedFloat32Array()
	for h in hits:
		flat.append_array([h.x, h.y, h.z, h.w])
	return [broken, damage_fraction(), flat, _hit_counter]


func import_state(state: Array) -> void:
	_hit_counter = int(state[3])
	hits.clear()
	var flat: PackedFloat32Array = state[2]
	for i in range(0, flat.size(), 4):
		hits.append(Vector4(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]))
	health = max_health * (1.0 - float(state[1]))
	_mat.set_shader_parameter("damage", float(state[1]))
	_push_shader()
	if bool(state[0]):
		break_glass(global_position, Vector3.FORWARD, 0.5, true)
