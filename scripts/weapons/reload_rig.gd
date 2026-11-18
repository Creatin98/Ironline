class_name ReloadRig
extends RefCounted
## Procedural reload animation for one weapon model (first-person model or a player's
## third-person copy). Moves the model's parts with keyframes: the magazine ("Mag"), the hands
## ("LeftHand"/"RightHand"), the charging handle, the pistol slide and the shotgun shell ("ShellProp").
##
## apply(t) takes the progress t (0..1) of one reload cycle, poses the parts and returns the
## sound events that were passed since the last call. holder_offset/holder_rotation tell the
## WeaponManager how the whole weapon tilts in the view.
##
## Styles: "rifle" (AK), "smg" (MP5), "pistol", "shotgun" (one shell per cycle).

const RIFLE := {
	"grip": Vector3(-0.030, -0.120, -0.068),
	"belt": Vector3(-0.200, -0.320, 0.000),
	"handle_hand": Vector3(0.012, 0.072, -0.020),
	"handle_pull": 0.055,
}
const SMG := {
	"grip": Vector3(-0.030, -0.115, -0.040),
	"belt": Vector3(-0.200, -0.320, 0.000),
	"handle_hand": Vector3(-0.060, 0.045, -0.240),
	"handle_pull": 0.060,
}
const PISTOL := {
	"grip": Vector3(-0.012, -0.112, 0.060),
	"belt": Vector3(-0.150, -0.260, 0.100),
}
## Shotgun: the support hand fetches a shell at the belt, shoves it into the loading gate at the bottom of the receiver
## and snaps back to the belt for the next one (only the last shell sends it back to the forend); the right hand stays on the grip.
const SHOTGUN := {
	"belt": Vector3(-0.150, -0.225, 0.085),
	"gate_low": Vector3(-0.045, -0.125, 0.080),
	"gate": Vector3(-0.012, -0.080, 0.052),
	"gate_push": Vector3(-0.002, -0.058, 0.032),
}
## Progress of a shell cycle at which the shell is pushed in (it counts for the magazine from here on, see Weapon).
const SHELL_INSERT_T := 0.62
## The "ratsch" sound starts a little earlier: shell scraping into the gate, the clack at the insert mark.
const SHELL_SOUND_T := 0.52

var style: String = "rifle"
var holder_offset: Vector3 = Vector3.ZERO
var holder_rotation: Vector3 = Vector3.ZERO

var _mag: Node3D
var _left: Node3D
var _right: Node3D
var _shell: Node3D
var _handle: Node3D
var _slide: Node3D
var _rest: Dictionary = {} # node -> [position, rotation]
var _last_t: float = -1.0
## Forearms stay anchored at the elbow while the hand moves: {hand, fore, start, elbow, length}
var _arms: Array = []
## Pose-driven tweaks of the left forearm (rifle reload: crossing over the weapon without clipping through it).
var left_elbow_shift: Vector3 = Vector3.ZERO
var left_arm_slim: float = 1.0
## False in the first-person view: there the arms come from FirstPersonArms (IK), the model's own sleeves stay hidden.
var show_sleeves: bool = true
## Shotgun: this cycle is the first (hand comes from the forend) / the last one (hand goes back to the forend).
var shell_first: bool = true
var shell_last: bool = true
var _exit_from: Dictionary = {} # node -> [position, rotation, scale] at the moment the reload was interrupted
var _exit_extra: Array = []


