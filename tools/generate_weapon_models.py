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
    # tex = procedural detail maps (assets/textures/<tex>.png, _n, _r), object-space triplanar at `scale` tiles per metre
    "gunmetal": dict(color=(0.30, 0.31, 0.34), metallic=0.3, roughness=1.0, tex="weapon_metal", scale=14),
    "steel": dict(color=(0.17, 0.175, 0.19), metallic=0.3, roughness=1.0, tex="weapon_metal", scale=14),
    "steel_light": dict(color=(0.48, 0.49, 0.52), metallic=0.45, roughness=1.0, tex="weapon_metal", scale=14),
    "wood": dict(color=(0.46, 0.28, 0.14), metallic=0.0, roughness=1.0, tex="weapon_wood", scale=9),
    "wood_dark": dict(color=(0.30, 0.18, 0.09), metallic=0.0, roughness=1.0, tex="weapon_wood", scale=9),
    "polymer": dict(color=(0.12, 0.12, 0.13), metallic=0.0, roughness=1.0, tex="weapon_polymer", scale=16),
    "polymer_grey": dict(color=(0.24, 0.25, 0.27), metallic=0.0, roughness=1.0, tex="weapon_polymer", scale=16),
    # bare hands: tinted per player at runtime (ReloadRig.apply_skin finds them by the material's resource_name)
    "skin": dict(color=(0.88, 0.72, 0.58), metallic=0.0, roughness=0.85, name="skin"),
    "skin_shade": dict(color=(0.77, 0.60, 0.47), metallic=0.0, roughness=0.9, name="skin_shade"),
    "nail": dict(color=(0.93, 0.80, 0.73), metallic=0.0, roughness=0.6, name="nail"),
    "sleeve": dict(color=(0.17, 0.20, 0.14), metallic=0.0, roughness=0.95),
    "shell_red": dict(color=(0.72, 0.10, 0.08), metallic=0.0, roughness=0.55),
    "brass": dict(color=(0.80, 0.62, 0.26), metallic=0.8, roughness=0.3),
    "lens": dict(color=(0.10, 0.20, 0.34), metallic=0.9, roughness=0.10),
    "sight_dot": dict(color=(0.95, 0.95, 0.9), metallic=0.0, roughness=0.4, emission=(1.0, 1.0, 0.95), energy=0.9),
}


