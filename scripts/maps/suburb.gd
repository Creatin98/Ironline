extends BlockMap
## SUBURB â€“ a compact, colourful American cul-de-sac (inspired by Nuketown).
## Two two-storey houses face each other diagonally across a short street.
## Rot spawns north behind the yellow house, Blau south behind the blue house.
## Lanes: back yards (left, x < -12), street with the bus (mid), garages (right, x > 12).

const C_YELLOW := Color(0.95, 0.85, 0.45)
const C_LIGHTBLUE := Color(0.6, 0.78, 0.92)
const C_WHITE := Color(0.95, 0.95, 0.93)
const C_ROOF := Color(0.55, 0.3, 0.25)
const C_FENCE := Color(0.95, 0.95, 0.9)
const C_DARK := Color(0.3, 0.3, 0.33)
const C_GREEN := Color(0.35, 0.6, 0.3)
const C_RED := Color(0.8, 0.2, 0.18)
const C_BLUE := Color(0.2, 0.45, 0.85)
const C_BUS := Color(0.95, 0.75, 0.2)
const C_GARAGE := Color(0.8, 0.8, 0.78)

const FLOOR_H := 2.9     # ground floor wall height
const UPPER_H := 2.6     # upper floor wall height
const SLAB := 0.3


func get_blocks() -> Array:
	var b: Array = []
	# ---------------------------------------------------------------- ground
	b.append(box(Vector3(0, -0.25, 0), Vector3(56, 0.5, 44), "grass"))
	b.append(box(Vector3(0, 0.01, 0), Vector3(10, 0.06, 44), "asphalt"))          # street
	b.append(box(Vector3(-6.0, 0.06, 0), Vector3(2, 0.12, 44), "concrete"))      # sidewalks
	b.append(box(Vector3(6.0, 0.06, 0), Vector3(2, 0.12, 44), "concrete"))
	b.append(cylinder(Vector3(0, 0.02, 0), 12.0, 0.06, "asphalt"))              # cul-de-sac circle
	# boundary: white picket fences + invisible walls
	b.append_array(fence(Vector3(-28, 0, -22), 56, 1.4, true, "plaster", C_FENCE))
	b.append_array(fence(Vector3(-28, 0, 22), 56, 1.4, true, "plaster", C_FENCE))
	b.append_array(fence(Vector3(-28, 0, -22), 44, 1.4, false, "plaster", C_FENCE))
	b.append_array(fence(Vector3(28, 0, -22), 44, 1.4, false, "plaster", C_FENCE))
	for wall in [
		{"pos": Vector3(0, 3, -22.3), "size": Vector3(57, 6, 0.3)},
		{"pos": Vector3(0, 3, 22.3), "size": Vector3(57, 6, 0.3)},
		{"pos": Vector3(-28.3, 3, 0), "size": Vector3(0.3, 6, 45)},
		{"pos": Vector3(28.3, 3, 0), "size": Vector3(0.3, 6, 45)},
	]:
		b.append({"pos": wall["pos"], "size": wall["size"], "mat": "plaster", "visible": false})

	# ---------------------------------------------------------------- houses
	b.append_array(_house(Vector3(-11, 0, -11), C_YELLOW, true))   # Rot, north-west, faces south/east
	b.append_array(_house(Vector3(11, 0, 11), C_LIGHTBLUE, false)) # Blau, south-east, faces north/west

	# ---------------------------------------------------------------- street (mid lane)
	# school bus in the middle of the cul-de-sac
	b.append(box(Vector3(0, 1.7, 0), Vector3(2.6, 2.4, 11.0), "metal_panel", C_BUS))
	b.append(box(Vector3(0, 0.25, 0), Vector3(2.4, 0.5, 10.5), "metal_panel", C_DARK))
	for wz in [-3.8, 3.8]:
		for wx in [-1.2, 1.2]:
			b.append({"pos": Vector3(wx, 0.45, wz), "size": Vector3(0.3, 0.9, 0.9), "mat": "rubber", "collide": false})
	b.append_array(car(Vector3(3.0, 0, -13), C_RED, 0.0))
	b.append_array(car(Vector3(-3.0, 0, 13), C_BLUE, 180.0))
	# mailboxes and a fire hydrant
	for z in [-7.0, 7.0]:
		b.append(box(Vector3(-6.5, 0.9, z), Vector3(0.3, 0.3, 0.5), "metal_panel", C_DARK))
		b.append(box(Vector3(-6.5, 0.4, z), Vector3(0.08, 0.8, 0.08), "metal_panel", C_DARK))
		b.append(box(Vector3(6.5, 0.9, -z), Vector3(0.3, 0.3, 0.5), "metal_panel", C_DARK))
		b.append(box(Vector3(6.5, 0.4, -z), Vector3(0.08, 0.8, 0.08), "metal_panel", C_DARK))
	b.append(cylinder(Vector3(6.5, 0.4, 0), 0.3, 0.8, "metal_panel", C_RED))
	# street-side hedges (waist high cover)
	b.append(box(Vector3(-9, 0.5, -4), Vector3(4.0, 1.0, 0.8), "grass", C_GREEN))
	b.append(box(Vector3(9, 0.5, 4), Vector3(4.0, 1.0, 0.8), "grass", C_GREEN))

	# ---------------------------------------------------------------- garages (right lane side for Rot, left for Blau)
	b.append_array(_garage(Vector3(13, 0, -13), true))   # Rot side, north-east
	b.append_array(_garage(Vector3(-13, 0, 13), false))  # Blau side, south-west

	# ---------------------------------------------------------------- back yards
	# north-west yard (behind the yellow house): shed, trampoline, fence with gap
	b.append_array(room_walls(Vector3(-23, 0, -6), Vector3(3.5, 2.4, 3.0), 0.2, "wood_planks", null,
		[{"side": "e", "offset": 0.0, "width": 1.2}]))
	b.append(header(Vector3(-21.25, 0, -6), 1.2, 2.0, 2.4, 0.2, false, "wood_planks"))
	b.append(box(Vector3(-23, 2.55, -6), Vector3(3.9, 0.3, 3.4), "roof_shingles"))
	b.append(cylinder(Vector3(-22, 0.45, -15), 3.2, 0.9, "rubber"))                 # trampoline
	b.append_array(fence(Vector3(-28, 0, 0), 8.0, 1.2, true, "plaster", C_FENCE))    # yard fence with gap at x -20..-16
	b.append_array(fence(Vector3(-16, 0, 0), 3.0, 1.2, true, "plaster", C_FENCE))
	# south-east yard (behind the blue house): swing set, barbecue, fence
	for x in [20.0, 24.0]:
		b.append(box(Vector3(x, 1.25, 6), Vector3(0.15, 2.5, 0.15), "metal_panel", C_DARK))
	b.append(box(Vector3(22, 2.5, 6), Vector3(4.3, 0.15, 0.15), "metal_panel", C_DARK))
	b.append(box(Vector3(22, 0.6, 6), Vector3(1.2, 0.1, 0.4), "wood_planks"))
	b.append(cylinder(Vector3(24, 0.5, 14), 0.8, 1.0, "metal_panel", C_DARK))       # barbecue
	b.append_array(fence(Vector3(20, 0, 0), 8.0, 1.2, true, "plaster", C_FENCE))     # gap at x 16..20
	b.append_array(fence(Vector3(13, 0, 0), 3.0, 1.2, true, "plaster", C_FENCE))
	# trees at the corners
	for p in [Vector3(-24, 0, 18), Vector3(24, 0, -18)]:
		b.append(cylinder(p + Vector3(0, 1.5, 0), 0.5, 3.0, "wood_planks"))
		b.append(box(p + Vector3(0, 3.8, 0), Vector3(4.5, 2.0, 4.5), "grass", C_GREEN, Vector3(0, 20, 0)))
	# trash cans + crates along the lanes
	for p in [Vector3(-20, 0, -19), Vector3(20, 0, 19), Vector3(-19, 0, 4), Vector3(19, 0, -4)]:
		b.append(cylinder(p + Vector3(0, 0.5, 0), 0.7, 1.0, "metal_panel", C_DARK))
		b.append(cylinder(p + Vector3(0.9, 0.5, 0.3), 0.7, 1.0, "metal_panel", C_GREEN))
	# team markers
	b.append(box(Vector3(0, 2.5, -21.9), Vector3(3.0, 0.5, 0.1), "plaster", C_RED))
	b.append(box(Vector3(0, 2.5, 21.9), Vector3(3.0, 0.5, 0.1), "plaster", C_BLUE))
	return b


