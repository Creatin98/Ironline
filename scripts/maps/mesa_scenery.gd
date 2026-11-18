class_name MesaScenery
extends RefCounted
## Visual-only dressing of the map Mesa: the red spiral tower in the atrium, wood-clad facades with cantilevered roofs,
## waving banners and bunting (cloth shader), drifting dust, a cloud layer, flower beds, rocks and life on the hills.
## Nothing here has collision: the layout, spawns and navigation of the map are untouched.

const PIT := -1.2
const RED := Color(0.86, 0.22, 0.13)
const RED_DARK := Color(0.66, 0.14, 0.09)
const CONCRETE := Color(0.82, 0.8, 0.76)
const WOOD := Color(0.66, 0.46, 0.3)
const CLOTH_SHADER := "res://assets/shaders/cloth.gdshader"

static var _cloth_mats: Dictionary = {}


# ----------------------------------------------------------------------------- tower

## The landmark of the atrium: a stepped spiral of curved red walls (like stacked, twisted rings) on a clad plinth.
static func tower(d: MapDetail) -> void:
	var base := PIT + 1.0 # top of the fountain basin
	d.add_cylinder(Vector3(0, base + 0.2, 0), 3.05, 0.4, "concrete", CONCRETE)
	var tiers := 7
	var h := 0.95
	var y := base + 0.4
	for k in tiers:
		var r := 1.45 - 0.17 * float(k)
		d.add_cylinder(Vector3(0, y + h * 0.5, 0), 2.0 * (r - 0.14), h, "plaster", Color(0.16, 0.1, 0.09))
		var n := 16
		for i in n:
			var a := float(k) * 0.52 + float(i) * TAU / float(n)
			var chord := 2.0 * r * sin(PI / float(n)) * 0.9
			var pos := Vector3(r * cos(a), y + h * 0.5, r * sin(a))
			d.add_box(pos, Vector3(chord, h * 0.96, 0.1), "plaster", RED if (i + k) % 4 != 0 else RED_DARK, Basis(Vector3.UP, -(a + PI * 0.5)))
		# a thin ledge between the tiers
		d.add_cylinder(Vector3(0, y + 0.02, 0), 2.0 * r + 0.1, 0.06, "concrete", Color(0.55, 0.52, 0.48))
		y += h
	d.add_cylinder(Vector3(0, y + 0.8, 0), 0.16, 1.6, "plaster", RED_DARK)
	# plinth cladding: concrete slabs with a dark joint, like the one in the reference
	var slabs := 14
	for i in slabs:
		var a := TAU * float(i) / float(slabs)
		d.add_box(Vector3(1.74 * cos(a), PIT + 0.5, 1.74 * sin(a)), Vector3(0.82, 1.0, 0.16), "concrete",
				Color(0.7, 0.68, 0.64) if i % 2 == 0 else Color(0.78, 0.76, 0.72), Basis(Vector3.UP, -(a + PI * 0.5)))
	# warm up-lights on the spiral
	d.bulb(Vector3(0, base + 1.2, 0), Color(1.0, 0.45, 0.3), 1.2, 1.4, 6.0)
	d.bulb(Vector3(0, base + 3.8, 0), Color(1.0, 0.5, 0.35), 1.0, 1.2, 6.0)
	d.glow(Vector3(0, y + 1.7, 0), Color(1.0, 0.55, 0.4), 1.0)


# ----------------------------------------------------------------------------- facades

