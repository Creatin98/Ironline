"""Generates the four first/third-person weapon models (scenes/weapons/models/*.tscn)
from primitive meshes and writes the matching hip/ADS offsets into resources/weapons/*.tres.

Conventions: model forward is -Z, up +Y, right +X, origin near the receiver.
Every weapon defines its iron-sight line explicitly (SIGHT_Y = height of the aiming point
above the origin, REAR_Z = z of the rear sight). The ADS offset is derived from it so that
the sight picture is exactly centred and the rear sight sits ADS_DIST in front of the eye.

Run:  python3 tools/generate_weapon_models.py
"""
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(ROOT, "scenes", "weapons", "models")
RES_DIR = os.path.join(ROOT, "resources", "weapons")

MATERIALS = {
    "gunmetal": dict(color=(0.24, 0.25, 0.28), metallic=0.35, roughness=0.5),
    "steel": dict(color=(0.13, 0.135, 0.15), metallic=0.3, roughness=0.55),
    "steel_light": dict(color=(0.38, 0.39, 0.42), metallic=0.6, roughness=0.4),
    "wood": dict(color=(0.45, 0.24, 0.10), metallic=0.0, roughness=0.6),
    "wood_dark": dict(color=(0.30, 0.15, 0.06), metallic=0.0, roughness=0.65),
    "polymer": dict(color=(0.11, 0.11, 0.12), metallic=0.0, roughness=0.85),
    "polymer_grey": dict(color=(0.22, 0.23, 0.25), metallic=0.0, roughness=0.8),
    "glove_pad": dict(color=(0.20, 0.21, 0.23), metallic=0.0, roughness=0.8),
    "glove": dict(color=(0.13, 0.13, 0.14), metallic=0.0, roughness=0.9),
    "sleeve": dict(color=(0.17, 0.20, 0.14), metallic=0.0, roughness=0.95),
    "shell_red": dict(color=(0.72, 0.10, 0.08), metallic=0.0, roughness=0.55),
    "brass": dict(color=(0.80, 0.62, 0.26), metallic=0.8, roughness=0.3),
    "sight_dot": dict(color=(0.95, 0.95, 0.9), metallic=0.0, roughness=0.4, emission=(1.0, 1.0, 0.95), energy=0.9),
}


