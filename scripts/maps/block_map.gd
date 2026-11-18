class_name BlockMap
extends Node3D
## Base class for maps built from block descriptions. Subclasses return a list of
## block dictionaries from get_blocks() and spawn descriptions from get_spawns();
## geometry, collision, spawn points and the kill zone are generated in _ready().
##
## Block dictionary keys:
##   pos: Vector3 (center), size: Vector3, mat: String (material name)
##   tint: Color (optional), rot: Vector3 degrees (optional), basis: Basis (optional)
##   shape: "box" (default) | "cylinder"   (cylinder uses size.x as diameter, size.y as height)
##   collide: bool (default true), visible: bool (default true)

const MATERIAL_DIR := "res://assets/materials/"

@export var map_display_name: String = "Map"
@export var kill_y: float = -12.0
@export var bake_navigation: bool = true

var geometry_root: Node3D
var nav_region: NavigationRegion3D
var navigation_ready: bool = false
var _material_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("map")
	_build_geometry()
	_build_spawns()
	_build_kill_zone()
	if bake_navigation:
		_bake_navigation()


# ----------------------------------------------------------------------------- overridables

func get_blocks() -> Array:
	return []


## Each entry: {"pos": Vector3, "yaw": float (degrees), "team": int}
## Optional extras per map: props, markings, roof equipment (visual only, see MapDetail).
func build_detail(_detail: MapDetail) -> void:
	pass


func get_spawns() -> Array:
	return []


## Bot routes: {"left": [Vector3,...], "mid": [...], "right": [...]} ordered north -> south.
func get_lanes() -> Dictionary:
	return {}


## Extra positions bots like to hold (behind cover, windows). Optional.
func get_cover_points() -> Array:
	return []


# ----------------------------------------------------------------------------- helpers for subclasses

static func box(pos: Vector3, size: Vector3, mat: String, tint = null, rot = null) -> Dictionary:
	var d := {"pos": pos, "size": size, "mat": mat}
	if tint != null:
		d["tint"] = tint
	if rot != null:
		d["rot"] = rot
	return d


static func cylinder(pos: Vector3, diameter: float, height: float, mat: String, tint = null) -> Dictionary:
	var d := {"pos": pos, "size": Vector3(diameter, height, diameter), "mat": mat, "shape": "cylinder"}
	if tint != null:
		d["tint"] = tint
	return d


## A walkable ramp from `low` (ground end, top surface) to `high` (upper end, top surface).
static func ramp(low: Vector3, high: Vector3, width: float, mat: String, thickness: float = 0.3, tint = null) -> Dictionary:
	var forward := (high - low)
	var length := forward.length()
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var basis := Basis(right, up, -forward)
	var center := (low + high) * 0.5 - up * (thickness * 0.5)
	var d := {"pos": center, "size": Vector3(width, thickness, length), "mat": mat, "basis": basis}
	if tint != null:
		d["tint"] = tint
	return d


static func spawn(pos: Vector3, yaw_degrees: float, team: int = 0) -> Dictionary:
	return {"pos": pos, "yaw": yaw_degrees, "team": team}


## Four walls around a rectangle (useful for rooms). Returns an array of blocks.
static func room_walls(center: Vector3, size: Vector3, thickness: float, mat: String, tint = null, openings: Array = []) -> Array:
	## openings: list of {"side": "n"|"s"|"e"|"w", "offset": float, "width": float}
	var out: Array = []
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	var y := center.y + h * 0.5
	for side in ["n", "s", "e", "w"]:
		var wall_len := size.x if side in ["n", "s"] else size.z
		var segments: Array = [[-wall_len * 0.5, wall_len * 0.5]]
		for o in openings:
			if o["side"] != side:
				continue
			var o_start: float = o["offset"] - o["width"] * 0.5
			var o_end: float = o["offset"] + o["width"] * 0.5
			var new_segments: Array = []
			for seg in segments:
				if o_end <= seg[0] or o_start >= seg[1]:
					new_segments.append(seg)
					continue
				if o_start > seg[0]:
					new_segments.append([seg[0], o_start])
				if o_end < seg[1]:
					new_segments.append([o_end, seg[1]])
			segments = new_segments
		for seg in segments:
			var seg_len: float = seg[1] - seg[0]
			var seg_mid: float = (seg[0] + seg[1]) * 0.5
			var pos: Vector3
			var sz: Vector3
			match side:
				"n":
					pos = Vector3(center.x + seg_mid, y, center.z - hz)
					sz = Vector3(seg_len, h, thickness)
				"s":
					pos = Vector3(center.x + seg_mid, y, center.z + hz)
					sz = Vector3(seg_len, h, thickness)
				"e":
					pos = Vector3(center.x + hx, y, center.z + seg_mid)
					sz = Vector3(thickness, h, seg_len)
				_:
					pos = Vector3(center.x - hx, y, center.z + seg_mid)
					sz = Vector3(thickness, h, seg_len)
			out.append(box(pos, sz, mat, tint))
	return out


