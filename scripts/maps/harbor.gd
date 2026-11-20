extends BlockMap
## HARBOR – Midnight Luxury Superyacht (104m x 36m)

const C_GELCOAT := Color(0.88, 0.90, 0.94)
const C_NAVY := Color(0.06, 0.12, 0.24)
const C_TEAK := Color(0.58, 0.38, 0.20)
const C_MARBLE := Color(0.92, 0.93, 0.95)
const C_CHROME := Color(0.85, 0.88, 0.92)
const C_BRASS := Color(0.86, 0.68, 0.32)
const C_DARK := Color(0.11, 0.13, 0.17)
const C_RED := Color(0.85, 0.22, 0.18)
const C_BLUE := Color(0.18, 0.52, 0.92)

const DECK_Y := 0.0
const LOWER_Y := -3.4
const UPPER_Y := 3.4

var _my_time: float = 0.0
var _my_ocean_mat: ShaderMaterial
var _my_spray: GPUParticles3D
var _my_liner: Node3D


func _ready() -> void:
	map_display_name = "Harbor"
	kill_y = -25.0
	atmosphere_preset = "clear_day"
	super._ready()
	_setup_midnight_atmosphere()
	_upgrade_reflective_materials()
	_build_seamless_yacht_hull()
	_build_midnight_ocean_and_liner()


func _process(delta: float) -> void:
	super._process(delta)
	_my_time += delta
	var w1 := sin(_my_time * 1.45)
	var w2 := sin(_my_time * 2.55 + 1.1)
	var wave_force := w1 * 0.7 + w2 * 0.3

	var ocean := get_node_or_null("MidnightStormOcean") as Node3D
	if ocean != null:
		ocean.position.y = -4.2 - w1 * 0.32
		ocean.rotation_degrees = Vector3(-cos(_my_time * 1.1) * 0.85, 0.0, -wave_force * 1.3)

	if _my_ocean_mat != null:
		_my_ocean_mat.set_shader_parameter("ship_speed_offset", _my_time * 6.8)

	if _my_liner != null:
		_my_liner.position.y = -1.6 + sin(_my_time * 1.0) * 0.55
		_my_liner.rotation_degrees = Vector3(cos(_my_time * 0.8) * 1.1, -28.0, sin(_my_time * 0.9) * 1.3)

	if _my_spray != null:
		if absf(wave_force) > 0.78:
			var side := signf(wave_force)
			_my_spray.position = Vector3(side * 17.2, 0.45, randf_range(-26.0, 26.0))
			var pmat := _my_spray.process_material as ParticleProcessMaterial
			if pmat != null:
				pmat.direction = Vector3(-side * 0.92, 1.15, -0.45).normalized()
			_my_spray.emitting = true
		else:
			_my_spray.emitting = false