class Scene:
    def __init__(self, root_name):
        self.root_name = root_name
        self.subs = []  # text blocks
        self.nodes = []  # text blocks
        self.mat_ids = {}
        self.counter = 0
        self.names = {}

    def _mat(self, name):
        if name not in self.mat_ids:
            m = MATERIALS[name]
            mid = "mat_" + name
            lines = [f'[sub_resource type="StandardMaterial3D" id="{mid}"]',
                     "albedo_color = Color(%.3f, %.3f, %.3f, 1)" % m["color"]]
            if m.get("metallic"):
                lines.append("metallic = %.2f" % m["metallic"])
            lines.append("roughness = %.2f" % m["roughness"])
            if "emission" in m:
                lines.append("emission_enabled = true")
                lines.append("emission = Color(%.3f, %.3f, %.3f, 1)" % m["emission"])
                lines.append("emission_energy_multiplier = %.2f" % m["energy"])
            self.subs.append("\n".join(lines))
            self.mat_ids[name] = mid
        return self.mat_ids[name]

    def _unique(self, name):
        n = self.names.get(name, 0)
        self.names[name] = n + 1
        return name if n == 0 else f"{name}{n + 1}"

    def _vec(self, v):
        return "Vector3(%.4f, %.4f, %.4f)" % tuple(v)

    def _node(self, name, ntype, parent, pos=None, rot_deg=None, mesh_id=None):
        name = self._unique(name)
        head = f'[node name="{name}" type="{ntype}"' + (f' parent="{parent}"' if parent is not None else "") + "]"
        lines = [head]
        if pos is not None and tuple(pos) != (0, 0, 0):
            lines.append("position = " + self._vec(pos))
        if rot_deg is not None and any(abs(a) > 1e-6 for a in rot_deg):
            lines.append("rotation = " + self._vec([math.radians(a) for a in rot_deg]))
        if mesh_id:
            lines.append(f'mesh = SubResource("{mesh_id}")')
        self.nodes.append("\n".join(lines))
        return name

    def _path(self, parent, name):
        return name if parent == "." else f"{parent}/{name}"

    def root(self):
        self._node(self.root_name, "Node3D", None)

    def group(self, name, pos, parent="."):
        n = self._node(name, "Node3D", parent, pos)
        return self._path(parent, n)

    def box(self, name, pos, size, mat, rot=None, parent="."):
        mesh_id = f"mesh_{self.counter}"
        self.counter += 1
        self.subs.append(f'[sub_resource type="BoxMesh" id="{mesh_id}"]\nmaterial = SubResource("{self._mat(mat)}")\nsize = {self._vec(size)}')
        self._node(name, "MeshInstance3D", parent, pos, rot, mesh_id)

    def cyl(self, name, pos, radius, length, mat, rot=None, parent=".", radius_end=None):
        """Cylinder along the Z axis."""
        mesh_id = f"mesh_{self.counter}"
        self.counter += 1
        r2 = radius if radius_end is None else radius_end
        self.subs.append(f'[sub_resource type="CylinderMesh" id="{mesh_id}"]\nmaterial = SubResource("{self._mat(mat)}")\n'
                         f"top_radius = {radius:.4f}\nbottom_radius = {r2:.4f}\nheight = {length:.4f}\nradial_segments = 14\nrings = 1")
        r = [90.0, 0.0, 0.0]
        if rot:
            r = [r[0] + rot[0], r[1] + rot[1], r[2] + rot[2]]
        self._node(name, "MeshInstance3D", parent, pos, r, mesh_id)

    def ring(self, name, center, radius, thick, depth, mat, parent=".", segments=12):
        """Octagon ring facing along Z (e.g. a diopter or a front-sight hood)."""
        side = 2.0 * radius * math.sin(math.pi / segments) + 0.0008
        for k in range(segments):
            a = 2.0 * math.pi * k / segments
            p = (center[0] + radius * math.cos(a), center[1] + radius * math.sin(a), center[2])
            self.box(f"{name}{k}", p, (side, thick, depth), mat, rot=(0, 0, math.degrees(a) + 90.0), parent=parent)

    def arm(self, name, a, b, w, h, mat, parent="."):
        """Box from point a to point b (long axis along the line)."""
        d = [b[i] - a[i] for i in range(3)]
        length = math.sqrt(sum(x * x for x in d))
        f = [x / length for x in d]
        pitch = math.degrees(math.asin(max(-1.0, min(1.0, f[1]))))
        yaw = math.degrees(math.atan2(-f[0], -f[2]))
        mid = [(a[i] + b[i]) / 2.0 for i in range(3)]
        self.box(name, mid, (w, h, length), mat, rot=(pitch, yaw, 0.0), parent=parent)

    def marker(self, name, pos, parent="."):
        self._node(name, "Node3D", parent, pos)

    def write(self, path):
        ids = len(self.subs) + 1
        out = [f"[gd_scene load_steps={ids} format=3]", ""]
        out += [s + "\n" for s in self.subs]
        out += [n + "\n" for n in self.nodes]
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out))


def support_hand(s, group, half):
    """Left/support hand wrapped around a handguard from below (group origin = palm centre, the
    handguard bottom is 0.012 above it): palm, four fingers curling up the right side, thumb on the left."""
    s.box("LeftPalm", (0.0, 0.0, 0.0), (0.056, 0.020, 0.082), "glove", parent=group)
    s.box("LeftPalmPad", (0.0, -0.011, -0.010), (0.046, 0.006, 0.050), "glove_pad", parent=group)
    for k, zc in enumerate((-0.030, -0.010, 0.010, 0.030)):
        reach = 1.0 - 0.06 * abs(k - 1.5) # the outer fingers are a little shorter
        s.box(f"LeftFinger{k}A", (half * 0.55 + 0.024, 0.0, zc), (0.038 * reach, 0.016, 0.017), "glove", parent=group)
        s.box(f"LeftFinger{k}B", (half + 0.011, 0.016, zc), (0.016, 0.034 * reach, 0.017), "glove", parent=group)
        s.box(f"LeftFinger{k}C", (half + 0.002, 0.034, zc), (0.020, 0.013, 0.016), "glove", parent=group)
        s.box(f"LeftKnuckle{k}", (half + 0.020, 0.012, zc), (0.003, 0.012, 0.014), "glove_pad", parent=group)
    s.box("LeftThumbBase", (-(half + 0.010), 0.014, 0.014), (0.016, 0.030, 0.020), "glove", parent=group)
    s.box("LeftThumbTip", (-(half + 0.006), 0.030, -0.014), (0.015, 0.014, 0.040), "glove", parent=group)
    s.box("LeftCuff", (-0.004, -0.004, 0.046), (0.062, 0.050, 0.026), "glove_pad", parent=group)


