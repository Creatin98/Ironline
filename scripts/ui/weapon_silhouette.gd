class_name WeaponSilhouette
extends Control
## The carried weapon as a detailed picture in the ammo panel: its real 3D model (hands hidden) rendered from the side
## into a transparent SubViewport with a low raking light, so every part (stock, magazine, rails, sights) is visible.
## The weapon name drops in above it (see Hud).

const VIEW_SIZE := Vector2i(600, 200)

var weapon_id: String = ""
var _viewport: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _rect: TextureRect


func _init() -> void:
	custom_minimum_size = Vector2(250, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.64)
	env.ambient_light_energy = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 1.1
	fill.rotation_degrees = Vector3(-10.0, 140.0, 0.0)
	_viewport.add_child(fill)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_cam)
	_cam.current = true
	_rect = TextureRect.new()
	_rect.texture = _viewport.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.self_modulate = Color(1.25, 1.25, 1.3) # lifted a little: dark steel on a dark panel
	add_child(_rect)
	if weapon_id != "":
		set_weapon(weapon_id)


func set_weapon(id: String) -> void:
	weapon_id = id
	if _pivot == null:
		return
	for c in _pivot.get_children():
		c.queue_free()
	var data := WeaponPickup.weapon_data(id)
	if data == null or data.model_scene == null:
		return
	var model: Node3D = data.model_scene.instantiate()
	for n in ["LeftHand", "RightHand"]:
		var h := model.get_node_or_null(n) as Node3D
		if h != null:
			h.visible = false
	_pivot.add_child(model)
	# frame the model: side view (the muzzle points right), centred, a little margin
	var box := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null and not mi.name.contains("Flash"):
			var a: AABB = model.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())
			box = a if first else box.merge(a)
			first = false
	if first:
		return
	var c := box.get_center()
	var aspect := float(VIEW_SIZE.x) / float(VIEW_SIZE.y)
	_cam.size = maxf(box.size.z * 1.0 / aspect, box.size.y * 1.25) # orthogonal size = height
	_cam.position = c + Vector3(3.0, 0.0, 0.0)
	_cam.look_at(c, Vector3.UP)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
