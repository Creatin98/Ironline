class_name DazeOverlay
extends CanvasLayer
## "Shaken" vision (double image, slow drift) while the player is dazed by a flashbang; behind the HUD.

var _rect: ColorRect
var _mat: ShaderMaterial
var _t: float = 0.0


func _ready() -> void:
	layer = 0
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/daze.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func set_amount(a: float, delta: float) -> void:
	_t += delta
	a = a if GameSettings.post_processing else 0.0
	_rect.visible = a > 0.01
	_mat.set_shader_parameter("amount", a)
	_mat.set_shader_parameter("t", _t)
