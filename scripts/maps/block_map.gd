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
var _rain_mat: ParticleProcessMaterial
var _wind_time: float = 0.0
var _wind_dir: Vector2 = Vector2(0.92, 0.38).normalized()

func _ready() -> void:
	add_to_group("map")
	_build_geometry()
	_build_spawns()
	_build_kill_zone()
	if bake_navigation:
		_bake_navigation()
	_upgrade_cinematic_lighting()

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


## A walkable slope from `low` (ground end, top surface) to `high` (upper end, top surface). Higher than ~45 cm it
## is drawn as real stairs (MapDetail.add_stairs: steps of ~18 cm) while the invisible collider stays a smooth slope
## (walking and navigation do not stumble over single steps); the slope runs half a step above the lower end, so the
## feet stay within half a step of the treads.
static func ramp(low: Vector3, high: Vector3, width: float, mat: String, thickness: float = 0.3, tint = null) -> Dictionary:
	var is_stairs := (high.y - low.y) > 0.45 and width >= 1.2
	var phys_low := low
	if is_stairs:
		var steps := maxi(2, roundi((high.y - low.y) / 0.18))
		phys_low = low + Vector3(0, (high.y - low.y) / float(steps) * 0.5, 0)
	var forward := (high - phys_low)
	var length := forward.length()
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var basis := Basis(right, up, -forward)
	var center := (phys_low + high) * 0.5 - up * (thickness * 0.5)
	var d := {"pos": center, "size": Vector3(width, thickness, length), "mat": mat, "basis": basis}
	if tint != null:
		d["tint"] = tint
	if is_stairs:
		d["visible"] = false
		d["stairs"] = true
		d["low"] = low
		d["high"] = high
		d["width"] = width
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

## Per-map sky look for the dynamic sky (Mesa builds its own with the shader defaults).
const SKY_PRESETS := {
	"Harbor": {"colors": {"zenith": Color(0.1, 0.22, 0.45), "mid_sky": Color(0.32, 0.45, 0.62), "horizon": Color(0.74, 0.78, 0.82), "ground": Color(0.36, 0.38, 0.4), "sun_tint": Color(1.0, 0.95, 0.85)}, "cover": Vector2(0.3, 0.6)},
	"Frontier": {"colors": {"zenith": Color(0.14, 0.3, 0.62), "mid_sky": Color(0.5, 0.6, 0.76), "horizon": Color(0.95, 0.8, 0.6), "ground": Color(0.5, 0.4, 0.3), "sun_tint": Color(1.0, 0.82, 0.55)}, "cover": Vector2(0.25, 0.6)},
	"Suburb": {"colors": {"zenith": Color(0.14, 0.34, 0.7), "mid_sky": Color(0.4, 0.58, 0.82), "horizon": Color(0.9, 0.86, 0.8), "ground": Color(0.4, 0.4, 0.36), "sun_tint": Color(1.0, 0.92, 0.78)}, "cover": Vector2(0.35, 0.75)},
	"Test Arena": {"colors": {"zenith": Color(0.12, 0.3, 0.7), "mid_sky": Color(0.4, 0.56, 0.8), "horizon": Color(0.85, 0.88, 0.92), "ground": Color(0.4, 0.42, 0.44)}, "cover": Vector2(0.3, 0.6)},
}


func _add_sky() -> void:
	if get_node_or_null("MesaSky") != null:
		return
	var sky := MesaSky.new()
	sky.name = "MesaSky"
	sky.preset = SKY_PRESETS.get(map_display_name, SKY_PRESETS["Test Arena"])
	add_child(sky)


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
	_add_sky()
	# breakable glass in every window opening (state is decided by the host, see GlassField)
	var glass := GlassField.new()
	glass.name = "Glass"
	add_child(glass)
	glass.setup(detail.windows)


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
	elif b.has("stairs"):
		detail.add_stairs(b)


