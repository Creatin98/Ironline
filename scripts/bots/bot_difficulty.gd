class_name BotDifficulty
extends RefCounted
## Tunable parameters per difficulty level (Einfach / Normal / Schwer).

var reaction_time: float = 0.45     # seconds between spotting and first shot
var aim_error_deg: float = 3.8      # random aim cone added to the real spread
var turn_speed: float = 6.0         # rad/s maximum turning speed
var view_range: float = 45.0        # metres
var fov_deg: float = 120.0          # field of view for spotting
var hearing_range: float = 30.0     # metres for reacting to gunfire
var burst_pause: float = 0.5        # pause between bursts
var grenade_chance: float = 0.08    # probability per second while an enemy is in throw range
var retreat_health: float = 0.3     # retreat to cover below this health ratio
var strafe_chance: float = 0.6      # probability to strafe instead of standing still in a fight
var headshot_bias: float = 0.0      # 0 = aim at chest, 1 = always aim at head
var memory_time: float = 4.0        # seconds a lost target is still chased


static func preset(level: int) -> BotDifficulty:
	var d := BotDifficulty.new()
	match level:
		MatchConfig.DIFFICULTY_EASY:
			d.reaction_time = 0.85
			d.aim_error_deg = 7.5
			d.turn_speed = 3.5
			d.view_range = 32.0
			d.fov_deg = 100.0
			d.hearing_range = 20.0
			d.burst_pause = 0.8
			d.grenade_chance = 0.03
			d.retreat_health = 0.2
			d.strafe_chance = 0.3
			d.headshot_bias = 0.0
			d.memory_time = 3.0
		MatchConfig.DIFFICULTY_HARD:
			d.reaction_time = 0.25
			d.aim_error_deg = 2.2
			d.turn_speed = 10.0
			d.view_range = 50.0
			d.fov_deg = 140.0
			d.hearing_range = 40.0
			d.burst_pause = 0.35
			d.grenade_chance = 0.12
			d.retreat_health = 0.35
			d.strafe_chance = 0.85
			d.headshot_bias = 0.4
			d.memory_time = 5.0
		_:
			pass
	return d
