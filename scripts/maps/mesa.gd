extends BlockMap
func _ready() -> void:
	atmosphere_preset = "tropical_storm"
	super._ready()
## MESA – a desert hillside villa estate (own design, three-lane structure in the spirit of classic CoD maps), extended by a
## vineyard wing (west) and a market wing (east) behind gated inner walls: x -42..42, z -28..28.
## Rot spawns north (z < 0), Blau south (z > 0). The map is mirrored across z = 0, so every position is written
## once for the "local" half (z' = distance from the centre line, 0..28) and placed for both teams (sgn).
##
##            x = -32 ......... -14 | -13 ........ 13 | 14 ......... 32
##  z' 28     spawn plaza (team side, behind walls and screens)
##  z' 21.5   garden gate  | rear doors of HALL | yard gate        (walls with 4 m gates)
##  z' 8.5-17 GARDEN       | HALL, 2 storeys    | GARAGE WING (2 storeys + roof terrace)
##            terrace +1.8 | loft with balcony  | catwalk +3.5 along the yard
##            pool, pergola| stairs inside      | service lane x 27..31
##  z' 0-7    open garden  | sunken ATRIUM -1.2 | arcade, garage bays, corridor z -2..2
##
## Lanes: LEFT = garden (open, lush, terrace overwatch at +1.8), MID = hall + sunken atrium (close quarters,
## balconies at +3.5 look into the pit), RIGHT = garage wing (hard, urban, catwalk and roof terrace at +3.5,
## service lane behind). Cross connections: hall side doors, atrium ramps, garage corridor, both stair routes.

const FLOOR_H := 3.2
const SLAB := 0.3
const TOP := 3.5    # upper floor level (top of the slabs)
const UP_H := 3.0
const PIT := -1.2   # floor of the atrium

const C_SAND := Color(0.88, 0.80, 0.66)
const C_WHITE := Color(0.93, 0.91, 0.86)
const C_TERRA := Color(0.82, 0.68, 0.52) # perimeter walls: warm sandstone
const C_WOOD := Color(0.72, 0.56, 0.40)
const C_CEIL := Color(0.9, 0.82, 0.68) # light timber ceilings
const C_DARK := Color(0.26, 0.27, 0.30)
const C_STONE := Color(0.76, 0.70, 0.60)
const C_GRASS := Color(0.62, 0.64, 0.38)
const C_HEDGE := Color(0.36, 0.5, 0.26)
const C_RED := Color(0.78, 0.22, 0.18)
const C_BLUE := Color(0.22, 0.46, 0.82)

var _palms: Array = []
var _bushes: Array = []


# ----------------------------------------------------------------------------- helpers (local frame, sgn = -1 north / +1 south)

func _bx(b: Array, sgn: float, x: float, y: float, z: float, sx: float, sy: float, sz: float, mat: String, tint = null, yaw: float = 0.0) -> void:
	var d := box(Vector3(x, y, sgn * z), Vector3(sx, sy, sz), mat, tint)
	if yaw != 0.0:
		d["rot"] = Vector3(0, rad_to_deg(yaw) * sgn, 0)
	b.append(d)


## Flat decal-like layer on the ground (no collision).
func _ov(b: Array, sgn: float, x: float, z: float, sx: float, sz: float, mat: String, tint = null, y: float = 0.02) -> void:
	var d := box(Vector3(x, y, sgn * z), Vector3(sx, 0.04, sz), mat, tint)
	d["collide"] = false
	b.append(d)


func _rp(b: Array, sgn: float, low: Vector3, high: Vector3, width: float, mat: String, thick: float = 0.3, tint = null) -> void:
	b.append(ramp(Vector3(low.x, low.y, sgn * low.z), Vector3(high.x, high.y, sgn * high.z), width, mat, thick, tint))


func _cyl(b: Array, sgn: float, x: float, y: float, z: float, d: float, h: float, mat: String, tint = null) -> void:
	b.append(cylinder(Vector3(x, y, sgn * z), d, h, mat, tint))


## Room with openings (see room_walls). Local side "n" faces the centre line. Every opening may carry
## "top" (door height, default 2.4) and "sill" (> 0 makes it a window).
func _room(b: Array, sgn: float, cx: float, cz: float, sx: float, sz: float, base_y: float, h: float, mat: String, tint, openings: Array) -> void:
	var world: Array = []
	var c := Vector3(cx, base_y, sgn * cz)
	for o in openings:
		var side: String = o["side"]
		var off: float = o["offset"]
		if sgn < 0.0:
			if side == "n":
				side = "s"
			elif side == "s":
				side = "n"
			else:
				off = -off
		world.append({"side": side, "offset": off, "width": o["width"]})
	b.append_array(room_walls(c, Vector3(sx, h, sz), 0.3, mat, tint, world))
	for i in openings.size():
		var o: Dictionary = openings[i]
		var w: Dictionary = world[i]
		var pos := Vector3.ZERO
		var axis_x := true
		match String(w["side"]):
			"n":
				pos = Vector3(cx + float(w["offset"]), 0, c.z - sz * 0.5)
			"s":
				pos = Vector3(cx + float(w["offset"]), 0, c.z + sz * 0.5)
			"e":
				pos = Vector3(cx + sx * 0.5, 0, c.z + float(w["offset"]))
				axis_x = false
			_:
				pos = Vector3(cx - sx * 0.5, 0, c.z + float(w["offset"]))
				axis_x = false
		b.append(header(pos, w["width"], base_y + float(o.get("top", 2.4)), base_y + h, 0.3, axis_x, mat, tint))
		var sill: float = o.get("sill", 0.0)
		if sill > 0.0:
			b.append(header(pos, w["width"], base_y, base_y + sill, 0.3, axis_x, mat, tint))


func _palm(sgn: float, x: float, z: float, scale: float = 1.0, collide_into: Array = []) -> void:
	_palms.append({"pos": Vector3(x, 0.0, sgn * z), "scale": scale, "yaw": float(_palms.size()) * 1.7, "tilt": 0.03 * float((_palms.size() % 3) - 1)})
	if not collide_into.is_empty():
		collide_into.append({"pos": Vector3(x, 1.5, sgn * z), "size": Vector3(0.45, 3.0, 0.45), "mat": "wood_planks", "shape": "cylinder", "visible": false})


func _bush(sgn: float, x: float, z: float, scale: Vector3, color: Color) -> void:
	_bushes.append({"pos": Vector3(x, 0.32 * scale.y, sgn * z), "scale3": scale, "yaw": float(_bushes.size()) * 2.3, "color": color})


# ----------------------------------------------------------------------------- wings