func _get_material(mat_name: String, tint) -> Material:
	var key := mat_name
	if tint != null:
		key += "#" + (tint as Color).to_html()
	if _material_cache.has(key):
		return _material_cache[key]
	var path := MATERIAL_DIR + mat_name + ".tres"
	var base: Material = null
	if ResourceLoader.exists(path):
		base = load(path)
	if base == null:
		push_warning("BlockMap: Material fehlt: " + path)
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.8, 0.2, 0.8)
		base = fallback
	var mat: Material = base
	if tint != null:
		mat = base.duplicate()
		if mat is StandardMaterial3D:
			mat.albedo_color = tint
			if mat.emission_enabled:
				mat.emission = tint
		elif mat is ShaderMaterial:
			mat.set_shader_parameter("tint_color", tint)
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




var _sun_light: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _lightning_flash: ColorRect
var _lens_rain_rect: ColorRect
var _lens_rain_mat: ShaderMaterial
var _lightning_timer: float = 3.5
var _lightning_flash_val: float = 0.0
var _outdoors_blend: float = 1.0


func _process(delta: float) -> void:
	_wind_time += delta
	var gust := 0.85 + 0.45 * sin(_wind_time * 1.1) + 0.30 * sin(_wind_time * 2.6)
	RenderingServer.global_shader_parameter_set("wind_dir", _wind_dir)
	RenderingServer.global_shader_parameter_set("wind_strength", gust)

	if _rain_mat != null:
		var slant := 11.5 * gust
		_rain_mat.direction = Vector3(_wind_dir.x * slant, -24.0, _wind_dir.y * slant).normalized()

	var cam := get_viewport().get_camera_3d()
	var outdoors := true
	if cam != null and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3.UP * 40.0)
		outdoors = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	_outdoors_blend = move_toward(_outdoors_blend, 1.0 if outdoors else 0.0, delta * 2.5)

	if _lens_rain_mat != null:
		_lens_rain_mat.set_shader_parameter("intensity", _outdoors_blend * clampf(gust * 0.75, 0.35, 1.0))

	# Kräftiges, dramatisches Licht wenn die Sonne durch die Gewitterwolken bricht
	var storm_pulse := 0.5 + 0.5 * sin(_wind_time * 0.35)
	if _sun_light != null:
		var base_energy := lerpf(1.25, 2.55, storm_pulse)
		_sun_light.light_energy = base_energy + _lightning_flash_val * 4.0
		_sun_light.light_color = Color(0.78, 0.86, 1.0) if _lightning_flash_val > 0.1 else Color(0.95, 0.82, 0.68).lerp(Color(1.0, 0.90, 0.78), storm_pulse)
		_sun_light.rotation_degrees = Vector3(-24.0 + sin(_wind_time * 0.15) * 1.5, -48.0, 0.0)

	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(4.0, 11.0)
		_lightning_flash_val = 1.0
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_seed", randf() * 100.0)

	if _lightning_flash_val > 0.0:
		var flicker := 1.0 if (_lightning_flash_val > 0.75 or (_lightning_flash_val > 0.35 and _lightning_flash_val < 0.55)) else 0.12
		var intensity := _lightning_flash_val * flicker
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_intensity", intensity)
		if _lightning_flash != null:
			_lightning_flash.color.a = intensity * 0.16 * _outdoors_blend
		_lightning_flash_val = maxf(0.0, _lightning_flash_val - delta * 2.4)
	else:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_intensity", 0.0)
		if _lightning_flash != null:
			_lightning_flash.color.a = 0.0


