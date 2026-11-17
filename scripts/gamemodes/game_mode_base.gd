class_name GameModeBase
extends RefCounted
## Rules shared by all game modes. Subclasses override the hooks.

const POINTS_KILL := 100
const POINTS_HEADSHOT_BONUS := 25
const POINTS_ASSIST := 0

var mode_id: String = "base"
var display_name: String = "Modus"
var kill_limit: int = 25
var uses_teams: bool = false
var max_participants: int = 8
var respawn_delay: float = 1.5


func setup(config: MatchConfig) -> void:
	kill_limit = config.kill_limit()
	max_participants = config.max_participants()


## Called by the MatchManager after a kill has been validated.
## Returns points awarded to the killer.
func on_kill(killer: Participant, victim: Participant, headshot: bool) -> int:
	var points := POINTS_KILL
	if headshot:
		points += POINTS_HEADSHOT_BONUS
	return points


## Which team gets a new participant. Balances teams in team modes.
func assign_team(participants: Dictionary, preferred: int) -> int:
	return Teams.Team.NONE


## Returns true if the mode decided the match is over.
func is_kill_limit_reached(team_scores: Dictionary, participants: Dictionary) -> bool:
	return false


## Winner description used by the end screen: {"team": int, "participant_id": int}
func get_leader(team_scores: Dictionary, participants: Dictionary) -> Dictionary:
	return {"team": Teams.Team.NONE, "participant_id": 0}


## Score shown for a team or participant in the HUD.
func get_team_score(team: int, team_scores: Dictionary) -> int:
	return int(team_scores.get(team, 0))
