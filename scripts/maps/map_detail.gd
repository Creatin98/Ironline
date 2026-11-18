class_name MapDetail
extends RefCounted
## Purely visual architectural detail for BlockMap maps (no colliders, no navigation influence).
## Walls get plinth, cornice, pilasters, pipes and units; openings get frames and sills.
## All pieces are merged into one mesh per material, so the draw call count stays low.

const WALL_MATS := ["plaster", "brick", "concrete", "ship_hull", "metal_panel"]
const TRIM := Color(0.74, 0.72, 0.68)

var _map: BlockMap
var _parts: Dictionary = {} # key -> {"mat": Material, "st": SurfaceTool}
var _box_mesh := BoxMesh.new()
var _cyl_mesh := CylinderMesh.new()
var _cyl_hi := CylinderMesh.new() # map blocks: smoother than the small props
var _lights: Array = []
## Glass panes found at window openings (for GlassField): {center, size, axis_x}
var windows: Array = []


func _init(map: BlockMap) -> void:
	_map = map
	_box_mesh.size = Vector3.ONE
	_cyl_mesh.top_radius = 0.5
	_cyl_mesh.bottom_radius = 0.5
	_cyl_mesh.height = 1.0
	_cyl_mesh.radial_segments = 10
	_cyl_mesh.rings = 1
	_cyl_hi.top_radius = 0.5
	_cyl_hi.bottom_radius = 0.5
	_cyl_hi.height = 1.0
	_cyl_hi.radial_segments = 24
	_cyl_hi.rings = 1


# ----------------------------------------------------------------------------- primitives

func add_box(center: Vector3, size: Vector3, mat: String, tint = null, basis: Basis = Basis.IDENTITY) -> void:
	_append(_box_mesh, Transform3D(basis.scaled_local(size), center), mat, tint)


func add_cylinder(center: Vector3, diameter: float, height: float, mat: String, tint = null, basis: Basis = Basis.IDENTITY) -> void:
	_append(_cyl_mesh, Transform3D(basis.scaled_local(Vector3(diameter, height, diameter)), center), mat, tint)


func _append(mesh: Mesh, xf: Transform3D, mat: String, tint) -> void:
	var key := mat
	if tint != null:
		key += "#" + (tint as Color).to_html()
	if not _parts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_parts[key] = {"mat": _map._get_material(mat, tint), "st": st}
	(_parts[key]["st"] as SurfaceTool).append_from(mesh, 0, xf)


## Visual of a map block (box or cylinder) merged into the per-material meshes. Replaces one MeshInstance3D per block.
func add_block(b: Dictionary) -> void:
	var size: Vector3 = b.get("size", Vector3.ONE)
	var basis := Basis.IDENTITY
	if b.has("basis"):
		basis = b["basis"]
	elif b.has("rot"):
		var r: Vector3 = b["rot"]
		basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	var mat: String = b.get("mat", "concrete")
	var tint = b.get("tint", null)
	if b.get("shape", "box") == "cylinder":
		_append(_cyl_hi, Transform3D(basis.scaled_local(Vector3(size.x, size.y, size.x)), b["pos"]), mat, tint)
	else:
		_append(_box_mesh, Transform3D(basis.scaled_local(size), b["pos"]), mat, tint)


## Real stairs for a sloped collider block (see BlockMap.ramp): solid steps (concrete, plaster, wood) or open
## industrial stairs with risers, treads and stringers (metal). Visual only.
func add_stairs(b: Dictionary) -> void:
	var low: Vector3 = b["low"]
	var high: Vector3 = b["high"]
	var width: float = b["width"]
	var mat: String = b.get("mat", "concrete")
	var tint = b.get("tint", null)
	var rise_total := high.y - low.y
	var n := maxi(2, roundi(rise_total / 0.18))
	var rs := rise_total / float(n)
	var flat := Vector3(high.x - low.x, 0, high.z - low.z)
	var length := flat.length()
	var fwd := flat / length
	var run := length / float(n)
	var basis := Basis(Vector3.UP, atan2(fwd.x, fwd.z))
	var open := mat == "metal_panel"
	for i in n:
		var c := Vector3(low.x, 0, low.z) + fwd * (run * (float(i) + 0.5))
		var top := low.y + float(i + 1) * rs
		if open:
			add_box(Vector3(c.x, top - 0.03, c.z), Vector3(width - 0.1, 0.06, run + 0.03), mat, tint, basis) # tread
			add_box(Vector3(c.x, top - rs * 0.5, c.z) - fwd * (run * 0.5 - 0.012), Vector3(width - 0.1, rs, 0.025), mat, tint, basis) # riser
		else:
			var h := top - low.y
			add_box(Vector3(c.x, low.y + h * 0.5, c.z), Vector3(width, h, run), mat, tint, basis)
			# a lighter nosing line on the tread edge
			add_box(Vector3(c.x, top + 0.004, c.z) - fwd * (run * 0.5 - 0.02), Vector3(width, 0.012, 0.04), "concrete", Color(0.8, 0.78, 0.72), basis)
	if open:
		var side := fwd.cross(Vector3.UP).normalized()
		for sgn in [-1.0, 1.0]:
			var off: Vector3 = side * sgn * (width * 0.5 - 0.04)
			bar(low + off - Vector3(0, 0.1, 0), high + off - Vector3(0, 0.1, 0), 0.07, 0.3, mat, Color(0.2, 0.22, 0.25))