func _upgrade_cinematic_lighting() -> void:
	var env_node: WorldEnvironment = null
	for child in get_children():
		if child is WorldEnvironment:
			env_node = child
			break
	if env_node == null:
		env_node = WorldEnvironment.new()
		add_child(env_node)
	if env_node.environment == null:
		env_node.environment = Environment.new()

	var env := env_node.environment
	env.tonemap_mode = 3
	env.tonemap_exposure = 1.02
	env.tonemap_white = 7.0

	# Böser Gewitterhimmel OHNE Regenbogen + dramatischer Sonnen-Durchbruch & Lens-Streaks beim Blick zur Sonne
	var cloud_code := "shader_type sky;\n" \
		+ "uniform float lightning_intensity = 0.0;\n" \
		+ "uniform float lightning_seed = 0.0;\n" \
		+ "float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }\n" \
		+ "float noise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y); }\n" \
		+ "float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.05 + vec2(2.1, 7.4); a *= 0.5; } return v; }\n" \
		+ "void sky() {\n" \
		+ "	vec3 d = normalize(EYEDIR);\n" \
		+ "	vec3 sun_dir = normalize(LIGHT0_DIRECTION);\n" \
		+ "	float h = clamp(d.y, 0.005, 1.0);\n" \
		+ "	vec2 uv = d.xz / (h + 0.16) * 0.85 + vec2(TIME * 0.045, TIME * 0.02);\n" \
		+ "	float c1 = fbm(uv);\n" \
		+ "	float c2 = fbm(uv * 2.7 - c1 * 0.9 + vec2(TIME * 0.03, 0.0));\n" \
		+ "	float storm = smoothstep(0.15, 0.85, c1 * 0.6 + c2 * 0.4);\n" \
		+ "	float sun_dot = max(dot(d, sun_dir), 0.0);\n" \
		+ "	vec3 abyss = vec3(0.07, 0.08, 0.11);\n" \
		+ "	vec3 slate = vec3(0.20, 0.23, 0.28);\n" \
		+ "	vec3 steel_rim = vec3(0.42, 0.45, 0.50);\n" \
		+ "	vec3 col = mix(slate, abyss, storm);\n" \
		+ "	col = mix(col, steel_rim, smoothstep(0.55, 0.92, c2) * (1.0 - storm * 0.5));\n" \
		+ "	// Dramatischer Sonnen-Durchbruch + anamorphotischer Lens-Flare-Streifen in Sonnenrichtung\n" \
		+ "	float sun_break = pow(sun_dot, 5.0) * (1.15 - storm * 0.65);\n" \
		+ "	float sun_core = pow(sun_dot, 90.0) * 1.6;\n" \
		+ "	float anamorphic_streak = exp(-abs(d.y - sun_dir.y) * 28.0) * pow(sun_dot, 6.0) * 0.55;\n" \
		+ "	col += vec3(1.0, 0.82, 0.62) * (sun_break + sun_core + anamorphic_streak);\n" \
		+ "	vec3 horizon = mix(vec3(0.26, 0.29, 0.33), vec3(0.55, 0.46, 0.38), pow(sun_dot, 2.0));\n" \
		+ "	col = mix(horizon, col, smoothstep(0.0, 0.30, d.y));\n" \
		+ "	if (lightning_intensity > 0.001) {\n" \
		+ "		float bolt_x = fract(sin(lightning_seed) * 43758.5453) * 2.0 - 1.0;\n" \
		+ "		float jag = (noise(vec2(d.y * 20.0, lightning_seed)) - 0.5) * 0.08;\n" \
		+ "		float bolt = exp(-abs((d.x - bolt_x * 0.7) + jag) * 160.0) * smoothstep(0.02, 0.42, d.y) * (1.0 - smoothstep(0.42, 0.60, d.y));\n" \
		+ "		float glow = exp(-length(d.xz - vec2(bolt_x * 0.7, -0.4)) * 2.4) * (0.35 + 0.65 * (1.0 - storm));\n" \
		+ "		col += vec3(0.68, 0.80, 1.0) * lightning_intensity * (bolt * 4.5 + glow * 1.6);\n" \
		+ "	}\n" \
		+ "	COLOR = col;\n" \
		+ "}\n"

	var sky_shd := Shader.new()
	sky_shd.code = cloud_code
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shd
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ssr_enabled = true
	env.ssr_max_steps = 28
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.3
	env.ssil_enabled = false

	# Lässt die Lens-Flare & den Sonnen-Durchbruch durch die Wolken schön glühen
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.10

	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.30, 0.32, 0.35)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.18
	env.fog_density = 0.56
	env.fog_depth_begin = 16.0
	env.fog_depth_end = 105.0
	env.fog_height = 4.0
	env.fog_height_density = 0.018

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.44)
	env.ambient_light_energy = 1.35

	for child in get_children():
		if child is DirectionalLight3D:
			_sun_light = child
			_sun_light.light_color = Color(1.0, 0.86, 0.72)
			_sun_light.light_energy = 1.85
			_sun_light.rotation_degrees = Vector3(-24.0, -48.0, 0.0)
			_sun_light.shadow_enabled = true
			_sun_light.shadow_blur = 2.4
			_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun_light.directional_shadow_max_distance = 110.0

	_spawn_lightning_and_lens_overlay()
	_spawn_rain_particles()
	_spawn_jungle_backdrop()

