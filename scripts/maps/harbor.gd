extends BlockMap
## HARBOR â€“ a luxury yacht on open water (inspired by Hijacked).
## Bow = Rot (north, z < 0), stern = Blau (south, z > 0).
## Lanes: port walkway (left, x < -7), superstructure interior (mid), starboard
## walkway (right, x > 7). Vertical play on the sun deck above the superstructure.

const C_HULL := Color(0.93, 0.94, 0.96)
const C_TRIM := Color(0.2, 0.35, 0.55)
const C_DECK := Color(0.78, 0.62, 0.42)
const C_GLASS := Color(0.35, 0.5, 0.6)
const C_DARK := Color(0.25, 0.27, 0.3)
const C_LIFEBOAT := Color(0.95, 0.5, 0.15)
const C_ENGINE := Color(0.45, 0.48, 0.5)
const C_RED := Color(0.75, 0.2, 0.18)
const C_BLUE := Color(0.2, 0.45, 0.8)

const DECK_Y := 0.0
const SUPER_H := 3.2
const ROOF_Y := 3.4


func get_blocks() -> Array:
	var b: Array = []
	# ---------------------------------------------------------------- water & hull
	b.append({"pos": Vector3(0, -2.5, 0), "size": Vector3(260, 0.2, 260), "mat": "water", "collide": false})
	b.append(box(Vector3(0, -0.3, 0), Vector3(30, 0.6, 64), "wood_planks", C_DECK))      # main deck
	b.append(box(Vector3(0, -2.2, 0), Vector3(31, 3.4, 65), "ship_hull", C_HULL))        # hull below deck
	b.append(box(Vector3(0, -0.55, 0), Vector3(31.2, 0.3, 65.2), "metal_panel", C_TRIM)) # trim line
	# bow taper (angled hull pieces, purely visual but collidable so nobody walks off the tip)
	b.append(box(Vector3(-9.5, -1.0, -34.5), Vector3(14, 6, 1.0), "ship_hull", C_HULL, Vector3(0, 35, 0)))
	b.append(box(Vector3(9.5, -1.0, -34.5), Vector3(14, 6, 1.0), "ship_hull", C_HULL, Vector3(0, -35, 0)))
	b.append(box(Vector3(0, -1.0, -36.5), Vector3(4, 6, 1.0), "ship_hull", C_HULL))
	# railings around the deck (1.1 m)
	b.append(box(Vector3(-14.9, 0.55, 0), Vector3(0.1, 1.1, 64), "metal_panel", C_DARK))
	b.append(box(Vector3(14.9, 0.55, 0), Vector3(0.1, 1.1, 64), "metal_panel", C_DARK))
	b.append(box(Vector3(0, 0.55, 31.95), Vector3(30, 1.1, 0.1), "metal_panel", C_DARK))
	b.append(box(Vector3(0, 0.55, -31.95), Vector3(30, 1.1, 0.1), "metal_panel", C_DARK))
	# invisible outer barrier so nobody can jump into the water from the rails
	b.append({"pos": Vector3(0, 3, 32.3), "size": Vector3(30.6, 6, 0.3), "mat": "water", "visible": false})
	b.append({"pos": Vector3(0, 3, -32.3), "size": Vector3(30.6, 6, 0.3), "mat": "water", "visible": false})
	b.append({"pos": Vector3(-15.3, 3, 0), "size": Vector3(0.3, 6, 65), "mat": "water", "visible": false})
	b.append({"pos": Vector3(15.3, 3, 0), "size": Vector3(0.3, 6, 65), "mat": "water", "visible": false})

	# ---------------------------------------------------------------- superstructure (mid lane)
	# outer shell x -7..7, z -13..13; three sections: cabins (north), salon (middle), engine room (south)
	b.append_array(room_walls(Vector3(0, 0, -8.5), Vector3(14, SUPER_H, 9), 0.3, "ship_hull", C_HULL,
		[{"side": "n", "offset": 0.0, "width": 2.0}, {"side": "s", "offset": 0.0, "width": 2.2},
				{"side": "w", "offset": -2.0, "width": 1.6}, {"side": "e", "offset": 2.0, "width": 1.6}]))
	b.append(header(Vector3(0, 0, -13), 2.0, 2.3, SUPER_H, 0.3, true, "ship_hull", C_HULL))
	b.append(header(Vector3(0, 0, -4), 2.2, 2.3, SUPER_H, 0.3, true, "ship_hull", C_HULL))
	b.append(header(Vector3(-7, 0, -10.5), 1.6, 2.2, SUPER_H, 0.3, false, "ship_hull", C_HULL))
	b.append(header(Vector3(7, 0, -6.5), 1.6, 2.2, SUPER_H, 0.3, false, "ship_hull", C_HULL))
	# cabin partitions (two cabins left/right of a corridor)
	b.append(box(Vector3(-2.2, 1.6, -9.5), Vector3(0.2, SUPER_H, 5.0), "plaster", Color(0.9, 0.88, 0.84)))
	b.append(box(Vector3(2.2, 1.6, -9.5), Vector3(0.2, SUPER_H, 5.0), "plaster", Color(0.9, 0.88, 0.84)))
	b.append(box(Vector3(-4.6, 0.35, -11.0), Vector3(2.4, 0.7, 2.0), "plaster", Color(0.85, 0.85, 0.9)))  # bed
	b.append(box(Vector3(4.6, 0.35, -11.0), Vector3(2.4, 0.7, 2.0), "plaster", Color(0.85, 0.85, 0.9)))   # bed
	# salon z -4..4
	b.append_array(room_walls(Vector3(0, 0, 0), Vector3(14, SUPER_H, 8), 0.3, "ship_hull", C_HULL,
		[{"side": "n", "offset": 0.0, "width": 2.2}, {"side": "s", "offset": 0.0, "width": 2.2},
				{"side": "w", "offset": 0.0, "width": 2.4}, {"side": "e", "offset": 0.0, "width": 2.4}]))
	b.append(header(Vector3(0, 0, 4), 2.2, 2.3, SUPER_H, 0.3, true, "ship_hull", C_HULL))
	b.append(header(Vector3(-7, 0, 0), 2.4, 2.3, SUPER_H, 0.3, false, "ship_hull", C_HULL))
	b.append(header(Vector3(7, 0, 0), 2.4, 2.3, SUPER_H, 0.3, false, "ship_hull", C_HULL))
	# salon furniture: bar counter + two sofas
	b.append(box(Vector3(0, 0.55, -2.4), Vector3(4.0, 1.1, 0.8), "wood_planks", C_DECK))
	b.append(box(Vector3(-4.3, 0.35, 1.8), Vector3(1.0, 0.7, 2.6), "plaster", C_TRIM))
	b.append(box(Vector3(4.3, 0.35, 1.8), Vector3(1.0, 0.7, 2.6), "plaster", C_TRIM))
	b.append(box(Vector3(0, 0.3, 2.0), Vector3(1.6, 0.6, 1.0), "wood_planks", C_DECK))
	# engine room z 4..13
	b.append_array(room_walls(Vector3(0, 0, 8.5), Vector3(14, SUPER_H, 9), 0.3, "metal_panel", C_ENGINE,
		[{"side": "n", "offset": 0.0, "width": 2.2}, {"side": "s", "offset": 0.0, "width": 2.0},
				{"side": "w", "offset": 2.0, "width": 1.6}, {"side": "e", "offset": -2.0, "width": 1.6}]))
	b.append(header(Vector3(0, 0, 13), 2.0, 2.3, SUPER_H, 0.3, true, "metal_panel", C_ENGINE))
	b.append(header(Vector3(-7, 0, 10.5), 1.6, 2.2, SUPER_H, 0.3, false, "metal_panel", C_ENGINE))
	b.append(header(Vector3(7, 0, 6.5), 1.6, 2.2, SUPER_H, 0.3, false, "metal_panel", C_ENGINE))
	b.append(box(Vector3(-3.0, 0.8, 8.5), Vector3(2.6, 1.6, 4.0), "metal_panel", C_DARK))   # engine block
	b.append(box(Vector3(3.0, 0.8, 8.5), Vector3(2.6, 1.6, 4.0), "metal_panel", C_DARK))    # engine block
	b.append(cylinder(Vector3(-3.0, 2.3, 8.5), 0.5, 1.4, "metal_panel", C_ENGINE))
	b.append(cylinder(Vector3(3.0, 2.3, 8.5), 0.5, 1.4, "metal_panel", C_ENGINE))
	for z in [5.5, 11.5]:
		b.append(cylinder(Vector3(0, 2.9, z), 0.3, 0.3, "metal_panel", Color(0.8, 0.2, 0.1)))
	# roof / sun deck
	b.append(box(Vector3(0, ROOF_Y - 0.15, 0), Vector3(20, 0.3, 26.6), "ship_hull", C_HULL))
	# sun deck railing with gaps where the stairs arrive (NW corner / SE corner)
	b.append(box(Vector3(0, ROOF_Y + 0.5, -13.25), Vector3(20, 1.0, 0.1), "metal_panel", C_DARK))
	b.append(box(Vector3(0, ROOF_Y + 0.5, 13.25), Vector3(20, 1.0, 0.1), "metal_panel", C_DARK))
	b.append(box(Vector3(-9.95, ROOF_Y + 0.5, 3.5), Vector3(0.1, 1.0, 19.6), "metal_panel", C_DARK))
	b.append(box(Vector3(9.95, ROOF_Y + 0.5, -3.5), Vector3(0.1, 1.0, 19.6), "metal_panel", C_DARK))
	# bridge cabin on the sun deck (blocks the long sightline)
	b.append_array(room_walls(Vector3(0, ROOF_Y, 0), Vector3(6, 2.4, 5), 0.25, "ship_hull", C_HULL,
		[{"side": "w", "offset": 0.0, "width": 1.6}, {"side": "e", "offset": 0.0, "width": 1.6}]))
	b.append(box(Vector3(0, ROOF_Y + 2.5, 0), Vector3(6.4, 0.2, 5.4), "ship_hull", C_HULL))
	b.append(header(Vector3(-3, ROOF_Y, 0), 1.6, ROOF_Y + 2.1, ROOF_Y + 2.4, 0.25, false, "ship_hull", C_HULL))
	b.append(header(Vector3(3, ROOF_Y, 0), 1.6, ROOF_Y + 2.1, ROOF_Y + 2.4, 0.25, false, "ship_hull", C_HULL))
	b.append(box(Vector3(0, ROOF_Y + 0.5, -1.5), Vector3(3.5, 1.0, 0.6), "wood_planks", C_DECK)) # console
	# sun loungers + jacuzzi on the sun deck
	b.append(cylinder(Vector3(0, ROOF_Y + 0.4, 9.0), 3.0, 0.8, "tiles"))
	b.append(cylinder(Vector3(0, ROOF_Y + 0.4, -9.0), 3.0, 0.8, "tiles"))
	for x in [-6.5, 6.5]:
		for z in [-5.0, 5.0]:
			b.append(box(Vector3(x, ROOF_Y + 0.25, z), Vector3(0.8, 0.5, 2.0), "plaster", Color(0.95, 0.95, 0.9)))
	# stairs to the sun deck: port side north, starboard side south
	b.append(ramp(Vector3(-11.5, DECK_Y, -20.5), Vector3(-11.5, ROOF_Y, -13.5), 3.0, "metal_panel", 0.3, C_DARK))
	b.append(ramp(Vector3(11.5, DECK_Y, 20.5), Vector3(11.5, ROOF_Y, 13.5), 3.0, "metal_panel", 0.3, C_DARK))
	b.append(box(Vector3(-11.5, ROOF_Y - 0.15, -13.2), Vector3(3.0, 0.3, 1.0), "metal_panel", C_DARK)) # landing
	b.append(box(Vector3(11.5, ROOF_Y - 0.15, 13.2), Vector3(3.0, 0.3, 1.0), "metal_panel", C_DARK))
	b.append(box(Vector3(-13.1, ROOF_Y - 1.7, -17), Vector3(0.1, 3.0, 7.5), "metal_panel", C_DARK, Vector3(-26, 0, 0))) # stair rail
	b.append(box(Vector3(13.1, ROOF_Y - 1.7, 17), Vector3(0.1, 3.0, 7.5), "metal_panel", C_DARK, Vector3(26, 0, 0)))

	# ---------------------------------------------------------------- side walkways (left/right lanes)
	# lifeboats on davits (cover) â€“ port at z 4, starboard at z -4
	b.append(box(Vector3(-12.5, 1.5, 5), Vector3(2.0, 1.0, 4.5), "metal_panel", C_LIFEBOAT))
	b.append(box(Vector3(12.5, 1.5, -5), Vector3(2.0, 1.0, 4.5), "metal_panel", C_LIFEBOAT))
	b.append(box(Vector3(-12.5, 0.5, 5), Vector3(0.3, 1.0, 0.3), "metal_panel", C_DARK))
	b.append(box(Vector3(12.5, 0.5, -5), Vector3(0.3, 1.0, 0.3), "metal_panel", C_DARK))
	# ventilation stacks and crates along the walkways
	for z in [-8.0, 8.0]:
		b.append(cylinder(Vector3(-9.0, 0.8, z), 1.1, 1.6, "metal_panel", C_HULL))
		b.append(cylinder(Vector3(9.0, 0.8, z), 1.1, 1.6, "metal_panel", C_HULL))
	b.append(box(Vector3(-12.5, 0.6, -5), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(-11.3, 0.6, -5.5), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(12.5, 0.6, 5), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(12.5, 1.8, 5), Vector3(1.2, 1.2, 1.2), "crate"))
	# benches
	b.append(box(Vector3(-13.5, 0.25, 0), Vector3(0.6, 0.5, 3.0), "wood_planks", C_DECK))
	b.append(box(Vector3(13.5, 0.25, 0), Vector3(0.6, 0.5, 3.0), "wood_planks", C_DECK))

	# ---------------------------------------------------------------- bow (Rot) and stern (Blau)
	# bow: jacuzzi, loungers, anchor winch
	b.append(cylinder(Vector3(0, 0.4, -24), 4.0, 0.8, "tiles"))
	b.append(cylinder(Vector3(0, 0.6, -30.5), 1.2, 1.2, "metal_panel", C_DARK))
	for x in [-5.0, 5.0]:
		b.append(box(Vector3(x, 0.25, -18), Vector3(0.8, 0.5, 2.0), "plaster", Color(0.95, 0.95, 0.9)))
	b.append(box(Vector3(-7, 0.5, -24), Vector3(2.5, 1.0, 0.4), "ship_hull", C_HULL))
	b.append(box(Vector3(7, 0.5, -24), Vector3(2.5, 1.0, 0.4), "ship_hull", C_HULL))
	b.append(box(Vector3(0, 0.5, -16), Vector3(5.0, 1.0, 0.4), "ship_hull", C_HULL))  # low wall before superstructure
	# stern: helipad, tender garage crates, bar
	b.append(cylinder(Vector3(0, 0.05, 25), 9.0, 0.1, "asphalt"))
	b.append(cylinder(Vector3(0, 0.08, 25), 1.5, 0.1, "plaster", Color(0.95, 0.9, 0.3)))
	b.append(box(Vector3(-7, 0.5, 24), Vector3(2.5, 1.0, 0.4), "ship_hull", C_HULL))
	b.append(box(Vector3(7, 0.5, 24), Vector3(2.5, 1.0, 0.4), "ship_hull", C_HULL))
	b.append(box(Vector3(0, 0.5, 16), Vector3(5.0, 1.0, 0.4), "ship_hull", C_HULL))
	b.append(box(Vector3(-5, 0.6, 19), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(5, 0.6, 19), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(0, 0.55, 30.5), Vector3(5.0, 1.1, 0.8), "wood_planks", C_DECK)) # stern bar
	# flag colours on the hull for orientation
	b.append(box(Vector3(0, 1.2, -31.8), Vector3(2.0, 0.3, 0.1), "plaster", C_RED))
	b.append(box(Vector3(0, 1.2, 31.8), Vector3(2.0, 0.3, 0.1), "plaster", C_BLUE))
	return b