## West wing "vineyard": a tiled court with a well (z' 0..10), a vineyard terrace at +1.8 (z' 10..20.5) with two stair routes,
## a lane and a cantina (z' 23..28). Reached through the middle gate and the plaza gate of the west wall.
func _wing_west(b: Array, sgn: float) -> void:
	_ov(b, sgn, -37.2, 5.0, 9.4, 10.0, "tiles", Color(0.9, 0.84, 0.7))
	_ov(b, sgn, -35.0, 24.0, 5.0, 8.0, "tiles", Color(0.86, 0.8, 0.66))
	# court: benches, barrels, olive trees
	_bx(b, sgn, -34.6, 0.25, 3.8, 2.6, 0.5, 0.6, "concrete", C_STONE)
	_bx(b, sgn, -40.2, 0.25, 4.2, 2.6, 0.5, 0.6, "concrete", C_STONE)
	_cyl(b, sgn, -41.0, 0.45, 8.4, 0.8, 0.9, "metal_panel", Color(0.5, 0.28, 0.18))
	_cyl(b, sgn, -40.0, 0.45, 8.9, 0.8, 0.9, "metal_panel", Color(0.5, 0.28, 0.18))
	_bx(b, sgn, -41.2, 0.6, 7.0, 1.2, 1.2, 1.2, "crate")
	var extra: Array = []
	_palm(sgn, -40.6, 2.2, 1.0, extra)
	_palm(sgn, -33.6, 8.6, 0.9, extra)
	b.append_array(extra)
	# vineyard terrace A (+1.8): parapets, hedge rows as chest-high cover, two stair routes
	_bx(b, sgn, -37.2, 0.9, 15.25, 9.4, 1.8, 10.5, "concrete", C_STONE)
	_ov(b, sgn, -37.2, 15.25, 9.0, 10.1, "grass", C_GRASS, 1.82)
	_rp(b, sgn, Vector3(-37.2, 0, 6.0), Vector3(-37.2, 1.8, 10.0), 3.0, "concrete", 0.3, C_STONE)
	_rp(b, sgn, Vector3(-34.0, 0, 23.0), Vector3(-34.0, 1.8, 19.0), 2.4, "concrete", 0.3, C_STONE)
	_bx(b, sgn, -40.3, 2.25, 10.15, 3.3, 0.9, 0.3, "concrete", C_WHITE)
	_bx(b, sgn, -34.2, 2.25, 10.15, 3.3, 0.9, 0.3, "concrete", C_WHITE)
	_bx(b, sgn, -38.6, 2.25, 20.35, 6.6, 0.9, 0.3, "concrete", C_WHITE)
	_bx(b, sgn, -39.0, 2.15, 12.6, 5.0, 0.7, 0.6, "grass", C_HEDGE)
	_bx(b, sgn, -35.0, 2.15, 15.4, 5.0, 0.7, 0.6, "grass", C_HEDGE)
	_bx(b, sgn, -39.0, 2.15, 18.2, 5.0, 0.7, 0.6, "grass", C_HEDGE)
	_bx(b, sgn, -41.4, 2.3, 15.4, 1.0, 1.0, 1.4, "crate")
	# cantina (door to the lane in the north, one to the corridor in the east), roof slab, bar and barrels inside
	_room(b, sgn, -38.6, 25.5, 7.2, 5.0, 0.0, 3.0, "plaster", C_WHITE, [
		{"side": "n", "offset": -1.5, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		{"side": "n", "offset": 2.1, "width": 1.2, "sill": 1.0, "top": 2.1}, {"side": "e", "offset": 1.9, "width": 1.0, "sill": 1.0, "top": 2.1},
	])
	_bx(b, sgn, -38.6, 3.15, 25.5, 7.8, SLAB, 5.6, "concrete", Color(0.7, 0.68, 0.64))
	_bx(b, sgn, -40.9, 0.5, 26.4, 0.8, 1.0, 3.2, "wood_planks", C_WOOD)
	_cyl(b, sgn, -41.3, 0.45, 24.1, 0.8, 0.9, "metal_panel", Color(0.5, 0.28, 0.18))
	_bx(b, sgn, -37.2, 0.4, 24.3, 1.4, 0.8, 0.9, "wood_planks", C_WOOD)
	# bushes and flower beds
	_bush(sgn, -41.2, 11.0, Vector3(1.0, 1.0, 1.0), C_HEDGE)
	_bush(sgn, -33.2, 21.6, Vector3(0.9, 0.8, 0.9), Color(0.9, 0.3, 0.5))


## East wing "market": a court with stalls and a van (z' 0..10), a two-storey shop block (z' 10..21) with a roof terrace at +3.5
## (long stair from the court) that is linked to the garage roof by a bridge through the wall; a market lane by the plaza gate.
func _wing_east(b: Array, sgn: float) -> void:
	_ov(b, sgn, 37.2, 5.0, 9.4, 10.0, "tiles", Color(0.82, 0.76, 0.66))
	_ov(b, sgn, 37.5, 24.5, 9.0, 7.0, "asphalt", Color(0.9, 0.86, 0.8))
	# stalls (tables, crates, barrels), a parked van
	_bx(b, sgn, 36.0, 0.5, 4.0, 3.0, 1.0, 1.0, "wood_planks", C_WOOD)
	_bx(b, sgn, 38.0, 0.5, 7.6, 3.0, 1.0, 1.0, "wood_planks", Color(0.62, 0.46, 0.3))
	_bx(b, sgn, 34.2, 0.6, 8.2, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 34.5, 1.8, 8.2, 1.2, 1.2, 1.2, "crate", null, 0.4)
	_bx(b, sgn, 41.0, 0.6, 5.0, 1.2, 1.2, 1.2, "crate")
	_cyl(b, sgn, 33.8, 0.45, 2.6, 0.8, 0.9, "metal_panel", Color(0.2, 0.32, 0.5))
	b.append_array(car(Vector3(35.4, 0, sgn * 1.6 + sgn * 0.0), Color(0.9, 0.62, 0.15), 0.0 if sgn > 0.0 else 180.0))
	# shop block: ground floor with arcade-like openings to the court and an alley door at the back, roof terrace +3.5
	_room(b, sgn, 38.2, 15.5, 7.4, 11.0, 0.0, FLOOR_H, "plaster", C_SAND, [
		{"side": "n", "offset": -2.2, "width": 2.4, "top": 2.8}, {"side": "n", "offset": 2.4, "width": 1.6},
		{"side": "w", "offset": -3.0, "width": 2.0}, {"side": "w", "offset": 3.0, "width": 1.6, "sill": 1.0, "top": 2.2},
		{"side": "s", "offset": 0.0, "width": 1.8}, {"side": "n", "offset": -0.3, "width": 1.0, "sill": 1.0, "top": 2.1},
	])
	_bx(b, sgn, 38.2, 0.4, 15.5, 1.6, 0.8, 1.0, "wood_planks", C_WOOD) # shop counter
	_bx(b, sgn, 40.4, 0.6, 18.8, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 38.2, 3.35, 15.5, 7.9, SLAB, 11.4, "concrete", Color(0.72, 0.7, 0.66))
	_bx(b, sgn, 34.3, TOP + 0.5, 16.45, 0.2, 1.0, 9.5, "concrete", C_WHITE) # (west edge open at z' 9.8..11.3: the bridge)
	_bx(b, sgn, 42.0, TOP + 0.5, 15.5, 0.2, 1.0, 11.4, "concrete", C_WHITE)
	_bx(b, sgn, 38.2, TOP + 0.5, 21.1, 7.9, 1.0, 0.2, "concrete", C_WHITE)
	_bx(b, sgn, 37.3, TOP + 0.5, 9.9, 4.2, 1.0, 0.2, "concrete", C_WHITE) # north parapet (the stair arrives right of it)
	_cyl(b, sgn, 40.3, TOP + 1.0, 18.6, 2.0, 2.0, "metal_panel", Color(0.78, 0.8, 0.82)) # water tank
	_bx(b, sgn, 36.6, TOP + 0.6, 18.4, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 36.4, TOP + 0.45, 12.6, 1.8, 0.9, 0.5, "concrete", C_STONE)
	_bx(b, sgn, 40.2, TOP + 0.45, 13.0, 0.5, 0.9, 2.2, "concrete", C_STONE)
	# long stair from the court up to the roof (east side) and the bridge to the garage roof
	_rp(b, sgn, Vector3(40.6, 0, 3.0), Vector3(40.6, TOP, 10.0), 2.0, "metal_panel", 0.3, C_DARK)
	_rp(b, sgn, Vector3(41.65, 1.0, 3.0), Vector3(41.65, TOP + 1.0, 10.0), 0.1, "metal_panel", 1.0, C_DARK)
	_rp(b, sgn, Vector3(39.55, 1.0, 3.0), Vector3(39.55, TOP + 1.0, 10.0), 0.1, "metal_panel", 1.0, C_DARK)
	_bx(b, sgn, 30.8, 3.35, 10.3, 7.3, SLAB, 2.4, "metal_panel", C_DARK)
	_bx(b, sgn, 30.8, TOP + 0.5, 9.15, 7.3, 1.0, 0.1, "metal_panel", C_DARK)
	_bx(b, sgn, 30.8, TOP + 0.5, 11.45, 7.3, 1.0, 0.1, "metal_panel", C_DARK)
	# market lane: crates and a flatbed by the plaza gate, palms
	_bx(b, sgn, 36.5, 0.6, 22.8, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 40.8, 0.45, 25.0, 1.4, 0.9, 3.0, "concrete", C_STONE)
	b.append_array(car(Vector3(38.2, 0, sgn * 26.6), Color(0.3, 0.4, 0.34), 90.0))
	var extra: Array = []
	_palm(sgn, 41.0, 22.0, 1.0, extra)
	_palm(sgn, 33.8, 27.0, 1.1, extra)
	b.append_array(extra)
	_bush(sgn, 34.0, 21.8, Vector3(1.0, 0.8, 1.0), Color(0.95, 0.75, 0.25))


## Features on the middle line (not mirrored): the well of the vineyard court and the fountain of the market court.
func _court_centres(b: Array) -> void:
	b.append(cylinder(Vector3(-37.2, 0.45, 0.0), 2.6, 0.9, "concrete", C_WHITE))
	b.append({"pos": Vector3(-37.2, 1.7, 0.0), "size": Vector3(0.4, 1.6, 0.4), "mat": "wood_planks", "shape": "cylinder", "visible": false})
	b.append(cylinder(Vector3(37.2, 0.35, 0.0), 3.0, 0.7, "concrete", C_STONE))


# ----------------------------------------------------------------------------- blocks

func get_blocks() -> Array:
	_palms.clear()
	_bushes.clear()
	var b: Array = []
	_ground(b)
	_atrium(b)
	for sgn in [-1.0, 1.0]:
		_hall(b, sgn)
		_garden(b, sgn)
		_garage(b, sgn)
		_plaza(b, sgn)
		_wing_west(b, sgn)
		_wing_east(b, sgn)
	_court_centres(b)
	return b


func _ground(b: Array) -> void:
	for sgn in [-1.0, 1.0]:
		_bx(b, sgn, 0, -1.0, 17.5, 84, 2.0, 21, "concrete", C_STONE)
	b.append(box(Vector3(-24.5, -1.0, 0), Vector3(35, 2.0, 14), "concrete", C_STONE))
	b.append(box(Vector3(24.5, -1.0, 0), Vector3(35, 2.0, 14), "concrete", C_STONE))
	b.append(box(Vector3(0, PIT - 1.0, 0), Vector3(14, 2.0, 14), "tiles", C_SAND))
	# outer perimeter walls (6 m, jump-proof) in warm sandstone
	b.append(box(Vector3(-42.25, 3, 0), Vector3(0.5, 6, 57), "plaster", C_TERRA))
	b.append(box(Vector3(42.25, 3, 0), Vector3(0.5, 6, 57), "plaster", C_TERRA))
	b.append(box(Vector3(0, 3, -28.25), Vector3(85, 6, 0.5), "plaster", C_TERRA))
	b.append(box(Vector3(0, 3, 28.25), Vector3(85, 6, 0.5), "plaster", C_TERRA))
	_inner_walls(b)


## The old outer walls (x = +-32.25) now separate the estate from the two wings. Gates: a 4 m gate in the middle (z -2..2),
## a 4 m gate next to each spawn plaza (z' 23..27) and, on the east wall, a 2.8 m passage under the rooftop bridge (z' 8.8..11.6).
func _inner_walls(b: Array) -> void:
	for sx in [-1.0, 1.0]:
		var x: float = sx * 32.25
		for sgn in [-1.0, 1.0]:
			var segs: Array = [[2.0, 23.0], [27.0, 28.5]]
			if sx > 0.0:
				segs = [[2.0, 8.8], [11.6, 23.0], [27.0, 28.5]]
			for sg in segs:
				b.append(box(Vector3(x, 3.0, sgn * (float(sg[0]) + float(sg[1])) * 0.5), Vector3(0.5, 6.0, float(sg[1]) - float(sg[0])), "plaster", C_TERRA))
			b.append(header(Vector3(x, 0, sgn * 25.0), 4.0, 3.2, 6.0, 0.5, false, "plaster", C_TERRA))
		b.append(header(Vector3(x, 0, 0), 4.0, 3.2, 6.0, 0.5, false, "plaster", C_TERRA))
	for sgn in [-1.0, 1.0]:
		b.append(header(Vector3(32.25, 0, sgn * 10.2), 2.8, 5.6, 6.0, 0.5, false, "plaster", C_TERRA))


## Sunken atrium (14 x 14 m, -1.2 m) with four ramps, a fountain, corner planters and a pergola on the rim.
func _atrium(b: Array) -> void:
	b.append(ramp(Vector3(3, PIT, 0), Vector3(7, 0, 0), 3.2, "concrete", 0.3, C_STONE))
	b.append(ramp(Vector3(-3, PIT, 0), Vector3(-7, 0, 0), 3.2, "concrete", 0.3, C_STONE))
	b.append(ramp(Vector3(0, PIT, 3), Vector3(0, 0, 7), 3.2, "concrete", 0.3, C_STONE))
	b.append(ramp(Vector3(0, PIT, -3), Vector3(0, 0, -7), 3.2, "concrete", 0.3, C_STONE))
	b.append(cylinder(Vector3(0, PIT + 0.5, 0), 3.2, 1.0, "concrete", C_WHITE))
	var water := box(Vector3(0, PIT + 0.92, 0), Vector3(2.7, 0.1, 2.7), "water")
	water["shape"] = "cylinder"
	water["collide"] = false
	b.append(water)
	b.append({"pos": Vector3(0, PIT + 2.0, 0), "size": Vector3(0.5, 3.0, 0.5), "mat": "wood_planks", "shape": "cylinder", "visible": false})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.append(box(Vector3(sx * 4.2, PIT + 0.45, sz * 4.2), Vector3(2.2, 0.9, 2.2), "concrete", C_WHITE))
			var top := box(Vector3(sx * 4.2, PIT + 0.92, sz * 4.2), Vector3(2.0, 0.06, 2.0), "grass", C_GRASS)
			top["collide"] = false
			b.append(top)
			_bushes.append({"pos": Vector3(sx * 4.2, PIT + 1.3, sz * 4.2), "scale3": Vector3(1.7, 1.5, 1.7), "yaw": sx + sz, "color": C_HEDGE})
			# pergola columns on the rim
			b.append(box(Vector3(sx * 8.2, 1.65, sz * 7.8), Vector3(0.5, 3.3, 0.5), "concrete", C_WHITE))
	_palms.append({"pos": Vector3(0, PIT + 1.0, 0), "scale": 0.6, "yaw": 0.4, "tilt": 0.0})


func _hall(b: Array, sgn: float) -> void:
	# ground floor: three rooms (salon in the middle), doors to the atrium, the plaza, both flanks
	_room(b, sgn, 0, 12.75, 26, 8.5, 0.0, FLOOR_H, "plaster", C_SAND, [
		{"side": "n", "offset": 0.0, "width": 3.2, "top": 2.8},
		{"side": "n", "offset": -9.5, "width": 1.6}, {"side": "n", "offset": 9.5, "width": 1.6},
		{"side": "s", "offset": -9.0, "width": 2.0}, {"side": "s", "offset": 9.0, "width": 2.0},
		{"side": "s", "offset": 0.0, "width": 1.6, "sill": 1.0, "top": 2.2},
		{"side": "e", "offset": 0.0, "width": 2.4}, {"side": "w", "offset": 0.0, "width": 2.4},
		{"side": "e", "offset": 3.0, "width": 1.2, "sill": 0.9, "top": 2.1}, {"side": "w", "offset": 3.0, "width": 1.2, "sill": 0.9, "top": 2.1},
	])
	for sx in [-4.5, 4.5]:
		_bx(b, sgn, sx, FLOOR_H * 0.5, 10.025, 0.25, FLOOR_H, 2.75, "plaster", C_WHITE)
		_bx(b, sgn, sx, FLOOR_H * 0.5, 15.475, 0.25, FLOOR_H, 2.75, "plaster", C_WHITE)
		b.append(header(Vector3(sx, 0, sgn * 12.75), 2.7, 2.4, FLOOR_H, 0.25, false, "plaster", C_WHITE))
	# furniture
	_bx(b, sgn, 0, 0.3, 14.9, 3.2, 0.6, 1.0, "plaster", C_DARK)          # sofa
	_bx(b, sgn, 0, 0.22, 12.4, 1.4, 0.45, 0.8, "wood_planks", C_WOOD)    # coffee table
	_bx(b, sgn, 9.5, 0.48, 16.4, 3.0, 0.95, 0.7, "wood_planks", C_WOOD)  # kitchen counter
	_bx(b, sgn, 9.0, 0.4, 12.4, 1.6, 0.8, 1.0, "wood_planks", C_WOOD)    # table
	_bx(b, sgn, -12.7, 1.1, 9.8, 0.4, 2.2, 2.4, "wood_planks", C_WOOD)   # bookcase
	_bx(b, sgn, -5.6, 0.35, 16.0, 1.0, 0.7, 1.8, "plaster", C_DARK)      # armchair
	# upper floor slabs with the stair well (west room), balcony over the atrium
	_bx(b, sgn, -11.575, 3.35, 12.75, 3.15, SLAB, 8.8, "wood_planks", C_CEIL)
	_bx(b, sgn, 3.075, 3.35, 12.75, 20.15, SLAB, 8.8, "wood_planks", C_CEIL)
	_bx(b, sgn, -8.5, 3.35, 16.075, 3.0, SLAB, 2.15, "wood_planks", C_CEIL)
	_bx(b, sgn, -8.5, 3.35, 8.675, 3.0, SLAB, 0.65, "wood_planks", C_CEIL)
	_rp(b, sgn, Vector3(-8.5, 0, 9.2), Vector3(-8.5, TOP, 15.0), 3.0, "wood_planks", 0.3, C_WOOD)
	_bx(b, sgn, -10.05, TOP + 0.5, 12.0, 0.1, 1.0, 6.0, "metal_panel", C_DARK)
	_bx(b, sgn, -6.95, TOP + 0.5, 12.0, 0.1, 1.0, 6.0, "metal_panel", C_DARK)
	_bx(b, sgn, -8.5, TOP + 0.5, 9.05, 3.0, 1.0, 0.1, "metal_panel", C_DARK)
	_bx(b, sgn, 0, 3.35, 7.475, 10.0, SLAB, 1.75, "wood_planks", C_CEIL)
	_bx(b, sgn, 0, TOP + 0.5, 6.65, 10.0, 1.0, 0.1, "metal_panel", C_WHITE)
	for sx in [-5.0, 5.0]:
		_bx(b, sgn, sx, TOP + 0.5, 7.5, 0.1, 1.0, 1.8, "metal_panel", C_WHITE)
		_bx(b, sgn, sx * 0.96, 1.6, 6.8, 0.4, 3.2, 0.4, "concrete", C_WHITE)
	# upper rooms
	_room(b, sgn, 0, 12.75, 26, 8.5, TOP, UP_H, "plaster", C_WHITE, [
		{"side": "n", "offset": 0.0, "width": 9.0, "top": 2.6},
		{"side": "n", "offset": -9.5, "width": 1.6, "sill": 0.9, "top": 2.1}, {"side": "n", "offset": 9.5, "width": 1.6, "sill": 0.9, "top": 2.1},
		{"side": "s", "offset": -9.0, "width": 1.8, "sill": 0.9, "top": 2.1}, {"side": "s", "offset": 9.0, "width": 1.8, "sill": 0.9, "top": 2.1},
		{"side": "s", "offset": 0.0, "width": 1.8, "sill": 0.9, "top": 2.1},
		{"side": "e", "offset": 0.0, "width": 1.8}, {"side": "w", "offset": 0.0, "width": 1.8},
	])
	for sx in [-4.5, 4.5]:
		_bx(b, sgn, sx, TOP + UP_H * 0.5, 10.025, 0.25, UP_H, 2.75, "plaster", C_WHITE)
		_bx(b, sgn, sx, TOP + UP_H * 0.5, 15.475, 0.25, UP_H, 2.75, "plaster", C_WHITE)
		b.append(header(Vector3(sx, 0, sgn * 12.75), 2.7, TOP + 2.4, TOP + UP_H, 0.25, false, "plaster", C_WHITE))
	_bx(b, sgn, 8.5, TOP + 0.45, 16.2, 3.0, 0.9, 0.6, "wood_planks", C_WOOD)   # loft sideboard
	_bx(b, sgn, 0, TOP + 0.4, 14.6, 2.6, 0.8, 1.0, "plaster", C_DARK)          # loft sofa
	_bx(b, sgn, 0, 6.65, 12.75, 26.6, SLAB, 9.1, "concrete", Color(0.7, 0.68, 0.64))
	# west exterior stair + landing to the loft (garden side)
	_bx(b, sgn, -14.4, 3.35, 12.75, 2.5, SLAB, 2.5, "metal_panel", C_DARK)
	_rp(b, sgn, Vector3(-14.4, 0, 20.0), Vector3(-14.4, TOP, 14.0), 2.0, "metal_panel", 0.3, C_DARK)
	_rp(b, sgn, Vector3(-15.45, 1.0, 20.0), Vector3(-15.45, TOP + 1.0, 14.0), 0.1, "metal_panel", 1.0, C_DARK)
	_bx(b, sgn, -15.7, TOP + 0.5, 12.75, 0.1, 1.0, 2.6, "metal_panel", C_DARK)
	_bx(b, sgn, -14.4, TOP + 0.5, 11.55, 2.5, 1.0, 0.1, "metal_panel", C_DARK)
	# east catwalk (hall loft -> garage terrace) with the yard stair
	_bx(b, sgn, 18.575, 3.35, 11.85, 10.85, SLAB, 2.7, "metal_panel", C_DARK)
	_bx(b, sgn, 18.575, TOP + 0.5, 13.15, 10.85, 1.0, 0.1, "metal_panel", C_DARK)
	_rp(b, sgn, Vector3(30.0, 0, 12.2), Vector3(24.0, TOP, 12.2), 2.0, "metal_panel", 0.3, C_DARK)
	_rp(b, sgn, Vector3(30.0, 1.0, 13.25), Vector3(24.0, TOP + 1.0, 13.25), 0.1, "metal_panel", 1.0, C_DARK)
	# rear screen walls (no sight from the atrium into the spawn through the rear doors)
	for sx in [-9.0, 9.0]:
		_bx(b, sgn, sx, 1.3, 19.2, 4.0, 2.6, 0.4, "plaster", C_SAND)


func _garden(b: Array, sgn: float) -> void:
	# ground
	_ov(b, sgn, -23.0, 12.0, 18.0, 19.0, "grass", C_GRASS)
	_ov(b, sgn, -17.5, 11.0, 3.0, 20.0, "concrete", Color(0.86, 0.82, 0.74), 0.03)
	# sun terrace (+1.8) with parapets, pergola posts and two ramps
	_bx(b, sgn, -27.5, 0.9, 7.0, 9.0, 1.8, 10.0, "concrete", C_STONE)
	_ov(b, sgn, -27.5, 7.0, 8.6, 9.6, "grass", C_GRASS, 1.82)
	_rp(b, sgn, Vector3(-27.5, 0, 17.0), Vector3(-27.5, 1.8, 12.0), 3.0, "concrete", 0.3, C_STONE)
	_rp(b, sgn, Vector3(-19.5, 0, 7.0), Vector3(-23.0, 1.8, 7.0), 3.0, "concrete", 0.3, C_STONE)
	_bx(b, sgn, -29.5, 2.25, 2.15, 5.0, 0.9, 0.3, "concrete", C_WHITE)
	_bx(b, sgn, -24.25, 2.25, 2.15, 2.5, 0.9, 0.3, "concrete", C_WHITE)
	_bx(b, sgn, -23.15, 2.25, 10.5, 0.3, 0.9, 3.0, "concrete", C_WHITE)
	_bx(b, sgn, -23.15, 2.25, 3.6, 0.3, 0.9, 2.8, "concrete", C_WHITE)
	_bx(b, sgn, -26.0, 2.25, 12.15, 4.0, 0.9, 0.3, "concrete", C_WHITE)
	for p in [Vector2(-30.0, 4.0), Vector2(-25.0, 4.0), Vector2(-30.0, 10.0), Vector2(-25.0, 10.0)]:
		_bx(b, sgn, p.x, 3.2, p.y, 0.3, 2.8, 0.3, "wood_planks", C_WOOD)
	_bx(b, sgn, -31.0, 2.25, 7.0, 0.7, 0.9, 1.6, "wood_planks", C_WOOD)   # bench on the terrace
	# pool (shallow, walkable), sun beds, hedges, boulders
	_bx(b, sgn, -21.0, 0.2, 15.5, 6.0, 0.4, 3.5, "water")
	_bx(b, sgn, -24.4, 0.25, 15.0, 0.8, 0.5, 2.0, "plaster", C_WHITE)
	_bx(b, sgn, -24.4, 0.25, 17.2, 0.8, 0.5, 2.0, "plaster", C_WHITE)
	_bx(b, sgn, -19.6, 0.55, 4.5, 0.9, 1.1, 4.0, "grass", C_HEDGE)
	_bx(b, sgn, -19.6, 0.55, 12.0, 0.9, 1.1, 3.0, "grass", C_HEDGE)
	_bx(b, sgn, -30.4, 0.7, 14.0, 1.8, 1.4, 1.6, "concrete", Color(0.7, 0.58, 0.45), 0.5)
	_bx(b, sgn, -21.5, 0.5, 9.5, 1.6, 1.0, 1.4, "concrete", Color(0.68, 0.58, 0.46), 1.2)
	_bx(b, sgn, -31.0, 0.6, 20.0, 1.2, 1.2, 1.2, "crate")
	# pool house (open on three sides) and the garden wall with a 4 m gate
	_room(b, sgn, -27.5, 19.5, 7.0, 4.0, 0.0, 2.9, "plaster", C_WHITE, [
		{"side": "n", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 2.0},
		{"side": "w", "offset": 0.0, "width": 1.2, "sill": 1.0, "top": 2.1},
		{"side": "n", "offset": -2.4, "width": 1.2, "sill": 1.0, "top": 2.1},
	])
	_bx(b, sgn, -27.5, 3.05, 19.5, 7.6, SLAB, 4.6, "concrete", Color(0.68, 0.66, 0.62))
	_bx(b, sgn, -22.0, 1.2, 21.5, 4.0, 2.4, 0.4, "plaster", C_SAND)
	_bx(b, sgn, -14.5, 1.2, 21.5, 3.0, 2.4, 0.4, "plaster", C_SAND)
	# vegetation (trunks collide as cover)
	var extra: Array = []
	_palm(sgn, -30.5, 8.0, 1.1, extra)
	_palm(sgn, -17.8, 20.2, 1.0, extra)
	_palm(sgn, -23.0, 11.0, 1.2, extra)
	_palm(sgn, -31.0, 17.5, 0.9, extra)
	b.append_array(extra)
	for p in [Vector3(-18.6, 0, 9.0), Vector3(-30.5, 0, 12.0), Vector3(-26.5, 0, 21.0), Vector3(-24.0, 0, 3.0), Vector3(-16.5, 0, 3.0)]:
		_bush(sgn, p.x, p.z, Vector3(1.8, 1.5, 1.6), C_HEDGE)
	for p in [Vector3(-31.4, 0, 3.0), Vector3(-31.4, 0, 12.5), Vector3(-31.4, 0, 18.0), Vector3(-13.6, 0, 21.0)]:
		_bush(sgn, p.x, p.z, Vector3(1.5, 1.8, 1.4), Color(0.88, 0.26, 0.5))


func _garage(b: Array, sgn: float) -> void:
	# ground floor: two bays facing the atrium arcade, doors to the corridor, the yard and the service lane
	_room(b, sgn, 22.0, 6.5, 10.0, 9.0, 0.0, FLOOR_H, "concrete", Color(0.8, 0.78, 0.72), [
		{"side": "w", "offset": -2.4, "width": 3.0, "top": 2.7}, {"side": "w", "offset": 2.4, "width": 3.0, "top": 2.7},
		{"side": "n", "offset": 0.0, "width": 2.0}, {"side": "e", "offset": 0.0, "width": 2.0},
		{"side": "s", "offset": -3.0, "width": 2.0}, {"side": "s", "offset": 3.0, "width": 2.0},
		{"side": "n", "offset": 3.4, "width": 1.2, "sill": 1.0, "top": 2.2},
	])
	b.append_array(car(Vector3(21.0, 0, sgn * 4.6), C_BLUE, 90.0 * sgn))
	_bx(b, sgn, 24.5, 0.5, 9.9, 3.0, 1.0, 0.7, "wood_planks", C_WOOD)    # workbench
	_bx(b, sgn, 25.9, 0.6, 3.1, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 24.7, 0.6, 3.3, 1.2, 1.2, 1.2, "crate", null, 0.4)
	_bx(b, sgn, 22.0, 1.6, 7.6, 0.5, 3.2, 0.5, "concrete", C_WHITE)         # column
	_cyl(b, sgn, 18.0, 0.45, 10.3, 0.7, 0.9, "metal_panel", C_BLUE * 0.7)    # barrels
	_cyl(b, sgn, 18.8, 0.45, 10.4, 0.7, 0.9, "metal_panel", C_RED * 0.8)
	# roof terrace (+3.5): parapets, pavilion, cover
	_bx(b, sgn, 22.0, 3.35, 6.5, 10.3, SLAB, 9.3, "concrete", Color(0.72, 0.7, 0.66))
	_bx(b, sgn, 16.9, TOP + 0.5, 6.5, 0.2, 1.0, 9.3, "concrete", C_WHITE)
	_bx(b, sgn, 22.0, TOP + 0.5, 1.9, 10.3, 1.0, 0.2, "concrete", C_WHITE)
	_bx(b, sgn, 27.1, TOP + 0.5, 5.475, 0.2, 1.0, 7.25, "concrete", C_WHITE) # (gap z' 9.3..11.05: the bridge to the market roof)
	_bx(b, sgn, 25.6, TOP + 0.5, 11.05, 3.1, 1.0, 0.2, "concrete", C_WHITE)
	_room(b, sgn, 25.0, 4.25, 4.0, 3.5, TOP, 2.6, "plaster", C_WHITE, [
		{"side": "w", "offset": 0.0, "width": 1.6, "top": 2.2}, {"side": "s", "offset": 0.0, "width": 1.4, "sill": 0.9, "top": 2.0},
	])
	_bx(b, sgn, 25.0, TOP + 2.75, 4.25, 4.6, SLAB, 4.1, "concrete", Color(0.66, 0.64, 0.6))
	_bx(b, sgn, 19.0, TOP + 0.6, 3.6, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 20.3, TOP + 0.6, 3.3, 1.2, 1.2, 1.2, "crate", null, 0.3)
	_bx(b, sgn, 20.5, TOP + 0.45, 8.0, 3.0, 0.9, 0.3, "concrete", C_STONE)
	# yard: carport, crates, low walls, tank, van
	for p in [Vector2(22.0, 16.5), Vector2(26.0, 16.5), Vector2(22.0, 19.5), Vector2(26.0, 19.5)]:
		_bx(b, sgn, p.x, 1.55, p.y, 0.35, 3.1, 0.35, "metal_panel", C_DARK)
	_bx(b, sgn, 24.0, 3.2, 18.0, 5.4, 0.25, 4.4, "metal_panel", C_WHITE)
	_bx(b, sgn, 17.5, 0.6, 15.0, 1.2, 1.2, 1.2, "crate")
	_bx(b, sgn, 17.5, 1.8, 15.0, 1.2, 1.2, 1.2, "crate", null, 0.5)
	_bx(b, sgn, 30.0, 0.5, 15.2, 3.5, 1.0, 0.4, "concrete", C_STONE)
	_bx(b, sgn, 15.0, 0.5, 17.0, 0.4, 1.0, 3.0, "concrete", C_STONE)
	_cyl(b, sgn, 30.7, 1.3, 19.8, 2.0, 2.6, "metal_panel", C_WHITE)
	b.append_array(car(Vector3(24.0, 0, sgn * 18.0), C_RED, 0.0))
	# yard wall with gates (x 16..20 and the service lane x 27..32)
	_bx(b, sgn, 14.5, 1.2, 21.5, 3.0, 2.4, 0.4, "plaster", C_SAND)
	_bx(b, sgn, 23.5, 1.2, 21.5, 7.0, 2.4, 0.4, "plaster", C_SAND)
	_palm(sgn, 16.0, 13.0, 1.0)
	_palm(sgn, 29.5, 6.0, 1.15)
	_bush(sgn, 31.4, 10.0, Vector3(1.6, 1.6, 1.8), C_HEDGE)
	_bush(sgn, 31.4, 17.0, Vector3(1.6, 1.8, 1.8), Color(0.88, 0.26, 0.5))
	_bush(sgn, 11.0, 5.0, Vector3(1.6, 1.3, 1.6), C_HEDGE)


func _plaza(b: Array, sgn: float) -> void:
	_ov(b, sgn, 0.0, 24.75, 44.0, 6.5, "asphalt", Color(0.9, 0.86, 0.8))
	_ov(b, sgn, 0.0, 27.4, 14.0, 0.5, "plaster", C_RED if sgn < 0.0 else C_BLUE, 0.05)
	_bx(b, sgn, 0.0, 0.5, 22.4, 3.0, 1.0, 1.2, "concrete", C_WHITE)           # centre planter
	_bx(b, sgn, -14.5, 0.45, 24.5, 1.2, 0.9, 4.0, "concrete", C_STONE)        # benches / planters
	_bx(b, sgn, 14.5, 0.45, 24.5, 1.2, 0.9, 4.0, "concrete", C_STONE)
	_bx(b, sgn, -6.0, 0.6, 21.9, 2.4, 1.2, 0.8, "concrete", C_WHITE)
	_bx(b, sgn, 6.0, 0.6, 21.9, 2.4, 1.2, 0.8, "concrete", C_WHITE)
	_palm(sgn, 0.0, 22.4, 1.1)
	_palm(sgn, -20.0, 26.0, 1.0)
	_palm(sgn, 20.0, 26.0, 1.2)


func get_spawns() -> Array:
	var s: Array = []
	for x in [-11.0, -6.5, -2.0, 2.0, 6.5, 11.0]:
		s.append(spawn(Vector3(x, 0.1, -24.5), 180.0, Teams.Team.RED))
	for x in [-11.0, -6.5, -2.0, 2.0, 6.5, 11.0]:
		s.append(spawn(Vector3(x, 0.1, 24.5), 0.0, Teams.Team.BLUE))
	# free-for-all extras: atrium, loft, garage terrace, sun terrace, garden, yard
	for sgn in [-1.0, 1.0]:
		var yaw := 0.0 if sgn > 0.0 else 180.0
		s.append(spawn(Vector3(-5.8, PIT + 0.1, sgn * 2.6), 270.0, Teams.Team.NONE))
		s.append(spawn(Vector3(8.5, TOP + 0.1, sgn * 12.75), yaw, Teams.Team.NONE))
		s.append(spawn(Vector3(20.0, TOP + 0.1, sgn * 5.0), yaw, Teams.Team.NONE))
		s.append(spawn(Vector3(-27.5, 1.9, sgn * 7.0), yaw, Teams.Team.NONE))
		s.append(spawn(Vector3(-17.5, 0.1, sgn * 14.0), yaw, Teams.Team.NONE))
		s.append(spawn(Vector3(20.5, 0.1, sgn * 15.0), yaw, Teams.Team.NONE))
	return s


func get_lanes() -> Dictionary:
	var left: Array[Vector3] = []
	var mid: Array[Vector3] = []
	var right: Array[Vector3] = []
	var roof: Array[Vector3] = []
	for z in [-24.0, -22.5, -12.0, -4.0, 0.0, 4.0, 12.0, 22.5, 24.0]:
		left.append(Vector3(-12.0 if absf(z) >= 24.0 else -17.0, 0, z))
	mid = [Vector3(3.5, 0, -23.5), Vector3(6, 0, -18.4), Vector3(6, 0, -12.75), Vector3(2.2, 0, -12.75), Vector3(0, 0, -9.5),
		Vector3(5.8, PIT, -2.4), Vector3(5.8, PIT, 2.4), Vector3(0, 0, 9.5), Vector3(2.2, 0, 12.75), Vector3(6, 0, 12.75),
		Vector3(6, 0, 18.4), Vector3(3.5, 0, 23.5)]
	right = [Vector3(12, 0, -24), Vector3(18, 0, -22.5), Vector3(20.5, 0, -16), Vector3(20.5, 0, -12), Vector3(14, 0, -6),
		Vector3(14, 0, 0), Vector3(14, 0, 6), Vector3(20.5, 0, 12), Vector3(20.5, 0, 16), Vector3(18, 0, 22.5), Vector3(12, 0, 24)]
	roof = [Vector3(6, TOP, -13), Vector3(20, TOP, -7), Vector3(-27.5, 1.8, -7), Vector3(-27.5, 1.8, 7), Vector3(20, TOP, 7), Vector3(6, TOP, 13)]
	var wing_w: Array[Vector3] = []
	var wing_e: Array[Vector3] = []
	for sgn in [-1.0, 1.0]:
		wing_w.append_array([Vector3(-37.0, 0, sgn * 3.5), Vector3(-34.8, 1.8, sgn * 12.6), Vector3(-38.5, 1.8, sgn * 15.4), Vector3(-34.8, 1.8, sgn * 18.2), Vector3(-33.8, 0, sgn * 21.8), Vector3(-34.0, 0, sgn * 25.5)])
		wing_e.append_array([Vector3(38.0, 0, sgn * 6.4), Vector3(33.4, 0, sgn * 15.0), Vector3(36.0, TOP, sgn * 14.5), Vector3(38.5, TOP, sgn * 17.4), Vector3(30.8, TOP, sgn * 10.3), Vector3(35.0, 0, sgn * 24.5)])
	return {"left": left, "mid": mid, "right": right, "roof": roof, "wing_west": wing_w, "wing_east": wing_e}


func get_cover_points() -> Array:
	return [
		Vector3(-5.8, PIT, -2.4), Vector3(5.8, PIT, 2.4), Vector3(-5.8, PIT, 2.4), Vector3(5.8, PIT, -2.4),
		Vector3(-12.0, 0, 7.5), Vector3(12.0, 0, -7.5), Vector3(-18.5, 0, -6.0), Vector3(14.5, 0, 6.5),
		Vector3(-27.5, 1.8, -9.0), Vector3(-27.5, 1.8, 9.0), Vector3(20, TOP, -9.5), Vector3(20, TOP, 9.5),
		Vector3(6, 0, -14.5), Vector3(-6, 0, 14.5), Vector3(24.5, 0, 14.0), Vector3(-24.5, 0, -13.0),
		Vector3(-35.0, 1.8, -14.4), Vector3(-39.0, 1.8, 16.6), Vector3(36.0, TOP, -13.5), Vector3(38.0, TOP, 19.0), Vector3(36.0, 0, -5.2), Vector3(-40.0, 0, 5.8),
	]


# ----------------------------------------------------------------------------- visual extras

func build_detail(d: MapDetail) -> void:
	# light atmosphere: warm string lights along the pergolas, glowing pool, uplit fountain and palms, balcony lights
	for sgn in [-1.0, 1.0]:
		for i in range(-5, 6):
			if absf(float(i)) >= 3.5:
				d.bulb(Vector3(float(i) * 1.55, 3.18, sgn * 7.8), Color(1.0, 0.72, 0.38), 0.9, 0.5, 3.0)
		d.bulb(Vector3(-21.0, 0.3, sgn * 15.5), Color(0.2, 0.9, 1.0), 3.2, 3.0, 8.0) # pool light
		d.bulb(Vector3(-18.4, 0.25, sgn * 15.5), Color(0.2, 0.9, 1.0), 1.4, 1.2, 4.0)
		d.bulb(Vector3(0.0, 3.6, sgn * 6.9), Color(1.0, 0.8, 0.5), 1.8, 1.5, 6.0) # under the balcony
		d.bulb(Vector3(-12.2, 0.25, sgn * 8.0), Color(1.0, 0.65, 0.3), 1.2, 1.0, 4.0) # palm uplights
		d.bulb(Vector3(-17.2, 0.25, sgn * 20.0), Color(1.0, 0.65, 0.3), 1.2, 1.0, 4.0)
		d.bulb(Vector3(25.0, TOP + 2.2, sgn * 6.0), Color(0.6, 0.9, 1.0), 1.0, 1.0, 5.0)
	d.bulb(Vector3(0, -0.1, 0), Color(1.0, 0.75, 0.45), 2.6, 3.0, 8.0) # fountain
	d.bulb(Vector3(4.2, -0.15, 4.2), Color(1.0, 0.7, 0.4), 1.4, 1.0, 4.0)
	d.bulb(Vector3(-4.2, -0.15, -4.2), Color(1.0, 0.7, 0.4), 1.4, 1.0, 4.0)
	d.bulb(Vector3(-4.2, -0.15, 4.2), Color(1.0, 0.7, 0.4), 1.4, 1.0, 4.0)
	d.bulb(Vector3(4.2, -0.15, -4.2), Color(1.0, 0.7, 0.4), 1.4, 1.0, 4.0)
	# pergola over the atrium rim, fountain rim, tiles ring
	for sz in [-7.8, 7.8]:
		for sx in [-1.0, 1.0]:
			d.bar(Vector3(sx * 5.3, 3.35, sz), Vector3(sx * 8.2, 3.35, sz), 0.22, 0.3, "wood_planks", C_WOOD)
			for i in [2, 3]:
				d.bar(Vector3(sx * float(i) * 2.7, 3.45, sz - 1.0), Vector3(sx * float(i) * 2.7, 3.45, sz + 1.0), 0.12, 0.14, "wood_planks", C_WOOD)
	for sx in [-8.2, 8.2]:
		d.bar(Vector3(sx, 3.35, -7.8), Vector3(sx, 3.35, 7.8), 0.22, 0.3, "wood_planks", C_WOOD)
	d.add_cylinder(Vector3(0, PIT + 1.02, 0), 3.5, 0.08, "concrete", C_WHITE)
	d.lamp_post(Vector3(-7.4, 0, 0), 4.2, 0.0)
	d.lamp_post(Vector3(7.4, 0, 0), 4.2, PI)
	for sgn in [-1.0, 1.0]:
		# hall: ceiling lights, roof equipment, solar panels
		d.lamp(Vector3(0, 3.15, sgn * 12.75), Color(1.0, 0.9, 0.72), 1.0, 8.5)
		d.lamp(Vector3(9.0, 3.15, sgn * 12.75), Color(1.0, 0.88, 0.7), 0.8, 7.0)
		d.lamp(Vector3(-9.0, 3.15, sgn * 12.75), Color(1.0, 0.88, 0.7), 0.8, 7.0)
		d.lamp(Vector3(0, TOP + UP_H - 0.05, sgn * 12.75), Color(1.0, 0.92, 0.78), 0.9, 8.0)
		d.lamp(Vector3(22.0, 3.15, sgn * 6.5), Color(0.92, 0.95, 1.0), 1.0, 8.0)
		d.lamp(Vector3(25.0, TOP + 2.45, sgn * 4.25), Color(1.0, 0.92, 0.8), 0.7, 5.0)
		for i in 4:
			for j in 2:
				d.solar_panel(Vector3(-9.0 + float(i) * 2.0, 6.8, sgn * (10.8 + float(j) * 2.2)), 0.0 if sgn > 0.0 else PI)
		d.ac_unit(Vector3(9.5, 6.8, sgn * 15.5), 0.0)
		d.vent_stack(Vector3(-11.5, 6.8, sgn * 15.8), 1.0)
		d.antenna(Vector3(12.0, 6.8, sgn * 9.5), 3.4)
		for i in 3:
			d.solar_panel(Vector3(23.0 + float(i) * 0.0, TOP + 2.9, sgn * (3.0 + float(i) * 1.2)), 0.0 if sgn > 0.0 else PI)
		d.ac_unit(Vector3(19.5, TOP, sgn * 9.2), PI * 0.5)
		# plaza and streets: lamps, boxes, barrels, markings
		d.lamp_post(Vector3(-9.0, 0, sgn * 26.5), 4.5, 0.0)
		d.lamp_post(Vector3(9.0, 0, sgn * 26.5), 4.5, PI)
		d.lamp_post(Vector3(-17.5, 0, sgn * 9.0), 4.2, 0.0)
		d.lamp_post(Vector3(15.0, 0, sgn * 9.0), 4.2, PI)
		d.power_box(Vector3(-31.5, 0, sgn * 15.0), PI * 0.5)
		d.power_box(Vector3(31.5, 0, sgn * 9.0), -PI * 0.5)
		d.barrel(Vector3(29.0, 0, sgn * 22.5), Color(0.55, 0.22, 0.14))
		d.pallet(Vector3(28.0, 0, sgn * 24.5), 0.3)
		d.barrel(Vector3(-30.5, 0, sgn * 24.0), Color(0.2, 0.32, 0.5))
		d.dashed_line(Vector3(-17.5, 0.07, sgn * 22.0), Vector3(-17.5, 0.07, sgn * 5.0), 0.1, 0.8, 0.8, Color(0.8, 0.76, 0.66))
		d.marking(Vector3(0, 0.07, sgn * 21.7), Vector3(44.0, 0.01, 0.15), Color(0.9, 0.86, 0.7))
		# pool coping, pergola beams over the terrace, string of garden lights
		d.add_box(Vector3(-21.0, 0.43, sgn * 15.5), Vector3(6.4, 0.06, 3.9), "concrete", C_WHITE)
		d.bar(Vector3(-30.0, 4.7, sgn * 4.0), Vector3(-25.0, 4.7, sgn * 4.0), 0.2, 0.25, "wood_planks", C_WOOD)
		d.bar(Vector3(-30.0, 4.7, sgn * 10.0), Vector3(-25.0, 4.7, sgn * 10.0), 0.2, 0.25, "wood_planks", C_WOOD)
		for i in 6:
			d.bar(Vector3(-30.0 + float(i), 4.8, sgn * 4.0), Vector3(-30.0 + float(i), 4.8, sgn * 10.0), 0.1, 0.12, "wood_planks", C_WOOD)
		d.lamp(Vector3(-27.5, 4.6, sgn * 7.0), Color(1.0, 0.85, 0.6), 0.6, 8.0)
		d.lamp(Vector3(-27.5, 2.85, sgn * 19.5), Color(1.0, 0.9, 0.7), 0.8, 6.0)
	# hills first (their heights place the plants), then the visual dressing, then the plants (wind in the foliage shader)
	var hills := [
		{"pos": Vector3(-20, -1, -58), "size": Vector3(70, 26, 40), "yaw": 0.2}, {"pos": Vector3(30, -1, -60), "size": Vector3(60, 20, 36), "yaw": -0.3},
		{"pos": Vector3(-24, -1, 58), "size": Vector3(64, 22, 38), "yaw": 0.4}, {"pos": Vector3(28, -1, 61), "size": Vector3(72, 28, 40), "yaw": -0.1},
		{"pos": Vector3(-76, -1, -8), "size": Vector3(44, 24, 70), "yaw": 0.1}, {"pos": Vector3(78, -1, 10), "size": Vector3(46, 30, 74), "yaw": -0.2},
		{"pos": Vector3(-74, -1, 40), "size": Vector3(40, 18, 40), "yaw": 0.5}, {"pos": Vector3(74, -1, -42), "size": Vector3(40, 22, 44), "yaw": 0.3},
		{"pos": Vector3(0, -1, -80), "size": Vector3(160, 40, 40), "yaw": 0.0}, {"pos": Vector3(0, -1, 80), "size": Vector3(160, 44, 40), "yaw": 0.0},
	]
	MesaScenery.tower(d)
	MesaScenery.facades(d)
	MesaScenery.wings(d, geometry_root, _bushes)
	MesaScenery.perimeter(d, _bushes)
	MesaScenery.interior(d, _bushes)
	MesaScenery.banners(d, geometry_root)
	MesaScenery.garden_details(d, _bushes, _palms)
	MesaScenery.hill_life(d, hills, _bushes, _palms)
	MesaScenery.dust(geometry_root)
	var weather := MesaSky.new()
	weather.name = "MesaSky"
	add_child(weather)
	Vegetation.scatter(geometry_root, Vegetation.palm_mesh(), _palms, "Palms")
	Vegetation.scatter(geometry_root, Vegetation.bush_mesh(), _bushes, "Bushes")
	var hill_mat := _get_material("dirt", Color(0.74, 0.66, 0.54))
	Vegetation.hills(geometry_root, hill_mat, hills)
