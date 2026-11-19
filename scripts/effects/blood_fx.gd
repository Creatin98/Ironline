class_name BloodFx
extends RefCounted
## Blood: spray particles plus splats on nearby walls/floor (world), and the procedural splat
## textures shared with the HUD's screen splatter. Fully procedural, no assets.

const MAX_WORLD_SPLATS := 520 # the map gets used: blood stays for a long time
const SPLAT_LIFETIME := 240.0
const FADE_TIME := 25.0
const VARIANTS := 4
const TEX_SIZE := 256

static var _textures: Array[ImageTexture] = []
static var _materials: Array[StandardMaterial3D] = []
static var _live: Array = []
static var _particle_mesh: Mesh


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
	var count := 5 + int(round(5.0 * scale))
	for i in count:
		var d := dir
		var reach := 4.6
		match i:
			0:
				d = dir
			1:
				d = Vector3.DOWN
				reach = 2.8
			_:
				d = (dir + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1))).normalized()
				reach = 4.2
		var q := PhysicsRayQueryParameters3D.create(pos, pos + d * reach, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["normal"] as Vector3).length() < 0.5:
			continue # (a ray that starts inside a collider has no normal)
		var dist := pos.distance_to(hit["position"])
		var size := rng.randf_range(0.7, 1.4) * lerpf(1.0, 0.7, clampf(dist / reach, 0.0, 1.0)) * (0.65 + 0.35 * scale)
		_place_splat(parent, hit["position"], hit["normal"], size, rng)


## A thin dark-red streak (long axis = Y, which the particles align with their velocity): spray and fountains, no balls.
static func streak_mesh() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = 0.0035
	m.height = 0.075
	m.radial_segments = 4
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.015, 0.012)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	return m


static func _spawn_particles(parent: Node3D, pos: Vector3, dir: Vector3, scale: float) -> void:
	if _particle_mesh == null:
		_particle_mesh = BloodFx.streak_mesh()
	var p := CPUParticles3D.new()
	p.mesh = _particle_mesh
	p.particle_flag_align_y = true # thin streaks along the flight direction, no round balls
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(6, int(90.0 * scale * GameSettings.effects_scale()))
	p.lifetime = 0.7
	p.direction = dir
	p.spread = 38.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0.0, -11.0, 0.0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 2.2
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
	_fade_later(mi, SPLAT_LIFETIME)
	# on walls and barrels the blood runs down (slowly, ending in a bead)
	if absf(normal.y) < 0.4 and size > 0.55 and rng.randf() < 0.7:
		_drip(mi, pos, normal, rng)
		if size > 0.9 and rng.randf() < 0.6:
			_drip(mi, pos + normal.cross(Vector3.UP).normalized() * rng.randf_range(-0.12, 0.12), normal, rng)


## Fades a node out over FADE_TIME at the end of its life and frees it (a tween bound to the node: no dangling callbacks).
static func _fade_later(mi: GeometryInstance3D, life: float) -> void:
	var tw := mi.create_tween()
	tw.tween_interval(maxf(life - FADE_TIME, 0.1))
	tw.tween_property(mi, "transparency", 1.0, FADE_TIME)
	tw.tween_callback(mi.queue_free)


## A run of blood on a vertical surface: a thin streak that grows downwards, thickest at the top, with a bead at its end.
static func _drip(decal: Node3D, pos: Vector3, normal: Vector3, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(0.25, 0.85)
	var width := rng.randf_range(0.018, 0.04)
	var q := QuadMesh.new()
	q.size = Vector2(width, 1.0)
	q.center_offset = Vector3(0, -0.5, 0) # grows downwards from its top edge
	var run := MeshInstance3D.new()
	run.mesh = q
	run.material_override = _drip_material()
	run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.add_child(run)
	var z := normal.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	run.global_transform = Transform3D(Basis(x, y, z), pos + normal * 0.02)
	run.scale = Vector3(1.0, 0.02, 1.0)
	var bead := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(width * 2.1, width * 2.4)
	bead.mesh = bq
	bead.material_override = _drip_material(true)
	bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.add_child(bead)
	bead.global_transform = Transform3D(Basis(x, y, z), pos + normal * 0.021)
	var dur := rng.randf_range(3.0, 7.0)
	var tw := run.create_tween().set_parallel(true)
	tw.tween_property(run, "scale:y", length, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bead, "global_position", pos + normal * 0.021 + Vector3.DOWN * length, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_later(run, SPLAT_LIFETIME)
	_fade_later(bead, SPLAT_LIFETIME)


static var _drip_mat: StandardMaterial3D
static var _bead_mat: StandardMaterial3D


static func _drip_material(bead: bool = false) -> StandardMaterial3D:
	if _drip_mat == null:
		var img := Image.create(16, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			var t := float(y) / 127.0
			var w := lerpf(0.5, 0.18, t) # tapers towards the end
			for x in 16:
				var dx := absf(float(x) / 15.0 * 2.0 - 1.0)
				var a := clampf((w * 2.0 - dx) / 0.35, 0.0, 1.0) * clampf((1.0 - t) * 6.0 + 0.4, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.albedo_color = Color(0.28, 0.006, 0.006, 0.92)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.render_priority = 2
		_drip_mat = m
		var n := 24
		var bi := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var p := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0)
				bi.set_pixel(x, y, Color(1, 1, 1, clampf((0.95 - p.length()) / 0.2, 0.0, 1.0)))
		var bm := m.duplicate() as StandardMaterial3D
		bm.albedo_texture = ImageTexture.create_from_image(bi)
		bm.albedo_color = Color(0.34, 0.01, 0.01, 0.95)
		_bead_mat = bm
	return _bead_mat if bead else _drip_mat


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
	_fade_later(mi, SPLAT_LIFETIME + 30.0)


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
