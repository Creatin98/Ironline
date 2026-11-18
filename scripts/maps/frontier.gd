extends BlockMap
## FRONTIER â€“ a small town with a light industrial edge (inspired by Standoff).
## North (Rot) = gas station, south (Blau) = warehouse loading dock.
## Lanes: alley with garages (left, x < -12), main street with kiosk (mid),
## shop row with a roof walk (right, x > 12).

const C_WARM := Color(0.87, 0.78, 0.62)
const C_SAND := Color(0.82, 0.72, 0.55)
const C_OCHRE := Color(0.8, 0.6, 0.3)
const C_DARK := Color(0.33, 0.33, 0.36)
const C_ROOF := Color(0.5, 0.35, 0.28)
const C_GREEN := Color(0.3, 0.45, 0.3)
const C_RUST := Color(0.55, 0.3, 0.2)
const C_WHITE := Color(0.92, 0.92, 0.9)
const C_RED := Color(0.75, 0.2, 0.18)
const C_BLUE := Color(0.2, 0.45, 0.8)
const WALL_H := 3.6


func get_blocks() -> Array:
	var b: Array = []
	# ---------------------------------------------------------------- ground
	b.append(box(Vector3(0, -0.25, 0), Vector3(60, 0.5, 46), "asphalt"))
	b.append(box(Vector3(-20, 0.02, 0), Vector3(16, 0.04, 46), "dirt"))      # alley is packed dirt
	b.append(box(Vector3(-6.5, 0.08, 0), Vector3(3, 0.16, 46), "concrete"))  # sidewalks
	b.append(box(Vector3(6.5, 0.08, 0), Vector3(3, 0.16, 46), "concrete"))
	b.append(box(Vector3(0, 3, -23.25), Vector3(60.5, 6, 0.5), "concrete", C_DARK))
	b.append(box(Vector3(0, 3, 23.25), Vector3(60.5, 6, 0.5), "concrete", C_DARK))
	b.append(box(Vector3(-30.25, 3, 0), Vector3(0.5, 6, 46.5), "concrete", C_DARK))
	b.append(box(Vector3(30.25, 3, 0), Vector3(0.5, 6, 46.5), "concrete", C_DARK))

	# ---------------------------------------------------------------- north: gas station (Rot)
	b.append(box(Vector3(0, 3.6, -19), Vector3(14, 0.3, 7), "metal_panel", C_WHITE))   # canopy
	for x in [-6.0, 6.0]:
		for z in [-22.0, -16.0]:
			b.append(box(Vector3(x, 1.75, z), Vector3(0.4, 3.5, 0.4), "metal_panel", C_DARK))
	for x in [-3.0, 3.0]:
		b.append(box(Vector3(x, 0.8, -19), Vector3(0.9, 1.6, 0.5), "metal_panel", C_RED))  # pumps
		b.append(box(Vector3(x, 0.1, -19), Vector3(2.4, 0.2, 1.4), "concrete"))
	b.append(box(Vector3(-12, 0.55, -20), Vector3(3.0, 1.1, 0.4), "concrete", C_WARM))
	b.append(box(Vector3(12, 0.55, -20), Vector3(3.0, 1.1, 0.4), "concrete", C_WARM))
	b.append(box(Vector3(-20, 0.6, -20), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(20, 0.6, -20), Vector3(1.2, 1.2, 1.2), "crate"))

	# ---------------------------------------------------------------- south: warehouse dock (Blau)
	b.append(box(Vector3(0, 0.5, 21), Vector3(14, 1.0, 3.5), "concrete", C_DARK))        # loading dock
	b.append(ramp(Vector3(-9, 0.0, 21), Vector3(-7, 1.0, 21), 3.0, "concrete", 0.3, C_DARK))
	b.append(ramp(Vector3(9, 0.0, 21), Vector3(7, 1.0, 21), 3.0, "concrete", 0.3, C_DARK))
	b.append(box(Vector3(0, 2.2, 22.9), Vector3(14, 2.4, 0.3), "metal_panel", C_RUST))    # roll gate (closed)
	b.append(box(Vector3(-3, 1.6, 20.5), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(3, 1.6, 20.5), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(-12, 0.55, 20), Vector3(3.0, 1.1, 0.4), "concrete", C_WARM))
	b.append(box(Vector3(12, 0.55, 20), Vector3(3.0, 1.1, 0.4), "concrete", C_WARM))
	b.append(box(Vector3(-20, 0.6, 20), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(20, 0.6, 20), Vector3(1.2, 1.2, 1.2), "crate"))

	# ---------------------------------------------------------------- west building row (brick)
	# NW building: doors to street (e), alley (w) and the central gap (s); window to the street
	b.append_array(room_walls(Vector3(-8, 0, -9), Vector3(8, WALL_H, 8), 0.3, "brick", null,
		[{"side": "e", "offset": -1.0, "width": 1.6}, {"side": "e", "offset": 2.0, "width": 1.4},
				{"side": "w", "offset": 1.0, "width": 1.6}, {"side": "s", "offset": -1.5, "width": 1.6}]))
	b.append(header(Vector3(-4, 0, -10), 1.6, 2.2, WALL_H, 0.3, false, "brick"))
	b.append_array(window(Vector3(-4, 0, -7), 1.4, 1.0, 2.1, WALL_H, 0.3, false, "brick"))
	b.append(header(Vector3(-12, 0, -8), 1.6, 2.2, WALL_H, 0.3, false, "brick"))
	b.append(header(Vector3(-9.5, 0, -5), 1.6, 2.2, WALL_H, 0.3, true, "brick"))
	b.append(box(Vector3(-8, WALL_H + 0.15, -9), Vector3(8.3, 0.3, 8.3), "concrete", C_DARK))
	b.append(box(Vector3(-8, 0.5, -11), Vector3(2.0, 1.0, 0.8), "wood_planks"))   # table
	# SW building with roof access from the alley
	b.append_array(room_walls(Vector3(-8, 0, 9), Vector3(8, WALL_H, 8), 0.3, "brick", null,
		[{"side": "e", "offset": 1.0, "width": 1.6}, {"side": "e", "offset": -2.0, "width": 1.4},
				{"side": "w", "offset": -1.0, "width": 1.6}, {"side": "n", "offset": 1.5, "width": 1.6}]))
	b.append(header(Vector3(-4, 0, 10), 1.6, 2.2, WALL_H, 0.3, false, "brick"))
	b.append_array(window(Vector3(-4, 0, 7), 1.4, 1.0, 2.1, WALL_H, 0.3, false, "brick"))
	b.append(header(Vector3(-12, 0, 8), 1.6, 2.2, WALL_H, 0.3, false, "brick"))
	b.append(header(Vector3(-6.5, 0, 5), 1.6, 2.2, WALL_H, 0.3, true, "brick"))
	b.append(box(Vector3(-8, WALL_H + 0.15, 9), Vector3(8.3, 0.3, 8.3), "concrete", C_DARK))
	# parapet on the SW roof (0.9 m) with a gap on the west where the stairs land
	b.append(box(Vector3(-8, WALL_H + 0.75, 4.95), Vector3(8.3, 0.9, 0.2), "brick"))
	b.append(box(Vector3(-8, WALL_H + 0.75, 13.05), Vector3(8.3, 0.9, 0.2), "brick"))
	b.append(box(Vector3(-3.95, WALL_H + 0.75, 9), Vector3(0.2, 0.9, 8.3), "brick"))
	b.append(box(Vector3(-12.05, WALL_H + 0.75, 11.5), Vector3(0.2, 0.9, 3.3), "brick"))
	b.append(ramp(Vector3(-13.5, 0.0, 14.5), Vector3(-13.5, WALL_H + 0.3, 7.5), 3.0, "metal_panel", 0.3, C_DARK))
	b.append(box(Vector3(-13.5, WALL_H + 0.15, 6.75), Vector3(3.0, 0.3, 1.5), "metal_panel", C_DARK))  # landing
	b.append(box(Vector3(-15.05, WALL_H - 1.5, 11), Vector3(0.1, 3.0, 7.5), "metal_panel", C_DARK, Vector3(25, 0, 0)))
	b.append(box(Vector3(-8, 0.5, 11), Vector3(2.0, 1.0, 0.8), "wood_planks"))
	# gap between the west buildings: market stall + low fence
	b.append(box(Vector3(-8, 2.4, 0), Vector3(3.0, 0.15, 2.4), "wood_planks", C_RED))      # stall roof
	for x in [-9.3, -6.7]:
		for z in [-1.0, 1.0]:
			b.append(box(Vector3(x, 1.2, z), Vector3(0.12, 2.4, 0.12), "wood_planks"))
	b.append(box(Vector3(-8, 0.45, 0), Vector3(2.6, 0.9, 0.8), "wood_planks"))            # stall counter
	b.append_array(fence(Vector3(-12, 0, -2.5), 5.0, 1.2, false, "wood_planks"))

	# ---------------------------------------------------------------- east building row (plaster)
	# NE shop
	b.append_array(room_walls(Vector3(8, 0, -9), Vector3(8, WALL_H, 8), 0.3, "plaster", C_WARM,
		[{"side": "w", "offset": 1.0, "width": 1.6}, {"side": "w", "offset": -2.0, "width": 1.6},
				{"side": "e", "offset": -1.0, "width": 1.6}, {"side": "s", "offset": 1.5, "width": 1.6}]))
	b.append(header(Vector3(4, 0, -8), 1.6, 2.2, WALL_H, 0.3, false, "plaster", C_WARM))
	b.append_array(window(Vector3(4, 0, -11), 1.6, 0.9, 2.2, WALL_H, 0.3, false, "plaster", C_WARM))
	b.append(header(Vector3(12, 0, -10), 1.6, 2.2, WALL_H, 0.3, false, "plaster", C_WARM))
	b.append(header(Vector3(9.5, 0, -5), 1.6, 2.2, WALL_H, 0.3, true, "plaster", C_WARM))
	b.append(box(Vector3(8, WALL_H + 0.15, -9), Vector3(8.3, 0.3, 8.3), "roof_shingles"))
	b.append(box(Vector3(8.5, 0.55, -9), Vector3(0.8, 1.1, 4.0), "wood_planks"))          # shop counter
	b.append(box(Vector3(10.5, 1.0, -11.5), Vector3(2.0, 2.0, 0.5), "wood_planks"))       # shelf
	# SE garage: open gate to the street, door to the right lane
	b.append_array(room_walls(Vector3(8, 0, 9), Vector3(8, 3.2, 8), 0.3, "plaster", C_SAND,
		[{"side": "w", "offset": 0.0, "width": 4.0}, {"side": "e", "offset": 1.0, "width": 1.6}, {"side": "n", "offset": -1.5, "width": 1.6}]))
	b.append(header(Vector3(4, 0, 9), 4.0, 2.4, 3.2, 0.3, false, "plaster", C_SAND))
	b.append(header(Vector3(12, 0, 10), 1.6, 2.2, 3.2, 0.3, false, "plaster", C_SAND))
	b.append(header(Vector3(6.5, 0, 5), 1.6, 2.2, 3.2, 0.3, true, "plaster", C_SAND))
	b.append(box(Vector3(8, 3.35, 9), Vector3(8.3, 0.3, 8.3), "metal_panel", C_RUST))
	b.append_array(car(Vector3(8.5, 0, 9.5), C_DARK, 90.0))
	b.append(box(Vector3(10.5, 0.6, 12.0), Vector3(1.2, 1.2, 1.2), "crate"))
	# gap between east buildings: dumpster + crates
	b.append(box(Vector3(9, 0.7, 0), Vector3(2.2, 1.4, 1.4), "metal_panel", C_GREEN))
	b.append(box(Vector3(6, 0.6, -1.5), Vector3(1.2, 1.2, 1.2), "crate"))

	# ---------------------------------------------------------------- mid street
	# kiosk in the middle with doors north/south and windows east/west
	b.append_array(room_walls(Vector3(0, 0, 0), Vector3(4, 2.8, 4), 0.25, "plaster", C_OCHRE,
		[{"side": "n", "offset": 0.0, "width": 1.4}, {"side": "s", "offset": 0.0, "width": 1.4},
				{"side": "e", "offset": 0.0, "width": 2.0}, {"side": "w", "offset": 0.0, "width": 2.0}]))
	b.append(header(Vector3(0, 0, -2), 1.4, 2.1, 2.8, 0.25, true, "plaster", C_OCHRE))
	b.append(header(Vector3(0, 0, 2), 1.4, 2.1, 2.8, 0.25, true, "plaster", C_OCHRE))
	b.append_array(window(Vector3(-2, 0, 0), 2.0, 1.0, 2.0, 2.8, 0.25, false, "plaster", C_OCHRE))
	b.append_array(window(Vector3(2, 0, 0), 2.0, 1.0, 2.0, 2.8, 0.25, false, "plaster", C_OCHRE))
	b.append(box(Vector3(0, 2.95, 0), Vector3(4.6, 0.3, 4.6), "roof_shingles"))
	# vehicles and barriers
	b.append_array(car(Vector3(-2.5, 0, -12), C_BLUE, 0.0))
	b.append_array(car(Vector3(2.5, 0, 12), C_RED, 180.0))
	b.append(box(Vector3(3.5, 0.5, -6), Vector3(2.2, 1.0, 0.5), "concrete"))
	b.append(box(Vector3(-3.5, 0.5, 6), Vector3(2.2, 1.0, 0.5), "concrete"))
	for z in [-15.0, 15.0]:
		b.append(cylinder(Vector3(-5.5, 2.5, z), 0.16, 5.0, "metal_panel", C_DARK))
		b.append(cylinder(Vector3(5.5, 2.5, z), 0.16, 5.0, "metal_panel", C_DARK))

	# ---------------------------------------------------------------- left lane: alley with garages
	# garage A (north) and B (south), open towards the alley (east)
	for gz in [-10.0, 10.0]:
		b.append_array(room_walls(Vector3(-25, 0, gz), Vector3(8, 3.2, 7), 0.3, "concrete", C_SAND,
			[{"side": "e", "offset": 0.0, "width": 4.0}]))
		b.append(header(Vector3(-21, 0, gz), 4.0, 2.4, 3.2, 0.3, false, "concrete", C_SAND))
		b.append(box(Vector3(-25, 3.35, gz), Vector3(8.3, 0.3, 7.3), "metal_panel", C_RUST))
	b.append_array(car(Vector3(-25, 0, -10), C_WHITE, 90.0))
	b.append(box(Vector3(-26, 0.7, 10), Vector3(2.0, 1.4, 3.0), "metal_panel", C_GREEN))   # workbench
	b.append(cylinder(Vector3(-23, 0.45, 12), 0.6, 0.9, "metal_panel", C_RED))
	# courtyard between the garages: tree, picnic tables, low wall
	b.append(cylinder(Vector3(-23, 1.5, 0), 0.5, 3.0, "wood_planks"))
	b.append(box(Vector3(-23, 3.6, 0), Vector3(4.0, 1.6, 4.0), "grass", C_GREEN, Vector3(0, 30, 0)))
	b.append(box(Vector3(-18, 0.4, -3), Vector3(1.8, 0.8, 0.8), "wood_planks"))
	b.append(box(Vector3(-18, 0.4, 3), Vector3(1.8, 0.8, 0.8), "wood_planks"))
	b.append(box(Vector3(-16, 0.55, -14), Vector3(0.4, 1.1, 4.0), "concrete", C_WARM))
	b.append(box(Vector3(-16, 0.55, 14), Vector3(0.4, 1.1, 4.0), "concrete", C_WARM))
	b.append(box(Vector3(-28, 0.6, 0), Vector3(1.2, 1.2, 1.2), "crate"))

	# ---------------------------------------------------------------- right lane: shop row + roof walk
	# R1 (north) with exterior stairs to its roof on the east side
	b.append_array(room_walls(Vector3(21, 0, -10), Vector3(10, WALL_H, 8), 0.3, "plaster", C_WHITE,
		[{"side": "w", "offset": 0.0, "width": 1.6}, {"side": "s", "offset": -2.0, "width": 1.6}, {"side": "w", "offset": 2.5, "width": 1.6}]))
	b.append(header(Vector3(16, 0, -10), 1.6, 2.2, WALL_H, 0.3, false, "plaster", C_WHITE))
	b.append_array(window(Vector3(16, 0, -7.5), 1.6, 1.0, 2.1, WALL_H, 0.3, false, "plaster", C_WHITE))
	b.append(header(Vector3(19, 0, -6), 1.6, 2.2, WALL_H, 0.3, true, "plaster", C_WHITE))
	b.append(box(Vector3(21, WALL_H + 0.15, -10), Vector3(10.3, 0.3, 8.3), "concrete", C_DARK))
	b.append(box(Vector3(21, WALL_H + 0.75, -14.05), Vector3(10.3, 0.9, 0.2), "plaster", C_WHITE))
	b.append(box(Vector3(21, WALL_H + 0.75, -5.95), Vector3(10.3, 0.9, 0.2), "plaster", C_WHITE))
	b.append(box(Vector3(15.95, WALL_H + 0.75, -10), Vector3(0.2, 0.9, 8.3), "plaster", C_WHITE))
	b.append(box(Vector3(26.05, WALL_H + 0.75, -12), Vector3(0.2, 0.9, 4.0), "plaster", C_WHITE))
	b.append(ramp(Vector3(27.8, 0.0, -1.0), Vector3(27.8, WALL_H + 0.3, -8.0), 3.0, "metal_panel", 0.3, C_DARK))
	b.append(box(Vector3(27.8, WALL_H + 0.15, -8.75), Vector3(3.0, 0.3, 1.5), "metal_panel", C_DARK))
	b.append(box(Vector3(29.35, WALL_H - 1.5, -4.5), Vector3(0.1, 3.0, 7.5), "metal_panel", C_DARK, Vector3(25, 0, 0)))
	b.append(box(Vector3(21, 0.5, -12), Vector3(3.0, 1.0, 0.8), "wood_planks"))
	# R2 (south)
	b.append_array(room_walls(Vector3(21, 0, 10), Vector3(10, WALL_H, 8), 0.3, "plaster", C_SAND,
		[{"side": "w", "offset": 0.0, "width": 1.6}, {"side": "n", "offset": 2.0, "width": 1.6}, {"side": "e", "offset": 0.0, "width": 1.6}]))
	b.append(header(Vector3(16, 0, 10), 1.6, 2.2, WALL_H, 0.3, false, "plaster", C_SAND))
	b.append(header(Vector3(23, 0, 6), 1.6, 2.2, WALL_H, 0.3, true, "plaster", C_SAND))
	b.append(header(Vector3(26, 0, 10), 1.6, 2.2, WALL_H, 0.3, false, "plaster", C_SAND))
	b.append(box(Vector3(21, WALL_H + 0.15, 10), Vector3(10.3, 0.3, 8.3), "roof_shingles"))
	b.append(box(Vector3(21, 0.5, 12), Vector3(3.0, 1.0, 0.8), "wood_planks"))
	# passage between R1 and R2: truck + fence
	b.append(box(Vector3(22, 1.2, 0), Vector3(2.4, 2.4, 6.0), "metal_panel", C_GREEN))     # truck trailer
	b.append(box(Vector3(22, 0.9, 4.0), Vector3(2.2, 1.8, 2.0), "metal_panel", C_DARK))    # truck cab
	b.append_array(fence(Vector3(16, 0, -2.5), 5.0, 1.2, false, "wood_planks"))
	b.append(box(Vector3(14, 0.6, -16), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(14, 0.6, 16), Vector3(1.2, 1.2, 1.2), "crate"))
	# direction markers
	b.append(box(Vector3(0, 4.5, -22.9), Vector3(3.0, 0.6, 0.1), "plaster", C_RED))
	b.append(box(Vector3(0, 4.5, 22.9), Vector3(3.0, 0.6, 0.1), "plaster", C_BLUE))
	return b