class Scene:
    adjust_all = {}  # (root name, box name) -> [(axis, side)]: push that face outwards by POP (fixes z-fighting)
    POP = 0.0008

    def __init__(self, root_name):
        self.root_name = root_name
        self.subs = []  # text blocks
        self.nodes = []  # text blocks
        self.mat_ids = {}
        self.ext = {}  # texture path -> ext_resource id
        self.counter = 0
        self.names = {}
        self.boxes = []  # axis-aligned world-space boxes (name, pos, size, mat) for the z-fighting check

    def _mat(self, name):
        if name not in self.mat_ids:
            m = MATERIALS[name]
            mid = "mat_" + name
            lines = [f'[sub_resource type="StandardMaterial3D" id="{mid}"]']
            if "name" in m:
                lines.append(f'resource_name = "{m["name"]}"')
            lines.append("albedo_color = Color(%.3f, %.3f, %.3f, 1)" % m["color"])
            if m.get("metallic"):
                lines.append("metallic = %.2f" % m["metallic"])
            lines.append("roughness = %.2f" % m["roughness"])
            if "tex" in m:
                a = self._ext(m["tex"] + ".png")
                n = self._ext(m["tex"] + "_n.png")
                r = self._ext(m["tex"] + "_r.png")
                lines.append(f'albedo_texture = ExtResource("{a}")')
                lines.append(f'roughness_texture = ExtResource("{r}")')
                lines.append("roughness_texture_channel = 0")
                lines.append("normal_enabled = true")
                lines.append(f'normal_texture = ExtResource("{n}")')
                lines.append("uv1_scale = Vector3(%d, %d, %d)" % ((m["scale"],) * 3))
                lines.append("uv1_triplanar = true")
            if "emission" in m:
                lines.append("emission_enabled = true")
                lines.append("emission = Color(%.3f, %.3f, %.3f, 1)" % m["emission"])
                lines.append("emission_energy_multiplier = %.2f" % m["energy"])
            self.subs.append("\n".join(lines))
            self.mat_ids[name] = mid
        return self.mat_ids[name]

    def _ext(self, fname):
        if fname not in self.ext:
            self.ext[fname] = "tex_%d" % (len(self.ext) + 1)
        return self.ext[fname]

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
        for ax, side in Scene.adjust_all.get((self.root_name, name), []):
            size = list(size)
            pos = list(pos)
            size[ax] += Scene.POP
            pos[ax] += side * Scene.POP / 2
        mesh_id = f"mesh_{self.counter}"
        self.counter += 1
        self.subs.append(f'[sub_resource type="BoxMesh" id="{mesh_id}"]\nmaterial = SubResource("{self._mat(mat)}")\nsize = {self._vec(size)}')
        self._node(name, "MeshInstance3D", parent, pos, rot, mesh_id)
        if parent == "." and (rot is None or not any(abs(a) > 1e-6 for a in rot)):
            self.boxes.append((name, tuple(pos), tuple(size), mat))

    def coplanar_faces(self, eps=0.0006, min_area=2e-6):
        """Same-facing coplanar faces of different-material boxes (they flicker = z-fighting in game).
        Returns [(smaller_box, other_box, axis, side, area)]; `side` is +1 for the max face, -1 for the min face."""
        out = []
        for i, (na, pa, sa, ma) in enumerate(self.boxes):
            for nb, pb, sb, mb in self.boxes[i + 1:]:
                if ma == mb:
                    continue
                for ax in range(3):
                    area = 1.0
                    for o in range(3):
                        if o == ax:
                            continue
                        lo = max(pa[o] - sa[o] / 2, pb[o] - sb[o] / 2)
                        hi = min(pa[o] + sa[o] / 2, pb[o] + sb[o] / 2)
                        area *= max(0.0, hi - lo)
                    if area < min_area:
                        continue
                    for side in (-1, 1):
                        fa = pa[ax] + side * sa[ax] / 2
                        fb = pb[ax] + side * sb[ax] / 2
                        if abs(fa - fb) < eps:
                            va = sa[0] * sa[1] * sa[2]
                            vb = sb[0] * sb[1] * sb[2]
                            out.append((na, nb, ax, side, area) if va <= vb else (nb, na, ax, side, area))
        return out

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
        ids = len(self.subs) + len(self.ext) + 1
        out = [f"[gd_scene load_steps={ids} format=3]", ""]
        out += [f'[ext_resource type="Texture2D" path="res://assets/textures/{f}" id="{i}"]\n' for f, i in self.ext.items()]
        out += [s + "\n" for s in self.subs]
        out += [n + "\n" for n in self.nodes]
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out))


