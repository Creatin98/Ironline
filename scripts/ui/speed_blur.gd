class_name SpeedBlur
extends CanvasLayer
## Edge motion blur for sprinting (behind the HUD); strength follows the camera's sprint blend.

var _rect: ColorRect
var _mat: ShaderMaterial
var _amount: float = 0.0


func _ready() -> void:
	layer = 0
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/speed_blur.gdshader")
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = false


func set_amount(a: float, delta: float) -> void:
	_amount = lerpf(_amount, a if GameSettings.post_processing else 0.0, minf(1.0, delta * 8.0))
	_rect.visible = _amount > 0.01
	_mat.set_shader_parameter("amount", _amount)
