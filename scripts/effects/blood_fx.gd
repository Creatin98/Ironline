class_name BloodFx
extends RefCounted
## Blood: spray particles plus splats on nearby walls/floor (world), and the procedural splat
## textures shared with the HUD's screen splatter. Fully procedural, no assets.

const MAX_WORLD_SPLATS := 90
const SPLAT_LIFETIME := 25.0
const VARIANTS := 4
const TEX_SIZE := 160

static var _textures: Array[ImageTexture] = []
static var _materials: Array[StandardMaterial3D] = []
static var _live: Array = []
static var _particle_mesh: SphereMesh
static var _particle_mat: StandardMaterial3D


## Splat texture `i` (white blob, alpha = shape); tint with the draw colour.
static func splat_texture(i: int) -> ImageTexture:
	if _textures.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 90210
		for v in VARIANTS:
			_textures.append(_make_texture(rng))
	return _textures[i % VARIANTS]


## A realistic splash: an irregular main body that stretches in one direction and a spray of cast-off drops
## (round near the body, elongated with a tail towards the body farther out) plus fine mist. Different per variant.
static func _make_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var bias := rng.randf() * TAU
	var base := rng.randf_range(0.15, 0.23)
	var phases: Array[float] = []
	var amps: Array[float] = []
	for k in 6:
		phases.append(rng.randf() * TAU)
		amps.append(rng.randf_range(0.2, 0.5) * base / (1.0 + k * 0.5))
	var stretch := rng.randf_range(0.04, 0.16)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var px := (float(x) / (TEX_SIZE - 1)) * 2.0 - 1.0
			var py := (float(y) / (TEX_SIZE - 1)) * 2.0 - 1.0
			var r := sqrt(px * px + py * py)
			var ang := atan2(py, px)
			var edge := base + stretch * pow(maxf(0.0, cos(ang - bias)), 3.0)
			for k in amps.size():
				edge += amps[k] * sin(ang * float(k + 2) + phases[k])
			var a := clampf((edge - r) / 0.035, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	# cast-off drops: mostly in the direction of the splash
	for i in rng.randi_range(26, 40):
		var dir_a := bias + rng.randfn(0.0, 0.85)
		var dist := 0.2 + pow(rng.randf(), 1.5) * 0.72
		var radius := lerpf(0.05, 0.012, dist) * rng.randf_range(0.6, 1.5)
		var c := Vector2(cos(dir_a), sin(dir_a)) * dist
		var tail := radius * rng.randf_range(0.0, 3.5) * clampf(dist * 1.6, 0.0, 1.0)
		_drop(img, c, radius, tail, -Vector2(cos(dir_a), sin(dir_a)))
	# fine mist
	for i in rng.randi_range(30, 55):
		var dir_a := bias + rng.randfn(0.0, 1.25)
		var dist := rng.randf_range(0.25, 0.95)
		_drop(img, Vector2(cos(dir_a), sin(dir_a)) * dist, rng.randf_range(0.006, 0.013), 0.0, Vector2.ZERO)
	return ImageTexture.create_from_image(img)


## A drop (optionally with a tail that points to `tail_dir`) at `c` (-1..1 space), only the pixels near it are touched.
static func _drop(img: Image, c: Vector2, radius: float, tail: float, tail_dir: Vector2) -> void:
	var half := float(TEX_SIZE - 1) * 0.5
	var reach := radius + tail + 0.02
	var x0 := clampi(int((c.x - reach + 1.0) * half), 0, TEX_SIZE - 1)
	var x1 := clampi(int((c.x + reach + 1.0) * half) + 1, 0, TEX_SIZE - 1)
	var y0 := clampi(int((c.y - reach + 1.0) * half), 0, TEX_SIZE - 1)
	var y1 := clampi(int((c.y + reach + 1.0) * half) + 1, 0, TEX_SIZE - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(float(x) / half - 1.0, float(y) / half - 1.0)
			var t := 0.0
			if tail > 0.0:
				t = clampf((p - c).dot(tail_dir) / tail, 0.0, 1.0)
			var centre := c + tail_dir * tail * t
			var rr := radius * (1.0 - 0.75 * t)
			var a := clampf((rr - p.distance_to(centre)) / 0.01, 0.0, 1.0)
			if a > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(1, 1, 1, a))


static func _material(i: int) -> StandardMaterial3D:
	if _materials.is_empty():
		for v in VARIANTS:
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = splat_texture(v)
			m.albedo_color = Color(0.36, 0.015, 0.015, 0.92)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 1.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.render_priority = 1
			_materials.append(m)
	return _materials[i % VARIANTS]


## Blood spray at `pos` flying along `dir` (direction of the bullet), plus splats on nearby surfaces.
## `scale`: 1 for a normal hit, smaller for single shotgun pellets.
static func burst(parent: Node3D, pos: Vector3, dir: Vector3, scale: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.DOWN
	_spawn_particles(parent, pos, dir, scale)
	var space := parent.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := 2 + int(round(3.0 * scale))
	for i in count:
		var d := dir
		var reach := 3.2
		match i:
			0:
				d = dir
			1:
				d = Vector3.DOWN
				reach = 2.4
			_:
				d = (dir + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1))).normalized()
				reach = 2.8
		var q := PhysicsRayQueryParameters3D.create(pos, pos + d * reach, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dist := pos.distance_to(hit["position"])
		var size := rng.randf_range(0.35, 0.7) * lerpf(1.0, 0.6, clampf(dist / reach, 0.0, 1.0)) * (0.65 + 0.35 * scale)
		_place_splat(parent, hit["position"], hit["normal"], size, rng)


static func _spawn_particles(parent: Node3D, pos: Vector3, dir: Vector3, scale: float) -> void:
	if _particle_mesh == null:
		_particle_mesh = SphereMesh.new()
		_particle_mesh.radius = 0.03
		_particle_mesh.height = 0.06
		_particle_mesh.radial_segments = 6
		_particle_mesh.rings = 3
		_particle_mat = StandardMaterial3D.new()
		_particle_mat.albedo_color = Color(0.5, 0.02, 0.02)
		_particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_particle_mesh.material = _particle_mat
	var p := CPUParticles3D.new()
	p.mesh = _particle_mesh
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(4, int(36.0 * scale * GameSettings.effects_scale()))
	p.lifetime = 0.7
	p.direction = dir
	p.spread = 38.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0.0, -11.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	p.emitting = true
	parent.add_child(p)
	p.global_position = pos
	parent.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


static func _place_splat(parent: Node3D, pos: Vector3, normal: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _material(rng.randi())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + normal * (0.012 + rng.randf() * 0.006)
	if absf(normal.dot(Vector3.UP)) > 0.99:
		mi.look_at(mi.global_position - normal, Vector3.FORWARD)
	else:
		mi.look_at(mi.global_position - normal, Vector3.UP)
	mi.rotate_object_local(Vector3.BACK, rng.randf() * TAU)
	_live.append(mi)
	while _live.size() > MAX_WORLD_SPLATS:
		var oldest = _live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	parent.get_tree().create_timer(SPLAT_LIFETIME).timeout.connect(mi.queue_free)
