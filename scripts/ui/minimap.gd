class_name Minimap
extends Control
## Rotating top-down minimap (view direction = up). The map is drawn as simple outlines of walls,
## houses and crates (taken from the collision shapes). Teammates are arrows, enemies only flash up
## as arrows at the moment they shoot (like Black Ops 2).

const PX := 220
const VIEW_METERS := 60.0 # width of the area shown: zoomed out, not glued to the player
const FLASH_TIME := 1.6
const ALLY_FLASH_TIME := 0.7
const ALLY_COLOR := Color(0.25, 0.6, 1.0) # teammates are always blue on the map, whatever the team colour

var player: Player

var _solids: Array = [] # [{pts: PackedVector2Array (world x/z), top: float}]
var _floors: Array = []
var _overlay: Control
var _redraw_timer: float = 0.0
var _ally_flash: Dictionary = {} # participant id -> seconds left of the "fired" glow
var _self_flash: float = 0.0
var _flashes: Array = [] # [{pos: Vector3, t: float}]


func _ready() -> void:
	custom_minimum_size = Vector2(PX, PX)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.06, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	GameEvents.shot_fired.connect(_on_shot)


func _process(delta: float) -> void:
	for f in _flashes:
		f["t"] = float(f["t"]) - delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return float(f["t"]) > 0.0)
	for id in _ally_flash.keys():
		_ally_flash[id] = float(_ally_flash[id]) - delta
		if float(_ally_flash[id]) <= 0.0:
			_ally_flash.erase(id)
	_self_flash = maxf(0.0, _self_flash - delta)
	if DisplayServer.get_name() == "headless" or not is_visible_in_tree():
		return # nothing to draw (tests / dedicated runs / hidden HUD)
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / 40.0 # 40 Hz is smooth enough for a minimap and cheaper than every frame
		_overlay.queue_redraw()


func _on_shot(shooter_id: int, pos: Vector3) -> void:
	if shooter_id == MatchManager.local_participant_id:
		_self_flash = ALLY_FLASH_TIME # our own arrow lights up when we fire
		return
	var me := MatchManager.get_local_participant()
	var shooter := MatchManager.get_participant(shooter_id)
	if shooter == null:
		return
	if MatchManager.mode != null and MatchManager.mode.uses_teams and me != null and shooter.team == me.team:
		_ally_flash[shooter_id] = ALLY_FLASH_TIME # teammates are always shown, they light up when firing
		return
	_flashes.append({"pos": pos, "t": FLASH_TIME})
	if _flashes.size() > 12:
		_flashes.pop_front()


## Collects the footprints of everything solid in the map (call once after the map is loaded).
func build_from(map_root: Node) -> void:
	_solids.clear()
	_floors.clear()
	var stack: Array = [map_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is CollisionShape3D) or (n as CollisionShape3D).shape == null:
			continue
		var cs := n as CollisionShape3D
		var body := cs.get_parent()
		if body is CollisionObject3D and (body as CollisionObject3D).collision_layer & 1 == 0:
			continue
		var mesh := cs.shape.get_debug_mesh()
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		var xf := cs.global_transform
		var pts := PackedVector2Array()
		var top := -INF
		var bottom := INF
		for corner in [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z)]:
			var w: Vector3 = xf * corner
			pts.append(Vector2(w.x, w.z))
		for cy in [box.position.y, box.end.y]:
			var wy: float = (xf * Vector3(0, cy, 0)).y
			top = maxf(top, wy)
			bottom = minf(bottom, wy)
		if top < 0.55:
			_floors.append({"pts": pts})
		elif top - bottom > 0.6 or top > 1.0:
			_solids.append({"pts": pts})


## Transform from world (x, z) to minimap pixels: player in the middle, view direction up.
func _world_to_map_transform() -> Transform2D:
	var yaw := player.rotation.y
	var k := float(PX) / VIEW_METERS
	var xa := Vector2(cos(yaw), sin(yaw)) * k
	var ya := Vector2(-sin(yaw), cos(yaw)) * k
	var origin := Vector2(PX, PX) * 0.5 - (xa * player.global_position.x + ya * player.global_position.z)
	return Transform2D(xa, ya, origin)


## World position -> pixel inside the minimap (player in the middle, view direction up).
func _to_map(world: Vector3) -> Vector2:
	return _world_to_map_transform() * Vector2(world.x, world.z)