## Two-storey house 10 x 9 m. `north` = Rot house (front faces +Z / street side east).
func _house(c: Vector3, color: Color, north: bool) -> Array:
	var out: Array = []
	var dir := 1.0 if north else -1.0   # +1: front door on the south side, back on the north
	var front := "s" if north else "n"
	var back := "n" if north else "s"
	var street := "e" if north else "w"
	var street_x := c.x + 5.0 * (1.0 if north else -1.0)
	var front_z := c.z + 4.5 * dir
	var back_z := c.z - 4.5 * dir
	# ground floor: front door (to the street side), back door (to the spawn), side door to the street, windows
	out.append_array(room_walls(c, Vector3(10, FLOOR_H, 9), 0.3, "plaster", color, [
		{"side": front, "offset": -1.5, "width": 1.6},
		{"side": front, "offset": 2.5, "width": 1.8},
		{"side": back, "offset": 1.5, "width": 1.6},
		{"side": street, "offset": 0.0, "width": 1.6},
		{"side": street, "offset": -3.0, "width": 1.6},
	]))
	out.append(header(Vector3(c.x - 1.5, 0, front_z), 1.6, 2.2, FLOOR_H, 0.3, true, "plaster", color))
	out.append_array(window(Vector3(c.x + 2.5, 0, front_z), 1.8, 0.9, 2.1, FLOOR_H, 0.3, true, "plaster", color))
	out.append(header(Vector3(c.x + 1.5, 0, back_z), 1.6, 2.2, FLOOR_H, 0.3, true, "plaster", color))
	out.append(header(Vector3(street_x, 0, c.z), 1.6, 2.2, FLOOR_H, 0.3, false, "plaster", color))
	out.append_array(window(Vector3(street_x, 0, c.z - 3.0), 1.6, 0.9, 2.1, FLOOR_H, 0.3, false, "plaster", color))
	# interior: kitchen counter + partition with a doorway
	out.append(box(Vector3(c.x - 3.5, 0.5, c.z - 2.5 * dir), Vector3(2.5, 1.0, 0.7), "wood_planks"))
	out.append(box(Vector3(c.x + 0.5, FLOOR_H * 0.5, c.z - 1.0 * dir), Vector3(0.2, FLOOR_H, 4.0), "plaster", C_WHITE))
	out.append(box(Vector3(c.x + 1.5, 0.35, c.z + 2.0 * dir), Vector3(2.2, 0.7, 1.0), "plaster", C_DARK))  # sofa
	# first floor slab (full) and upper floor room (smaller, leaves a balcony on the street side)
	var slab_y := FLOOR_H + SLAB * 0.5
	out.append(box(Vector3(c.x, slab_y, c.z), Vector3(10.3, SLAB, 9.3), "wood_planks"))
	var upper_c := Vector3(c.x - 1.5 * (1.0 if north else -1.0), FLOOR_H + SLAB, c.z)
	var upper_size := Vector3(7, UPPER_H, 9)
	out.append_array(room_walls(upper_c, upper_size, 0.3, "plaster", color, [
		{"side": street, "offset": 0.0, "width": 1.6},        # door to the balcony
		{"side": front, "offset": 0.0, "width": 2.0},          # window to the front
		{"side": back, "offset": 0.0, "width": 1.6},           # door to the back stairs
		{"side": "w" if north else "e", "offset": 0.0, "width": 2.0},  # window to the back yard
	]))
	var ux := upper_c.x + 3.5 * (1.0 if north else -1.0)
	var bx := upper_c.x - 3.5 * (1.0 if north else -1.0)
	out.append(header(Vector3(ux, FLOOR_H + SLAB, c.z), 1.6, FLOOR_H + SLAB + 2.1, FLOOR_H + SLAB + UPPER_H, 0.3, false, "plaster", color))
	out.append_array(window(Vector3(upper_c.x, 0, front_z), 2.0, FLOOR_H + SLAB + 0.9, FLOOR_H + SLAB + 2.0, FLOOR_H + SLAB + UPPER_H, 0.3, true, "plaster", color))
	out.append(header(Vector3(upper_c.x, FLOOR_H + SLAB, back_z), 1.6, FLOOR_H + SLAB + 2.1, FLOOR_H + SLAB + UPPER_H, 0.3, true, "plaster", color))
	out.append_array(window(Vector3(bx, 0, c.z), 2.0, FLOOR_H + SLAB + 0.9, FLOOR_H + SLAB + 2.0, FLOOR_H + SLAB + UPPER_H, 0.3, false, "plaster", color))
	# balcony railing on the street side of the slab
	var rail_x := c.x + 5.0 * (1.0 if north else -1.0)
	out.append(box(Vector3(rail_x, FLOOR_H + SLAB + 0.5, c.z), Vector3(0.1, 1.0, 9.3), "metal_panel", C_WHITE))
	out.append(box(Vector3((rail_x + ux) * 0.5, FLOOR_H + SLAB + 0.5, front_z), Vector3(3.2, 1.0, 0.1), "metal_panel", C_WHITE))
	# roof
	out.append(box(Vector3(upper_c.x, FLOOR_H + SLAB + UPPER_H + 0.15, c.z), Vector3(7.6, 0.3, 9.6), "roof_shingles"))
	# exterior stairs at the back up to the slab (towards the spawn side)
	var stair_x := upper_c.x
	var stair_low := Vector3(stair_x, 0.0, back_z - 7.5 * dir)
	var stair_high := Vector3(stair_x, FLOOR_H + SLAB, back_z - 0.9 * dir)
	out.append(ramp(stair_low, stair_high, 2.0, "wood_planks", 0.3))
	out.append(box(Vector3(stair_x, FLOOR_H + SLAB * 0.5, back_z - 0.45 * dir), Vector3(2.0, SLAB, 0.9), "wood_planks"))
	out.append(box(Vector3(stair_x + 1.05, FLOOR_H * 0.5, back_z - 4.2 * dir), Vector3(0.1, FLOOR_H + 0.6, 7.2), "metal_panel", C_WHITE, Vector3(-dir * 23.0, 0, 0)))
	# porch step at the front door
	out.append(box(Vector3(c.x - 1.5, 0.1, front_z + 0.8 * dir), Vector3(2.0, 0.2, 1.2), "concrete"))
	return out