func build_detail(d: MapDetail) -> void:
	# light atmosphere: warm rooms behind the windows, glowing pump displays and price sign
	for p in [Vector3(-8, 3.45, -9), Vector3(-8, 3.45, 9), Vector3(8, 3.45, -9), Vector3(8, 3.45, 9)]:
		d.lamp(p, Color(1.0, 0.8, 0.5), 1.0, 7.0)
	d.glow(Vector3(-11.5, 5.0, -13.35), Color(1.0, 0.85, 0.3), 4.5)
	d.bulb(Vector3(-11.5, 4.6, -13.3), Color(1.0, 0.85, 0.3), 1.5, 1.6, 6.0)
	for x in [-3.0, 3.0]:
		d.glow(Vector3(x, 1.25, -18.6), Color(0.3, 1.0, 0.5), 1.0)
	d.bulb(Vector3(0, 3.1, -22.0), Color(1.0, 0.2, 0.15), 1.6, 1.4, 6.0) # red accent under the canopy
	d.bulb(Vector3(0, 2.2, 22.5), Color(1.0, 0.55, 0.2), 1.6, 1.4, 6.0) # dock gate lamp
	# gas station: fascia, lights, pump screens, hoses, price pole
	d.add_box(Vector3(0, 3.6, -15.45), Vector3(14.3, 0.4, 0.12), "plaster", C_RED)
	d.add_box(Vector3(0, 3.6, -22.55), Vector3(14.3, 0.4, 0.12), "plaster", C_RED)
	d.add_box(Vector3(-7.15, 3.6, -19), Vector3(0.12, 0.4, 7.2), "plaster", C_RED)
	d.add_box(Vector3(7.15, 3.6, -19), Vector3(0.12, 0.4, 7.2), "plaster", C_RED)
	for x in [-3.0, 3.0]:
		d.lamp(Vector3(x, 3.42, -19), Color(1.0, 0.95, 0.8), 0.9, 8.0)
		d.add_box(Vector3(x, 1.25, -18.72), Vector3(0.6, 0.35, 0.04), "metal_panel", Color(0.08, 0.12, 0.1))
		d.add_cylinder(Vector3(x + 0.55, 1.0, -18.72), 0.06, 0.8, "rubber")
	d.add_cylinder(Vector3(-11.5, 2.5, -13.5), 0.18, 5.0, "metal_panel", Color(0.35, 0.37, 0.4))
	d.add_box(Vector3(-11.5, 5.0, -13.5), Vector3(1.4, 1.0, 0.15), "plaster", Color(0.9, 0.85, 0.5))
	# street lamps and utility poles with cables along the alley wall
	for z in [-12.0, 12.0]:
		d.lamp_post(Vector3(7.9, 0, z), 5.0, PI)
		d.lamp_post(Vector3(-7.9, 0, -z), 5.0, 0.0)
	for z in [-14.0, 0.0, 14.0]:
		d.utility_pole(Vector3(-29.5, 0, z), 7.0, PI * 0.5)
	for z in [-14.0, 0.0]:
		for x in [-0.85, 0.0, 0.85]:
			d.wire(Vector3(-29.5 + x, 6.65, z), Vector3(-29.5 + x, 6.65, z + 14.0), 0.5)
	# alley and dock clutter (against the outer walls)
	d.barrel(Vector3(-29.2, 0, -10.0), Color(0.55, 0.22, 0.14))
	d.barrel(Vector3(-29.2, 0, -9.0), Color(0.2, 0.32, 0.5))
	d.barrel(Vector3(-29.2, 0, 8.0), Color(0.55, 0.22, 0.14))
	d.pallet(Vector3(-28.8, 0, 3.0), 0.1)
	d.pallet(Vector3(-28.8, 0, -4.0), -0.05)
	d.pallet(Vector3(29.0, 0, 12.0), 0.2)
	d.barrel(Vector3(29.3, 0, 14.0), Color(0.2, 0.32, 0.5))
	d.power_box(Vector3(29.7, 0, -4.0), -PI * 0.5)
	d.power_box(Vector3(-29.7, 0, 20.0), PI * 0.5)
	# road markings
	d.dashed_line(Vector3(0, 0.005, -13.5), Vector3(0, 0.005, 13.5), 0.15, 2.0, 2.0, Color(0.88, 0.8, 0.45))
	d.marking(Vector3(0, 0.006, -14.2), Vector3(10.0, 0.01, 0.4), Color(0.85, 0.85, 0.8))
	d.marking(Vector3(0, 0.006, 14.2), Vector3(10.0, 0.01, 0.4), Color(0.85, 0.85, 0.8))