def grip_hand(s, group, mirror=False):
    """Hand on a pistol grip (group origin = grip centre): palm and back-strap pad behind/beside it, three
    fingers wrapped round the front, index finger forward along the trigger guard, thumb on the opposite side."""
    m = -1.0 if mirror else 1.0
    side = "Left" if mirror else "Right"
    s.box(f"{side}Palm", (m * 0.026, 0.0, 0.004), (0.020, 0.062, 0.044), "glove", parent=group)
    s.box(f"{side}BackPad", (m * 0.004, -0.004, 0.026), (0.040, 0.050, 0.016), "glove_pad", parent=group)
    for k, y in enumerate((0.014, -0.004, -0.022)):
        s.box(f"{side}Finger{k}A", (m * 0.002, y, -0.026), (0.046, 0.014, 0.016), "glove", parent=group)
        s.box(f"{side}Finger{k}B", (m * -0.026, y, -0.020), (0.014, 0.014, 0.022), "glove", parent=group)
    s.box(f"{side}Index", (0.0, 0.032, -0.046), (0.014, 0.012, 0.046), "glove", parent=group)
    s.box(f"{side}ThumbBase", (m * -0.020, 0.030, 0.018), (0.016, 0.020, 0.024), "glove", parent=group)
    s.box(f"{side}ThumbTip", (m * -0.028, 0.034, -0.014), (0.014, 0.014, 0.042), "glove", parent=group)
    s.box(f"{side}Cuff", (m * 0.010, -0.028, 0.044), (0.056, 0.048, 0.026), "glove_pad", parent=group)


def hands(s, left, right, left_target, right_target, parent=".", half=0.025, bottom=0.0):
    """Gloved hands plus sleeves as two groups (LeftHand / RightHand) so reload animations can move them.
    left = (x, _, z) of the support hand (its height follows the handguard bottom `bottom`),
    right = grip centre, *_target = where the forearm comes from (model space)."""
    rel = lambda p, c: (p[0] - c[0], p[1] - c[1], p[2] - c[2])
    left = (left[0], bottom - 0.012, left[2])
    lg = s.group("LeftHand", left, parent)
    support_hand(s, lg, half)
    s.arm("LeftForearm", (-0.006, -0.018, 0.040), rel(left_target, left), 0.062, 0.056, "sleeve", parent=lg)
    rg = s.group("RightHand", right, parent)
    grip_hand(s, rg)
    s.arm("RightForearm", (0.004, -0.028, 0.044), rel(right_target, right), 0.060, 0.054, "sleeve", parent=rg)


def mag_group(s, pivot):
    """Group for the removable magazine; origin = top of the magazine well (rotation pivot)."""
    return s.group("Mag", pivot)


# --------------------------------------------------------------------------- AK-47

