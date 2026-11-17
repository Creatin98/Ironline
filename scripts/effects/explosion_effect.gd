extends Node3D
## Grenade explosion: fireball + smoke particles, light flash, sound, camera shake.

const LIFETIME := 3.5

@onready var fire: CPUParticles3D = $Fire
@onready var smoke: CPUParticles3D = $Smoke
@onready var debris: CPUParticles3D = $Debris
@onready var light: OmniLight3D = $Light

var _life: float = LIFETIME
var _light_energy_start: float = 14.0


func play() -> void:
	fire.emitting = true
	smoke.emitting = true
	debris.emitting = true
	light.visible = true
	light.light_energy = _light_energy_start
	AudioManager.play_3d("explosion", global_position, 14.0, 0.08, 200.0)
	# shake nearby local camera
	var local := get_tree().get_first_node_in_group("local_player") as Player
	if local and local.alive:
		var d := local.global_position.distance_to(global_position)
		if d < 18.0:
			local.head.add_shake(clampf(1.0 - d / 18.0, 0.0, 1.0) * 1.4)


func _process(delta: float) -> void:
	_life -= delta
	if light.visible:
		light.light_energy = maxf(0.0, light.light_energy - delta * 40.0)
		if light.light_energy <= 0.0:
			light.visible = false
	if _life <= 0.0:
		queue_free()
