"""Writes one StandardMaterial3D .tres per generated texture (triplanar, world UV).

Run from the project root:  py -3 tools/generate_materials.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "materials")

# name: (roughness, metallic, uv scale per metre, specular)
MATERIALS = {
    "concrete": (0.92, 0.0, 0.5, 0.3),
    "plaster": (0.85, 0.0, 0.5, 0.35),
    "asphalt": (0.95, 0.0, 0.35, 0.2),
    "metal_panel": (0.45, 0.6, 0.5, 0.5),
    "wood_planks": (0.7, 0.0, 0.5, 0.4),
    "brick": (0.9, 0.0, 0.5, 0.3),
    "grass": (1.0, 0.0, 0.35, 0.1),
    "crate": (0.75, 0.0, 1.0, 0.4),
    "tiles": (0.35, 0.05, 0.5, 0.6),
    "roof_shingles": (0.9, 0.0, 0.5, 0.3),
    "ship_hull": (0.5, 0.35, 0.5, 0.5),
    "water": (0.1, 0.2, 0.2, 0.9),
    "dirt": (1.0, 0.0, 0.35, 0.1),
    "rubber": (0.8, 0.0, 1.0, 0.3),
}

# roughness values in MATERIALS are kept for reference; the roughness map holds the real values
NORMAL_SCALE = {"wood_planks": 0.5, "metal_panel": 0.7, "brick": 1.3, "concrete": 1.1, "asphalt": 1.0, "water": 0.6, "rubber": 0.8}

TEMPLATE = """[gd_resource type="StandardMaterial3D" load_steps=4 format=3]

[ext_resource type="Texture2D" path="res://assets/textures/{name}.png" id="1_tex"]
[ext_resource type="Texture2D" path="res://assets/textures/{name}_n.png" id="2_nrm"]
[ext_resource type="Texture2D" path="res://assets/textures/{name}_r.png" id="3_rgh"]

[resource]
resource_name = "{name}"
albedo_texture = ExtResource("1_tex")
metallic = {metallic}
metallic_specular = {specular}
roughness = 1.0
roughness_texture = ExtResource("3_rgh")
roughness_texture_channel = 0
normal_enabled = true
normal_scale = {nscale}
normal_texture = ExtResource("2_nrm")
uv1_scale = Vector3({scale}, {scale}, {scale})
uv1_triplanar = true
uv1_world_triplanar = true
texture_filter = 5
"""

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (rough, metal, scale, spec) in MATERIALS.items():
        path = os.path.join(OUT, name + ".tres")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(TEMPLATE.format(name=name, nscale=NORMAL_SCALE.get(name, 1.0), metallic=metal, scale=scale, specular=spec))
        print("wrote", path)