## Wood-clad wall panels and cantilevered white roof slabs (the modern villa look), for both halves.
static func facades(d: MapDetail) -> void:
	for sgn in [-1.0, 1.0]:
		# hall: thick white fascia that overhangs the facade
		d.add_box(Vector3(0, 6.5, sgn * 12.75), Vector3(29.4, 0.55, 10.6), "concrete", Color(0.9, 0.88, 0.84))
		d.add_box(Vector3(0, 6.9, sgn * 12.75), Vector3(29.4, 0.16, 10.6), "concrete", Color(0.6, 0.58, 0.54))
		# street side (z' 17.2) and atrium side (z' 8.3): wood panels between the openings, ground floor and loft
		for z in [17.22, 8.28]:
			for x in [-4.9, 4.9]:
				d.add_box(Vector3(x, 1.5, sgn * z), Vector3(6.0, 2.9, 0.07), "wood_planks", WOOD)
				d.add_box(Vector3(x, 5.0, sgn * z), Vector3(6.0, 2.7, 0.07), "wood_planks", Color(0.74, 0.54, 0.35))
				for i in 7: # thin vertical battens
					d.add_box(Vector3(x - 2.6 + float(i) * 0.87, 3.25, sgn * (z + (0.05 if z > 10.0 else -0.05))), Vector3(0.05, 6.1, 0.05), "wood_planks", Color(0.36, 0.24, 0.15))
		# garage wing: wood strips + a floating canopy over the bays
		d.add_box(Vector3(22.0, 3.05, sgn * 11.28), Vector3(9.4, 2.7, 0.07), "wood_planks", WOOD)
		d.add_box(Vector3(16.6, 3.35, sgn * 6.5), Vector3(1.3, 0.2, 9.6), "concrete", Color(0.9, 0.88, 0.84))
		# slim column rows (white) in front of the atrium arcade
		for x in [-3.0, 3.0]:
			d.add_box(Vector3(x, 1.6, sgn * 7.4), Vector3(0.22, 3.2, 0.22), "concrete", Color(0.92, 0.9, 0.86))
		# glowing LED lines under the fascia and a pink accent sign on the garage
		d.led_strip(Vector3(-13.5, 6.18, sgn * 17.3), Vector3(13.5, 6.18, sgn * 17.3), Color(1.0, 0.82, 0.55), 5.0)
		d.led_strip(Vector3(17.2, 3.1, sgn * 11.4), Vector3(26.8, 3.1, sgn * 11.4), Color(0.3, 0.9, 1.0), 4.0)
		d.add_box(Vector3(22.0, 2.45, sgn * 11.4), Vector3(3.2, 0.5, 0.08), "lamp", Color(1.0, 0.25, 0.55))
		d.glow(Vector3(22.0, 2.45, sgn * 11.6), Color(1.0, 0.3, 0.6), 3.2)


# ----------------------------------------------------------------------------- cloth

static func _cloth_material(color: Color, stripe: float = 0.0, amp: float = 0.18, speed: float = 2.2) -> ShaderMaterial:
	var key := "%s_%.2f_%.2f_%.1f" % [color.to_html(), stripe, amp, speed]
	if _cloth_mats.has(key):
		return _cloth_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(CLOTH_SHADER)
	m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter("stripe_amount", stripe)
	m.set_shader_parameter("amp", amp)
	m.set_shader_parameter("speed", speed)
	_cloth_mats[key] = m
	return m


static func _cloth(root: Node3D, pos: Vector3, size: Vector2, color: Color, yaw: float, stripe: float = 0.0, amp: float = 0.18) -> void:
	var q := QuadMesh.new()
	q.size = size
	q.subdivide_depth = 10
	q.subdivide_width = 4
	q.center_offset = Vector3(0, -size.y * 0.5, 0) # hangs down from `pos`
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _cloth_material(color, stripe, amp)
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)


## Banners in the team colours on both villa facades, bunting across the plazas, flags on the garage roofs.
static func banners(d: MapDetail, root: Node3D) -> void:
	for sgn in [-1.0, 1.0]:
		var team := Color(0.8, 0.14, 0.1) if sgn < 0.0 else Color(0.14, 0.36, 0.82)
		var yaw := 0.0 if sgn > 0.0 else PI
		for x in [-4.9, 4.9]:
			d.bar(Vector3(x - 0.7, 6.0, sgn * 17.45), Vector3(x + 0.7, 6.0, sgn * 17.45), 0.07, 0.07, "metal_panel", Color(0.15, 0.15, 0.16))
			_cloth(root, Vector3(x, 6.0, sgn * 17.47), Vector2(1.1, 3.0), team, yaw, 0.0, 0.14)
		# bunting between the plaza lamps
		var a := Vector3(-9.0, 4.35, sgn * 26.5)
		var b := Vector3(9.0, 4.35, sgn * 26.5)
		var n := 15
		var prev := a
		for i in n + 1:
			var t := float(i) / float(n)
			var p := a.lerp(b, t)
			p.y -= 0.9 * 4.0 * t * (1.0 - t) # sagging line
			if i > 0:
				d.bar(prev, p, 0.025, 0.025, "metal_panel", Color(0.2, 0.2, 0.2))
			prev = p
			if i % 1 == 0 and i < n:
				var cols := [Color(0.85, 0.15, 0.1), Color(0.95, 0.9, 0.8), Color(0.15, 0.4, 0.85), Color(0.95, 0.7, 0.15)]
				_cloth(root, p + Vector3(0.22, 0, 0), Vector2(0.4, 0.5), cols[i % cols.size()], yaw, 0.0, 0.09)
		# flags on the garage roof corner and the sun terrace
		for fp in [Vector3(26.7, 3.5, sgn * 2.3), Vector3(-31.2, 1.8, sgn * 4.3)]:
			d.bar(fp, fp + Vector3(0, 4.2, 0), 0.07, 0.07, "metal_panel", Color(0.78, 0.78, 0.8))
			_cloth(root, fp + Vector3(0.04, 4.15, 0.0), Vector2(1.7, 1.0), team, PI * 0.5, 0.0, 0.24)