def support_hand(s, group, half):
    """Bare left/support hand wrapped around a handguard from below (group origin = palm centre, the handguard
    bottom is 0.012 above it): palm with heel pad, four fingers (index nearest the muzzle) curling up the right
    side in three joints each with creases and nails, the thumb along the left side, a slim wrist."""
    s.box("LeftPalm", (0.0, 0.0, 0.0), (0.056, 0.022, 0.082), "skin", parent=group)
    s.box("LeftPalmHeel", (-0.004, -0.0125, 0.028), (0.040, 0.007, 0.030), "skin_shade", parent=group)
    t = 0.0165 # finger thickness
    for k, zc in enumerate((-0.0305, -0.0100, 0.0105, 0.0310)):
        reach = (1.0, 1.08, 1.0, 0.84)[k] # index, middle, ring, little finger
        xo = half + 0.002 + t / 2 # the finger rises beside the handguard
        top = -0.008 + 0.034 * reach
        s.box(f"LeftFinger{k}A", (0.0285, 0.0, zc), (0.032, t, 0.0162), "skin", parent=group)
        s.box(f"LeftFinger{k}B", (xo, (-0.008 + top) / 2, zc), (t, top + 0.008, 0.0162), "skin", parent=group)
        s.box(f"LeftFinger{k}C", (xo - 0.0015, top + 0.005, zc), (0.0145, 0.012 * reach, 0.0152), "skin", parent=group)
        s.box(f"LeftKnuckle{k}", (xo + 0.0001, -0.0035, zc), (t + 0.0006, 0.0028, 0.0166), "skin_shade", parent=group)
        s.box(f"LeftJoint{k}", (xo + 0.0001, top - 0.001, zc), (t + 0.0006, 0.0024, 0.0166), "skin_shade", parent=group)
        s.box(f"LeftNail{k}", (xo + 0.0071, top + 0.005, zc), (0.0016, 0.0085 * reach, 0.0105), "nail", parent=group)
    s.box("LeftThumbBase", (-(half + 0.0095), 0.013, 0.016), (0.0165, 0.030, 0.022), "skin", parent=group)
    s.box("LeftThumbMid", (-(half + 0.0075), 0.0285, 0.000), (0.0155, 0.0155, 0.032), "skin", parent=group)
    s.box("LeftThumbTip", (-(half + 0.0075), 0.0285, -0.0245), (0.0145, 0.0140, 0.022), "skin", parent=group)
    s.box("LeftThumbJoint", (-(half + 0.0075), 0.0285, -0.0140), (0.0160, 0.0165, 0.0026), "skin_shade", parent=group)
    s.box("LeftThumbNail", (-(half + 0.0075), 0.0357, -0.0245), (0.0105, 0.0016, 0.0125), "nail", parent=group)
    s.box("LeftWrist", (-0.005, -0.010, 0.056), (0.050, 0.040, 0.028), "skin", parent=group)


def grip_hand(s, group, mirror=False):
    """Bare hand on a pistol grip (group origin = grip centre): palm and web behind/beside it, three fingers wrapped
    round the front (creases, nails), index finger forward along the trigger guard, thumb on the opposite side, slim wrist."""
    m = -1.0 if mirror else 1.0
    side = "Left" if mirror else "Right"
    s.box(f"{side}Palm", (m * 0.026, 0.0, 0.006), (0.022, 0.064, 0.046), "skin", parent=group)
    s.box(f"{side}Web", (m * 0.006, -0.002, 0.030), (0.040, 0.052, 0.016), "skin", parent=group)
    for k, y in enumerate((0.014, -0.004, -0.022)):
        s.box(f"{side}Finger{k}A", (m * 0.003, y, -0.0265), (0.046, 0.0158, 0.0165), "skin", parent=group)
        s.box(f"{side}Finger{k}B", (m * -0.0265, y, -0.0215), (0.0155, 0.0152, 0.024), "skin", parent=group)
        s.box(f"{side}Knuckle{k}", (m * 0.0255, y, -0.0265), (0.0030, 0.0162, 0.0169), "skin_shade", parent=group)
        s.box(f"{side}Joint{k}", (m * -0.0265, y, -0.0155), (0.0159, 0.0156, 0.0026), "skin_shade", parent=group)
        s.box(f"{side}Nail{k}", (m * -0.0345, y, -0.0235), (0.0016, 0.0098, 0.0125), "nail", parent=group)
    s.box(f"{side}Index", (0.0, 0.032, -0.036), (0.0145, 0.0130, 0.026), "skin", parent=group)
    s.box(f"{side}IndexTip", (0.0, 0.032, -0.0595), (0.0135, 0.0120, 0.022), "skin", parent=group)
    s.box(f"{side}IndexJoint", (0.0, 0.032, -0.0485), (0.0150, 0.0135, 0.0026), "skin_shade", parent=group)
    s.box(f"{side}IndexNail", (0.0, 0.0388, -0.0595), (0.0105, 0.0016, 0.0125), "nail", parent=group)
    s.box(f"{side}ThumbBase", (m * -0.020, 0.030, 0.018), (0.0165, 0.021, 0.026), "skin", parent=group)
    s.box(f"{side}ThumbTip", (m * -0.028, 0.034, -0.014), (0.0145, 0.0145, 0.040), "skin", parent=group)
    s.box(f"{side}ThumbNail", (m * -0.028, 0.0414, -0.0265), (0.0110, 0.0016, 0.0125), "nail", parent=group)
    s.box(f"{side}Wrist", (m * 0.008, -0.026, 0.050), (0.050, 0.042, 0.030), "skin", parent=group)