static func create(model: Node3D, reload_style: String) -> ReloadRig:
	var r := ReloadRig.new()
	r.style = reload_style
	r._mag = model.get_node_or_null("Mag") as Node3D
	r._left = model.get_node_or_null("LeftHand") as Node3D
	r._right = model.get_node_or_null("RightHand") as Node3D
	r._shell = model.get_node_or_null("LeftHand/ShellProp") as Node3D
	r._handle = model.get_node_or_null("ChargingHandle") as Node3D
	if r._handle == null:
		r._handle = model.get_node_or_null("CockingHandle") as Node3D
	r._slide = model.get_node_or_null("Slide") as Node3D
	for n in [r._mag, r._left, r._right, r._shell, r._handle, r._slide]:
		if n != null:
			r._rest[n] = [n.position, n.rotation]
	for pair in [[r._left, "LeftForearm"], [r._right, "RightForearm"]]:
		var hand: Node3D = pair[0]
		if hand == null:
			continue
		var fore := hand.get_node_or_null(String(pair[1])) as MeshInstance3D
		if fore == null or not (fore.mesh is BoxMesh):
			continue
		var length := (fore.mesh as BoxMesh).size.z
		var axis := fore.transform.basis * Vector3(0.0, 0.0, 1.0)
		var e1 := fore.position + axis * length * 0.5
		var e2 := fore.position - axis * length * 0.5
		var start := e1 if e1.length() < e2.length() else e2 # the end at the hand
		var elbow := e2 if start == e1 else e1
		r._rest[fore] = [fore.position, fore.rotation, fore.scale]
		r._arms.append({"hand": hand, "fore": fore, "start": start, "elbow": hand.position + elbow, "length": length})
	return r


## Tints the bare hands of a weapon model to a skin tone (the same tone as the arm / the character):
## the model's skin materials are shared by all instances, so every model gets its own copies.
static func apply_skin(model: Node3D, skin: Color) -> void:
	var mats := {}
	for hand_name in ["LeftHand", "RightHand"]:
		var hand := model.get_node_or_null(hand_name)
		if hand == null:
			continue
		for n in hand.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var pm := mi.mesh as PrimitiveMesh
			if pm == null or pm.material == null:
				continue
			var key := pm.material.resource_name
			if key != "skin" and key != "skin_shade" and key != "nail":
				continue
			if not mats.has(key):
				var m := pm.material.duplicate() as StandardMaterial3D
				match key:
					"skin":
						m.albedo_color = skin
					"skin_shade":
						m.albedo_color = skin.darkened(0.13)
					_:
						m.albedo_color = skin.lerp(Color(1.0, 0.93, 0.88), 0.3)
				mats[key] = m
			mi.material_override = mats[key]


## Back to the rest pose (end of reload, weapon switch, death).
func reset() -> void:
	left_elbow_shift = Vector3.ZERO
	left_arm_slim = 1.0
	for arm in _arms:
		(arm["fore"] as Node3D).visible = show_sleeves
	for n in _rest:
		if is_instance_valid(n):
			n.position = _rest[n][0]
			n.rotation = _rest[n][1]
			if _rest[n].size() > 2:
				n.scale = _rest[n][2]
	if _mag != null:
		_mag.visible = true
	if _shell != null:
		_shell.visible = false
	holder_offset = Vector3.ZERO
	holder_rotation = Vector3.ZERO
	_last_t = -1.0
	_exit_from.clear()
	_exit_extra = []


## The reload is interrupted (shot while loading shells): remembers the current pose, blend_out() leads it back to rest.
func begin_exit() -> void:
	_exit_from.clear()
	for n in _rest:
		if is_instance_valid(n):
			_exit_from[n] = [n.position, n.rotation, n.scale]
	_exit_extra = [holder_offset, holder_rotation, left_elbow_shift, left_arm_slim, _shell != null and _shell.visible]


## Smooth way back from the interrupted pose into the rest pose, k = 0..1.
func blend_out(k: float) -> void:
	if _exit_extra.is_empty():
		return
	var e := _smooth(k)
	for n in _exit_from:
		if not is_instance_valid(n):
			continue
		var from: Array = _exit_from[n]
		var rest: Array = _rest[n]
		n.position = (from[0] as Vector3).lerp(rest[0], e)
		n.rotation = (from[1] as Vector3).lerp(rest[1], e)
		if rest.size() > 2:
			n.scale = (from[2] as Vector3).lerp(rest[2], e)
	holder_offset = (_exit_extra[0] as Vector3).lerp(Vector3.ZERO, e)
	holder_rotation = (_exit_extra[1] as Vector3).lerp(Vector3.ZERO, e)
	left_elbow_shift = (_exit_extra[2] as Vector3).lerp(Vector3.ZERO, e)
	left_arm_slim = lerpf(float(_exit_extra[3]), 1.0, e)
	if _shell != null:
		_shell.visible = bool(_exit_extra[4]) and k < 0.4
	_update_arms()