func _clamp_to_edge(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 8.0, PX - 8.0), clampf(p.y, 8.0, PX - 8.0))


func _draw_overlay() -> void:
	var o := _overlay
	o.draw_rect(Rect2(Vector2.ZERO, Vector2(PX, PX)), Color(0.04, 0.05, 0.06, 0.82), true)
	if player == null or not is_instance_valid(player):
		o.draw_rect(Rect2(Vector2.ZERO, Vector2(PX, PX)), Color(0.9, 0.7, 0.3, 0.9), false, 2.0)
		return
	var xf := _world_to_map_transform()
	for f in _floors:
		var pts: PackedVector2Array = xf * (f["pts"] as PackedVector2Array)
		o.draw_colored_polygon(pts, Color(0.16, 0.18, 0.2, 0.9))
	for sd in _solids:
		var pts2: PackedVector2Array = xf * (sd["pts"] as PackedVector2Array)
		o.draw_colored_polygon(pts2, Color(0.34, 0.37, 0.4, 0.95))
		var closed := pts2.duplicate()
		closed.append(pts2[0])
		o.draw_polyline(closed, Color(0.7, 0.74, 0.78, 0.9), 1.2)
	var me := MatchManager.get_local_participant()
	# teammates: always visible arrows
	if MatchManager.mode != null and MatchManager.mode.uses_teams and me != null:
		for p in MatchManager.participants.values():
			if p.id == me.id or p.team != me.team or not p.alive or p.node == null or not is_instance_valid(p.node):
				continue
			var n := p.node as Player
			var pos := _clamp_to_edge(_to_map(n.global_position))
			var glow := clampf(float(_ally_flash.get(p.id, 0.0)) / ALLY_FLASH_TIME, 0.0, 1.0)
			_draw_arrow_glow(o, pos, _heading(n.rotation.y), ALLY_COLOR, 9.0, glow)
	# enemies: only the moment they fire, as a red dot with a fading ring (no arrows)
	for f in _flashes:
		var life := clampf(float(f["t"]) / FLASH_TIME, 0.0, 1.0)
		var pos2 := _clamp_to_edge(_to_map(f["pos"]))
		o.draw_circle(pos2, 5.0, Color(0.0, 0.0, 0.0, life * 0.7))
		o.draw_circle(pos2, 4.0, Color(1.0, 0.18, 0.14, clampf(life * 1.6, 0.0, 1.0)))
		o.draw_arc(pos2, 6.0 + (1.0 - life) * 12.0, 0.0, TAU, 20, Color(1.0, 0.3, 0.2, life * 0.8), 2.0)
	# the local player in the middle (lights up while firing)
	_draw_arrow_glow(o, Vector2(PX, PX) * 0.5, Vector2(0, -1), Color(1.0, 0.95, 0.6), 9.0, clampf(_self_flash / ALLY_FLASH_TIME, 0.0, 1.0))
	o.draw_rect(Rect2(Vector2.ZERO, Vector2(PX, PX)), Color(0.9, 0.7, 0.3, 0.9), false, 2.0)


## Direction of a player with this yaw on the map (player's own view direction points up).
func _heading(yaw: float) -> Vector2:
	var h := Basis(Vector3.UP, -player.rotation.y) * (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1))
	return Vector2(h.x, h.z).normalized()


## Arrow that lights up (white core, pulsing ring) while `glow` > 0, e.g. right after a shot.
func _draw_arrow_glow(o: Control, c: Vector2, dir: Vector2, col: Color, r: float, glow: float) -> void:
	if glow > 0.0:
		o.draw_circle(c, r * (1.5 + 0.8 * (1.0 - glow)), Color(col.r, col.g, col.b, 0.35 * glow))
		o.draw_arc(c, r * (1.3 + 1.2 * (1.0 - glow)), 0.0, TAU, 24, Color(1, 1, 1, 0.8 * glow), 2.0)
	_draw_arrow(o, c, dir, col.lerp(Color.WHITE, 0.7 * glow), r * (1.0 + 0.25 * glow))


func _draw_arrow(o: Control, c: Vector2, dir: Vector2, col: Color, r: float) -> void:
	if dir.length() < 0.1:
		dir = Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([c + dir * r, c - dir * r * 0.75 + side * r * 0.75, c - dir * r * 0.3, c - dir * r * 0.75 - side * r * 0.75])
	o.draw_colored_polygon(pts, col)
	o.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, col.a * 0.85), 1.5)
