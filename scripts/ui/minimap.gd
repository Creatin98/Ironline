class_name Minimap
extends Control
## Rotating top-down minimap (view direction = up). The picture is a small top-down render of the
## real map; the overlay shows the local player, teammates and enemy gunfire (short flashes).

const PX := 220
const VIEW_METERS := 60.0 # width of the area shown: zoomed out, not glued to the player
const FLASH_TIME := 1.4

var player: Player

var _cam: Camera3D
var _overlay: Control
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
	var cont := SubViewportContainer.new()
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.stretch = true
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.modulate = Color(0.85, 0.9, 0.95, 0.92)
	add_child(cont)
	var vp := SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cont.add_child(vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_METERS
	_cam.near = 1.0
	_cam.far = 260.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	_cam.environment = env
	vp.add_child(_cam)
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
	if player != null and is_instance_valid(player):
		var pos := player.global_position
		_cam.global_transform = Transform3D(Basis(Vector3.UP, player.rotation.y) * Basis(Vector3.RIGHT, -PI / 2.0), pos + Vector3.UP * 100.0)
	_overlay.queue_redraw()


func _on_shot(shooter_id: int, pos: Vector3) -> void:
	if shooter_id == MatchManager.local_participant_id:
		return
	var me := MatchManager.get_local_participant()
	var shooter := MatchManager.get_participant(shooter_id)
	if shooter == null:
		return
	if MatchManager.mode != null and MatchManager.mode.uses_teams and me != null and shooter.team == me.team:
		return # teammates are drawn as dots anyway
	_flashes.append({"pos": pos, "t": FLASH_TIME})
	if _flashes.size() > 12:
		_flashes.pop_front()


## World position -> pixel inside the minimap (player in the middle, view direction up).
func _to_map(world: Vector3) -> Vector2:
	var rel := world - player.global_position
	var local := Basis(Vector3.UP, -player.rotation.y) * rel
	var scale := float(PX) / VIEW_METERS
	return Vector2(PX, PX) * 0.5 + Vector2(local.x, local.z) * scale


func _clamp_to_edge(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 6.0, PX - 6.0), clampf(p.y, 6.0, PX - 6.0))


func _draw_overlay() -> void:
	var o := _overlay
	o.draw_rect(Rect2(Vector2.ZERO, Vector2(PX, PX)), Color(0.9, 0.7, 0.3, 0.9), false, 2.0)
	if player == null or not is_instance_valid(player):
		return
	var me := MatchManager.get_local_participant()
	# teammates
	if MatchManager.mode != null and MatchManager.mode.uses_teams and me != null:
		for p in MatchManager.participants.values():
			if p.id == me.id or p.team != me.team or not p.alive or p.node == null or not is_instance_valid(p.node):
				continue
			var n := p.node as Player
			var pos := _clamp_to_edge(_to_map(n.global_position))
			var heading := Basis(Vector3.UP, -player.rotation.y) * (Basis(Vector3.UP, n.rotation.y) * Vector3(0, 0, -1))
			_draw_arrow(o, pos, Vector2(heading.x, heading.z).normalized(), Teams.color_of(p.team), 6.0)
	# enemy gunfire
	for f in _flashes:
		var life := clampf(float(f["t"]) / FLASH_TIME, 0.0, 1.0)
		var pos := _clamp_to_edge(_to_map(f["pos"]))
		var col := Color(1.0, 0.25, 0.2, life)
		o.draw_circle(pos, 3.5, col)
		o.draw_arc(pos, 4.0 + (1.0 - life) * 12.0, 0.0, TAU, 20, Color(1.0, 0.3, 0.2, life * 0.8), 2.0)
	# the local player in the middle
	_draw_arrow(o, Vector2(PX, PX) * 0.5, Vector2(0, -1), Color(1.0, 0.95, 0.6), 8.0)


func _draw_arrow(o: Control, c: Vector2, dir: Vector2, col: Color, r: float) -> void:
	if dir.length() < 0.1:
		dir = Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([c + dir * r, c - dir * r * 0.7 + side * r * 0.7, c - dir * r * 0.25, c - dir * r * 0.7 - side * r * 0.7])
	o.draw_colored_polygon(pts, col)
	o.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.7), 1.2)
