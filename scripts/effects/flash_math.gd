class_name FlashMath
extends RefCounted
## How badly a flashbang hits somebody: distance, where they look, and whether walls are in the way.
## Used for the local player (FlashOverlay) and for the bots (BotController).

const RADIUS := 24.0 # farther away nothing happens
const FULL_RADIUS := 6.0 # up to here the flash is at full strength (when looking at it)
const MIN_INTENSITY := 0.04
const MAX_BLIND := 1.8 # seconds of complete whiteout at full strength
const MAX_FADE := 3.7 # seconds of recovery after the whiteout at full strength (total ~5.5 s)


## 0..1. `eye`/`forward` = position and view direction of the victim, `center` = where the flashbang went off.
static func intensity(space: PhysicsDirectSpaceState3D, center: Vector3, eye: Vector3, forward: Vector3) -> float:
	var to := center - eye
	var dist := to.length()
	if dist > RADIUS:
		return 0.0
	var near := 1.0 - smoothstep(FULL_RADIUS, RADIUS, dist)
	var dir := to / maxf(dist, 0.001)
	# looking straight at it: full; sideways: about a third; with the back to it: a tenth (the light still fills the room)
	var look := lerpf(0.1, 1.0, smoothstep(-0.35, 0.6, forward.dot(dir)))
	var vis := visibility(space, center, eye)
	return clampf(near * look * vis, 0.0, 1.0)


## Share of the light that reaches the head (rays to the eye, above it and the chest; world geometry blocks).
## Behind a wall or in another room this is 0, around a corner it can be partial.
static func visibility(space: PhysicsDirectSpaceState3D, center: Vector3, eye: Vector3) -> float:
	var v := 0.0
	for probe in [[Vector3.ZERO, 0.6], [Vector3(0.0, 0.16, 0.0), 0.2], [Vector3(0.0, -0.4, 0.0), 0.2]]:
		var query := PhysicsRayQueryParameters3D.create(center, eye + (probe[0] as Vector3), 1)
		if space.intersect_ray(query).is_empty():
			v += float(probe[1])
	return v


## Seconds of complete whiteout.
static func blind_time(i: float) -> float:
	return MAX_BLIND * pow(clampf(i, 0.0, 1.0), 1.5)


## Seconds the sight and hearing need to recover after the whiteout.
static func fade_time(i: float) -> float:
	return 0.5 + (MAX_FADE - 0.5) * clampf(i, 0.0, 1.0)