def ak47():
    s = Scene("AK47Model")
    s.root()
    # receiver + dust cover
    s.box("Receiver", (0, 0.000, -0.030), (0.050, 0.062, 0.300), "gunmetal")
    s.box("DustCover", (0, 0.046, -0.034), (0.040, 0.028, 0.290), "gunmetal")
    s.box("DustCoverRidge", (0, 0.062, -0.034), (0.022, 0.008, 0.270), "steel")
    s.box("EjectionPort", (0.0255, 0.030, -0.020), (0.002, 0.020, 0.075), "steel")
    s.box("ChargingHandle", (0.032, 0.038, -0.015), (0.014, 0.010, 0.026), "steel_light")
    s.box("SafetyLever", (0.0265, 0.010, -0.010), (0.003, 0.010, 0.080), "steel_light")
    # rear sight (tangent leaf with a U notch)
    s.box("RearSightBase", (0, 0.070, -0.170), (0.024, 0.010, 0.050), "gunmetal")
    s.box("RearSightL", (-0.0095, 0.0795, -0.178), (0.005, 0.017, 0.010), "steel")
    s.box("RearSightR", (0.0095, 0.0795, -0.178), (0.005, 0.017, 0.010), "steel")
    # barrel group
    s.cyl("Barrel", (0, 0.038, -0.385), 0.0105, 0.430, "gunmetal")
    s.cyl("GasTube", (0, 0.060, -0.320), 0.0090, 0.200, "steel")
    s.box("UpperHandguard", (0, 0.060, -0.300), (0.040, 0.020, 0.190), "wood")
    s.box("LowerHandguard", (0, 0.020, -0.330), (0.050, 0.040, 0.205), "wood")
    s.box("HandguardCap", (0, 0.020, -0.435), (0.052, 0.046, 0.012), "steel")
    s.box("GasBlock", (0, 0.056, -0.470), (0.024, 0.036, 0.038), "gunmetal")
    s.cyl("MuzzleBrake", (0, 0.038, -0.610), 0.0135, 0.052, "gunmetal")
    s.cyl("MuzzleRing", (0, 0.038, -0.636), 0.0105, 0.012, "steel")
    # front sight with protective ears
    s.box("FrontSightBase", (0, 0.0765, -0.560), (0.020, 0.028, 0.020), "gunmetal")
    s.box("FrontSightPost", (0, 0.0905, -0.560), (0.0042, 0.016, 0.0042), "steel")
    s.box("FrontSightEarL", (-0.0105, 0.0865, -0.560), (0.003, 0.024, 0.010), "steel")
    s.box("FrontSightEarR", (0.0105, 0.0865, -0.560), (0.003, 0.024, 0.010), "steel")
    # magazine (curved, ribbed) as a group so it can be pulled out and swapped
    mp = (0.0, -0.030, -0.082)
    mg = mag_group(s, mp)
    sub = lambda p: (p[0] - mp[0], p[1] - mp[1], p[2] - mp[2])
    s.box("Magazine1", sub((0, -0.062, -0.082)), (0.030, 0.074, 0.056), "steel", rot=(-6, 0, 0), parent=mg)
    s.box("Magazine2", sub((0, -0.128, -0.068)), (0.030, 0.074, 0.056), "steel", rot=(-16, 0, 0), parent=mg)
    s.box("Magazine3", sub((0, -0.190, -0.044)), (0.030, 0.070, 0.056), "steel", rot=(-28, 0, 0), parent=mg)
    for i in range(3):
        s.box(f"MagRib{i}", sub((0.0155, -0.070 - 0.060 * i, -0.078 + 0.017 * i)), (0.002, 0.012, 0.050), "gunmetal", rot=(-6 - 11 * i, 0, 0), parent=mg)
    # trigger group + grip
    s.box("Grip", (0, -0.075, 0.082), (0.032, 0.096, 0.040), "polymer", rot=(16, 0, 0))
    s.box("TriggerGuardBottom", (0, -0.038, 0.034), (0.008, 0.008, 0.075), "steel")
    s.box("TriggerGuardFront", (0, -0.020, -0.004), (0.008, 0.034, 0.008), "steel")
    s.box("Trigger", (0, -0.018, 0.030), (0.006, 0.022, 0.008), "steel_light", rot=(18, 0, 0))
    # stock
    s.box("StockNeck", (0, 0.014, 0.155), (0.040, 0.092, 0.100), "wood")
    s.box("StockTang", (0, 0.056, 0.150), (0.030, 0.008, 0.090), "steel")
    s.box("Stock", (0, -0.012, 0.290), (0.040, 0.082, 0.150), "wood")
    s.box("StockPad", (0, -0.014, 0.372), (0.042, 0.098, 0.014), "polymer")
    s.marker("Muzzle", (0, 0.038, -0.650))
    hands(s, left=(0.0, 0.0, -0.335), right=(0.0, -0.078, 0.086), left_target=(-0.12, -0.55, 0.30), right_target=(0.14, -0.55, 0.38), half=0.025, bottom=0.0)
    return s


# --------------------------------------------------------------------------- MP5