# ----------------------------------------------------------------------------- air

## Dust motes and a thin low haze drifting with the wind: lit dust is what makes sunlight visible.
static func dust(root: Node3D) -> void:
	var zones := [
		[Vector3(0, 1.8, -24.5), Vector3(22, 1.8, 3.4), 90], [Vector3(0, 1.8, 24.5), Vector3(22, 1.8, 3.4), 90],
		[Vector3(-23, 1.6, -12), Vector3(9, 1.6, 8), 80], [Vector3(-23, 1.6, 12), Vector3(9, 1.6, 8), 80],
		[Vector3(24, 1.5, -15), Vector3(7, 1.5, 6), 60], [Vector3(24, 1.5, 15), Vector3(7, 1.5, 6), 60],
		[Vector3(0, 1.0, 0), Vector3(6.5, 2.2, 6.5), 70],
	]
	for z in zones:
		_emitter(root, z[0], z[1], int(z[2]), 0.1, Color(1.0, 0.93, 0.78, 0.42), 0.25, 0.6, 9.0)
		_emitter(root, z[0] - Vector3(0, 0.9, 0), z[1] * Vector3(1.0, 0.5, 1.0), maxi(6, int(z[2]) / 10), 4.5, Color(1.0, 0.88, 0.7, 0.035), 0.2, 0.45, 14.0)


static func _emitter(root: Node3D, pos: Vector3, extents: Vector3, amount: int, size: float, color: Color, v_min: float, v_max: float, life: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = MapDetail._glow_material(color)
	p.mesh = q
	p.amount = int(float(amount) * GameSettings.effects_scale())
	p.lifetime = life
	p.preprocess = life # already filled when the round starts
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(1.0, 0.04, 0.35)
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)


# ----------------------------------------------------------------------------- planting and rocks

## Flower beds along the plazas and the garden path, boulders along the walls, planters at the arcade.
static func garden_details(d: MapDetail, bushes: Array, palms: Array) -> void:
	var colors := [Color(0.9, 0.25, 0.5), Color(0.95, 0.75, 0.2), Color(0.85, 0.35, 0.2), Color(0.95, 0.95, 0.9)]
	for sgn in [-1.0, 1.0]:
		# raised beds with low shrubs and flowers
		for x in [-16.0, -11.0, 11.0, 16.0]:
			d.add_box(Vector3(x, 0.2, sgn * 20.2), Vector3(3.6, 0.4, 1.0), "concrete", Color(0.86, 0.82, 0.74))
			for i in 7:
				var sc := 0.38 + 0.12 * float((i * 5 + int(absf(x))) % 3)
				bushes.append({"pos": Vector3(x - 1.5 + float(i) * 0.5, 0.42 + 0.1 * sc, sgn * (20.0 + 0.25 * float(i % 2))), "scale3": Vector3(sc, sc * 0.8, sc), "yaw": float(i) * 1.9 + x,
						"color": colors[(i + int(absf(x))) % colors.size()]})
		# succulents and tall grasses along the perimeter walls
		for i in 16:
			var x := -39.0 + float(i) * 5.3
			bushes.append({"pos": Vector3(x, 0.25, sgn * 27.2), "scale3": Vector3(1.1, 0.5, 1.1), "yaw": float(i) * 2.1, "color": Color(0.5, 0.68, 0.55)})
			bushes.append({"pos": Vector3(x + 1.4, 0.4, sgn * 27.6), "scale3": Vector3(0.9, 0.9, 0.9), "yaw": float(i) * 1.3, "color": Color(0.7, 0.72, 0.4)})
		# boulders at the garden and yard walls (visual rocks)
		var rocks := [Vector3(-31.0, 0.0, 22.5), Vector3(-26.5, 0.0, 26.8), Vector3(-12.0, 0.0, 26.9), Vector3(30.5, 0.0, 26.5), Vector3(19.0, 0.0, 26.9), Vector3(31.0, 0.0, 24.0)]
		for i in rocks.size():
			var r: Vector3 = rocks[i]
			var s := 0.9 + 0.35 * float(i % 3)
			d.add_box(Vector3(r.x, 0.35 * s, sgn * r.z), Vector3(1.5 * s, 0.9 * s, 1.2 * s), "concrete", Color(0.62, 0.55, 0.46),
					Basis(Vector3.UP, float(i) * 1.1) * Basis(Vector3.RIGHT, 0.12 * float(i % 2)))
			d.add_box(Vector3(r.x + 0.7 * s, 0.22 * s, sgn * (r.z - 0.4)), Vector3(0.8 * s, 0.5 * s, 0.7 * s), "concrete", Color(0.7, 0.62, 0.52), Basis(Vector3.UP, 0.7 + float(i)))
		# extra palms behind the walls and around the corners (they frame the view from the plazas)
		for p in [Vector3(-27.0, 0, 29.5), Vector3(-8.0, 0, 29.8), Vector3(9.0, 0, 29.5), Vector3(27.5, 0, 30.0), Vector3(-43.5, 0, 14.0), Vector3(43.8, 0, 12.0), Vector3(-43.0, 0, 3.0), Vector3(-43.0, 0, 22.0), Vector3(43.2, 0, 22.0)]:
			palms.append({"pos": Vector3(p.x, 0.0, sgn * p.z), "scale": 1.5 + 0.2 * float(palms.size() % 3), "yaw": float(palms.size()) * 2.1, "tilt": 0.05 * float((palms.size() % 3) - 1)})


