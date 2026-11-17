class_name FreeForAll
extends GameModeBase
## Free for All: jeder gegen jeden, 8 Teilnehmer, 25 Kills.


func _init() -> void:
	mode_id = MatchConfig.MODE_FFA
	display_name = "Free for All"
	kill_limit = 25
	uses_teams = false
	max_participants = 8


func assign_team(participants: Dictionary, preferred: int) -> int:
	return Teams.Team.NONE


func is_kill_limit_reached(team_scores: Dictionary, participants: Dictionary) -> bool:
	for p in participants.values():
		if p.kills >= kill_limit:
			return true
	return false


func get_leader(team_scores: Dictionary, participants: Dictionary) -> Dictionary:
	var sorted: Array = participants.values()
	sorted.sort_custom(func(a: Participant, b: Participant) -> bool:
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.score > b.score)
	if sorted.is_empty():
		return {"team": Teams.Team.NONE, "participant_id": 0}
	var best: Participant = sorted[0]
	if sorted.size() > 1:
		var second: Participant = sorted[1]
		if second.kills == best.kills and second.score == best.score:
			return {"team": Teams.Team.NONE, "participant_id": 0}
	return {"team": Teams.Team.NONE, "participant_id": best.id}