def mp5():
    s = Scene("MP5Model")
    s.root()
    s.box("Receiver", (0, 0.018, 0.010), (0.050, 0.066, 0.270), "gunmetal")
    s.box("ReceiverTop", (0, 0.054, 0.010), (0.038, 0.010, 0.250), "steel")
    s.box("EjectionPort", (0.0255, 0.030, 0.015), (0.002, 0.020, 0.060), "steel")
    s.cyl("CockingTube", (-0.034, 0.030, -0.120), 0.0105, 0.300, "gunmetal")
    s.box("CockingHandle", (-0.034, 0.030, -0.250), (0.020, 0.012, 0.020), "steel_light")
    s.box("Handguard", (0, 0.010, -0.215), (0.056, 0.052, 0.170), "polymer_grey")
    for i in range(4):
        s.box(f"HandguardSlot{i}", (0.0285, 0.010, -0.160 - 0.034 * i), (0.002, 0.028, 0.014), "polymer")
    s.cyl("Barrel", (0, 0.016, -0.390), 0.0085, 0.150, "gunmetal")
    s.cyl("MuzzleSleeve", (0, 0.016, -0.452), 0.0125, 0.040, "gunmetal")
    # rear diopter (octagon ring) + front hood with post -> aiming point at y = 0.080
    s.box("DiopterBase", (0, 0.062, 0.070), (0.026, 0.008, 0.030), "steel")
    s.ring("DiopterRing", (0, 0.082, 0.070), 0.0100, 0.0050, 0.014, "steel")
    s.box("FrontSightPost", (0, 0.051, -0.440), (0.0040, 0.050, 0.0040), "steel")
    s.ring("FrontHood", (0, 0.082, -0.440), 0.0125, 0.0040, 0.016, "gunmetal")
    s.box("FrontHoodMount", (0, 0.040, -0.440), (0.012, 0.046, 0.016), "gunmetal")
    mp = (0.0, -0.030, -0.048)
    mg = mag_group(s, mp)
    sub = lambda p: (p[0] - mp[0], p[1] - mp[1], p[2] - mp[2])
    s.box("Magazine1", sub((0, -0.075, -0.048)), (0.026, 0.100, 0.050), "steel", rot=(-4, 0, 0), parent=mg)
    s.box("Magazine2", sub((0, -0.165, -0.034)), (0.026, 0.090, 0.050), "steel", rot=(-12, 0, 0), parent=mg)
    s.box("MagBase", sub((0, -0.213, -0.020)), (0.030, 0.008, 0.056), "polymer", rot=(-12, 0, 0), parent=mg)
    s.box("Grip", (0, -0.070, 0.108), (0.032, 0.095, 0.040), "polymer", rot=(14, 0, 0))
    s.box("TriggerGuardBottom", (0, -0.034, 0.062), (0.008, 0.008, 0.070), "steel")
    s.box("TriggerGuardFront", (0, -0.016, 0.028), (0.008, 0.034, 0.008), "steel")
    s.box("Trigger", (0, -0.014, 0.060), (0.006, 0.022, 0.008), "steel_light", rot=(18, 0, 0))
    # collapsible wire stock
    s.box("StockRailL", (-0.024, 0.026, 0.250), (0.008, 0.008, 0.230), "steel_light")
    s.box("StockRailR", (0.024, 0.026, 0.250), (0.008, 0.008, 0.230), "steel_light")
    s.box("StockBraceTop", (0, 0.032, 0.150), (0.056, 0.012, 0.016), "gunmetal")
    s.box("StockPad", (0, -0.004, 0.372), (0.044, 0.100, 0.016), "polymer")
    s.box("StockPadUpper", (0, 0.030, 0.366), (0.040, 0.022, 0.012), "polymer")
    s.marker("Muzzle", (0, 0.016, -0.480))
    hands(s, left=(0.0, 0.0, -0.220), right=(0.0, -0.074, 0.112), left_target=(-0.12, -0.55, 0.30), right_target=(0.14, -0.55, 0.38), half=0.028, bottom=-0.016)
    return s


# --------------------------------------------------------------------------- Shotgun