def reach(v, start, max_len):
    """Shortens the vector from `start` to `v` to at most `max_len` (forearms: stubby and thick instead of long and thin)."""
    d = [v[i] - start[i] for i in range(3)]
    l = math.sqrt(sum(x * x for x in d))
    if l <= max_len:
        return v
    return tuple(start[i] + d[i] * max_len / l for i in range(3))


def hands(s, left, right, left_target, right_target, parent=".", half=0.025, bottom=0.0):
    """Bare hands plus sleeves as two groups (LeftHand / RightHand) so reload animations can move them.
    left = (x, _, z) of the support hand (its height follows the handguard bottom `bottom`),
    right = grip centre, *_target = where the forearm comes from (model space)."""
    rel = lambda p, c: (p[0] - c[0], p[1] - c[1], p[2] - c[2])
    left = (left[0], bottom - 0.012, left[2])
    lg = s.group("LeftHand", left, parent)
    support_hand(s, lg, half)
    a_l = (-0.006, -0.018, 0.040)
    s.arm("LeftForearm", a_l, reach(rel(left_target, left), a_l, 0.36), 0.082, 0.074, "sleeve", parent=lg)
    rg = s.group("RightHand", right, parent)
    grip_hand(s, rg)
    a_r = (0.004, -0.028, 0.044)
    s.arm("RightForearm", a_r, reach(rel(right_target, right), a_r, 0.36), 0.078, 0.070, "sleeve", parent=rg)


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
    # charging handle on the LEFT side: a visible lever with a knob (the support hand pulls it during the reload)
    s.box("HandleSlot", (-0.0255, 0.040, 0.012), (0.002, 0.010, 0.130), "steel")  # the rail the handle runs in
    handle = s.group("ChargingHandle", (-0.046, 0.040, -0.015))  # moves with every shot and with the reload
    s.box("HandleLever", (0, 0, 0), (0.040, 0.012, 0.016), "steel_light", parent=handle)
    s.box("HandleKnob", (-0.024, 0, 0), (0.014, 0.020, 0.030), "polymer", parent=handle)
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
    # fine detail: receiver rivets, cleaning rod, handguard grooves, grip ridges
    for z in (-0.140, -0.095, 0.060, 0.100):
        for sx in (-1, 1):
            s.box(f"Rivet{sx}_{int(z * 1000)}", (sx * 0.0255, -0.012, z), (0.003, 0.006, 0.006), "steel_light")
    s.cyl("CleaningRod", (0, -0.004, -0.350), 0.0042, 0.230, "steel_light")
    for i in range(3):
        for sx in (-1, 1):
            s.box(f"HandguardGroove{sx}_{i}", (sx * 0.0255, 0.018, -0.275 - 0.040 * i), (0.002, 0.022, 0.012), "wood_dark")
    for i in range(3):
        for sx in (-1, 1):
            s.box(f"GripRidge{sx}_{i}", (sx * 0.0165, -0.050 - 0.026 * i, 0.076 + 0.007 * i), (0.002, 0.010, 0.030), "polymer_grey", rot=(16, 0, 0))
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
    # cocking handle: a short stem out of the tube ending in a flat grip knob; it runs back and forth with every shot / the reload
    handle = s.group("CockingHandle", (-0.034, 0.030, -0.250))
    s.box("HandleStem", (-0.016, 0, 0), (0.026, 0.009, 0.014), "steel_light", parent=handle)
    s.box("HandleKnob", (-0.034, 0, 0), (0.014, 0.018, 0.030), "polymer", parent=handle)
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