## Window: sill below and header above an opening in a wall made with room_walls().
## `axis_x` = true for walls running along X (north/south walls).
static func window(center: Vector3, width: float, sill_height: float, top_height: float, wall_height: float, thickness: float, axis_x: bool, mat: String, tint = null) -> Array:
	return [
		header(center, width, 0.0, sill_height, thickness, axis_x, mat, tint),
		header(center, width, top_height, wall_height, thickness, axis_x, mat, tint),
	]


## Simple fence: thin wall with posts. Runs along X if axis_x else along Z.
static func fence(start: Vector3, length: float, height: float, axis_x: bool, mat: String, tint = null) -> Array:
	var out: Array = []
	var dir := Vector3(1, 0, 0) if axis_x else Vector3(0, 0, 1)
	var center := start + dir * (length * 0.5) + Vector3(0, height * 0.5, 0)
	var sz := Vector3(length, height * 0.6, 0.06) if axis_x else Vector3(0.06, height * 0.6, length)
	out.append(box(center + Vector3(0, height * 0.15, 0), sz, mat, tint))
	var posts := int(length / 2.0) + 1
	for i in posts:
		var p := start + dir * minf(float(i) * 2.0, length) + Vector3(0, height * 0.5, 0)
		out.append(box(p, Vector3(0.12, height, 0.12), mat, tint))
	return out


## A parked car: body, cabin, wheels. yaw in degrees (0 = facing -Z).
static func car(center: Vector3, color: Color, yaw: float = 0.0) -> Array:
	var out: Array = []
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var body_pos := center + Vector3(0, 0.65, 0)
	out.append({"pos": body_pos, "size": Vector3(1.9, 0.9, 4.4), "mat": "metal_panel", "tint": color, "basis": basis, "kind": "car"})
	out.append({"pos": center + Vector3(0, 1.4, 0) + basis * Vector3(0, 0, 0.2), "size": Vector3(1.7, 0.6, 2.2), "mat": "metal_panel", "tint": Color(0.15, 0.17, 0.2), "basis": basis})
	for wx in [-0.85, 0.85]:
		for wz in [-1.4, 1.4]:
			var wp := center + basis * Vector3(wx, 0.35, wz)
			out.append({"pos": wp, "size": Vector3(0.25, 0.7, 0.7), "mat": "rubber", "basis": basis, "collide": false})
	return out


## Door/window header: wall piece above an opening.
static func header(center: Vector3, width: float, height_from: float, height_to: float, thickness: float, axis_x: bool, mat: String, tint = null) -> Dictionary:
	var h := height_to - height_from
	var pos := Vector3(center.x, height_from + h * 0.5, center.z)
	var sz := Vector3(width, h, thickness) if axis_x else Vector3(thickness, h, width)
	return box(pos, sz, mat, tint)


# ----------------------------------------------------------------------------- building

func _build_geometry() -> void:
	# geometry lives under the navigation region so the bake can parse it
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)
	geometry_root = Node3D.new()
	geometry_root.name = "Geometry"
	nav_region.add_child(geometry_root)
	var blocks := get_blocks()
	# the visuals of all blocks are merged per material (one draw call per material instead of one per block)
	var detail := MapDetail.new(self)
	for b in blocks:
		_add_block(b, detail)
	# visual-only detail (no colliders): automatic wall detail plus the map's own extras
	detail.build(blocks)
	build_detail(detail)
	detail.flush(geometry_root)


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	# cell sizes match the default navigation map (0.25) so edges rasterise cleanly;
	# radius/climb are multiples of the cell size to avoid rounding
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 42.0
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.0
	nm.detail_sample_distance = 4.0
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	if nav_region.navigation_mesh.get_polygon_count() == 0:
		push_warning("BlockMap: Navigation-Bake lieferte keine Polygone fuer " + map_display_name)
		return
	# the navigation map is iterated asynchronously; queries only work a few
	# physics frames later, once the server has synchronised our region
	NavigationServer3D.map_changed.connect(_on_nav_map_changed)