## Poses the model at cycle progress t (0..1). `tilt_scale` scales the whole-weapon tilt
## (the shotgun eases it in once at the start of the reload instead of per shell).
## Returns the sound events passed since the previous call.
func apply(t: float, tilt_scale: float = 1.0) -> Array[String]:
	t = clampf(t, 0.0, 1.0)
	match style:
		"pistol":
			_pose_pistol(t)
		"shotgun":
			_pose_shotgun(t, tilt_scale)
		"smg":
			_pose_rifle(t, SMG)
		_:
			_pose_rifle(t, RIFLE)
	_update_arms()
	var events: Array[String] = []
	var from := _last_t if _last_t >= 0.0 else -0.001
	for ev in _events():
		if float(ev[0]) > from and float(ev[0]) <= t:
			events.append(String(ev[1]))
	_last_t = t
	return events


## Re-aims each forearm from the fixed elbow to the (moved) hand and stretches it to fit.
func _update_arms() -> void:
	for arm in _arms:
		var hand: Node3D = arm["hand"]
		var fore: Node3D = arm["fore"]
		var a: Vector3 = hand.position + (arm["start"] as Vector3)
		var b: Vector3 = arm["elbow"]
		if hand == _left:
			b += left_elbow_shift
		var d := b - a
		var dist := d.length()
		if dist < 0.01:
			continue
		var f := d / dist
		fore.position = (a + b) * 0.5 - hand.position
		fore.rotation = Vector3(asin(clampf(f.y, -1.0, 1.0)), atan2(-f.x, -f.z), 0.0)
		var slim := left_arm_slim if hand == _left else 1.0
		fore.visible = show_sleeves and slim > 0.08
		fore.scale = Vector3(slim, slim, dist / float(arm["length"]))


func _events() -> Array:
	match style:
		"pistol":
			return [[0.15, "reload_release"], [0.24, "reload_pistol_out"], [0.72, "reload_pistol_in"], [0.80, "reload_slide"]]
		"shotgun":
			return [[SHELL_SOUND_T, "shell_insert"]]
		_:
			return [[0.15, "reload_release"], [0.21, "reload_mag_out"], [0.74, "reload_mag_in"], [0.79, "reload_slap"], [0.85, "reload_bolt"]]


# ----------------------------------------------------------------------------- helpers

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(0.0001, b - a), 0.0, 1.0)


## Smoothly interpolated keyframes: [[t, value], ...] sorted by t (Vector3 or float).
static func _key(keys: Array, t: float, snap: bool = false) -> Variant:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		if t <= t1:
			var t0: float = keys[i - 1][0]
			var lin := clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
			# snap: fast start, soft stop (every move is a quick flick instead of a smooth glide)
			var k := (1.0 - (1.0 - lin) * (1.0 - lin)) if snap else _smooth(lin)
			var a: Variant = keys[i - 1][1]
			var b: Variant = keys[i][1]
			if a is Vector3:
				return (a as Vector3).lerp(b, k)
			return lerpf(float(a), float(b), k)
	return keys[keys.size() - 1][1]


func _rest_pos(n: Node3D) -> Vector3:
	return _rest[n][0] if n != null and _rest.has(n) else Vector3.ZERO


# ----------------------------------------------------------------------------- rifle / smg

