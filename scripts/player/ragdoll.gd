class_name Ragdoll
extends Node3D
## Physical corpse: when a player dies the humanoid rig is replaced - in exactly the same pose, so nothing jumps - by a
## chain of rigid bodies (pelvis, torso, head, thighs, shins, upper arms, forearms) held together by limited joints.
## It keeps the movement of the body, gets a push away from the shooter (stronger for heavy weapons) and a snapping
## head on headshots, then falls under gravity. Purely visual and local on every machine (no network traffic): bodies
## collide with the world only (layer 5), never with players, bullets or grenades.

const LAYER := 16 # physics layer 5
const MAX_ALIVE := 8
const FREEZE_AFTER := 4.0 # the bodies are frozen then (no more cost)
const LIFETIME := 9.0
const FADE := 1.0
const HEAD_LIFETIME := 5.5 # a severed head lies around a little shorter than the body, then shrinks away

static var _alive: Array = []

var _bodies: Array[RigidBody3D] = []
var _visuals: Array[MeshInstance3D] = []
var _head_visuals: Array[MeshInstance3D] = []
var _age: float = 0.0
var _frozen: bool = false
var _push: Vector3 = Vector3.ZERO
var _strength: float = 1.0
var _headshot: bool = false
var _pushed: bool = false


## `push`: horizontal direction away from the killer; `strength` ~0.6 (pistol) .. 2 (explosion).
static func spawn(rig: HumanoidRig, parent: Node, velocity: Vector3, push: Vector3, strength: float, headshot: bool) -> Ragdoll:
	_alive = _alive.filter(func(r: Variant) -> bool: return is_instance_valid(r))
	while _alive.size() >= MAX_ALIVE:
		(_alive.pop_front() as Ragdoll).queue_free()
	var rd := Ragdoll.new()
	parent.add_child(rd)
	rd.global_transform = Transform3D.IDENTITY
	rd._build(rig, velocity, push, strength, headshot)
	_alive.append(rd)
	return rd


func _build(rig: HumanoidRig, velocity: Vector3, push: Vector3, strength: float, headshot: bool) -> void:
	var segs := rig.ragdoll_segments()
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.05
	var seg_i := -1
	for seg in segs:
		seg_i += 1
		var node: Node3D = seg["node"]
		var body := RigidBody3D.new()
		body.mass = float(seg["mass"])
		body.collision_layer = LAYER
		body.collision_mask = 1
		body.linear_damp = 0.35
		body.angular_damp = 2.2
		body.physics_material_override = phys
		if headshot and seg_i == 2: # severed head: rolls and bounces
			var hp := PhysicsMaterial.new()
			hp.friction = 0.55
			hp.bounce = 0.3
			body.physics_material_override = hp
			body.angular_damp = 0.7
			body.linear_damp = 0.15
		body.can_sleep = true
		add_child(body)
		body.global_transform = node.global_transform
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (seg["size"] as Vector3) * 0.9
		shape.shape = box
		shape.position = seg["center"]
		body.add_child(shape)
		# the visible boxes of this segment (same meshes and materials as the living body)
		for c in node.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.material_override = mi.material_override
			copy.transform = mi.transform
			body.add_child(copy)
			_visuals.append(copy)
			if headshot and seg_i == 2:
				_head_visuals.append(copy)
		body.linear_velocity = velocity
		_bodies.append(body)
	# joints with limits: knees and elbows bend one way only
	for i in segs.size():
		var seg: Dictionary = segs[i]
		var pi: int = seg["parent"]
		if pi < 0 or (headshot and i == 2):
			continue # a severed head has no joint any more
		var a := _bodies[pi]
		var b := _bodies[i]
		var joint := Generic6DOFJoint3D.new()
		add_child(joint)
		joint.global_transform = Transform3D(a.global_transform.basis, b.global_position)
		joint.node_a = joint.get_path_to(a)
		joint.node_b = joint.get_path_to(b)
		var cur := (a.global_transform.basis.inverse() * b.global_transform.basis).get_euler()
		var xr: Vector2 = seg.get("x", Vector2.ZERO)
		var yz: Vector2 = seg.get("yz", Vector2.ZERO)
		_limit(joint, 0, minf(xr.x - cur.x, 0.0), maxf(xr.y - cur.x, 0.0))
		_limit(joint, 1, -yz.x, yz.x)
		_limit(joint, 2, -yz.y, yz.y)
	_push = push
	_strength = strength
	_headshot = headshot
	if headshot:
		_sever_head()


