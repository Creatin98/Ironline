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
const UPPER_Y := 3.8

var _my_time: float = 0.0
var _my_ocean_mat: ShaderMaterial
var _my_spray: GPUParticles3D
var _my_liner: Node3D
var _my_wash_mat: ShaderMaterial
var _wash_l: float = 0.0
var _wash_r: float = 0.0


func _ready() -> void:
	map_display_name = "Harbor"
	kill_y = -25.0
	atmosphere_preset = "clear_day"
	super._ready()
	for old_sea in ["HarborStormOcean", "HarborDistantIslands"]:
		if has_node(old_sea):
			get_node(old_sea).visible = false

	for area in find_children("*", "Area3D", true, false):
		if area.global_position.y > -18.0:
			area.global_position.y = -25.0
	_setup_midnight_atmosphere()
	_upgrade_reflective_materials()
	_build_seamless_yacht_hull()
	_build_midnight_ocean_and_liner()


func _process(delta: float) -> void:
	super._process(delta)
	_my_time += delta
	var w1 := sin(_my_time * 1.45)
	var w2 := sin(_my_time * 2.45 + 1.1)
	var wave_force := w1 * 0.72 + w2 * 0.28
	var roll_deg := wave_force * 3.4
	var pitch_deg := cos(_my_time * 1.05) * 1.85

	# 1. Spürbares Rollen & Stampfen von Meer und Kreuzer rund um die Yacht
	var ocean := get_node_or_null("MidnightStormOcean") as MeshInstance3D
	if ocean != null:
		ocean.position.y = -4.6
		ocean.rotation_degrees = Vector3.ZERO

	if _my_ocean_mat != null:
		_my_ocean_mat.set_shader_parameter("ship_speed_offset", _my_time * 9.5)

	if _my_liner != null:
		_my_liner.position.y = -5.6 + sin(_my_time * 1.1) * 0.25
		_my_liner.rotation_degrees = Vector3(cos(_my_time * 0.9) * 0.8, -28.0, sin(_my_time * 1.0) * 1.1)

	if absf(wave_force) > 0.35:
		var side := signf(wave_force)
		if side < 0.0:
			_wash_l = minf(1.0, _wash_l + delta * 1.6)
		else:
			_wash_r = minf(1.0, _wash_r + delta * 1.6)
		if _my_spray != null:
			var sz := sin(_my_time * 2.1) * 28.0
			var sy := 1.15 if sz < -9.5 else (0.05 if sz < 9.5 else -1.05)
			_my_spray.position = Vector3(side * 17.3, sy, sz)
			var pmat := _my_spray.process_material as ParticleProcessMaterial
			if pmat != null:
				pmat.direction = Vector3(-side * 0.85, 1.65, -0.45).normalized()
			_my_spray.emitting = true
	else:
		if _my_spray != null:
			_my_spray.emitting = false

	_wash_l = maxf(0.0, _wash_l - delta * 0.28)
	_wash_r = maxf(0.0, _wash_r - delta * 0.28)
	if _my_wash_mat != null:
		_my_wash_mat.set_shader_parameter("wash_l", _wash_l)
		_my_wash_mat.set_shader_parameter("wash_r", _wash_r)

	# 2. Wellen schlagen ans Boot -> Gischt spritzt hoch & Wasser läuft über Mittel- & Achterdeck!
	if absf(wave_force) > 0.48:
		var side := signf(wave_force)
		if side < 0.0:
			_wash_l = minf(1.0, _wash_l + delta * 1.9)
		else:
			_wash_r = minf(1.0, _wash_r + delta * 1.9)
		if _my_spray != null:
			var sz := sin(_my_time * 1.8) * 24.0
			var sy := 1.35 if sz < -11.0 else (0.25 if sz < 11.0 else -0.85)
			_my_spray.position = Vector3(side * 17.1, sy, sz)
			var pmat := _my_spray.process_material as ParticleProcessMaterial
			if pmat != null:
				pmat.direction = Vector3(-side * 1.05, 1.35, -0.35).normalized()
			_my_spray.emitting = true
	else:
		if _my_spray != null:
			_my_spray.emitting = false

	_wash_l = maxf(0.0, _wash_l - delta * 0.35)
	_wash_r = maxf(0.0, _wash_r - delta * 0.35)
	if _my_wash_mat != null:
		_my_wash_mat.set_shader_parameter("wash_l", _wash_l)
		_my_wash_mat.set_shader_parameter("wash_r", _wash_r)

