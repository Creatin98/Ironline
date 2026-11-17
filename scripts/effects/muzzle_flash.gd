extends Node3D
## Short-lived muzzle flash: billboard quad + omni light.

const FLASH_TIME := 0.045

@onready var light: OmniLight3D = $Light
@onready var quad: MeshInstance3D = $Quad

var _timer: float = 0.0


func _ready() -> void:
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