func _pose_rifle(t: float, cfg: Dictionary) -> void:
	var lh0 := _rest_pos(_left)
	var mag0 := _rest_pos(_mag)
	var grip: Vector3 = cfg["grip"]
	var belt: Vector3 = cfg["belt"]
	var off := mag0 - grip # the magazine sits at this offset to the hand that holds it
	var side_x := -0.095 # clear of the weapon (it is +-0.025 wide) on the left
	var pull := Vector3(0.0, -0.11, 0.02)
	var hh: Vector3 = cfg["handle_hand"]
	var lh: Vector3 = _key([
		[0.00, lh0], [0.14, grip], [0.17, grip],
		[0.24, grip + Vector3(0, -0.02, 0.008)], [0.32, grip + pull],
		[0.46, belt], [0.50, belt],
		[0.64, grip + pull], [0.74, grip + Vector3(0, -0.008, 0)], [0.78, grip + Vector3(0, 0.006, 0)],
		# to the charging handle and back: around the LEFT side of the weapon, never through it
		[0.80, Vector3(side_x, grip.y + 0.09, grip.z)], [0.825, Vector3(side_x, hh.y + 0.04, (grip.z + hh.z) * 0.5)],
		[0.845, hh + Vector3(0, 0.02, 0.02)], [0.87, hh + Vector3(0, 0.01, float(cfg["handle_pull"]))],
		[0.90, hh + Vector3(0, 0.01, 0)], [0.93, Vector3(side_x, hh.y + 0.01, hh.z - 0.05)],
		[0.965, Vector3(side_x + 0.02, lh0.y + 0.05, lh0.z + 0.04)], [1.00, lh0],
	], t, true) # snap: every move is a quick flick (a magazine change in the middle of a fight)
	# while the hand crosses over the weapon its sleeve shrinks away (a sleeve in the line of the weapon would clip through it)
	left_arm_slim = 1.0 - (_smooth(_seg(t, 0.79, 0.815)) - _smooth(_seg(t, 0.94, 0.97)))
	var mag_pos: Vector3 = _key([
		[0.00, mag0], [0.17, mag0], [0.24, mag0 + Vector3(0, -0.02, 0.008)], [0.32, mag0 + pull],
		[0.46, belt + off], [0.50, belt + off],
		[0.64, mag0 + pull], [0.74, mag0 + Vector3(0, -0.008, 0)], [0.78, mag0],
	], t, true)
	var mag_rot: float = _key([[0.00, 0.0], [0.17, 0.0], [0.24, 0.20], [0.32, 0.22], [0.46, 0.30], [0.50, 0.30], [0.64, 0.22], [0.74, 0.02], [0.78, 0.0]], t)
	if _left != null:
		_left.position = lh
	if _mag != null:
		_mag.position = mag_pos
		_mag.rotation = Vector3(mag_rot, 0.0, 0.0)
		_mag.visible = not (t > 0.46 and t < 0.50) # the old magazine goes into the pouch, a new one comes out
	if _handle != null:
		var h := float(_key([[0.82, 0.0], [0.86, 1.0], [0.905, 0.0]], t))
		_handle.position = _rest_pos(_handle) + Vector3(0, 0, float(cfg["handle_pull"]) * h)
	var tilt := _smooth(_seg(t, 0.0, 0.10)) - _smooth(_seg(t, 0.92, 1.0))
	var seat := exp(-pow((t - 0.74) * 26.0, 2.0)) # the new magazine is slammed home
	var yank := exp(-pow((t - 0.24) * 24.0, 2.0)) # the old one is torn out
	var rack := exp(-pow((t - 0.885) * 24.0, 2.0)) # the charging handle is slapped forward
	holder_offset = (Vector3(-0.075, 0.0, 0.07) + Vector3(0.0, -0.014, 0.035) * seat + Vector3(0.0, 0.012, 0.02) * yank + Vector3(0.0, 0.0, -0.015) * rack) * tilt
	holder_rotation = Vector3(0.22 + seat * 0.16 - yank * 0.08 - rack * 0.05, -0.08 + seat * 0.05 - yank * 0.05, -0.58 + yank * 0.06 - seat * 0.04) * tilt


# ----------------------------------------------------------------------------- pistol