func build_detail(d: MapDetail) -> void:
	# deck railings with posts and handrails (all four sides, plus the sun deck)
	d.rail(Vector3(-14.82, 0.0, -31.9), Vector3(-14.82, 0.0, 31.9))
	d.rail(Vector3(14.82, 0.0, -31.9), Vector3(14.82, 0.0, 31.9))
	d.rail(Vector3(-14.82, 0.0, 31.88), Vector3(14.82, 0.0, 31.88))
	d.rail(Vector3(-14.82, 0.0, -31.88), Vector3(14.82, 0.0, -31.88))
	d.rail(Vector3(-9.88, ROOF_Y, -9.8), Vector3(-9.88, ROOF_Y, 13.2), 1.0)
	d.rail(Vector3(9.88, ROOF_Y, -13.2), Vector3(9.88, ROOF_Y, 9.8), 1.0)
	d.rail(Vector3(-9.9, ROOF_Y, -13.2), Vector3(9.9, ROOF_Y, -13.2), 1.0)
	d.rail(Vector3(-9.9, ROOF_Y, 13.2), Vector3(9.9, ROOF_Y, 13.2), 1.0)
	# hull: portholes, rubbing strake, waterline stripe
	for side in [-1.0, 1.0]:
		var x: float = side * 15.52
		for z in range(-28, 30, 4):
			d.add_cylinder(Vector3(x, -1.25, float(z) + 1.0), 0.62, 0.05, "metal_panel", Color(0.7, 0.72, 0.74), Basis(Vector3.BACK, PI * 0.5))
			d.add_cylinder(Vector3(x + side * 0.02, -1.25, float(z) + 1.0), 0.46, 0.05, "metal_panel", Color(0.05, 0.08, 0.1), Basis(Vector3.BACK, PI * 0.5))
		d.add_box(Vector3(side * 15.58, -0.95, 0), Vector3(0.12, 0.16, 62), "metal_panel", Color(0.15, 0.17, 0.2))
		d.add_box(Vector3(side * 15.53, -2.55, 0), Vector3(0.1, 0.6, 62), "plaster", Color(0.55, 0.14, 0.12))
	# bollards and lifebuoys along the rails
	for z in range(-24, 28, 8):
		for side in [-1.0, 1.0]:
			d.add_cylinder(Vector3(side * 14.5, 0.22, float(z)), 0.26, 0.45, "metal_panel", Color(0.2, 0.22, 0.25))
			d.add_cylinder(Vector3(side * 14.5, 0.47, float(z)), 0.36, 0.06, "metal_panel", Color(0.2, 0.22, 0.25))
	for z in [-18.0, -2.0, 16.0, 26.0]:
		for side in [-1.0, 1.0]:
			d.add_cylinder(Vector3(side * 14.74, 0.75, z), 0.62, 0.1, "metal_panel", Color(0.9, 0.42, 0.1), Basis(Vector3.BACK, PI * 0.5))
			d.add_cylinder(Vector3(side * 14.74, 0.75, z), 0.34, 0.11, "plaster", Color(0.95, 0.95, 0.95), Basis(Vector3.BACK, PI * 0.5))
	# mast, radar, vents and a dish on the bridge roof (unreachable)
	var roof := Vector3(0, ROOF_Y + 2.6, 0)
	d.antenna(roof + Vector3(1.8, 0, -1.2), 3.6)
	d.add_cylinder(roof + Vector3(-1.6, 0.9, 1.0), 0.14, 1.8, "metal_panel", Color(0.5, 0.52, 0.55))
	d.add_box(roof + Vector3(-1.6, 1.85, 1.0), Vector3(1.6, 0.08, 0.18), "metal_panel", Color(0.7, 0.72, 0.75))
	d.add_cylinder(roof + Vector3(0.2, 0.3, 1.5), 1.0, 0.6, "plaster", Color(0.95, 0.95, 0.95))
	d.vent_stack(roof + Vector3(-1.5, 0, -1.6), 0.9)
	d.vent_stack(roof + Vector3(0.6, 0, -1.7), 0.7)
	# interior lighting
	d.lamp(Vector3(0, 3.05, -8.5), Color(1.0, 0.9, 0.72), 1.1, 9.0)
	d.lamp(Vector3(0, 3.05, 0), Color(1.0, 0.92, 0.78), 1.2, 10.0)
	d.lamp(Vector3(0, 3.05, 8.5), Color(1.0, 0.72, 0.45), 1.1, 9.0)
	d.lamp(Vector3(0, ROOF_Y + 2.35, 0), Color(0.85, 0.92, 1.0), 0.8, 6.0)
	# helipad ring and H
	d.marking(Vector3(0, 0.142, 25), Vector3(0.35, 0.01, 3.4), Color(0.92, 0.92, 0.9))
	d.marking(Vector3(-1.1, 0.142, 25), Vector3(0.35, 0.01, 3.4), Color(0.92, 0.92, 0.9))
	d.marking(Vector3(1.1, 0.142, 25), Vector3(0.35, 0.01, 3.4), Color(0.92, 0.92, 0.9))
	d.add_cylinder(Vector3(0, 0.101, 25), 8.6, 0.01, "plaster", Color(0.92, 0.92, 0.9))
	d.add_cylinder(Vector3(0, 0.107, 25), 8.1, 0.01, "asphalt", Color(0.6, 0.6, 0.62))
	# deck equipment: winch cables, tender crates, fire cabinets on the superstructure
	for side in [-1.0, 1.0]:
		for z in [-10.5, -2.0, 6.0]:
			d.add_box(Vector3(side * 7.25, 1.2, z), Vector3(0.18, 0.7, 0.5), "metal_panel", Color(0.7, 0.14, 0.12))
		d.pallet(Vector3(side * 12.2, 0.0, 22.0 * -side), 0.4)
		d.barrel(Vector3(side * 13.6, 0.0, 12.0 * side), Color(0.75, 0.75, 0.78))
	d.pallet(Vector3(-5.0, 0.0, 19.0), 0.0)


