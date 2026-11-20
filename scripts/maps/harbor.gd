extends BlockMap
## HARBOR – Full-Scale Superyacht (92m x 36m) im Hijacked-Stil:
## 2 getrennte Deckhäuser + Kommandobrücke, offenes Mitteldeck, innere & äußere Seiten-Lanes + begehbarer Maschinenraum-Keller!

const C_HULL := Color(0.95, 0.96, 0.98)
const C_NAVY := Color(0.11, 0.22, 0.36)
const C_TEAK := Color(0.76, 0.58, 0.38)
const C_DARK := Color(0.16, 0.18, 0.22)
const C_CHROME := Color(0.84, 0.87, 0.90)
const C_ORANGE := Color(0.92, 0.44, 0.14)
const C_RED := Color(0.82, 0.22, 0.18)
const C_BLUE := Color(0.20, 0.48, 0.85)

const DECK_Y := 0.0
const LOWER_Y := -3.4
const UPPER_Y := 3.4


func get_blocks() -> Array:
	var b: Array = []

	# ---------------------------------------------------------------- 1. HAUPTDECK (MIT AUSSPARUNGEN FÜR KELLER-TREPPEN)
	# Mittelstreifen zwischen den beiden Treppenschächten (x -6.5..6.5, z -38..38)
	b.append(box(Vector3(0, -0.25, 0), Vector3(13.0, 0.5, 76.0), "wood_planks", C_TEAK))
	# Vor & hinter den Treppenschächten (z -38..-6 und z 6..38 über volle Breite 35m)
	b.append(box(Vector3(0, -0.25, -22.0), Vector3(35.0, 0.5, 32.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, 22.0), Vector3(35.0, 0.5, 32.0), "wood_planks", C_TEAK))
	# Äußere Promenaden-Lanes neben den Treppenschächten (x ±10.5..17.5, z -6..6)
	b.append(box(Vector3(-14.0, -0.25, 0), Vector3(7.0, 0.5, 12.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(14.0, -0.25, 0), Vector3(7.0, 0.5, 12.0), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 2. UNTERDECK-KELLER (MASCHINENRAUM-FLANKE, y = -3.4)
	b.append(box(Vector3(0, LOWER_Y - 0.3, 0), Vector3(24.0, 0.6, 52.0), "metal_panel", C_DARK))
	# Keller-Außenwände & Decke
	b.append(box(Vector3(-11.8, LOWER_Y + 1.6, 0), Vector3(0.4, 3.2, 52.0), "metal_panel", C_DARK))
	b.append(box(Vector3(11.8, LOWER_Y + 1.6, 0), Vector3(0.4, 3.2, 52.0), "metal_panel", C_DARK))
	b.append(box(Vector3(0, LOWER_Y + 1.6, -25.8), Vector3(24.0, 3.2, 0.4), "metal_panel", C_DARK))
	b.append(box(Vector3(0, LOWER_Y + 1.6, 25.8), Vector3(24.0, 3.2, 0.4), "metal_panel", C_DARK))
	# Zwei massive Schiffsturbinen & Rohrsäulen als taktische Deckung im Keller
	for z in [-12.0, 12.0]:
		b.append(box(Vector3(-3.8, LOWER_Y + 0.9, z), Vector3(2.4, 1.8, 5.2), "metal_panel", C_NAVY))
		b.append(box(Vector3(3.8, LOWER_Y + 0.9, z), Vector3(2.4, 1.8, 5.2), "metal_panel", C_NAVY))
		b.append(cylinder(Vector3(-3.8, LOWER_Y + 2.2, z), 0.55, 1.4, "metal_panel", C_CHROME))
		b.append(cylinder(Vector3(3.8, LOWER_Y + 2.2, z), 0.55, 1.4, "metal_panel", C_CHROME))
	b.append(box(Vector3(0, LOWER_Y + 0.7, 0), Vector3(3.2, 1.4, 2.2), "metal_panel", C_DARK)) # Kontrollpult Mitte

	# Zwei breite Keller-Treppen (Backbord & Steuerbord am Mitteldeck: x = ±8.5, z = -5.5..+5.5)
	b.append(ramp(Vector3(-8.5, DECK_Y, -5.5), Vector3(-8.5, LOWER_Y, 3.5), 3.6, "metal_panel", 0.3, C_CHROME))
	b.append(ramp(Vector3(8.5, DECK_Y, 5.5), Vector3(8.5, LOWER_Y, -3.5), 3.6, "metal_panel", 0.3, C_CHROME))

	# ---------------------------------------------------------------- 3. ÄUSSERER YACHT-RUMPF & UNSICHTBARE BARRIEREN
	b.append(box(Vector3(-17.6, -2.2, 0), Vector3(0.5, 3.8, 76.0), "ship_hull", C_HULL))
	b.append(box(Vector3(17.6, -2.2, 0), Vector3(0.5, 3.8, 76.0), "ship_hull", C_HULL))
	b.append(box(Vector3(-17.8, -0.55, 0), Vector3(0.2, 0.35, 76.0), "metal_panel", C_NAVY))
	b.append(box(Vector3(17.8, -0.55, 0), Vector3(0.2, 0.35, 76.0), "metal_panel", C_NAVY))
	# Niedriges weißes Schanzkleid rund ums Deck
	b.append(box(Vector3(-17.4, 0.2, 0), Vector3(0.25, 0.4, 76.0), "ship_hull", C_HULL))
	b.append(box(Vector3(17.4, 0.2, 0), Vector3(0.25, 0.4, 76.0), "ship_hull", C_HULL))
	b.append(box(Vector3(0, 0.2, -37.9), Vector3(35.0, 0.4, 0.25), "ship_hull", C_HULL))
	# Unsichtbare Außen-Barrieren gegen Ins-Wasser-Fallen
	b.append({"pos": Vector3(0, 3.0, 44.5), "size": Vector3(34.0, 6.0, 0.4), "mat": "water", "visible": false})
	b.append({"pos": Vector3(0, 3.0, -44.5), "size": Vector3(28.0, 6.0, 0.4), "mat": "water", "visible": false})
	b.append({"pos": Vector3(-17.9, 3.0, 0), "size": Vector3(0.4, 6.0, 78.0), "mat": "water", "visible": false})
	b.append({"pos": Vector3(17.9, 3.0, 0), "size": Vector3(0.4, 6.0, 78.0), "mat": "water", "visible": false})

	# ---------------------------------------------------------------- 4. BUG-DECK (NORD / ROT, z = -25..-44)
	b.append(box(Vector3(0, -0.25, -40.5), Vector3(24.0, 0.5, 5.5), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -2.2, -40.5), Vector3(24.6, 3.4, 5.8), "ship_hull", C_HULL))
	b.append(cylinder(Vector3(0, 0.4, -31.5), 3.8, 0.8, "tiles")) # Bug-Jacuzzi
	b.append(cylinder(Vector3(0, 0.5, -41.5), 1.1, 1.0, "metal_panel", C_DARK)) # Ankerwinde
	b.append(box(Vector3(-7.5, 0.4, -31.5), Vector3(1.2, 0.8, 4.8), "plaster", C_HULL))
	b.append(box(Vector3(7.5, 0.4, -31.5), Vector3(1.2, 0.8, 4.8), "plaster", C_HULL))
	b.append(box(Vector3(0, 0.5, -26.5), Vector3(6.5, 1.0, 0.5), "ship_hull", C_HULL))

	# ---------------------------------------------------------------- 5. HECK-DECK & HELIPAD (SÜD / BLAU, z = +25..+44)
	b.append(box(Vector3(0, -0.25, 40.5), Vector3(28.0, 0.5, 5.5), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -2.2, 40.5), Vector3(28.6, 3.4, 5.8), "ship_hull", C_HULL))
	b.append(box(Vector3(0, -0.65, 44.2), Vector3(23.0, 0.4, 2.6), "wood_planks", C_TEAK)) # Badeplattform
	b.append(cylinder(Vector3(0, 0.04, 33.5), 8.2, 0.08, "asphalt")) # Helipad
	b.append(cylinder(Vector3(0, 0.06, 33.5), 1.4, 0.08, "plaster", Color(0.95, 0.88, 0.25)))
	b.append(box(Vector3(-8.5, 0.4, 32.0), Vector3(1.2, 0.8, 4.8), "plaster", C_HULL))
	b.append(box(Vector3(8.5, 0.4, 32.0), Vector3(1.2, 0.8, 4.8), "plaster", C_HULL))
	b.append(box(Vector3(0, 0.5, 42.0), Vector3(6.8, 1.0, 1.0), "wood_planks", C_TEAK)) # Heck-Bar

	# ---------------------------------------------------------------- 6. OFFENES MITTELDECK (z = -8.5..+8.5)
	b.append(cylinder(Vector3(0, 0.4, 0), 3.2, 0.8, "tiles")) # Zentraler Whirlpool als Mid-Map-Cover
	b.append(box(Vector3(-4.6, 0.45, -4.8), Vector3(2.2, 0.9, 0.8), "wood_planks", C_TEAK))
	b.append(box(Vector3(4.6, 0.45, 4.8), Vector3(2.2, 0.9, 0.8), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 7. HAUS 1: NORD-DECKHAUS (BUG-VILLA + BALKON-GALERIE, z = -23.5..-8.5)
	b.append_array(room_walls(Vector3(0, 0, -16.0), Vector3(13.0, 3.2, 15.0), 0.32, "ship_hull", C_HULL,
		[{"side": "n", "offset": 0.0, "width": 2.6}, {"side": "s", "offset": 0.0, "width": 2.8},
		 {"side": "w", "offset": -2.5, "width": 2.2}, {"side": "e", "offset": 2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, -23.5), 2.6, 2.3, 3.2, 0.32, true, "ship_hull", C_HULL))
	b.append(header(Vector3(0, 0, -8.5), 2.8, 2.3, 3.2, 0.32, true, "ship_hull", C_HULL))
	b.append(header(Vector3(-6.5, 0, -18.5), 2.2, 2.3, 3.2, 0.32, false, "ship_hull", C_HULL))
	b.append(header(Vector3(6.5, 0, -13.5), 2.2, 2.3, 3.2, 0.32, false, "ship_hull", C_HULL))
	# Innenausstattung Nord-Haus
	b.append(box(Vector3(0, 0.5, -18.5), Vector3(4.4, 1.0, 0.9), "wood_planks", C_TEAK))
	b.append(box(Vector3(-3.8, 0.35, -13.0), Vector3(1.1, 0.7, 3.0), "plaster", C_NAVY))
	b.append(box(Vector3(3.8, 0.35, -13.0), Vector3(1.1, 0.7, 3.0), "plaster", C_NAVY))
	# Dach & offener Aussichtsbalkon (2. Stock über Nord-Haus)
	b.append(box(Vector3(0, UPPER_Y - 0.15, -16.0), Vector3(14.6, 0.3, 16.4), "ship_hull", C_HULL))
	b.append(box(Vector3(0, UPPER_Y + 0.02, -16.0), Vector3(13.8, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.2, -8.0), Vector3(14.6, 0.4, 0.25), "ship_hull", C_HULL)) # Balkon-Brüstung zum Mitteldeck!
	b.append(box(Vector3(0, UPPER_Y + 0.2, -24.0), Vector3(14.6, 0.4, 0.25), "ship_hull", C_HULL))
	b.append(box(Vector3(-7.2, UPPER_Y + 0.2, -14.5), Vector3(0.25, 0.4, 13.0), "ship_hull", C_HULL))
	b.append(box(Vector3(7.2, UPPER_Y + 0.2, -17.5), Vector3(0.25, 0.4, 13.0), "ship_hull", C_HULL))
	# Teakholz-Treppe aufs Nord-Oberdeck
	b.append(ramp(Vector3(-8.8, DECK_Y, -28.0), Vector3(-8.8, UPPER_Y, -21.0), 2.8, "wood_planks", 0.25, C_TEAK))

	# ---------------------------------------------------------------- 8. HAUS 2: SÜD-DECKHAUS + KOMMANDOBRÜCKE (z = +8.5..+23.5)
	b.append_array(room_walls(Vector3(0, 0, 16.0), Vector3(13.0, 3.2, 15.0), 0.32, "ship_hull", C_HULL,
		[{"side": "n", "offset": 0.0, "width": 2.8}, {"side": "s", "offset": 0.0, "width": 2.6},
		 {"side": "w", "offset": 2.5, "width": 2.2}, {"side": "e", "offset": -2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, 8.5), 2.8, 2.3, 3.2, 0.32, true, "ship_hull", C_HULL))
	b.append(header(Vector3(0, 0, 23.5), 2.6, 2.3, 3.2, 0.32, true, "ship_hull", C_HULL))
	b.append(header(Vector3(-6.5, 0, 18.5), 2.2, 2.3, 3.2, 0.32, false, "ship_hull", C_HULL))
	b.append(header(Vector3(6.5, 0, 13.5), 2.2, 2.3, 3.2, 0.32, false, "ship_hull", C_HULL))
	# Innenausstattung Süd-Haus
	b.append(box(Vector3(0, 0.5, 18.5), Vector3(4.4, 1.0, 0.9), "wood_planks", C_TEAK))
	b.append(box(Vector3(-3.8, 0.35, 13.0), Vector3(1.1, 0.7, 3.0), "plaster", C_NAVY))
	b.append(box(Vector3(3.8, 0.35, 13.0), Vector3(1.1, 0.7, 3.0), "plaster", C_NAVY))
	# Oberdeck Süd + Kommandobrücke (2. Stock mit Balkon zum Mitteldeck!)
	b.append(box(Vector3(0, UPPER_Y - 0.15, 16.0), Vector3(14.6, 0.3, 16.4), "ship_hull", C_HULL))
	b.append(box(Vector3(0, UPPER_Y + 0.02, 16.0), Vector3(13.8, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.2, 8.0), Vector3(14.6, 0.4, 0.25), "ship_hull", C_HULL)) # Balkon-Brüstung zum Mitteldeck!
	b.append(box(Vector3(0, UPPER_Y + 0.2, 24.0), Vector3(14.6, 0.4, 0.25), "ship_hull", C_HULL))
	b.append(box(Vector3(-7.2, UPPER_Y + 0.2, 17.5), Vector3(0.25, 0.4, 13.0), "ship_hull", C_HULL))
	b.append(box(Vector3(7.2, UPPER_Y + 0.2, 14.5), Vector3(0.25, 0.4, 13.0), "ship_hull", C_HULL))
	# Kommandobrücke auf dem Süd-Oberdeck
	b.append_array(room_walls(Vector3(0, UPPER_Y, 16.5), Vector3(7.0, 2.3, 6.0), 0.25, "ship_hull", C_HULL,
		[{"side": "w", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		 {"side": "n", "offset": -1.5, "width": 1.8}, {"side": "n", "offset": 1.5, "width": 1.8}]))
	for wx in [-1.5, 1.5]:
		b.append(header(Vector3(wx, 0, 13.5), 1.8, UPPER_Y, UPPER_Y + 0.85, 0.25, true, "ship_hull", C_HULL))
		b.append(header(Vector3(wx, 0, 13.5), 1.8, UPPER_Y + 1.95, UPPER_Y + 2.3, 0.25, true, "ship_hull", C_HULL))
	b.append(header(Vector3(-3.5, UPPER_Y, 16.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.3, 0.25, false, "ship_hull", C_HULL))
	b.append(header(Vector3(3.5, UPPER_Y, 16.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.3, 0.25, false, "ship_hull", C_HULL))
	b.append(box(Vector3(0, UPPER_Y + 2.4, 16.5), Vector3(7.6, 0.22, 6.6), "ship_hull", C_HULL))
	b.append(box(Vector3(0, UPPER_Y + 0.5, 14.5), Vector3(4.2, 1.0, 0.6), "wood_planks", C_TEAK))
	# Geschwungener Radar-Bogen über der Kommandobrücke
	b.append(box(Vector3(-4.8, UPPER_Y + 2.3, 18.0), Vector3(0.42, 4.6, 1.4), "ship_hull", C_HULL, Vector3(-15, 0, -10)))
	b.append(box(Vector3(4.8, UPPER_Y + 2.3, 18.0), Vector3(0.42, 4.6, 1.4), "ship_hull", C_HULL, Vector3(-15, 0, 10)))
	b.append(box(Vector3(0, UPPER_Y + 4.5, 18.6), Vector3(8.6, 0.36, 1.5), "ship_hull", C_HULL))
	# Teakholz-Treppe aufs Süd-Oberdeck
	b.append(ramp(Vector3(8.8, DECK_Y, 28.0), Vector3(8.8, UPPER_Y, 21.0), 2.8, "wood_planks", 0.25, C_TEAK))

	# ---------------------------------------------------------------- 9. ÄUSSERE SEITEN-LANES (X = ±11.5..17.4) – DECKUNG & FLOW
	for z in [-16.0, 16.0]:
		b.append(box(Vector3(-12.8, 1.1, z), Vector3(1.9, 0.85, 4.8), "ship_hull", C_HULL))
		b.append(box(Vector3(12.8, 1.1, z), Vector3(1.9, 0.85, 4.8), "ship_hull", C_HULL))
		b.append(box(Vector3(-12.8, 1.5, z), Vector3(2.1, 0.24, 5.0), "metal_panel", C_ORANGE))
		b.append(box(Vector3(12.8, 1.5, z), Vector3(2.1, 0.24, 5.0), "metal_panel", C_ORANGE))
	for z in [-24.0, -9.0, 9.0, 24.0]:
		b.append(cylinder(Vector3(-14.5, 0.65, z), 0.72, 1.3, "plaster", C_HULL))
		b.append(cylinder(Vector3(14.5, 0.65, z), 0.72, 1.3, "plaster", C_HULL))

	# Team-Markierungen an Bug & Heck
	b.append(box(Vector3(0, 0.55, -43.1), Vector3(2.6, 0.25, 0.15), "plaster", C_RED))
	b.append(box(Vector3(0, 0.55, 43.1), Vector3(2.6, 0.25, 0.15), "plaster", C_BLUE))
	return b


func build_detail(d: MapDetail) -> void:
	_build_curved_hull_ends(d)

	# LED-Deckstreifen & Navigationslichter
	d.led_strip(Vector3(-17.1, 0.06, -37.2), Vector3(-17.1, 0.06, 37.2), Color(0.25, 0.72, 1.0), 3.4)
	d.led_strip(Vector3(17.1, 0.06, -37.2), Vector3(17.1, 0.06, 37.2), Color(0.25, 0.72, 1.0), 3.4)
	d.bulb(Vector3(-17.2, 1.15, -37.5), Color(1.0, 0.12, 0.08), 1.6, 1.4, 5.5)
	d.bulb(Vector3(17.2, 1.15, -37.5), Color(0.1, 1.0, 0.25), 1.6, 1.4, 5.5)
	d.bulb(Vector3(0, 0.95, 0.0), Color(0.2, 0.88, 1.0), 2.6, 2.4, 7.0)
	d.bulb(Vector3(0, 0.95, -31.5), Color(0.2, 0.88, 1.0), 2.5, 2.3, 6.5)

	# Offene Chrom-Reling (Hauptdeck, Balkone & Keller-Treppenschächte)
	d.rail(Vector3(-17.4, 0.35, -37.8), Vector3(-17.4, 0.35, 37.8), 0.75)
	d.rail(Vector3(17.4, 0.35, -37.8), Vector3(17.4, 0.35, 37.8), 0.75)
	d.rail(Vector3(-7.2, UPPER_Y + 0.35, -8.0), Vector3(7.2, UPPER_Y + 0.35, -8.0), 0.75)
	d.rail(Vector3(-7.2, UPPER_Y + 0.35, 8.0), Vector3(7.2, UPPER_Y + 0.35, 8.0), 0.75)
	# Schutzgeländer um die beiden Keller-Treppenschächte
	for sx in [-6.6, -10.4]:
		d.rail(Vector3(sx, 0.0, -5.6), Vector3(sx, 0.0, 5.6), 0.95)
	for sx in [6.6, 10.4]:
		d.rail(Vector3(sx, 0.0, -5.6), Vector3(sx, 0.0, 5.6), 0.95)

	# Zwei schwarze Schlauchboote (RIBs) hinter der Badeplattform
	for bx in [-5.2, 5.2]:
		var bz := 47.5 if bx < 0.0 else 49.4
		d.add_box(Vector3(bx, -2.15, bz), Vector3(2.2, 0.55, 4.8), "metal_panel", Color(0.10, 0.11, 0.13))
		d.add_cylinder(Vector3(bx - 1.0, -1.95, bz), 0.35, 4.6, "metal_panel", Color(0.12, 0.13, 0.15), Basis(Vector3.RIGHT, PI * 0.5))
		d.add_cylinder(Vector3(bx + 1.0, -1.95, bz), 0.35, 4.6, "metal_panel", Color(0.12, 0.13, 0.15), Basis(Vector3.RIGHT, PI * 0.5))

	# Bullaugen & Rettungsringe
	for side in [-1.0, 1.0]:
		var x: float = side * 17.86
		for z in range(-32, 34, 4):
			d.add_cylinder(Vector3(x, -1.35, float(z)), 0.55, 0.05, "metal_panel", C_CHROME, Basis(Vector3.BACK, PI * 0.5))
			d.add_cylinder(Vector3(x + side * 0.02, -1.35, float(z)), 0.42, 0.05, "metal_panel", Color(0.05, 0.08, 0.12), Basis(Vector3.BACK, PI * 0.5))
	for z in [-26.0, -10.0, 10.0, 26.0]:
		for side in [-1.0, 1.0]:
			d.add_cylinder(Vector3(side * 17.25, 0.75, z), 0.60, 0.1, "metal_panel", C_ORANGE, Basis(Vector3.BACK, PI * 0.5))
			d.add_cylinder(Vector3(side * 17.25, 0.75, z), 0.33, 0.11, "plaster", C_HULL, Basis(Vector3.BACK, PI * 0.5))

	# Innenbeleuchtung & Keller-Maschinenraum-Lichter
	d.lamp(Vector3(0, 3.0, -16.0), Color(1.0, 0.93, 0.80), 1.3, 12.0)
	d.lamp(Vector3(0, 3.0, 16.0), Color(1.0, 0.93, 0.80), 1.3, 12.0)
	d.lamp(Vector3(0, UPPER_Y + 2.2, 16.5), Color(0.95, 0.97, 1.0), 1.1, 8.0)
	for kz in [-16.0, 0.0, 16.0]:
		d.lamp(Vector3(0, LOWER_Y + 2.9, kz), Color(0.82, 0.92, 1.0), 1.3, 13.0)


func _build_curved_hull_ends(d: MapDetail) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var z0 := lerpf(-38.0, -50.0, t0)
		var z1 := lerpf(-38.0, -50.0, t1)
		var w0 := 17.85 * pow(1.0 - t0, 0.70)
		var w1 := 17.85 * pow(1.0 - t1, 0.70)
		var y_top0 := lerpf(0.4, 0.95, t0)
		var y_top1 := lerpf(0.4, 0.95, t1)
		for side in [-1.0, 1.0]:
			var p00 := Vector3(side * w0, -4.0, z0)
			var p10 := Vector3(side * w1, -4.0, z1)
			var p11 := Vector3(side * w1, y_top1, z1)
			var p01 := Vector3(side * w0, y_top0, z0)
			if side > 0.0:
				st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
			else:
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
	for i in segs:
		var a0 := lerpf(-PI * 0.5, PI * 0.5, float(i) / float(segs))
		var a1 := lerpf(-PI * 0.5, PI * 0.5, float(i + 1) / float(segs))
		var p00 := Vector3(sin(a0) * 17.85, -4.0, 38.0 + cos(a0) * 7.5)
		var p10 := Vector3(sin(a1) * 17.85, -4.0, 38.0 + cos(a1) * 7.5)
		var p11 := Vector3(sin(a1) * 17.85, 0.4, 38.0 + cos(a1) * 7.5)
		var p01 := Vector3(sin(a0) * 17.85, 0.4, 38.0 + cos(a0) * 7.5)
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = C_HULL
	mat.roughness = 0.25
	mat.metallic = 0.05
	mi.material_override = mat
	d.add_child(mi)