## Finishes all merged meshes and adds them below `parent`.
func flush(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Detail"
	parent.add_child(root)
	for key in _parts:
		var st: SurfaceTool = _parts[key]["st"]
		var mesh := st.commit()
		mesh.surface_set_material(0, _parts[key]["mat"])
		var mi := MeshInstance3D.new()
		mi.name = "Detail_" + String(key).replace("#", "_")
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		root.add_child(mi)
	for l in _lights:
		root.add_child(l)
	_lights.clear()
	_parts.clear()


# ----------------------------------------------------------------------------- automatic detail

func build(blocks: Array) -> void:
	var sills: Array = []
	for b in blocks:
		if not _is_plain_wall(b):
			continue
		var p: Vector3 = b["pos"]
		var s: Vector3 = b["size"]
		if p.y + s.y * 0.5 > 0.35:
			sills.append(b) # any wall piece: the sill of an upper window may be a tall block from the ground up
	for b in blocks:
		if b.get("kind", "") == "car":
			_detail_car(b)
		if not _is_plain_wall(b):
			continue
		_detail_wall(b, sills)


## Parked car: glazing, lights, bumpers, grille and hub caps on top of the plain body blocks.
func _detail_car(b: Dictionary) -> void:
	var basis: Basis = b["basis"]
	var c: Vector3 = b["pos"] - Vector3(0, 0.65, 0)
	var glass := Color(0.3, 0.4, 0.48)
	add_box(c + basis * Vector3(0, 1.4, 0.2), Vector3(1.74, 0.4, 1.9), "metal_panel", glass, basis)
	add_box(c + basis * Vector3(0, 1.38, -0.92), Vector3(1.6, 0.4, 0.08), "metal_panel", glass, basis * Basis(Vector3.RIGHT, deg_to_rad(-25)))
	add_box(c + basis * Vector3(0, 1.74, 0.2), Vector3(1.66, 0.06, 2.0), "metal_panel", (b["tint"] as Color) * 0.9, basis)
	for sx in [-0.62, 0.62]:
		add_box(c + basis * Vector3(sx, 0.78, -2.21), Vector3(0.36, 0.16, 0.05), "lamp", Color(1.0, 0.96, 0.82), basis)
		add_box(c + basis * Vector3(sx, 0.78, 2.21), Vector3(0.36, 0.14, 0.05), "lamp", Color(0.9, 0.1, 0.08), basis)
	for z in [-2.24, 2.24]:
		add_box(c + basis * Vector3(0, 0.3, z), Vector3(1.96, 0.2, 0.1), "metal_panel", Color(0.12, 0.13, 0.14), basis)
	add_box(c + basis * Vector3(0, 0.62, -2.21), Vector3(0.9, 0.2, 0.04), "metal_panel", Color(0.06, 0.06, 0.07), basis)
	for wx in [-1.0, 1.0]:
		for wz in [-1.4, 1.4]:
			add_cylinder(c + basis * Vector3(wx * 0.99, 0.35, wz), 0.42, 0.04, "metal_panel", Color(0.7, 0.72, 0.75), basis * Basis(Vector3.BACK, PI * 0.5))


func _is_plain_wall(b: Dictionary) -> bool:
	if not b.get("visible", true) or not b.get("collide", true):
		return false
	if b.get("shape", "box") != "box" or b.has("basis") or b.has("rot"):
		return false
	if not (String(b.get("mat", "")) in WALL_MATS):
		return false
	var s: Vector3 = b["size"]
	return minf(s.x, s.z) <= 0.6 and maxf(s.x, s.z) >= 0.8 and s.y >= 0.3


func _detail_wall(b: Dictionary, sills: Array) -> void:
	var p: Vector3 = b["pos"]
	var s: Vector3 = b["size"]
	var mat: String = b["mat"]
	var tint = b.get("tint", null)
	var along_x := s.x >= s.z
	var length := s.x if along_x else s.z
	var thick := s.z if along_x else s.x
	var bottom := p.y - s.y * 0.5
	var top := p.y + s.y * 0.5
	var industrial := mat == "metal_panel" or mat == "ship_hull"
	var seed_v := _hash(p)

	# opening above (header): frame, lintel and a sill ledge
	if bottom >= 1.4 and s.y <= 1.7 and length <= 3.6:
		_frame_opening(b, sills, along_x, length, thick, bottom, industrial)
		return

	# cornice / coping on top of walls
	if top >= 2.3 and s.y >= 0.4:
		var cap := Vector3(length, 0.14, thick + 0.2)
		if along_x:
			add_box(Vector3(p.x, top + 0.07, p.z), cap, "concrete", _trim_tint(industrial))
		else:
			add_box(Vector3(p.x, top + 0.07, p.z), Vector3(cap.z, cap.y, cap.x), "concrete", _trim_tint(industrial))

	if s.y < 1.8:
		return
	# plinth at the foot of the wall
	if bottom < 0.3:
		var plinth_h := 0.45
		var px := thick + 0.12 if not along_x else length
		var pz := length if not along_x else thick + 0.12
		add_box(Vector3(p.x, bottom + plinth_h * 0.5, p.z), Vector3(px, plinth_h, pz), "concrete", Color(0.52, 0.5, 0.47))

	# pilasters on long walls (every ~4 m), vertical drain pipe, wall unit
	if length >= 4.5:
		var count := int(length / 4.0)
		var step := length / float(count)
		for i in count:
			var off := -length * 0.5 + step * (float(i) + 0.5)
			if length >= 6.0 and absf(off) < 0.01:
				continue
			var q := Vector3(p.x + (off if along_x else 0.0), p.y, p.z + (0.0 if along_x else off))
			var pil := Vector3(0.28, s.y - 0.5, thick + 0.16) if along_x else Vector3(thick + 0.16, s.y - 0.5, 0.28)
			add_box(Vector3(q.x, bottom + 0.45 + pil.y * 0.5, q.z), pil, mat if not industrial else "metal_panel", _pilaster_tint(tint, industrial))
	if length >= 3.0 and s.y >= 2.3:
		if seed_v % 3 == 0:
			_drain_pipe(p, along_x, length, thick, bottom, top, seed_v)
		elif seed_v % 3 == 1 and top >= 2.8:
			_wall_unit(p, along_x, length, thick, bottom, seed_v)


func _frame_opening(b: Dictionary, sills: Array, along_x: bool, length: float, thick: float, bottom: float, industrial: bool) -> void:
	var p: Vector3 = b["pos"]
	var sill_top := 0.0
	var is_window := false
	for sb in sills:
		var sp: Vector3 = sb["pos"]
		var ss: Vector3 = sb["size"]
		var st := sp.y + ss.y * 0.5
		if absf(sp.x - p.x) < 0.06 and absf(sp.z - p.z) < 0.06 and st < bottom - 0.4 and st > sill_top - 0.001 and (st > 0.35):
			sill_top = st
			is_window = true
	if is_window and bottom - sill_top > 2.2:
		is_window = false # too tall for a window: a door above a lower floor piece
		sill_top = 0.0
	if not is_window and bottom > 3.0:
		return # upper-floor door without a sill: no frame (the ground is far below)
	var h := bottom - sill_top
	if h < 0.4:
		return
	var frame_mat := "metal_panel"
	var frame_tint := Color(0.16, 0.18, 0.2) if industrial or is_window else Color(0.22, 0.17, 0.12)
	if not industrial and not is_window:
		frame_mat = "wood_planks"
	var depth := thick + 0.1
	var fw := 0.1
	# jambs left/right, lintel under the header
	for sgn in [-1.0, 1.0]:
		var off: float = sgn * (length * 0.5 - fw * 0.5)
		var c := Vector3(p.x + (off if along_x else 0.0), sill_top + h * 0.5, p.z + (0.0 if along_x else off))
		add_box(c, Vector3(fw, h, depth) if along_x else Vector3(depth, h, fw), frame_mat, frame_tint)
	var lc := Vector3(p.x, bottom - fw * 0.5, p.z)
	add_box(lc, Vector3(length, fw, depth) if along_x else Vector3(depth, fw, length), frame_mat, frame_tint)
	if is_window:
		# protruding sill ledge plus a mullion and a transom, so the opening reads as a real window
		var ledge := Vector3(length + 0.16, 0.07, thick + 0.28) if along_x else Vector3(thick + 0.28, 0.07, length + 0.16)
		add_box(Vector3(p.x, sill_top + 0.03, p.z), ledge, "concrete", _trim_tint(industrial))
		var pane_h := h - fw - 0.035
		if length - 2.0 * fw >= 0.7 and pane_h >= 0.6:
			windows.append({"center": Vector3(p.x, sill_top + 0.035 + pane_h * 0.5, p.z), "size": Vector2(length - 2.0 * fw, pane_h), "axis_x": along_x})
		var mid_c := Vector3(p.x, sill_top + h * 0.5, p.z)
		if length >= 1.5:
			add_box(mid_c, Vector3(0.05, h, 0.08) if along_x else Vector3(0.08, h, 0.05), frame_mat, frame_tint)
		add_box(Vector3(p.x, sill_top + h * 0.62, p.z), Vector3(length, 0.05, 0.08) if along_x else Vector3(0.08, 0.05, length), frame_mat, frame_tint)
	else:
		# door: header trim above the lintel
		add_box(Vector3(p.x, bottom + 0.06, p.z), Vector3(length + 0.2, 0.12, depth + 0.06) if along_x else Vector3(depth + 0.06, 0.12, length + 0.2), "concrete", _trim_tint(industrial))


func _drain_pipe(p: Vector3, along_x: bool, length: float, thick: float, bottom: float, top: float, seed_v: int) -> void:
	var off := (length * 0.5 - 0.35) * (1.0 if seed_v % 2 == 0 else -1.0)
	var side := (thick * 0.5 + 0.09) * (1.0 if (seed_v >> 1) % 2 == 0 else -1.0)
	var h := top - bottom - 0.3
	var c := Vector3(p.x + (off if along_x else side), bottom + 0.15 + h * 0.5, p.z + (side if along_x else off))
	add_cylinder(c, 0.11, h, "metal_panel", Color(0.28, 0.3, 0.32))
	var k := 0
	while float(k) * 1.1 < h:
		var bc := Vector3(c.x, bottom + 0.4 + float(k) * 1.1, c.z)
		add_cylinder(bc, 0.16, 0.06, "metal_panel", Color(0.15, 0.16, 0.17))
		k += 1


func _wall_unit(p: Vector3, along_x: bool, length: float, thick: float, bottom: float, seed_v: int) -> void:
	var off := (float(int(seed_v / 5.0) % 5) - 2.0) * length * 0.12
	var side := (thick * 0.5 + 0.2) * (1.0 if int(seed_v / 7.0) % 2 == 0 else -1.0)
	var c := Vector3(p.x + (off if along_x else side), bottom + 2.45, p.z + (side if along_x else off))
	var sz := Vector3(0.85, 0.5, 0.4) if along_x else Vector3(0.4, 0.5, 0.85)
	add_box(c, sz, "metal_panel", Color(0.62, 0.64, 0.66))
	# fan grille + support brackets
	var g := c + (Vector3(0, 0, sign(side) * 0.205) if along_x else Vector3(sign(side) * 0.205, 0, 0))
	add_cylinder(g, 0.32, 0.02, "metal_panel", Color(0.1, 0.1, 0.11), Basis(Vector3.RIGHT, PI * 0.5) if along_x else Basis(Vector3.FORWARD, PI * 0.5))
	var bc := c + Vector3(0, -0.35, 0)
	add_box(bc, Vector3(0.7, 0.04, 0.3) if along_x else Vector3(0.3, 0.04, 0.7), "metal_panel", Color(0.15, 0.16, 0.17))


# ----------------------------------------------------------------------------- prop kit for maps

## Rooftop air-conditioning unit with fan and pipes (visual only: place on roofs nobody can reach).
func ac_unit(base: Vector3, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	add_box(base + basis * Vector3(0, 0.45, 0), Vector3(1.6, 0.9, 1.1), "metal_panel", Color(0.66, 0.68, 0.7), basis)
	add_cylinder(base + basis * Vector3(0, 0.92, 0), 0.8, 0.05, "metal_panel", Color(0.1, 0.1, 0.11), basis)
	add_box(base + basis * Vector3(0.95, 0.35, 0.2), Vector3(0.3, 0.7, 0.5), "metal_panel", Color(0.45, 0.47, 0.5), basis)
	add_cylinder(base + basis * Vector3(1.2, 0.3, -0.2), 0.1, 0.6, "metal_panel", Color(0.2, 0.2, 0.22), Basis(Vector3.FORWARD, PI * 0.5) * basis)


func vent_stack(base: Vector3, height: float = 1.2) -> void:
	add_cylinder(base + Vector3(0, height * 0.5, 0), 0.3, height, "metal_panel", Color(0.55, 0.57, 0.6))
	add_cylinder(base + Vector3(0, height + 0.04, 0), 0.5, 0.08, "metal_panel", Color(0.3, 0.32, 0.35))


func antenna(base: Vector3, height: float = 3.0) -> void:
	add_cylinder(base + Vector3(0, height * 0.5, 0), 0.05, height, "metal_panel", Color(0.5, 0.52, 0.55))
	for i in 3:
		var y := height * (0.55 + 0.15 * float(i))
		add_box(base + Vector3(0, y, 0), Vector3(0.9 - 0.2 * float(i), 0.03, 0.03), "metal_panel", Color(0.5, 0.52, 0.55))


func barrel(base: Vector3, tint: Color = Color(0.2, 0.32, 0.5)) -> void:
	add_cylinder(base + Vector3(0, 0.45, 0), 0.58, 0.9, "metal_panel", tint)
	for y in [0.2, 0.7]:
		add_cylinder(base + Vector3(0, y, 0), 0.62, 0.05, "metal_panel", tint * 0.6)
	add_cylinder(base + Vector3(0, 0.91, 0), 0.5, 0.03, "metal_panel", Color(0.25, 0.25, 0.27))


func pallet(base: Vector3, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for z in [-0.4, 0.0, 0.4]:
		add_box(base + basis * Vector3(0, 0.07, z), Vector3(1.2, 0.14, 0.12), "wood_planks", Color(0.7, 0.55, 0.38), basis)
	for y in [0.16]:
		for i in 5:
			add_box(base + basis * Vector3(-0.5 + 0.25 * float(i), y, 0), Vector3(0.12, 0.04, 1.0), "wood_planks", Color(0.78, 0.62, 0.42), basis)


func power_box(base: Vector3, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	add_box(base + basis * Vector3(0, 0.6, 0), Vector3(0.7, 1.2, 0.35), "metal_panel", Color(0.4, 0.45, 0.42), basis)
	add_box(base + basis * Vector3(0, 0.6, 0.18), Vector3(0.6, 1.0, 0.02), "metal_panel", Color(0.3, 0.34, 0.32), basis)
	add_cylinder(base + basis * Vector3(0, 1.4, 0), 0.08, 0.4, "metal_panel", Color(0.1, 0.1, 0.1))


func lamp_post(base: Vector3, height: float = 5.0, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	add_cylinder(base + Vector3(0, height * 0.5, 0), 0.14, height, "metal_panel", Color(0.22, 0.24, 0.26))
	add_cylinder(base + Vector3(0, 0.2, 0), 0.3, 0.4, "metal_panel", Color(0.18, 0.2, 0.22))
	add_box(base + basis * Vector3(0.45, height + 0.02, 0), Vector3(1.0, 0.1, 0.18), "metal_panel", Color(0.22, 0.24, 0.26), basis)
	add_box(base + basis * Vector3(0.85, height - 0.05, 0), Vector3(0.4, 0.08, 0.3), "metal_panel", Color(0.7, 0.68, 0.55), basis)


## Railing along a line: posts every `spacing` m, top rail and mid rail, slightly proud of the surface it follows.
func rail(from: Vector3, to: Vector3, height: float = 1.1, spacing: float = 2.0, tint: Color = Color(0.82, 0.84, 0.86)) -> void:
	var dir := to - from
	var len := dir.length()
	dir = dir.normalized()
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var n := maxi(1, int(len / spacing))
	for i in n + 1:
		add_cylinder(from + dir * (len * float(i) / float(n)) + Vector3(0, height * 0.5, 0), 0.07, height, "metal_panel", tint)
	add_box(from + dir * len * 0.5 + Vector3(0, height, 0), Vector3(0.09, 0.06, len), "metal_panel", tint, basis)
	add_box(from + dir * len * 0.5 + Vector3(0, height * 0.5, 0), Vector3(0.04, 0.04, len), "metal_panel", tint, basis)


## Utility pole with crossarm and insulators.
func utility_pole(base: Vector3, height: float = 7.0, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	add_cylinder(base + Vector3(0, height * 0.5, 0), 0.22, height, "wood_planks", Color(0.5, 0.4, 0.3))
	add_box(base + basis * Vector3(0, height - 0.5, 0), Vector3(0.12, 0.14, 2.0), "wood_planks", Color(0.45, 0.36, 0.26), basis)
	for x in [-0.85, 0.0, 0.85]:
		add_cylinder(base + basis * Vector3(0, height - 0.35, x), 0.08, 0.2, "metal_panel", Color(0.25, 0.3, 0.3))


## Hanging cable between two points (two segments with a slight sag).
func wire(a: Vector3, b: Vector3, sag: float = 0.4, thickness: float = 0.03) -> void:
	var mid := (a + b) * 0.5 - Vector3(0, sag, 0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var dir := p1 - p0
		var len := dir.length()
		if len < 0.01:
			continue
		var z := dir / len
		var x := z.cross(Vector3.UP)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := z.cross(x).normalized()
		add_box((p0 + p1) * 0.5, Vector3(thickness, thickness, len), "metal_panel", Color(0.05, 0.05, 0.06), Basis(x, y, z))


## Straight bar (beam, pipe, strut) from a to b with a square-ish cross section (w x h).
func bar(a: Vector3, b: Vector3, w: float, h: float, mat: String, tint = null) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.01:
		return
	var z := dir / len
	var x := z.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	add_box((a + b) * 0.5, Vector3(w, h, len), mat, tint, Basis(x, y, z))


## Rooftop solar panel on a tilted stand (visual only, for roofs nobody can reach).
func solar_panel(base: Vector3, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var tilt := basis * Basis(Vector3.RIGHT, deg_to_rad(-18.0))
	add_box(base + basis * Vector3(0, 0.3, 0), Vector3(1.7, 0.05, 1.0), "metal_panel", Color(0.1, 0.16, 0.3), tilt)
	add_box(base + basis * Vector3(0, 0.29, 0), Vector3(1.76, 0.04, 1.06), "metal_panel", Color(0.75, 0.77, 0.8), tilt)
	for x in [-0.7, 0.7]:
		add_box(base + basis * Vector3(x, 0.14, 0.2), Vector3(0.05, 0.28, 0.05), "metal_panel", Color(0.5, 0.52, 0.55), basis)


## Ceiling lamp: emissive fixture plus a soft fill light (no shadows, cheap).
func lamp(pos: Vector3, color: Color = Color(1.0, 0.88, 0.66), energy: float = 1.0, light_range: float = 9.0) -> void:
	add_box(pos, Vector3(0.6, 0.07, 0.25), "lamp", color)
	var l := OmniLight3D.new()
	l.position = pos - Vector3(0, 0.25, 0)
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	_lights.append(l)


## Flat marking (road line / stencil) just above a surface.
func marking(center: Vector3, size: Vector3, tint: Color) -> void:
	add_box(center, size, "plaster", tint)


## Dashed marking along a line.
func dashed_line(from: Vector3, to: Vector3, width: float, dash: float, gap: float, tint: Color) -> void:
	var dir := to - from
	var len := dir.length()
	dir = dir.normalized()
	var yaw := atan2(dir.x, dir.z)
	var basis := Basis(Vector3.UP, yaw)
	var t := 0.0
	while t < len:
		var l := minf(dash, len - t)
		add_box(from + dir * (t + l * 0.5), Vector3(width, 0.012, l), "plaster", tint, basis)
		t += dash + gap


# ----------------------------------------------------------------------------- helpers

func _trim_tint(industrial: bool) -> Color:
	return Color(0.55, 0.57, 0.6) if industrial else TRIM


func _pilaster_tint(tint, industrial: bool) -> Variant:
	if industrial:
		return Color(0.34, 0.36, 0.4)
	if tint != null:
		return (tint as Color) * 0.88
	return Color(0.88, 0.88, 0.88)


func _hash(p: Vector3) -> int:
	return absi(int(roundf(p.x * 13.0)) * 73 + int(roundf(p.z * 7.0)) * 151 + int(roundf(p.y * 5.0)) * 31)
