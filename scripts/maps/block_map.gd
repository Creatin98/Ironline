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



@export_enum("clear_day", "overcast_industrial", "tropical_storm") var atmosphere_preset: String = "clear_day"
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
	var is_mesa := (atmosphere_preset == "tropical_storm" or name.to_lower().contains("mesa"))
	var is_harbor := (atmosphere_preset == "overcast_industrial" or name.to_lower().contains("harbor"))

	# 1. Wind läuft auf ALLEN Maps (Mesa = Tropensturm, Harbor = extremer Seewind, sonst leichte Brise)
	var base_wind := 0.85 if is_mesa else (1.15 if is_harbor else 0.30)
	var gust_amp := 0.45 if (is_mesa or is_harbor) else 0.12
	var gust := base_wind + gust_amp * sin(_wind_time * 1.1) + (gust_amp * 0.65) * sin(_wind_time * 2.6)
	RenderingServer.global_shader_parameter_set("wind_dir", _wind_dir)
	RenderingServer.global_shader_parameter_set("wind_strength", gust)

	# 2. Harbor: Schiff arbeitet dynamisch gegen schwere Wellen (Rollen, Stampfen & Heben ohne Regen!)
	if is_harbor:
		RenderingServer.global_shader_parameter_set("rain_wetness", 0.0)
		if _lens_rain_mat != null:
			_lens_rain_mat.set_shader_parameter("intensity", 0.0)
		if _lightning_flash != null:
			_lightning_flash.color.a = 0.0
		if geometry_root != null:
			var roll := sin(_wind_time * 0.95) * 1.35 + sin(_wind_time * 1.85) * 0.55
			var pitch := cos(_wind_time * 0.72) * 0.85 + sin(_wind_time * 1.45) * 0.35
			var heave := sin(_wind_time * 1.15) * 0.24 + cos(_wind_time * 2.1) * 0.08
			geometry_root.rotation_degrees = Vector3(pitch, 0.0, roll)
			geometry_root.position.y = heave
		return

	# 3. Trockene Maps ohne Sturm
	if not is_mesa:
		RenderingServer.global_shader_parameter_set("rain_wetness", 0.0)
		if _lens_rain_mat != null:
			_lens_rain_mat.set_shader_parameter("intensity", 0.0)
		if _lightning_flash != null:
			_lightning_flash.color.a = 0.0
		return

	# 4. Ab hier AUSSCHLIESSLICH Mesa (Tropensturm mit Regen, Blitzen & Visier-Tropfen)
	if _rain_mat != null:
		var slant := 11.5 * gust
		_rain_mat.direction = Vector3(_wind_dir.x * slant, -24.0, _wind_dir.y * slant).normalized()

	var cam := get_viewport().get_camera_3d()
	var outdoors := true
	if cam != null and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3.UP * 40.0)
		outdoors = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		var dt := maxf(delta, 0.001)
		var local_vel := cam.global_basis.inverse() * ((cam.global_position - _last_cam_pos) / dt)
		var yaw_delta := _last_cam_basis.z.cross(cam.global_basis.z).y / dt
		var pitch_delta := (cam.global_basis.z.y - _last_cam_basis.z.y) / dt
		var target_flow := Vector2(
			clampf(yaw_delta * 0.18 - local_vel.x * 0.04, -1.8, 1.8),
			clampf(1.0 + pitch_delta * 0.25 - local_vel.z * 0.03, 0.25, 2.5)
		)
		_visor_flow = _visor_flow.lerp(target_flow, minf(1.0, delta * 8.0))
		_last_cam_basis = cam.global_basis
		_last_cam_pos = cam.global_position

	var wet_rate := 1.4 if outdoors else 0.35
	_outdoors_blend = move_toward(_outdoors_blend, 1.0 if outdoors else 0.0, delta * wet_rate)
	RenderingServer.global_shader_parameter_set("rain_wetness", _outdoors_blend)

	if _lens_rain_mat != null:
		_lens_rain_mat.set_shader_parameter("intensity", _outdoors_blend * clampf(gust * 0.85, 0.4, 1.0))
		_lens_rain_mat.set_shader_parameter("flow_vel", _visor_flow)

	var storm_pulse := 0.5 + 0.5 * sin(_wind_time * 0.35)
	if _sun_light != null:
		var base_energy := lerpf(1.35, 2.25, storm_pulse)
		_sun_light.light_energy = base_energy + _lightning_flash_val * 3.5
		_sun_light.light_color = Color(0.78, 0.86, 1.0) if _lightning_flash_val > 0.1 else Color(0.95, 0.84, 0.72)

	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(5.0, 12.0)
		_lightning_flash_val = 1.0
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_seed", randf() * 100.0)

	if _lightning_flash_val > 0.0:
		var flicker := 1.0 if (_lightning_flash_val > 0.75 or (_lightning_flash_val > 0.35 and _lightning_flash_val < 0.55)) else 0.12
		var intensity := _lightning_flash_val * flicker
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_intensity", intensity)
		if _lightning_flash != null:
			_lightning_flash.color.a = intensity * 0.14 * (1.0 if outdoors else 0.0)
		_lightning_flash_val = maxf(0.0, _lightning_flash_val - delta * 2.4)
	else:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_intensity", 0.0)
		if _lightning_flash != null:
			_lightning_flash.color.a = 0.0


