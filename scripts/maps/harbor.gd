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
