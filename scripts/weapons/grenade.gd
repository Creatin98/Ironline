class_name Grenade
extends RigidBody3D
## Thrown grenade. KIND_FRAG: short fuse, radial damage with line-of-sight check. KIND_FLASH (flashbang): shorter
## fuse, no damage but a blinding flash and a bang (see FlashMath / FlashOverlay); both hurt a little when they hit an
## enemy on the way (direct hit: a few points of damage and a hitmarker).

const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")
const FUSE_TIME := 2.4
const RADIUS := 6.5
const MAX_DAMAGE := 290.0 # a direct hit kills at full health (250)
const MIN_DAMAGE := 25.0
const BOUNCE_SOUND_COOLDOWN := 0.25
const KIND_FRAG := 0
const KIND_FLASH := 1
const FLASH_FUSE_TIME := 1.6
## Damage of a grenade that hits an enemy on its way (a direct hit, no explosion needed).
const DIRECT_HIT_DAMAGE := 5.0
const DIRECT_HIT_MIN_SPEED := 3.0

var kind: int = KIND_FRAG
var thrower_id: int = 0
var thrower_team: int = Teams.Team.NONE
## Network id (server-assigned); 0 offline.
var net_id: int = 0
## Client copy: only flies and bounces, the server decides when it explodes.
var visual_only: bool = false

var _fuse: float = FUSE_TIME
var _exploded: bool = false
var _bounce_cooldown: float = 0.0
var _hit_bodies: Dictionary = {} # instance ids of players this grenade already hit (once each)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	if kind == KIND_FLASH:
		_fuse = FLASH_FUSE_TIME
		_build_flash_look()


## Flashbang look: a silver can with dark end caps and band, a straight lever - clearly not the green round frag grenade.
func _build_flash_look() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.74, 0.76, 0.80)
	steel.metallic = 0.75
	steel.roughness = 0.32
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.10)
	dark.metallic = 0.3
	dark.roughness = 0.6
	var body := $Mesh as MeshInstance3D
	var can := CylinderMesh.new()
	can.top_radius = 0.033
	can.bottom_radius = 0.033
	can.height = 0.115
	can.radial_segments = 14
	can.material = steel
	body.mesh = can
	for part in [[0.060, 0.026, 0.0345], [-0.060, 0.026, 0.0345], [0.012, 0.012, 0.0340]]: # fuze cap, bottom cap, band
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(part[2])
		cm.bottom_radius = float(part[2])
		cm.height = float(part[1])
		cm.radial_segments = 14
		cm.material = dark
		mi.mesh = cm
		mi.position = Vector3(0.0, float(part[0]), 0.0)
		add_child(mi)
	var lever := $Lever as MeshInstance3D
	var lm := BoxMesh.new()
	lm.size = Vector3(0.006, 0.118, 0.022)
	lm.material = dark
	lever.mesh = lm
	lever.position = Vector3(0.036, 0.006, 0.0)


func launch(initial_velocity: Vector3) -> void:
	linear_velocity = initial_velocity
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _process(delta: float) -> void:
	_bounce_cooldown = maxf(0.0, _bounce_cooldown - delta)
	_fuse -= delta
	if _fuse <= (-1.5 if visual_only else 0.0) and not _exploded:
		explode()


func _on_body_entered(body: Node) -> void:
	if body is Player and not visual_only and MatchManager.is_authority():
		_direct_hit(body as Player)
	if _bounce_cooldown > 0.0 or linear_velocity.length() < 1.5:
		return
	_bounce_cooldown = BOUNCE_SOUND_COOLDOWN
	AudioManager.play_3d("grenade_bounce", global_position, -1.0, 0.1, 30.0)


## A grenade that flies into an enemy hurts a little and gives a hitmarker (once per grenade and player).
func _direct_hit(target: Player) -> void:
	if not target.alive or target.participant_id == thrower_id or linear_velocity.length() < DIRECT_HIT_MIN_SPEED:
		return
	if MatchManager.mode.uses_teams and thrower_team != Teams.Team.NONE and target.team == thrower_team:
		return
	if _hit_bodies.has(target.get_instance_id()):
		return
	_hit_bodies[target.get_instance_id()] = true
	var killed := target.take_damage(DIRECT_HIT_DAMAGE, thrower_id, "flashbang" if kind == KIND_FLASH else "grenade", target.get_center(), false, global_position)
	var thrower := MatchManager.get_participant(thrower_id)
	if thrower != null and thrower.node != null and is_instance_valid(thrower.node):
		(thrower.node as Player).hit_flag |= HitFeedback.BODY | (HitFeedback.KILL if killed else 0)
	if thrower_id == MatchManager.local_participant_id:
		GameEvents.local_player_hit_enemy.emit(false, killed)
	elif thrower != null and not thrower.is_bot and NetworkManager.is_host():
		NetworkManager.send_hit_feedback(thrower_id, false, killed)


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	if kind == KIND_FLASH:
		var spot := global_position + Vector3(0.0, 0.1, 0.0)
		spawn_flash_fx(get_tree(), spot, thrower_id)
		if not visual_only and MatchManager.is_authority():
			NetworkManager.broadcast_grenade_explosion(net_id, spot, kind)
		queue_free()
		return
	var center := global_position + Vector3(0.0, 0.25, 0.0)
	spawn_explosion_fx(get_tree(), center)
	if not visual_only and MatchManager.is_authority():
		NetworkManager.broadcast_grenade_explosion(net_id, center, kind)
		_apply_damage(center)
	queue_free()


## Client: the server detonated this grenade at `center`.
func explode_visual_at(center: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	if kind == KIND_FLASH:
		spawn_flash_fx(get_tree(), center, thrower_id)
	else:
		spawn_explosion_fx(get_tree(), center)
	queue_free()


## Flashbang burst: a white ball of light, sparks, the bang; tells everyone (the local player's blinding, bots).
static func spawn_flash_fx(tree: SceneTree, center: Vector3, thrower: int) -> void:
	var parent := tree.get_first_node_in_group("effects_container")
	if parent == null:
		parent = tree.current_scene
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = center
	var light := OmniLight3D.new()
	light.light_energy = 18.0
	light.omni_range = 18.0
	light.light_color = Color(1.0, 0.97, 0.9)
	root.add_child(light)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	sphere.material = glow
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var sparks := CPUParticles3D.new()
	sparks.amount = 32
	sparks.lifetime = 0.45
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 10.0
	sparks.gravity = Vector3(0.0, -9.0, 0.0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.03, 0.03, 0.12)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.96, 0.82)
	spark_mesh.material = spark_mat
	sparks.mesh = spark_mesh
	root.add_child(sparks)
	sparks.emitting = true
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball, "scale", Vector3.ONE * 3.2, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(glow, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_interval(0.3)
	tw.chain().tween_callback(root.queue_free)
	AudioManager.play_3d("flashbang_bang", center, 4.0, 0.02, 160.0)
	GameEvents.flashbang_exploded.emit(center, thrower)


static func spawn_explosion_fx(tree: SceneTree, center: Vector3) -> void:
	var fx := EXPLOSION_SCENE.instantiate()
	var parent := tree.get_first_node_in_group("effects_container")
	if parent == null:
		parent = tree.current_scene
	parent.add_child(fx)
	fx.global_position = center
	if fx.has_method("play"):
		fx.play()
	GameEvents.explosion_at.emit(center, RADIUS)


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
