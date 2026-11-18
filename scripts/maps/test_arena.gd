extends BlockMap
## Testarena: compact three-lane training map (approx. 56 x 40 m).
## North (z < 0) = Rot, South (z > 0) = Blau. Lanes: left (x < -12),
## mid (-6..6), right (x > 12). Buildings between the lanes have cut-throughs.

const C_WARM := Color(0.86, 0.78, 0.62)
const C_COOL := Color(0.72, 0.78, 0.84)
const C_RED := Color(0.75, 0.25, 0.2)
const C_BLUE := Color(0.25, 0.45, 0.75)
const C_GREEN := Color(0.35, 0.55, 0.35)
const C_DARK := Color(0.35, 0.35, 0.38)


func get_blocks() -> Array:
	var b: Array = []
	# ---------------------------------------------------------------- ground & borders
	b.append(box(Vector3(0, -0.25, 0), Vector3(60, 0.5, 44), "asphalt"))
	# sidewalks along both long sides of the mid street
	b.append(box(Vector3(-7.5, 0.08, 0), Vector3(3, 0.16, 44), "concrete"))
	b.append(box(Vector3(7.5, 0.08, 0), Vector3(3, 0.16, 44), "concrete"))
	# outer walls
	b.append(box(Vector3(0, 3, -22.25), Vector3(60.5, 6, 0.5), "concrete", C_DARK))
	b.append(box(Vector3(0, 3, 22.25), Vector3(60.5, 6, 0.5), "concrete", C_DARK))
	b.append(box(Vector3(-30.25, 3, 0), Vector3(0.5, 6, 44.5), "concrete", C_DARK))
	b.append(box(Vector3(30.25, 3, 0), Vector3(0.5, 6, 44.5), "concrete", C_DARK))

	# ---------------------------------------------------------------- west building row (brick)
	# north-west block with a cut-through to the left lane and the street
	b.append_array(room_walls(Vector3(-9, 0, -8), Vector3(6, 3.6, 7), 0.3, "brick", null,
		[{"side": "e", "offset": 0.0, "width": 1.6}, {"side": "w", "offset": 1.0, "width": 1.6}, {"side": "s", "offset": -1.0, "width": 1.6},
				{"side": "n", "offset": 0.0, "width": 1.6}]))
	b.append_array(window(Vector3(-9, 0, -11.5), 1.6, 1.0, 2.1, 3.6, 0.3, true, "brick"))
	b.append(header(Vector3(-6, 0, -8), 1.6, 2.2, 3.6, 0.3, false, "brick"))
	b.append(header(Vector3(-12, 0, -7), 1.6, 2.2, 3.6, 0.3, false, "brick"))
	b.append(header(Vector3(-10, 0, -4.5), 1.6, 2.2, 3.6, 0.3, true, "brick"))
	b.append(box(Vector3(-9, 3.75, -8), Vector3(6.3, 0.3, 7.3), "roof_shingles"))
	# south-west block
	b.append_array(room_walls(Vector3(-9, 0, 8), Vector3(6, 3.6, 7), 0.3, "brick", null,
		[{"side": "e", "offset": 0.0, "width": 1.6}, {"side": "w", "offset": -1.0, "width": 1.6}, {"side": "n", "offset": 1.0, "width": 1.6},
				{"side": "s", "offset": 0.0, "width": 1.6}]))
	b.append_array(window(Vector3(-9, 0, 11.5), 1.6, 1.0, 2.1, 3.6, 0.3, true, "brick"))
	b.append(header(Vector3(-6, 0, 8), 1.6, 2.2, 3.6, 0.3, false, "brick"))
	b.append(header(Vector3(-12, 0, 7), 1.6, 2.2, 3.6, 0.3, false, "brick"))
	b.append(header(Vector3(-8, 0, 4.5), 1.6, 2.2, 3.6, 0.3, true, "brick"))
	b.append(box(Vector3(-9, 3.75, 8), Vector3(6.3, 0.3, 7.3), "roof_shingles"))
	# low wall in the gap between the two west blocks (cover for the cut-through)
	b.append(box(Vector3(-9, 0.55, 0), Vector3(2.4, 1.1, 0.35), "concrete", C_WARM))

	# ---------------------------------------------------------------- east building row (plaster)
	b.append_array(room_walls(Vector3(9, 0, -8), Vector3(6, 3.6, 7), 0.3, "plaster", C_WARM,
		[{"side": "w", "offset": 0.0, "width": 1.6}, {"side": "e", "offset": -1.0, "width": 1.6}, {"side": "s", "offset": 1.0, "width": 1.6},
				{"side": "n", "offset": 0.0, "width": 1.6}]))
	b.append_array(window(Vector3(9, 0, -11.5), 1.6, 1.0, 2.1, 3.6, 0.3, true, "plaster", C_WARM))
	b.append(header(Vector3(6, 0, -8), 1.6, 2.2, 3.6, 0.3, false, "plaster", C_WARM))
	b.append(header(Vector3(12, 0, -9), 1.6, 2.2, 3.6, 0.3, false, "plaster", C_WARM))
	b.append(header(Vector3(10, 0, -4.5), 1.6, 2.2, 3.6, 0.3, true, "plaster", C_WARM))
	b.append(box(Vector3(9, 3.75, -8), Vector3(6.3, 0.3, 7.3), "concrete", C_DARK))
	b.append_array(room_walls(Vector3(9, 0, 8), Vector3(6, 3.6, 7), 0.3, "plaster", C_COOL,
		[{"side": "w", "offset": 0.0, "width": 1.6}, {"side": "e", "offset": 1.0, "width": 1.6}, {"side": "n", "offset": -1.0, "width": 1.6},
				{"side": "s", "offset": 0.0, "width": 1.6}]))
	b.append_array(window(Vector3(9, 0, 11.5), 1.6, 1.0, 2.1, 3.6, 0.3, true, "plaster", C_COOL))
	b.append(header(Vector3(6, 0, 8), 1.6, 2.2, 3.6, 0.3, false, "plaster", C_COOL))
	b.append(header(Vector3(12, 0, 9), 1.6, 2.2, 3.6, 0.3, false, "plaster", C_COOL))
	b.append(header(Vector3(8, 0, 4.5), 1.6, 2.2, 3.6, 0.3, true, "plaster", C_COOL))
	b.append(box(Vector3(9, 3.75, 8), Vector3(6.3, 0.3, 7.3), "concrete", C_DARK))
	# crates in the east gap
	b.append(box(Vector3(9.5, 0.6, 0.3), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(8.3, 0.6, -0.6), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(9.5, 1.8, 0.3), Vector3(1.2, 1.2, 1.2), "crate"))

	# ---------------------------------------------------------------- mid street
	# parked vehicles as hard cover
	b.append(box(Vector3(-2.5, 0.65, -10), Vector3(2.0, 1.3, 4.4), "metal_panel", C_BLUE))
	b.append(box(Vector3(-2.5, 1.55, -10.3), Vector3(1.8, 0.5, 2.4), "metal_panel", C_DARK))
	b.append(box(Vector3(2.5, 0.65, 10), Vector3(2.0, 1.3, 4.4), "metal_panel", C_RED))
	b.append(box(Vector3(2.5, 1.55, 10.3), Vector3(1.8, 0.5, 2.4), "metal_panel", C_DARK))
	# central planter / fountain block
	b.append(box(Vector3(0, 0.45, 0), Vector3(4.5, 0.9, 4.5), "concrete", C_COOL))
	b.append(box(Vector3(0, 1.1, 0), Vector3(3.3, 0.4, 3.3), "grass"))
	b.append(cylinder(Vector3(0, 1.5, 0), 0.5, 1.6, "concrete"))
	# low concrete barriers on the street (jersey barriers)
	b.append(box(Vector3(-3.5, 0.5, -3), Vector3(2.2, 1.0, 0.5), "concrete"))
	b.append(box(Vector3(3.5, 0.5, 3), Vector3(2.2, 1.0, 0.5), "concrete"))
	# street lamps
	for z in [-14.0, 14.0]:
		b.append(cylinder(Vector3(-6.3, 2.5, z), 0.16, 5.0, "metal_panel", C_DARK))
		b.append(cylinder(Vector3(6.3, 2.5, z), 0.16, 5.0, "metal_panel", C_DARK))

	# ---------------------------------------------------------------- left lane (x -28..-12): containers + elevated catwalk
	b.append(box(Vector3(-19, 1.3, -6), Vector3(2.4, 2.6, 6.0), "metal_panel", C_GREEN))
	b.append(box(Vector3(-19, 1.3, 6), Vector3(2.4, 2.6, 6.0), "metal_panel", C_RED))
	b.append(box(Vector3(-15, 0.55, 0), Vector3(0.35, 1.1, 3.0), "concrete"))
	# catwalk along the west wall with ramps on both ends
	b.append(box(Vector3(-26.5, 2.6, 0), Vector3(6.0, 0.3, 22.0), "metal_panel", C_DARK))
	b.append(box(Vector3(-23.6, 3.1, 0), Vector3(0.1, 0.9, 22.0), "metal_panel", C_DARK)) # railing
	b.append(ramp(Vector3(-26.5, 0.0, -17.5), Vector3(-26.5, 2.75, -11.0), 6.0, "metal_panel", 0.3, C_DARK))
	b.append(ramp(Vector3(-26.5, 0.0, 17.5), Vector3(-26.5, 2.75, 11.0), 6.0, "metal_panel", 0.3, C_DARK))
	for z in [-10.0, 0.0, 10.0]:
		b.append(cylinder(Vector3(-24.0, 1.25, z), 0.3, 2.5, "metal_panel", C_DARK))
	# barrels
	b.append(cylinder(Vector3(-14.5, 0.45, -12), 0.6, 0.9, "metal_panel", C_BLUE))
	b.append(cylinder(Vector3(-13.8, 0.45, -12.6), 0.6, 0.9, "metal_panel", C_RED))
	b.append(cylinder(Vector3(-14.5, 0.45, 12), 0.6, 0.9, "metal_panel", C_GREEN))

	# ---------------------------------------------------------------- right lane (x 12..28): garage + raised room
	# open garage (three walls, open to the west)
	b.append_array(room_walls(Vector3(23, 0, -11), Vector3(9, 3.2, 8), 0.3, "concrete", C_WARM,
		[{"side": "w", "offset": 0.0, "width": 5.0}, {"side": "s", "offset": 2.0, "width": 1.6}]))
	b.append(header(Vector3(18.5, 0, -11), 5.0, 2.4, 3.2, 0.3, false, "concrete", C_WARM))
	b.append(header(Vector3(25, 0, -7), 1.6, 2.2, 3.2, 0.3, true, "concrete", C_WARM))
	b.append(box(Vector3(23, 3.35, -11), Vector3(9.3, 0.3, 8.3), "metal_panel", C_DARK))
	b.append(box(Vector3(24, 0.7, -12), Vector3(2.0, 1.4, 4.4), "metal_panel", C_DARK))
	# raised room on the south-east with a ramp
	b.append(box(Vector3(23, 2.8, 11), Vector3(10, 0.3, 8), "wood_planks"))
	for p in [Vector3(18.5, 1.35, 7.5), Vector3(27.5, 1.35, 7.5), Vector3(18.5, 1.35, 14.5), Vector3(27.5, 1.35, 14.5)]:
		b.append(box(p, Vector3(0.5, 2.7, 0.5), "concrete", C_DARK))
	b.append(box(Vector3(23, 3.4, 15), Vector3(10, 0.9, 0.1), "metal_panel", C_DARK)) # railing south
	b.append(box(Vector3(23, 3.4, 7), Vector3(6, 0.9, 0.1), "metal_panel", C_DARK))  # railing north (gap for drop-down)
	b.append(ramp(Vector3(15.5, 0.0, 11), Vector3(18.0, 2.95, 11), 3.0, "wood_planks"))
	b.append(box(Vector3(14, 0.55, 4), Vector3(3.0, 1.1, 0.35), "concrete"))
	b.append(box(Vector3(20, 0.6, 2), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(21.3, 0.6, 2.3), Vector3(1.2, 1.2, 1.2), "crate"))

	# ---------------------------------------------------------------- spawn-side cover (north / south)
	for sx in [-20.0, -10.0, 10.0, 20.0]:
		b.append(box(Vector3(sx, 0.55, -18), Vector3(3.0, 1.1, 0.4), "concrete", C_COOL))
		b.append(box(Vector3(sx, 0.55, 18), Vector3(3.0, 1.1, 0.4), "concrete", C_COOL))
	b.append(box(Vector3(0, 0.6, -19), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(0, 0.6, 19), Vector3(1.2, 1.2, 1.2), "crate"))
	return b


