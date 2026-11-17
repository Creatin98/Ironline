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
var _failures: Array[String] = []
var _stats: Dictionary = {"hits": 0, "died": 0, "explosions": 0, "kills_seen": 0, "disconnected": 0}
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
	_started_msec = Time.get_ticks_msec()
	GameSettings.player_name = role
	GameSettings.preferred_team = Teams.Team.RED if role == "host" else Teams.Team.BLUE
	GameSettings.preferred_class_id = "assault"
	GameEvents.local_player_hit_enemy.connect(func(_hs: bool, _k: bool) -> void: _stats["hits"] += 1)
	GameEvents.local_player_died.connect(func(_k: int, _d: float) -> void: _stats["died"] += 1)
	GameEvents.explosion_at.connect(func(_p: Vector3, _r: float) -> void: _stats["explosions"] += 1)
	GameEvents.participant_killed.connect(func(_v: int, _k: int, _w: String, _h: bool) -> void: _stats["kills_seen"] += 1)
	NetworkManager.disconnected.connect(func(_r: String) -> void: _stats["disconnected"] += 1)
	if role == "host":
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
	_log("Kill gewertet, Client respawnt")
	await get_tree().create_timer(1.0).timeout

	# 5) grenade replication
	host_player.input.grenade_pressed = true
	if not await _wait(func() -> bool: return int(_stats["explosions"]) >= 1, 8.0):
		_fail("Granate des Hosts ist nicht explodiert")
	else:
		_log("Granate explodiert")
	await get_tree().create_timer(2.0).timeout
	_log("Host beendet die Lobby")
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

	# 4) server kills us -> death, score, respawn must arrive
	if not await _wait(func() -> bool: return int(_stats["died"]) >= 1, 20.0):
		_fail("Tod wurde nicht repliziert")
	elif me.deaths != 1 or host_participant.kills != 1:
		_fail("Spielstand nach dem Tod falsch (Tode %d, Host-Kills %d)" % [me.deaths, host_participant.kills])
	if not await _wait(func() -> bool: return _player_of(my_id) != null and _player_of(my_id).alive and me.alive, 10.0):
		_fail("Respawn wurde nicht repliziert")
	_log("Tod und Respawn repliziert")

	# 5) grenade explosion thrown by the host
	if not await _wait(func() -> bool: return int(_stats["explosions"]) >= 1, 15.0):
		_fail("Granatenexplosion nicht empfangen")
	else:
		_log("Granatenexplosion empfangen")

	# 6) host leaves -> we notice and are sent back
	if not await _wait(func() -> bool: return int(_stats["disconnected"]) >= 1 or not NetworkManager.is_online(), 20.0):
		_fail("Verlassen des Hosts wurde nicht erkannt")
	else:
		_log("Host-Abschied erkannt")
	_finish()
