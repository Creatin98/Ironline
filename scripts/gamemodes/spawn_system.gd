class_name SpawnSystem
extends RefCounted
## Picks spawn points: far from enemies, out of their sight, not recently used,
## not occupied. Works for TDM (team points) and FFA (all points).

const RECENT_USE_PENALTY_TIME := 4.0
const OCCUPIED_RADIUS := 1.6
const DANGER_RADIUS := 9.0

var points: Array[SpawnPoint] = []
var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree
	refresh()


## True if a standing player capsule at `pos` (feet position) would overlap solid world geometry.
static func is_blocked(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.95, 0.0))
	q.collision_mask = 1
	return not space.intersect_shape(q, 1).is_empty()


## A free position near `pos` (the point itself if free; otherwise the closest free spot on rings around it).
static func free_position_near(space: PhysicsDirectSpaceState3D, pos: Vector3) -> Vector3:
	if not is_blocked(space, pos):
		return pos
	for radius in [0.8, 1.4, 2.0, 3.0]:
		for i in 12:
			var a := TAU * float(i) / 12.0
			var cand: Vector3 = pos + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
			if not is_blocked(space, cand):
				return cand
	return pos


func refresh() -> void:
	points.clear()
	for n in _tree.get_nodes_in_group("spawn_points"):
		if n is SpawnPoint:
			points.append(n)


func pick_spawn(participant: Participant, use_teams: bool) -> Transform3D:
	if points.is_empty():
		push_warning("SpawnSystem: Keine Spawnpunkte auf der Map!")
		return Transform3D.IDENTITY
	var candidates: Array[SpawnPoint] = []
	for p in points:
		if not use_teams or p.team == Teams.Team.NONE or p.team == participant.team:
			candidates.append(p)
	if candidates.is_empty():
		candidates = points.duplicate()

	var enemies: Array[Vector3] = []
	var everyone: Array[Vector3] = []
	for other in MatchManager.participants.values():
		if other.node == null or not other.alive or other.id == participant.id:
			continue
		var pos: Vector3 = other.node.global_position
		everyone.append(pos)
		if participant.is_enemy_of(other):
			enemies.append(pos)

	var now := Time.get_ticks_msec() / 1000.0
	var space: PhysicsDirectSpaceState3D = null
	if not points.is_empty():
		space = points[0].get_world_3d().direct_space_state

	var best: SpawnPoint = null
	var best_score := -INF
	for p in candidates:
		var score := randf() * 2.0
		if space and is_blocked(space, p.global_position):
			score -= 500.0 # inside a wall / crate: only if nothing else is left
		var min_enemy := 999.0
		for e in enemies:
			min_enemy = minf(min_enemy, e.distance_to(p.global_position))
		score += minf(min_enemy, 40.0)
		if min_enemy < DANGER_RADIUS:
			score -= 30.0
		var occupied := false
		for o in everyone:
			if o.distance_to(p.global_position) < OCCUPIED_RADIUS:
				occupied = true
				break
		if occupied:
			score -= 100.0
		if now - p.last_used_time < RECENT_USE_PENALTY_TIME:
			score -= 12.0
		# line of sight from enemies (cheap: only nearest few)
		if space and not enemies.is_empty():
			var eye := p.global_position + Vector3(0, 1.6, 0)
			var visible_count := 0
			for e in enemies:
				if e.distance_to(p.global_position) > 35.0:
					continue
				var q := PhysicsRayQueryParameters3D.create(eye, e + Vector3(0, 1.5, 0), 1)
				if space.intersect_ray(q).is_empty():
					visible_count += 1
			score -= visible_count * 10.0
		if score > best_score:
			best_score = score
			best = p
	if best == null:
		best = candidates[0]
	best.last_used_time = now
	var t := best.global_transform
	if space:
		t.origin = free_position_near(space, t.origin)
	return t