func build_detail(d: MapDetail) -> void:
	for p in [Vector3(-9, 3.45, -8), Vector3(-9, 3.45, 8)]:
		d.lamp(p, Color(1.0, 0.82, 0.55), 1.0, 7.0)
	for p in [Vector3(9, 3.45, -8), Vector3(9, 3.45, 8)]:
		d.lamp(p, Color(0.85, 0.92, 1.0), 1.0, 7.0)
	for z in [-14.0, 14.0]:
		d.lamp_post(Vector3(-9.2, 0, z), 5.0, 0.0)
		d.lamp_post(Vector3(9.2, 0, -z), 5.0, PI)
	d.power_box(Vector3(-29.6, 0, 6.0), PI * 0.5)
	d.power_box(Vector3(29.6, 0, -6.0), -PI * 0.5)
	d.barrel(Vector3(-29.3, 0, -3.0), Color(0.2, 0.32, 0.5))
	d.barrel(Vector3(-29.3, 0, -2.0), Color(0.55, 0.22, 0.14))
	d.barrel(Vector3(29.3, 0, 3.0), Color(0.55, 0.22, 0.14))
	d.pallet(Vector3(29.0, 0, 7.0), 0.2)
	d.dashed_line(Vector3(0, 0.005, -21), Vector3(0, 0.005, 21), 0.15, 2.0, 2.0, Color(0.9, 0.85, 0.4))
	d.marking(Vector3(-4.9, 0.006, 0), Vector3(0.12, 0.01, 44), Color(0.85, 0.85, 0.8))
	d.marking(Vector3(4.9, 0.006, 0), Vector3(0.12, 0.01, 44), Color(0.85, 0.85, 0.8))


func get_spawns() -> Array:
	var s: Array = []
	# Rot im Norden (schaut nach Sueden = +Z -> yaw 180)
	for x in [-26.0, -17.0, -8.0, 3.0, 13.0, 24.0]:
		s.append(spawn(Vector3(x, 0.1, -20), 180.0, Teams.Team.RED))
	# Blau im Sueden (schaut nach Norden = -Z -> yaw 0)
	for x in [-24.0, -13.0, -3.0, 8.0, 17.0, 26.0]:
		s.append(spawn(Vector3(x, 0.1, 20), 0.0, Teams.Team.BLUE))
	# neutrale Punkte an den Flanken (FFA + Nachspawns)
	s.append(spawn(Vector3(-26.5, 2.9, 0), 90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-14.6, 0.1, -11.3), 135.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-14.6, 0.1, 12.7), 45.0, Teams.Team.NONE))
	s.append(spawn(Vector3(22.6, 0.1, -12.3), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(25, 3.1, 11), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(15, 0.1, 0), -90.0, Teams.Team.NONE))
	return s
