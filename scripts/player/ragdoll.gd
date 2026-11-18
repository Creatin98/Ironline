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
var _sev: Array[int] = [] # segment indices that are torn off (head 2, thighs 3/7, shins 4/8, upper arms 5/9, forearms 6/10)
var _centers: Dictionary = {}
var _pool_done: bool = false
var _chunk_n: int = 0
var _events: Array = [] # delayed effects, run from _physics_process (no lambdas that could outlive this node)


## All corpses go away (a killcam replays the past: no bodies of the present may lie around).
static func clear_all() -> void:
	for r in _alive:
		if is_instance_valid(r):
			(r as Ragdoll).queue_free()
	_alive.clear()


## `push`: horizontal direction away from the killer; `strength` ~0.6 (pistol) .. 2 (explosion).
static func spawn(rig: HumanoidRig, parent: Node, velocity: Vector3, push: Vector3, strength: float, headshot: bool, severed: Array = []) -> Ragdoll:
	_alive = _alive.filter(func(r: Variant) -> bool: return is_instance_valid(r))
	while _alive.size() >= MAX_ALIVE:
		(_alive.pop_front() as Ragdoll).queue_free()
	var rd := Ragdoll.new()
	parent.add_child(rd)
	rd.global_transform = Transform3D.IDENTITY
	rd._build(rig, velocity, push, strength, headshot, severed)
	_alive.append(rd)
	return rd


func _build(rig: HumanoidRig, velocity: Vector3, push: Vector3, strength: float, headshot: bool, severed: Array) -> void:
	var segs := rig.ragdoll_segments()
	_sev.clear()
	for idx in severed:
		if int(idx) > 1 and int(idx) < segs.size() and not _sev.has(int(idx)):
			_sev.append(int(idx))
	if headshot and not _sev.has(2):
		_sev.append(2)
	for i in segs.size():
		_centers[i] = segs[i]["center"]
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
		if pi < 0 or _sev.has(i):
			continue # torn-off parts have no joint any more
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
	for idx in _sev:
		_sever(idx, segs[idx]["parent"])


## A part is torn off: raw stump (with a bit of bone) on the body, a red cut surface on the part, blood that keeps
## pumping out of the stump in weakening spurts - also while the body already lies on the floor.
func _sever(idx: int, parent_idx: int) -> void:
	var a := _bodies[parent_idx]
	var b := _bodies[idx]
	var at := a.to_local(b.global_position)
	var flesh := StandardMaterial3D.new()
	flesh.albedo_color = Color(0.3, 0.012, 0.012)
	flesh.roughness = 0.3
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.82, 0.78, 0.7)
	var sz := 0.11 if idx != 2 else 0.1
	for pair in [[a, at], [b, Vector3.ZERO]]:
		var host: Node3D = pair[0]
		var stump := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sz, sz * 0.7, sz)
		stump.mesh = bm
		stump.material_override = flesh
		stump.position = pair[1]
		host.add_child(stump)
		_visuals.append(stump)
		var bn := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(0.035, 0.05, 0.035)
		bn.mesh = bbm
		bn.material_override = bone
		bn.position = pair[1] + Vector3(randf_range(-0.02, 0.02), 0.03, randf_range(-0.02, 0.02))
		host.add_child(bn)
		_visuals.append(bn)
		if idx == 2 and host == b:
			_head_visuals.append(stump)
			_head_visuals.append(bn)
	var dir := Vector3.UP
	if idx != 2:
		dir = (a.to_local(b.global_transform * (_centers[idx] as Vector3)) - at).normalized()
	_emit_blood(a, at, 1.2, 60)
	_spurts(a, at, dir)
	if idx == 2:
		_emit_blood(b, Vector3(0, 0.03, 0), 0.8, 36)
	_chunk_n += 3 if _strength >= 1.7 else 1
	BloodFx.burst(get_parent(), b.global_position, dir, 1.6)


func _later(delay: float, kind: String, node: Node, args: Dictionary = {}) -> void:
	_events.append({"t": _age + delay, "kind": kind, "node": node, "args": args})


func _run_events() -> void:
	var i := 0
	while i < _events.size():
		var e: Dictionary = _events[i]
		if _age < float(e["t"]):
			i += 1
			continue
		_events.remove_at(i)
		var n: Node = e["node"]
		if not is_instance_valid(n):
			continue
		match String(e["kind"]):
			"free":
				n.queue_free()
			"stop":
				(n as CPUParticles3D).emitting = false
			"pulse":
				var a: Dictionary = e["args"]
				_pulse(n as Node3D, a["at"], a["dir"], int(a["amount"]))


## Blood pumps out in spurts with the heartbeat: strong at first, weaker and weaker, over several seconds.
func _spurts(body: Node3D, at: Vector3, dir: Vector3) -> void:
	for k in 9:
		var t := 0.35 + float(k) * 0.42
		var amount := maxi(5, int(30.0 * (1.0 - float(k) / 9.0)))
		_later(t, "pulse", body, {"at": at, "dir": dir, "amount": amount})


func _pulse(body: Node3D, at: Vector3, dir: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	mesh.radial_segments = 5
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.015, 0.015)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(4, int(float(amount) * GameSettings.effects_scale()))
	p.lifetime = 0.55
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0.0, -10.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	body.add_child(p)
	p.position = at
	p.emitting = true
	_later(1.0, "free", p)


## Small flesh chunks flying off.
func _spawn_chunks(origin: Vector3, dir: Vector3, n: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.03, 0.025)
	mat.roughness = 0.4
	for i in mini(n, 14):
		var c := RigidBody3D.new()
		c.collision_layer = LAYER
		c.collision_mask = 1
		c.mass = 0.4
		c.linear_damp = 0.3
		c.angular_damp = 0.6
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz := randf_range(0.05, 0.12)
		bs.size = Vector3(sz, sz * randf_range(0.6, 1.0), sz * randf_range(0.7, 1.2))
		cs.shape = bs
		c.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		mi.mesh = bm
		mi.material_override = mat
		c.add_child(mi)
		add_child(c)
		c.global_position = origin + Vector3(randf_range(-0.15, 0.15), randf_range(0.0, 0.3), randf_range(-0.15, 0.15))
		c.linear_velocity = dir * randf_range(2.0, 6.0) + Vector3(randf_range(-2.5, 2.5), randf_range(1.5, 5.0), randf_range(-2.5, 2.5))
		c.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		_later(5.5 + randf() * 1.5, "free", c)


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
	_later(seconds, "stop", p)


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
	for idx in _sev:
		if idx == 2:
			continue
		var limb := _bodies[idx]
		limb.apply_central_impulse((dir * randf_range(2.5, 5.5) * maxf(strength, 1.0) + Vector3.UP * randf_range(1.0, 3.0) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))) * limb.mass)
		limb.angular_velocity = Vector3(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0), randf_range(-10.0, 10.0))
	if _chunk_n > 0:
		_spawn_chunks(torso.global_position + Vector3(0, 0.3, 0), dir, _chunk_n)
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
	_run_events()
	if not _pushed and _age > 0.04: # a couple of physics steps in: the masses are known now
		_pushed = true
		_apply_push()
	if not _pool_done and not _sev.is_empty() and _age >= 1.1:
		_pool_done = true
		BloodFx.pool(get_parent(), _bodies[0].global_position, 1.0 + 0.35 * _sev.size())
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
