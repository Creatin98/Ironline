class_name Vegetation
extends RefCounted
## Prozedurale Pflanzen und Terrain: Palmen, mehrschichtige Blatt-Büsche mit Pflanzbeeten und Hügel.

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


static func bush_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var card_count := 30
	for i in card_count:
		var fi := float(i)
		var yaw := fmod(fi * 2.399963, TAU)
		var layer := fi / float(card_count)
		var pitch := lerpf(0.28, 1.25, layer) + sin(fi * 3.1) * 0.18
		var dist := lerpf(0.24, 0.06, layer)
		var card_w := lerpf(0.68, 0.48, layer)
		var card_h := lerpf(0.58, 0.44, layer)

		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var center := dir * dist + Vector3(0.0, lerpf(0.05, 0.34, layer), 0.0)

		var out_dir := (dir * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
		var up_card := side.cross(out_dir).normalized()
		var bend := out_dir * 0.09

		var v_bl := center - side * (card_w * 0.5) - up_card * (card_h * 0.35)
		var v_br := center + side * (card_w * 0.5) - up_card * (card_h * 0.35)
		var v_tr := center + side * (card_w * 0.5) + up_card * (card_h * 0.65) + bend
		var v_tl := center - side * (card_w * 0.5) + up_card * (card_h * 0.65) + bend

		var col_inner := Color(0.32, 0.36, 0.28)
		var col_tip := Color(0.88, 0.94, 0.80)
		var nrm := (out_dir + Vector3.UP * 0.6).normalized()

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
	var m := _foliage_material("res://assets/textures/palm_frond.png", Color(0.62, 0.78, 0.46), true, 0.06)
	mesh.surface_set_material(0, m)
	return mesh


static func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3) -> void:
	st.set_normal(nrm)
	st.set_uv(Vector2(p0.x + p0.z, p0.y) * 0.5)
	st.add_vertex(p0)
	st.set_uv(Vector2(p1.x + p1.z, p1.y) * 0.5)
	st.add_vertex(p1)
	st.set_uv(Vector2(p2.x + p2.z, p2.y) * 0.5)
	st.add_vertex(p2)

	st.set_uv(Vector2(p0.x + p0.z, p0.y) * 0.5)
	st.add_vertex(p0)
	st.set_uv(Vector2(p2.x + p2.z, p2.y) * 0.5)
	st.add_vertex(p2)
	st.set_uv(Vector2(p3.x + p3.z, p3.y) * 0.5)
	st.add_vertex(p3)


static func _planter_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := 0.72
	var hd := 0.72
	var h := 0.36
	var rim := 0.14
	var iw := hw - rim
	var id := hd - rim

	# Außenwände des Beton-Pflanzbeets
	_add_quad(st, Vector3(-hw, 0.0, hd), Vector3(hw, 0.0, hd), Vector3(hw, h, hd), Vector3(-hw, h, hd), Vector3.BACK)
	_add_quad(st, Vector3(hw, 0.0, -hd), Vector3(-hw, 0.0, -hd), Vector3(-hw, h, -hd), Vector3(hw, h, -hd), Vector3.FORWARD)
	_add_quad(st, Vector3(hw, 0.0, hd), Vector3(hw, 0.0, -hd), Vector3(hw, h, -hd), Vector3(hw, h, hd), Vector3.RIGHT)
	_add_quad(st, Vector3(-hw, 0.0, -hd), Vector3(-hw, 0.0, hd), Vector3(-hw, h, hd), Vector3(-hw, h, -hd), Vector3.LEFT)

	# Oberer Steinrand (4 Streifen um die Erde)
	_add_quad(st, Vector3(-hw, h, hd), Vector3(hw, h, hd), Vector3(iw, h, id), Vector3(-iw, h, id), Vector3.UP)
	_add_quad(st, Vector3(hw, h, -hd), Vector3(-hw, h, -hd), Vector3(-iw, h, -id), Vector3(iw, h, -id), Vector3.UP)
	_add_quad(st, Vector3(hw, h, hd), Vector3(hw, h, -hd), Vector3(iw, h, -id), Vector3(iw, h, id), Vector3.UP)
	_add_quad(st, Vector3(-hw, h, -hd), Vector3(-hw, h, hd), Vector3(-iw, h, id), Vector3(-iw, h, -id), Vector3.UP)

	var mesh := st.commit()
	if ResourceLoader.exists("res://assets/materials/concrete.tres"):
		mesh.surface_set_material(0, load("res://assets/materials/concrete.tres"))

	# Dunkle Erde im Beet
	var soil_st := SurfaceTool.new()
	soil_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sy := h - 0.06
	_add_quad(soil_st, Vector3(-iw, sy, id), Vector3(iw, sy, id), Vector3(iw, sy, -id), Vector3(-iw, sy, -id), Vector3.UP)
	soil_st.commit(mesh)

	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.14, 0.11, 0.08)
	soil_mat.roughness = 0.95
	mesh.surface_set_material(1, soil_mat)
	return mesh


static func scatter(parent: Node3D, mesh: Mesh, items: Array, node_name: String) -> void:
	if items.is_empty():
		return
	var is_bush := node_name.to_lower().contains("bush")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()

	var planter_mm: MultiMesh = null
	if is_bush:
		planter_mm = MultiMesh.new()
		planter_mm.transform_format = MultiMesh.TRANSFORM_3D
		planter_mm.mesh = _planter_mesh()
		planter_mm.instance_count = items.size()

	for i in items.size():
		var it: Dictionary = items[i]
		var sc: Vector3 = it.get("scale3", Vector3.ONE * float(it.get("scale", 1.0)))
		var yaw := float(it.get("yaw", 0.0))
		var pos: Vector3 = it["pos"]

		if is_bush and planter_mm != null:
			var p_basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(sc.x, 1.0, sc.z))
			planter_mm.set_instance_transform(i, Transform3D(p_basis, Vector3(pos.x, maxf(0.0, pos.y - 0.25), pos.z)))
			pos = Vector3(pos.x, maxf(0.28, pos.y), pos.z)

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

	if planter_mm != null:
		var pmi := MultiMeshInstance3D.new()
		pmi.name = node_name + "_Planters"
		pmi.multimesh = planter_mm
		parent.add_child(pmi)


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
