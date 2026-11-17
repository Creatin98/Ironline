class_name SpawnPoint
extends Marker3D
## A spawn location. team 0 = usable by everyone, 1 = Rot, 2 = Blau.

@export var team: int = Teams.Team.NONE

var last_used_time: float = -100.0


func _ready() -> void:
	add_to_group("spawn_points")
