class_name LensFlare
extends Control
## Screen-space lens flare of the sun: a soft core with halo, an anamorphic streak, a ring and a chain of coloured ghosts
## along the line through the screen centre. Strength follows how directly the camera looks at the sun and fades out
## smoothly when a wall or building covers the sun (ray test). Purely visual, drawn additively on its own canvas layer.

var sun: DirectionalLight3D
var _vis: float = 0.0
var _glow: ImageTexture
var _ring: ImageTexture
var _hex: ImageTexture
var _material: CanvasItemMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = _material
	_glow = _make_glow(128, 2.2)
	_ring = _make_ring(128)
	_hex = _make_hex(128)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if sun == null or cam == null or not is_instance_valid(sun):
		visible = false
		return
	var to_sun := sun.global_transform.basis.z.normalized() # a directional light shines along -Z: the sun is at +Z
	var target := smoothstep(0.2, 0.92, (-cam.global_transform.basis.z).dot(to_sun)) # 1 = looking straight at the sun
	if target > 0.0:
		var space := cam.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + to_sun * 600.0, 1)
		if not space.intersect_ray(q).is_empty():
			target = 0.0
	target *= float(sun.get_meta("clear", 1.0)) # clouds in front of the sun weaken the flare
	_vis = move_toward(_vis, target, delta * 4.0)
	visible = _vis > 0.01
	if visible:
		queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or sun == null:
		return
	var to_sun := sun.global_transform.basis.z.normalized()
	var sun_world := cam.global_position + to_sun * 800.0
	if cam.is_position_behind(sun_world):
		return
	var size := get_viewport_rect().size
	var k := size.y / 1080.0
	var p := cam.unproject_position(sun_world)
	var c := size * 0.5
	var v := c - p
	var diag := size.length()
	var centred := 1.0 - clampf((p - c).length() / (diag * 0.55), 0.0, 1.0) # ghosts are strongest when the sun is near the middle
	var i := _vis
	var tint := sun.light_color
	# core, halo and the anamorphic streak
	_blob(_glow, p, 150.0 * k, Color(1.0, 0.93, 0.78, 0.6 * i))
	_blob(_glow, p, 520.0 * k, Color(tint.r, tint.g * 0.92, tint.b * 0.75, 0.16 * i))
	_blob(_glow, p, 1500.0 * k, Color(1.0, 0.85, 0.6, 0.07 * i))
	draw_texture_rect(_glow, Rect2(p.x - 900.0 * k, p.y - 14.0 * k, 1800.0 * k, 28.0 * k), false, Color(0.7, 0.85, 1.0, 0.42 * i))
	draw_texture_rect(_glow, Rect2(p.x - 420.0 * k, p.y - 5.0 * k, 840.0 * k, 10.0 * k), false, Color(1.0, 1.0, 1.0, 0.5 * i))
	# ring around the sun
	_blob(_ring, p, 760.0 * k, Color(1.0, 0.88, 0.7, 0.03 * i))
	# ghosts along the axis through the centre
	var ghosts := [
		[0.28, 80.0, Color(0.5, 1.0, 0.7), 0.10, 0], [0.55, 46.0, Color(1.0, 0.55, 0.35), 0.07, 0], [0.82, 130.0, Color(0.55, 0.7, 1.0), 0.05, 2],
		[1.12, 60.0, Color(1.0, 0.8, 0.4), 0.09, 0], [1.45, 160.0, Color(0.9, 0.5, 1.0), 0.06, 0], [1.85, 100.0, Color(0.5, 1.0, 0.9), 0.05, 0],
	]
	for g in ghosts:
		var gp := p + v * float(g[0])
		var col: Color = g[2]
		col.a = float(g[3]) * 1.5 * i * (0.35 + 0.65 * centred)
		var tex: ImageTexture = _hex if int(g[4]) == 2 else (_ring if int(g[4]) == 1 else _glow)
		_blob(tex, gp, float(g[1]) * 2.0 * k, col)


func _blob(tex: Texture2D, center: Vector2, diameter: float, col: Color) -> void:
	draw_texture_rect(tex, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), false, col)


static func _make_glow(n: int, power: float) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0).length()
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _make_ring(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0).length()
			var a := exp(-pow((d - 0.78) / 0.09, 2.0)) * clampf((1.0 - d) * 6.0, 0.0, 1.0) + 0.18 * clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A soft hexagon (aperture ghost).
static func _make_hex(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0)
			var a := absf(p.x) * 0.866 + absf(p.y) * 0.5
			var h := maxf(a, absf(p.y))
			var edge := clampf((0.9 - h) / 0.12, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, edge * (0.35 + 0.65 * smoothstep(0.5, 0.9, h))))
	return ImageTexture.create_from_image(img)