# --------------------------------------------------------------------------- Sniper (bolt action, scope)

def sniper():
    s = Scene("SniperModel")
    s.root()
    # receiver with rail and ejection port
    s.box("Receiver", (0, 0.0, 0.040), (0.052, 0.064, 0.300), "gunmetal")
    s.box("ReceiverRail", (0, 0.036, 0.040), (0.030, 0.008, 0.280), "steel")
    s.box("EjectionPort", (0.0265, 0.014, 0.050), (0.002, 0.026, 0.100), "steel")
    # heavy barrel, sleeve and muzzle brake with ports
    s.cyl("Barrel", (0, 0.012, -0.440), 0.0135, 0.660, "gunmetal")
    s.cyl("BarrelSleeve", (0, 0.012, -0.300), 0.0185, 0.340, "steel")
    s.cyl("MuzzleBrake", (0, 0.012, -0.800), 0.0185, 0.080, "steel_light")
    s.box("BrakePortL", (-0.0188, 0.012, -0.800), (0.004, 0.012, 0.050), "polymer")
    s.box("BrakePortR", (0.0188, 0.012, -0.800), (0.004, 0.012, 0.050), "polymer")
    # chassis forend with a bottom rail
    s.box("Forend", (0, -0.016, -0.260), (0.056, 0.052, 0.340), "polymer_grey")
    s.box("ForendRail", (0, -0.045, -0.260), (0.020, 0.010, 0.300), "steel")
    # scope: tube, bells with glass, turrets, rings (mounted ~1.2 cm higher, on taller rings, so it clearly sits above the rail)
    s.cyl("ScopeTube", (0, 0.094, -0.020), 0.0215, 0.300, "polymer")
    s.cyl("ScopeObjective", (0, 0.094, -0.205), 0.033, 0.090, "polymer")
    s.cyl("ScopeOcular", (0, 0.094, 0.175), 0.0285, 0.070, "polymer")
    s.cyl("ScopeLensFront", (0, 0.094, -0.2515), 0.0305, 0.004, "lens")
    s.cyl("ScopeLensRear", (0, 0.094, 0.2105), 0.0250, 0.004, "lens")
    s.box("ScopeTurretTop", (0, 0.1195, -0.020), (0.026, 0.024, 0.026), "polymer")
    s.box("ScopeTurretSide", (0.0345, 0.094, -0.020), (0.024, 0.026, 0.026), "polymer")
    s.box("ScopeRingFront", (0, 0.0585, -0.090), (0.036, 0.0425, 0.032), "steel")
    s.box("ScopeRingRear", (0, 0.0585, 0.095), (0.036, 0.0425, 0.032), "steel")
    # bolt (group: axis along z, the heavy handle sticks out to the right and turns up when it is worked)
    bolt = s.group("Bolt", (0, 0.014, 0.070))
    s.box("BoltBody", (0, 0, 0), (0.024, 0.024, 0.140), "steel_light", parent=bolt)
    s.box("BoltRod", (0.066, 0, 0.040), (0.112, 0.014, 0.014), "steel_light", parent=bolt)
    s.box("BoltKnob", (0.138, 0, 0.040), (0.036, 0.034, 0.034), "polymer_grey", parent=bolt)
    s.marker("BoltGrip", (0.138, 0, 0.040), parent=bolt)
    # trigger group, grip, stock
    s.box("TriggerGuardBottom", (0, -0.040, 0.060), (0.008, 0.008, 0.075), "steel")
    s.box("TriggerGuardFront", (0, -0.024, 0.024), (0.008, 0.030, 0.008), "steel")
    s.box("Trigger", (0, -0.022, 0.056), (0.006, 0.022, 0.008), "steel_light", rot=(18, 0, 0))
    s.box("Grip", (0, -0.078, 0.140), (0.034, 0.092, 0.044), "polymer_grey", rot=(22, 0, 0))
    s.box("StockNeck", (0, 0.002, 0.235), (0.042, 0.070, 0.090), "polymer_grey")
    s.box("Stock", (0, -0.015, 0.360), (0.046, 0.085, 0.180), "polymer_grey", rot=(-3, 0, 0))
    s.box("CheekRiser", (0, 0.040, 0.330), (0.040, 0.030, 0.120), "polymer")
    s.box("StockPad", (0, -0.022, 0.462), (0.048, 0.100, 0.016), "polymer")
    # box magazine (removable)
    mp = (0.0, -0.030, 0.020)
    mg = mag_group(s, mp)
    s.box("MagBody", (0.0, -0.055, 0.0), (0.034, 0.110, 0.070), "steel", parent=mg)
    s.box("MagFloor", (0.0, -0.113, 0.0), (0.040, 0.010, 0.078), "gunmetal", parent=mg)
    s.marker("Muzzle", (0, 0.012, -0.845))
    hands(s, left=(0.0, 0.0, -0.280), right=(0.0, -0.082, 0.138), left_target=(-0.12, -0.55, 0.30), right_target=(0.14, -0.55, 0.40), half=0.028, bottom=-0.042)
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
    a_r = (0.004, -0.028, 0.044)
    s.arm("RightForearm", a_r, reach((0.09 - rc[0], -0.55 - rc[1], 0.30 - rc[2]), a_r, 0.36), 0.078, 0.070, "sleeve", parent=rg)
    lc = (-0.040, -0.052, 0.050)
    lg = s.group("LeftHand", lc)
    grip_hand(s, lg, mirror=True)
    a_l = (-0.004, -0.026, 0.044)
    s.arm("LeftForearm", a_l, reach((-0.09 - lc[0], -0.55 - lc[1], 0.30 - lc[2]), a_l, 0.36), 0.078, 0.070, "sleeve", parent=lg)
    return s


