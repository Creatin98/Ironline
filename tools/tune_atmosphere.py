"""Writes the per-map atmosphere (sky, ambient, fog, post, sun) into the map scenes. Run from the project root."""
import re

COMMON_ENV = {
    "ssao_radius": "1.6", "ssao_intensity": "2.0", "ssao_power": "1.6", "ssao_detail": "0.6",
    "glow_intensity": "0.28", "glow_bloom": "0.0", "glow_hdr_threshold": "1.25", "glow_hdr_scale": "2.0",
    "fog_sun_scatter": "0.12", "fog_aerial_perspective": "0.25", "fog_sky_affect": "0.6",
    "volumetric_fog_enabled": "true", "volumetric_fog_length": "70.0", "volumetric_fog_ambient_inject": "0.0",
    "volumetric_fog_anisotropy": "0.55", "volumetric_fog_detail_spread": "2.0",
    "tonemap_mode": "3", "adjustment_enabled": "true", "adjustment_brightness": "1.0",
}
MAPS = {
    "harbor": {
        "sky": {"sky_top_color": "Color(0.13, 0.33, 0.68, 1)", "sky_horizon_color": "Color(0.64, 0.77, 0.88, 1)", "sky_curve": "0.14",
                "ground_horizon_color": "Color(0.42, 0.58, 0.68, 1)", "ground_bottom_color": "Color(0.06, 0.16, 0.26, 1)"},
        "env": {"ambient_light_color": "Color(0.64, 0.68, 0.74, 1)", "ambient_light_sky_contribution": "0.45", "ambient_light_energy": "1.0", "fog_density": "0.0042", "fog_light_color": "Color(0.62, 0.76, 0.88, 1)",
                "volumetric_fog_density": "0.0035", "volumetric_fog_albedo": "Color(0.78, 0.86, 0.94, 1)",
                "adjustment_contrast": "1.12", "adjustment_saturation": "1.06", "tonemap_exposure": "1.0", "tonemap_white": "5.0"},
        "sun": {"light_color": "Color(1, 0.95, 0.86, 1)", "light_energy": "1.4"},
    },
    "frontier": {
        "sky": {"sky_top_color": "Color(0.25, 0.42, 0.72, 1)", "sky_horizon_color": "Color(0.9, 0.78, 0.6, 1)", "sky_curve": "0.12",
                "ground_horizon_color": "Color(0.72, 0.6, 0.45, 1)", "ground_bottom_color": "Color(0.22, 0.17, 0.12, 1)"},
        "env": {"ambient_light_color": "Color(0.72, 0.66, 0.58, 1)", "ambient_light_sky_contribution": "0.5", "ambient_light_energy": "0.9", "fog_density": "0.0055", "fog_light_color": "Color(0.88, 0.76, 0.58, 1)",
                "volumetric_fog_density": "0.0045", "volumetric_fog_albedo": "Color(0.92, 0.82, 0.66, 1)",
                "adjustment_contrast": "1.16", "adjustment_saturation": "1.05", "tonemap_exposure": "1.0", "tonemap_white": "5.0"},
        "sun": {"light_color": "Color(1, 0.86, 0.66, 1)", "light_energy": "1.6"},
    },
    "suburb": {
        "sky": {"sky_top_color": "Color(0.3, 0.45, 0.72, 1)", "sky_horizon_color": "Color(0.93, 0.82, 0.72, 1)", "sky_curve": "0.14",
                "ground_horizon_color": "Color(0.6, 0.58, 0.55, 1)", "ground_bottom_color": "Color(0.16, 0.18, 0.15, 1)"},
        "env": {"ambient_light_color": "Color(0.68, 0.68, 0.7, 1)", "ambient_light_sky_contribution": "0.5", "ambient_light_energy": "0.95", "fog_density": "0.0035", "fog_light_color": "Color(0.8, 0.82, 0.86, 1)",
                "volumetric_fog_density": "0.003", "volumetric_fog_albedo": "Color(0.88, 0.86, 0.84, 1)",
                "adjustment_contrast": "1.1", "adjustment_saturation": "0.96", "tonemap_exposure": "1.0", "tonemap_white": "5.0"},
        "sun": {"light_color": "Color(1, 0.89, 0.74, 1)", "light_energy": "1.4"},
    },
    "mesa": {
        "sky": {"sky_top_color": "Color(0.2, 0.42, 0.78, 1)", "sky_horizon_color": "Color(0.95, 0.84, 0.68, 1)", "sky_curve": "0.13",
                "ground_horizon_color": "Color(0.7, 0.6, 0.48, 1)", "ground_bottom_color": "Color(0.3, 0.24, 0.17, 1)"},
        "env": {"ambient_light_color": "Color(0.74, 0.68, 0.6, 1)", "ambient_light_sky_contribution": "0.5", "ambient_light_energy": "0.95",
                "fog_density": "0.0032", "fog_light_color": "Color(0.9, 0.8, 0.64, 1)",
                "volumetric_fog_density": "0.0035", "volumetric_fog_albedo": "Color(0.95, 0.86, 0.7, 1)",
                "adjustment_contrast": "1.14", "adjustment_saturation": "1.1", "tonemap_exposure": "1.0", "tonemap_white": "5.0"},
        "sun": {"light_color": "Color(1, 0.9, 0.74, 1)", "light_energy": "1.55"},
    },
    "test_arena": {
        "sky": {"sky_top_color": "Color(0.22, 0.4, 0.78, 1)", "sky_horizon_color": "Color(0.72, 0.8, 0.9, 1)", "sky_curve": "0.15",
                "ground_horizon_color": "Color(0.55, 0.58, 0.62, 1)", "ground_bottom_color": "Color(0.14, 0.14, 0.16, 1)"},
        "env": {"ambient_light_color": "Color(0.66, 0.68, 0.72, 1)", "ambient_light_sky_contribution": "0.5", "ambient_light_energy": "0.95", "fog_density": "0.004", "fog_light_color": "Color(0.74, 0.8, 0.88, 1)",
                "volumetric_fog_density": "0.0032", "volumetric_fog_albedo": "Color(0.85, 0.88, 0.92, 1)",
                "adjustment_contrast": "1.1", "adjustment_saturation": "1.04", "tonemap_exposure": "1.0", "tonemap_white": "5.0"},
        "sun": {"light_color": "Color(1, 0.94, 0.84, 1)", "light_energy": "1.4"},
    },
}
SUN_EXTRA = {"shadow_normal_bias": "2.0", "shadow_bias": "0.08", "shadow_blur": "1.3", "directional_shadow_blend_splits": "true", "directional_shadow_max_distance": "110.0"}