def shotgun():
    s = Scene("ShotgunModel")
    s.root()
    s.box("Receiver", (0, 0.012, 0.000), (0.050, 0.074, 0.230), "gunmetal")
    s.box("EjectionPort", (0.0255, 0.028, 0.000), (0.002, 0.022, 0.085), "steel")
    s.box("ReceiverTop", (0, 0.052, 0.000), (0.036, 0.008, 0.230), "steel")
    s.cyl("Barrel", (0, 0.040, -0.410), 0.0145, 0.600, "gunmetal")
    s.cyl("MagTube", (0, 0.008, -0.360), 0.0130, 0.500, "steel")
    s.cyl("MagTubeCap", (0, 0.008, -0.620), 0.0150, 0.014, "steel_light")
    s.box("VentRib", (0, 0.0585, -0.380), (0.012, 0.005, 0.560), "steel")
    s.box("RibSupport0", (0, 0.0515, -0.200), (0.006, 0.010, 0.012), "steel")
    s.box("RibSupport1", (0, 0.0515, -0.400), (0.006, 0.010, 0.012), "steel")
    s.box("Bead", (0, 0.0645, -0.685), (0.0070, 0.008, 0.0070), "sight_dot")
    s.box("RearNotchL", (-0.0085, 0.060, 0.040), (0.006, 0.010, 0.014), "steel")
    s.box("RearNotchR", (0.0085, 0.060, 0.040), (0.006, 0.010, 0.014), "steel")
    pump = s.group("Pump", (0, 0.004, -0.360))
    s.box("PumpForearm", (0, 0, 0), (0.058, 0.048, 0.170), "wood", parent=pump)
    for i in range(5):
        s.box(f"PumpGroove{i}", (0, -0.0245, -0.060 + 0.030 * i), (0.050, 0.003, 0.008), "wood_dark", parent=pump)
    s.box("PumpRing", (0, 0.0, 0.092), (0.054, 0.044, 0.012), "steel", parent=pump)
    s.box("Grip", (0, -0.048, 0.135), (0.034, 0.072, 0.046), "wood", rot=(22, 0, 0))
    s.box("TriggerGuardBottom", (0, -0.034, 0.060), (0.008, 0.008, 0.075), "steel")
    s.box("TriggerGuardFront", (0, -0.018, 0.024), (0.008, 0.030, 0.008), "steel")
    s.box("Trigger", (0, -0.016, 0.056), (0.006, 0.022, 0.008), "steel_light", rot=(18, 0, 0))
    s.box("StockNeck", (0, 0.004, 0.230), (0.040, 0.066, 0.110), "wood")
    s.box("Stock", (0, -0.020, 0.340), (0.042, 0.092, 0.150), "wood", rot=(-3, 0, 0))
    s.box("StockPad", (0, -0.026, 0.424), (0.044, 0.104, 0.014), "polymer")
    s.marker("Muzzle", (0, 0.040, -0.715))
    hands(s, left=(0.0, 0.0, -0.360), right=(0.0, -0.045, 0.138), left_target=(-0.12, -0.55, 0.30), right_target=(0.14, -0.55, 0.40), half=0.029, bottom=-0.020)
    # a shell the support hand carries to the loading gate (hidden unless the reload animation shows it)
    shell = s.group("ShellProp", (0.020, 0.004, -0.044), "LeftHand")
    s.cyl("ShellBody", (0.0, 0.0, -0.012), 0.0105, 0.044, "shell_red", parent=shell)
    s.cyl("ShellBase", (0.0, 0.0, 0.016), 0.0112, 0.012, "brass", parent=shell)
    return s


# --------------------------------------------------------------------------- Pistol

