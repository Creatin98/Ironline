extends BlockMap
## HARBOR – High-End 6v6 Superyacht (104m x 36m) – Showcase Rework
## Glattes Yacht-Gelcoat, geschwungener 104m-Rumpf, voll ausgestattete Kommandobrücke,
## VIP-Bar mit Kronleuchtern, Club-Deck, heller Maschinenraum-Keller, Küstengebirge & Kreuzfahrtschiff.

const C_GELCOAT := Color(0.96, 0.97, 0.99)
const C_NAVY := Color(0.07, 0.14, 0.26)
const C_TEAK := Color(0.68, 0.46, 0.26)
const C_MARBLE := Color(0.92, 0.93, 0.95)
const C_CHROME := Color(0.85, 0.88, 0.92)
const C_BRASS := Color(0.86, 0.68, 0.32)
const C_DARK := Color(0.12, 0.14, 0.18)
const C_RED := Color(0.85, 0.22, 0.18)
const C_BLUE := Color(0.18, 0.52, 0.92)

const DECK_Y := 0.0
const LOWER_Y := -3.4
const UPPER_Y := 3.4


func _ready() -> void:
	kill_y = -25.0
	atmosphere_preset = "overcast_industrial"
	super._ready()
	_upgrade_yacht_materials()
	_build_seamless_yacht_hull()
	_build_scenic_coast_and_liner()


