class_name WeaponSilhouette
extends Control
## A dark side silhouette of the carried weapon (drawn from polygons, one per weapon family) with a faint highlight line.
## Used in the ammo panel; the weapon name drops in above it for a moment when the round starts or the weapon changes.

var weapon_id: String = "ak47"
var tint: Color = Color(0.82, 0.84, 0.86, 0.9)


func _init() -> void:
	custom_minimum_size = Vector2(190, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_weapon(id: String) -> void:
	weapon_id = id
	queue_redraw()


func _draw() -> void:
	var sx := size.x / 190.0
	var sy := size.y / 46.0
	var polys: Array = _shapes(weapon_id)
	for poly in polys:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(Vector2(p.x * sx, p.y * sy))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var shifted := PackedVector2Array()
		for p in pts:
			shifted.append(p + Vector2(0, -1))
		draw_polyline(shifted + PackedVector2Array([shifted[0]]), Color(tint.r, tint.g, tint.b, 0.5), 1.0, true)
		draw_colored_polygon(pts, Color(tint.r, tint.g, tint.b, 0.16))


static func _shapes(id: String) -> Array:
	match id:
		"mp5":
			return [[Vector2(4, 22), Vector2(70, 18), Vector2(150, 18), Vector2(186, 21), Vector2(186, 26), Vector2(150, 27), Vector2(112, 28), Vector2(60, 28), Vector2(4, 28)],
					[Vector2(86, 28), Vector2(100, 28), Vector2(96, 44), Vector2(84, 44)], [Vector2(54, 28), Vector2(70, 28), Vector2(66, 40), Vector2(54, 40)]]
		"shotgun":
			return [[Vector2(2, 20), Vector2(60, 17), Vector2(120, 19), Vector2(188, 21), Vector2(188, 25), Vector2(120, 26), Vector2(60, 29), Vector2(2, 31)],
					[Vector2(96, 26), Vector2(130, 26), Vector2(128, 33), Vector2(98, 33)]]
		"sniper":
			return [[Vector2(2, 20), Vector2(50, 17), Vector2(118, 19), Vector2(188, 21), Vector2(188, 24), Vector2(118, 26), Vector2(50, 29), Vector2(2, 31)],
					[Vector2(60, 8), Vector2(112, 8), Vector2(112, 16), Vector2(60, 16)], [Vector2(88, 26), Vector2(96, 26), Vector2(92, 36), Vector2(86, 36)]]
		"pistol":
			return [[Vector2(70, 14), Vector2(130, 14), Vector2(132, 22), Vector2(112, 22), Vector2(104, 44), Vector2(90, 44), Vector2(92, 22), Vector2(70, 22)]]
	# AK family: long barrel, wooden furniture, curved magazine
	return [[Vector2(2, 22), Vector2(30, 17), Vector2(110, 17), Vector2(188, 20), Vector2(188, 24), Vector2(110, 26), Vector2(66, 27), Vector2(30, 31), Vector2(2, 34)],
			[Vector2(72, 26), Vector2(94, 26), Vector2(104, 44), Vector2(90, 45), Vector2(78, 34)], [Vector2(36, 27), Vector2(50, 27), Vector2(46, 42), Vector2(36, 42)]]
