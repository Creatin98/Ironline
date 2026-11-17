extends Node
## Two-process network integration test (see tools/run_net_test.py).
##
##   godot --headless --path . tests/net_test.tscn -- --role=host   --port=7791
##   godot --headless --path . tests/net_test.tscn -- --role=client --port=7791
##
## Host and client are separate Godot processes talking over localhost ENet.
## Checks: lobby sync, match start, roster, spawn, input -> server movement,
## server-side reconciliation, hitscan damage + hit feedback, kill/score/respawn
## replication, grenade explosion replication and host-leave handling.
## Exit code 0 = ok.

const GLOBAL_TIMEOUT := 150.0
const TEST_SPOT := Vector3(0.0, 0.1, -17.0)

var role: String = "host"
var port: int = 7791
var scenario: String = "full" # full | leave (client quits mid-match)
var _failures: Array[String] = []
var _stats: Dictionary = {"hits": 0, "died": 0, "explosions": 0, "kills_seen": 0, "disconnected": 0, "votes": 0}
var _started_msec: int = 0


func _ready() -> void:
	if not bool(get_meta("runner", false)):
		# the scene itself is replaced when the match scene loads, so run from a root child
		var runner: Node = (get_script() as GDScript).new()
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
		elif arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg.begins_with("--scenario="):
			scenario = arg.substr(11)
	_started_msec = Time.get_ticks_msec()
	GameSettings.player_name = role
	GameSettings.preferred_team = Teams.Team.RED if role == "host" else Teams.Team.BLUE
	GameSettings.preferred_class_id = "assault"
	GameEvents.local_player_hit_enemy.connect(func(_hs: bool, _k: bool) -> void: _stats["hits"] += 1)
	GameEvents.local_player_died.connect(func(_k: int, _d: float) -> void: _stats["died"] += 1)
	GameEvents.explosion_at.connect(func(_p: Vector3, _r: float) -> void: _stats["explosions"] += 1)
	GameEvents.participant_killed.connect(func(_v: int, _k: int, _w: String, _h: bool) -> void: _stats["kills_seen"] += 1)
	NetworkManager.vote_opened.connect(func(_m: Array, _d: float) -> void: _stats["votes"] += 1)
	NetworkManager.disconnected.connect(func(_r: String) -> void: _stats["disconnected"] += 1)
	if scenario == "trio":
		if role == "host":
			await _host_trio()
		else:
			await _client_trio()
	elif role == "host":
		await _run_host()
	else:
		await _run_client()


func _process(_delta: float) -> void:
	if bool(get_meta("runner", false)) and (Time.get_ticks_msec() - _started_msec) / 1000.0 > GLOBAL_TIMEOUT:
		_fail("Gesamt-Zeitlimit überschritten")
		_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[%s] FEHLER: %s" % [role, msg])


func _log(msg: String) -> void:
	print("[%s] %s" % [role, msg])


func _finish() -> void:
	NetworkManager.leave()
	if _failures.is_empty():
		print("NETTEST %s OK" % role)
		get_tree().quit(0)
	else:
		print("NETTEST %s FEHLGESCHLAGEN (%d Fehler)" % [role, _failures.size()])
		get_tree().quit(1)


