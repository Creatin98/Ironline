class_name FirstPersonArms
extends Node3D
## The arms of the first-person view. Two-bone IK from shoulders that sit in camera space (just behind and
## below the picture) to the wrists of the weapon model's hands: upper arm and forearm always connect and leave
## the picture at its edge, whatever the hand does (reload, sprint, aim, field of view up to 110 degrees).
## A target that is out of reach stretches the arm (as in every first-person game) instead of cutting it off.
##
## Limbs are flat-shaded tapered octagonal prisms (the blocky look of the world): bare forearm in the skin tone of
## the player, shirt sleeve on the upper arm - the same colours as the third-person figure.
## Space: camera space (x right, y up, -z forward).

const UPPER := 0.30
const FORE := 0.28
## Shoulders: below the picture's lower edge, slightly behind the picture plane.
const SHOULDERS := [Vector3(0.27, -0.31, 0.05), Vector3(-0.27, -0.31, 0.05)]
## Elbow directions: down and outwards (right arm / left arm).
const POLES := [Vector3(0.40, -1.0, 0.35), Vector3(-0.50, -1.0, 0.30)]
const R_WRIST := 0.030
const R_ELBOW := 0.052
const R_SHOULDER := 0.062

var _upper: Array[MeshInstance3D] = []
var _fore: Array[MeshInstance3D] = []
var _skin_mat: StandardMaterial3D
var _shirt_mat: StandardMaterial3D


func _ready() -> void:
	_skin_mat = _material(Color(0.88, 0.72, 0.58))
	_shirt_mat = _material(Color(0.25, 0.29, 0.2))
	var fore_mesh := limb(FORE, R_WRIST, R_ELBOW)
	var upper_mesh := limb(UPPER, R_ELBOW, R_SHOULDER)
	for side in 2:
		var f := MeshInstance3D.new()
		f.mesh = fore_mesh
		f.material_override = _skin_mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		_fore.append(f)
		var u := MeshInstance3D.new()
		u.mesh = upper_mesh
		u.material_override = _shirt_mat
		u.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(u)
		_upper.append(u)


static func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED # winding-independent; back faces get flipped normals
	return m


func set_colors(skin: Color, shirt: Color) -> void:
	if _skin_mat != null:
		_skin_mat.albedo_color = skin
		_shirt_mat.albedo_color = shirt


## Flat-shaded tapered octagonal prism from z = 0 (radius `r0`) to z = -length (radius `r1`), caps included.
static func limb(length: float, r0: float, r1: float, sides: int = 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for i in sides:
		var ang := TAU * (float(i) + 0.5) / float(sides)
		a.append(Vector3(cos(ang) * r0, sin(ang) * r0, 0.0))
		b.append(Vector3(cos(ang) * r1, sin(ang) * r1, -length))
	for i in sides:
		var j := (i + 1) % sides
		for v in [a[i], b[i], b[j], a[i], b[j], a[j]]:
			st.add_vertex(v)
		for v in [Vector3.ZERO, a[j], a[i]]:
			st.add_vertex(v)
		for v in [Vector3(0, 0, -length), b[i], b[j]]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Solves both arms. Targets: the wrists in camera space (Vector3.INF = hand not available, arm hidden).
func update(right_wrist: Vector3, left_wrist: Vector3) -> void:
	_solve(0, right_wrist)
	_solve(1, left_wrist)


func _solve(side: int, target: Vector3) -> void:
	var show := target != Vector3.INF
	_upper[side].visible = show
	_fore[side].visible = show
	if not show:
		return
	var shoulder: Vector3 = SHOULDERS[side]
	var to_t := target - shoulder
	var dist := maxf(to_t.length(), 0.06)
	var reach := UPPER + FORE
	# too far away: stretch both bones evenly so the arm still reaches the hand
	var stretch := maxf(1.0, dist / (reach * 0.998))
	var l1 := UPPER * stretch
	var l2 := FORE * stretch
	var d := minf(dist, (l1 + l2) * 0.999)
	var fwd := to_t / dist
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var pole: Vector3 = POLES[side]
	var side_dir := pole - fwd * pole.dot(fwd)
	if side_dir.length() < 0.001:
		side_dir = Vector3.DOWN
	side_dir = side_dir.normalized()
	var elbow := shoulder + fwd * a + side_dir * h
	var wrist := shoulder + fwd * d
	_upper[side].transform = Transform3D(_look(elbow - shoulder) * Basis.from_scale(Vector3(1, 1, stretch)), shoulder)
	_fore[side].transform = Transform3D(_look(wrist - elbow) * Basis.from_scale(Vector3(1, 1, stretch)), elbow)


static func _look(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(d, up)