func _upgrade_cinematic_lighting() -> void:
	for n in find_children("*", "WorldEnvironment", true, false):
		if n.get_parent() != self:
			n.queue_free()
	for old_name in ["LightningLayer", "RainParticles", "RainRoofCollider", "JungleBackdrop", "HarborStormOcean"]:
		if has_node(old_name):
			get_node(old_name).queue_free()

	var map_id := name.to_lower()
	if map_id.contains("mesa"):
		atmosphere_preset = "tropical_storm"
	elif map_id.contains("harbor"):
		atmosphere_preset = "overcast_industrial"
	else:
		atmosphere_preset = "clear_day"

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
	env.tonemap_exposure = 1.0
	env.tonemap_white = 7.5
	env.ssr_enabled = true
	env.ssr_max_steps = 28
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.15
	env.ssil_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.58, 0.62)
	env.ambient_light_energy = 1.65

	for child in get_children():
		if child is DirectionalLight3D:
			_sun_light = child
			_sun_light.shadow_enabled = true
			_sun_light.shadow_blur = 2.2
			_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun_light.directional_shadow_max_distance = 110.0

	if atmosphere_preset == "tropical_storm":
		_apply_tropical_storm(env)
	elif atmosphere_preset == "overcast_industrial":
		_apply_harbor_atmosphere(env)
	else:
		_apply_clean_daylight(env)


func _apply_clean_daylight(env: Environment) -> void:
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.24, 0.44, 0.72)
	mat.sky_horizon_color = Color(0.62, 0.70, 0.78)
	mat.ground_bottom_color = Color(0.25, 0.26, 0.28)
	mat.ground_horizon_color = Color(0.55, 0.60, 0.66)
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.62, 0.68, 0.75)
	env.fog_density = 0.22
	env.fog_depth_begin = 35.0
	env.fog_depth_end = 180.0

	if _sun_light != null:
		_sun_light.light_color = Color(1.0, 0.95, 0.88)
		_sun_light.light_energy = 1.85
		_sun_light.rotation_degrees = Vector3(-42.0, -45.0, 0.0)

	RenderingServer.global_shader_parameter_set("rain_wetness", 0.0)


