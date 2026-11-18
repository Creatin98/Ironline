class_name GrenadeView
extends Node3D
## First-person grenade throw: the right hand brings up the grenade, the left hand pulls the pin
## (ring and pin come away with it), the right arm winds up and throws, then both hands leave.
## Procedural boxes (bare hands/arms in the skin tone of the player), driven by `apply(t)` with t = 0..1.
## Two grenades: the green round frag grenade and the silver flashbang can (same throw, same pin).
## Space: camera space (x right, y up, -z forward).

const SKIN := Color(0.88, 0.72, 0.58)
const SLEEVE := Color(0.17, 0.20, 0.14)
const CAN := Color(0.74, 0.76, 0.80)
const CAN_DARK := Color(0.09, 0.09, 0.10)
const BODY := Color(0.24, 0.29, 0.17)
const STEEL := Color(0.62, 0.64, 0.66)

## t at which the grenade leaves the hand (Weapon manager spawns the real grenade then).
const RELEASE_T := 0.62

var _right: Node3D
var _right_arm: Node3D
var _left: Node3D
var _grenade: Node3D
var _ring: Node3D
var _lever: Node3D
var _flash_can: Node3D
var _flash_lever: Node3D
var _skin_mat: StandardMaterial3D
var _kind: int = Grenade.KIND_FRAG

const R_POS := [
	[0.00, Vector3(0.30, -0.52, -0.30)], [0.20, Vector3(0.11, -0.14, -0.40)], [0.46, Vector3(0.11, -0.13, -0.40)],
	[0.58, Vector3(0.19, -0.03, -0.22)], [0.62, Vector3(0.19, -0.02, -0.21)], [0.70, Vector3(0.05, -0.08, -0.72)],
	[0.80, Vector3(0.07, -0.22, -0.78)], [1.00, Vector3(0.30, -0.58, -0.40)],
]
const R_ROT := [
	[0.00, 0.30], [0.20, 0.10], [0.46, 0.05], [0.58, 0.75], [0.62, 0.80], [0.70, -0.60], [0.80, -0.95], [1.00, -0.30],
]
const L_POS := [
	[0.00, Vector3(-0.40, -0.55, -0.30)], [0.22, Vector3(-0.40, -0.55, -0.30)], [0.32, Vector3(0.10, -0.07, -0.37)],
	[0.36, Vector3(0.10, -0.06, -0.38)], [0.44, Vector3(-0.14, -0.14, -0.36)], [0.56, Vector3(-0.32, -0.42, -0.30)],
	[1.00, Vector3(-0.40, -0.58, -0.30)],
]
const HAND_SCALE := 1.35
const PIN_T := 0.36


func _ready() -> void:
	_build()
	visible = false


