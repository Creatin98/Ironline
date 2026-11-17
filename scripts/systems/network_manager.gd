extends Node
## Autoload "NetworkManager": ENet host/client, lobby and every RPC of the game.
##
## Model: the host is the server and plays along ("listen server"). The server
## simulates every player (humans from replicated input, bots from the AI) and is
## the only place where hits, damage, kills, scores and respawns are decided.
## Clients predict their own movement and weapon handling for responsiveness,
## render remote players from interpolated snapshots and receive all gameplay
## results (kills, scores, health, spawns) from the server.
##
## Offline (`mode == OFFLINE`) every broadcast helper is a no-op, so the rest of
## the game never needs to know whether it is online.

enum Mode { OFFLINE, HOST, CLIENT }

const PROTOCOL_VERSION := 6
const DEFAULT_PORT := 7777
const MAX_PEERS := 12
const SNAPSHOT_EVERY_TICKS := 3 # 20 Hz at 60 physics ticks
const OWNER_STATE_EVERY_TICKS := 6 # 10 Hz
const LOAD_TIMEOUT := 12.0
const CONNECT_TIMEOUT := 8.0
const VOTE_TIME := 20.0 # fixed: 10 s scoreboard + 10 s final vote (with the class choice) in the middle of the screen

# held input bits (client -> server, every tick)
const HELD_SPRINT := 1
const HELD_CROUCH := 2
const HELD_AIM := 4
const HELD_FIRE := 8
const HELD_GRENADE := 16
# one-shot action bits (client -> server, reliable, only when pressed)
const ACT_FIRE := 1
const ACT_JUMP := 2
const ACT_RELOAD := 4
const ACT_GRENADE := 8
const ACT_SWITCH := 16
const ACT_PRIMARY := 32
const ACT_SECONDARY := 64
# snapshot flags (server -> clients)
const SNAP_CROUCH := 1
const SNAP_SPRINT := 2
const SNAP_AIM := 4
const SNAP_ON_FLOOR := 8
const SNAP_SLIDE := 16

signal lobby_updated
signal joined_lobby
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal all_peers_loaded
signal network_state_changed
signal vote_opened(maps: Array, duration: float)
signal vote_tally_changed(tally: Dictionary)
signal vote_closed(winner_map: String)

var mode: int = Mode.OFFLINE
## peer_id -> {"name": String, "team": int, "class_id": String}
var peers: Dictionary = {}
var lobby_config: MatchConfig = MatchConfig.new()
var in_match: bool = false
## Message for the main menu after an involuntary return (kick, host left, ...).
var pending_message: String = ""
## The active Game scene registers itself here.
var game: Node = null

var _loaded_peers: Dictionary = {}
var _waiting_for_load: bool = false
var _load_timer: float = 0.0
var _connect_timer: float = 0.0
var _connecting: bool = false
var _tick: int = 0
var _next_grenade_id: int = 1
var _grenades: Dictionary = {} # net id -> Grenade
## Vote length and the pause between the end of the vote and the start of the round (closing animation
## of the end screen); the tests shorten both.
var vote_time: float = VOTE_TIME
var vote_outcome_time: float = 2.8
var _outcome_pending: bool = false
var _vote_active: bool = false
var _vote_timer: float = 0.0
var _votes: Dictionary = {} # peer id -> map id


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ----------------------------------------------------------------------------- queries

func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func local_info() -> Dictionary:
	return {"name": GameSettings.player_name, "team": GameSettings.preferred_team, "class_id": GameSettings.preferred_class_id}


func human_count() -> int:
	return peers.size()


# ----------------------------------------------------------------------------- host / join / leave

func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		pending_message = ""
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	peers = {1: local_info()}
	lobby_config = MatchConfig.new()
	in_match = false
	network_state_changed.emit()
	lobby_updated.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	peers = {}
	_connecting = true
	_connect_timer = CONNECT_TIMEOUT
	network_state_changed.emit()
	return OK


