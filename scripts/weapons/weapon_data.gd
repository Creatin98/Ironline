class_name WeaponData
extends Resource
## Static definition of a hitscan weapon. Instances live in resources/weapons/*.tres.

enum Slot { PRIMARY, SECONDARY }

@export var weapon_id: String = "weapon"
@export var display_name: String = "Waffe"
@export var slot: Slot = Slot.PRIMARY
@export var model_scene: PackedScene

@export_group("Schaden")
@export var damage: float = 30.0
@export var min_damage: float = 20.0
@export var falloff_start: float = 20.0 # Meter, bis hier voller Schaden
@export var falloff_end: float = 45.0   # Meter, ab hier min_damage
@export var headshot_multiplier: float = 1.4
@export var pellets: int = 1
@export var max_range: float = 200.0

@export_group("Feuer")
@export var rpm: float = 600.0
@export var automatic: bool = true
@export var pump_action: bool = false
@export var pump_time: float = 0.65
@export var magazine_size: int = 30
@export var reserve_ammo: int = 90
@export var reload_time: float = 2.2
@export var reload_single_shells: bool = false # Shotgun: eine Patrone pro Zyklus
@export var shell_reload_time: float = 0.55
@export var draw_time: float = 0.4

@export_group("Streuung (Grad)")
@export var spread_hip: float = 2.2
@export var spread_ads: float = 0.25
@export var spread_moving_bonus: float = 1.5
@export var spread_per_shot: float = 0.35
@export var spread_max_bonus: float = 2.5
@export var spread_recovery: float = 6.0

@export_group("Rueckstoss")
@export var recoil_vertical: float = 1.2    # Grad pro Schuss
@export var recoil_horizontal: float = 0.5  # Grad, zufaellig links/rechts
@export var recoil_kick_back: float = 0.06  # Modellversatz (m)
@export var recoil_recovery: float = 9.0

@export_group("ADS")
@export var ads_fov: float = 60.0
@export var ads_time: float = 0.22
@export var ads_position: Vector3 = Vector3(0.0, -0.11, -0.28)
@export var hip_position: Vector3 = Vector3(0.24, -0.22, -0.46)
@export var move_speed_multiplier: float = 1.0
@export var ads_speed_multiplier: float = 0.65

@export_group("Audio")
@export var shot_sound: String = "shot_ak47"
@export var shot_sound_far: String = "shot_ak47_far"
@export var reload_sounds: Array[String] = ["reload_mag_out", "reload_mag_in"]
@export var shot_volume_db: float = 0.0

@export_group("Bots")
@export var bot_effective_range: float = 30.0
@export var bot_burst_shots: int = 4


func seconds_between_shots() -> float:
	return 60.0 / maxf(rpm, 1.0)


func damage_at_distance(distance: float) -> float:
	if distance <= falloff_start:
		return damage
	if distance >= falloff_end:
		return min_damage
	var t := (distance - falloff_start) / maxf(0.001, falloff_end - falloff_start)
	return lerpf(damage, min_damage, t)