func _apply_harbor_atmosphere(env: Environment) -> void:
	var sky_shd := Shader.new()
	sky_shd.code = """
shader_type sky;
float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.04 + vec2(1.9, 6.2); a *= 0.5; } return v; }
void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float h = clamp(d.y, 0.005, 1.0);
	vec2 uv = d.xz / (h + 0.18) * 0.9 + vec2(TIME * 0.075, TIME * 0.03);
	float c = fbm(uv) * 0.65 + fbm(uv * 2.4 + vec2(TIME * 0.04, 0.0)) * 0.35;
	float sun_dot = max(dot(d, sun_dir), 0.0);
	vec3 sky_col = mix(vec3(0.22, 0.30, 0.38), vec3(0.11, 0.15, 0.21), smoothstep(0.2, 0.85, c));
	sky_col += vec3(0.95, 0.88, 0.78) * pow(sun_dot, 8.0) * (1.0 - c * 0.5) * 0.85;
	vec3 horizon = vec3(0.36, 0.43, 0.50);
	COLOR = mix(horizon, sky_col, smoothstep(0.0, 0.28, d.y));
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sky_shd
	var sky := Sky.new()
	sky.sky_material = smat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.42, 0.48, 0.55)
	env.fog_density = 0.34
	env.fog_depth_begin = 24.0
	env.fog_depth_end = 150.0

	if _sun_light != null:
		_sun_light.light_color = Color(0.92, 0.94, 0.98)
		_sun_light.light_energy = 1.75
		_sun_light.rotation_degrees = Vector3(-30.0, 125.0, 0.0)

	RenderingServer.global_shader_parameter_set("rain_wetness", 0.0)
	_spawn_harbor_storm_ocean()


func _spawn_harbor_storm_ocean() -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "HarborStormOcean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(360.0, 360.0)
	plane.subdivide_width = 140
	plane.subdivide_depth = 140
	ocean.mesh = plane
	ocean.position = Vector3(0.0, -2.4, 0.0)

	var oshd := Shader.new()
	oshd.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying float wave_h;
varying vec3 w_pos;

float wave(vec2 p, vec2 dir, float freq, float speed, float t) {
	return sin(dot(p, dir) * freq + t * speed);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float h = 0.0;
	h += wave(wp.xz, normalize(vec2(0.85, 0.35)), 0.16, 2.8, t) * 1.45;
	h += wave(wp.xz, normalize(vec2(0.55, -0.75)), 0.28, 3.6, t) * 0.85;
	h += wave(wp.xz, normalize(vec2(-0.35, 0.92)), 0.55, 4.9, t) * 0.38;
	h += wave(wp.xz, normalize(vec2(0.95, 0.15)), 1.15, 6.5, t) * 0.16;
	VERTEX.y += h;
	wave_h = h;
	w_pos = wp + vec3(0.0, h, 0.0);
}

void fragment() {
	vec3 dx = dFdx(w_pos);
	vec3 dz = dFdy(w_pos);
	NORMAL = normalize(cross(dz, dx));

	float crest = smoothstep(0.95, 2.15, wave_h);
	float streak = sin(w_pos.x * 1.8 + w_pos.z * 0.7 + TIME * 3.5) * cos(w_pos.z * 2.1 - TIME * 2.8);
	float foam = clamp(crest * (0.65 + 0.35 * streak), 0.0, 1.0);

	vec3 deep_sea = vec3(0.03, 0.11, 0.17);
	vec3 wave_body = vec3(0.07, 0.22, 0.30);
	vec3 sea_col = mix(deep_sea, wave_body, smoothstep(-1.2, 1.4, wave_h));
	ALBEDO = mix(sea_col, vec3(0.84, 0.90, 0.94), foam * 0.88);
	ROUGHNESS = mix(0.08, 0.55, foam);
	SPECULAR = 0.85;
}
"""
	var omat := ShaderMaterial.new()
	omat.shader = oshd
	ocean.material_override = omat
	add_child(ocean)


func _apply_tropical_storm(env: Environment) -> void:
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
		+ "	vec3 abyss = vec3(0.10, 0.12, 0.16);\n" \
		+ "	vec3 slate = vec3(0.26, 0.30, 0.36);\n" \
		+ "	vec3 steel_rim = vec3(0.48, 0.52, 0.58);\n" \
		+ "	vec3 col = mix(slate, abyss, storm);\n" \
		+ "	col = mix(col, steel_rim, smoothstep(0.55, 0.92, c2) * (1.0 - storm * 0.5));\n" \
		+ "	float sun_break = pow(sun_dot, 5.0) * (1.15 - storm * 0.65);\n" \
		+ "	float sun_core = pow(sun_dot, 90.0) * 1.4;\n" \
		+ "	float anamorphic_streak = exp(-abs(d.y - sun_dir.y) * 28.0) * pow(sun_dot, 6.0) * 0.45;\n" \
		+ "	col += vec3(1.0, 0.84, 0.66) * (sun_break + sun_core + anamorphic_streak);\n" \
		+ "	vec3 horizon = mix(vec3(0.32, 0.35, 0.40), vec3(0.56, 0.48, 0.40), pow(sun_dot, 2.0));\n" \
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

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.36, 0.39, 0.44)
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.48
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 110.0

	if _sun_light != null:
		_sun_light.light_color = Color(1.0, 0.86, 0.72)
		_sun_light.light_energy = 1.85
		_sun_light.rotation_degrees = Vector3(-24.0, -48.0, 0.0)

	_spawn_lightning_and_lens_overlay()
	_spawn_rain_particles()
	_spawn_jungle_backdrop()
	_bake_roof_dry_mask()