## Leaves the lobby/match. The host closes the server, which drops every client.
func leave() -> void:
	if mode == Mode.OFFLINE:
		return
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_rpc_kicked.rpc("Der Host hat die Verbindung beendet.")
		# give the kick a moment on the wire before the socket closes
		multiplayer.multiplayer_peer.poll()
	_reset()


func _reset() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	peers = {}
	in_match = false
	_connecting = false
	_waiting_for_load = false
	_loaded_peers = {}
	_grenades = {}
	_vote_active = false
	_outcome_pending = false
	network_state_changed.emit()


func _process(delta: float) -> void:
	if _connecting:
		_connect_timer -= delta
		if _connect_timer <= 0.0:
			_connecting = false
			_reset()
			connection_failed.emit("Keine Antwort vom Host (Zeitüberschreitung).")
	if _vote_active and mode == Mode.HOST:
		_vote_timer -= delta
		if _vote_timer <= 0.0:
			_finish_vote()
	if _waiting_for_load:
		_load_timer -= delta
		if _load_timer <= 0.0 and game != null:
			_finish_load_wait()


func _physics_process(_delta: float) -> void:
	if mode != Mode.HOST or not in_match or game == null:
		return
	_tick += 1
	if _tick % SNAPSHOT_EVERY_TICKS == 0:
		_send_snapshot()
	if _tick % OWNER_STATE_EVERY_TICKS == 0:
		_send_owner_states()


# ----------------------------------------------------------------------------- connection signals

func _on_peer_connected(id: int) -> void:
	if mode != Mode.HOST:
		return
	if in_match:
		_rpc_kicked.rpc_id(id, "Das Match läuft bereits. Bitte warte auf die nächste Lobby.")
		_disconnect_peer_later(id)
		return
	if peers.size() >= lobby_config.max_participants():
		_rpc_kicked.rpc_id(id, "Die Lobby ist voll.")
		_disconnect_peer_later(id)
	# the client introduces itself with _rpc_register


func _on_peer_disconnected(id: int) -> void:
	if mode != Mode.HOST:
		return
	if not peers.has(id):
		return
	peers.erase(id)
	_loaded_peers.erase(id)
	if _vote_active:
		_votes.erase(id)
		_broadcast_tally()
	if in_match:
		var p := MatchManager.get_participant(id)
		if p != null and game != null and game.has_method("remove_player_node"):
			game.remove_player_node(id)
		MatchManager.remove_participant(id)
		_rpc_participant_left.rpc(id)
		if _waiting_for_load and _all_loaded():
			_finish_load_wait()
	else:
		_broadcast_lobby()
	lobby_updated.emit()


func _on_connected_to_server() -> void:
	_connecting = false
	_rpc_register.rpc_id(1, PROTOCOL_VERSION, local_info())


func _on_connection_failed() -> void:
	_connecting = false
	_reset()
	connection_failed.emit("Verbindung fehlgeschlagen. Adresse und Port prüfen.")


func _on_server_disconnected() -> void:
	var reason := pending_message if pending_message != "" else "Verbindung zum Host verloren."
	pending_message = reason
	var was_in_match := in_match
	_reset()
	disconnected.emit(reason)
	if was_in_match:
		GameDirector.return_to_main_menu(true)


func _disconnect_peer_later(id: int) -> void:
	# let the kick message leave the socket first
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if mode == Mode.HOST and multiplayer.multiplayer_peer != null:
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if enet and enet.get_peer(id) != null:
				enet.disconnect_peer(id))


