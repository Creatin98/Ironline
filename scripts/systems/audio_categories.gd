class_name AudioCategories
extends RefCounted
## Single source of truth for all sound categories: audio buses, their hierarchy, labels for the
## settings menu, default volumes and which sound file belongs to which category.
##
## The ambience categories below "Umgebung allgemein" are silent by default (opt-in: raise the
## slider to hear them). A new category (e.g. a future ambience sound) only needs ONE entry in ENTRIES: the bus is created
## at startup, the slider appears in the sound settings, the value is saved automatically.
## Sounds are assigned to a category in EXACT_SOUNDS / SOUND_PREFIXES by their file name.

## id: key in GameSettings.volumes and in settings.cfg; bus: AudioServer bus; parent: bus it sends to
## (a parent's volume affects all its children); group: heading in the settings menu; preview: unused since every
## slider confirms with the same quiet tick (AudioManager.play_preview).
const ENTRIES: Array[Dictionary] = [
	{"id": "master", "bus": "Master", "parent": "", "label": "Gesamtlautstärke", "group": "Gesamt", "default": 1.0, "preview": "kill_confirm"},
	{"id": "music", "bus": "Music", "parent": "Master", "label": "Musik", "group": "Gesamt", "default": 0.6, "preview": ""},
	{"id": "ui", "bus": "UI", "parent": "Master", "label": "Menü und Oberfläche", "group": "Gesamt", "default": 1.0, "preview": "ui_click"},
	{"id": "sfx", "bus": "SFX", "parent": "Master", "label": "Spielgeräusche gesamt", "group": "Spielgeräusche", "default": 1.0, "preview": "shot_ak47"},
	{"id": "weapons", "bus": "Weapons", "parent": "SFX", "label": "Waffen", "group": "Spielgeräusche", "default": 1.0, "preview": "shot_ak47"},
	{"id": "grenades", "bus": "Grenades", "parent": "SFX", "label": "Granaten und Explosionen", "group": "Spielgeräusche", "default": 1.0, "preview": "explosion"},
	{"id": "reload", "bus": "Reload", "parent": "SFX", "label": "Nachladen", "group": "Spielgeräusche", "default": 1.0, "preview": "reload_mag_in"},
	{"id": "handling", "bus": "Handling", "parent": "SFX", "label": "Waffenwechsel und Klicken", "group": "Spielgeräusche", "default": 1.0, "preview": "weapon_switch"},
	{"id": "movement", "bus": "Movement", "parent": "SFX", "label": "Schritte und Bewegung", "group": "Spielgeräusche", "default": 1.0, "preview": "footstep_1"},
	{"id": "hitmarker", "bus": "Hitmarker", "parent": "SFX", "label": "Hitmarker", "group": "Trefferfeedback", "default": 1.0, "preview": "hitmarker"},
	{"id": "headshot", "bus": "Headshot", "parent": "SFX", "label": "Headshot-Sound", "group": "Trefferfeedback", "default": 1.0, "preview": "hitmarker_headshot"},
	{"id": "kill", "bus": "Kill", "parent": "SFX", "label": "Kill-Sound", "group": "Trefferfeedback", "default": 1.0, "preview": "kill_confirm"},
	{"id": "hit_other", "bus": "HitOther", "parent": "SFX", "label": "Einschläge, Treffer auf dich, Tod", "group": "Trefferfeedback", "default": 1.0, "preview": "bullet_impact"},
	{"id": "ambience", "bus": "Ambience", "parent": "Master", "label": "Umgebung allgemein", "group": "Umgebung", "default": 1.0, "preview": ""},
	{"id": "birds", "bus": "Birds", "parent": "Ambience", "label": "Vögel und Naturgeräusche", "group": "Umgebung", "default": 0.0, "preview": "amb_bird_1"},
	{"id": "wind", "bus": "Wind", "parent": "Ambience", "label": "Wind", "group": "Umgebung", "default": 0.0, "preview": "amb_wind"},
	{"id": "water", "bus": "Water", "parent": "Ambience", "label": "Wasser", "group": "Umgebung", "default": 0.0, "preview": "amb_water"},
	{"id": "distant", "bus": "Distant", "parent": "Ambience", "label": "Flugzeuge und entfernte Geräusche", "group": "Umgebung", "default": 0.0, "preview": "amb_plane"},
	{"id": "breath", "bus": "Breath", "parent": "Ambience", "label": "Eigene Atemgeräusche", "group": "Umgebung", "default": 0.0, "preview": "breath_heavy"},
	{"id": "ambient_other", "bus": "AmbientOther", "parent": "Ambience", "label": "Weitere Umgebungsgeräusche", "group": "Umgebung", "default": 0.0, "preview": ""},
]