func _wait(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _player_of(id: int) -> Player:
	var p := MatchManager.get_participant(id)
	if p == null or p.node == null or not is_instance_valid(p.node):
		return null
	return p.node as Player


## True when every listed player (id -> start position) is at least `min_dist` away from its start.
func _all_moved(starts: Dictionary, min_dist: float) -> bool:
	for id in starts:
		var p := _player_of(int(id))
		if p == null or p.global_position.distance_to(starts[id]) < min_dist:
			return false
	return true


func _client_id() -> int:
	for id in NetworkManager.peers:
		if int(id) != 1:
			return int(id)
	return 0


func _match_running_with(count: int) -> bool:
	if MatchManager.state != MatchManager.State.RUNNING or MatchManager.participants.size() != count:
		return false
	for p in MatchManager.participants.values():
		if not p.alive or p.node == null or not is_instance_valid(p.node):
			return false
	return true


# ----------------------------------------------------------------------------- host

func _run_host() -> void:
	var err := NetworkManager.host(port)
	if err != OK:
		_fail("Host konnte nicht starten (%d)" % err)
		_finish()
		return
	_log("Lobby offen auf Port %d" % port)
	if not await _wait(func() -> bool: return NetworkManager.peers.size() >= 2, 30.0):
		_fail("Client ist der Lobby nicht beigetreten")
		_finish()
		return
	var cid := _client_id()
	var cinfo: Dictionary = NetworkManager.peers[cid]
	if cinfo["name"] != "client" or int(cinfo["team"]) != Teams.Team.BLUE:
		_fail("Lobby-Daten des Clients falsch: %s" % str(cinfo))
	_log("Client %d in der Lobby: %s" % [cid, str(cinfo)])

	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM
	cfg.map_id = "test_arena"
	cfg.bots_enabled = false
	cfg.time_limit = 0.0
	NetworkManager.host_start_match(cfg)
	if not await _wait(func() -> bool: return _match_running_with(2), 40.0):
		_fail("Match wurde nicht gestartet (Zustand %d, Teilnehmer %d)" % [MatchManager.state, MatchManager.participants.size()])
		_finish()
		return
	var me := MatchManager.get_participant(1)
	var other := MatchManager.get_participant(cid)
	if me.team == other.team or me.team == Teams.Team.NONE or other.team == Teams.Team.NONE:
		_fail("Teams falsch verteilt (%d / %d)" % [me.team, other.team])
	_log("Match läuft, 2 Spieler gespawnt")

	var host_player := _player_of(1)
	host_player.human_controller.deactivate()
	if scenario == "leave":
		await _host_leave_scenario(cid)
		return
	var client_node := _player_of(cid)
	if client_node.is_local:
		_fail("Client-Node auf dem Host fälschlich als lokal markiert")

	# 1) client input moves its player on the server
	var start_pos := client_node.global_position
	if not await _wait(func() -> bool: return client_node.global_position.distance_to(start_pos) > 3.0, 20.0):
		_fail("Server hat die Bewegung des Clients nicht übernommen")
		_finish()
		return
	_log("Bewegung des Clients wurde serverseitig simuliert (%.1f m)" % client_node.global_position.distance_to(start_pos))

	# 2) reconciliation: teleport on the server, the client must follow
	var aligned := false
	var end_msec := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < end_msec:
		# keep the client on the spot until it has walked out its scripted input
		client_node.global_position = TEST_SPOT
		client_node.velocity = Vector3.ZERO
		await get_tree().physics_frame
		if absf(angle_difference(client_node.rotation.y, PI)) < 0.15 and client_node.global_position.distance_to(TEST_SPOT) < 1.0:
			aligned = true
			break
	if not aligned:
		_fail("Client folgt der Server-Position nicht (Abgleich) oder dreht sich nicht")
		_finish()
		return
	_log("Client hat die Serverkorrektur übernommen und zielt auf die Teststrecke")

	# 3) client shoots the host: server-side hitscan, damage, hit feedback
	var forward := -client_node.global_transform.basis.z
	host_player.global_position = client_node.global_position + forward * 6.0
	host_player.velocity = Vector3.ZERO
	var max_hp := host_player.health.max_health
	if not await _wait(func() -> bool: return host_player.health.health < max_hp - 10.0, 12.0):
		_fail("Schuss des Clients hat den Host nicht getroffen")
	else:
		_log("Treffer des Clients: Host hat noch %d Lebenspunkte" % int(host_player.health.health))
	await get_tree().create_timer(1.2).timeout

	# 4) kill + score + respawn replication
	host_player.health.health = max_hp
	var killed := client_node.take_damage(5000.0, 1, "ak47", client_node.get_center(), false, host_player.global_position)
	if not killed:
		_fail("Tödlicher Schaden hat den Client nicht getötet")
	await get_tree().process_frame
	if me.kills != 1 or other.deaths != 1:
		_fail("Kill nicht gewertet (Host-Kills %d, Client-Tode %d)" % [me.kills, other.deaths])
	if int(MatchManager.team_scores[me.team]) != 1:
		_fail("Teampunkt fehlt")
	if not await _wait(func() -> bool: return other.alive and _player_of(cid) != null and _player_of(cid).alive, 8.0):
		_fail("Client ist nicht respawnt")
	client_node = _player_of(cid)
	if client_node.class_data.class_id != "shotgun" or client_node.weapon_manager.weapons[0].data.weapon_id != "shotgun":
		_fail("Klassenwechsel des Clients wurde beim Respawn nicht angewendet")
	_log("Kill gewertet, Client respawnt als Shotgun-Klasse")
	await get_tree().create_timer(1.0).timeout

	# 5) grenade replication
	host_player.input.grenade_pressed = true
	if not await _wait(func() -> bool: return int(_stats["explosions"]) >= 1, 8.0):
		_fail("Granate des Hosts ist nicht explodiert")
	else:
		_log("Granate explodiert")
	await get_tree().create_timer(2.0).timeout

	# 6) match end -> map vote -> next round on the voted map
	MatchManager.end_match()
	if not await _wait(func() -> bool: return int(_stats["votes"]) >= 1, 5.0):
		_fail("Kartenabstimmung wurde nicht geöffnet")
	NetworkManager.cast_vote("harbor")
	if not await _wait(func() -> bool: return MatchManager.config.map_id == "harbor" and _match_running_with(2), 60.0):
		_fail("Nächste Runde auf der abgestimmten Map startete nicht (Map %s, Zustand %d)" % [MatchManager.config.map_id, MatchManager.state])
	else:
		_log("Abstimmung ausgewertet, neue Runde läuft auf Harbor")
	await get_tree().create_timer(2.0).timeout
	_log("Host beendet die Lobby")
	_finish()


## Three humans (host + two clients): everybody sees everybody, movement of
## the others arrives, and the map vote waits for all three votes.
func _host_trio() -> void:
	if NetworkManager.host(port) != OK:
		_fail("Host konnte nicht starten")
		_finish()
		return
	if not await _wait(func() -> bool: return NetworkManager.peers.size() >= 3, 40.0):
		_fail("Nicht beide Clients sind beigetreten (Peers %d)" % NetworkManager.peers.size())
		_finish()
		return
	var cfg := MatchConfig.new()
	cfg.mode_id = MatchConfig.MODE_TDM
	cfg.map_id = "test_arena"
	cfg.bots_enabled = false
	cfg.time_limit = 0.0
	NetworkManager.host_start_match(cfg)
	if not await _wait(func() -> bool: return _match_running_with(3), 50.0):
		_fail("Match mit drei Spielern lief nicht an (Teilnehmer %d, Zustand %d)" % [MatchManager.participants.size(), MatchManager.state])
		_finish()
		return
	_log("Match mit drei Spielern läuft")
	# both clients walk (client2 starts later); the host sees both move
	var starts: Dictionary = {}
	for id in NetworkManager.peers:
		if int(id) != 1:
			starts[int(id)] = _player_of(int(id)).global_position
	var moved := await _wait(func() -> bool: return _all_moved(starts, 3.0), 25.0)
	if not moved:
		_fail("Bewegung beider Clients kam auf dem Host nicht an")
	else:
		_log("Beide Clients bewegen sich serverseitig")
	await get_tree().create_timer(2.0).timeout
	MatchManager.end_match()
	if not await _wait(func() -> bool: return int(_stats["votes"]) >= 1, 5.0):
		_fail("Abstimmung nicht geöffnet")
	await get_tree().create_timer(2.0).timeout
	if MatchManager.config.map_id == "frontier":
		_fail("Abstimmung wurde beendet, obwohl nicht alle gewählt hatten")
	NetworkManager.cast_vote("frontier")
	if not await _wait(func() -> bool: return MatchManager.config.map_id == "frontier" and _match_running_with(3), 60.0):
		_fail("Runde auf Frontier mit drei Spielern nicht gestartet (Map %s)" % MatchManager.config.map_id)
	else:
		_log("Alle drei haben gewählt, Runde läuft auf Frontier")
	await get_tree().create_timer(2.0).timeout
	_finish()


func _client_trio() -> void:
	var joined := false
	for attempt in 10:
		if NetworkManager.join("127.0.0.1", port) == OK and await _wait(func() -> bool: return NetworkManager.peers.has(NetworkManager.local_peer_id()), 6.0):
			joined = true
			break
		NetworkManager.leave()
		await get_tree().create_timer(1.0).timeout
	if not joined:
		_fail("Beitritt fehlgeschlagen")
		_finish()
		return
	if not await _wait(func() -> bool: return _match_running_with(3), 60.0):
		_fail("Match mit drei Spielern läuft nicht (Teilnehmer %d)" % MatchManager.participants.size())
		_finish()
		return
	var my_id := NetworkManager.local_peer_id()
	var me := _player_of(my_id)
	var others: Array = []
	for id in MatchManager.participants:
		if int(id) != my_id:
			others.append(int(id))
	var starts: Dictionary = {}
	for id in others:
		if _player_of(id) == null or _player_of(id).is_local:
			_fail("Mitspieler %d fehlt oder ist fälschlich lokal" % id)
			_finish()
			return
		starts[id] = _player_of(id).global_position
	me.human_controller.scripted = true
	me.human_controller.activate()
	if role == "client2":
		await get_tree().create_timer(2.0).timeout
	var walk_start := me.global_position
	me.input.move = Vector2(0, 1)
	await get_tree().create_timer(1.5).timeout
	if me.global_position.distance_to(walk_start) < 2.0:
		me.rotation.y += PI # spawned facing a wall: walk the other way
		await get_tree().create_timer(1.5).timeout
	me.input.move = Vector2.ZERO
	# the two others (host stands still, the other client walks) must be visible at their server positions
	var others_no_host: Dictionary = {}
	for id in others:
		if id != 1:
			others_no_host[id] = starts[id]
	var seen := await _wait(func() -> bool: return _all_moved(others_no_host, 2.0), 25.0)
	if not seen:
		_fail("Bewegung des anderen Clients kam nicht an")
	else:
		_log("Bewegung des anderen Clients sichtbar")
	if not await _wait(func() -> bool: return int(_stats["votes"]) >= 1, 40.0):
		_fail("Abstimmung nicht empfangen")
	else:
		NetworkManager.cast_vote("frontier")
		if not await _wait(func() -> bool: return MatchManager.config.map_id == "frontier" and _match_running_with(3), 60.0):
			_fail("Runde auf Frontier nicht gestartet")
		else:
			_log("Neue Runde auf Frontier mit drei Spielern")
	_finish()


## The client quits mid-match: the host must drop it cleanly and keep playing.
func _host_leave_scenario(cid: int) -> void:
	if not await _wait(func() -> bool: return MatchManager.participants.size() == 1 and NetworkManager.peers.size() == 1, 20.0):
		_fail("Verlassener Client wurde nicht entfernt (Teilnehmer %d, Peers %d)" % [MatchManager.participants.size(), NetworkManager.peers.size()])
		_finish()
		return
	if MatchManager.state != MatchManager.State.RUNNING or _player_of(1) == null or not _player_of(1).alive:
		_fail("Match läuft nach dem Weggang des Clients nicht weiter")
	for n in get_tree().get_nodes_in_group("players"):
		if (n as Player).participant_id == cid:
			_fail("Spieler-Node des verlassenen Clients existiert noch")
	_log("Client entfernt, Match läuft allein weiter")
	await get_tree().create_timer(1.0).timeout
	MatchManager.end_match()
	if not await _wait(func() -> bool: return int(_stats["votes"]) >= 1, 5.0):
		_fail("Abstimmung ohne Mitspieler wurde nicht geöffnet")
	NetworkManager.cast_vote("suburb")
	if not await _wait(func() -> bool: return MatchManager.config.map_id == "suburb" and _match_running_with(1), 60.0):
		_fail("Neue Runde allein nicht gestartet (Map %s, Zustand %d)" % [MatchManager.config.map_id, MatchManager.state])
	else:
		_log("Neue Runde allein auf Suburb läuft")
	_finish()


# ----------------------------------------------------------------------------- client

func _run_client() -> void:
	var joined := false
	for attempt in 8:
		var err := NetworkManager.join("127.0.0.1", port)
		if err == OK and await _wait(func() -> bool: return NetworkManager.peers.has(NetworkManager.local_peer_id()), 6.0):
			joined = true
			break
		NetworkManager.leave()
		await get_tree().create_timer(1.0).timeout
	if not joined:
		_fail("Beitritt zur Lobby fehlgeschlagen")
		_finish()
		return
	_log("In der Lobby als Peer %d" % NetworkManager.local_peer_id())
	if not await _wait(func() -> bool: return _match_running_with(2), 50.0):
		_fail("Match läuft nicht (Zustand %d, Teilnehmer %d)" % [MatchManager.state, MatchManager.participants.size()])
		_finish()
		return
	var my_id := NetworkManager.local_peer_id()
	var me := MatchManager.get_participant(my_id)
	var host_participant := MatchManager.get_participant(1)
	if me == null or host_participant == null:
		_fail("Roster unvollständig")
		_finish()
		return
	if me.team != Teams.Team.BLUE or host_participant.team != Teams.Team.RED:
		_fail("Teams auf dem Client falsch (%d / %d)" % [me.team, host_participant.team])
	if MatchManager.config.map_id != "test_arena" or MatchManager.config.mode_id != MatchConfig.MODE_TDM:
		_fail("Match-Konfiguration nicht übernommen")
	var player := _player_of(my_id)
	var host_node := _player_of(1)
	if player == null or not player.is_local or host_node == null or host_node.is_local:
		_fail("Spieler-Nodes auf dem Client falsch aufgebaut")
		_finish()
		return
	_log("Match läuft, Roster und Nodes stimmen")

	if scenario == "leave":
		await get_tree().create_timer(3.0).timeout
		NetworkManager.leave()
		if NetworkManager.is_online():
			_fail("Client ist nach leave() noch online")
		_log("Client hat das Match verlassen")
		_finish()
		return
	player.human_controller.scripted = true
	player.human_controller.activate()
	# 1) walk forward for a moment (input is sent to the server)
	player.input.move = Vector2(0, 1)
	await get_tree().create_timer(1.5).timeout
	player.input.move = Vector2.ZERO

	# 2) wait for the server to teleport us, then look down the test lane
	if not await _wait(func() -> bool: return player.global_position.distance_to(TEST_SPOT) < 1.5, 25.0):
		_fail("Serverkorrektur hat den Client nicht an die Teststelle gesetzt (Position %s)" % str(player.global_position))
		_finish()
		return
	player.rotation.y = PI
	_log("Client folgt der Serverkorrektur")

	# 3) shoot as soon as the host stands in front of us
	if not await _wait(func() -> bool: return host_node.global_position.distance_to(player.global_position) < 8.0, 20.0):
		_fail("Host-Spieler erscheint nicht vor dem Client (Position %s)" % str(host_node.global_position))
		_finish()
		return
	player.input.fire_held = true
	if not await _wait(func() -> bool: return int(_stats["hits"]) >= 1, 8.0):
		_fail("Kein Trefferfeedback vom Server erhalten")
	else:
		_log("Trefferfeedback erhalten")
	player.input.fire_held = false
	NetworkManager.request_class_change("shotgun")

	# 4) server kills us -> death, score, respawn must arrive
	if not await _wait(func() -> bool: return int(_stats["died"]) >= 1, 20.0):
		_fail("Tod wurde nicht repliziert")
	elif me.deaths != 1 or host_participant.kills != 1:
		_fail("Spielstand nach dem Tod falsch (Tode %d, Host-Kills %d)" % [me.deaths, host_participant.kills])
	if not await _wait(func() -> bool: return _player_of(my_id) != null and _player_of(my_id).alive and me.alive, 10.0):
		_fail("Respawn wurde nicht repliziert")
	var respawned := _player_of(my_id)
	if respawned == null or respawned.weapon_manager.get_current_weapon().data.weapon_id != "shotgun":
		_fail("Neue Klasse (Shotgun) ist nach dem Respawn nicht aktiv")
	_log("Tod und Respawn repliziert, neue Klasse aktiv")

	# 5) grenade explosion thrown by the host
	if not await _wait(func() -> bool: return int(_stats["explosions"]) >= 1, 15.0):
		_fail("Granatenexplosion nicht empfangen")
	else:
		_log("Granatenexplosion empfangen")

	# 6) match end -> vote, then the next round starts on the voted map
	if not await _wait(func() -> bool: return int(_stats["votes"]) >= 1, 15.0):
		_fail("Abstimmung nicht empfangen")
	else:
		NetworkManager.cast_vote("harbor")
		if not await _wait(func() -> bool: return MatchManager.config.map_id == "harbor" and _match_running_with(2), 60.0):
			_fail("Nächste Runde auf Harbor nicht gestartet (Map %s, Zustand %d)" % [MatchManager.config.map_id, MatchManager.state])
		else:
			_log("Neue Runde auf der abgestimmten Map läuft")

	# 7) host leaves -> we notice and are sent back
	if not await _wait(func() -> bool: return int(_stats["disconnected"]) >= 1 or not NetworkManager.is_online(), 20.0):
		_fail("Verlassen des Hosts wurde nicht erkannt")
	else:
		_log("Host-Abschied erkannt")
	_finish()
