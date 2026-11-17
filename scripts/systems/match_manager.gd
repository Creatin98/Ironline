extends Node
## Autoload "MatchManager": authoritative match state (roster, scores, timer, rules).
## Online only the server mutates this; clients receive replicated copies through
## NetworkManager (apply_* functions). Offline the local machine is the server.

enum State { IDLE, WARMUP, RUNNING, ENDED }

const WARMUP_TIME := 3.0
const KILL_LIMIT_SAFETY := 999

var config: MatchConfig = MatchConfig.new()
var mode: GameModeBase = TeamDeathmatch.new()
var participants: Dictionary = {} # id -> Participant
var team_scores: Dictionary = {Teams.Team.RED: 0, Teams.Team.BLUE: 0}
var state: int = State.IDLE
var time_left: float = 0.0
var warmup_left: float = 0.0
var local_participant_id: int = 1
var winner: Dictionary = {"team": Teams.Team.NONE, "participant_id": 0}
## victim id -> ids of the assisting players of that victim's latest death (read by the replay/killcam info)
var kill_assists: Dictionary = {}

var _next_bot_id: int = Participant.BOT_ID_START
var _last_whole_second: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if not is_authority():
		# client: count down locally for a smooth display, the server corrects us
		if state == State.WARMUP:
			warmup_left = maxf(0.0, warmup_left - delta)
		elif state == State.RUNNING and config.time_limit > 0.0:
			time_left = maxf(0.0, time_left - delta)
			_emit_whole_second()
		return
	if state == State.WARMUP:
		warmup_left -= delta
		if warmup_left <= 0.0:
			_set_state(State.RUNNING)
			GameEvents.match_started.emit()
	elif state == State.RUNNING and config.time_limit > 0.0:
		time_left = maxf(0.0, time_left - delta)
		if _emit_whole_second():
			NetworkManager.broadcast_time(time_left)
		if time_left <= 0.0:
			end_match()


func _emit_whole_second() -> bool:
	var whole := int(ceil(time_left))
	if whole != _last_whole_second:
		_last_whole_second = whole
		GameEvents.time_changed.emit(time_left)
		return true
	return false


func is_authority() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func get_local_participant() -> Participant:
	return participants.get(local_participant_id)


func get_participant(id: int) -> Participant:
	return participants.get(id)


# ----------------------------------------------------------------------------- setup

func prepare_match(new_config: MatchConfig) -> void:
	config = new_config.duplicate_config()
	mode = _make_mode(config.mode_id)
	mode.setup(config)
	participants.clear()
	team_scores = {Teams.Team.RED: 0, Teams.Team.BLUE: 0}
	winner = {"team": Teams.Team.NONE, "participant_id": 0}
	time_left = config.time_limit
	warmup_left = 0.0
	_last_whole_second = -1
	_next_bot_id = Participant.BOT_ID_START
	_set_state(State.IDLE)


func _make_mode(mode_id: String) -> GameModeBase:
	if mode_id == MatchConfig.MODE_FFA:
		return FreeForAll.new()
	return TeamDeathmatch.new()


func begin_warmup() -> void:
	warmup_left = WARMUP_TIME
	_set_state(State.WARMUP)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	if is_authority():
		NetworkManager.broadcast_match_state(state, time_left, warmup_left)
	GameEvents.match_state_changed.emit(state)


# ----------------------------------------------------------------------------- roster

func add_human(peer_id: int, display_name: String, preferred_team: int, class_id: String) -> Participant:
	var p := Participant.new()
	p.id = peer_id
	p.display_name = display_name
	p.is_bot = false
	p.class_id = class_id
	p.team = mode.assign_team(participants, preferred_team)
	participants[p.id] = p
	GameEvents.participant_added.emit(p.id)
	return p


func add_bot(display_name: String, difficulty: int, class_id: String, preferred_team: int = Teams.Team.NONE) -> Participant:
	var p := Participant.new()
	p.id = _next_bot_id
	_next_bot_id += 1
	p.display_name = display_name
	p.is_bot = true
	p.bot_difficulty = difficulty
	p.class_id = class_id
	p.team = mode.assign_team(participants, preferred_team)
	participants[p.id] = p
	GameEvents.participant_added.emit(p.id)
	return p


func remove_participant(id: int) -> void:
	if participants.has(id):
		participants.erase(id)
		GameEvents.participant_removed.emit(id)
		GameEvents.scores_changed.emit()


func count_participants() -> int:
	return participants.size()


func get_team_members(team: int) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants.values():
		if p.team == team:
			out.append(p)
	return out