def set_keys(block: str, values: dict) -> str:
    for k, v in values.items():
        pat = re.compile(r"^%s = .*$" % re.escape(k), re.M)
        if pat.search(block):
            block = pat.sub("%s = %s" % (k, v), block)
        else:
            block = block.rstrip("\n") + "\n%s = %s\n" % (k, v)
    return block


def edit_section(text: str, header: str, values: dict) -> str:
    m = re.search(r"(\[%s\]\n)(.*?)(?=\n\[|\Z)" % re.escape(header), text, re.S)
    assert m, header
    body = set_keys(m.group(2), values)
    return text[:m.start(2)] + body + text[m.end(2):]


for name, cfg in MAPS.items():
    path = "scenes/maps/%s.tscn" % name
    t = open(path, encoding="utf-8").read()
    t = edit_section(t, 'sub_resource type="ProceduralSkyMaterial" id="sky_mat"', cfg["sky"])
    env = dict(COMMON_ENV)
    env.update(cfg["env"])
    t = edit_section(t, 'sub_resource type="Environment" id="env"', env)
    sun = dict(SUN_EXTRA)
    sun.update(cfg["sun"])
    t = edit_section(t, 'node name="Sun" type="DirectionalLight3D" parent="."', sun)
    open(path, "w", encoding="utf-8", newline="\n").write(t)
    print("tuned", name)
