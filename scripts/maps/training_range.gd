extends BlockMap
## Trainingsarena: shooting range (46 x 150 m). The firing line is in the south (z = +60): five lanes with targets at
## 10, 25, 50, 75 and 100 m, a zone row close to the firing line (standing, crouched, behind cover) for studying the hit
## zones, and a combat yard at the north end (cover, stairs, a platform, a house with a window). The dummies are real
## players without a brain (see get_dummies): they show the hit zone and damage, die with the full gore and stand up again.

const C_CONCRETE := Color(0.62, 0.64, 0.66)
const C_DARK := Color(0.3, 0.32, 0.35)
const C_SAFETY := Color(0.9, 0.7, 0.15)
const LANES_X := [-16.0, -8.0, 0.0, 8.0, 16.0]
const FIRING_Z := 60.0


func get_blocks() -> Array:
	var b: Array = []
	b.append(box(Vector3(0, -0.25, 0), Vector3(46, 0.5, 150), "concrete", Color(0.72, 0.72, 0.7)))
	b.append(box(Vector3(0, 0.02, FIRING_Z - 1.0), Vector3(46, 0.04, 6.0), "asphalt")) # firing line apron
	for x in [-23.25, 23.25]:
		b.append(box(Vector3(x, 3.5, 0), Vector3(0.5, 7, 150.5), "concrete", C_DARK))
	for z in [-75.25, 75.25]:
		b.append(box(Vector3(0, 3.5, z), Vector3(46.5, 7, 0.5), "concrete", C_DARK))
	# earth berm behind the targets (stops nothing, looks right) and a back wall at the firing line
	b.append(box(Vector3(0, 1.5, -72.0), Vector3(44, 3, 4), "dirt", Color(0.5, 0.42, 0.32)))
	# lane dividers and shooting benches
	for i in LANES_X.size():
		var x: float = LANES_X[i]
		b.append(box(Vector3(x, 0.55, FIRING_Z - 2.5), Vector3(3.6, 1.1, 0.7), "concrete", C_CONCRETE)) # bench
		b.append(box(Vector3(x, 1.2, FIRING_Z - 2.9), Vector3(3.6, 0.1, 0.9), "wood_planks", Color(0.5, 0.36, 0.24)))
		if i < LANES_X.size() - 1:
			b.append(box(Vector3(x + 4.0, 1.0, FIRING_Z - 4.0), Vector3(0.25, 2.0, 6.0), "concrete", C_CONCRETE))
	# distance markers on the floor (a line and a plaque every lane)
	for d in [10, 25, 50, 75, 100]:
		var z := FIRING_Z - float(d)
		var line := box(Vector3(0, 0.03, z), Vector3(44, 0.06, 0.3), "plaster", C_SAFETY)
		line["collide"] = false
		b.append(line)
	# ---- zone row (z = 44..52): cover walls with dummies behind
	b.append(box(Vector3(-12, 0.6, 46.5), Vector3(3.0, 1.2, 0.4), "concrete", C_CONCRETE))
	b.append(box(Vector3(12, 1.0, 46.5), Vector3(3.0, 2.0, 0.4), "concrete", C_CONCRETE))
	b.append(box(Vector3(0, 0.6, 38.0), Vector3(1.2, 1.2, 1.2), "crate"))
	# ---- combat yard (z -45..-70)
	b.append(box(Vector3(-14, 0.6, -50), Vector3(1.2, 1.2, 4.0), "crate"))
	b.append(box(Vector3(-6, 1.0, -54), Vector3(5.0, 2.0, 0.5), "concrete", C_CONCRETE))
	b.append(box(Vector3(6, 0.6, -52), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(7.4, 0.6, -52.4), Vector3(1.2, 1.2, 1.2), "crate"))
	b.append(box(Vector3(16, 1.5, -48), Vector3(4.0, 3.0, 4.0), "concrete", C_CONCRETE)) # platform +3
	b.append(ramp(Vector3(16, 0, -43), Vector3(16, 3.0, -46), 2.4, "concrete", 0.3, C_CONCRETE))
	# house with a window (breakable glass) and a door
	b.append_array(room_walls(Vector3(-16, 0, -64), Vector3(8, 3.2, 6), 0.3, "brick", null,
		[{"side": "s", "offset": -2.0, "width": 1.6}]))
	b.append_array(window(Vector3(-16, 0, -61), 2.0, 1.0, 2.1, 3.2, 0.3, true, "brick"))
	b.append(box(Vector3(-16, 3.35, -64), Vector3(8.4, 0.3, 6.4), "concrete", C_DARK))
	return b


