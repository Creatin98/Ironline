class_name GlassField
extends Node3D
## All breakable windows of a map. The HOST decides (shots, explosions) and tells everybody with small events; the
## other machines only draw the result. Intact glass sits on physics layer 32: players cannot walk through it, bullets
## and the bots' line of sight ignore it (a shot passes through and damages the pane on its way, like it used to
## pass through the open window). Broken panes have no collision at all.

const LAYER := 32
const BLAST_REACH := 1.1 # glass reacts up to 1.1x the explosion radius (damage falls off steeply)
const BLAST_STRENGTH := 320.0
const MAX_PANE_DAMAGE := 120.0 # one pellet / bullet never counts for more (the sniper still breaks a pane at once)

var windows: Array[GlassWindow] = []


func _ready() -> void:
	add_to_group("glass_field")


func setup(defs: Array) -> void:
	for i in defs.size():
		var w := GlassWindow.new()
		w.name = "Window%d" % i
		add_child(w)
		w.setup(i, defs[i])
		windows.append(w)


static func find(tree: SceneTree) -> GlassField:
	return tree.get_first_node_in_group("glass_field") as GlassField


func pane_by_id(id: int) -> GlassWindow:
	return windows[id] if id >= 0 and id < windows.size() else null


# ----------------------------------------------------------------------------- host: decisions

## Host: a bullet flew from `from` to `to`; every pane on the way takes damage. Called by Weapon for every pellet.
static func on_shot(tree: SceneTree, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, damage: float) -> void:
	if not MatchManager.is_authority():
		return
	var field := find(tree)
	if field != null and not field.windows.is_empty():
		field.shot(space, from, to, damage)


func shot(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, damage: float) -> void:
	if from.distance_to(to) < 0.01:
		return
	var dir := (to - from).normalized()
	var exclude: Array[RID] = []
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER)
		q.exclude = exclude
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		exclude.append(r["rid"])
		var body := r["collider"] as Node
		var win: GlassWindow = null
		if body != null:
			win = body.get_meta("glass", null) as GlassWindow
		if win == null or win.broken:
			continue
		var amount := minf(damage, MAX_PANE_DAMAGE)
		var point: Vector3 = r["position"]
		if win.damage_by(amount, point, dir):
			var power := clampf(amount / 70.0, 0.4, 1.5)
			win.break_glass(point, dir, power)
			NetworkManager.broadcast_glass(1, win.id, point, dir, power)
		else:
			NetworkManager.broadcast_glass(0, win.id, point, dir, win.damage_fraction())


## Host: a thrown grenade flew from `from` to `to`; every intact pane on the way is smashed completely (like in the
## big shooters, a grenade cannot be thrown through whole glass) and the grenade flies on through the opening.
static func on_grenade_move(tree: SceneTree, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> void:
	if not MatchManager.is_authority() or from.distance_to(to) < 0.01:
		return
	var field := find(tree)
	if field == null or field.windows.is_empty():
		return
	var dir := (to - from).normalized()
	var exclude: Array[RID] = []
	for i in 3:
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER)
		q.exclude = exclude
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		exclude.append(r["rid"])
		var body := r["collider"] as Node
		var win: GlassWindow = body.get_meta("glass", null) as GlassWindow if body != null else null
		if win == null or win.broken:
			continue
		var point: Vector3 = r["position"]
		win.health = 0.0
		win.break_glass(point, dir, 0.8)
		NetworkManager.broadcast_glass(1, win.id, point, dir, 0.8)


## Host: an explosion at `center` (radius = its damage radius). Panes close by break, farther ones crack, the rest is untouched.
static func on_explosion(tree: SceneTree, space: PhysicsDirectSpaceState3D, center: Vector3, radius: float) -> void:
	if not MatchManager.is_authority():
		return
	var field := find(tree)
	if field != null and not field.windows.is_empty():
		field.blast(space, center, radius)


func blast(space: PhysicsDirectSpaceState3D, center: Vector3, radius: float) -> void:
	var reach := radius * BLAST_REACH
	var ids := PackedInt32Array()
	var fracs := PackedFloat32Array()
	for w in windows:
		if w.broken:
			continue
		var wc := w.global_position
		var d := center.distance_to(wc)
		if d > reach:
			continue
		var occ := 1.0
		var q := PhysicsRayQueryParameters3D.create(center, wc, 1)
		var r := space.intersect_ray(q)
		if not r.is_empty() and center.distance_to(r["position"]) < d - 0.5:
			occ = 0.3 # walls in between take most of the pressure
		var power := pow(1.0 - d / reach, 1.2) * occ * BLAST_STRENGTH
		if power < 4.0:
			continue
		var away := (wc - center).normalized()
		var point := _project_on_pane(w, center)
		ids.append(w.id)
		if w.damage_by(power, point, away):
			var strength := clampf(power / 90.0, 0.5, 1.6)
			w.break_glass(point, away, strength)
			fracs.append(1.0 + strength)
		else:
			fracs.append(w.damage_fraction())
	if not ids.is_empty():
		NetworkManager.broadcast_glass_blast(center, ids, fracs)


static func _project_on_pane(w: GlassWindow, center: Vector3) -> Vector3:
	var local := w.to_local(center)
	local.z = 0.0
	local.x = clampf(local.x, -w.pane_size.x * 0.4, w.pane_size.x * 0.4)
	local.y = clampf(local.y, -w.pane_size.y * 0.4, w.pane_size.y * 0.4)
	return w.to_global(local)


# ----------------------------------------------------------------------------- clients: events from the host

## kind 0 = hit (a = point, b = direction, f = damage fraction), 1 = break (f = power)
func net_event(kind: int, id: int, a: Vector3, b: Vector3, f: float) -> void:
	var w := pane_by_id(id)
	if w == null:
		return
	if kind == 0:
		w.apply_hit(a, b, f)
	else:
		w.break_glass(a, b, f)


## Panes hit by a pressure wave: fracs >= 1 = broken (value - 1 = power), else the damage fraction.
func net_blast(center: Vector3, ids: PackedInt32Array, fracs: PackedFloat32Array) -> void:
	for i in ids.size():
		var w := pane_by_id(ids[i])
		if w == null or w.broken:
			continue
		var away := (w.global_position - center).normalized()
		var point := _project_on_pane(w, center)
		var delay := center.distance_to(w.global_position) * 0.012 # the wave takes a moment to arrive
		var f: float = fracs[i]
		if f >= 1.0:
			_later(delay, func() -> void: w.break_glass(point, away, f - 1.0))
		else:
			_later(delay, func() -> void: w.apply_hit(point, away, f))


func _later(delay: float, fn: Callable) -> void:
	if delay <= 0.02:
		fn.call()
	else:
		get_tree().create_timer(delay).timeout.connect(fn)


func export_state() -> Array:
	var out: Array = []
	for w in windows:
		out.append(w.export_state() if (w.broken or not w.hits.is_empty()) else [])
	return out


func import_state(state: Array) -> void:
	for i in mini(state.size(), windows.size()):
		if not (state[i] as Array).is_empty():
			windows[i].import_state(state[i])
