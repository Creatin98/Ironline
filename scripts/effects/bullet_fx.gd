class_name BulletFx
extends Node3D

## Visible projectile: a small brass-coloured round that flies from the muzzle to where the shot ends (no streaks), and
## ejected casings that tumble, bounce and ring on the ground. Purely visual (the hit itself is the instant hitscan).

const SPEED := 260.0
const MAX_CASINGS := 28

static var _mesh: CapsuleMesh
static var _mat: StandardMaterial3D
static var _casing_mesh: CylinderMesh
static var _casing_mat: StandardMaterial3D
static var _casings: Array = []

var _from: Vector3
var _to: Vector3
var _t: float = 0.0
var _dur: float = 0.1


static func fire(parent: Node, from: Vector3, to: Vector3) -> void:
	var d := from.distance_to(to)
	if d < 4.0 or parent == null:
		return
	if _mesh == null:
		_mesh = CapsuleMesh.new()
		_mesh.radius = 0.011
		_mesh.height = 0.07
		_mesh.radial_segments = 6
		_mesh.rings = 2
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.95, 0.72, 0.32)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.6, 0.2)
		_mat.emission_energy_multiplier = 2.2
		_mat.metallic = 0.8
		_mat.roughness = 0.3
		_mesh.material = _mat
	var b := BulletFx.new()
	b._from = from
	b._to = to
	b._dur = maxf(d / SPEED, 0.02)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.rotation.x = PI * 0.5 # capsule along -Z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(mi)
	parent.add_child(b)
	b.global_position = from + (to - from).normalized() * 1.0
	b.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)


func _process(delta: float) -> void:
	_t += delta
	var k := _t / _dur
	if k >= 1.0:
		queue_free()
		return
	global_position = _from.lerp(_to, k)


## A brass casing flies out of the ejection port (`pos`), `right` is the weapon's right direction.
static func eject_casing(parent: Node, pos: Vector3, right: Vector3, up: Vector3) -> void:
	if parent == null or not GameSettings.effects_scale() > 0.0:
		return
	if _casing_mesh == null:
		_casing_mesh = CylinderMesh.new()
		_casing_mesh.top_radius = 0.0045
		_casing_mesh.bottom_radius = 0.0055
		_casing_mesh.height = 0.04
		_casing_mesh.radial_segments = 6
		_casing_mat = StandardMaterial3D.new()
		_casing_mat.albedo_color = Color(0.85, 0.62, 0.25)
		_casing_mat.metallic = 0.9
		_casing_mat.roughness = 0.35
		_casing_mesh.material = _casing_mat
	_casings = _casings.filter(func(c) -> bool: return is_instance_valid(c))
	while _casings.size() >= MAX_CASINGS:
		(_casings.pop_front() as Node).queue_free()
	var rb := CasingBody.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 0.02
	rb.linear_damp = 0.1
	rb.angular_damp = 0.2
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	var phys := PhysicsMaterial.new()
	phys.bounce = 0.4
	phys.friction = 0.6
	rb.physics_material_override = phys
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.0055
	sh.height = 0.04
	cs.shape = sh
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _casing_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	parent.add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = right * randf_range(1.6, 2.6) + up * randf_range(1.2, 2.2) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	rb.angular_velocity = Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30))
	_casings.append(rb)
