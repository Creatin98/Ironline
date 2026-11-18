class_name HumanoidRig
extends Node3D
## Procedural low-poly humanoid (two legs, two arms, torso, head) for every player seen in third
## person. Built from boxes, animated in code: walk/run cycle, crouch, slide, jump pose, sprint lean.
## The arms are solved with two-bone IK towards the hands of the held weapon model, so they follow
## every weapon pose (aiming, reloading). Each part has a slightly larger "outline" copy (red for
## enemies, blue for teammates) that is depth tested like everything else: never visible through walls.
##
## Origin = feet, facing -Z. Total height about 1.78 m.

const HIP_H := 0.92
const THIGH := 0.44
const SHIN := 0.42
const UPPER_ARM := 0.29
const FORE_ARM := 0.27
const OUTLINE_GROW := 0.024
const OUTLINE_SHADER := "shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0, 0.2, 0.15, 0.6);
uniform float energy = 2.2;
void fragment() {
	ALBEDO = col.rgb * energy;
	ALPHA = col.a;
}"

static var _outline_shader: Shader
static var _cloth_cache: Dictionary = {}

var skin_color: Color = Color(0.9, 0.74, 0.6)
var _pelvis: Node3D
var _spine: Node3D
var _head: Node3D
var _thigh: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _arm_up: Array[Node3D] = []
var _arm_low: Array[Node3D] = []
var _outlines: Array[MeshInstance3D] = []
var _parts: Array[MeshInstance3D] = []
var _outline_mat: ShaderMaterial
var _outline_color: Color = Color(-1, 0, 0)

var _phase: float = 0.0
var _time: float = 0.0
var _crouch: float = 0.0
var _slide: float = 0.0
var _air: float = 0.0
var _sprint: float = 0.0
var _speed: float = 0.0
var _gait: float = 0.0
## Inputs set by the Player every frame (all known on every machine from snapshots/events).
var aiming: bool = false
## Throw progress 0..1 of a grenade (the pulled grenade is held at its cocked point), -1 = not throwing.
var throw_progress: float = -1.0
var _aim: float = 0.0
var _air_time: float = 0.0
var _was_air: float = 0.0
var _land: float = 0.0 # landing squash 1 -> 0
var _strafe: float = 0.0 # yaw of the legs towards the direction of movement
var _spine_lean: float = 0.0
var _hit: Vector3 = Vector3.ZERO # torso reaction: pitch, roll, yaw
var _head_snap: Vector3 = Vector3.ZERO # head reaction: pitch, roll
var _kick: float = 0.0 # recoil of the last shot
var _switch: float = 0.0 # weapon change dip 1 -> 0
var _throw_w: float = 0.0
var _nade: MeshInstance3D


func _ready() -> void:
	_build()


func get_skin_color() -> Color:
	return skin_color


func get_shirt_color() -> Color:
	return _shirt_color


## Look of this person: skin tone (beige, lighter to darker), hair and neutral clothes, derived from the id.
func setup_look(seed_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_id) + 7919
	skin_color = Color(0.96, 0.81, 0.67).lerp(Color(0.58, 0.40, 0.29), rng.randf())
	var hairs: Array[Color] = [Color(0.07, 0.06, 0.05), Color(0.2, 0.13, 0.08), Color(0.34, 0.21, 0.11), Color(0.74, 0.58, 0.3), Color(0.45, 0.45, 0.46)]
	var shirts: Array[Color] = [Color(0.36, 0.42, 0.29), Color(0.3, 0.36, 0.45), Color(0.5, 0.44, 0.33), Color(0.36, 0.37, 0.4), Color(0.45, 0.3, 0.26)]
	var pants: Array[Color] = [Color(0.2, 0.24, 0.32), Color(0.34, 0.32, 0.25), Color(0.19, 0.19, 0.21), Color(0.26, 0.3, 0.22)]
	_apply_colors(hairs[rng.randi() % hairs.size()], shirts[rng.randi() % shirts.size()], pants[rng.randi() % pants.size()])


var _hair_color := Color(0.2, 0.13, 0.08)
var _shirt_color := Color(0.21, 0.25, 0.19)
var _pants_color := Color(0.13, 0.15, 0.2)
var _mats: Dictionary = {}


func _apply_colors(hair: Color, shirt: Color, pants: Color) -> void:
	_hair_color = hair
	_shirt_color = shirt
	_pants_color = pants
	for key in _mats:
		var m: StandardMaterial3D = _mats[key]
		match key:
			"skin": m.albedo_color = skin_color
			"hair": m.albedo_color = hair
			"shirt": m.albedo_color = shirt
			"pants": m.albedo_color = pants


