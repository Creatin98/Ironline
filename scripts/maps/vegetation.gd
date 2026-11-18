class_name Vegetation
extends RefCounted
## Procedural plants and terrain for maps: palms (trunk + crown of alpha-cut fronds), bushes and rolling hills,
## each kind as one MultiMesh (one draw call). Fronds and bushes sway in the wind (assets/shaders/foliage.gdshader).
## Purely visual: collisions of trunks are placed by the map as blocks.

const SHADER := "res://assets/shaders/foliage.gdshader"


static func _foliage_material(tex_path: String, tint: Color, alpha_mode: bool, sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("tex", load(tex_path))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("alpha_mode", alpha_mode)
	m.set_shader_parameter("sway", sway)
	return m


static func _bark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/bark.png")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/bark_n.png")
	m.roughness = 1.0
	m.roughness_texture = load("res://assets/textures/bark_r.png")
	m.uv1_scale = Vector3(2.0, 3.0, 1.0)
	return m


## Palm mesh: surface 0 = trunk (tapered, 8 sides, slightly curved), surface 1 = crown (fronds). Height ~6 m.
static func palm_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# trunk
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	var sides := 8
	var height := 6.0
	var rings: Array = []
	for i in segs + 1:
		var t := float(i) / float(segs)
		var r := lerpf(0.26, 0.16, t)
		var c := Vector3(0.35 * t * t, t * height, 0.0)
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			ring.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
		rings.append(ring)
	for i in segs:
		for k in sides:
			var k2 := (k + 1) % sides
			var v00: Vector3 = rings[i][k]
			var v01: Vector3 = rings[i][k2]
			var v10: Vector3 = rings[i + 1][k]
			var v11: Vector3 = rings[i + 1][k2]
			var u0 := float(k) / float(sides)
			var u1 := float(k + 1) / float(sides)
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			for q in [[v00, u0, t0], [v10, u0, t1], [v11, u1, t1], [v00, u0, t0], [v11, u1, t1], [v01, u1, t0]]:
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	st.generate_normals()
	mesh = st.commit()
	mesh.surface_set_material(0, _bark_material())
	# crown
	var top := Vector3(0.35, height, 0.0)
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 11
	for f in fronds:
		var yaw := TAU * float(f) / float(fronds) + float(f % 3) * 0.2
		var rise := 0.55 + 0.35 * float((f * 7) % 5) / 4.0
		var length := 2.5 + 0.5 * float((f * 3) % 4) / 3.0
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-sin(yaw), 0, cos(yaw))
		var half_w := 0.55
		var steps := 5
		for s in steps:
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var p0 := top + dir * (length * t0) + Vector3(0, length * (rise * t0 - 0.95 * t0 * t0), 0)
			var p1 := top + dir * (length * t1) + Vector3(0, length * (rise * t1 - 0.95 * t1 * t1), 0)
			var w0 := half_w * sin(PI * clampf(0.12 + 0.88 * t0, 0.0, 1.0)) ** 0.6
			var w1 := half_w * sin(PI * clampf(0.12 + 0.88 * t1, 0.0, 1.0)) ** 0.6
			var a := p0 - side * w0
			var b := p0 + side * w0
			var c := p1 + side * w1
			var d := p1 - side * w1
			for q in [[a, 0.0, t0], [b, 1.0, t0], [c, 1.0, t1], [a, 0.0, t0], [c, 1.0, t1], [d, 0.0, t1]]:
				cs.set_uv(Vector2(q[1], q[2]))
				cs.set_normal(Vector3(0, 1, 0))
				cs.add_vertex(q[0])
	cs.commit(mesh)
	mesh.surface_set_material(1, _foliage_material("res://assets/textures/palm_frond.png", Color(1.0, 1.0, 1.0), true, 0.16))
	return mesh


## Bush: a lumpy low sphere with leaf texture (tint per instance through the multimesh colours).
static func bush_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.8
	sphere.radial_segments = 10
	sphere.rings = 5
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	var m := _foliage_material("res://assets/textures/foliage.png", Color(1, 1, 1), false, 0.05)
	m.set_shader_parameter("tex_scale", 3.0)
	mesh.surface_set_material(0, m)
	return mesh


## items: [{"pos": Vector3, "scale": float, "yaw": float, "color": Color (optional)}]
static func scatter(parent: Node3D, mesh: Mesh, items: Array, node_name: String) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var it: Dictionary = items[i]
		var sc: Vector3 = it.get("scale3", Vector3.ONE * float(it.get("scale", 1.0)))
		var basis := Basis(Vector3.UP, float(it.get("yaw", 0.0))).scaled_local(sc)
		var tilt: float = it.get("tilt", 0.0)
		if tilt != 0.0:
			basis = Basis(Vector3.UP, float(it.get("yaw", 0.0))) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(sc)
		mm.set_instance_transform(i, Transform3D(basis, it["pos"]))
		mm.set_instance_color(i, it.get("color", Color.WHITE))
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	parent.add_child(mi)


## Hills around the playing area (huge squashed spheres with the ground texture, no collision).
static func hills(parent: Node3D, material: Material, items: Array) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 20
	sphere.rings = 10
	sphere.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = items.size()
	for i in items.size():
		var it: Dictionary = items[i]
		var basis := Basis(Vector3.UP, float(it.get("yaw", 0.0))).scaled_local(it["size"])
		mm.set_instance_transform(i, Transform3D(basis, it["pos"]))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Hills"
	mi.multimesh = mm
	parent.add_child(mi)
