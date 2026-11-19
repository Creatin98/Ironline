class_name Vegetation
extends RefCounted
## Prozedurale Pflanzen und Terrain: Palmen, dichte mehrschichtige Blatt-Büsche und Hügel.

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


static func palm_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
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
			ring.append(c + Vector3(cos(a) * r, 0.0, sin(a) * r))
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

			st.set_uv(Vector2(u0, t0))
			st.add_vertex(v00)
			st.set_uv(Vector2(u0, t1))
			st.add_vertex(v10)
			st.set_uv(Vector2(u1, t1))
			st.add_vertex(v11)

			st.set_uv(Vector2(u0, t0))
			st.add_vertex(v00)
			st.set_uv(Vector2(u1, t1))
			st.add_vertex(v11)
			st.set_uv(Vector2(u1, t0))
			st.add_vertex(v01)

	st.generate_normals()
	mesh = st.commit()
	mesh.surface_set_material(0, _bark_material())

	var top := Vector3(0.35, height, 0.0)
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 11
	for f in fronds:
		var yaw := TAU * float(f) / float(fronds) + float(f % 3) * 0.2
		var rise := 0.55 + 0.35 * float((f * 7) % 5) / 4.0
		var length := 2.5 + 0.5 * float((f * 3) % 4) / 3.0
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var half_w := 0.55
		var steps := 5
		for s in steps:
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var p0 := top + dir * (length * t0) + Vector3(0.0, length * (rise * t0 - 0.95 * t0 * t0), 0.0)
			var p1 := top + dir * (length * t1) + Vector3(0.0, length * (rise * t1 - 0.95 * t1 * t1), 0.0)
			var w0 := half_w * pow(sin(PI * clampf(0.12 + 0.88 * t0, 0.0, 1.0)), 0.6)
			var w1 := half_w * pow(sin(PI * clampf(0.12 + 0.88 * t1, 0.0, 1.0)), 0.6)
			var a := p0 - side * w0
			var b := p0 + side * w0
			var c := p1 + side * w1
			var d := p1 - side * w1

			cs.set_normal(Vector3.UP)
			cs.set_uv(Vector2(0.0, t0))
			cs.add_vertex(a)
			cs.set_uv(Vector2(1.0, t0))
			cs.add_vertex(b)
			cs.set_uv(Vector2(1.0, t1))
			cs.add_vertex(c)

			cs.set_uv(Vector2(0.0, t0))
			cs.add_vertex(a)
			cs.set_uv(Vector2(1.0, t1))
			cs.add_vertex(c)
			cs.set_uv(Vector2(0.0, t1))
			cs.add_vertex(d)

	cs.commit(mesh)
	mesh.surface_set_material(1, _foliage_material("res://assets/textures/palm_frond.png", Color(1.0, 1.0, 1.0), true, 0.16))
	return mesh


## Voller, dichter Blatt-Busch (reicht bis zum Boden, ohne Lücke unten)
static func bush_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var card_count := 36
	for i in card_count:
		var fi := float(i)
		var yaw := fmod(fi * 2.399963, TAU)
		var layer := fi / float(card_count) # 0 = unten breit am Boden, 1 = oben Krone
		var pitch := lerpf(0.15, 1.15, layer) + sin(fi * 2.7) * 0.22
		var dist := lerpf(0.32, 0.05, layer)
		var card_w := lerpf(0.82, 0.52, layer)
		var card_h := lerpf(0.68, 0.48, layer)

		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		# Untere Karten sitzen tiefer (-0.14), damit der Busch satt auf dem Boden aufliegt
		var center := dir * dist + Vector3(0.0, lerpf(-0.14, 0.30, layer), 0.0)

		var out_dir := (dir * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
		var up_card := side.cross(out_dir).normalized()
		var bend := out_dir * 0.08

		var v_bl := center - side * (card_w * 0.5) - up_card * (card_h * 0.42)
		var v_br := center + side * (card_w * 0.5) - up_card * (card_h * 0.42)
		var v_tr := center + side * (card_w * 0.5) + up_card * (card_h * 0.58) + bend
		var v_tl := center - side * (card_w * 0.5) + up_card * (card_h * 0.58) + bend

		var col_inner := Color(0.28, 0.34, 0.24)
		var col_tip := Color(0.90, 0.96, 0.82)
		var nrm := (out_dir + Vector3.UP * 0.55).normalized()

		st.set_normal(nrm)
		st.set_color(col_inner)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(v_bl)

		st.set_color(col_inner)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(v_br)

		st.set_color(col_tip)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(v_tr)

		st.set_color(col_inner)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(v_bl)

		st.set_color(col_tip)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(v_tr)

		st.set_color(col_tip)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(v_tl)

	var mesh := st.commit()
	var m := _foliage_material("res://assets/textures/palm_frond.png", Color(0.64, 0.80, 0.48), true, 0.06)
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
		var yaw := float(it.get("yaw", 0.0))
		var pos: Vector3 = it["pos"]

		var basis := Basis(Vector3.UP, yaw).scaled_local(sc)
		var tilt: float = it.get("tilt", 0.0)
		if tilt != 0.0:
			basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(sc)
		mm.set_instance_transform(i, Transform3D(basis, pos))
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