# name -> (builder, sight_y, rear_z, ads_dist, hip_position, ads_fov)
WEAPONS = {
    "ak47": (ak47, 0.088, -0.178, 0.42, (0.20, -0.20, -0.40), 56.0),
    "mp5": (mp5, 0.082, 0.070, 0.30, (0.19, -0.19, -0.40), 58.0),
    "shotgun": (shotgun, 0.0645, 0.040, 0.30, (0.20, -0.20, -0.42), 58.0),
    "pistol": (pistol, 0.0585, 0.050, 0.32, (0.11, -0.16, -0.36), 60.0),
    # sight_y = the scope axis, rear_z = the rear lens: the eye sits 0.10 m behind it
    "sniper": (sniper, 0.094, 0.2125, 0.10, (0.22, -0.22, -0.50), 60.0),
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
        Scene.adjust_all = {}
        scene = builder()
        for small, other, ax, side, area in scene.coplanar_faces():
            Scene.adjust_all.setdefault((scene.root_name, small), []).append((ax, side))
        if Scene.adjust_all:
            print(f"{name}: {len(Scene.adjust_all)} Boxen gegen Flackern (z-fighting) um {Scene.POP * 1000:.1f} mm vorgezogen")
            scene = builder()
            left = scene.coplanar_faces()
            if left:
                print("FLACKERN (bleibt):", left)
        scene.write(os.path.join(MODEL_DIR, name + "_model.tscn"))
        ads = (0.0, -sight_y, -ads_dist - rear_z)
        update_resource(name, ads, hip, fov)
        print(f"{name}: {len(scene.nodes)} Nodes, ADS {ads}")


if __name__ == "__main__":
    main()