def pistol():
    s = Scene("PistolModel")
    s.root()
    slide = s.group("Slide", (0, 0, 0))
    s.box("SlideMesh", (0, 0.032, -0.025), (0.030, 0.034, 0.170), "gunmetal", parent=slide)
    s.box("SlideTop", (0, 0.051, -0.025), (0.014, 0.004, 0.160), "steel", parent=slide)
    for i in range(4):
        s.box(f"SlideSerration{i}", (0.0155, 0.034, 0.030 + 0.011 * i), (0.002, 0.026, 0.005), "steel", parent=slide)
    s.box("EjectionPort", (0.0155, 0.038, -0.030), (0.002, 0.016, 0.050), "steel", parent=slide)
    # sights: aiming point at y = 0.056
    s.box("RearSightL", (-0.0075, 0.0585, 0.050), (0.0075, 0.012, 0.010), "steel", parent=slide)
    s.box("RearSightR", (0.0075, 0.0585, 0.050), (0.0075, 0.012, 0.010), "steel", parent=slide)
    s.box("RearDotL", (-0.0075, 0.0585, 0.0449), (0.0035, 0.0035, 0.001), "sight_dot", parent=slide)
    s.box("RearDotR", (0.0075, 0.0585, 0.0449), (0.0035, 0.0035, 0.001), "sight_dot", parent=slide)
    s.box("FrontSight", (0, 0.0585, -0.100), (0.0045, 0.012, 0.010), "steel", parent=slide)
    s.box("FrontDot", (0, 0.0585, -0.1052), (0.0030, 0.0030, 0.001), "sight_dot", parent=slide)
    s.box("Frame", (0, 0.004, -0.010), (0.028, 0.024, 0.150), "polymer_grey")
    s.cyl("BarrelTip", (0, 0.030, -0.110), 0.0075, 0.020, "steel_light")
    s.box("Grip", (0, -0.050, 0.050), (0.030, 0.092, 0.052), "polymer", rot=(12, 0, 0))
    for i in range(4):
        s.box(f"GripPanel{i}", (0.0155, -0.040 - 0.018 * i, 0.047 + 0.003 * i), (0.002, 0.010, 0.040), "polymer_grey", rot=(12, 0, 0))
    mp = (0.0, -0.045, 0.055) # top of the magazine well inside the grip
    mg = mag_group(s, mp)
    s.box("MagBody", (0.0, -0.030, 0.003), (0.024, 0.070, 0.040), "steel", rot=(12, 0, 0), parent=mg)
    s.box("MagBase", (0.0, -0.055 , 0.011), (0.032, 0.008, 0.056), "steel", rot=(12, 0, 0), parent=mg)
    s.box("TriggerGuardBottom", (0, -0.014, -0.020), (0.008, 0.008, 0.060), "polymer_grey")
    s.box("TriggerGuardFront", (0, -0.002, -0.048), (0.008, 0.024, 0.008), "polymer_grey")
    s.box("Trigger", (0, -0.004, -0.014), (0.006, 0.020, 0.007), "steel_light", rot=(16, 0, 0))
    s.box("Hammer", (0, 0.040, 0.064), (0.008, 0.012, 0.012), "steel")
    s.marker("Muzzle", (0, 0.032, -0.122))
    # right hand on the grip, left hand supports from the other side (both are groups for the reload animation)
    rc = (0.002, -0.044, 0.056)
    rg = s.group("RightHand", rc)
    grip_hand(s, rg)
    s.arm("RightForearm", (0.004, -0.028, 0.044), (0.09 - rc[0], -0.55 - rc[1], 0.30 - rc[2]), 0.056, 0.050, "sleeve", parent=rg)
    lc = (-0.040, -0.052, 0.050)
    lg = s.group("LeftHand", lc)
    grip_hand(s, lg, mirror=True)
    s.arm("LeftForearm", (-0.004, -0.026, 0.044), (-0.09 - lc[0], -0.55 - lc[1], 0.30 - lc[2]), 0.056, 0.050, "sleeve", parent=lg)
    return s


# name -> (builder, sight_y, rear_z, ads_dist, hip_position, ads_fov)
WEAPONS = {
    "ak47": (ak47, 0.088, -0.178, 0.42, (0.20, -0.20, -0.40), 56.0),
    "mp5": (mp5, 0.082, 0.070, 0.30, (0.19, -0.19, -0.40), 58.0),
    "shotgun": (shotgun, 0.0645, 0.040, 0.30, (0.20, -0.20, -0.42), 58.0),
    "pistol": (pistol, 0.0585, 0.050, 0.32, (0.17, -0.17, -0.34), 60.0),
}


def update_resource(weapon, ads_pos, hip_pos, fov):
    path = os.path.join(RES_DIR, weapon + ".tres")
    text = open(path, encoding="utf-8").read()
    vec = lambda v: "Vector3(%.4f, %.4f, %.4f)" % v
    text = re.sub(r"^ads_position = .*$", "ads_position = " + vec(ads_pos), text, flags=re.M)
    text = re.sub(r"^hip_position = .*$", "hip_position = " + vec(hip_pos), text, flags=re.M)
    text = re.sub(r"^ads_fov = .*$", "ads_fov = %.1f" % fov, text, flags=re.M)
    open(path, "w", encoding="utf-8", newline="\n").write(text)


def main():
    for name, (builder, sight_y, rear_z, ads_dist, hip, fov) in WEAPONS.items():
        scene = builder()
        scene.write(os.path.join(MODEL_DIR, name + "_model.tscn"))
        ads = (0.0, -sight_y, -ads_dist - rear_z)
        update_resource(name, ads, hip, fov)
        print(f"{name}: {len(scene.nodes)} Nodes, ADS {ads}")


if __name__ == "__main__":
    main()
