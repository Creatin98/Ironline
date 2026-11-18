class_name CasingBody
extends RigidBody3D
## A brass casing: rings once on its first hit and removes itself after a few seconds (no lambdas that could outlive it).

var _age: float = 0.0
var _rang: bool = false


func _ready() -> void:
	body_entered.connect(_on_hit)


func _on_hit(_b: Node) -> void:
	if not _rang:
		_rang = true
		AudioManager.play_3d("casing_drop", global_position, -14.0, 0.2, 18.0)


func _process(delta: float) -> void:
	_age += delta
	if _age > 5.0:
		queue_free()
