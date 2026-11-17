class_name Grenade
extends RigidBody3D
## Thrown frag grenade: short fuse, radial damage with line-of-sight check.

const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")
const FUSE_TIME := 2.4
const RADIUS := 6.5
const MAX_DAMAGE := 230.0 # a direct hit kills at full health (200)
const MIN_DAMAGE := 25.0
const BOUNCE_SOUND_COOLDOWN := 0.25

var thrower_id: int = 0
var thrower_team: int = Teams.Team.NONE

var _fuse: float = FUSE_TIME
var _exploded: bool = false
var _bounce_cooldown: float = 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)


func launch(initial_velocity: Vector3) -> void:
	linear_velocity = initial_velocity
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _process(delta: float) -> void:
	_bounce_cooldown = maxf(0.0, _bounce_cooldown - delta)
	_fuse -= delta
	if _fuse <= 0.0 and not _exploded:
		explode()


func _on_body_entered(_body: Node) -> void:
	if _bounce_cooldown > 0.0 or linear_velocity.length() < 1.5:
		return
	_bounce_cooldown = BOUNCE_SOUND_COOLDOWN
	AudioManager.play_3d("grenade_bounce", global_position, -8.0, 0.1, 30.0)


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	var center := global_position + Vector3(0.0, 0.25, 0.0)
	var fx := EXPLOSION_SCENE.instantiate()
	var parent := get_tree().get_first_node_in_group("effects_container")
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(fx)
	fx.global_position = center
	if fx.has_method("play"):
		fx.play()
	GameEvents.explosion_at.emit(center, RADIUS)
	if MatchManager.is_authority():
		_apply_damage(center)
	queue_free()


func _apply_damage(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("players"):
		var target := node as Player
		if target == null or not target.alive:
			continue
		var target_center := target.get_center()
		var distance := center.distance_to(target_center)
		if distance > RADIUS:
			continue
		# line of sight against world geometry only
		var query := PhysicsRayQueryParameters3D.create(center, target_center, 1)
		if not space.intersect_ray(query).is_empty():
			# try the feet as well: cover that only hides the torso still lets splash through
			var feet_query := PhysicsRayQueryParameters3D.create(center, target.global_position + Vector3(0, 0.2, 0), 1)
			if not space.intersect_ray(feet_query).is_empty():
				continue
		var t := clampf(distance / RADIUS, 0.0, 1.0)
		var damage := lerpf(MAX_DAMAGE, MIN_DAMAGE, t * t)
		target.take_damage(damage, thrower_id, "grenade", target_center, false, center)