## Headshot kill: a raw neck stump on the torso and fountains of blood from the neck and the flying head.
func _sever_head() -> void:
	var torso := _bodies[1]
	var stump := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.07, 0.11)
	stump.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.015, 0.015)
	m.roughness = 0.35
	stump.material_override = m
	stump.position = Vector3(0, 0.55, 0)
	torso.add_child(stump)
	_visuals.append(stump)
	_emit_blood(torso, Vector3(0, 0.57, 0), 1.6, 70)
	_emit_blood(_bodies[2], Vector3(0, 0.03, 0), 0.8, 36)
	BloodFx.burst(get_parent(), torso.global_transform * Vector3(0, 0.57, 0), Vector3.UP, 1.8)


func _emit_blood(body: Node3D, at: Vector3, seconds: float, amount: int) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.02, 0.02)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.amount = maxi(8, int(float(amount) * GameSettings.effects_scale()))
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0.0, -11.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.7
	p.explosiveness = 0.0
	p.emitting = true
	body.add_child(p)
	p.position = at
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false)


## The push (after the first physics step: only then the bodies know their mass, an earlier impulse would act on 1 kg).
func _apply_push() -> void:
	var push := _push
	var strength := _strength
	var headshot := _headshot
	var dir := Vector3(push.x, 0.0, push.z).normalized()
	var torso := _bodies[1]
	torso.apply_central_impulse((dir * 3.6 * strength + Vector3.UP * 0.9) * torso.mass)
	_bodies[0].apply_central_impulse(dir * 1.4 * strength * _bodies[0].mass)
	if headshot:
		var head := _bodies[2]
		head.apply_central_impulse((dir * 5.5 + Vector3.UP * 1.8) * head.mass)
		head.angular_velocity = Vector3(randf_range(-9.0, 9.0), randf_range(-5.0, 5.0), randf_range(-9.0, 9.0))
		torso.apply_central_impulse(dir * 1.8 * torso.mass)
	if strength > 1.7: # explosion: thrown up
		torso.apply_central_impulse((Vector3.UP * 4.2 + dir * 2.0) * torso.mass)
		torso.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * torso.mass * 0.6)


func _limit(joint: Generic6DOFJoint3D, axis: int, lower: float, upper: float) -> void:
	var flag := Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT
	var lo := Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT
	var up := Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT
	match axis:
		0:
			joint.set_flag_x(flag, true)
			joint.set_param_x(lo, lower)
			joint.set_param_x(up, upper)
		1:
			joint.set_flag_y(flag, true)
			joint.set_param_y(lo, lower)
			joint.set_param_y(up, upper)
		_:
			joint.set_flag_z(flag, true)
			joint.set_param_z(lo, lower)
			joint.set_param_z(up, upper)


func _physics_process(delta: float) -> void:
	_age += delta
	if not _pushed and _age > 0.04: # a couple of physics steps in: the masses are known now
		_pushed = true
		_apply_push()
	if not _frozen and _age >= FREEZE_AFTER:
		_frozen = true
		for bi in _bodies.size():
			if not (_headshot and bi == 2): # the severed head keeps rolling a little longer
				_bodies[bi].freeze = true # lies where it fell, costs nothing any more
	if _headshot and _age >= HEAD_LIFETIME - FADE and _age < LIFETIME:
		var hk := clampf((HEAD_LIFETIME - _age) / FADE, 0.0, 1.0)
		for v in _head_visuals:
			v.scale = Vector3.ONE * maxf(hk, 0.01)
		if _age >= HEAD_LIFETIME - 0.3:
			_bodies[2].freeze = true
	if _age >= LIFETIME - FADE:
		var k := clampf((LIFETIME - _age) / FADE, 0.0, 1.0)
		for v in _visuals:
			v.scale = Vector3.ONE * maxf(k, 0.01)
	if _age >= LIFETIME:
		queue_free()
