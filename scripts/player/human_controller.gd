class_name HumanController
extends Node
## Reads keyboard and mouse and writes into the parent Player's input state.
## Only active for the locally controlled player. Mouse look is applied
## immediately (per event) for minimal latency; everything else per physics tick.
## As an online client the same input is also sent to the server every tick.

const BASE_SENSITIVITY := 0.0022

var player: Player
var enabled: bool = false
## Tests drive the input state themselves; the controller then only forwards it.
var scripted: bool = false

var _pending_actions: int = 0


func _ready() -> void:
	player = get_parent() as Player
	# run before the Player consumes the input state in the same physics tick
	process_physics_priority = -10
	set_process_unhandled_input(true)


func activate() -> void:
	enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func deactivate() -> void:
	enabled = false
	if player:
		player.input.clear_all()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or player == null or not player.controls_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var sens := BASE_SENSITIVITY * GameSettings.mouse_sensitivity
		var d := motion.relative * sens * player.get_ads_sensitivity_scale()
		if GameSettings.invert_y:
			d.y = -d.y
		player.apply_look(d)
		return
	if event.is_action_pressed("fire"):
		player.input.fire_pressed = true
		_pending_actions |= NetworkManager.ACT_FIRE
	elif event.is_action_pressed("jump"):
		player.input.jump_pressed = true
		_pending_actions |= NetworkManager.ACT_JUMP
	elif event.is_action_pressed("reload"):
		player.input.reload_pressed = true
		_pending_actions |= NetworkManager.ACT_RELOAD
	elif event.is_action_pressed("grenade"):
		player.input.grenade_pressed = true
		_pending_actions |= NetworkManager.ACT_GRENADE
	elif event.is_action_pressed("switch_weapon"):
		player.input.switch_pressed = true
		_pending_actions |= NetworkManager.ACT_SWITCH
	elif event.is_action_pressed("weapon_primary"):
		player.input.select_primary = true
		_pending_actions |= NetworkManager.ACT_PRIMARY
	elif event.is_action_pressed("weapon_secondary"):
		player.input.select_secondary = true
		_pending_actions |= NetworkManager.ACT_SECONDARY


func _physics_process(_delta: float) -> void:
	if not enabled or player == null:
		return
	if scripted:
		send_to_server()
		return
	var inp := player.input
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.controls_enabled:
		inp.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		inp.sprint = Input.is_action_pressed("sprint")
		inp.crouch = Input.is_action_pressed("crouch")
		inp.aim = Input.is_action_pressed("aim")
		inp.fire_held = Input.is_action_pressed("fire")
	else:
		inp.clear_all()
		_pending_actions = 0
	send_to_server()


## Online client: mirrors the current input state to the server. Also used by
## tests that drive the input state directly.
func send_to_server() -> void:
	if not NetworkManager.is_client() or not player.alive:
		_pending_actions = 0
		return
	var inp := player.input
	var held := 0
	if inp.sprint:
		held |= NetworkManager.HELD_SPRINT
	if inp.crouch:
		held |= NetworkManager.HELD_CROUCH
	if inp.aim:
		held |= NetworkManager.HELD_AIM
	if inp.fire_held:
		held |= NetworkManager.HELD_FIRE
	var actions := _pending_actions
	if inp.fire_pressed:
		actions |= NetworkManager.ACT_FIRE
	if inp.jump_pressed:
		actions |= NetworkManager.ACT_JUMP
	if inp.reload_pressed:
		actions |= NetworkManager.ACT_RELOAD
	if inp.grenade_pressed:
		actions |= NetworkManager.ACT_GRENADE
	if inp.switch_pressed:
		actions |= NetworkManager.ACT_SWITCH
	if inp.select_primary:
		actions |= NetworkManager.ACT_PRIMARY
	if inp.select_secondary:
		actions |= NetworkManager.ACT_SECONDARY
	_pending_actions = 0
	var seq := NetworkManager.send_input(inp.move, player.rotation.y, player.head.pitch, held, actions)
	player.pending_input_seq = seq
