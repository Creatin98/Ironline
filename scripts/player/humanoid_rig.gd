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


func _ready() -> void:
	_build()


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
	set_outline_visible(false)


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
	return _pelvis.transform * (_spine.transform * Vector3(0.13, 0.31, -0.30)) + position


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
	var dir := -1.0 if vel_local.z > 0.6 else 1.0 # walking backwards runs the cycle in reverse
	_phase += delta * speed * 2.6 * dir
	var moving := clampf(_speed / 1.2, 0.0, 1.0)
	var spd := clampf(_speed / 7.7, 0.0, 1.0)
	var amp := lerpf(0.4, 0.9, spd) * moving
	var flex := lerpf(0.55, 1.15, spd) * moving
	var s := sin(_phase)
	var c := cos(_phase)

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
		_thigh[i].rotation.x = th
		_knee[i].rotation.x = kn
	# pelvis height and lean
	var bob := absf(s) * 0.035 * moving * (1.0 - _crouch) * (1.0 - _slide)
	var h := lerpf(HIP_H - bob, 0.66, _crouch)
	h = lerpf(h, 0.34, _slide)
	h = lerpf(h, HIP_H + 0.04, _air)
	_pelvis.position.y = h
	position.z = 0.18 * _crouch + 0.38 * _slide
	var lean := -0.05 * moving - 0.30 * _sprint - 0.42 * _crouch + 0.5 * _slide - 0.1 * _air
	_spine.rotation.x = lerpf(_spine.rotation.x, lean, minf(1.0, delta * 8.0))
	_spine.rotation.z = sin(_time * 1.7) * 0.012 + (-vel_local.x * 0.012)
	_head.rotation.x = clampf(pitch, -1.2, 1.2) * 0.75 - _spine.rotation.x * 0.7

	_solve_arm(0, right_target, Vector3(0.45, -1.0, 0.25))
	_solve_arm(1, left_target, Vector3(-0.45, -1.0, 0.25))


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
