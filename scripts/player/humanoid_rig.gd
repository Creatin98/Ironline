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
const OUTLINE_SHADER := "shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0, 0.2, 0.15, 0.6);
uniform float energy = 2.2;
uniform float grow = 0.013;
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	ALBEDO = col.rgb * energy;
	ALPHA = col.a;
}"

static var _outline_shader: Shader

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

## Flashbang: 0..1, the left arm covers the face.
var flash_cover: float = 0.0
var lean: float = 0.0 # -1 left .. +1 right (corner lean)
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
			"pants_dark": m.albedo_color = pants * 0.8


const CLOTH_KEYS := ["shirt", "pants", "pants_dark", "vest", "helmet", "webbing"]
static var _cloth_tex: Texture2D
static var _cloth_nrm: Texture2D
static var _unit_box: BoxMesh
static var _unit_cyl: CylinderMesh

var _groups: Dictionary = {} # "<pivot id>:<material key>" -> {"pivot", "key", "st"}


func _material(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.92
		if key in CLOTH_KEYS:
			if _cloth_tex == null:
				_cloth_tex = load("res://assets/textures/cloth.png")
				_cloth_nrm = load("res://assets/textures/cloth_n.png")
			m.albedo_texture = _cloth_tex
			m.normal_enabled = true
			m.normal_texture = _cloth_nrm
			m.normal_scale = 0.5
			m.uv1_triplanar = true # object space: the weave sticks to the limbs while they move
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		match key:
			"skin":
				m.roughness = 0.62
				m.metallic_specular = 0.45
			"metal":
				m.metallic = 0.8
				m.roughness = 0.35
			"plate":
				m.metallic = 0.3
				m.roughness = 0.5
			"boots", "rubber":
				m.roughness = 0.62
			"lens":
				m.roughness = 0.12
				m.metallic = 0.4
		_mats[key] = m
	return _mats[key]


## Adds a box (or cylinder) to the merged mesh of (pivot, material). One draw call per pivot and material.
func _part(pivot: Node3D, size: Vector3, center: Vector3, key: String, rot_deg: Vector3 = Vector3.ZERO, cylinder: bool = false) -> void:
	var gk := "%d:%s" % [pivot.get_instance_id(), key]
	if not _groups.has(gk):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_groups[gk] = {"pivot": pivot, "key": key, "st": st}
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_cyl = CylinderMesh.new()
		_unit_cyl.top_radius = 0.5
		_unit_cyl.bottom_radius = 0.5
		_unit_cyl.height = 1.0
		_unit_cyl.radial_segments = 10
		_unit_cyl.rings = 1
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	var xf := Transform3D(basis.scaled_local(size), center)
	((_groups[gk]["st"]) as SurfaceTool).append_from(_unit_cyl if cylinder else _unit_box, 0, xf)


## Turns the collected parts into one MeshInstance3D per (pivot, material), each with an outline copy.
func _commit_parts() -> void:
	for gk in _groups:
		var g: Dictionary = _groups[gk]
		var mesh: ArrayMesh = (g["st"] as SurfaceTool).commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mats[g["key"]]
		(g["pivot"] as Node3D).add_child(mi)
		_parts.append(mi)
		if g["key"] == "eye" or g["key"] == "lens":
			continue
		var ol := MeshInstance3D.new()
		ol.mesh = _outline_mesh(mesh)
		ol.material_override = _outline_mat
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ol.visible = false
		mi.add_child(ol)
		_outlines.append(ol)
	_groups.clear()


## Copy of a mesh with smoothed normals (shared corners averaged), so the outline shader can push it outwards without cracks.
func _outline_mesh(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var sums: Dictionary = {}
	for i in verts.size():
		var k := Vector3i(roundi(verts[i].x * 1000.0), roundi(verts[i].y * 1000.0), roundi(verts[i].z * 1000.0))
		sums[k] = sums.get(k, Vector3.ZERO) + normals[i]
	var smooth := PackedVector3Array()
	smooth.resize(verts.size())
	for i in verts.size():
		var k := Vector3i(roundi(verts[i].x * 1000.0), roundi(verts[i].y * 1000.0), roundi(verts[i].z * 1000.0))
		smooth[i] = (sums[k] as Vector3).normalized()
	var out := ArrayMesh.new()
	var oa: Array = []
	oa.resize(Mesh.ARRAY_MAX)
	oa[Mesh.ARRAY_VERTEX] = verts
	oa[Mesh.ARRAY_NORMAL] = smooth
	oa[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, oa)
	return out


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
	_material("skin", skin_color)
	_material("hair", _hair_color)
	_material("shirt", _shirt_color)
	_material("pants", _pants_color)
	_material("pants_dark", _pants_color * 0.8)
	_material("boots", Color(0.09, 0.08, 0.07))
	_material("rubber", Color(0.04, 0.04, 0.045))
	_material("eye", Color(0.03, 0.03, 0.04))
	_material("lip", Color(0.5, 0.26, 0.24))
	_material("vest", Color(0.17, 0.18, 0.16))
	_material("plate", Color(0.1, 0.11, 0.11))
	_material("webbing", Color(0.2, 0.2, 0.17))
	_material("helmet", Color(0.2, 0.22, 0.18))
	_material("metal", Color(0.35, 0.36, 0.38))
	_material("lens", Color(0.12, 0.2, 0.26))

	_pelvis = _pivot(self, Vector3(0, HIP_H, 0))
	_part(_pelvis, Vector3(0.36, 0.2, 0.22), Vector3.ZERO, "pants")
	# belt with buckle, magazine pouches and a holster
	_part(_pelvis, Vector3(0.375, 0.055, 0.24), Vector3(0, 0.095, 0), "webbing")
	_part(_pelvis, Vector3(0.06, 0.04, 0.012), Vector3(0, 0.095, -0.123), "metal")
	for x in [-0.1, 0.1]:
		_part(_pelvis, Vector3(0.075, 0.1, 0.05), Vector3(x, 0.07, -0.14), "vest")
	_part(_pelvis, Vector3(0.06, 0.2, 0.13), Vector3(0.205, -0.07, -0.01), "webbing")
	_part(_pelvis, Vector3(0.05, 0.1, 0.1), Vector3(-0.2, 0.07, 0.04), "vest")
	_spine = _pivot(_pelvis, Vector3.ZERO)
	_part(_spine, Vector3(0.40, 0.52, 0.24), Vector3(0, 0.27, 0), "shirt")
	# plate carrier: shoulder straps, plates, three magazine pouches, radio, small assault pack
	_part(_spine, Vector3(0.425, 0.36, 0.265), Vector3(0, 0.33, 0), "vest")
	for x in [-0.12, 0.12]:
		_part(_spine, Vector3(0.09, 0.05, 0.27), Vector3(x, 0.53, 0), "vest")
	_part(_spine, Vector3(0.3, 0.25, 0.03), Vector3(0, 0.37, -0.14), "plate")
	_part(_spine, Vector3(0.3, 0.25, 0.03), Vector3(0, 0.37, 0.14), "plate")
	for x in [-0.11, 0.0, 0.11]:
		_part(_spine, Vector3(0.095, 0.115, 0.065), Vector3(x, 0.2, -0.155), "webbing")
		_part(_spine, Vector3(0.085, 0.02, 0.055), Vector3(x, 0.265, -0.158), "vest")
	_part(_spine, Vector3(0.05, 0.11, 0.04), Vector3(-0.17, 0.47, -0.12), "metal")
	_part(_spine, Vector3(0.012, 0.1, 0.012), Vector3(-0.17, 0.57, -0.12), "rubber")
	_part(_spine, Vector3(0.3, 0.32, 0.12), Vector3(0, 0.31, 0.2), "vest")
	_part(_spine, Vector3(0.26, 0.05, 0.1), Vector3(0, 0.49, 0.2), "webbing")
	_part(_spine, Vector3(0.14, 0.06, 0.15), Vector3(0, 0.555, 0), "shirt") # collar
	_head = _pivot(_spine, Vector3(0, 0.55, 0))
	_part(_head, Vector3(0.115, 0.1, 0.115), Vector3(0, 0.02, 0), "skin") # neck
	_part(_head, Vector3(0.23, 0.24, 0.23), Vector3(0, 0.14, 0), "skin")
	_part(_head, Vector3(0.20, 0.07, 0.21), Vector3(0, 0.035, 0.0), "skin") # jaw
	_part(_head, Vector3(0.036, 0.05, 0.045), Vector3(0, 0.12, -0.13), "skin") # nose
	for sx in [-1.0, 1.0]:
		_part(_head, Vector3(0.022, 0.06, 0.04), Vector3(sx * 0.122, 0.14, 0.01), "skin") # ears
		_part(_head, Vector3(0.062, 0.014, 0.02), Vector3(sx * 0.055, 0.19, -0.121), "hair", Vector3(0, 0, sx * -8.0)) # brows
		_part(_head, Vector3(0.045, 0.026, 0.02), Vector3(sx * 0.055, 0.16, -0.118), "eye")
	_part(_head, Vector3(0.07, 0.012, 0.012), Vector3(0, 0.07, -0.118), "lip")
	_part(_head, Vector3(0.25, 0.12, 0.05), Vector3(0, 0.17, 0.11), "hair") # hair at the back
	# helmet with brim, side rails, chin strap and goggles pushed up on the shell
	_part(_head, Vector3(0.27, 0.1, 0.285), Vector3(0, 0.285, 0.01), "helmet")
	_part(_head, Vector3(0.28, 0.055, 0.29), Vector3(0, 0.225, 0.015), "helmet")
	_part(_head, Vector3(0.24, 0.03, 0.045), Vector3(0, 0.252, -0.155), "helmet")
	_part(_head, Vector3(0.26, 0.04, 0.2), Vector3(0, 0.315, -0.02), "helmet")
	_part(_head, Vector3(0.265, 0.04, 0.05), Vector3(0, 0.248, -0.12), "rubber") # goggle strap
	_part(_head, Vector3(0.12, 0.05, 0.03), Vector3(0, 0.285, -0.145), "lens")
	for sx in [-1.0, 1.0]:
		_part(_head, Vector3(0.014, 0.15, 0.014), Vector3(sx * 0.106, 0.1, -0.03), "webbing")
		_part(_head, Vector3(0.016, 0.03, 0.2), Vector3(sx * 0.14, 0.27, 0.01), "metal")
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		# legs: thigh -> knee -> shin, boot with sole, pockets and knee pad
		var hip := _pivot(_pelvis, Vector3(sx * 0.1, -0.02, 0))
		_part(hip, Vector3(0.16, THIGH, 0.17), Vector3(0, -THIGH * 0.5, 0), "pants")
		_part(hip, Vector3(0.045, 0.15, 0.12), Vector3(sx * 0.1, -0.2, -0.01), "pants_dark")
		_part(hip, Vector3(0.05, 0.02, 0.1), Vector3(sx * 0.1, -0.13, -0.01), "webbing")
		var knee := _pivot(hip, Vector3(0, -THIGH, 0))
		_part(knee, Vector3(0.135, SHIN, 0.145), Vector3(0, -SHIN * 0.5, 0), "pants")
		_part(knee, Vector3(0.14, 0.12, 0.05), Vector3(0, -0.03, -0.09), "vest") # knee pad
		_part(knee, Vector3(0.152, 0.17, 0.168), Vector3(0, -SHIN + 0.07, 0), "boots") # boot shaft over the trousers
		_part(knee, Vector3(0.146, 0.08, 0.27), Vector3(0, -SHIN - 0.005, -0.05), "boots")
		_part(knee, Vector3(0.152, 0.03, 0.285), Vector3(0, -SHIN - 0.055, -0.052), "rubber") # sole
		_part(knee, Vector3(0.14, 0.05, 0.05), Vector3(0, -SHIN - 0.01, -0.19), "rubber") # toe cap
		_thigh.append(hip)
		_knee.append(knee)
		# arms: bones are pivots in rig space (solved by IK), meshes extend along -Z
		var up := _pivot(self, Vector3.ZERO)
		_part(up, Vector3(0.115, 0.115, UPPER_ARM), Vector3(0, 0, -UPPER_ARM * 0.5), "shirt")
		_part(up, Vector3(0.14, 0.04, 0.1), Vector3(0, 0.06, -0.04), "vest") # shoulder pad
		var low := _pivot(self, Vector3.ZERO)
		var sleeve := FORE_ARM - 0.1
		_part(low, Vector3(0.1, 0.1, sleeve), Vector3(0, 0, -sleeve * 0.5), "shirt")
		_part(low, Vector3(0.108, 0.04, 0.1), Vector3(0, 0.055, 0.0), "vest") # elbow pad
		_part(low, Vector3(0.108, 0.108, 0.03), Vector3(0, 0, -sleeve - 0.015), "webbing") # cuff
		_part(low, Vector3(0.088, 0.088, 0.085), Vector3(0, 0, -FORE_ARM + 0.035), "skin") # hand
		_arm_up.append(up)
		_arm_low.append(low)
	_commit_parts()
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
	# crouch: a staggered squat (left foot forward, right heel up) with real steps - the lifted foot bends its knee
	var crouch_thigh := [0.98 + 0.5 * amp * s, 1.30 - 0.5 * amp * s]
	var crouch_knee := [-1.55 - 0.6 * flex * maxf(0.0, c), -1.25 - 0.6 * flex * maxf(0.0, -c)]
	var slide_thigh := [1.5, 0.25]
	var slide_knee := [-0.1, -2.0]
	var air_thigh := [0.95, 0.25]
	var air_knee := [-1.25, -0.55]
	var foot_depth := [0.0, 0.0] # how far each foot hangs below the pelvis
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
		foot_depth[i] = THIGH * cos(th) + SHIN * cos(th + kn)
	# pelvis height and lean
	var bob := absf(s) * 0.035 * moving * (1.0 - _crouch) * (1.0 - _slide)
	# crouching: the pelvis sits exactly so that the lower foot touches the floor (no hovering)
	var crouch_h := maxf(float(foot_depth[0]), float(foot_depth[1])) + 0.035
	var h := lerpf(HIP_H - bob, crouch_h, _crouch)
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
	_spine.rotation.z = sin(_time * 1.7) * 0.012 + (-vel_local.x * 0.012) + _hit.y - lean * 0.2
	_pelvis.position.x = lean * 0.07
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
	if flash_cover > 0.001:
		var face_local := to_local(face_cover_point())
		left_target = face_local if left_target == Vector3.INF else left_target.lerp(face_local, flash_cover)
		# the other arm lets go of the grip a little and the upper body shrinks away from the light
		_spine_lean = lerpf(_spine_lean, -0.18, minf(1.0, flash_cover * 0.5))
	_solve_arm(0, right_target, Vector3(0.45, -1.0, 0.25))
	_solve_arm(1, left_target, Vector3(-0.45, -1.0, 0.25) if flash_cover < 0.001 else Vector3(-0.55, 0.95, -0.1))


## World position in front of the face where the covering hand goes (right of the face: the left forearm crosses the eyes diagonally from lower left to upper right).
func face_cover_point() -> Vector3:
	var jit := Vector3(sin(_time * 44.0) * 0.008, sin(_time * 57.0) * 0.007, sin(_time * 35.0) * 0.004) * flash_cover
	return _head.to_global(Vector3(0.13, 0.17, -0.20) + jit)


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
