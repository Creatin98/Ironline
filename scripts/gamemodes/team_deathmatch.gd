class_name TeamDeathmatch
extends GameModeBase
## Team Deathmatch: Rot gegen Blau, 6 vs 6, 50 Team-Kills.


func _init() -> void:
	mode_id = MatchConfig.MODE_TDM
	display_name = "Team Deathmatch"
	kill_limit = 50
	uses_teams = true
	max_participants = 12


func assign_team(participants: Dictionary, preferred: int) -> int:
	var red := 0
	var blue := 0
	for p in participants.values():
		if p.team == Teams.Team.RED:
			red += 1
		elif p.team == Teams.Team.BLUE:
			blue += 1
	if preferred == Teams.Team.RED and red < 6:
		return Teams.Team.RED
	if preferred == Teams.Team.BLUE and blue < 6:
		return Teams.Team.BLUE
	if red <= blue and red < 6:
		return Teams.Team.RED
	if blue < 6:
		return Teams.Team.BLUE
	return Teams.Team.RED if red <= blue else Teams.Team.BLUE


func is_kill_limit_reached(team_scores: Dictionary, participants: Dictionary) -> bool:
	for t in team_scores:
		if int(team_scores[t]) >= kill_limit:
			return true
	return false


func get_leader(team_scores: Dictionary, participants: Dictionary) -> Dictionary:
	var red := int(team_scores.get(Teams.Team.RED, 0))
	var blue := int(team_scores.get(Teams.Team.BLUE, 0))
	if red == blue:
		return {"team": Teams.Team.NONE, "participant_id": 0}
	return {"team": Teams.Team.RED if red > blue else Teams.Team.BLUE, "participant_id": 0}