func get_blocks() -> Array:
	var b: Array = []

	# 1. Spiegelndes Teakholz-Hauptdeck
	b.append(box(Vector3(0, -0.25, 0), Vector3(13.2, 0.5, 76.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, -22.5), Vector3(34.6, 0.5, 31.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, 22.5), Vector3(34.6, 0.5, 31.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(-13.9, -0.25, 0), Vector3(6.8, 0.5, 14.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(13.9, -0.25, 0), Vector3(6.8, 0.5, 14.0), "wood_planks", C_TEAK))

	# 2. Heller Maschinenraum-Keller (y = -3.4)
	b.append(box(Vector3(0, LOWER_Y - 0.35, 0), Vector3(25.0, 0.7, 54.0), "metal_panel", Color(0.28, 0.32, 0.38)))
	b.append(box(Vector3(-12.2, LOWER_Y + 1.7, 0), Vector3(0.6, 3.6, 54.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(12.2, LOWER_Y + 1.7, 0), Vector3(0.6, 3.6, 54.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, LOWER_Y + 1.7, -26.8), Vector3(25.0, 3.6, 0.6), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, LOWER_Y + 1.7, 26.8), Vector3(25.0, 3.6, 0.6), "ship_hull", C_GELCOAT))
	for z in [-13.5, 13.5]:
		for side in [-1.0, 1.0]:
			var ex: float = side * 4.4
			b.append(box(Vector3(ex, LOWER_Y + 0.85, z), Vector3(2.2, 1.7, 5.4), "metal_panel", C_NAVY))
			b.append(box(Vector3(ex, LOWER_Y + 1.85, z), Vector3(1.5, 0.35, 4.8), "metal_panel", C_CHROME))
			for cz in [-1.6, 0.0, 1.6]:
				b.append(cylinder(Vector3(ex - 0.45, LOWER_Y + 2.35, z + cz), 0.36, 1.1, "metal_panel", C_BRASS))
				b.append(cylinder(Vector3(ex + 0.45, LOWER_Y + 2.35, z + cz), 0.36, 1.1, "metal_panel", C_CHROME))
	b.append(box(Vector3(0, LOWER_Y + 0.6, 0), Vector3(3.8, 1.2, 1.8), "metal_panel", C_DARK))
	b.append(box(Vector3(0, LOWER_Y + 1.25, 0), Vector3(4.0, 0.1, 2.0), "metal_panel", C_CHROME))
	b.append(ramp(Vector3(-8.6, DECK_Y, -6.2), Vector3(-8.6, LOWER_Y, 3.8), 3.6, "wood_planks", 0.3, C_TEAK))
	b.append(ramp(Vector3(8.6, DECK_Y, 6.2), Vector3(8.6, LOWER_Y, -3.8), 3.6, "wood_planks", 0.3, C_TEAK))

	# 3. Schanzkleid & lückenlose Barrieren
	b.append(box(Vector3(-17.2, 0.22, 0), Vector3(0.3, 0.44, 76.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(17.2, 0.22, 0), Vector3(0.3, 0.44, 76.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.22, -37.9), Vector3(34.6, 0.44, 0.3), "ship_hull", C_GELCOAT))
	b.append({"pos": Vector3(0, 3.0, 44.0), "size": Vector3(35.0, 6.0, 0.5), "mat": "water", "visible": false})
	b.append({"pos": Vector3(0, 3.0, -44.0), "size": Vector3(35.0, 6.0, 0.5), "mat": "water", "visible": false})
	b.append({"pos": Vector3(-17.4, 3.0, 0), "size": Vector3(0.5, 6.0, 88.0), "mat": "water", "visible": false})
	b.append({"pos": Vector3(17.4, 3.0, 0), "size": Vector3(0.5, 6.0, 88.0), "mat": "water", "visible": false})

	# 4. Bug-Deck (Rot) & Heck-Helipad (Blau)
	b.append(cylinder(Vector3(0, 0.38, -32.2), 3.8, 0.76, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, 0.68, -32.2), 3.2, 0.14, "water", Color(0.12, 0.85, 0.96)))
	b.append(cylinder(Vector3(0, 0.55, -42.0), 1.1, 1.1, "metal_panel", C_CHROME))
	b.append(box(Vector3(-6.8, 0.55, -31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(6.8, 0.55, -31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, -26.8), Vector3(7.4, 1.1, 0.6), "ship_hull", C_GELCOAT))

	b.append(cylinder(Vector3(0, 0.03, 33.5), 8.4, 0.06, "asphalt", C_DARK))
	b.append(cylinder(Vector3(0, 0.05, 33.5), 1.5, 0.06, "metal_panel", C_BRASS))
	b.append(box(Vector3(-6.8, 0.55, 31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(6.8, 0.55, 31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, 26.8), Vector3(7.4, 1.1, 0.6), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.54, 41.2), Vector3(6.8, 1.08, 1.0), "wood_planks", C_TEAK))
	# 5. Offenes Mitteldeck (Marmor-Infinity-Pool)
	b.append(cylinder(Vector3(0, 0.36, 0), 3.6, 0.72, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, 0.68, 0), 3.0, 0.14, "water", Color(0.12, 0.86, 0.96)))
	b.append(box(Vector3(-4.5, 0.44, -4.6), Vector3(2.2, 0.88, 0.85), "wood_planks", C_TEAK))
	b.append(box(Vector3(4.5, 0.44, 4.6), Vector3(2.2, 0.88, 0.85), "wood_planks", C_TEAK))

	# 6. Nord-Deckhaus: VIP-Lounge & Cocktail-Bar
	b.append_array(room_walls(Vector3(0, 0, -16.0), Vector3(13.2, 3.2, 15.0), 0.32, "ship_hull", C_GELCOAT,
		[{"side": "n", "offset": 0.0, "width": 2.6}, {"side": "s", "offset": 0.0, "width": 2.8},
		 {"side": "w", "offset": -2.5, "width": 2.2}, {"side": "e", "offset": 2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, -23.5), 2.6, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(0, 0, -8.5), 2.8, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-6.6, 0, -18.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(6.6, 0, -13.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.52, -19.2), Vector3(5.0, 1.04, 0.95), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, 1.08, -19.2), Vector3(5.2, 0.1, 1.15), "tiles", C_MARBLE))
	for hx in [-1.8, -0.6, 0.6, 1.8]:
		b.append(cylinder(Vector3(hx, 0.38, -18.2), 0.38, 0.76, "metal_panel", C_BRASS))
	b.append(box(Vector3(-4.0, 0.35, -13.0), Vector3(1.1, 0.7, 3.4), "metal_panel", C_NAVY))
	b.append(box(Vector3(4.0, 0.35, -13.0), Vector3(1.1, 0.7, 3.4), "metal_panel", C_NAVY))

	# Oberdeck Nord (100% stolperfreie Treppe)
	b.append(box(Vector3(0, UPPER_Y - 0.15, -16.0), Vector3(14.8, 0.3, 16.4), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.02, -16.0), Vector3(14.0, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.22, -8.0), Vector3(14.8, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(2.2, UPPER_Y + 0.22, -24.0), Vector3(10.4, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-7.3, UPPER_Y + 0.22, -14.5), Vector3(0.25, 0.44, 13.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(7.3, UPPER_Y + 0.22, -16.0), Vector3(0.25, 0.44, 16.0), "ship_hull", C_GELCOAT))
	b.append(ramp(Vector3(-5.2, DECK_Y, -30.2), Vector3(-5.2, UPPER_Y + 0.05, -24.0), 3.0, "wood_planks", 0.28, C_TEAK))

	# 7. Süd-Deckhaus: Disco / Club-Lounge
	b.append_array(room_walls(Vector3(0, 0, 16.0), Vector3(13.2, 3.2, 15.0), 0.32, "ship_hull", C_GELCOAT,
		[{"side": "n", "offset": 0.0, "width": 2.8}, {"side": "s", "offset": 0.0, "width": 2.6},
		 {"side": "w", "offset": 2.5, "width": 2.2}, {"side": "e", "offset": -2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, 8.5), 2.8, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(0, 0, 23.5), 2.6, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-6.6, 0, 18.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(6.6, 0, 13.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.03, 15.2), Vector3(5.6, 0.06, 5.4), "tiles", C_NAVY))
	b.append(box(Vector3(0, 0.56, 19.6), Vector3(3.8, 1.12, 1.0), "metal_panel", C_DARK))
	b.append(box(Vector3(0, 1.15, 19.6), Vector3(4.0, 0.08, 1.1), "metal_panel", C_CHROME))
	b.append(box(Vector3(-2.6, 1.1, 19.8), Vector3(0.9, 2.2, 0.9), "metal_panel", C_DARK))
	b.append(box(Vector3(2.6, 1.1, 19.8), Vector3(0.9, 2.2, 0.9), "metal_panel", C_DARK))
	b.append(box(Vector3(-4.2, 0.35, 14.5), Vector3(1.0, 0.7, 3.4), "metal_panel", C_NAVY))
	b.append(box(Vector3(4.2, 0.35, 14.5), Vector3(1.0, 0.7, 3.4), "metal_panel", C_NAVY))

	# Oberdeck Süd (100% stolperfreie Treppe)
	b.append(box(Vector3(0, UPPER_Y - 0.15, 16.0), Vector3(14.8, 0.3, 16.4), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.02, 16.0), Vector3(14.0, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.22, 8.0), Vector3(14.8, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-2.2, UPPER_Y + 0.22, 24.0), Vector3(10.4, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-7.3, UPPER_Y + 0.22, 16.0), Vector3(0.25, 0.44, 16.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(7.3, UPPER_Y + 0.22, 14.5), Vector3(0.25, 0.44, 13.0), "ship_hull", C_GELCOAT))
	b.append(ramp(Vector3(5.2, DECK_Y, 30.2), Vector3(5.2, UPPER_Y + 0.05, 24.0), 3.0, "wood_planks", 0.28, C_TEAK))

	# 8. Kommandobrücke mit warm-bernsteinfarbenem Cockpit (wie Referenzbild 1)
	b.append_array(room_walls(Vector3(0, UPPER_Y, 15.5), Vector3(7.4, 2.35, 6.0), 0.26, "ship_hull", C_GELCOAT,
		[{"side": "w", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		 {"side": "n", "offset": -1.5, "width": 1.8}, {"side": "n", "offset": 1.5, "width": 1.8}]))
	for wx in [-1.5, 1.5]:
		b.append(header(Vector3(wx, 0, 12.5), 1.8, UPPER_Y, UPPER_Y + 0.85, 0.26, true, "ship_hull", C_GELCOAT))
		b.append(header(Vector3(wx, 0, 12.5), 1.8, UPPER_Y + 1.98, UPPER_Y + 2.35, 0.26, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-3.7, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.02, UPPER_Y + 2.35, 0.26, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(3.7, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.02, UPPER_Y + 2.35, 0.26, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 2.45, 15.5), Vector3(8.0, 0.22, 6.6), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.52, 13.4), Vector3(5.2, 1.04, 0.85), "metal_panel", C_DARK))
	b.append(box(Vector3(0, UPPER_Y + 1.06, 13.4), Vector3(5.3, 0.08, 0.92), "wood_planks", C_TEAK))
	for mx in [-1.4, 0.0, 1.4]:
		b.append(box(Vector3(mx, UPPER_Y + 1.32, 13.2), Vector3(0.85, 0.45, 0.08), "metal_panel", Color(0.05, 0.45, 0.65), Vector3(-25, 0, 0)))
	b.append(cylinder(Vector3(0, UPPER_Y + 1.15, 13.9), 0.36, 0.08, "metal_panel", C_BRASS))
	b.append(box(Vector3(0.75, UPPER_Y + 1.18, 13.75), Vector3(0.28, 0.24, 0.22), "metal_panel", C_CHROME))
	b.append(box(Vector3(0, UPPER_Y + 0.45, 14.9), Vector3(0.85, 0.9, 0.85), "metal_panel", C_NAVY))
	b.append(box(Vector3(0, UPPER_Y + 1.05, 14.55), Vector3(0.85, 0.8, 0.16), "metal_panel", C_NAVY))
	b.append(box(Vector3(-2.4, UPPER_Y + 0.48, 16.8), Vector3(1.8, 0.96, 1.1), "wood_planks", C_TEAK))
	b.append(box(Vector3(-4.9, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "ship_hull", C_GELCOAT, Vector3(-15, 0, -10)))
	b.append(box(Vector3(4.9, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "ship_hull", C_GELCOAT, Vector3(-15, 0, 10)))
	b.append(box(Vector3(0, UPPER_Y + 4.5, 17.8), Vector3(8.8, 0.36, 1.5), "ship_hull", C_GELCOAT))

	# 9. Außen-Promenaden & Team-Markierungen
	for z in [-16.0, 16.0]:
		b.append(box(Vector3(-13.2, 1.05, z), Vector3(1.8, 0.85, 4.8), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(13.2, 1.05, z), Vector3(1.8, 0.85, 4.8), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(-13.2, 1.48, z), Vector3(2.0, 0.22, 5.0), "metal_panel", C_NAVY))
		b.append(box(Vector3(13.2, 1.48, z), Vector3(2.0, 0.22, 5.0), "metal_panel", C_NAVY))
	for z in [-24.0, -9.0, 9.0, 24.0]:
		b.append(cylinder(Vector3(-14.6, 0.65, z), 0.72, 1.3, "ship_hull", C_GELCOAT))
		b.append(cylinder(Vector3(14.6, 0.65, z), 0.72, 1.3, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, -43.2), Vector3(2.6, 0.25, 0.15), "ship_hull", C_RED))
	b.append(box(Vector3(0, 0.55, 43.2), Vector3(2.6, 0.25, 0.15), "ship_hull", C_BLUE))
	return b


func build_detail(d: MapDetail) -> void:
	# Warmgoldene Deck-Spots entlang der Reling (wie Referenzbild 6)
	for rz in range(-34, 38, 6):
		d.bulb(Vector3(-16.9, 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)
		d.bulb(Vector3(16.9, 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)

	# Lila-magenta Unterdeck-Lichtschächte am Mitteldeck -> strahlen lila aufs Teakholz (wie Referenzbild 3!)
	for mz in [-4.5, 0.0, 4.5]:
		d.add_box(Vector3(-6.45, 0.38, mz), Vector3(0.18, 0.58, 2.4), "metal_panel", C_DARK)
		d.add_box(Vector3(6.45, 0.38, mz), Vector3(0.18, 0.58, 2.4), "metal_panel", C_DARK)
		d.led_strip(Vector3(-6.56, 0.38, mz - 1.0), Vector3(-6.56, 0.38, mz + 1.0), Color(0.88, 0.25, 1.0), 5.2)
		d.led_strip(Vector3(6.56, 0.38, mz - 1.0), Vector3(6.56, 0.38, mz + 1.0), Color(0.88, 0.25, 1.0), 5.2)
		d.lamp(Vector3(-7.4, 0.65, mz), Color(0.85, 0.28, 1.0), 1.4, 8.0)
		d.lamp(Vector3(7.4, 0.65, mz), Color(0.85, 0.28, 1.0), 1.4, 8.0)

	# Lila Eingangs-Lichtbalken über allen 8 Türen
	var door_bars := [
		{"a": Vector3(-1.3, 2.42, -23.68), "b": Vector3(1.3, 2.42, -23.68)},
		{"a": Vector3(-1.4, 2.42, -8.32), "b": Vector3(1.4, 2.42, -8.32)},
		{"a": Vector3(-6.78, 2.42, -19.6), "b": Vector3(-6.78, 2.42, -17.4)},
		{"a": Vector3(6.78, 2.42, -14.6), "b": Vector3(6.78, 2.42, -12.4)},
		{"a": Vector3(-1.4, 2.42, 8.32), "b": Vector3(1.4, 2.42, 8.32)},
		{"a": Vector3(-1.3, 2.42, 23.68), "b": Vector3(1.3, 2.42, 23.68)},
		{"a": Vector3(-6.78, 2.42, 17.4), "b": Vector3(-6.78, 2.42, 19.6)},
		{"a": Vector3(6.78, 2.42, 12.4), "b": Vector3(6.78, 2.42, 14.6)}
	]
	for db in door_bars:
		d.led_strip(db["a"], db["b"], Color(0.76, 0.24, 1.0), 4.8)

	# Strahlende cyan-blaue Unterwasser-Lichtkegel rund ums Schiff (wie Referenzbild 4!) + Heck-Lichtbalken (Bild 2!)
	for uz in range(-36, 40, 8):
		d.bulb(Vector3(-17.85, -1.5, float(uz)), Color(0.18, 0.78, 1.0), 4.8, 3.6, 18.0)
		d.bulb(Vector3(17.85, -1.5, float(uz)), Color(0.18, 0.78, 1.0), 4.8, 3.6, 18.0)
	d.bulb(Vector3(0.0, -1.5, 47.0), Color(0.18, 0.82, 1.0), 5.5, 4.0, 20.0)
	d.bulb(Vector3(0.0, -1.5, -49.0), Color(0.18, 0.82, 1.0), 5.0, 3.8, 18.0)
	d.led_strip(Vector3(-4.2, 0.65, 42.8), Vector3(4.2, 0.65, 42.8), Color(0.20, 0.55, 1.0), 6.0)

	# Detaillierter Hauptmast mit Radar-Kuppel & Flutlicht-Scheinwerfern auf dem Nord-Oberdeck (wie Bild 3 & 5!)
	var mast := Vector3(0.0, UPPER_Y, -16.0)
	d.add_box(mast + Vector3(0, 0.25, 0), Vector3(2.0, 0.5, 2.0), "metal_panel", C_DARK)
	d.add_cylinder(mast + Vector3(0, 3.8, 0), 0.30, 7.6, "metal_panel", C_DARK)
func _setup_midnight_atmosphere() -> void:
	if has_node("HarborDistantIslands"):
		get_node("HarborDistantIslands").visible = false

	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment

	var sky_shd := Shader.new()
	sky_shd.code = "shader_type sky;\nfloat hash(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}\nfloat noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}\nfloat fbm(vec2 p){float v=0.0;float a=0.5;for(int i=0;i<6;i++){v+=a*noise(p);p=p*2.04+vec2(2.3,6.8);a*=0.5;}return v;}\nvoid sky(){vec3 d=normalize(EYEDIR);vec3 moon_dir=normalize(LIGHT0_DIRECTION);float h=clamp(d.y,0.004,1.0);vec3 col=mix(vec3(0.025,0.045,0.085),vec3(0.005,0.012,0.028),smoothstep(0.0,0.52,d.y));vec2 star_uv=d.xz/(h+0.35)*110.0;vec2 star_id=floor(star_uv);vec2 star_gv=fract(star_uv)-0.5;float s_rnd=hash(star_id);if(s_rnd>0.955&&d.y>0.03){float twinkle=0.65+0.35*sin(TIME*(1.8+fract(s_rnd*37.0)*3.0)+s_rnd*40.0);float s_dot=smoothstep(0.13,0.01,length(star_gv-(vec2(fract(s_rnd*13.0),fract(s_rnd*29.0))-0.5)*0.5));col+=vec3(0.82,0.92,1.0)*s_dot*twinkle*smoothstep(0.03,0.22,d.y)*1.8;}float moon_dot=max(dot(d,moon_dir),0.0);float moon_disc=smoothstep(0.99935,0.99968,moon_dot);float moon_halo=pow(moon_dot,28.0)*0.45+pow(moon_dot,260.0)*1.6;vec3 right_v=normalize(cross(moon_dir,vec3(0.0,1.0,0.0)));vec3 up_v=cross(right_v,moon_dir);float dx=dot(d,right_v);float dy=dot(d,up_v);float diag=abs(dx*0.55-dy*0.83);float diag_ray=exp(-diag*85.0)*pow(moon_dot,6.0)*0.95;float cross_ray=exp(-abs(dx*0.83+dy*0.55)*95.0)*pow(moon_dot,12.0)*0.45;col+=vec3(1.35,1.40,1.50)*moon_disc*3.8;col+=vec3(0.60,0.78,1.0)*(moon_halo+diag_ray+cross_ray);vec2 cuv=d.xz/(h+0.15)*0.75+vec2(TIME*0.022,TIME*0.010);float c1=fbm(cuv);float c2=fbm(cuv*2.7-c1*0.90+vec2(TIME*0.016,0.0));float cloud=smoothstep(0.38,0.82,c1*0.60+c2*0.40)*smoothstep(0.01,0.20,d.y);float rim=smoothstep(0.36,0.58,c1)*(1.0-smoothstep(0.58,0.85,c1))*pow(moon_dot,2.2);vec3 cloud_lit=vec3(0.24,0.32,0.44)+vec3(0.65,0.78,0.95)*rim*2.4;col=mix(col,cloud_lit,cloud*0.90);col=mix(col,vec3(0.018,0.026,0.045),smoothstep(0.60,0.90,c2)*cloud*0.75);COLOR=col;}"
	var smat := ShaderMaterial.new()
	smat.shader = sky_shd
	var sky := Sky.new()
	sky.sky_material = smat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.22, 0.34)
	env.ambient_light_energy = 1.40
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.22

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.03, 0.06, 0.12)
	env.fog_sun_scatter = 0.28
	env.fog_density = 0.16
	env.fog_depth_begin = 65.0
	env.fog_depth_end = 560.0

	var sun := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(0.70, 0.82, 1.0)
		sun.light_energy = 1.05
		sun.rotation_degrees = Vector3(-16.0, -138.0, 0.0)


func _upgrade_reflective_materials() -> void:
	var gelcoat := StandardMaterial3D.new()
	gelcoat.albedo_color = C_GELCOAT
	gelcoat.roughness = 0.24
	gelcoat.metallic = 0.05
	gelcoat.clearcoat = 0.65
	gelcoat.clearcoat_roughness = 0.16

	var plank_mat: StandardMaterial3D = null
	for mi in find_children("*", "MeshInstance3D", true, false):
		var mat = mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		if mat == null:
			continue
		if mat.resource_path.contains("ship_hull"):
			mi.material_override = gelcoat
		elif mat.resource_path.contains("wood_planks"):
			if plank_mat == null:
				plank_mat = mat.duplicate() as StandardMaterial3D
				if plank_mat != null:
					plank_mat.roughness = 0.24
					plank_mat.specular = 0.85
					plank_mat.clearcoat = 0.45
					plank_mat.clearcoat_roughness = 0.20
			if plank_mat != null:
				mi.material_override = plank_mat


func _build_seamless_yacht_hull() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck_st := SurfaceTool.new()
	deck_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var slices := 56
	for i in slices:
		var t0 := float(i) / float(slices)
		var t1 := float(i + 1) / float(slices)
		var z0 := lerpf(-52.0, 48.0, t0)
		var z1 := lerpf(-52.0, 48.0, t1)
		var w0 := _hull_half_width(z0)
		var w1 := _hull_half_width(z1)
		var yt0 := lerpf(1.15, 0.44, smoothstep(-52.0, -37.5, z0))
		var yt1 := lerpf(1.15, 0.44, smoothstep(-52.0, -37.5, z1))
		for side in [-1.0, 1.0]:
			var p00 := Vector3(side * w0, -4.4, z0)
			var p10 := Vector3(side * w1, -4.4, z1)
			var p11 := Vector3(side * w1, yt1, z1)
			var p01 := Vector3(side * w0, yt0, z0)
			if side > 0.0:
				st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
			else:
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)

		if z0 < -37.0 or z1 > 37.0:
			var dy0 := lerpf(0.65, 0.01, smoothstep(-52.0, -37.5, z0)) if z0 < 0.0 else 0.01
			var dy1 := lerpf(0.65, 0.01, smoothstep(-52.0, -37.5, z1)) if z1 < 0.0 else 0.01
			var d00 := Vector3(-w0, dy0, z0)
			var d10 := Vector3(w0, dy0, z0)
			var d11 := Vector3(w1, dy1, z1)
			var d01 := Vector3(-w1, dy1, z1)
			deck_st.set_uv(Vector2(-w0 * 0.25, z0 * 0.25)); deck_st.add_vertex(d00)
			deck_st.set_uv(Vector2(w0 * 0.25, z0 * 0.25)); deck_st.add_vertex(d10)
			deck_st.set_uv(Vector2(w1 * 0.25, z1 * 0.25)); deck_st.add_vertex(d11)
			deck_st.set_uv(Vector2(-w0 * 0.25, z0 * 0.25)); deck_st.add_vertex(d00)
			deck_st.set_uv(Vector2(w1 * 0.25, z1 * 0.25)); deck_st.add_vertex(d11)
			deck_st.set_uv(Vector2(-w1 * 0.25, z1 * 0.25)); deck_st.add_vertex(d01)

	st.generate_normals()
	var hull_mi := MeshInstance3D.new()
	hull_mi.name = "SeamlessYachtHull"
	hull_mi.mesh = st.commit()
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = C_GELCOAT
	hmat.roughness = 0.24
	hmat.metallic = 0.05
	hmat.clearcoat = 0.65
	hull_mi.material_override = hmat
	add_child(hull_mi)
	hull_mi.create_trimesh_collision()

	deck_st.generate_normals()
	var deck_mi := MeshInstance3D.new()
	deck_mi.name = "SeamlessTeakEnds"
	deck_mi.mesh = deck_st.commit()
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).albedo_color == C_TEAK:
			deck_mi.material_override = mi.material_override
			break
	add_child(deck_mi)
	deck_mi.create_trimesh_collision()


func _hull_half_width(z: float) -> float:
	if z < -37.5:
		var u := clampf((z + 52.0) / 14.5, 0.0, 1.0)
		return 17.5 * pow(u, 0.65)
	elif z > 37.5:
		var u := clampf((48.0 - z) / 10.5, 0.0, 1.0)
		return 17.5 * sqrt(u)
	return 17.5


func _build_midnight_ocean_and_liner() -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "MidnightStormOcean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600.0, 1600.0)
	plane.subdivide_width = 180
	plane.subdivide_depth = 180
	ocean.mesh = plane
	ocean.position = Vector3(0.0, -4.2, 0.0)

	var oshd := Shader.new()
	oshd.code = "shader_type spatial;\nrender_mode cull_back,diffuse_burley,specular_schlick_ggx;\nuniform float ship_speed_offset=0.0;\nvarying float wave_h;\nvarying vec3 w_pos;\nvarying vec3 world_nrm;\nfloat hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}\nfloat noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}\nfloat fbm(vec2 p){return noise(p)*0.55+noise(p*2.15+3.7)*0.28+noise(p*4.4-1.9)*0.17;}\nvoid vertex(){vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vec2 hull=abs(wp.xz)/vec2(19.5,52.0);float hull_dist=max(hull.x,hull.y);float damp=smoothstep(0.84,1.28,hull_dist);float bow_wake=exp(-abs(hull_dist-1.12)*4.5)*0.55;vec2 travel=wp.xz+vec2(0.0,ship_speed_offset);float t=TIME;vec2 d1=normalize(vec2(0.85,0.35));vec2 d2=normalize(vec2(0.55,-0.75));vec2 d3=normalize(vec2(-0.35,0.92));float p1=dot(travel,d1)*0.11+t*1.55;float p2=dot(travel,d2)*0.20+t*2.65+1.1;float p3=dot(travel,d3)*0.38+t*3.7;float h=(sin(p1)*1.15+sin(p2)*0.68+sin(p3)*0.32)*damp+bow_wake;VERTEX.y+=h;wave_h=h;w_pos=vec3(travel.x,wp.y+h,travel.y);vec2 grad=(d1*cos(p1)*0.11*1.15+d2*cos(p2)*0.20*0.68+d3*cos(p3)*0.38*0.32)*damp;world_nrm=normalize(vec3(-grad.x,1.0,-grad.y));}\nvoid fragment(){vec2 uv1=w_pos.xz*0.55+vec2(TIME*0.18,TIME*0.09);vec2 uv2=w_pos.xz*1.65-vec2(TIME*0.14,-TIME*0.22);float eps=0.08;float n0=fbm(uv1)+fbm(uv2)*0.6;float nx=fbm(uv1+vec2(eps,0.0))+fbm(uv2+vec2(eps,0.0))*0.6;float nz=fbm(uv1+vec2(0.0,eps))+fbm(uv2+vec2(0.0,eps))*0.6;vec3 detail_nrm=normalize(world_nrm+vec3((n0-nx)*2.6,0.0,(n0-nz)*2.6));NORMAL=normalize((VIEW_MATRIX*vec4(detail_nrm,0.0)).xyz);float crest=smoothstep(0.85,1.75,wave_h);float foam_tex=fbm(w_pos.xz*vec2(0.28,0.68)+vec2(TIME*0.35,0.0));float foam=clamp(crest*smoothstep(0.42,0.78,foam_tex)*1.1,0.0,1.0);vec3 sea_col=mix(vec3(0.005,0.018,0.045),vec3(0.015,0.065,0.14),smoothstep(-1.2,1.4,wave_h));ALBEDO=mix(sea_col,vec3(0.75,0.85,0.96),foam*0.75);ROUGHNESS=mix(0.04,0.35,foam);SPECULAR=1.0;}"
	_my_ocean_mat = ShaderMaterial.new()
	_my_ocean_mat.shader = oshd
	ocean.material_override = _my_ocean_mat
	add_child(ocean)

	_my_spray = GPUParticles3D.new()
	_my_spray.name = "MidnightWaveSpray"
	_my_spray.amount = 380
	_my_spray.lifetime = 0.85
	_my_spray.emitting = false
	var smat := ParticleProcessMaterial.new()
	smat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	smat.emission_box_extents = Vector3(0.8, 0.35, 11.0)
	smat.direction = Vector3(-0.9, 1.2, -0.4).normalized()
	smat.spread = 22.0
	smat.initial_velocity_min = 8.0
	smat.initial_velocity_max = 14.5
	smat.gravity = Vector3(0.0, -18.0,
	-4.5)
	smat.scale_min = 0.3
	smat.scale_max = 0.85
	_my_spray.process_material = smat
	var sdrop := QuadMesh.new()
	sdrop.size = Vector2(0.04, 0.42)
	var sdmat := StandardMaterial3D.new()
	sdmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sdmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sdmat.albedo_color = Color(0.78, 0.88, 0.98, 0.26)
	sdrop.material = sdmat
	_my_spray.draw_pass_1 = sdrop
	add_child(_my_spray)
	_my_liner = Node3D.new()
	_my_liner.name = "DistantCruiseLiner"
	_my_liner.position = Vector3(175.0, -1.6, -75.0)
	_my_liner.rotation_degrees = Vector3(0.0, -28.0, 0.0)
	var liner_shd := Shader.new()
	liner_shd.code = "shader_type spatial;\nrender_mode cull_back,diffuse_burley,specular_schlick_ggx;\nvarying vec3 w_p;\nvoid vertex(){w_p=(MODEL_MATRIXvec4(VERTEX,1.0)).xyz;}\nvoid fragment(){float deck_line=smoothstep(0.06,0.0,abs(fract(w_p.y0.32)-0.5));float win_z=step(0.30,fract(w_p.z0.34))step(fract(w_p.z0.34),0.74);float win_y=step(0.32,fract(w_p.y0.32))step(fract(w_p.y0.32),0.62);float is_win=win_zwin_y;vec3 steel=mix(vec3(0.78,0.82,0.88),vec3(0.25,0.30,0.38),deck_line0.7);ALBEDO=mix(steel,vec3(0.06,0.09,0.14),is_win);EMISSION=vec3(1.0,0.82,0.46)is_win3.8;ROUGHNESS=mix(0.38,0.08,is_win);METALLIC=0.22;}"
	var lmat := ShaderMaterial.new()
	lmat.shader = liner_shd
	var navy_mat := StandardMaterial3D.new()
	navy_mat.albedo_color = Color(0.04, 0.08, 0.16)
	navy_mat.roughness = 0.35
	var red_accent := StandardMaterial3D.new()
	red_accent.albedo_color = Color(0.72, 0.14, 0.13)
	var tiers := [
	{"size": Vector3(26.0, 10.0, 195.0), "pos": Vector3(0.0, 0.5, 0.0), "mat": navy_mat},
	{"size": Vector3(26.4, 0.8, 196.0), "pos": Vector3(0.0, 5.6, 0.0), "mat": red_accent},
	{"size": Vector3(23.0, 4.6, 166.0), "pos": Vector3(0.0, 8.0, 2.0), "mat": lmat},
	{"size": Vector3(19.8, 4.4, 138.0), "pos": Vector3(0.0, 12.2, 4.0), "mat": lmat},
	{"size": Vector3(16.0, 3.8, 102.0), "pos": Vector3(0.0, 16.0, 2.0), "mat": lmat},
	{"size": Vector3(18.5, 2.4, 15.0), "pos": Vector3(0.0, 17.5, -40.0), "mat": lmat},
	{"size": Vector3(6.6, 8.0, 12.0), "pos": Vector3(0.0, 21.2, 26.0), "mat": navy_mat},
	{"size": Vector3(6.8, 1.6, 12.2), "pos": Vector3(0.0, 23.4, 26.0), "mat": red_accent}
	]
		for t in tiers:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = t["size"]
	m.mesh = bm
	m.material_override = t["mat"]
	m.position = t["pos"]
	_my_liner.add_child(m)
	var bow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(26.0, 28.0, 10.0)
	bow.mesh = pm
	bow.material_override = navy_mat
	bow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	bow.position = Vector3(0.0, 0.5, -111.5)
	_my_liner.add_child(bow)
	add_child(_my_liner)
func get_spawns() -> Array:
	var s: Array = []
	var red_pts := [
	Vector3(-9.5, 0.25, -31.0), Vector3(-4.5, 0.25, -33.0), Vector3(0.0, 0.25, -34.0),
	Vector3(4.5, 0.25, -33.0), Vector3(9.5, 0.25, -31.0), Vector3(-13.5, 0.25, -29.0),
	Vector3(13.5, 0.25, -29.0), Vector3(0.0, 0.25, -30.5)
	]
		for p in red_pts:
	s.append({"pos": p, "yaw": 180.0, "team": 0})
	var blue_pts := [
	Vector3(-9.5, 0.25, 31.0), Vector3(-4.5, 0.25, 33.0), Vector3(0.0, 0.25, 34.0),
	Vector3(4.5, 0.25, 33.0), Vector3(9.5, 0.25, 31.0), Vector3(-13.5, 0.25, 29.0),
	Vector3(13.5, 0.25, 29.0), Vector3(0.0, 0.25, 30.5)
	]
		for p in blue_pts:
	s.append({"pos": p, "yaw": 0.0, "team": 1})
	return s
func get_lanes() -> Dictionary:
	return {
	"left": [
	Vector3(-13.8, 0.25, -28.0), Vector3(-13.8, 0.25, -12.0),
	Vector3(-13.8, 0.25, 0.0), Vector3(-13.8, 0.25, 12.0), Vector3(-13.8, 0.25, 28.0)
	],
	"mid": [
	Vector3(0.0, 0.25, -28.0), Vector3(0.0, 0.25, -16.0),
	Vector3(0.0, 0.25, -5.0), Vector3(0.0, 0.25, 5.0),
	Vector3(0.0, 0.25, 16.0), Vector3(0.0, 0.25, 28.0)
	],
	"right": [
	Vector3(13.8, 0.25, -28.0), Vector3(13.8, 0.25, -12.0),
	Vector3(13.8, 0.25, 0.0), Vector3(13.8, 0.25, 12.0), Vector3(13.8, 0.25, 28.0)
	]
	}
func get_cover_points() -> Array:
	return [
	Vector3(-4.5, 0.25, -4.6), Vector3(4.5, 0.25, 4.6),
	Vector3(-13.8, 0.25, -12.0), Vector3(13.8, 0.25, 12.0),
	Vector3(0.0, UPPER_Y + 0.25, -12.0), Vector3(0.0, UPPER_Y + 0.25, 10.5),
	Vector3(-4.2, LOWER_Y + 0.25, -8.0), Vector3(4.2, LOWER_Y + 0.25, 8.0)
	]
