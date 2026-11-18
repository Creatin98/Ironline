class_name GlassShards
extends Node3D
## The fragments of a broken window: a few dozen triangles in ONE MultiMesh, moved by this script (no physics bodies):
## they fly with the shot / pressure wave, fall, bounce once on the floor below the window, lie there and shrink away.
## At most MAX_ACTIVE breaks are alive at the same time (the oldest is removed first).

const MAX_ACTIVE := 8
const LIFETIME := 8.0
const FADE := 1.2

static var _active: Array = []
static var _shard_mesh: ArrayMesh
static var _chip_mesh: QuadMesh
static var _material: StandardMaterial3D

var _mm: MultiMesh
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _axis: Array[Vector3] = []
var _angle: PackedFloat32Array = PackedFloat32Array()
var _spin: PackedFloat32Array = PackedFloat32Array()
var _scale: PackedFloat32Array = PackedFloat32Array()
var _landed: PackedInt32Array = PackedInt32Array() # 0 flying, 1 bounced once, 2 resting
var _floor: Array[float] = [0.0, 0.0]
var _normal: Vector3 = Vector3.FORWARD
var _origin: Vector3 = Vector3.ZERO
var _age: float = 0.0


static func shard_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.72, 0.9, 0.93, 0.5)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.roughness = 0.05
		_material.metallic_specular = 1.0
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material


static func chip_mesh() -> QuadMesh:
	if _chip_mesh == null:
		_chip_mesh = QuadMesh.new()
		_chip_mesh.size = Vector2(0.035, 0.035)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.9, 0.97, 1.0, 0.9)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_chip_mesh.material = m
	return _chip_mesh


static func _triangle() -> ArrayMesh:
	if _shard_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.1, 0.5, 0)]:
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(v)
		_shard_mesh = st.commit()
		_shard_mesh.surface_set_material(0, shard_material())
	return _shard_mesh


static func spawn(parent: Node, window: GlassWindow, point: Vector3, dir: Vector3, power: float) -> void:
	while _active.size() >= MAX_ACTIVE:
		var old = _active.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var s := GlassShards.new()
	parent.add_child(s)
	s._start(window, point, dir.normalized(), power)
	_active.append(s)
	# a shower of fine sparkles at the moment of breaking
	var p := CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = dir
	p.spread = 70.0
	p.initial_velocity_min = 1.0 + power
	p.initial_velocity_max = 3.0 + 2.0 * power
	p.gravity = Vector3(0, -8.0, 0)
	p.mesh = chip_mesh()
	parent.add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(p.queue_free)


func _start(window: GlassWindow, point: Vector3, dir: Vector3, power: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (window.id + 3) + int(power * 100.0)
	var n := clampi(int(window.pane_size.x * window.pane_size.y * 18.0), 16, 38)
	var xf := window.global_transform
	_origin = xf.origin
	_normal = xf.basis.z.normalized()
	var space := window.get_world_3d().direct_space_state
	var base := xf.origin - Vector3(0, window.pane_size.y * 0.5, 0)
	for side in 2:
		var from := base + _normal * (0.8 if side == 0 else -0.8) + Vector3(0, 0.4, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -8.0, 0), 1)
		var r := space.intersect_ray(q)
		_floor[side] = float(r["position"].y) if not r.is_empty() else base.y - 1.0
	var inv := xf.affine_inverse()
	for i in n:
		var local := Vector3(rng.randf_range(-0.5, 0.5) * window.pane_size.x, rng.randf_range(-0.5, 0.5) * window.pane_size.y, 0)
		if i % 2 == 0: # half of them start around the impact
			var lp := inv * point
			local = Vector3(lp.x + rng.randfn(0.0, 0.3), lp.y + rng.randfn(0.0, 0.3), 0)
			local.x = clampf(local.x, -window.pane_size.x * 0.5, window.pane_size.x * 0.5)
			local.y = clampf(local.y, -window.pane_size.y * 0.5, window.pane_size.y * 0.5)
		var p := xf * local
		var v := dir * rng.randf_range(0.8, 3.2) * (0.6 + power) + (p - point) * rng.randf_range(0.5, 1.6) + Vector3(0, rng.randf_range(-0.2, 1.2), 0)
		_pos.append(p)
		_vel.append(v)
		_axis.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
		_angle.append(rng.randf() * TAU)
		_spin.append(rng.randf_range(-9.0, 9.0))
		_scale.append(rng.randf_range(0.06, 0.26))
		_landed.append(0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _triangle()
	_mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true # positions are world space
	add_child(mi)
	mi.custom_aabb = AABB(_origin - Vector3.ONE * 14.0, Vector3.ONE * 28.0)
	_update_transforms(1.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var fade := 1.0 if _age < LIFETIME - FADE else clampf((LIFETIME - _age) / FADE, 0.0, 1.0)
	for i in _pos.size():
		if _landed[i] == 2:
			continue
		var v := _vel[i]
		v.y -= 9.8 * delta
		v *= 1.0 - 0.25 * delta # air drag
		var p := _pos[i] + v * delta
		_angle[i] += _spin[i] * delta
		var side := 0 if (p - _origin).dot(_normal) >= 0.0 else 1
		var fl := _floor[side] + 0.01
		if p.y <= fl:
			p.y = fl
			if _landed[i] == 0 and absf(v.y) > 1.2:
				v = Vector3(v.x * 0.4, -v.y * 0.28, v.z * 0.4)
				_landed[i] = 1
			else:
				v = Vector3.ZERO
				_landed[i] = 2
				_spin[i] = 0.0
		_vel[i] = v
		_pos[i] = p
	_update_transforms(fade)


func _exit_tree() -> void:
	_active.erase(self)


func _update_transforms(fade: float) -> void:
	for i in _pos.size():
		var b: Basis
		if _landed[i] == 2:
			b = Basis(Vector3.UP, _angle[i]) * Basis(Vector3.RIGHT, -PI * 0.5) # lying flat on the floor
		else:
			b = Basis(_axis[i], _angle[i])
		_mm.set_instance_transform(i, Transform3D(b.scaled_local(Vector3.ONE * _scale[i] * fade), _pos[i]))