func get_spawns() -> Array:
	var s: Array = []
	for x in [-24.0, -15.0, -5.0, 5.0, 15.0, 24.0]:
		s.append(spawn(Vector3(x, 0.1, -21.0), 180.0, Teams.Team.RED))
	for x in [-24.0, -15.0, -5.0, 5.0, 15.0, 24.0]:
		# the two middle points stand on the loading dock (1 m high)
		var y := 1.1 if absf(x) < 7.0 else 0.1
		s.append(spawn(Vector3(x, y, 21.0), 0.0, Teams.Team.BLUE))
	s.append(spawn(Vector3(-20, 0.1, 0), 90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-8, WALL_H + 0.4, 9), 90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(21, WALL_H + 0.4, -10), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(14, 0.1, 0), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-8, 0.1, -9), 180.0, Teams.Team.NONE))
	s.append(spawn(Vector3(7.3, 0.1, 7.8), 0.0, Teams.Team.NONE))
	return s


func get_lanes() -> Dictionary:
	return {
		"left": [Vector3(-14, 0, -20), Vector3(-19, 0, -14), Vector3(-19, 0, -5), Vector3(-19, 0, 5), Vector3(-19, 0, 14), Vector3(-14, 0, 20)],
		"mid": [Vector3(0, 0, -20), Vector3(0, 0, -13), Vector3(0, 0, -6), Vector3(-3.5, 0, 0), Vector3(0, 0, 6), Vector3(0, 0, 13), Vector3(0, 0, 20)],
		"right": [Vector3(14, 0, -20), Vector3(14, 0, -13), Vector3(14, 0, -5), Vector3(14, 0, 5), Vector3(14, 0, 13), Vector3(14, 0, 20)],
		"roof": [Vector3(-13.5, 0, 15), Vector3(-13.5, WALL_H + 0.3, 7), Vector3(-8, WALL_H + 0.3, 9), Vector3(27.8, 0, 0), Vector3(27.8, WALL_H + 0.3, -8), Vector3(21, WALL_H + 0.3, -10)],
	}


func get_cover_points() -> Array:
	return [
		Vector3(-12.5, 0, -20), Vector3(12.5, 0, -20), Vector3(-12.5, 0, 20), Vector3(12.5, 0, 20),
		Vector3(3.5, 0, -7), Vector3(-3.5, 0, 7), Vector3(-2.5, 0, -14.5), Vector3(2.5, 0, 14.5),
		Vector3(-16.5, 0, -14), Vector3(-16.5, 0, 14), Vector3(-18, 0, -1.5), Vector3(9, 0, 1.5),
		Vector3(-4.8, 0, -7), Vector3(-4.8, 0, 7), Vector3(-8, WALL_H + 0.3, 6), Vector3(21, WALL_H + 0.3, -7),
	]
