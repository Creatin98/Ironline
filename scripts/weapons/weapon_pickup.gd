class_name WeaponPickup
extends Node3D
## A primary weapon lying on the floor (dropped by a dead player, or put down by a swap). The model lies on its side with a
## soft glow and a label; the local player sees "[E] pick up" when close. The Game (host) decides who takes it.

const LIFETIME := 45.0
const PICKUP_RANGE := 2.0
const LABEL_RANGE := 7.0

var pickup_id: int = 0
var weapon_id: String = ""
var magazine: int = 0
var reserve: int = 0
var age: float = 0.0
var _label: Label3D
var _glow: MeshInstance3D
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
	model.position = Vector3(0.0, 0.11, 0.0)
	model.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add_child(model)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.01
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1.0, 0.78, 0.3, 0.22)
	disc.material = gm
	_glow = MeshInstance3D.new()
	_glow.mesh = disc
	_glow.position = Vector3(0, 0.02, 0)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.0028
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3(0, 0.75, 0)
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
	if _glow != null:
		var pulse := 0.5 + 0.5 * sin(age * 3.0)
		(_glow.mesh as CylinderMesh).material.albedo_color.a = 0.14 + 0.16 * pulse
	if age > LIFETIME - 5.0:
		visible = int(age * 5.0) % 2 == 0 # blinks shortly before it vanishes


func _update_label(near: bool) -> void:
	if _label == null:
		return
	var text := "%s  %d | %d" % [_title, magazine, reserve]
	if near:
		text += "\n[E] aufnehmen"
	_label.text = text
