class_name MatchConfig
extends RefCounted
## Everything the lobby decides before a match starts.

const MODE_TDM := "tdm"
const MODE_FFA := "ffa"

const DIFFICULTY_EASY := 0
const DIFFICULTY_NORMAL := 1
const DIFFICULTY_HARD := 2

var mode_id: String = MODE_TDM
var map_id: String = "harbor"
var map_voting: bool = true
var bots_enabled: bool = true
var bot_count: int = 7
var bot_difficulty: int = DIFFICULTY_NORMAL
var time_limit: float = 600.0 # Sekunden, 0 = unbegrenzt
var local_team: int = Teams.Team.RED
var local_class_id: String = "assault"
var training: bool = false # shooting range: no kill limit, ammo refills, dummies
var spectator: bool = false # free-fly spectator of a bot match (offline)


func max_participants() -> int:
	return 12 if mode_id == MODE_TDM else 8


func kill_limit() -> int:
	return 50 if mode_id == MODE_TDM else 25


func duplicate_config() -> MatchConfig:
	var c := MatchConfig.new()
	c.apply_dict(to_dict())
	return c


func to_dict() -> Dictionary:
	return {
		"mode_id": mode_id, "map_id": map_id, "map_voting": map_voting,
		"training": training, "spectator": spectator, "bots_enabled": bots_enabled, "bot_count": bot_count, "bot_difficulty": bot_difficulty,
		"time_limit": time_limit, "local_team": local_team, "local_class_id": local_class_id,
	}


func apply_dict(d: Dictionary) -> void:
	mode_id = d.get("mode_id", mode_id)
	map_id = d.get("map_id", map_id)
	map_voting = d.get("map_voting", map_voting)
	bots_enabled = d.get("bots_enabled", bots_enabled)
	spectator = d.get("spectator", spectator)
	training = d.get("training", training)
	bot_count = d.get("bot_count", bot_count)
	bot_difficulty = d.get("bot_difficulty", bot_difficulty)
	time_limit = d.get("time_limit", time_limit)
	local_team = d.get("local_team", local_team)
	local_class_id = d.get("local_class_id", local_class_id)
