class_name Participant
extends RefCounted
## One match participant: a human player (id = network peer id) or a bot (id >= BOT_ID_START).

const BOT_ID_START := 10000

var id: int = 0
var display_name: String = "Spieler"
var team: int = Teams.Team.NONE
var is_bot: bool = false
var bot_difficulty: int = 1
var class_id: String = "assault"
var kills: int = 0
var deaths: int = 0
var assists: int = 0
var score: int = 0
var killstreak: int = 0
var alive: bool = false
var node: Node = null # The Player node while spawned
var is_dummy: bool = false # training target: stands still at dummy_xf, dies and stands up again
var dummy_xf: Transform3D = Transform3D.IDENTITY
var dummy_crouch: bool = false
var is_spectator: bool = false # free-fly camera only: invisible, untouchable, never an enemy


func is_human() -> bool:
	return not is_bot


func is_enemy_of(other: Participant) -> bool:
	if other == null or other.id == id or is_spectator or other.is_spectator:
		return false
	if team == Teams.Team.NONE or other.team == Teams.Team.NONE:
		return true
	return team != other.team


func to_dict() -> Dictionary:
	return {
		"id": id, "name": display_name, "team": team, "is_bot": is_bot,
		"class_id": class_id, "kills": kills, "deaths": deaths, "assists": assists, "score": score,
		"alive": alive,
	}


func apply_dict(d: Dictionary) -> void:
	id = d.get("id", id)
	display_name = d.get("name", display_name)
	team = d.get("team", team)
	is_bot = d.get("is_bot", is_bot)
	class_id = d.get("class_id", class_id)
	kills = d.get("kills", kills)
	deaths = d.get("deaths", deaths)
	assists = d.get("assists", assists)
	score = d.get("score", score)
	alive = d.get("alive", alive)
