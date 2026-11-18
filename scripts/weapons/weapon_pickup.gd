class_name WeaponPickup
extends Node3D
## A primary weapon lying on the floor (dropped by a dead player, or put down by a swap). The model lies on its side (thin white outline, label);
## it falls to the floor when spawned; the local player sees "[E] pick up" when close. The Game (host) decides who takes it.

const LIFETIME := 45.0
const PICKUP_RANGE := 2.0
const LABEL_RANGE := 7.0
const FALL_HEIGHT := 0.95 # the weapon drops out of the hand from about this height
const FALL_TIME := 0.42

var pickup_id: int = 0
var weapon_id: String = ""
var magazine: int = 0
var reserve: int = 0
var age: float = 0.0
var _label: Label3D
var _pivot: Node3D
var _outline: StandardMaterial3D
var _rest_y: float = 0.05
var _bounced: bool = false
var _title: String = ""


static func create(id: int, w_id: String, mag: int, res: int, pos: Vector3, yaw: float) -> WeaponPickup:
	var p := WeaponPickup.new()
	p.pickup_id = id
	p.weapon_id = w_id
	p.magazine = mag
	p.reserve = res
	p.position = pos
	p.rotation.y = yaw
	p.add_to_group("weapon_pickups")
	return p


static func weapon_data(w_id: String) -> WeaponData:
	var path := "res://resources/weapons/%s.tres" % w_id
	return load(path) as WeaponData if ResourceLoader.exists(path) else null


func _ready() -> void:
	var data := weapon_data(weapon_id)
	if data == null:
		queue_free()
		return
	_title = data.display_name
	var model: Node3D = data.model_scene.instantiate()
	for n in ["LeftHand", "RightHand"]:
		var h := model.get_node_or_null(n) as Node3D
		if h != null:
			h.visible = false # only the weapon lies there, no floating hands
	model.scale = Vector3.ONE * 1.25
	model.rotation = Vector3(0.0, 0.0, PI * 0.5) # lies on its side
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.add_child(model)
	_outline = StandardMaterial3D.new()
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	_outline.grow_amount = 0.007
	_outline.albedo_color = Color(1, 1, 1, 0.3)
	var lowest := INF
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.visible and mi.mesh != null:
			mi.material_overlay = _outline
			var box := mi.global_transform * mi.mesh.get_aabb()
			lowest = minf(lowest, box.position.y - global_position.y)
	# rest height: the lowest point of the weapon touches the floor
	_rest_y = 0.012 - (lowest if lowest < INF else -0.05)
	_pivot.position.y = _rest_y + FALL_HEIGHT
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.0028
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3(0, 0.6, 0)
	_label.no_depth_test = true
	_label.modulate = Color(1, 0.9, 0.7)
	add_child(_label)
	_update_label(false)


func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	var near := false
	var show := false
	var me := MatchManager.get_local_participant()
	if me != null and me.node != null and is_instance_valid(me.node) and (me.node as Player).alive:
		var d := (me.node as Node3D).global_position.distance_to(global_position)
		near = d <= PICKUP_RANGE + 0.3
		show = d <= LABEL_RANGE
	_label.visible = show
	_update_label(near)
	_animate_fall()
	_outline.albedo_color.a = 0.18 + 0.2 * (0.5 + 0.5 * sin(age * 2.6))
	if age > LIFETIME - 5.0:
		visible = int(age * 5.0) % 2 == 0 # blinks shortly before it vanishes


func _update_label(near: bool) -> void:
	if _label == null:
		return
	var text := "%s  %d | %d" % [_title, magazine, reserve]
	if near:
		text += "\n[E] aufnehmen"
	_label.text = text


## The weapon falls out of the hand, tumbles and lands flat on the floor (one small bounce).
func _animate_fall() -> void:
	if age >= FALL_TIME + 0.2:
		if _pivot.position.y != _rest_y:
			_pivot.position.y = _rest_y
			_pivot.rotation = Vector3.ZERO
		return
	if age < FALL_TIME:
		var k := age / FALL_TIME
		_pivot.position.y = _rest_y + FALL_HEIGHT * (1.0 - k * k)
		var spin := (1.0 - k) * (1.0 - k)
		_pivot.rotation = Vector3(spin * TAU * 0.8, 0.0, spin * 1.4)
		return
	if not _bounced:
		_bounced = true
		AudioManager.play_3d("weapon_switch", global_position, -6.0, 0.15, 30.0)
	var b := (age - FALL_TIME) / 0.2
	_pivot.position.y = _rest_y + 0.05 * sin(b * PI)
	_pivot.rotation = Vector3.ZERO
