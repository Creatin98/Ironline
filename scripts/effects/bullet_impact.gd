extends Node3D
## Bullet impact: sparks/dust or blood particles plus a small decal quad that fades.

const DECAL_LIFETIME := 12.0
const PARTICLE_LIFETIME := 0.6
const MAX_LIVE := 64 # oldest impacts disappear first (keeps node count low in long fights)

static var _live: Array = []

@onready var particles: CPUParticles3D = $Particles
@onready var decal: MeshInstance3D = $Decal

var _life: float = 0.0
var _is_blood: bool = false


func setup(pos: Vector3, normal: Vector3, blood: bool) -> void:
	_is_blood = blood
	_live.append(self)
	while _live.size() > MAX_LIVE:
		var oldest = _live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	global_position = pos + normal * 0.01
	# look_at points local -Z at the target, so aiming at (pos - normal)
	# leaves local +Z (quad front, particle direction) along the surface normal
	if absf(normal.dot(Vector3.UP)) > 0.99:
		look_at(global_position - normal, Vector3.FORWARD)
	else:
		look_at(global_position - normal, Vector3.UP)
	if blood:
		particles.color = Color(0.55, 0.05, 0.05, 1.0)
		particles.amount = 10
		particles.initial_velocity_min = 1.5
		particles.initial_velocity_max = 4.0
		particles.gravity = Vector3(0, -9.0, 0)
		decal.visible = false
	else:
		particles.color = Color(1.0, 0.82, 0.45, 1.0)
		AudioManager.play_3d("bullet_impact", pos, -10.0, 0.15, 35.0)
		if randf() < 0.25:
			AudioManager.play_3d("ricochet", pos, -14.0, 0.2, 40.0)
	particles.emitting = true
	_life = DECAL_LIFETIME if not blood else PARTICLE_LIFETIME + 0.2


func _exit_tree() -> void:
	_live.erase(self)


func _process(delta: float) -> void:
	_life -= delta
	if decal.visible and _life < 2.0:
		var m := decal.material_override as StandardMaterial3D
		if m:
			m.albedo_color.a = clampf(_life / 2.0, 0.0, 1.0) * 0.85
	if _life <= 0.0:
		queue_free()