func _spawn_lightning_and_lens_overlay() -> void:
	if has_node("LightningLayer"):
		return
	var layer := CanvasLayer.new()
	layer.name = "LightningLayer"
	layer.layer = 5

	var lens_code := "shader_type canvas_item;\n" \
		+ "uniform float intensity = 0.0;\n" \
		+ "vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }\n" \
		+ "void fragment() {\n" \
		+ "	vec2 aspect = vec2(1.77, 1.0);\n" \
		+ "	vec2 uv = UV * aspect * vec2(14.0, 8.0);\n" \
		+ "	vec2 id = floor(uv);\n" \
		+ "	vec2 gv = fract(uv) - 0.5;\n" \
		+ "	vec2 rnd = hash2(id);\n" \
		+ "	float cycle = fract(TIME * (0.18 + rnd.x * 0.22) + rnd.y * 6.28);\n" \
		+ "	float slide = smoothstep(0.35, 1.0, cycle) * 0.45;\n" \
		+ "	vec2 pos = (rnd - 0.5) * 0.45 + vec2(0.0, slide);\n" \
		+ "	vec2 d = (gv - pos) * vec2(1.0, 0.65);\n" \
		+ "	float dist = length(d);\n" \
		+ "	float radius = 0.14 * (1.0 - smoothstep(0.65, 1.0, cycle)) * step(0.58, rnd.x);\n" \
		+ "	float rim = smoothstep(radius, radius * 0.68, dist) - smoothstep(radius * 0.68, radius * 0.2, dist);\n" \
		+ "	float glint = smoothstep(radius * 0.45, 0.0, length(d + vec2(0.03, 0.04))) * step(0.01, radius);\n" \
		+ "	float edge_mask = smoothstep(0.18, 0.68, length(UV - 0.5));\n" \
		+ "	float alpha = (rim * 0.16 + glint * 0.28) * intensity * edge_mask;\n" \
		+ "	COLOR = vec4(0.82, 0.88, 0.96, clamp(alpha, 0.0, 0.35));\n" \
		+ "}\n"

	var lshd := Shader.new()
	lshd.code = lens_code
	_lens_rain_mat = ShaderMaterial.new()
	_lens_rain_mat.shader = lshd
	_lens_rain_rect = ColorRect.new()
	_lens_rain_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lens_rain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens_rain_rect.material = _lens_rain_mat
	layer.add_child(_lens_rain_rect)

	_lightning_flash = ColorRect.new()
	_lightning_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lightning_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lightning_flash.color = Color(0.72, 0.82, 1.0, 0.0)
	layer.add_child(_lightning_flash)
	add_child(layer)


func _spawn_rain_particles() -> void:
	if has_node("RainParticles"):
		get_node("RainParticles").queue_free()
	if has_node("RainRoofCollider"):
		get_node("RainRoofCollider").queue_free()

	var col := GPUParticlesCollisionHeightField3D.new()
	col.name = "RainRoofCollider"
	col.size = Vector3(160.0, 45.0, 160.0)
	col.position = Vector3(0.0, 16.0, 0.0)
	col.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	col.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(col)

	var rain := GPUParticles3D.new()
	rain.name = "RainParticles"
	rain.amount = 5200
	rain.lifetime = 0.85
	rain.preprocess = 1.0
	rain.visibility_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 40, 160))
	rain.position = Vector3(0.0, 18.0, 0.0)

	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(60.0, 3.0, 60.0)
	_rain_mat.direction = Vector3(0.45, -1.0, 0.18).normalized()
	_rain_mat.spread = 2.5
	_rain_mat.initial_velocity_min = 26.0
	_rain_mat.initial_velocity_max = 35.0
	_rain_mat.gravity = Vector3(7.5, -16.0, 3.0)
	_rain_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	rain.process_material = _rain_mat

	var drop := QuadMesh.new()
	drop.size = Vector2(0.007, 0.78)
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.albedo_color = Color(0.78, 0.83, 0.90, 0.30)
	drop.material = dmat
	rain.draw_pass_1 = drop

	rain.rotation_degrees = Vector3(9.0, 0.0, -23.0)
	add_child(rain)