func get_blocks() -> Array:
	var b: Array = []

	# ---------------------------------------------------------------- 1. HAUPTDECK (TEAKHOLZ + TREPPEN-SCHÄCHTE)
	b.append(box(Vector3(0, -0.25, 0), Vector3(13.2, 0.5, 76.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, -22.5), Vector3(34.6, 0.5, 31.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.25, 22.5), Vector3(34.6, 0.5, 31.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(-13.9, -0.25, 0), Vector3(6.8, 0.5, 14.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(13.9, -0.25, 0), Vector3(6.8, 0.5, 14.0), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 2. HELLER, TROCKENER MASCHINENRAUM-KELLER (y = -3.4)
	b.append(box(Vector3(0, LOWER_Y - 0.35, 0), Vector3(25.0, 0.7, 54.0), "metal_panel", Color(0.32, 0.35, 0.40)))
	b.append(box(Vector3(-12.2, LOWER_Y + 1.7, 0), Vector3(0.6, 3.6, 54.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(12.2, LOWER_Y + 1.7, 0), Vector3(0.6, 3.6, 54.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, LOWER_Y + 1.7, -26.8), Vector3(25.0, 3.6, 0.6), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, LOWER_Y + 1.7, 26.8), Vector3(25.0, 3.6, 0.6), "ship_hull", C_GELCOAT))
	# Zwei detaillierte V12-Schiffsdiesel mit Zylinderköpfen, Kupferrohren & Kühlern
	for z in [-13.5, 13.5]:
		for side in [-1.0, 1.0]:
			var ex: float = side * 4.4
			b.append(box(Vector3(ex, LOWER_Y + 0.85, z), Vector3(2.2, 1.7, 5.4), "metal_panel", C_NAVY))
			b.append(box(Vector3(ex, LOWER_Y + 1.85, z), Vector3(1.5, 0.35, 4.8), "metal_panel", C_CHROME))
			for cz in [-1.6, 0.0, 1.6]:
				b.append(cylinder(Vector3(ex - 0.45, LOWER_Y + 2.35, z + cz), 0.36, 1.1, "metal_panel", C_BRASS))
				b.append(cylinder(Vector3(ex + 0.45, LOWER_Y + 2.35, z + cz), 0.36, 1.1, "metal_panel", C_CHROME))
	# Ingenieurs-Leitstand & Werkbank im Keller
	b.append(box(Vector3(0, LOWER_Y + 0.6, 0), Vector3(3.8, 1.2, 1.8), "metal_panel", C_DARK))
	b.append(box(Vector3(0, LOWER_Y + 1.25, 0), Vector3(4.0, 0.1, 2.0), "metal_panel", C_CHROME))
	# Breite Niedergangs-Treppen (münden 100 % bündig auf y = 0.0!)
	b.append(ramp(Vector3(-8.6, DECK_Y, -6.2), Vector3(-8.6, LOWER_Y, 3.8), 3.6, "wood_planks", 0.3, C_TEAK))
	b.append(ramp(Vector3(8.6, DECK_Y, 6.2), Vector3(8.6, LOWER_Y, -3.8), 3.6, "wood_planks", 0.3, C_TEAK))

	# ---------------------------------------------------------------- 3. SCHANZLEID & LÜCKENLOSE SICHERHEITSBARRIEREN
	b.append(box(Vector3(-17.2, 0.22, 0), Vector3(0.3, 0.44, 76.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(17.2, 0.22, 0), Vector3(0.3, 0.44, 76.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.22, -37.9), Vector3(34.6, 0.44, 0.3), "ship_hull", C_GELCOAT))
	# Lückenlose unsichtbare Reling-Kollision (niemand fällt mehr ins Wasser!)
	b.append({"pos": Vector3(0, 3.0, 44.0), "size": Vector3(35.0, 6.0, 0.5), "mat": "water", "visible": false})
	b.append({"pos": Vector3(0, 3.0, -44.0), "size": Vector3(35.0, 6.0, 0.5), "mat": "water", "visible": false})
	b.append({"pos": Vector3(-17.4, 3.0, 0), "size": Vector3(0.5, 6.0, 88.0), "mat": "water", "visible": false})
	b.append({"pos": Vector3(17.4, 3.0, 0), "size": Vector3(0.5, 6.0, 88.0), "mat": "water", "visible": false})

	# ---------------------------------------------------------------- 4. BUG-DECK (TEAM ROT) & HECK-HELIPAD (TEAM BLAU)
	b.append(box(Vector3(0, -0.25, -40.8), Vector3(26.0, 0.5, 6.0), "wood_planks", C_TEAK))
	b.append(cylinder(Vector3(0, 0.38, -32.2), 3.8, 0.76, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, 0.68, -32.2), 3.2, 0.14, "water", Color(0.12, 0.85, 0.96)))
	b.append(cylinder(Vector3(0, 0.55, -42.0), 1.1, 1.1, "metal_panel", C_CHROME))
	# CoD-Sichtschutz-Lounges am Bug-Spawn (verhindert Cross-Map-Spawnkills!)
	b.append(box(Vector3(-6.8, 0.55, -31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(6.8, 0.55, -31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, -26.8), Vector3(7.4, 1.1, 0.6), "ship_hull", C_GELCOAT))

	b.append(box(Vector3(0, -0.25, 40.8), Vector3(28.0, 0.5, 6.0), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, -0.68, 44.8), Vector3(22.0, 0.4, 2.8), "wood_planks", C_TEAK))
	b.append(cylinder(Vector3(0, 0.03, 33.5), 8.4, 0.06, "asphalt", C_DARK))
	b.append(cylinder(Vector3(0, 0.05, 33.5), 1.5, 0.06, "metal_panel", C_BRASS))
	# CoD-Sichtschutz-Lounges & Heck-Bar am Blau-Spawn
	b.append(box(Vector3(-6.8, 0.55, 31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(6.8, 0.55, 31.5), Vector3(4.6, 1.1, 1.2), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, 26.8), Vector3(7.4, 1.1, 0.6), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.54, 42.2), Vector3(7.2, 1.08, 1.0), "wood_planks", C_TEAK))
	# ---------------------------------------------------------------- 5. OFFENES MITTELDECK (MARMOR-INFINITY-POOL)
	b.append(cylinder(Vector3(0, 0.36, 0), 3.6, 0.72, "tiles", C_MARBLE))
	b.append(cylinder(Vector3(0, 0.68, 0), 3.0, 0.14, "water", Color(0.12, 0.86, 0.96)))
	b.append(box(Vector3(-4.5, 0.44, -4.6), Vector3(2.2, 0.88, 0.85), "wood_planks", C_TEAK))
	b.append(box(Vector3(4.5, 0.44, 4.6), Vector3(2.2, 0.88, 0.85), "wood_planks", C_TEAK))

	# ---------------------------------------------------------------- 6. NORD-DECKHAUS: VIP-LOUNGE & COCKTAIL-BAR
	b.append_array(room_walls(Vector3(0, 0, -16.0), Vector3(13.2, 3.2, 15.0), 0.32, "ship_hull", C_GELCOAT,
		[{"side": "n", "offset": 0.0, "width": 2.6}, {"side": "s", "offset": 0.0, "width": 2.8},
		 {"side": "w", "offset": -2.5, "width": 2.2}, {"side": "e", "offset": 2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, -23.5), 2.6, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(0, 0, -8.5), 2.8, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-6.6, 0, -18.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(6.6, 0, -13.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	# Beleuchtete Marmor-Bar, Barhocker & VIP-Ledersofas
	b.append(box(Vector3(0, 0.52, -19.2), Vector3(5.0, 1.04, 0.95), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, 1.08, -19.2), Vector3(5.2, 0.1, 1.15), "tiles", C_MARBLE))
	for hx in [-1.8, -0.6, 0.6, 1.8]:
		b.append(cylinder(Vector3(hx, 0.38, -18.2), 0.38, 0.76, "metal_panel", C_BRASS))
	b.append(box(Vector3(-4.0, 0.35, -13.0), Vector3(1.1, 0.7, 3.4), "metal_panel", C_NAVY))
	b.append(box(Vector3(4.0, 0.35, -13.0), Vector3(1.1, 0.7, 3.4), "metal_panel", C_NAVY))

	# Oberdeck Nord (100% stolperfreier Übergang an der Treppe!)
	b.append(box(Vector3(0, UPPER_Y - 0.15, -16.0), Vector3(14.8, 0.3, 16.4), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.02, -16.0), Vector3(14.0, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.22, -8.0), Vector3(14.8, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(2.2, UPPER_Y + 0.22, -24.0), Vector3(10.4, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-7.3, UPPER_Y + 0.22, -14.5), Vector3(0.25, 0.44, 13.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(7.3, UPPER_Y + 0.22, -16.0), Vector3(0.25, 0.44, 16.0), "ship_hull", C_GELCOAT))
	b.append(ramp(Vector3(-5.2, DECK_Y, -30.2), Vector3(-5.2, UPPER_Y + 0.05, -24.0), 3.0, "wood_planks", 0.28, C_TEAK))

	# ---------------------------------------------------------------- 7. SÜD-DECKHAUS: DISCO / CLUB-LOUNGE
	b.append_array(room_walls(Vector3(0, 0, 16.0), Vector3(13.2, 3.2, 15.0), 0.32, "ship_hull", C_GELCOAT,
		[{"side": "n", "offset": 0.0, "width": 2.8}, {"side": "s", "offset": 0.0, "width": 2.6},
		 {"side": "w", "offset": 2.5, "width": 2.2}, {"side": "e", "offset": -2.5, "width": 2.2}]))
	b.append(header(Vector3(0, 0, 8.5), 2.8, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(0, 0, 23.5), 2.6, 2.35, 3.2, 0.32, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-6.6, 0, 18.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(6.6, 0, 13.5), 2.2, 2.35, 3.2, 0.32, false, "ship_hull", C_GELCOAT))
	# Disco-Tanzfläche, DJ-Pult mit Turntables & Bass-Türme
	b.append(box(Vector3(0, 0.03, 15.2), Vector3(5.6, 0.06, 5.4), "tiles", C_NAVY))
	b.append(box(Vector3(0, 0.56, 19.6), Vector3(3.8, 1.12, 1.0), "metal_panel", C_DARK))
	b.append(box(Vector3(0, 1.15, 19.6), Vector3(4.0, 0.08, 1.1), "metal_panel", C_CHROME))
	b.append(box(Vector3(-2.6, 1.1, 19.8), Vector3(0.9, 2.2, 0.9), "metal_panel", C_DARK)) # Lautsprecher-Turm L
	b.append(box(Vector3(2.6, 1.1, 19.8), Vector3(0.9, 2.2, 0.9), "metal_panel", C_DARK))  # Lautsprecher-Turm R
	b.append(box(Vector3(-4.2, 0.35, 14.5), Vector3(1.0, 0.7, 3.4), "metal_panel", C_NAVY))
	b.append(box(Vector3(4.2, 0.35, 14.5), Vector3(1.0, 0.7, 3.4), "metal_panel", C_NAVY))
	# Oberdeck Süd (100% stolperfreier Übergang an der Treppe!)
	b.append(box(Vector3(0, UPPER_Y - 0.15, 16.0), Vector3(14.8, 0.3, 16.4), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 0.02, 16.0), Vector3(14.0, 0.06, 15.6), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.22, 8.0), Vector3(14.8, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-2.2, UPPER_Y + 0.22, 24.0), Vector3(10.4, 0.44, 0.25), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(-7.3, UPPER_Y + 0.22, 16.0), Vector3(0.25, 0.44, 16.0), "ship_hull", C_GELCOAT))
	b.append(box(Vector3(7.3, UPPER_Y + 0.22, 14.5), Vector3(0.25, 0.44, 13.0), "ship_hull", C_GELCOAT))
	b.append(ramp(Vector3(5.2, DECK_Y, 30.2), Vector3(5.2, UPPER_Y + 0.05, 24.0), 3.0, "wood_planks", 0.28, C_TEAK))

	# ---------------------------------------------------------------- 8. VOLL AUSGESTATTETE KOMMANDOBRÜCKE (2. STOCK)
	b.append_array(room_walls(Vector3(0, UPPER_Y, 15.5), Vector3(7.4, 2.35, 6.0), 0.26, "ship_hull", C_GELCOAT,
		[{"side": "w", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		 {"side": "n", "offset": -1.5, "width": 1.8}, {"side": "n", "offset": 1.5, "width": 1.8}]))
	for wx in [-1.5, 1.5]:
		b.append(header(Vector3(wx, 0, 12.5), 1.8, UPPER_Y, UPPER_Y + 0.85, 0.26, true, "ship_hull", C_GELCOAT))
		b.append(header(Vector3(wx, 0, 12.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.35, 0.26, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-3.7, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.35, 0.26, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(3.7, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.0, UPPER_Y + 2.35, 0.26, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 2.45, 15.5), Vector3(8.0, 0.22, 6.6), "ship_hull", C_GELCOAT))
	# Steuerpult, Kapitänssessel & Navigations-Kartentisch in der Kommandobrücke!
	b.append(box(Vector3(0, UPPER_Y + 0.52, 13.4), Vector3(5.0, 1.04, 0.85), "metal_panel", C_DARK))
	b.append(box(Vector3(0, UPPER_Y + 1.08, 13.4), Vector3(5.2, 0.08, 0.95), "wood_planks", C_TEAK))
	b.append(box(Vector3(0, UPPER_Y + 0.45, 14.8), Vector3(0.85, 0.9, 0.85), "metal_panel", C_NAVY)) # Kapitänssessel
	b.append(box(Vector3(0, UPPER_Y + 0.5, 17.2), Vector3(3.2, 1.0, 1.2), "wood_planks", C_TEAK)) # Kartentisch hinten
	# Radar-Bogen
	b.append(box(Vector3(-5.0, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "ship_hull", C_GELCOAT, Vector3(-15, 0, -10)))
	b.append(box(Vector3(5.0, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "ship_hull", C_GELCOAT, Vector3(-15, 0, 10)))
	b.append(box(Vector3(0, UPPER_Y + 4.5, 17.8), Vector3(9.0, 0.36, 1.5), "ship_hull", C_GELCOAT))

	# ---------------------------------------------------------------- 9. AUSSEN-PROMENADEN-DECKUNG & TEAM-MARKIERUNGEN
	for z in [-16.0, 16.0]:
		b.append(box(Vector3(-13.2, 1.05, z), Vector3(1.8, 0.85, 4.8), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(13.2, 1.05, z), Vector3(1.8, 0.85, 4.8), "ship_hull", C_GELCOAT))
		b.append(box(Vector3(-13.2, 1.48, z), Vector3(2.0, 0.22, 5.0), "metal_panel", C_NAVY))
		b.append(box(Vector3(13.2, 1.48, z), Vector3(2.0, 0.22, 5.0), "metal_panel", C_NAVY))
	for z in [-24.0, -9.0, 9.0, 24.0]:
		b.append(cylinder(Vector3(-14.6, 0.65, z), 0.72, 1.3, "ship_hull", C_GELCOAT))
		b.append(cylinder(Vector3(14.6, 0.65, z), 0.72, 1.3, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, 0.55, -43.1), Vector3(2.6, 0.25, 0.15), "ship_hull", C_RED))
	b.append(box(Vector3(0, 0.55, 43.1), Vector3(2.6, 0.25, 0.15), "ship_hull", C_BLUE))
	return b
	# ---------------------------------------------------------------- 8. KOMMANDOBRÜCKE MIT KOMPLETTEM STEUERSTAND (2. STOCK)
	b.append_array(room_walls(Vector3(0, UPPER_Y, 15.5), Vector3(7.4, 2.35, 6.0), 0.26, "ship_hull", C_GELCOAT,
		[{"side": "w", "offset": 0.0, "width": 1.8}, {"side": "e", "offset": 0.0, "width": 1.8},
		 {"side": "n", "offset": -1.5, "width": 1.8}, {"side": "n", "offset": 1.5, "width": 1.8}]))
	for wx in [-1.5, 1.5]:
		b.append(header(Vector3(wx, 0, 12.5), 1.8, UPPER_Y, UPPER_Y + 0.85, 0.26, true, "ship_hull", C_GELCOAT))
		b.append(header(Vector3(wx, 0, 12.5), 1.8, UPPER_Y + 1.98, UPPER_Y + 2.35, 0.26, true, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(-3.7, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.02, UPPER_Y + 2.35, 0.26, false, "ship_hull", C_GELCOAT))
	b.append(header(Vector3(3.7, UPPER_Y, 15.5), 1.8, UPPER_Y + 2.02, UPPER_Y + 2.35, 0.26, false, "ship_hull", C_GELCOAT))
	b.append(box(Vector3(0, UPPER_Y + 2.45, 15.5), Vector3(8.0, 0.22, 6.6), "ship_hull", C_GELCOAT))

	# Detaillierter Brücken-Steuerstand: Hauptkonsole, 3 Monitore, Steuerrad, Schubhebel, Kapitänssessel & Kartentisch!
	b.append(box(Vector3(0, UPPER_Y + 0.52, 13.4), Vector3(5.2, 1.04, 0.85), "metal_panel", C_DARK))
	b.append(box(Vector3(0, UPPER_Y + 1.06, 13.4), Vector3(5.3, 0.08, 0.92), "wood_planks", C_TEAK))
	for mx in [-1.4, 0.0, 1.4]:
		b.append(box(Vector3(mx, UPPER_Y + 1.32, 13.2), Vector3(0.85, 0.45, 0.08), "metal_panel", Color(0.05, 0.45, 0.65), Vector3(-25, 0, 0)))
	b.append(cylinder(Vector3(0, UPPER_Y + 1.15, 13.9), 0.36, 0.08, "metal_panel", C_BRASS)) # Steuerrad
	b.append(box(Vector3(0.75, UPPER_Y + 1.18, 13.75), Vector3(0.28, 0.24, 0.22), "metal_panel", C_CHROME)) # Schubhebel-Block
	b.append(box(Vector3(0, UPPER_Y + 0.45, 14.9), Vector3(0.85, 0.9, 0.85), "metal_panel", C_NAVY)) # Kapitänssessel
	b.append(box(Vector3(0, UPPER_Y + 1.05, 14.55), Vector3(0.85, 0.8, 0.16), "metal_panel", C_NAVY))
	b.append(box(Vector3(-2.4, UPPER_Y + 0.48, 16.8), Vector3(1.8, 0.96, 1.1), "wood_planks", C_TEAK)) # Navigations-Kartentisch

	# Geschwungener Superyacht-Radar-Bogen
	b.append(box(Vector3(-4.9, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "ship_hull", C_GELCOAT, Vector3(-15, 0, -10)))
	b.append(box(Vector3(4.9, UPPER_Y + 2.3, 17.2), Vector3(0.42, 4.6, 1.4), "ship_hull", C_GELCOAT, Vector3(-15, 0, 10)))
	b.append(box(Vector3(0, UPPER_Y + 4.5, 17.8), Vector3(8.8, 0.36, 1.5), "ship_hull", C_GELCOAT))

	# ---------------------------------------------------------------- 9. AUSSEN-PROMENADEN-DECKUNG & TEAM-MARKIERUNGEN
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
	# 1. Deck-LED-Ambiente, Pool-Beleuchtung & Kronleuchter
	d.led_strip(Vector3(-16.9, 0.06, -37.2), Vector3(-16.9, 0.06, 37.2), Color(0.22, 0.78, 1.0), 3.6)
	d.led_strip(Vector3(16.9, 0.06, -37.2), Vector3(16.9, 0.06, 37.2), Color(0.22, 0.78, 1.0), 3.6)
	d.led_strip(Vector3(-6.4, 0.06, -6.0), Vector3(-6.4, 0.06, 6.0), Color(0.22, 0.78, 1.0), 3.2)
	d.led_strip(Vector3(6.4, 0.06, -6.0), Vector3(6.4, 0.06, 6.0), Color(0.22, 0.78, 1.0), 3.2)
	d.bulb(Vector3(-17.0, 1.15, -37.5), Color(1.0, 0.12, 0.08), 1.6, 1.4, 5.5)
	d.bulb(Vector3(17.0, 1.15, -37.5), Color(0.1, 1.0, 0.25), 1.6, 1.4, 5.5)
	d.bulb(Vector3(0, 0.95, 0.0), Color(0.15, 0.90, 1.0), 3.4, 2.8, 9.0)
	d.bulb(Vector3(0, 0.95, -32.2), Color(0.15, 0.90, 1.0), 2.8, 2.4, 7.0)
	d.glow(Vector3(0, UPPER_Y + 6.2, 17.8), Color(1.0, 0.15, 0.1), 1.4)

	# Kronleuchter in VIP-Lounge (Nord) & Disco-Club (Süd)
	for cz in [-15.5, 15.5]:
		var col := Color(1.0, 0.85, 0.55) if cz < 0.0 else Color(0.75, 0.35, 1.0)
		d.add_cylinder(Vector3(0, 2.95, cz), 0.12, 0.5, "metal_panel", C_BRASS)
		d.add_cylinder(Vector3(0, 2.68, cz), 1.4, 0.08, "metal_panel", C_BRASS)
		d.bulb(Vector3(0, 2.55, cz), col, 2.2, 1.8, 11.0)

	# 2. Chrom-Relings mit sauberen Durchgängen
	d.rail(Vector3(-17.2, 0.35, -37.8), Vector3(-17.2, 0.35, 37.8), 0.75)
	d.rail(Vector3(17.2, 0.35, -37.8), Vector3(17.2, 0.35, 37.8), 0.75)
	d.rail(Vector3(-7.3, UPPER_Y + 0.35, -8.0), Vector3(7.3, UPPER_Y + 0.35, -8.0), 0.75)
	d.rail(Vector3(-7.3, UPPER_Y + 0.35, 8.0), Vector3(7.3, UPPER_Y + 0.35, 8.0), 0.75)
	d.rail(Vector3(-3.4, UPPER_Y + 0.35, -24.0), Vector3(7.3, UPPER_Y + 0.35, -24.0), 0.75)
	d.rail(Vector3(-7.3, UPPER_Y + 0.35, 24.0), Vector3(3.4, UPPER_Y + 0.35, 24.0), 0.75)
	for sx in [-6.7, -10.5]:
		d.rail(Vector3(sx, 0.0, -6.2), Vector3(sx, 0.0, 6.2), 0.95)
	for sx in [6.7, 10.5]:
		d.rail(Vector3(sx, 0.0, -6.2), Vector3(sx, 0.0, 6.2), 0.95)

	# 3. Zwei schwarze RIB-Schlauchboote hinter der Heck-Badeplattform
	for bx in [-5.2, 5.2]:
		var bz := 48.0 if bx < 0.0 else 49.8
		d.add_box(Vector3(bx, -2.15, bz), Vector3(2.2, 0.55, 4.8), "metal_panel", Color(0.10, 0.11, 0.13))
		d.add_cylinder(Vector3(bx - 1.0, -1.95, bz), 0.35, 4.6, "metal_panel", Color(0.12, 0.13, 0.15), Basis(Vector3.RIGHT, PI * 0.5))
		d.add_cylinder(Vector3(bx + 1.0, -1.95, bz), 0.35, 4.6, "metal_panel", Color(0.12, 0.13, 0.15), Basis(Vector3.RIGHT, PI * 0.5))

	# 4. Helle Raum- & Maschinenraum-Ausleuchtung (null schwarze Ecken mehr!)
	d.lamp(Vector3(0, 3.0, -16.0), Color(1.0, 0.90, 0.72), 1.6, 14.0)
	d.lamp(Vector3(0, 3.0, 15.5), Color(0.55, 0.30, 1.0), 1.8, 13.0)
	d.lamp(Vector3(0, 2.8, 19.2), Color(0.15, 0.88, 1.0), 1.5, 10.0)
	d.lamp(Vector3(0, UPPER_Y + 2.2, 15.5), Color(0.95, 0.98, 1.0), 1.3, 9.0)
	for kz in [-18.0, -6.0, 6.0, 18.0]:
		for kx in [-5.5, 5.5]:
			d.lamp(Vector3(kx, LOWER_Y + 3.1, kz), Color(0.85, 0.94, 1.0), 1.8, 15.0)
func _upgrade_yacht_materials() -> void:
	var gelcoat := StandardMaterial3D.new()
	gelcoat.albedo_color = C_GELCOAT
	gelcoat.roughness = 0.20
	gelcoat.metallic = 0.04
	gelcoat.clearcoat = 0.65
	gelcoat.clearcoat_roughness = 0.14
	for mi in find_children("*", "MeshInstance3D", true, false):
		var mat = mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		if mat != null and mat.resource_path.contains("ship_hull"):
			mi.material_override = gelcoat


func _build_seamless_yacht_hull() -> void:
	# 1. Nahtlose weiße Außenbordwand von Bugspitze (-52) bis Heck (+48)
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

		# Geschlossenes Teakholz-Deck für Bug- & Heckspitze (keine Lücken mehr zum Rumpf!)
		if z0 < -37.0 or z1 > 37.0:
			var dy0 := lerpf(0.75, 0.01, smoothstep(-52.0, -37.5, z0)) if z0 < 0.0 else 0.01
			var dy1 := lerpf(0.75, 0.01, smoothstep(-52.0, -37.5, z1)) if z1 < 0.0 else 0.01
			var d00 := Vector3(-w0, dy0, z0)
			var d10 := Vector3(w0, dy0, z0)
			var d11 := Vector3(w1, dy1, z1)
			var d01 := Vector3(-w1, dy1, z1)
			deck_st.set_uv(Vector2(0.0, z0 * 0.25)); deck_st.add_vertex(d00)
			deck_st.set_uv(Vector2(1.0, z0 * 0.25)); deck_st.add_vertex(d10)
			deck_st.set_uv(Vector2(1.0, z1 * 0.25)); deck_st.add_vertex(d11)
			deck_st.set_uv(Vector2(0.0, z0 * 0.25)); deck_st.add_vertex(d00)
			deck_st.set_uv(Vector2(1.0, z1 * 0.25)); deck_st.add_vertex(d11)
			deck_st.set_uv(Vector2(0.0, z1 * 0.25)); deck_st.add_vertex(d01)

	st.generate_normals()
	var hull_mi := MeshInstance3D.new()
	hull_mi.name = "SeamlessYachtHull"
	hull_mi.mesh = st.commit()
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = C_GELCOAT
	hmat.roughness = 0.20
	hmat.metallic = 0.05
	hmat.clearcoat = 0.70
	hull_mi.material_override = hmat
	add_child(hull_mi)

	deck_st.generate_normals()
	var deck_mi := MeshInstance3D.new()
	deck_mi.name = "SeamlessTeakEnds"
	deck_mi.mesh = deck_st.commit()
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = C_TEAK
	dmat.roughness = 0.45
	deck_mi.material_override = dmat
	add_child(deck_mi)


func _hull_half_width(z: float) -> float:
	if z < -37.5:
		var u := clampf((z + 52.0) / 14.5, 0.0, 1.0)
		return 17.5 * pow(u, 0.65)
	elif z > 37.5:
		var u := clampf((48.0 - z) / 10.5, 0.0, 1.0)
		return 17.5 * sqrt(u)
	return 17.5


func _build_scenic_coast_and_liner() -> void:
	if has_node("HarborDistantIslands"):
		get_node("HarborDistantIslands").visible = false

	var env_root := Node3D.new()
	env_root.name = "ScenicCoastAndLiner"
	add_child(env_root)

	# 1. Dichter, organischer Regenwald-Gebirgszug (keine Nadelspitzen & keine kaputten Bush-Meshes!)
	var m_shd := Shader.new()
	m_shd.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 w_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Hochauflösende Baumkronen- & Felsrelief-Normalen
	float eps = 1.4;
	float c0 = fbm(w_pos.xz * 0.28 + w_pos.y * 0.14);
	float cx = fbm((w_pos.xz + vec2(eps, 0.0)) * 0.28 + w_pos.y * 0.14);
	float cz = fbm((w_pos.xz + vec2(0.0, eps)) * 0.28 + w_pos.y * 0.14);
	vec3 canopy_nrm = normalize(vec3((c0 - cx) * 4.5, 1.0, (c0 - cz) * 4.5));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(canopy_nrm, 0.0)).xyz, 0.82));

	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - clamp(world_n.y, 0.0, 1.0);
	float n_macro = fbm(w_pos.xz * 0.025);
	float h_var = w_pos.y + (n_macro - 0.5) * 24.0;

	// Dichter tropischer Regenwald (tiefe Kronenschatten & sattes Blattgrün)
	vec3 deep_canopy = vec3(0.015, 0.065, 0.025);
	vec3 bright_canopy = vec3(0.075, 0.19, 0.065);
	vec3 forest_col = mix(deep_canopy, bright_canopy, smoothstep(0.28, 0.78, c0));

	// Dunkler Vulkan-/Schieferfels an steilen Klippen & hohen Graten
	vec3 wet_rock = vec3(0.11, 0.13, 0.16);
	vec3 ridge_rock = vec3(0.24, 0.26, 0.29);
	vec3 rock_col = mix(wet_rock, ridge_rock, c0);

	float rock_mask = clamp(smoothstep(42.0, 78.0, h_var) + smoothstep(0.42, 0.68, slope) * 0.85, 0.0, 1.0);
	vec3 col = mix(forest_col, rock_col, rock_mask);

	// Atmosphärischer Nebel in den Tälern & auf Distanz
	float dist = length(w_pos.xz);
	float depth_haze = smoothstep(240.0, 460.0, dist);
	float valley_mist = 1.0 - smoothstep(-2.0, 24.0, w_pos.y);
	col = mix(col, vec3(0.36, 0.43, 0.50), clamp(depth_haze * 0.55 + valley_mist * 0.38, 0.0, 0.78));

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
"""
	var m_mat := ShaderMaterial.new()
	m_mat.shader = m_shd

	var rng := RandomNumberGenerator.new()
	rng.seed = 202699
	for layer in 3:
		var count := 18 if layer == 0 else (20 if layer == 1 else 22)
		var base_dist := 245.0 + float(layer) * 72.0
		var max_h := 48.0 + float(layer) * 34.0
		var base_rad := 95.0 + float(layer) * 35.0

		for i in count:
			var t := float(i) / float(count)
			var ang := lerpf(0.55, TAU - 0.15, t) + rng.randf_range(-0.08, 0.08)
			var dist := base_dist + rng.randf_range(-18.0, 22.0)
			var m_pos := Vector3(cos(ang) * dist, -6.0, sin(ang) * dist)

			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var rad := base_rad * rng.randf_range(0.85, 1.25)
			var h := max_h * rng.randf_range(0.75, 1.2)
			var rings := 14
			var segs := 28
			var p1 := rng.randf() * TAU
			var p2 := rng.randf() * TAU
			for r in rings:
				var v0 := float(r) / float(rings)
				var v1 := float(r + 1) / float(rings)
				for s in segs:
					var a0 := TAU * float(s) / float(segs)
					var a1 := TAU * float(s + 1) / float(segs)
					var pts: Array[Vector3] = []
					for idx in 4:
						var vv := v0 if (idx == 0 or idx == 1) else v1
						var aa := a0 if (idx == 0 or idx == 3) else a1
						var ridge := 1.0 \
							+ 0.34 * sin(aa * 3.0 + p1) * (1.0 - vv * 0.25) \
							+ 0.20 * cos(aa * 5.0 + p2 + vv * 2.0) \
							+ 0.11 * sin(aa * 8.0 - vv * 3.0)
						# Breite, organische Bergrücken statt spitzer Nadeln!
						var rr := rad * pow(1.0 - vv, 0.62) * ridge
						var yy := vv * h * (1.0 + 0.14 * sin(aa * 2.0 + p1) * vv)
						pts.append(Vector3(cos(aa) * rr, yy, sin(aa) * rr))
					st.add_vertex(pts.front()); st.add_vertex(pts.get(1)); st.add_vertex(pts.get(2))
					st.add_vertex(pts.front()); st.add_vertex(pts.get(2)); st.add_vertex(pts.back())
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = m_mat
			mi.position = m_pos
			env_root.add_child(mi)

	# 2. Majestätisches Kreuzfahrtschiff hoch auf den Wellen (y = +0.4, mit beleuchteten Fensterreihen & Rettungsbooten!)
	var liner := Node3D.new()
	liner.name = "DistantCruiseLiner"
	liner.position = Vector3(195.0, 0.4, -15.0)
	liner.rotation_degrees = Vector3(0.0, -18.0, 0.0)

	var liner_shd := Shader.new()
	liner_shd.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
varying vec3 w_p;
void vertex() { w_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float deck_line = smoothstep(0.07, 0.0, abs(fract(w_p.y * 0.32) - 0.5));
	float win_z = step(0.28, fract(w_p.z * 0.32)) * step(fract(w_p.z * 0.32), 0.76);
	float win_y = step(0.30, fract(w_p.y * 0.32)) * step(fract(w_p.y * 0.32), 0.62);
	float is_win = win_z * win_y;
	vec3 hull_white = mix(vec3(0.86, 0.89, 0.93), vec3(0.22, 0.28, 0.36), deck_line * 0.75);
	ALBEDO = mix(hull_white, vec3(0.08, 0.12, 0.18), is_win);
	EMISSION = vec3(1.0, 0.82, 0.48) * is_win * 2.8;
	ROUGHNESS = mix(0.32, 0.08, is_win);
	SPECULAR = 0.80;
}
"""
	var lmat := ShaderMaterial.new()
	lmat.shader = liner_shd

	var navy_mat := StandardMaterial3D.new()
	navy_mat.albedo_color = Color(0.04, 0.09, 0.18)
	navy_mat.roughness = 0.28

	var red_accent := StandardMaterial3D.new()
	red_accent.albedo_color = Color(0.78, 0.15, 0.14)
	red_accent.roughness = 0.35

	var orange_mat := StandardMaterial3D.new()
	orange_mat.albedo_color = Color(0.95, 0.45, 0.12)
	orange_mat.roughness = 0.35

	var tiers := [
		{"size": Vector3(22.0, 7.5, 175.0), "pos": Vector3(0.0, 1.5, 0.0), "mat": navy_mat},
		{"size": Vector3(22.4, 0.7, 176.0), "pos": Vector3(0.0, 5.4, 0.0), "mat": red_accent},
		{"size": Vector3(20.0, 4.4, 152.0), "pos": Vector3(0.0, 7.8, 2.0), "mat": lmat},
		{"size": Vector3(17.2, 4.2, 126.0), "pos": Vector3(0.0, 11.8, 4.0), "mat": lmat},
		{"size": Vector3(13.8, 3.6, 92.0), "pos": Vector3(0.0, 15.4, 2.0), "mat": lmat},
		{"size": Vector3(16.5, 2.2, 14.0), "pos": Vector3(0.0, 16.9, -36.0), "mat": lmat},
		{"size": Vector3(5.8, 7.2, 11.0), "pos": Vector3(0.0, 20.2, 24.0), "mat": navy_mat},
		{"size": Vector3(6.0, 1.4, 11.2), "pos": Vector3(0.0, 22.2, 24.0), "mat": red_accent}
	]
	for t in tiers:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = t["size"]
		m.mesh = bm
		m.material_override = t["mat"]
		m.position = t["pos"]
		liner.add_child(m)

	# Rettungsboote an den Flanken des Kreuzfahrtschiffs
	for side in [-1.0, 1.0]:
		for lz in range(-36, 42, 14):
			var lb := MeshInstance3D.new()
			var lbm := BoxMesh.new()
			lbm.size = Vector3(1.6, 1.4, 8.5)
			lb.mesh = lbm
			lb.material_override = orange_mat
			lb.position = Vector3(side * 10.6, 6.4, float(lz))
			liner.add_child(lb)

	var bow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(22.0, 24.0, 7.5)
	bow.mesh = pm
	bow.material_override = navy_mat
	bow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	bow.position = Vector3(0.0, 1.5, -99.5)
	liner.add_child(bow)

	for side in [-1.0, 1.0]:
		var nav := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85
		nav.mesh = sm
		var nmat := StandardMaterial3D.new()
		var ncol := Color(1.0, 0.12, 0.08) if side < 0.0 else Color(0.1, 1.0, 0.28)
		nmat.albedo_color = ncol
		nmat.emission_enabled = true
		nmat.emission = ncol
		nmat.emission_energy_multiplier = 6.0
		nav.material_override = nmat
		nav.position = Vector3(side * 9.5, 17.2, -36.0)
		liner.add_child(nav)

	env_root.add_child(liner)
func get_spawns() -> Array:
	var s: Array = []
	var red_pts := [
		Vector3(-9.5, 0.1, -33.5), Vector3(-4.5, 0.1, -35.5), Vector3(0.0, 0.1, -36.5),
		Vector3(4.5, 0.1, -35.5), Vector3(9.5, 0.1, -33.5), Vector3(-13.5, 0.1, -31.0),
		Vector3(13.5, 0.1, -31.0), Vector3(0.0, 0.1, -34.0)
	]
	for p in red_pts:
		s.append({"pos": p, "yaw": 180.0, "team": 0})

	var blue_pts := [
		Vector3(-9.5, 0.1, 33.5), Vector3(-4.5, 0.1, 35.5), Vector3(0.0, 0.1, 36.5),
		Vector3(4.5, 0.1, 35.5), Vector3(9.5, 0.1, 33.5), Vector3(-13.5, 0.1, 31.0),
		Vector3(13.5, 0.1, 31.0), Vector3(0.0, 0.1, 34.0)
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