## Exact file name -> category id.
const EXACT_SOUNDS := {
	"pump": "reload", "shell_insert": "reload",
	"weapon_switch": "handling", "empty_click": "handling", "ammo_stow": "handling", "medal_hit": "hitmarker",
	"jump": "movement", "land": "movement", "slide": "movement",
	"hitmarker": "hitmarker", "hitmarker_headshot": "headshot",
	"kill_confirm": "kill", "kill_headshot": "kill",
	"bullet_impact": "hit_other", "glass_hit": "hit_other", "glass_break": "hit_other", "glass_tinkle": "hit_other", "ricochet": "hit_other", "hurt": "hit_other", "death": "hit_other",
	"explosion": "grenades", "flashbang_bang": "grenades", "flash_ring": "hit_other",
	"sniper_bolt_open": "reload", "sniper_bolt_close": "reload", "sniper_scope_in": "handling", "sniper_scope_out": "handling", "sniper_scope_zoom": "handling",
	"respawn": "ui", "round_start": "ui", "round_win": "ui", "round_lose": "ui",
	"amb_wind": "wind", "amb_water": "water", "amb_plane": "distant", "amb_gull": "birds",
}

## File name prefix -> category id (checked after EXACT_SOUNDS).
const SOUND_PREFIXES := {
	"shot_": "weapons", "reload_": "reload", "grenade_": "grenades", "footstep_": "movement",
	"ui_": "ui", "countdown_": "ui", "amb_bird": "birds", "breath": "breath",
}


static func get_entry(id: String) -> Dictionary:
	for e in ENTRIES:
		if e["id"] == id:
			return e
	return {}


static func entry_of_bus(bus_name: String) -> Dictionary:
	for e in ENTRIES:
		if e["bus"] == bus_name:
			return e
	return {}


## What actually reaches the speakers: the category's volume times the volumes of all its parent buses
## (e.g. wind x ambience x master). 0 = inaudible, so callers can skip playing a sound at all.
static func effective_volume(id: String, volumes: Dictionary) -> float:
	var v := 1.0
	var e := get_entry(id)
	var guard := 0
	while not e.is_empty() and guard < 8:
		v *= float(volumes.get(String(e["id"]), float(e["default"])))
		var parent_bus := String(e["parent"])
		e = entry_of_bus(parent_bus) if parent_bus != "" else {}
		guard += 1
	return v


static func default_volumes() -> Dictionary:
	var d := {}
	for e in ENTRIES:
		d[e["id"]] = float(e["default"])
	return d


## Category id of a sound file name (without extension); unknown sounds fall back to "sfx".
static func category_of(sfx_name: String) -> String:
	if EXACT_SOUNDS.has(sfx_name):
		return String(EXACT_SOUNDS[sfx_name])
	for prefix in SOUND_PREFIXES:
		if sfx_name.begins_with(prefix):
			return String(SOUND_PREFIXES[prefix])
	return "sfx"


static func bus_of(sfx_name: String) -> String:
	return String(get_entry(category_of(sfx_name))["bus"])


## Creates every bus of ENTRIES that does not exist yet (idempotent, keeps existing buses such as
## Music/SFX/UI from the bus layout) and wires the send hierarchy. Safe to call repeatedly.
static func ensure_buses() -> void:
	for e in ENTRIES:
		var bus_name: String = e["bus"]
		if bus_name == "Master":
			continue
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, StringName(String(e["parent"])))
	# grenades are loud: a limiter keeps the explosion powerful without clipping or distortion
	var g := AudioServer.get_bus_index("Grenades")
	if g >= 0 and AudioServer.get_bus_effect_count(g) == 0:
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -1.0
		lim.threshold_db = -4.0
		AudioServer.add_bus_effect(g, lim)
