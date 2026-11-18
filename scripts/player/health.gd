class_name Health
extends Node
## Health with Call-of-Duty style regeneration after a few seconds without damage.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, attacker_id: int)
signal died(attacker_id: int, weapon_id: String, headshot: bool)

@export var max_health: float = 250.0
@export var regen_delay: float = 4.0
@export var regen_rate: float = 112.0

var health: float = 250.0
var alive: bool = true
var _time_since_damage: float = 999.0
var last_attacker_id: int = 0
var last_weapon_id: String = ""

## Damage per attacker for assists: [attacker_id, time_msec, amount]
const ASSIST_WINDOW_MSEC := 8000
const ASSIST_MIN_DAMAGE := 30.0
var _damage_log: Array = []


func _ready() -> void:
	health = max_health


func _process(delta: float) -> void:
	if not alive:
		return
	_time_since_damage += delta
	if health < max_health and _time_since_damage >= regen_delay:
		health = minf(max_health, health + regen_rate * delta)
		health_changed.emit(health, max_health)


func reset() -> void:
	health = max_health
	alive = true
	_time_since_damage = 999.0
	last_attacker_id = 0
	last_weapon_id = ""
	_damage_log.clear()
	health_changed.emit(health, max_health)


## Returns true if this damage killed the owner.
func apply_damage(amount: float, attacker_id: int, weapon_id: String, headshot: bool) -> bool:
	if not alive or amount <= 0.0:
		return false
	health -= amount
	_time_since_damage = 0.0
	if attacker_id != 0:
		_damage_log.append([attacker_id, Time.get_ticks_msec(), amount])
	last_attacker_id = attacker_id
	last_weapon_id = weapon_id
	damaged.emit(amount, attacker_id)
	health_changed.emit(maxf(0.0, health), max_health)
	if health <= 0.0:
		health = 0.0
		alive = false
		died.emit(attacker_id, weapon_id, headshot)
		return true
	return false


func kill(attacker_id: int = 0, weapon_id: String = "world", headshot: bool = false) -> void:
	if not alive:
		return
	apply_damage(health + 1.0, attacker_id, weapon_id, headshot)


## Client side: adopt the server's health value (no death handling here).
func set_remote_health(value: float) -> void:
	if not alive:
		return
	var clamped := clampf(value, 0.0, max_health)
	if absf(clamped - health) < 0.01:
		return
	if clamped < health:
		_time_since_damage = 0.0
	health = clamped
	health_changed.emit(health, max_health)


## Ids of everybody who did at least ASSIST_MIN_DAMAGE within the window, except `killer_id`.
func get_assisters(killer_id: int) -> Array:
	var now := Time.get_ticks_msec()
	var totals: Dictionary = {}
	for entry in _damage_log:
		if now - int(entry[1]) > ASSIST_WINDOW_MSEC:
			continue
		totals[int(entry[0])] = float(totals.get(int(entry[0]), 0.0)) + float(entry[2])
	var out: Array = []
	for id in totals:
		if id != killer_id and float(totals[id]) >= ASSIST_MIN_DAMAGE:
			out.append(id)
	return out


func ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0)