# ----------------------------------------------------------------------------- lobby

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(version: int, info: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_rpc_kicked.rpc_id(id, "Spielversion passt nicht zum Host (Protokoll %d, Host %d)." % [version, PROTOCOL_VERSION])
		_disconnect_peer_later(id)
		return
	if in_match or peers.size() >= lobby_config.max_participants():
		return
	peers[id] = _sanitize_info(info, id)
	_broadcast_lobby()
	lobby_updated.emit()


func _sanitize_info(info: Dictionary, id: int) -> Dictionary:
	var name := String(info.get("name", "")).strip_edges().left(16)
	if name == "":
		name = "Spieler %d" % id
	var team := int(info.get("team", Teams.Team.NONE))
	if team != Teams.Team.RED and team != Teams.Team.BLUE:
		team = Teams.Team.NONE
	var class_id := String(info.get("class_id", "assault"))
	if not GameDirector.CLASSES.has(class_id):
		class_id = "assault"
	return {"name": name, "team": team, "class_id": class_id}


func _broadcast_lobby() -> void:
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_rpc_lobby_state.rpc(peers, lobby_config.to_dict())


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_state(new_peers: Dictionary, config: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	var first := peers.is_empty()
	peers = new_peers
	lobby_config.apply_dict(config)
	lobby_updated.emit()
	if first:
		joined_lobby.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
	pending_message = reason
	# the server closes the socket right after; server_disconnected handles the rest


## Host only: new lobby settings (mode, map, bots ...).
func host_set_config(cfg: MatchConfig) -> void:
	if mode != Mode.HOST:
		return
	lobby_config = cfg.duplicate_config()
	_broadcast_lobby()
	lobby_updated.emit()


## Everyone, also during a match: choose the class that is used from the next respawn on.
func request_class_change(class_id: String) -> void:
	if not GameDirector.CLASSES.has(class_id):
		return
	GameSettings.preferred_class_id = class_id
	GameSettings.save()
	MatchManager.config.local_class_id = class_id
	if mode == Mode.HOST:
		_apply_class_choice(1, class_id)
	elif mode == Mode.CLIENT:
		_rpc_class_choice.rpc_id(1, class_id)
	else:
		_apply_class_choice(MatchManager.local_participant_id, class_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_class_choice(class_id: String) -> void:
	if mode != Mode.HOST:
		return
	_apply_class_choice(multiplayer.get_remote_sender_id(), class_id)


func _apply_class_choice(id: int, class_id: String) -> void:
	if not GameDirector.CLASSES.has(class_id):
		return
	if peers.has(id):
		peers[id]["class_id"] = class_id
	var p := MatchManager.get_participant(id)
	if p != null and not p.is_bot:
		p.class_id = class_id


## Everyone: own team / class choice for the next match.
func set_local_loadout(team: int, class_id: String) -> void:
	GameSettings.preferred_team = team
	GameSettings.preferred_class_id = class_id
	if mode == Mode.HOST:
		peers[1] = _sanitize_info(local_info(), 1)
		_broadcast_lobby()
		lobby_updated.emit()
	elif mode == Mode.CLIENT:
		_rpc_update_loadout.rpc_id(1, local_info())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_update_loadout(info: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	peers[id] = _sanitize_info(info, id)
	_broadcast_lobby()
	lobby_updated.emit()


# ----------------------------------------------------------------------------- match start / load

## Host only: starts the match for everybody (also used for "next round").
func host_start_match(cfg: MatchConfig) -> void:
	if mode != Mode.HOST:
		return
	lobby_config = cfg.duplicate_config()
	_outcome_pending = false
	in_match = true
	multiplayer.multiplayer_peer.refuse_new_connections = true
	_loaded_peers = {}
	_waiting_for_load = true
	_load_timer = LOAD_TIMEOUT
	_grenades = {}
	if multiplayer.get_peers().size() > 0:
		_rpc_begin_match.rpc(lobby_config.to_dict())
	GameDirector.start_match(lobby_config)


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_match(config: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	in_match = true
	_grenades = {}
	var cfg := MatchConfig.new()
	cfg.apply_dict(config)
	lobby_config = cfg
	GameDirector.start_match(cfg)


## Called by the Game scene once it is ready (host and clients).
func notify_game_loaded(g: Node) -> void:
	game = g
	if mode == Mode.CLIENT:
		_rpc_client_loaded.rpc_id(1)
	elif mode == Mode.HOST:
		_loaded_peers[1] = true
		if _all_loaded():
			# nobody else connected (or everyone already loaded)
			call_deferred("_finish_load_wait")


func notify_game_unloaded(g: Node) -> void:
	if game == g:
		game = null


func _all_loaded() -> bool:
	for id in peers:
		if not _loaded_peers.has(id):
			return false
	return true


func _finish_load_wait() -> void:
	if not _waiting_for_load:
		return
	_waiting_for_load = false
	all_peers_loaded.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_loaded() -> void:
	if mode != Mode.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	_loaded_peers[id] = true
	if _waiting_for_load:
		if _all_loaded():
			_finish_load_wait()
	elif in_match and game != null:
		# late loader (the host did not wait for it): catch it up right now
		_rpc_full_state.rpc_id(id, MatchManager.to_dict())
		for p in MatchManager.participants.values():
			if p.alive and p.node != null and is_instance_valid(p.node):
				var pl := p.node as Player
				_rpc_spawn.rpc_id(id, p.id, pl.global_position, pl.rotation.y, p.class_id)


## Host: complete roster/score/timer state to everybody (right before the warmup).
func broadcast_full_state() -> void:
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_rpc_full_state.rpc(MatchManager.to_dict())


@rpc("authority", "call_remote", "reliable")
func _rpc_full_state(state: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	MatchManager.apply_full_state(state)


# ----------------------------------------------------------------------------- server -> clients: match flow

func broadcast_spawn(id: int, origin: Vector3, yaw: float, class_id: String) -> void:
	if mode == Mode.HOST and in_match and multiplayer.get_peers().size() > 0:
		_rpc_spawn.rpc(id, origin, yaw, class_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn(id: int, origin: Vector3, yaw: float, class_id: String) -> void:
	if mode != Mode.CLIENT or game == null:
		return
	game.remote_spawn(id, Transform3D(Basis(Vector3.UP, yaw), origin), class_id)


func broadcast_match_state(state: int, time_left: float, warmup_left: float) -> void:
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_rpc_match_state.rpc(state, time_left, warmup_left)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_state(state: int, time_left: float, warmup_left: float) -> void:
	if mode != Mode.CLIENT:
		return
	MatchManager.apply_remote_state(state, time_left, warmup_left)


func broadcast_time(time_left: float) -> void:
	if mode == Mode.HOST and in_match and multiplayer.get_peers().size() > 0:
		_rpc_time.rpc(time_left)


@rpc("authority", "call_remote", "reliable")
func _rpc_time(time_left: float) -> void:
	if mode != Mode.CLIENT:
		return
	MatchManager.apply_remote_time(time_left)


func broadcast_kill(victim_id: int, killer_id: int, weapon_id: String, headshot: bool, points: int, stats: Dictionary, assist_ids: Array = []) -> void:
	if mode == Mode.HOST and in_match and multiplayer.get_peers().size() > 0:
		_rpc_kill_event.rpc(victim_id, killer_id, weapon_id, headshot, points, stats, assist_ids)


@rpc("authority", "call_remote", "reliable")
func _rpc_kill_event(victim_id: int, killer_id: int, weapon_id: String, headshot: bool, points: int, stats: Dictionary, assist_ids: Array) -> void:
	if mode != Mode.CLIENT:
		return
	MatchManager.apply_remote_kill(victim_id, killer_id, weapon_id, headshot, points, stats, assist_ids)
	if game != null and game.has_method("remote_death"):
		game.remote_death(victim_id, killer_id, weapon_id, headshot)


func broadcast_match_end(winner: Dictionary, stats: Dictionary) -> void:
	if mode == Mode.HOST and in_match and multiplayer.get_peers().size() > 0:
		_rpc_match_ended.rpc(winner, stats)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_ended(winner: Dictionary, stats: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	MatchManager.apply_remote_end(winner, stats)


@rpc("authority", "call_remote", "reliable")
func _rpc_participant_left(id: int) -> void:
	if mode != Mode.CLIENT:
		return
	if game != null and game.has_method("remove_player_node"):
		game.remove_player_node(id)
	MatchManager.remove_participant(id)


## Host only: back to the lobby after a match (clients follow).
func host_return_to_lobby() -> void:
	if mode != Mode.HOST:
		return
	in_match = false
	_outcome_pending = false
	_waiting_for_load = false
	multiplayer.multiplayer_peer.refuse_new_connections = false
	if multiplayer.get_peers().size() > 0:
		_rpc_return_to_lobby.rpc()
	GameDirector.return_to_main_menu(true)


@rpc("authority", "call_remote", "reliable")
func _rpc_return_to_lobby() -> void:
	if mode != Mode.CLIENT:
		return
	in_match = false
	GameDirector.return_to_main_menu(true)


# ----------------------------------------------------------------------------- client -> server: input

var _input_seq: int = 0


## Client: sends the local player's input for this physics tick.
func send_input(move: Vector2, yaw: float, pitch: float, held: int, actions: int) -> int:
	if mode != Mode.CLIENT or not in_match:
		return 0
	_input_seq += 1
	_rpc_input.rpc_id(1, _input_seq, move, yaw, pitch, held)
	if actions != 0:
		_rpc_input_action.rpc_id(1, actions)
	return _input_seq


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(seq: int, move: Vector2, yaw: float, pitch: float, held: int) -> void:
	if mode != Mode.HOST:
		return
	var player := _player_of(multiplayer.get_remote_sender_id())
	if player == null:
		return
	player.set_remote_input(seq, move, yaw, pitch, held)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_input_action(actions: int) -> void:
	if mode != Mode.HOST:
		return
	var player := _player_of(multiplayer.get_remote_sender_id())
	if player == null:
		return
	player.add_remote_actions(actions)


func _player_of(id: int) -> Player:
	var p := MatchManager.get_participant(id)
	if p == null or p.node == null or not is_instance_valid(p.node):
		return null
	return p.node as Player


# ----------------------------------------------------------------------------- server -> clients: world state

func _send_snapshot() -> void:
	var data: Array = []
	for p in MatchManager.participants.values():
		if p.node == null or not is_instance_valid(p.node) or not p.alive:
			continue
		var pl := p.node as Player
		var flags := 0
		if pl.is_crouching:
			flags |= SNAP_CROUCH
		if pl.is_sprinting:
			flags |= SNAP_SPRINT
		if pl.is_aiming:
			flags |= SNAP_AIM
		if pl.is_on_floor():
			flags |= SNAP_ON_FLOOR
		if pl.is_sliding:
			flags |= SNAP_SLIDE
		data.append([p.id, pl.global_position, pl.rotation.y, pl.head.pitch, pl.velocity, flags, pl.weapon_manager.current_index, pl.remote_input_seq])
	if not data.is_empty() and multiplayer.get_peers().size() > 0:
		_rpc_snapshot.rpc(data)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(data: Array) -> void:
	if mode != Mode.CLIENT:
		return
	var my_id := local_peer_id()
	for entry in data:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 8:
			continue
		var id: int = entry[0]
		var p := MatchManager.get_participant(id)
		if p == null or p.node == null or not is_instance_valid(p.node):
			continue
		var pl := p.node as Player
		if id == my_id:
			pl.reconcile_with_server(int(entry[7]), entry[1], entry[4])
		else:
			pl.push_snapshot(entry[1], float(entry[2]), float(entry[3]), entry[4], int(entry[5]), int(entry[6]))


func _send_owner_states() -> void:
	for id in peers:
		if id == 1:
			continue
		var pl := _player_of(id)
		if pl == null or not pl.alive:
			continue
		var w := pl.weapon_manager.get_current_weapon()
		var mag := w.magazine if w else 0
		var reserve := w.reserve if w else 0
		_rpc_owner_state.rpc_id(id, pl.health.health, mag, reserve, pl.weapon_manager.grenades, pl.weapon_manager.current_index)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_owner_state(health: float, magazine: int, reserve: int, grenades: int, weapon_index: int) -> void:
	if mode != Mode.CLIENT:
		return
	var pl := _player_of(local_peer_id())
	if pl == null:
		return
	pl.apply_owner_state(health, magazine, reserve, grenades, weapon_index)


## Server: a remote human took damage -> feedback on its machine.
func send_damage_feedback(victim_id: int, amount: float, source_position: Vector3, health: float) -> void:
	if mode == Mode.HOST and victim_id != 1 and peers.has(victim_id):
		_rpc_damaged.rpc_id(victim_id, amount, source_position, health)


@rpc("authority", "call_remote", "reliable")
func _rpc_damaged(amount: float, source_position: Vector3, health: float) -> void:
	if mode != Mode.CLIENT:
		return
	var pl := _player_of(local_peer_id())
	if pl == null:
		return
	pl.remote_damage_feedback(amount, source_position, health)


## Server: a remote human hit an enemy -> hitmarker on its machine.
func send_hit_feedback(shooter_id: int, headshot: bool, killed: bool) -> void:
	if mode == Mode.HOST and shooter_id != 1 and peers.has(shooter_id):
		_rpc_hit_feedback.rpc_id(shooter_id, headshot, killed)


@rpc("authority", "call_remote", "reliable")
func _rpc_hit_feedback(headshot: bool, killed: bool) -> void:
	if mode != Mode.CLIENT:
		return
	GameEvents.local_player_hit_enemy.emit(headshot, killed)


## Server: a shot happened -> everyone except the shooter (who predicted it) sees it.
func broadcast_shot(shooter_id: int, impacts: Array) -> void:
	if mode != Mode.HOST or not in_match:
		return
	for id in multiplayer.get_peers():
		if id != shooter_id:
			_rpc_shot.rpc_id(id, shooter_id, impacts)


@rpc("authority", "call_remote", "reliable")
func _rpc_shot(shooter_id: int, impacts: Array) -> void:
	if mode != Mode.CLIENT:
		return
	var pl := _player_of(shooter_id)
	if pl == null:
		return
	pl.weapon_manager.play_remote_shot(impacts)


## Server: reload / switch / grenade pin of a player -> sound on the other machines.
func broadcast_weapon_event(owner_id: int, event: String) -> void:
	if mode != Mode.HOST or not in_match:
		return
	for id in multiplayer.get_peers():
		if id != owner_id:
			_rpc_weapon_event.rpc_id(id, owner_id, event)


@rpc("authority", "call_remote", "reliable")
func _rpc_weapon_event(owner_id: int, event: String) -> void:
	if mode != Mode.CLIENT:
		return
	var pl := _player_of(owner_id)
	if pl == null:
		return
	pl.weapon_manager.play_remote_event(event)


# ----------------------------------------------------------------------------- grenades

## Server: registers the authoritative grenade and mirrors it to the clients.
func register_grenade(grenade: Node, thrower_id: int, team: int, origin: Vector3, velocity: Vector3) -> void:
	if mode != Mode.HOST:
		return
	var gid := _next_grenade_id
	_next_grenade_id += 1
	grenade.net_id = gid
	_grenades[gid] = grenade
	if multiplayer.get_peers().size() > 0:
		_rpc_grenade_spawn.rpc(gid, thrower_id, team, origin, velocity)


@rpc("authority", "call_remote", "reliable")
func _rpc_grenade_spawn(gid: int, thrower_id: int, team: int, origin: Vector3, velocity: Vector3) -> void:
	if mode != Mode.CLIENT or game == null:
		return
	var grenade: Node = game.spawn_visual_grenade(thrower_id, team, origin, velocity)
	# the spoon flies off at the moment of the throw (the time of the release is known only now, the hold may last)
	if thrower_id != MatchManager.local_participant_id:
		AudioManager.play_3d("grenade_lever", origin, -10.0, 0.04, 25.0)
	if grenade != null:
		grenade.net_id = gid
		_grenades[gid] = grenade


func broadcast_grenade_explosion(gid: int, center: Vector3) -> void:
	_grenades.erase(gid)
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_rpc_grenade_explode.rpc(gid, center)


@rpc("authority", "call_remote", "reliable")
func _rpc_grenade_explode(gid: int, center: Vector3) -> void:
	if mode != Mode.CLIENT:
		return
	var grenade = _grenades.get(gid)
	_grenades.erase(gid)
	if grenade != null and is_instance_valid(grenade):
		grenade.explode_visual_at(center)
	elif game != null:
		game.play_explosion_at(center)


# ----------------------------------------------------------------------------- respawn skip

## Everyone: skip the rest of the killcam wait (the server checks the minimum time).
func request_skip_respawn() -> void:
	if mode == Mode.CLIENT:
		_rpc_skip_respawn.rpc_id(1)
	elif game != null and game.has_method("skip_respawn"):
		game.skip_respawn(MatchManager.local_participant_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_skip_respawn() -> void:
	if mode != Mode.HOST or game == null or not game.has_method("skip_respawn"):
		return
	game.skip_respawn(multiplayer.get_remote_sender_id())


# ----------------------------------------------------------------------------- map voting

## Host: opens the vote for the next map (called when a match has ended).
func host_open_vote(maps: Array) -> void:
	if mode != Mode.HOST or _vote_active:
		return
	_vote_active = true
	_vote_timer = vote_time
	_votes = {}
	if multiplayer.get_peers().size() > 0:
		_rpc_vote_open.rpc(maps, vote_time)
	vote_opened.emit(maps, vote_time)
	vote_tally_changed.emit(_tally())


@rpc("authority", "call_remote", "reliable")
func _rpc_vote_open(maps: Array, duration: float) -> void:
	if mode != Mode.CLIENT:
		return
	vote_opened.emit(maps, duration)
	vote_tally_changed.emit({})


## Everyone: cast (or change) the own vote.
func cast_vote(map_id: String) -> void:
	if mode == Mode.HOST:
		_register_vote(1, map_id)
	elif mode == Mode.CLIENT:
		_rpc_cast_vote.rpc_id(1, map_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cast_vote(map_id: String) -> void:
	if mode != Mode.HOST:
		return
	_register_vote(multiplayer.get_remote_sender_id(), map_id)


func _register_vote(id: int, map_id: String) -> void:
	if not _vote_active or not peers.has(id) or not GameDirector.ROTATION_MAPS.has(map_id):
		return
	_votes[id] = map_id
	_broadcast_tally()
	# no early end: the vote always runs its full time (the end screen follows a fixed sequence)


func _tally() -> Dictionary:
	var out: Dictionary = {}
	for id in _votes:
		var m: String = _votes[id]
		out[m] = int(out.get(m, 0)) + 1
	return out


func _broadcast_tally() -> void:
	vote_tally_changed.emit(_tally())
	if multiplayer.get_peers().size() > 0:
		_rpc_vote_tally.rpc(_tally())


@rpc("authority", "call_remote", "reliable")
func _rpc_vote_tally(tally: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	vote_tally_changed.emit(tally)


## Host: picks the winner (ties and no votes are decided randomly), tells everybody (closing animation of
## the end screen) and starts the next round `vote_outcome_time` later.
func _finish_vote() -> void:
	if not _vote_active:
		return
	_vote_active = false
	var tally := _tally()
	var best := 0
	for m in tally:
		best = maxi(best, int(tally[m]))
	var winners: Array = []
	for m in GameDirector.ROTATION_MAPS:
		if best > 0 and int(tally.get(m, 0)) == best:
			winners.append(m)
	if winners.is_empty():
		winners = GameDirector.ROTATION_MAPS.duplicate()
	var cfg := MatchManager.config.duplicate_config()
	cfg.map_id = winners[randi() % winners.size()]
	_outcome_pending = true
	if multiplayer.get_peers().size() > 0:
		_rpc_vote_close.rpc(cfg.map_id)
	vote_closed.emit(cfg.map_id)
	await get_tree().create_timer(vote_outcome_time).timeout
	if not _outcome_pending or mode != Mode.HOST:
		return # the host went back to the lobby / left in the meantime
	_outcome_pending = false
	host_start_match(cfg)


@rpc("authority", "call_remote", "reliable")
func _rpc_vote_close(winner_map: String) -> void:
	if mode != Mode.CLIENT:
		return
	vote_closed.emit(winner_map)
