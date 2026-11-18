class_name BloodFx
extends RefCounted
## Blood: spray particles plus splats on nearby walls/floor (world), and the procedural splat
## textures shared with the HUD's screen splatter. Fully procedural, no assets.

const MAX_WORLD_SPLATS := 90
const SPLAT_LIFETIME := 25.0
const VARIANTS := 4
const TEX_SIZE := 256

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


## Fine spatter: a few tiny irregular cores and a lot of small cast-off drops that fly in one direction - round near the
## source, long thin streaks with a tail pointing back to the source farther out - plus a haze of mist. Every drop has its
## own opacity, so it reads as wet spray on the surface instead of a paint blob. Different per variant.
static func _make_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var bias := rng.randf() * TAU
	var bdir := Vector2(cos(bias), sin(bias))
	# a small ragged core at the impact point
	for i in rng.randi_range(2, 4):
		var c := Vector2(rng.randfn(0.0, 0.05), rng.randfn(0.0, 0.05))
		_drop(img, c, rng.randf_range(0.028, 0.055), rng.randf_range(0.0, 0.1), -bdir, rng.randf_range(0.8, 1.0))
	# cast-off drops along the direction, wide scatter
	for i in rng.randi_range(70, 110):
		var dir_a := bias + rng.randfn(0.0, 0.55)
		var dist := 0.08 + pow(rng.randf(), 1.25) * 0.88
		var radius := lerpf(0.026, 0.005, dist) * rng.randf_range(0.5, 1.3)
		var c := Vector2(cos(dir_a), sin(dir_a)) * dist
		var tail := radius * rng.randf_range(0.5, 7.0) * clampf(dist * 1.8, 0.0, 1.0)
		_drop(img, c, radius, tail, -Vector2(cos(dir_a), sin(dir_a)), rng.randf_range(0.55, 1.0))
	# mist
	for i in rng.randi_range(60, 110):
		var dir_a := bias + rng.randfn(0.0, 1.0)
		var dist := rng.randf_range(0.1, 0.97)
		_drop(img, Vector2(cos(dir_a), sin(dir_a)) * dist, rng.randf_range(0.0035, 0.008), 0.0, Vector2.ZERO, rng.randf_range(0.4, 0.9))
	return ImageTexture.create_from_image(img)


## A drop (optionally with a tail that points to `tail_dir`) at `c` (-1..1 space), only the pixels near it are touched.
static func _drop(img: Image, c: Vector2, radius: float, tail: float, tail_dir: Vector2, opacity: float = 1.0) -> void:
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
			var a := clampf((rr - p.distance_to(centre)) / 0.006, 0.0, 1.0) * opacity
			if a > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(1, 1, 1, a))


static func _material(i: int) -> StandardMaterial3D:
	if _materials.is_empty():
		for v in VARIANTS:
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = splat_texture(v)
			m.albedo_color = Color(0.3, 0.008, 0.008, 0.95)
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
		var size := rng.randf_range(0.7, 1.4) * lerpf(1.0, 0.7, clampf(dist / reach, 0.0, 1.0)) * (0.65 + 0.35 * scale)
		_place_splat(parent, hit["position"], hit["normal"], size, rng)


static func _spawn_particles(parent: Node3D, pos: Vector3, dir: Vector3, scale: float) -> void:
	if _particle_mesh == null:
		_particle_mesh = SphereMesh.new()
		_particle_mesh.radius = 0.011
		_particle_mesh.height = 0.022
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
	p.amount = maxi(4, int(60.0 * scale * GameSettings.effects_scale()))
	p.lifetime = 0.7
	p.direction = dir
	p.spread = 38.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0.0, -11.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
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


## A pool of blood that spreads under a body: irregular dark patch, grows over a few seconds, stays a while.
static func pool(parent: Node, pos: Vector3, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var space := (parent as Node3D).get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -2.0, 0), 1))
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	if n.dot(Vector3.UP) < 0.7:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _pool_texture()
	m.albedo_color = Color(0.26, 0.005, 0.005, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = hit["position"] + Vector3(0, 0.014, 0)
	mi.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_live.append(mi)
	parent.get_tree().create_timer(SPLAT_LIFETIME + 10.0).timeout.connect(mi.queue_free)


static var _pool_tex: ImageTexture


static func _pool_texture() -> ImageTexture:
	if _pool_tex != null:
		return _pool_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var ph: Array[float] = []
	for k in 5:
		ph.append(rng.randf() * TAU)
	for y in n:
		for x in n:
			var p := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0)
			var ang := atan2(p.y, p.x)
			var edge := 0.62 + 0.13 * sin(ang * 3.0 + ph[0]) + 0.09 * sin(ang * 5.0 + ph[1]) + 0.06 * sin(ang * 8.0 + ph[2])
			var a := clampf((edge - p.length()) / 0.12, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_pool_tex = ImageTexture.create_from_image(img)
	return _pool_tex