## Single garage 6 x 6 with an open door and a car, attached to the Rot (north) or Blau side.
func _garage(c: Vector3, north: bool) -> Array:
	var out: Array = []
	var open_side := "s" if north else "n"
	var dir := 1.0 if north else -1.0
	out.append_array(room_walls(c, Vector3(6, 2.8, 6), 0.3, "plaster", C_GARAGE, [
		{"side": open_side, "offset": 0.0, "width": 3.2},
		{"side": "w" if north else "e", "offset": 0.0, "width": 1.4},
	]))
	out.append(header(Vector3(c.x, 0, c.z + 3.0 * dir), 3.2, 2.3, 2.8, 0.3, true, "plaster", C_GARAGE))
	out.append(header(Vector3(c.x - 3.0 * dir, 0, c.z), 1.4, 2.1, 2.8, 0.3, false, "plaster", C_GARAGE))
	out.append(box(Vector3(c.x, 2.95, c.z), Vector3(6.4, 0.3, 6.4), "roof_shingles"))
	out.append_array(car(c + Vector3(0, 0, -0.5 * dir), C_WHITE, 0.0))
	out.append(box(Vector3(c.x + 2.2 * dir, 0.6, c.z - 2.0 * dir), Vector3(1.2, 1.2, 1.2), "crate"))
	out.append(box(Vector3(c.x + 2.2 * dir, 1.8, c.z - 2.0 * dir), Vector3(1.2, 1.2, 1.2), "crate"))
	# driveway
	out.append(box(Vector3(c.x, 0.03, c.z + 5.0 * dir), Vector3(4.0, 0.06, 4.0), "concrete"))
	return out


