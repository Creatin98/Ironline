extends Node3D
## Short-lived muzzle flash: billboard quad + omni light.

const FLASH_TIME := 0.045

@onready var light: OmniLight3D = $Light
@onready var quad: MeshInstance3D = $Quad

var _timer: float = 0.0


func _ready() -> void:
	_soften_quad()
	light.visible = false
	quad.visible = false
	set_process(false)


func flash() -> void:
	_timer = FLASH_TIME
	light.visible = true
	quad.visible = true
	quad.rotation.z = randf() * TAU
	var s := randf_range(0.8, 1.3)
	quad.scale = Vector3(s, s, s)
	light.light_energy = randf_range(2.5, 4.0)
	set_process(true)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		light.visible = false
		quad.visible = false
		set_process(false)


## Radial soft sprite instead of a hard-edged square (matters most when seen up close).
func _soften_quad() -> void:
	var mat := (quad.mesh as QuadMesh).material as StandardMaterial3D
	if mat == null or mat.albedo_texture != null:
		return
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 0.98, 0.85, 1.0), Color(1.0, 0.75, 0.3, 0.6), Color(1.0, 0.5, 0.1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