func get_blocks() -> Array:
	var b: Array = []
	var BOW_Y := 1.10
	var MID_Y := 0.0
	var STERN_Y := -1.10

	# 1. 3-stufiges Teakholz-Deck mit großzügigem 4m-Vorplatz vor allen Türen!
	b.append(box(Vector3(0, BOW_Y - 0.25, -23.75), Vector3(34.6, 0.5, 28.5), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, MID_Y - 0.25, 0.0), Vector3(34.6, 0.5, 19.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, STERN_Y - 0.25, 23.75), Vector3(34.6, 0.5, 28.5), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -2.85, 0.0), Vector3(34.2, 2.8, 76.0), "ship_hull", C_GELCOAT))

	# 2. Bündige Terrassen-Treppen LINKS & RECHTS (liegen komplett VOR den Deck-Kanten z = ±9.5, nichts darunter vergraben!)
	# Nord-Absatz: Mitteldeck (0.0) -> Vordeck (+1.10) bei z = -9.5
	b.append(box(Vector3(0.0, BOW_Y * 0.5, -9.5), Vector3(15.6, BOW_Y, 0.5), "ship_hull", C_GELCOAT))
	for side in [-1.0, 1.0]:
		var tx: float = side * 12.2
		b.append(ramp(Vector3(tx, MID_Y, -5.8), Vector3(tx, BOW_Y + 0.02, -9.5), 8.8, "wood_planks", 0.35, C_TEAK))
		for st_i in 6:
			var t := float(st_i + 1) / 6.0
			var h := t * BOW_Y
			var sz := lerpf(-5.8, -9.15, t)
			b.append(box(Vector3(tx, h * 0.5, sz), Vector3(8.8, h, 0.65), "wood_planks", C_TEAK))

	# Süd-Absatz: Achterdeck (-1.10) -> Mitteldeck (0.0) bei z = +9.5 (liegen komplett VOR z = +9.5 auf dem Achterdeck!)
	b.append(box(Vector3(0.0, STERN_Y + 0.55, 9.5), Vector3(15.6, 1.1, 0.5), "ship_hull", C_GELCOAT))
	for side in [-1.0, 1.0]:
		var tx: float = side * 12.2
		b.append(ramp(Vector3(tx, STERN_Y, 13.2), Vector3(tx, MID_Y + 0.02, 9.5), 8.8, "wood_planks", 0.35, C_TEAK))
		for st_i in 6:
			var t := float(st_i + 1) / 6.0
			var h := t * 1.10
			var sz := lerpf(13.2, 9.85, t)
			b.append(box(Vector3(tx, STERN_Y + h * 0.5, sz), Vector3(8.8, h, 0.65), "wood_planks", C_TEAK))

	# 3. Schanzkleid, Barrieren & Pools
	for side in [-1.0, 1.0]:
		b.append(box(Vector3(side * 17.2, BOW_Y + 0.22, -23.75), Vector3(0.3, 0.44, 28.5), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(side * 17.2, MID_Y + 0.22, 0.0), Vector3(0.3, 0.44, 19.0), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(side * 17.2, STERN_Y + 0.22, 23.75), Vector3(0.3, 0.44, 28.5), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, BOW_Y + 0.22, -37.9), Vector3(34.6, 0.44, 0.3), "ship_hull", C_GELCOAT))
	b.append({"pos": Vector3(0, 3.0, 44.0), "size": Vector3(35.0, 8.0, 0.5), "mat": "water", "visible": false})
	b.append({"pos": Vector3(0, 3.0, -44.0), "size": Vector3(35.0, 8.0, 0.5), "mat": "water", "visible": false})
	b.append({"pos": Vector3(-17.4, 3.0, 0), "size": Vector3(0.5, 8.0, 88.0), "mat": "water", "visible": false})
	b.append({"pos": Vector3(17.4, 3.0, 0), "size": Vector3(0.5, 8.0, 88.0), "mat": "water", "visible": false})

	b.append(cylinder(Vector3(0, BOW_Y + 0.38, -33.5), 3.6, 0.76, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, BOW_Y + 0.68, -33.5), 3.0, 0.14, "water", Color(0.12, 0.85, 0.96)))
	b.append(cylinder(Vector3(0, BOW_Y + 0.55, -41.5), 1.1, 1.1, "metal_panel", C_CHROME))
	b.append(cylinder(Vector3(0, STERN_Y + 0.03, 33.5), 7.8, 0.06, "asphalt", C_DARK))
	b.append(cylinder(Vector3(0, STERN_Y + 0.05, 33.5), 1.5, 0.06, "metal_panel", C_BRASS))
	b.append(box(Vector3(0, STERN_Y + 0.54, 41.2), Vector3(6.8, 1.08, 1.0), "wood_planks", C_TEAK))
	b.append(cylinder(Vector3(0, MID_Y + 0.36, 0), 3.4, 0.72, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, MID_Y + 0.68, 0), 2.8, 0.14, "water", Color(0.12, 0.86, 0.96)))

	# 4. Hohes Nord-Deckhaus (3.8m hoch) – Eingänge komplett frei, verwinkeltes Stufen-Treppenhaus hinten rechts!
	b.append_array(room_walls(Vector3(0, BOW_Y, -20.5), Vector3(13.8, UPPER_Y, 13.0), 0.34, "ship_hull", C_GELCOAT,
		[{"side": "n", "offset": -2.4, "width": 2.6}, {"side": "s", "offset": -2.4, "width": 2.8},
		 {"side": "w", "offset": 0.0, "width": 2.4}]))
	b.append(header(Vector3(-2.4, BOW_Y, -27.0), 2.6, 2.55, UPPER_Y, 0.34, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-2.4, BOW_Y, -14.0), 2.8, 2.55, UPPER_Y, 0.34, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-6.9, BOW_Y, -20.5), 2.4, 2.55, UPPER_Y, 0.34, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-3.2, BOW_Y + 0.52, -23.5), Vector3(4.2, 1.04, 0.95), "wood_planks", C_TEAK))
	b.append(box(Vector3(-3.2, BOW_Y + 1.08, -23.5), Vector3(4.4, 0.1, 1.15), "tiles", C_MARBLE))

	# Verwinkeltes Innen-Treppenhaus Nord (Ostseite innen, weit weg von allen Türen! Echte Stufen + Rampen + riesige Öffnung oben)
	var U_N := BOW_Y + UPPER_Y
	var P_N := BOW_Y + UPPER_Y * 0.5
	b.append(box(Vector3(4.5, P_N - 0.12, -25.0), Vector3(4.2, 0.24, 3.2), "wood_planks", C_TEAK)) # Zwischenpodest
	b.append(box(Vector3(2.2, BOW_Y + 1.4, -21.2), Vector3(0.28, 2.8, 7.2), "ship_hull", C_GELCOAT)) # Trennwand zum Salon
	# Lauf 1: Echte Stufen + Rampe (x=5.4, z=-17.5 -> -23.4)
	b.append(ramp(Vector3(5.4, BOW_Y, -17.5), Vector3(5.4, P_N + 0.02, -23.4), 2.1, "wood_planks", 0.3, C_TEAK))
	for s1 in 10:
		var t1 := float(s1 + 1) / 10.0
		var h1 := t1 * (UPPER_Y * 0.5)
		b.append(box(Vector3(5.4, BOW_Y + h1 * 0.5, lerpf(-17.5, -23.4, t1)), Vector3(2.0, h1, 0.65), "wood_planks", C_TEAK))
	# Lauf 2 (90°/180° Knick): Echte Stufen + Rampe nach vorne aufs offene Oberdeck (x=3.3, z=-23.4 -> -17.2)
	b.append(ramp(Vector3(3.3, P_N, -23.4), Vector3(3.3, U_N + 0.04, -17.2), 2.1, "wood_planks", 0.3, C_TEAK))
	for s2 in 10:
		var t2 := float(s2 + 1) / 10.0
		var h2 := (UPPER_Y * 0.5) + t2 * (UPPER_Y * 0.5)
		b.append(box(Vector3(3.3, BOW_Y + h2 * 0.5, lerpf(-23.4, -17.2, t2)), Vector3(2.0, h2, 0.68), "wood_planks", C_TEAK))

	# Oberdeck Nord: Komplett offen über dem gesamten Treppenhaus (x=2.1..6.8, z=-23.5..-13.6) -> null Kopf-Anstoßen!
	b.append(box(Vector3(-2.6, U_N - 0.15, -20.5), Vector3(9.6, 0.3, 13.8), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(4.6, U_N - 0.15, -25.5), Vector3(5.4, 0.3, 3.8), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(6.8, U_N - 0.15, -18.6), Vector3(1.2, 0.3, 10.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-2.6, U_N + 0.22, -13.6), Vector3(9.6, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, U_N + 0.22, -27.4), Vector3(14.8, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-7.3, U_N + 0.22, -20.5), Vector3(0.25, 0.44, 13.8), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(7.3, U_N + 0.22, -20.5), Vector3(0.25, 0.44, 13.8), "ship_hull", C_GELCOAT))

	# 5. Hohes Süd-Deckhaus (3.8m hoch) – Eingänge komplett frei, verwinkeltes Stufen-Treppenhaus hinten links!
	b.append_array(room_walls(Vector3(0, STERN_Y, 20.5), Vector3(13.8, UPPER_Y, 13.0), 0.34, "ship_hull", C_GELCOAT,
		[{"side": "n", "offset": 2.4, "width": 2.8}, {"side": "s", "offset": 2.4, "width": 2.6},
		 {"side": "e", "offset": 0.0, "width": 2.4}]))
	b.append(header(Vector3(2.4, STERN_Y, 14.0), 2.8, 2.55, UPPER_Y, 0.34, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(2.4, STERN_Y, 27.0), 2.6, 2.55, UPPER_Y, 0.34, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(6.9, STERN_Y, 20.5), 2.4, 2.55, UPPER_Y, 0.34, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(3.2, STERN_Y + 0.56, 23.5), Vector3(4.2, 1.12, 1.0), "metal_panel", C_DARK))
	b.append(box(Vector3(3.2, STERN_Y + 1.15, 23.5), Vector3(4.4, 0.08, 1.1), "metal_panel", C_CHROME))

	# Verwinkeltes Innen-Treppenhaus Süd (Westseite innen, weit weg von allen Türen! Echte Stufen + Rampen + riesige Öffnung oben)
	var U_S := STERN_Y + UPPER_Y
	var P_S := STERN_Y + UPPER_Y * 0.5
	b.append(box(Vector3(-4.5, P_S - 0.12, 25.0), Vector3(4.2, 0.24, 3.2), "wood_planks", C_TEAK))
	b.append(box(Vector3(-2.2, STERN_Y + 1.4, 21.2), Vector3(0.28, 2.8, 7.2), "ship_hull", C_GELCOAT))
	b.append(ramp(Vector3(-5.4, STERN_Y, 17.5), Vector3(-5.4, P_S + 0.02, 23.4), 2.1, "wood_planks", 0.3, C_TEAK))
	for s1 in 10:
		var t1 := float(s1 + 1) / 10.0
		var h1 := t1 * (UPPER_Y * 0.5)
		b.append(box(Vector3(-5.4, STERN_Y + h1 * 0.5, lerpf(17.5, 23.4, t1)), Vector3(2.0, h1, 0.65), "wood_planks", C_TEAK))
	b.append(ramp(Vector3(-3.3, P_S, 23.4), Vector3(-3.3, U_S + 0.04, 17.2), 2.1, "wood_planks", 0.3, C_TEAK))
	for s2 in 10:
		var t2 := float(s2 + 1) / 10.0
		var h2 := (UPPER_Y * 0.5) + t2 * (UPPER_Y * 0.5)
		b.append(box(Vector3(-3.3, STERN_Y + h2 * 0.5, lerpf(23.4, 17.2, t2)), Vector3(2.0, h2, 0.68), "wood_planks", C_TEAK))

	# Oberdeck Süd: Komplett offen über dem gesamten Treppenhaus (x=-6.8..-2.1, z=13.6..23.5) -> null Kopf-Anstoßen!
	b.append(box(Vector3(2.6, U_S - 0.15, 20.5), Vector3(9.6, 0.3, 13.8), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-4.6, U_S - 0.15, 25.5), Vector3(5.4, 0.3, 3.8), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-6.8, U_S - 0.15, 18.6), Vector3(1.2, 0.3, 10.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(2.6, U_S + 0.22, 13.6), Vector3(9.6, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, U_S + 0.22, 27.4), Vector3(14.8, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-7.3, U_S + 0.22, 20.5), Vector3(0.25, 0.44, 13.8), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(7.3, U_S + 0.22, 20.5), Vector3(0.25, 0.44, 13.8), "ship_hull", C_GELCOAT))


	# 6. Kommandobrücke auf Oberdeck Süd + taktische Seiten-Deckung
	b.append_array(room_walls(Vector3(1.5, U_S, 19.5), Vector3(6.8, 2.5, 5.8), 0.26, "ship_hull", C_GELCOAT,
		[{"side": "w", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		 {"side": "n", "offset": -1.4, "width": 1.8}, {"side": "n", "offset": 1.4, "width": 1.8}]))
	for wx in [0.1, 2.9]:
		b.append(header(Vector3(wx, 0.0, 16.6), 1.8, U_S, U_S + 0.85, 0.26, true, "ship_hull", C_GELCOAT))
		b.append(header(Vector3(wx, 0.0, 16.6), 1.8, U_S + 2.05, U_S + 2.5, 0.26, true, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(1.5, U_S + 2.6, 19.5), Vector3(7.4, 0.22, 6.4), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(1.5, U_S + 0.52, 17.5), Vector3(4.8, 1.04, 0.85), "metal_panel", C_DARK))
	b.append(box(Vector3(1.5, U_S + 1.06, 17.5), Vector3(4.9, 0.08, 0.92), "wood_planks", C_TEAK))

	for side in [-1.0, 1.0]:
		b.append(box(Vector3(side * 12.2, BOW_Y + 0.52, -21.0), Vector3(2.4, 1.04, 1.2), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(side * 12.2, MID_Y + 0.52, -3.5), Vector3(2.4, 1.04, 1.2), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(side * 12.2, MID_Y + 0.52, 3.5), Vector3(2.4, 1.04, 1.2), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(side * 12.2, STERN_Y + 0.52, 21.0), Vector3(2.4, 1.04, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, BOW_Y + 0.55, -43.2), Vector3(2.6, 0.25, 0.15), "ship_hull", C_RED))
	b.append(box(Vector3(0, STERN_Y + 0.55, 43.2), Vector3(2.6, 0.25, 0.15), "ship_hull", C_BLUE))
	return b

func build_detail(d: MapDetail) -> void:
	var BOW_Y := 1.10
	var MID_Y := 0.0
	var STERN_Y := -1.10
	var U_N := BOW_Y + UPPER_Y
	var U_S := STERN_Y + UPPER_Y

	# Reling-Spots passend zu den 3 Deck-Höhen
	for rz in range(-36, -9, 6):
		d.bulb(Vector3(-16.9, BOW_Y + 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)
		d.bulb(Vector3(16.9, BOW_Y + 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)
	for rz in range(-7, 9, 5):
		d.bulb(Vector3(-16.9, MID_Y + 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)
		d.bulb(Vector3(16.9, MID_Y + 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)
	for rz in range(11, 38, 6):
		d.bulb(Vector3(-16.9, STERN_Y + 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)
		d.bulb(Vector3(16.9, STERN_Y + 0.55, float(rz)), Color(1.0, 0.85, 0.58), 0.75, 0.45, 5.5)

	# Stufen-LED-Bänder an den zwei Deck-Absätzen (z = ±9.5)
	d.led_strip(Vector3(-16.8, BOW_Y + 0.05, -9.5), Vector3(16.8, BOW_Y + 0.05, -9.5), Color(0.25, 0.80, 1.0), 3.6)
	d.led_strip(Vector3(-16.8, MID_Y + 0.05, 9.5), Vector3(16.8, MID_Y + 0.05, 9.5), Color(0.25, 0.80, 1.0), 3.6)

	# Lila Eingangs-Lichtbalken über allen 8 Türen (passend zu den versetzten Eingängen!)
	var door_bars := [
		{"a": Vector3(1.1, BOW_Y + 2.62, -27.18), "b": Vector3(3.7, BOW_Y + 2.62, -27.18)},
		{"a": Vector3(-3.8, BOW_Y + 2.62, -13.82), "b": Vector3(-1.0, BOW_Y + 2.62, -13.82)},
		{"a": Vector3(-7.08, BOW_Y + 2.62, -23.8), "b": Vector3(-7.08, BOW_Y + 2.62, -21.6)},
		{"a": Vector3(7.08, BOW_Y + 2.62, -19.4), "b": Vector3(7.08, BOW_Y + 2.62, -17.2)},
		{"a": Vector3(1.0, STERN_Y + 2.62, 13.82), "b": Vector3(3.8, STERN_Y + 2.62, 13.82)},
		{"a": Vector3(-3.7, STERN_Y + 2.62, 27.18), "b": Vector3(-1.1, STERN_Y + 2.62, 27.18)},
		{"a": Vector3(-7.08, STERN_Y + 2.62, 21.6), "b": Vector3(-7.08, STERN_Y + 2.62, 23.8)},
		{"a": Vector3(7.08, STERN_Y + 2.62, 17.2), "b": Vector3(7.08, STERN_Y + 2.62, 19.4)}
	]
	for db in door_bars:
		d.led_strip(db["a"], db["b"], Color(0.76, 0.24, 1.0), 4.8)

	# Unterwasser-Lichtkegel rund um den gesamten Rumpf
	for uz in range(-36, 40, 8):
		d.bulb(Vector3(-17.85, -1.5, float(uz)), Color(0.18, 0.78, 1.0), 4.8, 3.6, 18.0)
		d.bulb(Vector3(17.85, -1.5, float(uz)), Color(0.18, 0.78, 1.0), 4.8, 3.6, 18.0)
	d.bulb(Vector3(0.0, -1.5, 47.0), Color(0.18, 0.82, 1.0), 5.5, 4.0, 20.0)
	d.bulb(Vector3(0.0, -1.5, -49.0), Color(0.18, 0.82, 1.0), 5.0, 3.8, 18.0)

	# Hauptmast auf Nord-Oberdeck & Davit-Rettungsboote auf Mitteldeck
	var mast := Vector3(-2.6, U_N, -20.5)
	d.add_box(mast + Vector3(0, 0.25, 0), Vector3(2.0, 0.5, 2.0), "metal_panel", C_DARK)
	d.add_cylinder(mast + Vector3(0, 3.8, 0), 0.30, 7.6, "metal_panel", C_DARK)
	d.add_cylinder(mast + Vector3(0, 8.2, 0), 0.12, 2.2, "metal_panel", C_CHROME)
	d.glow(mast + Vector3(0, 9.4, 0), Color(1.0, 0.12, 0.08), 1.4)
	d.add_box(mast + Vector3(0, 4.5, 0), Vector3(4.4, 0.16, 0.5), "metal_panel", C_DARK)
	d.add_cylinder(mast + Vector3(-1.3, 4.85, 0), 0.78, 0.48, "ship_hull", C_GELCOAT)
	d.add_cylinder(mast + Vector3(1.3, 4.85, 0), 0.78, 0.48, "ship_hull", C_GELCOAT)

	for side in [-1.0, 1.0]:
		var dx: float = side * 15.8
		for dz in [-2.6, 2.6]:
			d.add_box(Vector3(dx + side * 0.6, MID_Y + 1.6, dz), Vector3(0.32, 3.2, 0.38), "ship_hull", C_GELCOAT)
			d.add_box(Vector3(dx, MID_Y + 3.1, dz), Vector3(1.6, 0.28, 0.34), "ship_hull", C_GELCOAT)
		d.add_box(Vector3(dx - side * 0.2, MID_Y + 2.05, 0.0), Vector3(1.75, 0.85, 5.4), "ship_hull", C_GELCOAT)
		d.add_box(Vector3(dx - side * 0.2, MID_Y + 2.52, 0.0), Vector3(1.80, 0.22, 5.45), "metal_panel", Color(0.92, 0.32, 0.10))

	# Relings + Innen-Treppenhaus-Geländer & gemütliche Beleuchtung
	for side in [-1.0, 1.0]:
		d.rail(Vector3(side * 17.2, BOW_Y + 0.35, -37.8), Vector3(side * 17.2, BOW_Y + 0.35, -9.5), 0.75)
		d.rail(Vector3(side * 17.2, MID_Y + 0.35, -9.5), Vector3(side * 17.2, MID_Y + 0.35, 9.5), 0.75)
		d.rail(Vector3(side * 17.2, STERN_Y + 0.35, 9.5), Vector3(side * 17.2, STERN_Y + 0.35, 37.8), 0.75)
	d.rail(Vector3(-7.3, U_N + 0.35, -13.6), Vector3(7.3, U_N + 0.35, -13.6), 0.75)
	d.rail(Vector3(-7.3, U_N + 0.35, -27.4), Vector3(7.3, U_N + 0.35, -27.4), 0.75)
	d.rail(Vector3(-7.3, U_S + 0.35, 13.6), Vector3(7.3, U_S + 0.35, 13.6), 0.75)
	d.rail(Vector3(-7.3, U_S + 0.35, 27.4), Vector3(7.3, U_S + 0.35, 27.4), 0.75)

	d.bulb(Vector3(0, MID_Y + 0.95, 0.0), Color(0.15, 0.90, 1.0), 3.4, 2.8, 9.0)
	d.bulb(Vector3(0, BOW_Y + 0.95, -33.5), Color(0.15, 0.90, 1.0), 2.8, 2.4, 7.0)
	d.lamp(Vector3(-1.5, BOW_Y + 3.4, -20.5), Color(1.0, 0.76, 0.36), 2.4, 16.0)
	d.lamp(Vector3(4.5, BOW_Y + 3.4, -22.5), Color(0.45, 0.78, 1.0), 1.4, 10.0) # Treppenhaus-Licht Nord
	d.lamp(Vector3(1.5, STERN_Y + 3.4, 20.5), Color(1.0, 0.74, 0.34), 2.2, 15.0)
	d.lamp(Vector3(-4.5, STERN_Y + 3.4, 22.5), Color(0.45, 0.78, 1.0), 1.4, 10.0) # Treppenhaus-Licht Süd
	d.lamp(Vector3(1.5, U_S + 2.2, 18.5), Color(1.0, 0.68, 0.34), 0.65, 8.0)



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
	gelcoat.roughness = 0.22
	gelcoat.metallic = 0.04
	gelcoat.clearcoat = 0.68
	gelcoat.clearcoat_roughness = 0.15

	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(s)
			if mat == null:
				mat = mi.material_override
			if mat == null:
				continue
			var m_id := (mat.resource_path + " " + mat.resource_name).to_lower()
			if m_id.contains("ship_hull"):
				mi.set_surface_override_material(s, gelcoat)
			elif m_id.contains("wood_planks"):
				var pm := mat.duplicate() as StandardMaterial3D
				if pm != null:
					pm.uv1_triplanar = true
					pm.uv1_world_triplanar = true
					pm.uv1_scale = Vector3(0.35, 0.35, 0.35)
					pm.roughness = 0.24
					pm.specular = 0.85
					pm.clearcoat = 0.45
					mi.set_surface_override_material(s, pm)

func _build_seamless_yacht_hull() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck_st := SurfaceTool.new()
	deck_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var slices := 64
	for i in slices:
		var t0 := float(i) / float(slices)
		var t1 := float(i + 1) / float(slices)
		var z0 := lerpf(-52.0, 48.0, t0)
		var z1 := lerpf(-52.0, 48.0, t1)
		var w0 := _hull_half_width(z0)
		var w1 := _hull_half_width(z1)

		# Bordwand-Oberkante exakt passend zu Vordeck (+1.10), Mitteldeck (0.0) & Achterdeck (-1.10)
		var yt0 := 0.44
		if z0 < -11.0:
			yt0 = lerpf(1.75, 1.54, smoothstep(-52.0, -37.5, z0))
		elif z0 > 11.0:
			yt0 = -0.66

		var yt1 := 0.44
		if z1 < -11.0:
			yt1 = lerpf(1.75, 1.54, smoothstep(-52.0, -37.5, z1))
		elif z1 > 11.0:
			yt1 = -0.66

		for side in [-1.0, 1.0]:
			var p00 := Vector3(side * w0, -4.8, z0)
			var p10 := Vector3(side * w1, -4.8, z1)
			var p11 := Vector3(side * w1, yt1, z1)
			var p01 := Vector3(side * w0, yt0, z0)
			if side > 0.0:
				st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
			else:
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)

		# Rundes Teakholz-Bugdeck (+1.11) & Teakholz-Heckdeck (-1.09) nahtlos schließen
		if z0 < -37.0 or z1 > 37.0:
			var dy0 := lerpf(1.30, 1.11, smoothstep(-52.0, -37.5, z0)) if z0 < 0.0 else -1.09
			var dy1 := lerpf(1.30, 1.11, smoothstep(-52.0, -37.5, z1)) if z1 < 0.0 else -1.09
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
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var s_mat: Material = mi.get_surface_override_material(0)
			if s_mat != null and s_mat is StandardMaterial3D and (s_mat as StandardMaterial3D).uv1_triplanar:
				deck_mi.material_override = s_mat
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
	var far_sea := MeshInstance3D.new()
	far_sea.name = "FarHorizonSea"
	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(2400.0, 2400.0)
	far_sea.mesh = far_plane
	far_sea.position = Vector3(0.0, -5.4, 0.0)
	var far_mat := StandardMaterial3D.new()
	far_mat.albedo_color = Color(0.005, 0.018, 0.042)
	far_mat.roughness = 0.08
	far_mat.metallic = 0.2
	far_sea.material_override = far_mat
	add_child(far_sea)

	var ocean := MeshInstance3D.new()
	ocean.name = "MidnightStormOcean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(460.0, 460.0)
	plane.subdivide_width = 256
	plane.subdivide_depth = 256
	ocean.mesh = plane
	ocean.position = Vector3(0.0, -4.6, 0.0)

	var oshd := Shader.new()
	oshd.code = "shader_type spatial;\nrender_mode cull_back,diffuse_burley,specular_schlick_ggx;\nuniform float ship_speed_offset=0.0;\nvarying float wave_h;\nvarying vec3 w_pos;\nfloat hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}\nfloat noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}\nfloat fbm(vec2 p){float v=0.0;float a=0.5;for(int i=0;i<5;i++){v+=a*noise(p);p=p*2.03+vec2(1.9,4.3);a*=0.5;}return v;}\nfloat wave_height(vec2 xz,float t){return sin(xz.x*0.18+xz.y*0.07+t*2.4)*0.85+sin(xz.x*0.34-xz.y*0.19+t*3.3)*0.52+sin(xz.x*0.65+xz.y*0.42+t*4.5)*0.26+sin(xz.y*0.24+t*2.9)*0.45;}\nvoid vertex(){vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vec2 travel=wp.xz+vec2(0.0,ship_speed_offset);float hull_d=max(abs(wp.x)/17.8,abs(wp.z)/48.0);float splash_boost=1.0+exp(-abs(hull_d-1.05)*5.0)*0.85;float inner_damp=smoothstep(0.88,1.03,hull_d);float h=wave_height(travel,TIME)*splash_boost*inner_damp;VERTEX.y+=h;wave_h=h;w_pos=vec3(travel.x,wp.y+h,travel.y);float e=0.25;float hx=wave_height(travel+vec2(e,0.0),TIME)*splash_boost*inner_damp;float hz=wave_height(travel+vec2(0.0,e),TIME)*splash_boost*inner_damp;NORMAL=normalize(vec3(h-hx,e,h-hz));}\nvoid fragment(){vec2 uv1=w_pos.xz*0.45+vec2(TIME*0.25,TIME*0.12);vec2 uv2=w_pos.xz*1.45-vec2(TIME*0.18,-TIME*0.24);float e=0.06;float n0=fbm(uv1)+fbm(uv2)*0.5;float nx=fbm(uv1+vec2(e,0.0))+fbm(uv2+vec2(e,0.0))*0.5;float nz=fbm(uv1+vec2(0.0,e))+fbm(uv2+vec2(0.0,e))*0.5;vec3 wn=normalize(vec3((n0-nx)*2.2,1.0,(n0-nz)*2.2));NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(wn.x,0.0,wn.z,0.0)).xyz*0.65);float crest=smoothstep(0.75,1.65,wave_h);float foam_n=fbm(w_pos.xz*0.35+vec2(TIME*0.4,0.0));float foam=clamp(crest*smoothstep(0.38,0.72,foam_n)*1.25,0.0,1.0);vec3 deep=vec3(0.006,0.022,0.052);vec3 mid=vec3(0.018,0.075,0.145);ALBEDO=mix(mix(deep,mid,smoothstep(-1.2,1.4,wave_h)),vec3(0.82,0.90,0.98),foam*0.85);ROUGHNESS=mix(0.03,0.35,foam);METALLIC=0.15;SPECULAR=1.0;}"
	_my_ocean_mat = ShaderMaterial.new()
	_my_ocean_mat.shader = oshd
	ocean.material_override = _my_ocean_mat
	add_child(ocean)

	_my_spray = GPUParticles3D.new()
	_my_spray.name = "MidnightWaveSpray"
	_my_spray.amount = 900
	_my_spray.lifetime = 1.15
	_my_spray.emitting = false
	var smat := ParticleProcessMaterial.new()
	smat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	smat.emission_box_extents = Vector3(0.45, 0.25, 14.0)
	smat.direction = Vector3(-0.85, 1.65, -0.45).normalized()
	smat.spread = 28.0
	smat.initial_velocity_min = 6.5
	smat.initial_velocity_max = 12.5
	smat.gravity = Vector3(0.0, -16.5, -3.0)
	smat.scale_min = 0.04
	smat.scale_max = 0.14
	_my_spray.process_material = smat
	var sdrop := SphereMesh.new()
	sdrop.radius = 0.5
	sdrop.height = 1.0
	sdrop.radial_segments = 8
	sdrop.rings = 4
	var sdmat := StandardMaterial3D.new()
	sdmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sdmat.albedo_color = Color(0.84, 0.93, 1.0, 0.42)
	sdmat.roughness = 0.05
	sdrop.material = sdmat
	_my_spray.draw_pass_1 = sdrop
	add_child(_my_spray)

	var wash_shd := Shader.new()
	wash_shd.code = "shader_type spatial;\nrender_mode blend_mix,depth_draw_never,cull_back,diffuse_burley,specular_schlick_ggx;\nuniform float wash_l=0.0;\nuniform float wash_r=0.0;\nvarying vec3 w_p;\nfloat hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}\nfloat noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}\nfloat fbm(vec2 p){return noise(p)*0.55+noise(p*2.1+3.1)*0.30+noise(p*4.3-1.7)*0.15;}\nvoid vertex(){w_p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}\nvoid fragment(){float surge=w_p.x<0.0?wash_l:wash_r;float edge_dist=clamp((17.0-abs(w_p.x))/7.5,0.0,1.0);float organic=fbm(w_p.xz*vec2(0.28,0.16)+vec2(0.0,TIME*0.45));float puddle_mask=smoothstep(0.46,0.62,organic+(1.0-edge_dist)*surge*0.55);float border_fade=smoothstep(1.0,0.65,edge_dist);float water_alpha=puddle_mask*border_fade;float foam_rim=smoothstep(0.08,0.0,abs((organic+(1.0-edge_dist)*surge*0.55)-0.50))*surge*border_fade;vec2 rip=w_p.xz*2.2+vec2(TIME*0.4,-TIME*0.3);float r0=fbm(rip);float rx=fbm(rip+vec2(0.08,0.0));float rz=fbm(rip+vec2(0.0,0.08));NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4((r0-rx)*1.4,0.0,(r0-rz)*1.4,0.0)).xyz);ALBEDO=mix(vec3(0.04,0.12,0.20),vec3(0.86,0.94,1.0),foam_rim*0.85);ALPHA=clamp(water_alpha*0.62+foam_rim*0.55,0.0,0.82);ROUGHNESS=0.015;METALLIC=0.25;SPECULAR=1.0;}"
	_my_wash_mat = ShaderMaterial.new()
	_my_wash_mat.shader = wash_shd

	var deck_zones := [
		{"pos": Vector3(-11.8, 1.115, -24.0), "size": Vector2(10.2, 27.5)},
		{"pos": Vector3(11.8, 1.115, -24.0), "size": Vector2(10.2, 27.5)},
		{"pos": Vector3(-11.8, 0.015, 0.0), "size": Vector2(10.2, 18.5)},
		{"pos": Vector3(11.8, 0.015, 0.0), "size": Vector2(10.2, 18.5)},
		{"pos": Vector3(-11.8, -1.085, 24.0), "size": Vector2(10.2, 27.5)},
		{"pos": Vector3(11.8, -1.085, 24.0), "size": Vector2(10.2, 27.5)}
	]
	for dz in deck_zones:
		var wmi := MeshInstance3D.new()
		var wpm := PlaneMesh.new()
		wpm.size = dz["size"]
		wmi.mesh = wpm
		wmi.material_override = _my_wash_mat
		wmi.position = dz["pos"]
		add_child(wmi)



	_my_liner = Node3D.new()
	_my_liner.name = "DistantCruiseLiner"
	_my_liner.position = Vector3(175.0, -3.6, -75.0)
	_my_liner.rotation_degrees = Vector3(0.0, -28.0, 0.0)
	var liner_shd := Shader.new()
	liner_shd.code = "shader_type spatial;\nrender_mode cull_back,diffuse_burley,specular_schlick_ggx;\nvarying vec3 w_p;\nvoid vertex(){w_p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}\nvoid fragment(){float deck_line=smoothstep(0.06,0.0,abs(fract(w_p.y*0.32)-0.5));float win_z=step(0.30,fract(w_p.z*0.34))*step(fract(w_p.z*0.34),0.74);float win_y=step(0.32,fract(w_p.y*0.32))*step(fract(w_p.y*0.32),0.62);float is_win=win_z*win_y;vec3 steel=mix(vec3(0.78,0.82,0.88),vec3(0.25,0.30,0.38),deck_line*0.7);ALBEDO=mix(steel,vec3(0.06,0.09,0.14),is_win);EMISSION=vec3(1.0,0.82,0.46)*is_win*3.8;ROUGHNESS=mix(0.38,0.08,is_win);METALLIC=0.22;}"
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
	var orange_mat := StandardMaterial3D.new()
	orange_mat.albedo_color = Color(0.95, 0.42, 0.10)
	for side in [-1.0, 1.0]:
		for lz in range(-44, 48, 16):
			var lb := MeshInstance3D.new()
			var lbm := BoxMesh.new()
			lbm.size = Vector3(1.8, 1.5, 9.5)
			lb.mesh = lbm
			lb.material_override = orange_mat
			lb.position = Vector3(side * 12.2, 6.8, float(lz))
			_my_liner.add_child(lb)
		var nav := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		nav.mesh = sm
		var nmat := StandardMaterial3D.new()
		var ncol := Color(1.0, 0.12, 0.08) if side < 0.0 else Color(0.1, 1.0, 0.28)
		nmat.albedo_color = ncol
		nmat.emission_enabled = true
		nmat.emission = ncol
		nmat.emission_energy_multiplier = 7.0
		nav.material_override = nmat
		nav.position = Vector3(side * 10.5, 18.0, -40.0)
		_my_liner.add_child(nav)

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
		Vector3(-9.5, 1.35, -31.0), Vector3(-4.5, 1.35, -33.0), Vector3(0.0, 1.35, -35.5),
		Vector3(4.5, 1.35, -33.0), Vector3(9.5, 1.35, -31.0), Vector3(-13.5, 1.35, -29.0),
		Vector3(13.5, 1.35, -29.0), Vector3(0.0, 1.35, -28.5)
	]
	for p in red_pts:
		s.append({"pos": p, "yaw": 180.0, "team": 0})
	var blue_pts := [
		Vector3(-9.5, -0.85, 31.0), Vector3(-4.5, -0.85, 33.0), Vector3(0.0, -0.85, 35.5),
		Vector3(4.5, -0.85, 33.0), Vector3(9.5, -0.85, 31.0), Vector3(-13.5, -0.85, 29.0),
		Vector3(13.5, -0.85, 29.0), Vector3(0.0, -0.85, 28.5)
	]
	for p in blue_pts:
		s.append({"pos": p, "yaw": 0.0, "team": 1})
	return s


func get_lanes() -> Dictionary:
	return {
		"left": [
			Vector3(-13.8, 1.35, -28.0), Vector3(-5.8, 1.35, -13.0),
			Vector3(-13.8, 0.25, 0.0), Vector3(-5.8, -0.85, 13.0), Vector3(-13.8, -0.85, 28.0)
		],
		"mid": [
			Vector3(0.0, 1.35, -28.0), Vector3(0.0, 1.35, -18.0),
			Vector3(0.0, 0.25, -4.5), Vector3(0.0, 0.25, 4.5),
			Vector3(0.0, -0.85, 18.0), Vector3(0.0, -0.85, 28.0)
		],
		"right": [
			Vector3(13.8, 1.35, -28.0), Vector3(5.8, 1.35, -13.0),
			Vector3(13.8, 0.25, 0.0), Vector3(5.8, -0.85, 13.0), Vector3(13.8, -0.85, 28.0)
		]
	}


func get_cover_points() -> Array:
	return [
		Vector3(-4.5, 0.25, -4.6), Vector3(4.5, 0.25, 4.6),
		Vector3(-12.2, 1.35, -21.0), Vector3(12.2, 1.35, -21.0),
		Vector3(-12.2, 0.25, 0.0), Vector3(12.2, 0.25, 0.0),
		Vector3(-12.2, -0.85, 21.0), Vector3(12.2, -0.85, 21.0)
	]