func _on_nav_map_changed(map_rid: RID) -> void:
	if navigation_ready or not is_inside_tree():
		return
	if map_rid != get_world_3d().navigation_map:
		return
	# verify with a real query: the first spawn point must resolve to a mesh point
	var spawns := get_spawns()
	var probe: Vector3 = spawns[0]["pos"] if not spawns.is_empty() else Vector3.ZERO
	probe += Vector3(0, 0.5, 0)
	var closest := NavigationServer3D.map_get_closest_point(map_rid, probe)
	if closest != Vector3.ZERO and closest.distance_to(probe) < 2.0:
		navigation_ready = true
		NavigationServer3D.map_changed.disconnect(_on_nav_map_changed)


## Awaits until bots may query paths (returns false after `max_frames` physics frames).
func wait_navigation_ready(max_frames: int = 120) -> bool:
	var frames := 0
	while not navigation_ready and frames < max_frames and is_inside_tree():
		await get_tree().physics_frame
		frames += 1
	return navigation_ready


## World-space positions of the lane waypoints (for bots) as flat list.
func get_all_lane_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for lane in get_lanes().values():
		for p in lane:
			out.append(p)
	return out


func _add_block(b: Dictionary, detail: MapDetail) -> void:
	var pos: Vector3 = b.get("pos", Vector3.ZERO)
	var size: Vector3 = b.get("size", Vector3.ONE)
	var shape_kind: String = b.get("shape", "box")
	var collide: bool = b.get("collide", true)
	var is_visible: bool = b.get("visible", true)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	if b.has("basis"):
		body.transform.basis = b["basis"]
	elif b.has("rot"):
		var r: Vector3 = b["rot"]
		body.rotation_degrees = r
	geometry_root.add_child(body)

	if collide:
		var col := CollisionShape3D.new()
		if shape_kind == "cylinder":
			var cs := CylinderShape3D.new()
			cs.radius = size.x * 0.5
			cs.height = size.y
			col.shape = cs
		else:
			var bs := BoxShape3D.new()
			bs.size = size
			col.shape = bs
		body.add_child(col)

	if is_visible:
		detail.add_block(b)


func _get_material(mat_name: String, tint) -> Material:
	var key := mat_name
	if tint != null:
		key += "#" + (tint as Color).to_html()
	if _material_cache.has(key):
		return _material_cache[key]
	var path := MATERIAL_DIR + mat_name + ".tres"
	var base: StandardMaterial3D = null
	if ResourceLoader.exists(path):
		base = load(path)
	if base == null:
		push_warning("BlockMap: Material fehlt: " + path)
		base = StandardMaterial3D.new()
		base.albedo_color = Color(0.8, 0.2, 0.8)
	var mat := base
	if tint != null:
		mat = base.duplicate()
		mat.albedo_color = tint
	_material_cache[key] = mat
	return mat


func _build_spawns() -> void:
	var root := Node3D.new()
	root.name = "SpawnPoints"
	add_child(root)
	var i := 0
	for s in get_spawns():
		var sp := SpawnPoint.new()
		sp.name = "Spawn_%d" % i
		sp.team = int(s.get("team", 0))
		sp.position = s["pos"]
		sp.rotation_degrees = Vector3(0.0, float(s.get("yaw", 0.0)), 0.0)
		root.add_child(sp)
		i += 1


func _build_kill_zone() -> void:
	var area := Area3D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = 2 | 4
	area.monitoring = true
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 4, 400)
	shape.shape = bs
	area.add_child(shape)
	# top face of the zone sits exactly at kill_y, the box extends 4 m below it
	area.position = Vector3(0, kill_y - bs.size.y * 0.5, 0)
	area.body_entered.connect(_on_kill_zone_entered)
	add_child(area)


func _on_kill_zone_entered(body: Node3D) -> void:
	if body is Player and (body as Player).alive and MatchManager.is_authority():
		(body as Player).health.kill(0, "world")
	elif body is RigidBody3D:
		body.queue_free()
