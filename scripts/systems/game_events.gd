extends Node
## Autoload "GameEvents": global signal bus. Systems talk through these signals
## instead of holding references to each other.

# Match flow
signal match_started
signal match_state_changed(state: int)
signal match_ended(winner_team: int, winner_participant_id: int)
signal scores_changed
signal time_changed(seconds_left: float)

# Participants
signal participant_added(id: int)
signal participant_removed(id: int)
signal participant_spawned(id: int)
signal participant_killed(victim_id: int, killer_id: int, weapon_id: String, headshot: bool)

# Local player feedback (only emitted for the player at this machine)
signal local_player_spawned(player: Node)
signal local_player_died(killer_id: int, respawn_delay: float)
signal local_player_damaged(amount: float, source_position: Vector3)
signal local_player_hit_enemy(headshot: bool, killed: bool)
signal local_player_scored(points: int, reason: String)
signal local_weapon_changed(weapon: Node)
signal local_ammo_changed(magazine: int, reserve: int)
signal local_grenades_changed(count: int)
signal local_health_changed(health: float, max_health: float)
signal local_camera_shake(strength: float)

# World
signal explosion_at(position: Vector3, radius: float)
signal shot_fired(shooter_id: int, position: Vector3)
