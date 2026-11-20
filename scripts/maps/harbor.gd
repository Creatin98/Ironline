extends BlockMap
## HARBOR – High-End Superyacht (96m x 36m) – Complete Showcase Rework
## Vollständig trockener Maschinenraum-Keller, VIP-Lounge/Bar, Club-Deck, Infinity-Pool & Kommandobrücke.

const C_GELCOAT := Color(0.97, 0.98, 0.99)
const C_NAVY := Color(0.08, 0.16, 0.28)
const C_TEAK := Color(0.72, 0.52, 0.32)
const C_MARBLE := Color(0.92, 0.93, 0.95)
const C_CHROME := Color(0.86, 0.89, 0.92)
const C_GLASS := Color(0.14, 0.28, 0.38)
const C_ENGINE := Color(0.18, 0.21, 0.25)
const C_COPPER := Color(0.82, 0.48, 0.26)
const C_RED := Color(0.85, 0.22, 0.18)
const C_BLUE := Color(0.18, 0.52, 0.92)

const DECK_Y := 0.0
const LOWER_Y := -3.4
const UPPER_Y := 3.4


func get_blocks() -> Array:
	var b: Array = []

	# ---------------------------------------------------------------- 1. HAUPTDECK (TEAKHOLZ MIT SAUBEREN TREPPEN-AUSSPARUNGEN)
	b.append(box(Vector3(0, -0.25, 0), Vector3(13.2, 0.5, 76.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, -22.5), Vector3(35.0, 0.5, 31.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, 22.5), Vector3(35.0, 0.5, 31.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(-14.1, -0.25, 0), Vector3(6.8, 0.5, 14.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(14.1, -0.25, 0), Vector3(6.8, 0.5, 14.0), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 2. WASSERDICHTER UNTERDECK-KELLER (MASCHINENRAUM, y = -3.4)
	b.append(box(Vector3(0, LOWER_Y - 0.35, 0), Vector3(25.0, 0.7, 54.0), "asphalt", C_ENGINE))
	b.append(box(Vector3(-12.2, LOWER_Y + 1.7, 0), Vector3(0.6, 3.6, 54.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(12.2, LOWER_Y + 1.7, 0), Vector3(0.6, 3.6, 54.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, LOWER_Y + 1.7, -26.8), Vector3(25.0, 3.6, 0.6), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, LOWER_Y + 1.7, 26.8), Vector3(25.0, 3.6, 0.6), "plaster", C_GELCOAT))
	# Zwei massive V12-Schiffsmotoren, Abgasrohre & Kühlmittel-Tanks im Maschinenraum
	for z in [-13.5, 13.5]:
		b.append(box(Vector3(-4.2, LOWER_Y + 0.95, z), Vector3(2.4, 1.9, 5.6), "metal_panel", C_NAVY))
		b.append(box(Vector3(4.2, LOWER_Y + 0.95, z), Vector3(2.4, 1.9, 5.6), "metal_panel", C_NAVY))
		b.append(cylinder(Vector3(-4.2, LOWER_Y + 2.35, z - 1.2), 0.52, 1.6, "metal_panel", C_CHROME))
		b.append(cylinder(Vector3(4.2, LOWER_Y + 2.35, z - 1.2), 0.52, 1.6, "metal_panel", C_CHROME))
		b.append(cylinder(Vector3(-4.2, LOWER_Y + 2.35, z + 1.2), 0.52, 1.6, "metal_panel", C_COPPER))
		b.append(cylinder(Vector3(4.2, LOWER_Y + 2.35, z + 1.2), 0.52, 1.6, "metal_panel", C_COPPER))
	# Zentraler Kontrollstand & Werkbank im Maschinenraum
	b.append(box(Vector3(0, LOWER_Y + 0.65, 0), Vector3(3.6, 1.3, 2.0), "metal_panel", C_ENGINE))
	b.append(box(Vector3(0, LOWER_Y + 1.35, 0), Vector3(3.8, 0.12, 2.2), "metal_panel", C_CHROME))
	# Zwei sanfte, breite Niedergangs-Treppen ins Unterdeck (x = ±8.6, z = -6.2..+6.2)
	b.append(ramp(Vector3(-8.6, DECK_Y, -6.2), Vector3(-8.6, LOWER_Y, 3.8), 3.6, "wood_planks", 0.3, C_TEAK))
	b.append(ramp(Vector3(8.6, DECK_Y, 6.2), Vector3(8.6, LOWER_Y, -3.8), 3.6, "wood_planks", 0.3, C_TEAK))

	# ---------------------------------------------------------------- 3. GLATTER WEISSER SUPERYACHT-RUMPF (KEIN ROSTBLECH!)
	b.append(box(Vector3(-17.6, -2.1, 0), Vector3(0.5, 4.0, 76.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(17.6, -2.1, 0), Vector3(0.5, 4.0, 76.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(-17.85, -0.55, 0), Vector3(0.16, 0.36, 76.0), "metal_panel", C_NAVY))
	b.append(box(Vector3(17.85, -0.55, 0), Vector3(0.16, 0.36, 76.0), "metal_panel", C_NAVY))
	b.append(box(Vector3(-17.4, 0.18, 0), Vector3(0.28, 0.36, 76.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(17.4, 0.18, 0), Vector3(0.28, 0.36, 76.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, 0.18, -37.9), Vector3(35.0, 0.36, 0.28), "plaster", C_GELCOAT))
	# Unsichtbare Außen-Barrieren
	b.append({"pos": Vector3(0, 3.0, 44.5), "size": Vector3(34.0, 6.0, 0.4), "mat": "water", "visible": false})
	b.append({"pos": Vector3(0, 3.0, -44.5), "size": Vector3(28.0, 6.0, 0.4), "mat": "water", "visible": false})
	b.append({"pos": Vector3(-17.9, 3.0, 0), "size": Vector3(0.4, 6.0, 78.0), "mat": "water", "visible": false})
	b.append({"pos": Vector3(17.9, 3.0, 0), "size": Vector3(0.4, 6.0, 78.0), "mat": "water", "visible": false})

	# ---------------------------------------------------------------- 4. BUG-DECK (NORD / ROT) & HECK-HELIPAD (SÜD / BLAU)
	b.append(box(Vector3(0, -0.25, -40.5), Vector3(24.0, 0.5, 5.5), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -2.1, -40.5), Vector3(24.6, 3.8, 5.8), "plaster", C_GELCOAT))
	b.append(cylinder(Vector3(0, 0.38, -31.8), 3.8, 0.76, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, 0.5, -41.5), 1.0, 1.0, "metal_panel", C_CHROME))
	b.append(box(Vector3(-7.5, 0.38, -31.8), Vector3(1.2, 0.76, 4.8), "plaster", C_GELCOAT))
	b.append(box(Vector3(7.5, 0.38, -31.8), Vector3(1.2, 0.76, 4.8), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, 0.48, -26.5), Vector3(6.6, 0.96, 0.5), "plaster", C_GELCOAT))

	b.append(box(Vector3(0, -0.25, 40.5), Vector3(28.0, 0.5, 5.5), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -2.1, 40.5), Vector3(28.6, 3.8, 5.8), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, -0.65, 44.2), Vector3(23.0, 0.4, 2.6), "wood_planks", C_TEAK))
	b.append(cylinder(Vector3(0, 0.04, 33.5), 8.4, 0.08, "asphalt", C_ENGINE))
	b.append(cylinder(Vector3(0, 0.06, 33.5), 1.5, 0.08, "plaster", Color(0.96, 0.85, 0.22)))
	b.append(box(Vector3(-8.5, 0.38, 32.0), Vector3(1.2, 0.76, 4.8), "plaster", C_GELCOAT))
	b.append(box(Vector3(8.5, 0.38, 32.0), Vector3(1.2, 0.76, 4.8), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, 0.52, 42.0), Vector3(7.0, 1.04, 1.0), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 5. OFFENES MITTELDECK (MARMOR-POOL & LOUNGE)
	b.append(cylinder(Vector3(0, 0.36, 0), 3.4, 0.72, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, 0.66, 0), 2.8, 0.14, "water", Color(0.18, 0.85, 0.95)))
	b.append(box(Vector3(-4.5, 0.44, -4.6), Vector3(2.2, 0.88, 0.85), "wood_planks", C_TEAK))
	b.append(box(Vector3(4.5, 0.44, 4.6), Vector3(2.2, 0.88, 0.85), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 6. NORD-DECKHAUS: VIP-LOUNGE & COCKTAIL-BAR
	b.append_array(room_walls(Vector3(0, 0, -16.0), Vector3(13.2, 3.2, 15.0), 0.32, "plaster", C_GELCOAT,
		[{"side": "n", "offset": 0.0, "width": 2.6}, {"side": "s", "offset": 0.0, "width": 2.8},
		 {"side": "w", "offset": -2.5, "width": 2.2}, {"side": "e", "offset": 2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, -23.5), 2.6, 2.35, 3.2, 0.32, true, "plaster", C_GELCOAT))
	b.append(header(Vector3(0, 0, -8.5), 2.8, 2.35, 3.2, 0.32, true, "plaster", C_GELCOAT))
	b.append(header(Vector3(-6.6, 0, -18.5), 2.2, 2.35, 3.2, 0.32, false, "plaster", C_GELCOAT))
	b.append(header(Vector3(6.6, 0, -13.5), 2.2, 2.35, 3.2, 0.32, false, "plaster", C_GELCOAT))
	# Cocktail-Bar, Marmor-Tresen & VIP-Sofas
	b.append(box(Vector3(0, 0.52, -19.2), Vector3(4.8, 1.04, 0.9), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, 1.08, -19.2), Vector3(5.0, 0.1, 1.1), "tiles", C_MARBLE))
	b.append(box(Vector3(-3.9, 0.35, -13.0), Vector3(1.1, 0.7, 3.2), "plaster", C_NAVY))
	b.append(box(Vector3(3.9, 0.35, -13.0), Vector3(1.1, 0.7, 3.2), "plaster", C_NAVY))
	# Oberdeck Nord (mit sauberem Durchgang bei x = -8.8 für die Treppe!)
	b.append(box(Vector3(0, UPPER_Y - 0.15, -16.0), Vector3(14.8, 0.3, 16.4), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.02, -16.0), Vector3(14.0, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.2, -8.0), Vector3(14.8, 0.4, 0.25), "plaster", C_GELCOAT))
	b.append(box(Vector3(2.2, UPPER_Y + 0.2, -24.0), Vector3(10.4, 0.4, 0.25), "plaster", C_GELCOAT))
	b.append(box(Vector3(-7.3, UPPER_Y + 0.2, -14.5), Vector3(0.25, 0.4, 13.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(7.3, UPPER_Y + 0.2, -16.0), Vector3(0.25, 0.4, 16.0), "plaster", C_GELCOAT))
	# Freitreppe Nord-Oberdeck (mündet direkt in die offene Lücke links!)
	b.append(ramp(Vector3(-5.2, DECK_Y, -29.2), Vector3(-5.2, UPPER_Y, -23.8), 2.8, "wood_planks", 0.26, C_TEAK))

	# ---------------------------------------------------------------- 7. SÜD-DECKHAUS: DISCO / CLUB-LOUNGE & BRÜCKE
	b.append_array(room_walls(Vector3(0, 0, 16.0), Vector3(13.2, 3.2, 15.0), 0.32, "plaster", C_GELCOAT,
		[{"side": "n", "offset": 0.0, "width": 2.8}, {"side": "s", "offset": 0.0, "width": 2.6},
		 {"side": "w", "offset": 2.5, "width": 2.2}, {"side": "e", "offset": -2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, 8.5), 2.8, 2.35, 3.2, 0.32, true, "plaster", C_GELCOAT))
	b.append(header(Vector3(0, 0, 23.5), 2.6, 2.35, 3.2, 0.32, true, "plaster", C_GELCOAT))
	b.append(header(Vector3(-6.6, 0, 18.5), 2.2, 2.35, 3.2, 0.32, false, "plaster", C_GELCOAT))
	b.append(header(Vector3(6.6, 0, 13.5), 2.2, 2.35, 3.2, 0.32, false, "plaster", C_GELCOAT))
	# Disco-Tanzfläche, DJ-Pult & Club-Bänke
	b.append(box(Vector3(0, 0.03, 15.5), Vector3(5.6, 0.06, 5.6), "tiles", C_NAVY))
	b.append(box(Vector3(0, 0.55, 19.6), Vector3(3.6, 1.1, 0.9), "metal_panel", C_ENGINE))
	b.append(box(Vector3(-4.2, 0.35, 14.5), Vector3(1.0, 0.7, 3.4), "plaster", C_NAVY))
	b.append(box(Vector3(4.2, 0.35, 14.5), Vector3(1.0, 0.7, 3.4), "plaster", C_NAVY))
	# Oberdeck Süd (mit sauberem Durchgang bei x = +5.2 für die Treppe!)
	b.append(box(Vector3(0, UPPER_Y - 0.15, 16.0), Vector3(14.8, 0.3, 16.4), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.02, 16.0), Vector3(14.0, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.2, 8.0), Vector3(14.8, 0.4, 0.25), "plaster", C_GELCOAT))
	b.append(box(Vector3(-2.2, UPPER_Y + 0.2, 24.0), Vector3(10.4, 0.4, 0.25), "plaster", C_GELCOAT))
	b.append(box(Vector3(-7.3, UPPER_Y + 0.2, 16.0), Vector3(0.25, 0.4, 16.0), "plaster", C_GELCOAT))
	b.append(box(Vector3(7.3, UPPER_Y + 0.2, 14.5), Vector3(0.25, 0.4, 13.0), "plaster", C_GELCOAT))
	# Freitreppe Süd-Oberdeck (mündet direkt in die offene Lücke rechts!)
	b.append(ramp(Vector3(5.2, DECK_Y, 29.2), Vector3(5.2, UPPER_Y, 23.8), 2.8, "wood_planks", 0.26, C_TEAK))
	# ---------------------------------------------------------------- 8. KOMMANDOBRÜCKE & RADAR-BOGEN (2. STOCK)
	b.append_array(room_walls(Vector3(0, UPPER_Y, 15.5), Vector3(7.2, 2.3, 5.8), 0.26, "plaster", C_GELCOAT,
		[{"side": "w", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		 {"side": "n", "offset": -1.5, "width": 1.8}, {"side": "n", "offset": 1.5, "width": 1.8}]))
	for wx in [-1.5, 1.5]:
		b.append(header(Vector3(wx, 0, 12.6), 1.8, UPPER_Y, UPPER_Y + 0.85, 0.26, true, "plaster", C_GELCOAT))
		b.append(header(Vector3(wx, 0, 12.6), 1.8, UPPER_Y + 1.95, UPPER_Y + 2.3, 0.26, true, "plaster", C_GELCOAT))
	b.append(header(Vector3(-3.6, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.3, 0.26, false, "plaster", C_GELCOAT))
	b.append(header(Vector3(3.6, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.3, 0.26, false, "plaster", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 2.4, 15.5), Vector3(7.8, 0.22, 6.4), "plaster", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.52, 13.6), Vector3(4.4, 1.04, 0.65), "wood_planks", C_TEAK))
	# Geschwungener Radar-Bogen
	b.append(box(Vector3(-4.9, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "plaster", C_GELCOAT, Vector3(-15, 0, -10)))
	b.append(box(Vector3(4.9, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "plaster", C_GELCOAT, Vector3(-15, 0, 10)))
	b.append(box(Vector3(0, UPPER_Y + 4.5, 17.8), Vector3(8.8, 0.36, 1.5), "plaster", C_GELCOAT))

	# ---------------------------------------------------------------- 9. AUSSEN-PROMENADEN-DECKUNG & TEAM-MARKIERUNGEN
	for z in [-16.0, 16.0]:
		b.append(box(Vector3(-13.2, 1.05, z), Vector3(1.8, 0.85, 4.8), "plaster", C_GELCOAT))
		b.append(box(Vector3(13.2, 1.05, z), Vector3(1.8, 0.85, 4.8), "plaster", C_GELCOAT))
		b.append(box(Vector3(-13.2, 1.48, z), Vector3(2.0, 0.22, 5.0), "metal_panel", C_NAVY))
		b.append(box(Vector3(13.2, 1.48, z), Vector3(2.0, 0.22, 5.0), "metal_panel", C_NAVY))
	for z in [-24.0, -9.0, 9.0, 24.0]:
		b.append(cylinder(Vector3(-14.6, 0.65, z), 0.72, 1.3, "plaster", C_GELCOAT))
		b.append(cylinder(Vector3(14.6, 0.65, z), 0.72, 1.3, "plaster", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, -43.1), Vector3(2.6, 0.25, 0.15), "plaster", C_RED))
	b.append(box(Vector3(0, 0.55, 43.1), Vector3(2.6, 0.25, 0.15), "plaster", C_BLUE))
	return b


func build_detail(d: MapDetail) -> void:
	_build_curved_hull_ends(d)

	# 1. Deck-Ambiente-LEDs, Pool-Unterwasserlicht & Disco-Spotlights
	d.led_strip(Vector3(-17.1, 0.06, -37.2), Vector3(-17.1, 0.06, 37.2), Color(0.22, 0.78, 1.0), 3.6)
	d.led_strip(Vector3(17.1, 0.06, -37.2), Vector3(17.1, 0.06, 37.2), Color(0.22, 0.78, 1.0), 3.6)
	d.led_strip(Vector3(-6.4, 0.06, -6.0), Vector3(-6.4, 0.06, 6.0), Color(0.22, 0.78, 1.0), 3.2)
	d.led_strip(Vector3(6.4, 0.06, -6.0), Vector3(6.4, 0.06, 6.0), Color(0.22, 0.78, 1.0), 3.2)
	d.bulb(Vector3(-17.2, 1.15, -37.5), Color(1.0, 0.12, 0.08), 1.6, 1.4, 5.5)
	d.bulb(Vector3(17.2, 1.15, -37.5), Color(0.1, 1.0, 0.25), 1.6, 1.4, 5.5)
	d.bulb(Vector3(0, 0.95, 0.0), Color(0.15, 0.90, 1.0), 3.2, 2.8, 8.5)
	d.bulb(Vector3(0, 0.95, -31.8), Color(0.15, 0.90, 1.0), 2.8, 2.4, 7.0)
	d.glow(Vector3(0, UPPER_Y + 6.2, 17.8), Color(1.0, 0.15, 0.1), 1.4)

	# 2. Chrom-Relings mit offenen Treppen-Durchgängen
	d.rail(Vector3(-17.4, 0.35, -37.8), Vector3(-17.4, 0.35, 37.8), 0.75)
	d.rail(Vector3(17.4, 0.35, -37.8), Vector3(17.4, 0.35, 37.8), 0.75)
	d.rail(Vector3(-7.3, UPPER_Y + 0.35, -8.0), Vector3(7.3, UPPER_Y + 0.35, -8.0), 0.75)
	d.rail(Vector3(-7.3, UPPER_Y + 0.35, 8.0), Vector3(7.3, UPPER_Y + 0.35, 8.0), 0.75)
	d.rail(Vector3(-3.4, UPPER_Y + 0.35, -24.0), Vector3(7.3, UPPER_Y + 0.35, -24.0), 0.75)
	d.rail(Vector3(-7.3, UPPER_Y + 0.35, 24.0), Vector3(3.4, UPPER_Y + 0.35, 24.0), 0.75)
	for sx in [-6.7, -10.5]:
		d.rail(Vector3(sx, 0.0, -6.2), Vector3(sx, 0.0, 6.2), 0.95)
	for sx in [6.7, 10.5]:
		d.rail(Vector3(sx, 0.0, -6.2), Vector3(sx, 0.0, 6.2), 0.95)

	# 3. Zwei schwarze RIB-Beiboote am Heck
	for bx in [-5.2, 5.2]:
		var bz := 47.5 if bx < 0.0 else 49.4
		d.add_box(Vector3(bx, -2.15, bz), Vector3(2.2, 0.55, 4.8), "metal_panel", Color(0.10, 0.11, 0.13))
		d.add_cylinder(Vector3(bx - 1.0, -1.95, bz), 0.35, 4.6, "metal_panel", Color(0.12, 0.13, 0.15), Basis(Vector3.RIGHT, PI * 0.5))
		d.add_cylinder(Vector3(bx + 1.0, -1.95, bz), 0.35, 4.6, "metal_panel", Color(0.12, 0.13, 0.15), Basis(Vector3.RIGHT, PI * 0.5))

	# 4. Raytracing-ähnliche Raum-Ausleuchtung (VIP-Bar, Club-Disco, Brücke & Maschinenraum)
	d.lamp(Vector3(0, 3.0, -16.0), Color(1.0, 0.88, 0.68), 1.5, 13.0) # Warmes VIP-Lounge-Licht
	d.lamp(Vector3(0, 3.0, 15.5), Color(0.45, 0.25, 1.0), 1.8, 12.0)  # Violettes Disco-Club-Licht
	d.lamp(Vector3(0, 2.8, 19.2), Color(0.15, 0.85, 1.0), 1.4, 9.0)   # Cyan DJ-Pult-Licht
	d.lamp(Vector3(0, UPPER_Y + 2.2, 15.5), Color(0.95, 0.97, 1.0), 1.2, 8.0)
	for kz in [-16.0, 0.0, 16.0]:
		d.lamp(Vector3(0, LOWER_Y + 3.0, kz), Color(0.75, 0.90, 1.0), 1.5, 14.0) # Helles Maschinenraum-Licht

func _build_curved_hull_ends(d: MapDetail) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var z0 := lerpf(-38.0, -51.0, t0)
		var z1 := lerpf(-38.0, -51.0, t1)
		var w0 := 17.85 * pow(1.0 - t0, 0.68)
		var w1 := 17.85 * pow(1.0 - t1, 0.68)
		var y_top0 := lerpf(0.36, 1.05, t0)
		var y_top1 := lerpf(0.36, 1.05, t1)
		for side in [-1.0, 1.0]:
			var p00 := Vector3(side * w0, -4.2, z0)
			var p10 := Vector3(side * w1, -4.2, z1)
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
		var p00 := Vector3(sin(a0) * 17.85, -4.2, 38.0 + cos(a0) * 8.0)
		var p10 := Vector3(sin(a1) * 17.85, -4.2, 38.0 + cos(a1) * 8.0)
		var p11 := Vector3(sin(a1) * 17.85, 0.36, 38.0 + cos(a1) * 8.0)
		var p01 := Vector3(sin(a0) * 17.85, 0.36, 38.0 + cos(a0) * 8.0)
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = C_GELCOAT
	mat.roughness = 0.22
	mat.metallic = 0.05
	mi.material_override = mat
	add_child(mi)


func _ready() -> void:
	kill_y = -25.0
	atmosphere_preset = "overcast_industrial"
	super._ready()


func get_spawns() -> Array:
	var s: Array = []
	var red_pts := [
		Vector3(-11.0, 0.1, -29.0), Vector3(-5.5, 0.1, -33.0), Vector3(0.0, 0.1, -35.0),
		Vector3(5.5, 0.1, -33.0), Vector3(11.0, 0.1, -29.0), Vector3(-13.5, 0.1, -26.5),
		Vector3(13.5, 0.1, -26.5), Vector3(0.0, 0.1, -28.0)
	]
	for p in red_pts:
		s.append({"pos": p, "yaw": 180.0, "team": 0})
	var blue_pts := [
		Vector3(-11.0, 0.1, 29.0), Vector3(-5.5, 0.1, 33.0), Vector3(0.0, 0.1, 35.0),
		Vector3(5.5, 0.1, 33.0), Vector3(11.0, 0.1, 29.0), Vector3(-13.5, 0.1, 26.5),
		Vector3(13.5, 0.1, 26.5), Vector3(0.0, 0.1, 28.0)
	]
	for p in blue_pts:
		s.append({"pos": p, "yaw": 0.0, "team": 1})
	return s


func get_lanes() -> Dictionary:
	return {
		"left": [
			Vector3(-13.8, 0.1, -28.0), Vector3(-13.8, 0.1, -12.0),
			Vector3(-13.8, 0.1, 0.0), Vector3(-13.8, 0.1, 12.0), Vector3(-13.8, 0.1, 28.0)
		],
		"mid": [
			Vector3(0.0, 0.1, -28.0), Vector3(0.0, 0.1, -16.0),
			Vector3(0.0, 0.1, -5.0), Vector3(0.0, 0.1, 5.0),
			Vector3(0.0, 0.1, 16.0), Vector3(0.0, 0.1, 28.0)
		],
		"right": [
			Vector3(13.8, 0.1, -28.0), Vector3(13.8, 0.1, -12.0),
			Vector3(13.8, 0.1, 0.0), Vector3(13.8, 0.1, 12.0), Vector3(13.8, 0.1, 28.0)
		]
	}


func get_cover_points() -> Array:
	return [
		Vector3(-4.5, 0.1, -4.6), Vector3(4.5, 0.1, 4.6),
		Vector3(-13.8, 0.1, -12.0), Vector3(13.8, 0.1, 12.0),
		Vector3(0.0, UPPER_Y + 0.1, -12.0), Vector3(0.0, UPPER_Y + 0.1, 10.5),
		Vector3(-4.2, LOWER_Y + 0.1, -8.0), Vector3(4.2, LOWER_Y + 0.1, 8.0)
	]
