class_name Health
extends Node
## Health with Call-of-Duty style regeneration after a few seconds without damage.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, attacker_id: int)
signal died(attacker_id: int, weapon_id: String, headshot: bool)

@export var max_health: float = 200.0
@export var regen_delay: float = 4.0
@export var regen_rate: float = 90.0

var health: float = 200.0
var alive: bool = true
var _time_since_damage: float = 999.0
var last_attacker_id: int = 0
var last_weapon_id: String = ""


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
	health_changed.emit(health, max_health)


## Returns true if this damage killed the owner.
func apply_damage(amount: float, attacker_id: int, weapon_id: String, headshot: bool) -> bool:
	if not alive or amount <= 0.0:
		return false
	health -= amount
	_time_since_damage = 0.0
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


func kill(attacker_id: int = 0, weapon_id: String = "world") -> void:
	if not alive:
		return
	apply_damage(health + 1.0, attacker_id, weapon_id, false)


func ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0)