func get_spawns() -> Array:
	var s: Array = []
	for x in [-11.0, -6.0, -2.0, 2.0, 6.0, 11.0]:
		s.append(spawn(Vector3(x, 0.1, -28.0), 180.0, Teams.Team.RED))
	for x in [-11.0, -6.0, -2.0, 2.0, 6.0, 11.0]:
		s.append(spawn(Vector3(x, 0.1, 28.0), 0.0, Teams.Team.BLUE))
	s.append(spawn(Vector3(-12.5, 0.1, -12.0), 150.0, Teams.Team.NONE))
	s.append(spawn(Vector3(12.5, 0.1, 12.0), -30.0, Teams.Team.NONE))
	s.append(spawn(Vector3(-6.5, ROOF_Y + 0.1, -9.0), 90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(6.5, ROOF_Y + 0.1, 9.0), -90.0, Teams.Team.NONE))
	s.append(spawn(Vector3(0, 0.1, -9.5), 180.0, Teams.Team.NONE))
	s.append(spawn(Vector3(0, 0.1, 8.0), 0.0, Teams.Team.NONE))
	return s


func get_lanes() -> Dictionary:
	return {
		"left": [Vector3(-6, 0, -26), Vector3(-11, 0, -18), Vector3(-11, 0, -8), Vector3(-11, 0, 0), Vector3(-11, 0, 8), Vector3(-11, 0, 18), Vector3(-6, 0, 26)],
		"mid": [Vector3(0, 0, -22), Vector3(0, 0, -14), Vector3(0, 0, -9.5), Vector3(0, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, 14), Vector3(0, 0, 22)],
		"right": [Vector3(6, 0, -26), Vector3(11, 0, -18), Vector3(11, 0, -8), Vector3(11, 0, 0), Vector3(11, 0, 8), Vector3(11, 0, 18), Vector3(6, 0, 26)],
		"roof": [Vector3(-11.5, ROOF_Y, -14), Vector3(-6, ROOF_Y, -8), Vector3(-6, ROOF_Y, 6), Vector3(6, ROOF_Y, -6), Vector3(6, ROOF_Y, 8), Vector3(11.5, ROOF_Y, 14)],
	}


func get_cover_points() -> Array:
	return [
		Vector3(-12.5, 0, 2.0), Vector3(12.5, 0, -2.0), Vector3(-7, 0, -22.5), Vector3(7, 0, 22.5),
		Vector3(0, 0, -17.2), Vector3(0, 0, 17.2), Vector3(-4.3, 0, 3.5), Vector3(4.3, 0, 3.5),
		Vector3(-3, 0, 11), Vector3(3, 0, 6), Vector3(-6.5, ROOF_Y, -3.5), Vector3(6.5, ROOF_Y, 3.5),
	]