func _material(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


func _box(parent: Node3D, size: Vector3, center: Vector3, mat: StandardMaterial3D, outline: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = center
	mi.material_override = mat
	parent.add_child(mi)
	_parts.append(mi)
	if outline:
		var ol := MeshInstance3D.new()
		var om := BoxMesh.new()
		om.size = size + Vector3.ONE * OUTLINE_GROW
		ol.mesh = om
		ol.material_override = _outline_mat
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ol.visible = false
		mi.add_child(ol)
		_outlines.append(ol)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = _outline_shader
	var skin := _material("skin", skin_color)
	var hair := _material("hair", _hair_color)
	var shirt := _material("shirt", _shirt_color)
	var pants := _material("pants", _pants_color)
	var boots := _material("boots", Color(0.07, 0.07, 0.08))
	var eye := _material("eye", Color(0.04, 0.04, 0.05))

	_pelvis = _pivot(self, Vector3(0, HIP_H, 0))
	_box(_pelvis, Vector3(0.36, 0.2, 0.22), Vector3(0, 0.0, 0), pants)
	_spine = _pivot(_pelvis, Vector3.ZERO)
	_box(_spine, Vector3(0.40, 0.52, 0.24), Vector3(0, 0.27, 0), shirt)
	_head = _pivot(_spine, Vector3(0, 0.55, 0))
	_box(_head, Vector3(0.10, 0.08, 0.10), Vector3(0, 0.0, 0), skin, false) # neck
	_box(_head, Vector3(0.23, 0.24, 0.23), Vector3(0, 0.14, 0), skin)
	_box(_head, Vector3(0.25, 0.07, 0.25), Vector3(0, 0.27, 0.005), hair)
	_box(_head, Vector3(0.25, 0.14, 0.05), Vector3(0, 0.2, 0.1), hair, false) # hair at the back
	_box(_head, Vector3(0.045, 0.03, 0.02), Vector3(-0.055, 0.16, -0.118), eye, false)
	_box(_head, Vector3(0.045, 0.03, 0.02), Vector3(0.055, 0.16, -0.118), eye, false)
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		# legs: thigh -> knee -> shin, boot
		var hip := _pivot(_pelvis, Vector3(sx * 0.1, -0.02, 0))
		_box(hip, Vector3(0.16, THIGH, 0.17), Vector3(0, -THIGH * 0.5, 0), pants)
		var knee := _pivot(hip, Vector3(0, -THIGH, 0))
		_box(knee, Vector3(0.135, SHIN, 0.145), Vector3(0, -SHIN * 0.5, 0), pants)
		_box(knee, Vector3(0.145, 0.09, 0.27), Vector3(0, -SHIN - 0.0, -0.05), boots)
		_thigh.append(hip)
		_knee.append(knee)
		# arms: bones are pivots in rig space (solved by IK), meshes extend along -Z
		var up := _pivot(self, Vector3.ZERO)
		_box(up, Vector3(0.115, 0.115, UPPER_ARM), Vector3(0, 0, -UPPER_ARM * 0.5), shirt)
		var low := _pivot(self, Vector3.ZERO)
		_box(low, Vector3(0.098, 0.098, FORE_ARM), Vector3(0, 0, -FORE_ARM * 0.5), skin)
		_arm_up.append(up)
		_arm_low.append(low)
	# the grenade in the throwing hand (visible during a throw until it is released)
	_nade = MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.07, 0.09, 0.07)
	_nade.mesh = nm
	_nade.material_override = _material("grenade", Color(0.2, 0.26, 0.15))
	_nade.position = Vector3(0, 0, -FORE_ARM - 0.02)
	_nade.visible = false
	_arm_low[0].add_child(_nade)
	set_outline_visible(false)


## Body segments for the ragdoll: pivot node (its origin = the joint), parent segment, collision box, mass and joint limits
## (x = flexion range in radians, y/z = swing either way).
func ragdoll_segments() -> Array:
	var seg: Array = []
	seg.append({"node": _pelvis, "parent": -1, "size": Vector3(0.36, 0.2, 0.22), "center": Vector3.ZERO, "mass": 9.0})
	seg.append({"node": _spine, "parent": 0, "size": Vector3(0.40, 0.52, 0.24), "center": Vector3(0, 0.27, 0), "mass": 20.0, "x": Vector2(-0.7, 0.6), "yz": Vector2(0.5, 0.5)})
	seg.append({"node": _head, "parent": 1, "size": Vector3(0.23, 0.26, 0.23), "center": Vector3(0, 0.15, 0), "mass": 5.0, "x": Vector2(-0.9, 0.9), "yz": Vector2(0.9, 0.6)})
	for i in 2:
		var thigh_idx := seg.size()
		seg.append({"node": _thigh[i], "parent": 0, "size": Vector3(0.16, THIGH, 0.17), "center": Vector3(0, -THIGH * 0.5, 0), "mass": 8.0, "x": Vector2(-1.4, 0.9), "yz": Vector2(0.5, 0.6)})
		seg.append({"node": _knee[i], "parent": thigh_idx, "size": Vector3(0.14, SHIN, 0.15), "center": Vector3(0, -SHIN * 0.5, 0), "mass": 5.0, "x": Vector2(-2.3, 0.0), "yz": Vector2(0.05, 0.05)})
		var up_idx := seg.size()
		seg.append({"node": _arm_up[i], "parent": 1, "size": Vector3(0.115, 0.115, UPPER_ARM), "center": Vector3(0, 0, -UPPER_ARM * 0.5), "mass": 3.0, "x": Vector2(-1.7, 1.7), "yz": Vector2(1.2, 1.2)})
		seg.append({"node": _arm_low[i], "parent": up_idx, "size": Vector3(0.1, 0.1, FORE_ARM), "center": Vector3(0, 0, -FORE_ARM * 0.5), "mass": 2.0, "x": Vector2(-2.2, 0.1), "yz": Vector2(0.15, 0.15)})
	return seg


# ----------------------------------------------------------------------------- appearance

## Outline colour (red = enemy, blue = teammate); the glow comes from the shader's energy.
func set_outline_color(c: Color) -> void:
	if c == _outline_color:
		return
	_outline_color = c
	_outline_mat.set_shader_parameter("col", Color(c.r, c.g, c.b, 0.5))


func set_outline_visible(v: bool) -> void:
	for o in _outlines:
		o.visible = v


## Own body: only its shadow is drawn (the camera sits inside the head).
func set_shadow_only(shadow_only: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for p in _parts:
		p.cast_shadow = mode


# ----------------------------------------------------------------------------- animation

## Where the weapon (hands node) sits: in front of the chest, follows lean and crouch.
func weapon_anchor() -> Vector3:
	var dip := sin(_switch * PI)
	var off := Vector3(0.13, 0.31, -0.30)
	off += Vector3(-0.09, 0.09, -0.06) * _aim # shouldered, close to the face
	off += Vector3(0.04, -0.17, 0.07) * _sprint # lowered, across the body
	off += Vector3(0.0, -0.26, 0.06) * dip # weapon change: down and up again
	off += Vector3(0.0, 0.012, 0.035) * _kick # recoil
	return _pelvis.transform * (_spine.transform * off) + position


## Extra rotation of the weapon (added to the pitch): sprint carry, weapon change, recoil.
func weapon_tilt() -> Vector3:
	var dip := sin(_switch * PI)
	return Vector3(-0.38 * _sprint + 0.55 * dip - 0.07 * _kick, 0.55 * _sprint, 0.22 * _sprint - 0.3 * dip)


# --- reactions (events, also from the network)

## A hit: torso and head react. `from_local` = direction the shot came from (rig space, horizontal), strength ~0.5..1.5.
func hit_react(from_local: Vector3, headshot: bool, strength: float = 1.0) -> void:
	var d := Vector3(from_local.x, 0.0, from_local.z).normalized()
	_hit += Vector3(-d.z * 0.22, d.x * 0.18, d.x * 0.12) * strength * (1.7 if headshot else 1.0)
	_hit = _hit.clamp(Vector3(-0.6, -0.5, -0.4), Vector3(0.6, 0.5, 0.4))
	if headshot:
		_head_snap = Vector3(-d.z * 0.95 + 0.2, d.x * 0.5, 0.0)
	else:
		_head_snap += Vector3(-d.z * 0.3, d.x * 0.15, 0.0) * strength


func shot_kick() -> void:
	_kick = 1.0


func switch_pulse() -> void:
	_switch = 1.0


## `vel_local`: velocity in the player's own frame (x right, -z forward). Hand targets are in rig space
## (or Vector3.INF for "no weapon": the arm hangs down).
func animate(delta: float, vel_local: Vector3, on_floor: bool, crouching: bool, sliding: bool, sprinting: bool, pitch: float, right_target: Vector3, left_target: Vector3) -> void:
	_time += delta
	var speed := Vector2(vel_local.x, vel_local.z).length()
	var k := minf(1.0, delta * 10.0)
	_speed = lerpf(_speed, speed, k)
	_crouch = lerpf(_crouch, 1.0 if crouching and not sliding else 0.0, minf(1.0, delta * 9.0))
	_slide = lerpf(_slide, 1.0 if sliding else 0.0, minf(1.0, delta * 9.0))
	_air = lerpf(_air, 1.0 if (not on_floor and not sliding) else 0.0, minf(1.0, delta * 12.0))
	_sprint = lerpf(_sprint, 1.0 if sprinting else 0.0, minf(1.0, delta * 8.0))
	_aim = lerpf(_aim, 1.0 if (aiming and not sprinting) else 0.0, minf(1.0, delta * 12.0))
	_kick = move_toward(_kick, 0.0, delta * 9.0)
	_switch = move_toward(_switch, 0.0, delta * 2.3)
	_hit = _hit.lerp(Vector3.ZERO, minf(1.0, delta * 7.0))
	_head_snap = _head_snap.lerp(Vector3.ZERO, minf(1.0, delta * 6.0))
	# landing: remember how long we were in the air
	if on_floor:
		if _was_air > 0.5 and _air_time > 0.12:
			_land = clampf(0.4 + _air_time * 0.5, 0.4, 1.0)
		_air_time = 0.0
	else:
		_air_time += delta
	_was_air = _air
	_land = move_toward(_land, 0.0, delta * 3.4)
	var dir := -1.0 if vel_local.z > 0.6 else 1.0 # walking backwards runs the cycle in reverse
	_phase += delta * speed * 2.6 * dir
	var moving := clampf(_speed / 1.2, 0.0, 1.0)
	var spd := clampf(_speed / 7.7, 0.0, 1.0)
	var amp := lerpf(0.4, 0.9, spd) * moving
	var flex := lerpf(0.55, 1.15, spd) * moving
	var s := sin(_phase)
	var c := cos(_phase)

	# legs step in the direction of movement (strafing, backwards-diagonal)
	var strafe_target := -clampf(atan2(vel_local.x, absf(vel_local.z)), -1.1, 1.1) * moving * (1.0 - _slide) * (1.0 - _air)
	_strafe = lerpf(_strafe, strafe_target, minf(1.0, delta * 9.0))
	# per leg: stand/gait -> crouch -> slide -> air
	var thigh := [amp * s, -amp * s]
	var knee := [-(0.1 + flex * maxf(0.0, c)), -(0.1 + flex * maxf(0.0, -c))]
	var crouch_thigh := [1.15 + 0.25 * amp * s, 1.15 - 0.25 * amp * s]
	var crouch_knee := [-1.15, -1.15]
	var slide_thigh := [1.5, 0.25]
	var slide_knee := [-0.1, -2.0]
	var air_thigh := [0.95, 0.25]
	var air_knee := [-1.25, -0.55]
	for i in 2:
		var th: float = thigh[i]
		var kn: float = knee[i]
		th = lerpf(th, crouch_thigh[i], _crouch)
		kn = lerpf(kn, crouch_knee[i], _crouch)
		th = lerpf(th, slide_thigh[i], _slide)
		kn = lerpf(kn, slide_knee[i], _slide)
		th = lerpf(th, air_thigh[i], _air)
		kn = lerpf(kn, air_knee[i], _air)
		th += 0.6 * _land * (1.0 - _slide) # landing: knees give way
		kn -= 0.9 * _land * (1.0 - _slide)
		_thigh[i].rotation.y = _strafe * 0.85
		_thigh[i].rotation.x = th
		_knee[i].rotation.x = kn
	# pelvis height and lean
	var bob := absf(s) * 0.035 * moving * (1.0 - _crouch) * (1.0 - _slide)
	var h := lerpf(HIP_H - bob, 0.66, _crouch)
	h = lerpf(h, 0.34, _slide)
	h = lerpf(h, HIP_H + 0.04, _air)
	h -= 0.13 * _land
	_pelvis.position.y = h
	position.z = 0.18 * _crouch + 0.38 * _slide
	var lean := -0.05 * moving - 0.30 * _sprint - 0.42 * _crouch + 0.5 * _slide - 0.1 * _air + 0.22 * _land
	lean += 0.05 * _aim # leaning into the sights
	_spine_lean = lerpf(_spine_lean, lean, minf(1.0, delta * 8.0))
	# throwing: the torso winds up and swings
	var twist := 0.0
	if throw_progress >= 0.0:
		var wind := smoothstep(0.35, 0.58, throw_progress) - smoothstep(0.62, 0.78, throw_progress)
		twist = -0.55 * wind
	_spine.rotation.x = _spine_lean + _hit.x + 0.06 * _kick
	_spine.rotation.z = sin(_time * 1.7) * 0.012 + (-vel_local.x * 0.012) + _hit.y
	_spine.rotation.y = _hit.z + twist
	_head.rotation.x = clampf(pitch, -1.2, 1.2) * 0.75 - _spine.rotation.x * 0.7 + _head_snap.x
	_head.rotation.z = _head_snap.y

	_throw_w = lerpf(_throw_w, 1.0 if throw_progress >= 0.0 else 0.0, minf(1.0, delta * 14.0))
	if _throw_w > 0.01:
		var p := maxf(throw_progress, 0.0)
		var rs := _shoulder(0)
		var ls := _shoulder(1)
		right_target = _blend_target(right_target, rs + _throw_hand(p), _throw_w)
		left_target = _blend_target(left_target, ls + _throw_left(p), _throw_w)
	_nade.visible = _throw_w > 0.5 and throw_progress >= 0.0 and throw_progress < 0.62
	_solve_arm(0, right_target, Vector3(0.45, -1.0, 0.25))
	_solve_arm(1, left_target, Vector3(-0.45, -1.0, 0.25))


func _shoulder(side: int) -> Vector3:
	var sx := 1.0 if side == 0 else -1.0
	return _pelvis.transform * (_spine.transform * Vector3(sx * 0.255, 0.47, 0.0))


## `INF` (no weapon) blends from the hanging arm.
func _blend_target(from: Vector3, to: Vector3, w: float) -> Vector3:
	if from == Vector3.INF:
		return to
	return from.lerp(to, w)


## Right (throwing) hand relative to the shoulder: grenade at the chest, wound back high, thrown forward, hanging.
func _throw_hand(p: float) -> Vector3:
	return _key3([[0.0, Vector3(0.0, -0.30, -0.28)], [0.3, Vector3(0.02, -0.14, -0.32)], [0.55, Vector3(0.06, 0.20, 0.30)], [0.62, Vector3(0.06, 0.22, 0.32)], [0.72, Vector3(-0.05, -0.02, -0.60)], [0.86, Vector3(-0.02, -0.34, -0.40)], [1.0, Vector3(0.0, -0.52, -0.06)]], p)


## Left hand pulls the pin at the grenade, then drops.
func _throw_left(p: float) -> Vector3:
	return _key3([[0.0, Vector3(0.0, -0.30, -0.30)], [0.2, Vector3(-0.04, -0.16, -0.30)], [0.4, Vector3(-0.30, -0.22, -0.34)], [0.56, Vector3(-0.22, -0.38, -0.20)], [1.0, Vector3(-0.10, -0.52, -0.06)]], p)


static func _key3(keys: Array, t: float) -> Vector3:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		if t <= t1:
			var t0: float = keys[i - 1][0]
			var u := clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return (keys[i - 1][1] as Vector3).lerp(keys[i][1], u)
	return keys[keys.size() - 1][1]


## Two-bone IK: shoulder -> elbow -> hand target (rig space). Bone 0 = right, 1 = left.
func _solve_arm(side: int, target: Vector3, pole: Vector3) -> void:
	var sx := 1.0 if side == 0 else -1.0
	var shoulder: Vector3 = _pelvis.transform * (_spine.transform * Vector3(sx * 0.255, 0.47, 0.0))
	var t := target
	if t == Vector3.INF:
		t = shoulder + Vector3(sx * 0.1, -(UPPER_ARM + FORE_ARM) * 0.92, -0.05) # hanging arm
	var to_t := t - shoulder
	var d := clampf(to_t.length(), 0.08, UPPER_ARM + FORE_ARM - 0.002)
	var fwd := to_t.normalized()
	var a := (UPPER_ARM * UPPER_ARM - FORE_ARM * FORE_ARM + d * d) / (2.0 * d)
	var hgt := sqrt(maxf(0.0, UPPER_ARM * UPPER_ARM - a * a))
	var side_dir := pole - fwd * pole.dot(fwd)
	if side_dir.length() < 0.001:
		side_dir = Vector3.DOWN
	side_dir = side_dir.normalized()
	var elbow := shoulder + fwd * a + side_dir * hgt
	var hand := shoulder + fwd * d
	_arm_up[side].transform = Transform3D(_look(elbow - shoulder), shoulder)
	_arm_low[side].transform = Transform3D(_look(hand - elbow), elbow)


static func _look(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(d, up)
