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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slices := 48
	for i in slices:
		var t0 := float(i) / float(slices)
		var t1 := float(i + 1) / float(slices)
		var z0 := lerpf(-52.0, 48.0, t0)
		var z1 := lerpf(-52.0, 48.0, t1)
		var w0 := _hull_half_width(z0)
		var w1 := _hull_half_width(z1)
		var yt0 := 1.15 if z0 < -38.0 else 0.44
		var yt1 := 1.15 if z1 < -38.0 else 0.44
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


func _hull_half_width(z: float) -> float:
	if z < -37.5:
		var u := clampf((z + 52.0) / 14.5, 0.0, 1.0)
		return 17.5 * pow(u, 0.65)
	elif z > 37.5:
		var u := clampf((48.0 - z) / 10.5, 0.0, 1.0)
		return 17.5 * sqrt(u)
	return 17.5


func _build_scenic_coast_and_liner() -> void:
	var env_root := Node3D.new()
	env_root.name = "ScenicCoastAndLiner"
	add_child(env_root)

	var rng := RandomNumberGenerator.new()
	rng.seed = 202606
	for i in 14:
		var ang := lerpf(-2.4, -0.7, float(i) / 13.0) if i < 7 else lerpf(0.7, 2.4, float(i - 7) / 6.0)
		var dist := rng.randf_range(210.0, 290.0)
		var m_pos := Vector3(cos(ang) * dist, -5.0, sin(ang) * dist)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rad := rng.randf_range(48.0, 82.0)
		var h := rng.randf_range(55.0, 115.0)
		var rings := 10
		var segs := 20
		for r in rings:
			var v0 := float(r) / float(rings)
			var v1 := float(r + 1) / float(rings)
			for s in segs:
				var a0 := TAU * float(s) / float(segs)
				var a1 := TAU * float(s + 1) / float(segs)
				var pts := []
				for pair in [[v0, a0], [v0, a1], [v1, a1], [v1, a0]]:
					var vv: float = pair[0]
					var aa: float = pair[1]
					var ridge := 1.0 + 0.25 * sin(aa * 5.0 + float(i)) * (1.0 - vv * 0.4) + 0.14 * cos(aa * 9.0)
					var rr := rad * (1.0 - vv) * ridge
					var col := Color(0.08, 0.22, 0.12).lerp(Color(0.28, 0.30, 0.33), smoothstep(0.45, 0.78, vv))
					col = col.lerp(Color(0.88, 0.91, 0.95), smoothstep(0.82, 0.98, vv))
					st.set_color(col)
					pts.append(Vector3(cos(aa) * rr, vv * h, sin(aa) * rr))
				st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
				st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mmat := StandardMaterial3D.new()
		mmat.vertex_color_use_as_albedo = true
		mmat.roughness = 0.92
		mi.material_override = mmat
		mi.position = m_pos
		env_root.add_child(mi)

	var liner := Node3D.new()
	liner.name = "DistantCruiseLiner"
	liner.position = Vector3(-135.0, -2.5, -45.0)
	liner.rotation_degrees = Vector3(0.0, 18.0, 0.0)
	var hull_box := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(22.0, 12.0, 145.0)
	hull_box.mesh = hb
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.92, 0.94, 0.97)
	hull_box.material_override = lmat
	hull_box.position = Vector3(0, 4.0, 0)
	liner.add_child(hull_box)
	for deck in [5.5, 8.2, 10.8]:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(22.4, 0.55, 130.0)
		strip.mesh = sm
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(1.0, 0.88, 0.62)
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.85, 0.55)
		emat.emission_energy_multiplier = 2.4
		strip.material_override = emat
		strip.position = Vector3(0, deck, 0)
		liner.add_child(strip)
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