func _spawn_lightning_and_lens_overlay() -> void:
	if has_node("LightningLayer"):
		return
	var layer := CanvasLayer.new()
	layer.name = "LightningLayer"
	layer.layer = 5

	var lens_code := "shader_type canvas_item;\n" \
		+ "uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;\n" \
		+ "uniform float intensity = 0.0;\n" \
		+ "uniform vec2 flow_vel = vec2(0.0, 1.0);\n" \
		+ "vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }\n" \
		+ "vec3 drop_layer(vec2 uv, float scale, float speed, float t) {\n" \
		+ "	vec2 st = uv * scale;\n" \
		+ "	vec2 id = floor(st);\n" \
		+ "	vec2 rnd = hash2(id);\n" \
		+ "	float cycle = fract(t * speed * (0.6 + rnd.x * 0.7) + rnd.y * 6.28);\n" \
		+ "	float slide = smoothstep(0.28, 1.0, cycle);\n" \
		+ "	vec2 drift = flow_vel * slide * 0.85;\n" \
		+ "	drift.x += sin(slide * 9.0 + rnd.y * 6.28) * 0.08 * slide;\n" \
		+ "	vec2 gv = fract(st) - 0.5;\n" \
		+ "	vec2 drop_pos = (rnd - 0.5) * 0.78 + drift;\n" \
		+ "	vec2 d = gv - drop_pos;\n" \
		+ "	float stretch = 1.0 + length(flow_vel) * slide * 0.45;\n" \
		+ "	d.y /= stretch;\n" \
		+ "	float dist = length(d);\n" \
		+ "	float active = step(0.56, rnd.x) * (1.0 - smoothstep(0.82, 1.0, cycle));\n" \
		+ "	float r = (0.12 + rnd.y * 0.08) * active;\n" \
		+ "	float drop_mask = smoothstep(r, r * 0.65, dist);\n" \
		+ "	vec2 nrm = (d / max(r, 0.001)) * drop_mask;\n" \
		+ "	vec2 trail_d = gv - (rnd - 0.5) * 0.78;\n" \
		+ "	float along = dot(trail_d, normalize(flow_vel + vec2(0.0001, 1.0)));\n" \
		+ "	float perp = length(trail_d - normalize(flow_vel + vec2(0.0001, 1.0)) * along);\n" \
		+ "	float in_trail = smoothstep(0.0, 0.08, along) * (1.0 - smoothstep(length(drift) - 0.05, length(drift) + 0.02, along));\n" \
		+ "	float trail_mask = smoothstep(r * 0.42, r * 0.1, perp) * in_trail * active * 0.55;\n" \
		+ "	vec2 trail_nrm = (trail_d * 2.5) * trail_mask;\n" \
		+ "	return vec3(nrm + trail_nrm, max(drop_mask, trail_mask));\n" \
		+ "}\n" \
		+ "void fragment() {\n" \
		+ "	if (intensity <= 0.005) { discard; }\n" \
		+ "	vec2 aspect = vec2(1.777, 1.0);\n" \
		+ "	vec2 uv = SCREEN_UV * aspect;\n" \
		+ "	float edge_mask = smoothstep(0.18, 0.58, length(SCREEN_UV - 0.5));\n" \
		+ "	vec3 l1 = drop_layer(uv, 4.8, 0.20, TIME);\n" \
		+ "	vec3 l2 = drop_layer(uv + vec2(0.37, 0.71), 9.5, 0.13, TIME + 3.1);\n" \
		+ "	vec3 l3 = drop_layer(uv + vec2(0.83, 0.19), 18.0, 0.06, TIME + 7.4);\n" \
		+ "	vec2 total_nrm = (l1.xy * 1.3 + l2.xy * 0.85 + l3.xy * 0.45) * intensity * edge_mask;\n" \
		+ "	float mask = clamp((l1.z + l2.z * 0.8 + l3.z * 0.5) * intensity * edge_mask, 0.0, 1.0);\n" \
		+ "	if (mask <= 0.005) { discard; }\n" \
		+ "	vec3 refracted = textureLod(screen_tex, SCREEN_UV - total_nrm * 0.045, 0.6).rgb;\n" \
		+ "	float spec = pow(max(dot(normalize(vec3(-total_nrm * 2.2, 1.0)), normalize(vec3(-0.35, -0.55, 0.75))), 0.0), 18.0);\n" \
		+ "	float fresnel = smoothstep(0.25, 0.95, length(total_nrm)) * 0.25;\n" \
		+ "	vec3 water_col = refracted * (1.06 - fresnel) + vec3(0.92, 0.96, 1.0) * spec * 0.65;\n" \
		+ "	COLOR = vec4(water_col, clamp(mask * 1.4, 0.0, 0.95));\n" \
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