func _spawn_jungle_backdrop() -> void:
	if has_node("JungleBackdrop"):
		return
	var root := Node3D.new()
	root.name = "JungleBackdrop"
	add_child(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42012

	var rock_st := SurfaceTool.new()
	rock_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ico := SphereMesh.new()
	ico.radial_segments = 10
	ico.rings = 6
	var arrays := ico.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idxs: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for idx in idxs:
		var v := verts[idx]
		var n := sin(v.x * 5.1) * cos(v.z * 4.7) * 0.22 + sin(v.y * 6.3) * 0.14
		v = v * (1.0 + n)
		v.y = maxf(v.y * 0.75, -0.35)
		rock_st.set_uv(Vector2(v.x + v.z, v.y) * 0.5)
		rock_st.add_vertex(v)
	rock_st.generate_normals()
	var rock_mesh := rock_st.commit()
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.18, 0.20, 0.19)
	rock_mat.roughness = 0.92
	rock_mesh.surface_set_material(0, rock_mat)

	var rock_mm := MultiMesh.new()
	rock_mm.transform_format = MultiMesh.TRANSFORM_3D
	rock_mm.mesh = rock_mesh
	rock_mm.instance_count = 34
	for i in 34:
		var ang := TAU * float(i) / 34.0 + rng.randf_range(-0.08, 0.08)
		var dist := rng.randf_range(46.0, 74.0)
		var pos := Vector3(cos(ang) * dist, rng.randf_range(-0.5, 1.5), sin(ang) * dist)
		var sc := Vector3(rng.randf_range(5.0, 13.0), rng.randf_range(3.5, 10.0), rng.randf_range(5.0, 13.0))
		rock_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled_local(sc), pos))
	var rock_mi := MultiMeshInstance3D.new()
	rock_mi.multimesh = rock_mm
	root.add_child(rock_mi)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.35
	trunk_mesh.bottom_radius = 0.65
	trunk_mesh.height = 7.5
	trunk_mesh.radial_segments = 8
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.16, 0.13, 0.10)
	tmat.roughness = 0.95
	trunk_mesh.material = tmat

	var canopy_mesh := Vegetation.bush_mesh()
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.mesh = trunk_mesh
	trunk_mm.instance_count = 42

	var canopy_items: Array = []
	for i in 42:
		var ang := TAU * float(i) / 42.0 + rng.randf_range(-0.06, 0.06)
		var dist := rng.randf_range(42.0, 68.0)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var h_sc := rng.randf_range(0.9, 1.5)
		trunk_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled_local(Vector3(1.0, h_sc, 1.0)), pos + Vector3(0.0, 3.6 * h_sc, 0.0)))
		canopy_items.append({
			"pos": pos + Vector3(0.0, 6.8 * h_sc, 0.0),
			"scale3": Vector3(rng.randf_range(5.5, 8.5), rng.randf_range(3.5, 5.5), rng.randf_range(5.5, 8.5)),
			"yaw": rng.randf() * TAU,
			"color": Color(0.55, 0.68, 0.52).lerp(Color(0.35, 0.50, 0.34), rng.randf())
		})

	var trunk_mi := MultiMeshInstance3D.new()
	trunk_mi.multimesh = trunk_mm
	root.add_child(trunk_mi)
	Vegetation.scatter(root, canopy_mesh, canopy_items, "JungleCanopies")