## Hills: height of the squashed-sphere hills at (x, z), or -1000 outside of every hill.
static func hill_height(hills: Array, x: float, z: float) -> float:
	var best := -1000.0
	for h in hills:
		var size: Vector3 = h["size"]
		var local := Basis(Vector3.UP, float(h.get("yaw", 0.0))).inverse() * (Vector3(x, 0.0, z) - Vector3((h["pos"] as Vector3).x, 0.0, (h["pos"] as Vector3).z))
		var nx := local.x / (size.x * 0.5)
		var nz := local.z / (size.z * 0.5)
		var q := 1.0 - nx * nx - nz * nz
		if q > 0.0:
			best = maxf(best, (h["pos"] as Vector3).y + size.y * 0.5 * sqrt(q))
	return best


## Life on the hills: scrub, trees and palms in groups, a few distant white villas with lit windows.
static func hill_life(d: MapDetail, hills: Array, bushes: Array, palms: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260518
	var greens := [Color(0.4, 0.52, 0.28), Color(0.5, 0.58, 0.3), Color(0.32, 0.44, 0.26), Color(0.66, 0.62, 0.36), Color(0.55, 0.66, 0.4)]
	var tries := 0
	var made := 0
	while made < 260 and tries < 3000:
		tries += 1
		var p := Vector2(rng.randf_range(-130.0, 130.0), rng.randf_range(-110.0, 110.0))
		if absf(p.x) < 47.0 and absf(p.y) < 33.0:
			continue # not inside the playing area
		var y := hill_height(hills, p.x, p.y)
		if y < 1.0:
			continue
		if rng.randf() < 0.22:
			palms.append({"pos": Vector3(p.x, y - 0.3, p.y), "scale": rng.randf_range(1.8, 3.0), "yaw": rng.randf() * TAU, "tilt": rng.randf_range(-0.06, 0.06)})
		else:
			# groups of 2-4 bushes
			for i in rng.randi_range(2, 4):
				var q := p + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
				var qy := hill_height(hills, q.x, q.y)
				if qy < 0.5:
					continue
				var sc := rng.randf_range(2.2, 4.6)
				bushes.append({"pos": Vector3(q.x, qy - 0.2, q.y), "scale3": Vector3(sc, sc * 0.75, sc), "yaw": rng.randf() * TAU, "color": greens[rng.randi() % greens.size()]})
		made += 1
	# distant villas (flat white boxes with dark glazing and warm lit windows)
	var villas := [Vector3(-52, 0, -30), Vector3(-46, 0, 52), Vector3(50, 0, -50), Vector3(58, 0, 40), Vector3(-72, 0, 14)]
	for v in villas:
		var y := hill_height(hills, v.x, v.z)
		if y < 6.0:
			continue
		var flat := true
		for c in [Vector2(-7, -4), Vector2(7, -4), Vector2(-7, 4), Vector2(7, 4)]:
			if absf(hill_height(hills, v.x + c.x, v.z + c.y) - y) > 1.2:
				flat = false
		if not flat:
			continue
		d.add_box(Vector3(v.x, y + 2.0, v.z), Vector3(12.0, 4.0, 7.0), "plaster", Color(0.93, 0.9, 0.84))
		d.add_box(Vector3(v.x + 1.0, y + 4.25, v.z), Vector3(13.5, 0.5, 8.0), "concrete", Color(0.85, 0.83, 0.8))
		d.add_box(Vector3(v.x, y + 1.6, v.z + 3.52), Vector3(8.0, 1.6, 0.06), "lamp", Color(1.0, 0.82, 0.5))
		d.glow(Vector3(v.x, y + 1.7, v.z + 4.0), Color(1.0, 0.8, 0.5), 7.0)


## Perimeter: pilasters and a cap on the outside, patches of climbing vines and pink blossoms on the inside, a pool deck
## with sun loungers and umbrellas, lit by warm ground lights.
static func perimeter(d: MapDetail, bushes: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	# cap + outside pilasters on the outer walls (x +-42.25, z +-28.25)
	d.add_box(Vector3(-42.25, 6.1, 0), Vector3(0.9, 0.25, 57.6), "concrete", Color(0.7, 0.66, 0.6))
	d.add_box(Vector3(42.25, 6.1, 0), Vector3(0.9, 0.25, 57.6), "concrete", Color(0.7, 0.66, 0.6))
	d.add_box(Vector3(0, 6.1, -28.25), Vector3(85.6, 0.25, 0.9), "concrete", Color(0.7, 0.66, 0.6))
	d.add_box(Vector3(0, 6.1, 28.25), Vector3(85.6, 0.25, 0.9), "concrete", Color(0.7, 0.66, 0.6))
	for i in range(-3, 4):
		var t := float(i) * 8.0
		d.add_box(Vector3(-42.85, 3.0, t), Vector3(0.5, 6.0, 0.7), "concrete", Color(0.76, 0.72, 0.66))
		d.add_box(Vector3(42.85, 3.0, t), Vector3(0.5, 6.0, 0.7), "concrete", Color(0.76, 0.72, 0.66))
	for i in range(-5, 6):
		var t := float(i) * 7.6
		d.add_box(Vector3(t, 3.0, -28.85), Vector3(0.7, 6.0, 0.5), "concrete", Color(0.76, 0.72, 0.66))
		d.add_box(Vector3(t, 3.0, 28.85), Vector3(0.7, 6.0, 0.5), "concrete", Color(0.76, 0.72, 0.66))
	# inner walls: caps on top, sandstone-coloured gate frames
	for sx in [-1.0, 1.0]:
		d.add_box(Vector3(sx * 32.25, 6.1, 0), Vector3(0.8, 0.22, 57.4), "concrete", Color(0.7, 0.66, 0.6))
		for gz in [0.0, -25.0, 25.0]:
			for dz in [-2.1, 2.1]:
				d.add_box(Vector3(sx * 32.25, 1.6, gz + dz), Vector3(0.9, 3.2, 0.35), "concrete", Color(0.82, 0.78, 0.7))
	for gz in [-10.2, 10.2]:
		for dz in [-1.45, 1.45]:
			d.add_box(Vector3(32.25, 1.6, gz + dz), Vector3(0.9, 3.2, 0.35), "concrete", Color(0.82, 0.78, 0.7))
	# pool decks, loungers and umbrellas (visual only, placed beside the pool, off the walking lines)
	for sgn in [-1.0, 1.0]:
		d.add_box(Vector3(-21.4, 0.03, sgn * 15.5), Vector3(7.0, 0.05, 5.8), "wood_planks", Color(0.66, 0.5, 0.34))
		for i in 3:
			var x := -23.4 + float(i) * 1.7
			d.add_box(Vector3(x, 0.28, sgn * 18.55), Vector3(0.7, 0.14, 1.9), "plaster", Color(0.95, 0.93, 0.88), Basis(Vector3.RIGHT, 0.12 * sgn))
			d.add_box(Vector3(x, 0.14, sgn * 18.55), Vector3(0.6, 0.28, 1.7), "wood_planks", Color(0.4, 0.28, 0.18))
		d.add_cylinder(Vector3(-21.0, 1.1, sgn * 19.1), 0.06, 2.2, "metal_panel", Color(0.8, 0.8, 0.82))
		d.add_cylinder(Vector3(-21.0, 2.15, sgn * 19.1), 3.0, 0.08, "plaster", Color(0.95, 0.9, 0.8) if sgn > 0.0 else Color(0.9, 0.82, 0.7))
		d.add_cylinder(Vector3(-21.0, 2.2, sgn * 19.1), 1.2, 0.12, "plaster", Color(0.8, 0.25, 0.2) if sgn < 0.0 else Color(0.2, 0.4, 0.75))
		d.bulb(Vector3(-24.9, 0.2, sgn * 12.9), Color(1.0, 0.7, 0.4), 1.0, 0.9, 4.0)
		d.bulb(Vector3(-17.1, 0.2, sgn * 18.2), Color(1.0, 0.7, 0.4), 1.0, 0.9, 4.0)


## Interior dressing (visual only, along the walls): rugs, framed art, plants, pendant lights, books.
static func interior(d: MapDetail, bushes: Array) -> void:
	for sgn in [-1.0, 1.0]:
		# salon: rug under the coffee table, abstract art on the inside walls, a plant in every corner, pendant lamps
		d.add_box(Vector3(0, 0.035, sgn * 12.6), Vector3(5.0, 0.03, 3.4), "plaster", Color(0.16, 0.34, 0.4))
		d.add_box(Vector3(0, 0.05, sgn * 12.6), Vector3(4.2, 0.03, 2.6), "plaster", Color(0.82, 0.66, 0.4))
		d.add_box(Vector3(9.0, 0.035, sgn * 12.5), Vector3(3.4, 0.03, 2.6), "plaster", Color(0.5, 0.18, 0.16))
		for x in [-7.0, 7.0, 11.5, -11.5]:
			var col := Color(0.8, 0.3, 0.2) if int(absf(x)) % 2 == 0 else Color(0.2, 0.45, 0.62)
			d.add_box(Vector3(x, 1.75, sgn * 16.82), Vector3(1.7, 1.1, 0.05), "plaster", Color(0.1, 0.1, 0.1))
			d.add_box(Vector3(x - 0.3, 1.78, sgn * 16.79), Vector3(0.8, 0.8, 0.03), "plaster", col)
			d.add_box(Vector3(x + 0.35, 1.7, sgn * 16.79), Vector3(0.6, 0.6, 0.03), "plaster", Color(0.92, 0.82, 0.55))
		for c in [Vector3(-12.3, 0.0, 16.4), Vector3(12.3, 0.0, 9.1), Vector3(12.3, 0.0, 16.4)]:
			d.add_cylinder(Vector3(c.x, 0.3, sgn * c.z), 0.5, 0.6, "plaster", Color(0.85, 0.82, 0.76))
			bushes.append({"pos": Vector3(c.x, 1.0, sgn * c.z), "scale3": Vector3(0.9, 1.3, 0.9), "yaw": c.x, "color": Color(0.3, 0.55, 0.28)})
		for x in [-3.0, 3.0]:
			d.add_cylinder(Vector3(x, 2.15, sgn * 13.0), 0.04, 2.0, "metal_panel", Color(0.15, 0.15, 0.15))
			d.add_cylinder(Vector3(x, 1.2, sgn * 13.0), 0.5, 0.3, "lamp", Color(1.0, 0.82, 0.55))
			d.glow(Vector3(x, 1.2, sgn * 13.0), Color(1.0, 0.8, 0.5), 1.8)
		# books on the shelf, bottles on the counter
		for i in 12:
			d.add_box(Vector3(-12.55, 0.6 + 0.4 * float(i % 4), sgn * (8.9 + 0.15 * float(i))), Vector3(0.2, 0.3, 0.09),
					"plaster", [Color(0.7, 0.2, 0.15), Color(0.2, 0.4, 0.55), Color(0.85, 0.7, 0.3), Color(0.3, 0.5, 0.3)][i % 4])
		# garage: oil stains, tool wall, hanging work lights
		d.add_box(Vector3(21.0, 0.03, sgn * 4.6), Vector3(3.0, 0.02, 2.0), "plaster", Color(0.08, 0.08, 0.09))
		d.add_box(Vector3(24.5, 1.6, sgn * 10.9), Vector3(3.0, 1.2, 0.05), "metal_panel", Color(0.35, 0.37, 0.4))
		for i in 6:
			d.add_box(Vector3(23.4 + 0.45 * float(i), 1.7, sgn * 10.86), Vector3(0.08, 0.5, 0.04), "metal_panel", Color(0.8, 0.2, 0.15) if i % 2 == 0 else Color(0.85, 0.85, 0.88))


# ----------------------------------------------------------------------------- wings

static func _awning(root: Node3D, pos: Vector3, size: Vector2, col: Color, yaw: float) -> void:
	var q := QuadMesh.new()
	q.size = size
	q.subdivide_depth = 4
	q.subdivide_width = 3
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _cloth_material(col, 1.0, 0.04, 1.4)
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(-62.0), yaw, 0.0)
	root.add_child(mi)


## Dressing of the two wings: vines on trellises and a pergola over the vineyard terrace, lanterns, well and fountain water,
## market stalls with striped awnings, bunting, neon signs, rails and lamps. Visual only.
static func wings(d: MapDetail, root: Node3D, bushes: Array) -> void:
	var stripes := [Color(0.85, 0.2, 0.15), Color(0.2, 0.42, 0.8), Color(0.9, 0.7, 0.2), Color(0.25, 0.6, 0.4)]
	for sgn in [-1.0, 1.0]:
		# --- vineyard: trellis posts and wires along the hedge rows, vine leaves and grapes
		for row in [[-39.0, 12.6, 5.0], [-35.0, 15.4, 5.0], [-39.0, 18.2, 5.0]]:
			var cx: float = row[0]
			var cz: float = row[1]
			var len: float = row[2]
			for i in 4:
				var x := cx - len * 0.5 + 0.3 + float(i) * (len - 0.6) / 3.0
				d.add_box(Vector3(x, 2.65, sgn * cz), Vector3(0.07, 1.7, 0.07), "wood_planks", Color(0.42, 0.28, 0.18))
			d.bar(Vector3(cx - len * 0.5 + 0.3, 3.1, sgn * cz), Vector3(cx + len * 0.5 - 0.3, 3.1, sgn * cz), 0.025, 0.025, "metal_panel", Color(0.3, 0.3, 0.3))
			d.bar(Vector3(cx - len * 0.5 + 0.3, 2.65, sgn * cz), Vector3(cx + len * 0.5 - 0.3, 2.65, sgn * cz), 0.025, 0.025, "metal_panel", Color(0.3, 0.3, 0.3))
			for i in 9:
				var x := cx - len * 0.5 + 0.35 + float(i) * (len - 0.7) / 8.0
				bushes.append({"pos": Vector3(x, 2.55 + 0.1 * float(i % 3), sgn * cz), "scale3": Vector3(0.7, 0.9, 0.5), "yaw": float(i) * 1.7 + cx, "color": Color(0.34, 0.5, 0.22) if i % 4 != 0 else Color(0.35, 0.16, 0.4)})
		# pergola over the vineyard terrace (timber beams) and string lights
		for x in [-41.4, -33.2]:
			d.bar(Vector3(x, 4.45, sgn * 11.0), Vector3(x, 4.45, sgn * 19.6), 0.18, 0.22, "wood_planks", WOOD)
		for i in 5:
			var z := 11.4 + float(i) * 2.0
			d.bar(Vector3(-41.5, 4.55, sgn * z), Vector3(-33.1, 4.55, sgn * z), 0.1, 0.12, "wood_planks", WOOD)
		for pz in [11.0, 19.6]:
			for px in [-41.4, -33.2]:
				d.add_box(Vector3(px, 3.1, sgn * pz), Vector3(0.22, 2.6, 0.22), "wood_planks", WOOD)
		d.bulb(Vector3(-37.2, 4.2, sgn * 13.0), Color(1.0, 0.78, 0.45), 1.0, 0.9, 5.0)
		d.bulb(Vector3(-37.2, 4.2, sgn * 17.5), Color(1.0, 0.78, 0.45), 1.0, 0.9, 5.0)
		# cantina: lanterns, sign, lamp, a lit window glow
		d.add_box(Vector3(-38.6, 3.3, sgn * 22.85), Vector3(2.6, 0.45, 0.08), "lamp", Color(1.0, 0.55, 0.2))
		d.glow(Vector3(-38.6, 3.3, sgn * 22.6), Color(1.0, 0.6, 0.25), 3.0)
		d.lamp(Vector3(-38.6, 2.95, sgn * 25.5), Color(1.0, 0.85, 0.6), 0.8, 6.0)
		d.bulb(Vector3(-34.0, 2.6, sgn * 21.5), Color(1.0, 0.7, 0.4), 0.9, 0.9, 5.0)
		# court: lantern posts and the gate lanterns
		d.lamp_post(Vector3(-41.2, 0, sgn * 5.0), 4.0, 0.0)
		d.bulb(Vector3(-32.9, 3.0, sgn * 2.4), Color(1.0, 0.72, 0.4), 0.9, 0.9, 5.0)
		d.bulb(Vector3(-32.9, 3.0, sgn * 25.0), Color(1.0, 0.72, 0.4), 0.9, 0.9, 5.0)
		# --- market: stalls with awnings, bunting, neon, rails
		for st in [[36.0, 4.0, 3.4], [38.0, 7.6, 3.4]]:
			var sx: float = st[0]
			var sz: float = st[1]
			for dx in [-1.6, 1.6]:
				d.bar(Vector3(sx + dx, 0.0, sgn * (sz - 0.55)), Vector3(sx + dx, 2.5, sgn * (sz - 0.55)), 0.06, 0.06, "wood_planks", Color(0.4, 0.27, 0.17))
				d.bar(Vector3(sx + dx, 0.0, sgn * (sz + 0.55)), Vector3(sx + dx, 2.2, sgn * (sz + 0.55)), 0.06, 0.06, "wood_planks", Color(0.4, 0.27, 0.17))
			_awning(root, Vector3(sx, 2.4, sgn * sz), Vector2(st[2], 1.5), stripes[int(sx) % stripes.size()], 0.0 if sgn > 0.0 else PI)
			d.bulb(Vector3(sx, 2.15, sgn * sz), Color(1.0, 0.82, 0.55), 0.9, 0.8, 4.0)
			# goods on the table: little boxes in warm colours
			for i in 5:
				d.add_box(Vector3(sx - 1.1 + float(i) * 0.55, 1.12, sgn * sz), Vector3(0.36, 0.22, 0.36), "plaster", [Color(0.85, 0.25, 0.15), Color(0.95, 0.75, 0.2), Color(0.3, 0.6, 0.3), Color(0.9, 0.5, 0.15), Color(0.6, 0.2, 0.4)][i])
		# bunting across the market court and a neon sign on the shop
		var a := Vector3(33.0, 4.2, sgn * 6.0)
		var b := Vector3(41.8, 4.2, sgn * 6.0)
		var n := 12
		var prev := a
		for i in n + 1:
			var t := float(i) / float(n)
			var p := a.lerp(b, t)
			p.y -= 0.7 * 4.0 * t * (1.0 - t)
			if i > 0:
				d.bar(prev, p, 0.022, 0.022, "metal_panel", Color(0.2, 0.2, 0.2))
			prev = p
			if i < n:
				_cloth(root, p + Vector3(0.2, 0, 0), Vector2(0.38, 0.5), stripes[i % stripes.size()], 0.0 if sgn > 0.0 else PI, 0.0, 0.08)
		d.add_box(Vector3(38.2, 3.0, sgn * 9.78), Vector3(3.4, 0.5, 0.08), "lamp", Color(0.2, 0.9, 1.0))
		d.glow(Vector3(38.2, 3.0, sgn * 9.5), Color(0.3, 0.9, 1.0), 3.4)
		d.add_box(Vector3(35.0, 3.0, sgn * 9.78), Vector3(0.5, 0.5, 0.08), "lamp", Color(1.0, 0.3, 0.55))
		d.led_strip(Vector3(34.3, 3.55, sgn * 9.7), Vector3(42.0, 3.55, sgn * 9.7), Color(1.0, 0.8, 0.5), 4.0)
		d.lamp(Vector3(38.2, 3.1, sgn * 15.5), Color(1.0, 0.88, 0.66), 0.9, 7.0)
		d.lamp_post(Vector3(33.6, 0, sgn * 5.0), 4.2, PI)
		d.bulb(Vector3(32.9, 3.0, sgn * 2.4), Color(1.0, 0.72, 0.4), 0.9, 0.9, 5.0)
		d.bulb(Vector3(32.9, 3.0, sgn * 25.0), Color(1.0, 0.72, 0.4), 0.9, 0.9, 5.0)
		# roof and bridge rails, water tank legs
		d.rail(Vector3(34.3, 3.5, sgn * 21.1), Vector3(42.0, 3.5, sgn * 21.1), 0.9, 2.0, Color(0.82, 0.84, 0.86))
		d.ac_unit(Vector3(36.0, 3.5, sgn * 12.2), 0.0)
		d.vent_stack(Vector3(41.2, 3.5, sgn * 12.0), 1.0)
		d.antenna(Vector3(41.0, 3.5, sgn * 20.0), 3.0)
		d.solar_panel(Vector3(37.0, 3.5, sgn * 19.8), 0.0 if sgn > 0.0 else PI)
		d.solar_panel(Vector3(38.8, 3.5, sgn * 19.8), 0.0 if sgn > 0.0 else PI)
	# well and fountain water (once)
	var water := Color(0.25, 0.7, 0.8)
	d.add_cylinder(Vector3(-37.2, 0.86, 0), 2.2, 0.06, "water")
	d.add_cylinder(Vector3(37.2, 0.66, 0), 2.6, 0.06, "water")
	d.bulb(Vector3(-37.2, 1.2, 0), Color(1.0, 0.75, 0.4), 1.2, 1.0, 5.0)
	d.bulb(Vector3(37.2, 1.2, 0), water, 1.4, 1.2, 5.5)
	for i in 6: # a ring of lanterns around the market fountain
		var ang := TAU * float(i) / 6.0
		d.add_box(Vector3(37.2 + 1.9 * cos(ang), 0.28, 1.9 * sin(ang)), Vector3(0.22, 0.2, 0.22), "lamp", Color(1.0, 0.8, 0.5))