func get_enemies_of(id: int) -> Array[Participant]:
	var me: Participant = participants.get(id)
	var out: Array[Participant] = []
	if me == null:
		return out
	for p in participants.values():
		if me.is_enemy_of(p):
			out.append(p)
	return out


## Sorted for the scoreboard: by score, then kills, then fewer deaths.
func get_sorted_participants(team_filter: int = -1) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants.values():
		if team_filter == -1 or p.team == team_filter:
			out.append(p)
	out.sort_custom(func(a: Participant, b: Participant) -> bool:
		if a.score != b.score:
			return a.score > b.score
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.deaths < b.deaths)
	return out


# ----------------------------------------------------------------------------- scoring

## Authoritative kill report. killer_id may be 0 (environment) or equal to victim_id (suicide).
## assist_ids: players that damaged the victim shortly before (see Health.get_assisters).
func report_kill(victim_id: int, killer_id: int, weapon_id: String, headshot: bool, assist_ids: Array = []) -> void:
	if not is_authority() or state != State.RUNNING:
		if state == State.WARMUP or state == State.ENDED:
			_apply_death_only(victim_id)
		return
	var victim: Participant = participants.get(victim_id)
	if victim == null:
		return
	victim.deaths += 1
	victim.killstreak = 0
	victim.alive = false
	var points := 0
	var killer: Participant = participants.get(killer_id)
	if killer != null and killer_id != victim_id and killer.is_enemy_of(victim):
		killer.kills += 1
		killer.killstreak += 1
		points = mode.on_kill(killer, victim, headshot)
		killer.score += points
		if mode.uses_teams and team_scores.has(killer.team):
			team_scores[killer.team] = int(team_scores[killer.team]) + 1
		if killer_id == local_participant_id:
			GameEvents.local_player_scored.emit(points, "Kopfschuss" if headshot else "Kill")
	elif killer != null and killer_id != victim_id:
		# Teamkill: Abzug für den Schützen
		killer.score = maxi(0, killer.score - 50)
	else:
		# Selbstmord
		victim.score = maxi(0, victim.score - 25)
	# assists only count for a real enemy kill and only for enemies of the victim
	var paid_assists: Array = []
	if points > 0:
		for aid in assist_ids:
			var assistant: Participant = participants.get(int(aid))
			if assistant == null or int(aid) == killer_id or not assistant.is_enemy_of(victim):
				continue
			assistant.assists += 1
			assistant.score += mode.on_assist(assistant, victim)
			paid_assists.append(int(aid))
			if int(aid) == local_participant_id:
				GameEvents.local_player_scored.emit(mode.on_assist(assistant, victim), "Assist")
	kill_assists[victim_id] = paid_assists
	GameEvents.participant_killed.emit(victim_id, killer_id, weapon_id, headshot)
	GameEvents.scores_changed.emit()
	NetworkManager.broadcast_kill(victim_id, killer_id, weapon_id, headshot, points, stats_dict(), paid_assists)
	if mode.is_kill_limit_reached(team_scores, participants):
		end_match()


func _apply_death_only(victim_id: int) -> void:
	var victim: Participant = participants.get(victim_id)
	if victim:
		victim.alive = false


func mark_spawned(id: int, node: Node) -> void:
	var p: Participant = participants.get(id)
	if p:
		p.alive = true
		p.node = node
		GameEvents.participant_spawned.emit(id)


func mark_despawned(id: int) -> void:
	var p: Participant = participants.get(id)
	if p:
		p.alive = false
		p.node = null


func end_match() -> void:
	if state == State.ENDED:
		return
	winner = mode.get_leader(team_scores, participants)
	_set_state(State.ENDED)
	NetworkManager.broadcast_match_end(winner, stats_dict())
	GameEvents.match_ended.emit(int(winner["team"]), int(winner["participant_id"]))


func local_player_won() -> bool:
	var me := get_local_participant()
	if me == null:
		return false
	if mode.uses_teams:
		return int(winner["team"]) == me.team
	return int(winner["participant_id"]) == me.id


func is_draw() -> bool:
	if mode.uses_teams:
		return int(winner["team"]) == Teams.Team.NONE
	return int(winner["participant_id"]) == 0


func get_score_for_hud() -> Dictionary:
	## Returns a dictionary the HUD can render for either mode.
	var me := get_local_participant()
	if mode.uses_teams:
		return {
			"teams": true,
			"red": int(team_scores[Teams.Team.RED]),
			"blue": int(team_scores[Teams.Team.BLUE]),
			"limit": mode.kill_limit,
			"my_team": me.team if me else Teams.Team.NONE,
		}
	var sorted := get_sorted_participants()
	var leader: Participant = sorted[0] if sorted.size() > 0 else null
	var second: Participant = sorted[1] if sorted.size() > 1 else null
	return {
		"teams": false,
		"me": me.kills if me else 0,
		"leader_name": leader.display_name if leader else "-",
		"leader_kills": leader.kills if leader else 0,
		"second_name": second.display_name if second else "-",
		"second_kills": second.kills if second else 0,
		"limit": mode.kill_limit,
	}