func _pose_pistol(t: float) -> void:
	var lh0 := _rest_pos(_left)
	var mag0 := _rest_pos(_mag)
	var grip: Vector3 = PISTOL["grip"]
	var belt: Vector3 = PISTOL["belt"]
	var off := mag0 - grip
	var pulled := Vector3(0.0, -0.13, 0.01)
	var lh: Vector3 = _key([
		[0.00, lh0], [0.14, grip], [0.17, grip], [0.26, grip + Vector3(0, -0.06, 0.005)], [0.34, grip + pulled],
		[0.44, belt], [0.48, belt],
		[0.62, grip + pulled], [0.72, grip + Vector3(0, -0.008, 0)], [0.76, grip + Vector3(0, 0.005, 0)],
		[0.84, lh0 + Vector3(0, -0.01, 0.01)], [1.00, lh0],
	], t, true)
	var mag_pos: Vector3 = _key([
		[0.00, mag0], [0.17, mag0], [0.26, mag0 + Vector3(0, -0.06, 0.005)], [0.34, mag0 + pulled],
		[0.44, belt + off], [0.48, belt + off],
		[0.62, mag0 + pulled], [0.72, mag0 + Vector3(0, -0.008, 0)], [0.76, mag0],
	], t, true)
	if _left != null:
		_left.position = lh
	if _mag != null:
		_mag.position = mag_pos
		_mag.rotation = Vector3.ZERO
		_mag.visible = not (t > 0.44 and t < 0.48)
	if _slide != null:
		# the slide is released: it snaps back a little and forward again
		var kick := float(_key([[0.80, 0.0], [0.82, 1.0], [0.86, 0.0]], t))
		_slide.position = _rest_pos(_slide) + Vector3(0, 0, 0.034 * kick)
	var tilt := _smooth(_seg(t, 0.0, 0.10)) - _smooth(_seg(t, 0.92, 1.0))
	var seat := exp(-pow((t - 0.72) * 26.0, 2.0)) # the magazine is slammed in
	var yank := exp(-pow((t - 0.26) * 24.0, 2.0)) # the old one is ripped out
	var slap := exp(-pow((t - 0.81) * 28.0, 2.0)) # slide release
	holder_offset = (Vector3(-0.065, 0.02, 0.05) + Vector3(0.0, -0.012, 0.03) * seat + Vector3(0.0, 0.010, 0.015) * yank + Vector3(0.0, 0.0, -0.012) * slap) * tilt
	holder_rotation = Vector3(0.30 + seat * 0.14 - yank * 0.07 - slap * 0.05, -0.08 + seat * 0.05, -0.62 + yank * 0.05 - seat * 0.04) * tilt


# ----------------------------------------------------------------------------- shotgun

func _pose_shotgun(t: float, tilt_scale: float) -> void:
	var lh0 := _rest_pos(_left)
	var belt: Vector3 = SHOTGUN["belt"]
	var gate_low: Vector3 = SHOTGUN["gate_low"]
	var gate: Vector3 = SHOTGUN["gate"]
	var push: Vector3 = SHOTGUN["gate_push"]
	var start := lh0 if shell_first else belt # the first cycle comes from the forend, later ones from the belt
	var end := lh0 if shell_last else belt # the last cycle ends on the forend
	var lh: Vector3 = _key([
		[0.00, start], [0.16 if shell_first else 0.02, belt], [0.22, belt],
		[0.44, gate_low], [0.56, gate], [SHELL_INSERT_T, push], [0.72, push],
		[0.92 if not shell_last else 0.97, end], [1.00, end],
	], t, true)
	if _left != null:
		_left.position = lh
	if _shell != null:
		_shell.visible = t > 0.22 and t < SHELL_INSERT_T + 0.02
		var shell_tilt := float(_key([[0.22, 0.0], [0.44, 0.95], [0.56, 0.55], [SHELL_INSERT_T, 0.30]], t, true))
		_shell.rotation = Vector3(shell_tilt, 0.0, 0.0)
	# aggressive loading: the weapon is flung into a steep tilt, dips when the shell is pulled from the belt,
	# is hit hard when the shell goes in and rebounds afterwards
	var grab := exp(-pow((t - 0.22) * 15.0, 2.0))
	var snap := exp(-pow((t - SHELL_INSERT_T) * 13.0, 2.0))
	var rebound := exp(-pow((t - 0.80) * 10.0, 2.0))
	holder_offset = (Vector3(-0.07, 0.06, 0.06) + Vector3(0.0, 0.0, 0.085) * snap + Vector3(0.0, -0.012, 0.0) * grab + Vector3(0.0, 0.018, -0.03) * rebound) * tilt_scale
	holder_rotation = Vector3(0.30 - snap * 0.20 + grab * 0.10 - rebound * 0.06, -0.10 + snap * 0.07, -0.66 + snap * 0.15 - grab * 0.06) * tilt_scale