func build_detail(d: MapDetail) -> void:
	# signs with the distances above every lane, bench lamps and a flag
	for i in LANES_X.size():
		var x: float = LANES_X[i]
		d.add_box(Vector3(x, 3.4, FIRING_Z - 5.0), Vector3(2.4, 0.9, 0.12), "metal_panel", C_DARK)
		d.add_box(Vector3(x, 3.4, FIRING_Z - 5.07), Vector3(2.0, 0.6, 0.04), "lamp", Color(0.95, 0.85, 0.5))
		d.lamp(Vector3(x, 3.1, FIRING_Z - 3.0), Color(1.0, 0.95, 0.85), 0.7, 7.0)
	for z in [-70.0, -20.0, 20.0]:
		d.lamp_post(Vector3(-21.5, 0, z), 5.0, 0.0)
		d.lamp_post(Vector3(21.5, 0, z), 5.0, PI)
	for dd in [10, 25, 50, 75, 100]:
		for x in [-21.0, 21.0]:
			d.add_box(Vector3(x, 1.0, FIRING_Z - float(dd)), Vector3(0.12, 1.6, 1.4), "metal_panel", C_SAFETY)
	d.rail(Vector3(-22.5, 0, FIRING_Z), Vector3(22.5, 0, FIRING_Z), 1.0, 3.0)


func get_spawns() -> Array:
	var s: Array = []
	for x in LANES_X:
		s.append(spawn(Vector3(x, 0.1, FIRING_Z + 5.0), 0.0, Teams.Team.NONE))
	s.append(spawn(Vector3(0, 0.1, -40), 180.0, Teams.Team.NONE))
	for i in 6: # team spawns (the range is no team map, they only keep the map checks happy)
		s.append(spawn(Vector3(-10.0 + float(i) * 4.0, 0.1, FIRING_Z + 8.0), 0.0, Teams.Team.BLUE))
		s.append(spawn(Vector3(-10.0 + float(i) * 4.0, 0.1, -36.0), 180.0, Teams.Team.RED))
	return s


func get_lanes() -> Dictionary:
	var l: Array[Vector3] = [Vector3(-8, 0, 20), Vector3(8, 0, 20), Vector3(0, 0, -20)]
	return {"left": l, "mid": l, "right": l}


func get_cover_points() -> Array:
	return [Vector3(-6, 0, -50), Vector3(6, 0, -50)]


## Dummies: {"pos", "yaw" (degrees), "crouch", "label"}. They face the firing line.
func get_dummies() -> Array:
	var out: Array = []
	var i := 1
	for d in [10, 25, 50, 75, 100]:
		for x in LANES_X:
			if d >= 50 and (x == -16.0 or x == 16.0):
				continue
			out.append({"pos": Vector3(x, 0.05, FIRING_Z - float(d)), "yaw": 180.0, "crouch": false, "label": "%d m" % d})
	# zone row
	out.append({"pos": Vector3(-4.0, 0.05, 50.0), "yaw": 180.0, "crouch": false, "label": "Zonen"})
	out.append({"pos": Vector3(4.0, 0.05, 50.0), "yaw": 180.0, "crouch": true, "label": "Hocke"})
	out.append({"pos": Vector3(-12, 0.05, 45.5), "yaw": 180.0, "crouch": false, "label": "Deckung"})
	out.append({"pos": Vector3(12, 0.05, 45.5), "yaw": 180.0, "crouch": true, "label": "Deckung"})
	# combat yard
	out.append({"pos": Vector3(-6, 0.05, -52.5), "yaw": 180.0, "crouch": false, "label": "Hof"})
	out.append({"pos": Vector3(16, 3.05, -48.0), "yaw": 180.0, "crouch": false, "label": "Plattform"})
	out.append({"pos": Vector3(-16, 0.05, -64.0), "yaw": 180.0, "crouch": false, "label": "Haus"})
	return out
