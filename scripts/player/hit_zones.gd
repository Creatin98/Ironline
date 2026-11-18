class_name HitZones
extends RefCounted
## Body zones tailored to the figure (HumanoidRig): head, chest, belly (torso + pelvis), upper arm, forearm, thigh, shin
## (the last four with a side: 0 = right, 1 = left). The zones are measured on the model in a standing pose and scaled with
## the current height (crouch). Result: {"zone": String, "side": int, "seg": int} where seg is the ragdoll segment index
## (head 2, thighs 3/7, shins 4/8, upper arms 5/9, forearms 6/10; -1 for torso zones).

const STAND := 1.8
const KNEE := 0.50         # knee height of the standing figure
const HIP := 0.92          # pelvis joint
const CHEST := 1.22        # above this the torso counts as chest
const SHOULDER := 1.42     # top of the shoulders
const ELBOW := 1.12        # elbow height of the arms held forward
const ARM_X := 0.17        # |x| beyond this (and between the hands' and shoulders' heights) is an arm
const HEAD_Y := 1.44       # head and neck above this


## `local`: hit point relative to the feet, rotated into the figure's frame (x = right, y = up, -z = forward).
static func classify(local: Vector3, height: float) -> Dictionary:
	var r := STAND / maxf(height, 0.5)
	var x := local.x
	var y := local.y * r
	var side := 0 if x >= 0.0 else 1
	if y >= HEAD_Y:
		return {"zone": "head", "side": side, "seg": 2}
	if y < HIP - 0.04:
		if y >= KNEE:
			return {"zone": "thigh", "side": side, "seg": 3 + 4 * side}
		return {"zone": "shin", "side": side, "seg": 4 + 4 * side}
	if absf(x) > ARM_X and y >= 0.78 and y < SHOULDER + 0.06:
		if y >= ELBOW:
			return {"zone": "upper_arm", "side": side, "seg": 5 + 4 * side}
		return {"zone": "forearm", "side": side, "seg": 6 + 4 * side}
	if y >= CHEST:
		return {"zone": "chest", "side": side, "seg": -1}
	return {"zone": "belly", "side": side, "seg": -1}


static func is_limb(zone: String) -> bool:
	return zone in ["upper_arm", "forearm", "thigh", "shin"]