static func _mat(c: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.metallic = metallic
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _forearm(parent: Node3D, from: Vector3, to: Vector3, w: float, h: float, mat: Material) -> void:
	var d := to - from
	var mi := _box(parent, Vector3(w, h, d.length()), (from + to) * 0.5, mat)
	mi.basis = Basis.looking_at(d.normalized(), Vector3.UP)


func _build() -> void:
	_skin_mat = _mat(SKIN)
	var glove := _skin_mat # bare hands and forearms
	var sleeve := _skin_mat
	var steel := _mat(STEEL, 0.6)
	var body := _mat(BODY)
	# --- right hand holding the grenade
	_right = Node3D.new()
	_right.scale = Vector3.ONE * HAND_SCALE
	add_child(_right)
	_box(_right, Vector3(0.078, 0.034, 0.092), Vector3(0, -0.035, 0.02), glove) # palm
	for k in 4:
		_box(_right, Vector3(0.016, 0.03, 0.05), Vector3(-0.03 + 0.02 * k, 0.012, -0.03), glove, Vector3(-0.5, 0, 0)) # fingers over the grenade
	_box(_right, Vector3(0.02, 0.03, 0.06), Vector3(-0.045, 0.0, 0.0), glove, Vector3(0, 0.3, 0)) # thumb
	_right_arm = Node3D.new() # pivot at the wrist; counter-rotates so the sleeve stays below the view while the hand swings
	_right_arm.position = Vector3(0.01, -0.05, 0.07)
	_right.add_child(_right_arm)
	_forearm(_right_arm, Vector3.ZERO, Vector3(0.13, -0.17, 0.35), 0.09, 0.08, sleeve)
	_grenade = Node3D.new()
	_grenade.position = Vector3(0, 0.02, -0.02)
	_right.add_child(_grenade)
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.034
	cm.bottom_radius = 0.034
	cm.height = 0.092
	cm.radial_segments = 8
	cyl.mesh = cm
	cyl.material_override = body
	_grenade.add_child(cyl)
	_box(_grenade, Vector3(0.026, 0.018, 0.026), Vector3(0, 0.055, 0), steel) # fuze
	_lever = Node3D.new()
	_lever.position = Vector3(0.034, 0.05, 0)
	_grenade.add_child(_lever)
	_box(_lever, Vector3(0.008, 0.095, 0.024), Vector3(0.0, -0.04, 0), steel) # spoon along the body
	# --- the flashbang: silver can, dark caps and band, straight lever
	_flash_can = Node3D.new()
	_flash_can.position = _grenade.position
	_right.add_child(_flash_can)
	var can_mat := _mat(CAN, 0.75)
	var dark_mat := _mat(CAN_DARK, 0.3)
	for part in [[0.0, 0.100, 0.030, can_mat], [0.056, 0.024, 0.0315, dark_mat], [-0.056, 0.024, 0.0315, dark_mat], [0.004, 0.014, 0.0308, dark_mat]]:
		var cm2 := CylinderMesh.new()
		cm2.top_radius = float(part[2])
		cm2.bottom_radius = float(part[2])
		cm2.height = float(part[1])
		cm2.radial_segments = 10
		var cy := MeshInstance3D.new()
		cy.mesh = cm2
		cy.material_override = part[3]
		cy.position = Vector3(0.0, float(part[0]), 0.0)
		cy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash_can.add_child(cy)
	_flash_lever = Node3D.new()
	_flash_lever.position = Vector3(0.031, 0.05, 0.0)
	_flash_can.add_child(_flash_lever)
	_box(_flash_lever, Vector3(0.007, 0.108, 0.022), Vector3(0.0, -0.045, 0.0), dark_mat)
	_flash_can.visible = false
	# --- pin ring (travels with the left hand once pulled)
	_ring = Node3D.new()
	add_child(_ring)
	for k in 4:
		var a := TAU * k / 4.0
		_box(_ring, Vector3(0.006, 0.006, 0.026), Vector3(cos(a) * 0.011, 0, sin(a) * 0.011).rotated(Vector3.UP, 0.0), steel, Vector3(0, -a + PI / 2.0, 0))
	_box(_ring, Vector3(0.005, 0.005, 0.04), Vector3(0, -0.012, 0), steel) # pin shaft
	# --- left hand (hooks the ring)
	_left = Node3D.new()
	_left.scale = Vector3.ONE * HAND_SCALE
	add_child(_left)
	_box(_left, Vector3(0.07, 0.03, 0.085), Vector3(0, -0.03, 0.02), glove)
	_box(_left, Vector3(0.016, 0.03, 0.05), Vector3(0.01, 0.012, -0.035), glove, Vector3(-0.7, 0, 0.3))
	_box(_left, Vector3(0.018, 0.03, 0.05), Vector3(0.035, 0.0, -0.02), glove, Vector3(-0.2, 0, 0.0))
	_forearm(_left, Vector3(-0.01, -0.05, 0.07), Vector3(-0.16, -0.22, 0.42), 0.085, 0.075, sleeve)


static func _key(keys: Array, t: float) -> Variant:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		if t <= t1:
			var t0: float = keys[i - 1][0]
			var u := clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			var a: Variant = keys[i - 1][1]
			var b: Variant = keys[i][1]
			if a is Vector3:
				return (a as Vector3).lerp(b, u)
			return lerpf(float(a), float(b), u)
	return keys[keys.size() - 1][1]


## Which grenade is in the hand (before a throw).
func set_kind(kind: int) -> void:
	_kind = kind


## Skin tone of the player (hands and forearms), like the first-person arms.
func set_colors(skin: Color) -> void:
	if _skin_mat != null:
		_skin_mat.albedo_color = skin


## t = 0..1 over the whole throw. The view hides itself before 0 and after 1.
func apply(t: float, hold_time: float = 0.0) -> void:
	visible = t > 0.0 and t < 1.0
	if not visible:
		return
	var rp: Vector3 = _key(R_POS, t)
	if hold_time > 0.0:
		# held ready: the cocked arm trembles a little (stronger the longer it is held)
		var s := minf(1.0 + hold_time * 0.5, 2.5)
		rp += Vector3(sin(hold_time * 9.0) * 0.0018, cos(hold_time * 7.3) * 0.0022, sin(hold_time * 5.1) * 0.0012) * s
	_right.position = rp
	_right.rotation = Vector3(float(_key(R_ROT, t)), 0.0, 0.0)
	_right_arm.rotation.x = -_right.rotation.x * 0.85
	var lp: Vector3 = _key(L_POS, t)
	_left.position = lp
	_left.visible = t > 0.2 and t < 0.6
	_grenade.visible = t < RELEASE_T and _kind == Grenade.KIND_FRAG
	_flash_can.visible = t < RELEASE_T and _kind == Grenade.KIND_FLASH
	# the spoon flips away when the grenade is let go
	_lever.rotation.z = -0.9 * clampf((t - RELEASE_T) / 0.05, 0.0, 1.0)
	_flash_lever.rotation.z = _lever.rotation.z
	# ring: on the grenade until the pin is pulled, then in the left hand
	if t < PIN_T:
		_ring.position = rp + Basis.from_euler(_right.rotation) * ((_grenade.position + Vector3(0.0, 0.07, 0.0)) * HAND_SCALE)
		_ring.visible = t > 0.1 and t < RELEASE_T
	else:
		_ring.position = lp + Vector3(0.0, 0.0, -0.01)
		_ring.visible = t < 0.58