func get_spawns() -> Array:
	var s: Array = []
	for x in [-24.0, -16.0, -8.0, 0.0, 8.0, 20.0]:
		s.append(spawn(Vector3(x, 0.1, -20.0), 180.0, Teams.Team.RED))
	for x in [-20.0, -8.0, 0.0, 8.0, 16.0, 24.0]:
		s.append(spawn(Vector3(x, 0.1, 20.0), 0.0, Teams.Team.BLUE))
	s.append(spawn(Vector3(-22, 0.1, -10), 90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(22, 0.1, 10), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-11, FLOOR_H + SLAB + 0.1, -11), 90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(11, FLOOR_H + SLAB + 0.1, 11), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(13, 0.1, -16), 180.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-13, 0.1, 16), 0.0, Teams.Team.NONE))
	return s


func get_lanes() -> Dictionary:
	return {
		"left": [Vector3(-16, 0, -20), Vector3(-20, 0, -12), Vector3(-18, 0, -4), Vector3(-18, 0, 4), Vector3(-20, 0, 12), Vector3(-16, 0, 20)],
		"mid": [Vector3(0, 0, -20), Vector3(0, 0, -12), Vector3(-3, 0, -7), Vector3(-4, 0, 0), Vector3(3, 0, 7), Vector3(0, 0, 12), Vector3(0, 0, 20)],
		"right": [Vector3(16, 0, -20), Vector3(20, 0, -12), Vector3(18, 0, -4), Vector3(18, 0, 4), Vector3(20, 0, 12), Vector3(16, 0, 20)],
		"houses": [Vector3(-11, 0, -3), Vector3(-11, 0, -11), Vector3(-9.5, FLOOR_H + SLAB, -11), Vector3(11, 0, 3), Vector3(11, 0, 11), Vector3(9.5, FLOOR_H + SLAB, 11)],
	}


func get_cover_points() -> Array:
	return [
		Vector3(-1.8, 0, -6.5), Vector3(1.8, 0, 6.5), Vector3(3, 0, -15.8), Vector3(-3, 0, 15.8),
		Vector3(-9, 0, -5.2), Vector3(9, 0, 5.2), Vector3(-18, 0, -1.2), Vector3(18, 0, 1.2),
		Vector3(-6.5, 0, -11), Vector3(6.5, 0, 11), Vector3(13, 0, -10.5), Vector3(-13, 0, 10.5),
		Vector3(-7, FLOOR_H + SLAB, -11), Vector3(7, FLOOR_H + SLAB, 11),
	]
