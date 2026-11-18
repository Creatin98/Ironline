class_name ScopeOverlay
extends CanvasLayer
## Scoped weapons (sniper): while aiming the picture is not just zoomed or framed by black borders - a second camera
## (same world, narrow field of view) renders what the scope shows, and the shader puts that sharp zoomed circle with its
## reticle into the middle of the screen. Around it the normal, un-zoomed picture is visible, blurred and darkened.
## The viewmodel is on its own render layer so the scope camera never sees it.
## The circle opens with the aim blend (WeaponManager.scope_blend); the wheel changes the zoom (Weapon.zoom_step).

const SHADER := preload("res://assets/shaders/scope_view.gdshader")
const VIEW_SIZE := 768
## Render layer of the first-person viewmodel (weapon, arms, grenade): the scope camera leaves it out.
const VIEWMODEL_LAYER := 1 << 19

var rect: ColorRect
## Current iris 0..1.
var open: float = 0.0

var _material: ShaderMaterial
var _sub: SubViewport
var _cam: Camera3D
var _was_open: bool = false
var _zoom_flash: float = 0.0
var _last_scope_index: int = -1
## Killcam / last kill cam: the recorder tells whether the killer looks through a scope (set by Game).
var recorder: ReplayRecorder


func _ready() -> void:
	layer = 1 # above the 3D world, below the HUD
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	rect.material = _material
	rect.visible = false
	add_child(rect)
	_sub = SubViewport.new()
	_sub.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sub.msaa_3d = Viewport.MSAA_2X
	add_child(_sub)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.05
	_cam.cull_mask = 0xFFFFF & ~VIEWMODEL_LAYER
	_sub.add_child(_cam)
	_material.set_shader_parameter("scope_tex", _sub.get_texture())


func is_open() -> bool:
	return open > 0.001


func _process(delta: float) -> void:
	var me := MatchManager.get_local_participant()
	var target := 0.0
	var pl: Player = null
	var w: Weapon = null
	if me != null and me.alive and me.node != null and is_instance_valid(me.node):
		pl = me.node as Player
		if pl != null and not pl.replay_mode and MatchManager.state != MatchManager.State.ENDED:
			w = pl.weapon_manager.get_current_weapon()
			if w != null and w.data.scoped:
				target = pl.weapon_manager.scope_blend()
	var scope_fov := 0.0
	var scope_index := 0
	if w != null and w.data.scoped:
		scope_fov = w.scope_fov()
		scope_index = w.scope_index
	# killcam: the killer's view through his scope (same picture, opens with the killer's aim blend)
	var replay_view := false
	if recorder != null and recorder.playing and target <= 0.0:
		var kf := recorder.killer_scope_fov()
		if kf > 0.0:
			replay_view = true
			scope_fov = kf
			target = clampf((recorder.killer_aim - Player.REPLAY_SCOPE_HIDE_AT) / (1.0 - Player.REPLAY_SCOPE_HIDE_AT), 0.0, 1.0)
	open = target
	var now_open := open > 0.001
	if now_open != _was_open:
		_was_open = now_open
		AudioManager.play_2d("sniper_scope_in" if now_open else "sniper_scope_out", -6.0, 0.02)
	if not now_open or (not replay_view and (w == null or pl == null)):
		if rect.visible:
			rect.visible = false
			_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not rect.visible:
		rect.visible = true
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_cam.fov = scope_fov
		_last_scope_index = scope_index
	# the zoom glides between the steps and flashes a little
	if scope_index != _last_scope_index:
		_last_scope_index = scope_index
		_zoom_flash = 1.0
	_zoom_flash = move_toward(_zoom_flash, 0.0, delta * 5.0)
	_cam.fov = lerpf(_cam.fov, scope_fov, 1.0 - exp(-delta * 16.0))
	var main_cam := get_viewport().get_camera_3d()
	if main_cam != null:
		_cam.far = main_cam.far
		_cam.global_transform = main_cam.global_transform
	var size := get_viewport().get_visible_rect().size
	_material.set_shader_parameter("open", open)
	_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_material.set_shader_parameter("zoom_flash", _zoom_flash)


## Puts every visual part of `root` on the viewmodel layer (called for weapon models, arms and the grenade view).
static func tag_viewmodel(root: Node) -> void:
	for n in root.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = VIEWMODEL_LAYER
