extends Node
## Autoload "GameDirector": scene flow (main menu -> match -> post match -> ...)
## and the registry of maps and classes.

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"

const MAPS: Dictionary = {
	"harbor": {
		"name": "Harbor",
		"scene": "res://scenes/maps/harbor.tscn",
		"description": "Luxusyacht auf offenem Wasser. Decks, Kabinen, Maschinenraum und Sonnendeck.",
		"color": Color(0.3, 0.5, 0.8),
	},
	"frontier": {
		"name": "Frontier",
		"scene": "res://scenes/maps/frontier.tscn",
		"description": "Kleinstadt mit Tankstelle, Gassen, Garagen und Laeden.",
		"color": Color(0.8, 0.6, 0.35),
	},
	"suburb": {
		"name": "Suburb",
		"scene": "res://scenes/maps/suburb.tscn",
		"description": "Bunte Vorstadtsiedlung. Zwei Haeuser, Strasse, Gaerten und Garagen.",
		"color": Color(0.4, 0.7, 0.4),
	},
	"test_arena": {
		"name": "Testarena",
		"scene": "res://scenes/maps/test_arena.tscn",
		"description": "Kompakte Drei-Wege-Trainingsmap.",
		"color": Color(0.55, 0.6, 0.65),
	},
}

## Maps that take part in rotation and voting (the test arena is not one of them).
const ROTATION_MAPS: Array[String] = ["harbor", "frontier", "suburb"]

const CLASSES: Dictionary = {
	"assault": "res://resources/classes/class_assault.tres",
	"smg": "res://resources/classes/class_smg.tres",
	"shotgun": "res://resources/classes/class_shotgun.tres",
}

const BOT_NAMES: Array[String] = [
	"Viper", "Hawk", "Raven", "Ghost", "Blaze", "Frost", "Shadow", "Bolt",
	"Jackal", "Nova", "Cinder", "Drift", "Kestrel", "Onyx", "Pike", "Zephyr",
]

var pending_config: MatchConfig = MatchConfig.new()
var last_match_summary: Dictionary = {}

var _class_cache: Dictionary = {}


func get_class_data(class_id: String) -> ClassData:
	if _class_cache.has(class_id):
		return _class_cache[class_id]
	var path: String = CLASSES.get(class_id, CLASSES["assault"])
	var data: ClassData = load(path)
	_class_cache[class_id] = data
	return data


func get_class_ids() -> Array:
	return CLASSES.keys()


func get_map_ids() -> Array:
	return MAPS.keys()


## Preview image for menus (rendered by tools/shots/generate_previews.sh); null if missing.
func get_map_preview(map_id: String) -> Texture2D:
	return _preview("map_" + map_id)


func get_class_preview(class_id: String) -> Texture2D:
	return _preview("class_" + class_id)


func _preview(name: String) -> Texture2D:
	var path := "res://assets/ui/previews/%s.png" % name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Items for a PreviewPicker: maps (optionally only the rotation maps) or classes.
func map_picker_items(rotation_only: bool = false) -> Array:
	var out: Array = []
	for id in (ROTATION_MAPS if rotation_only else get_map_ids()):
		out.append({"id": id, "title": get_map_info(id)["name"], "texture": get_map_preview(id)})
	return out


func class_picker_items() -> Array:
	var out: Array = []
	for id in get_class_ids():
		out.append({"id": id, "title": get_class_data(id).display_name, "texture": get_class_preview(id)})
	return out


func get_map_info(map_id: String) -> Dictionary:
	return MAPS.get(map_id, MAPS["harbor"])


func start_match(config: MatchConfig) -> void:
	pending_config = config.duplicate_config()
	MatchManager.prepare_match(pending_config)
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## keep_lobby: stay connected (host/clients returning to the online lobby).
func return_to_main_menu(keep_lobby: bool = false) -> void:
	if not keep_lobby:
		NetworkManager.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func quit_game() -> void:
	get_tree().quit()


func random_bot_names(count: int) -> Array[String]:
	var pool: Array[String] = BOT_NAMES.duplicate()
	pool.shuffle()
	var out: Array[String] = []
	for i in count:
		if i < pool.size():
			out.append(pool[i])
		else:
			out.append("Bot %d" % (i + 1))
	return out