# ----------------------------------------------------------------------------- replication

## Full state snapshot (used by the network layer and the post-match screen).
func to_dict() -> Dictionary:
	var roster: Array = []
	for p in participants.values():
		roster.append(p.to_dict())
	return {
		"config": config.to_dict(), "participants": roster,
		"team_scores": {"red": team_scores[Teams.Team.RED], "blue": team_scores[Teams.Team.BLUE]},
		"state": state, "time_left": time_left, "warmup_left": warmup_left, "winner": winner,
	}


## Compact score state sent with every kill: {"p": {id: [kills, deaths, score, killstreak, alive]}, "red", "blue"}
func stats_dict() -> Dictionary:
	var p_stats: Dictionary = {}
	for p in participants.values():
		p_stats[p.id] = [p.kills, p.deaths, p.score, p.killstreak, p.alive, p.assists]
	return {"p": p_stats, "red": int(team_scores[Teams.Team.RED]), "blue": int(team_scores[Teams.Team.BLUE])}


func _apply_stats(stats: Dictionary) -> void:
	var p_stats: Dictionary = stats.get("p", {})
	for id in p_stats:
		var p: Participant = participants.get(int(id))
		if p == null:
			continue
		var arr: Array = p_stats[id]
		if arr.size() < 5:
			continue
		p.kills = int(arr[0])
		p.deaths = int(arr[1])
		p.score = int(arr[2])
		p.killstreak = int(arr[3])
		p.alive = bool(arr[4])
		if arr.size() > 5:
			p.assists = int(arr[5])
	team_scores[Teams.Team.RED] = int(stats.get("red", team_scores[Teams.Team.RED]))
	team_scores[Teams.Team.BLUE] = int(stats.get("blue", team_scores[Teams.Team.BLUE]))


## Client: complete state from the server (roster, config, scores, timers).
func apply_full_state(d: Dictionary) -> void:
	config.apply_dict(d.get("config", {}))
	mode = _make_mode(config.mode_id)
	mode.setup(config)
	# keep nodes of participants we already know
	var old_nodes: Dictionary = {}
	for p in participants.values():
		if p.node != null:
			old_nodes[p.id] = p.node
	participants.clear()
	for entry in d.get("participants", []):
		var p := Participant.new()
		p.apply_dict(entry)
		p.node = old_nodes.get(p.id)
		participants[p.id] = p
		GameEvents.participant_added.emit(p.id)
	var ts: Dictionary = d.get("team_scores", {})
	team_scores[Teams.Team.RED] = int(ts.get("red", 0))
	team_scores[Teams.Team.BLUE] = int(ts.get("blue", 0))
	winner = d.get("winner", winner)
	time_left = float(d.get("time_left", time_left))
	warmup_left = float(d.get("warmup_left", warmup_left))
	_set_state(int(d.get("state", state)))
	GameEvents.scores_changed.emit()
	GameEvents.time_changed.emit(time_left)


func apply_remote_state(new_state: int, new_time_left: float, new_warmup_left: float) -> void:
	time_left = new_time_left
	warmup_left = new_warmup_left
	var was := state
	_set_state(new_state)
	if was != State.RUNNING and new_state == State.RUNNING:
		GameEvents.match_started.emit()
	GameEvents.time_changed.emit(time_left)


func apply_remote_time(new_time_left: float) -> void:
	time_left = new_time_left
	_emit_whole_second()


func apply_remote_kill(victim_id: int, killer_id: int, weapon_id: String, headshot: bool, points: int, stats: Dictionary, assist_ids: Array = []) -> void:
	_apply_stats(stats)
	kill_assists[victim_id] = assist_ids
	if assist_ids.has(local_participant_id):
		GameEvents.local_player_scored.emit(GameModeBase.POINTS_ASSIST, "Assist")
	if killer_id == local_participant_id and victim_id != killer_id and points > 0:
		GameEvents.local_player_scored.emit(points, "Kopfschuss" if headshot else "Kill")
	GameEvents.participant_killed.emit(victim_id, killer_id, weapon_id, headshot)
	GameEvents.scores_changed.emit()


func apply_remote_end(new_winner: Dictionary, stats: Dictionary) -> void:
	_apply_stats(stats)
	winner = new_winner
	GameEvents.scores_changed.emit()
	_set_state(State.ENDED)
	GameEvents.match_ended.emit(int(winner["team"]), int(winner["participant_id"]))
