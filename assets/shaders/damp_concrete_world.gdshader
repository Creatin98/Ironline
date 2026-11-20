shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform sampler2D roof_mask_tex : filter_linear, repeat_disable;
global uniform vec4 roof_bounds;
global uniform float rain_wetness;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 uv1_scale = vec3(0.5, 0.5, 0.5);

uniform float normal_scale = 1.25;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.68;
uniform float puddle_scale = 0.09;
uniform float dirt_bottom_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fast_fbm(vec2 p) {
	return noise(p) * 0.65 + noise(p * 2.3) * 0.35;
}

vec2 rain_ripples(vec2 uv, float t) {
	vec2 p = uv * 2.6;
	vec2 n = floor(p);
	vec2 f = fract(p);
	vec2 ripple_nrm = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g);
			float phase = fract(t * 0.85 + o.x * 6.28);
			vec2 r = g + o - f;
			float d = length(r);
			float ring = sin((d - phase * 0.75) * 38.0) * exp(-d * 6.0) * (1.0 - phase);
			ring *= smoothstep(0.0, 0.08, phase) * smoothstep(0.75, 0.15, d);
			ripple_nrm += normalize(r + 0.0001) * ring;
		}
	}
	return ripple_nrm;
}

vec4 triplanar_tex(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy * uv1_scale.xy) * w.x
		 + texture(tex, p.xz * uv1_scale.xz) * w.y
		 + texture(tex, p.xy * uv1_scale.xy) * w.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = abs(world_nrm);
	w = w / (w.x + w.y + w.z + 0.0001);

	vec3 base_col = triplanar_tex(albedo_texture, world_pos, w).rgb;
	vec3 base_nrm = triplanar_tex(normal_texture, world_pos, w).rgb;
	float base_rgh = triplanar_tex(roughness_texture, world_pos, w).r;

	// Fallback-Betonstruktur falls eine Textur ungesetzt (weiss) ist
	float grain = fast_fbm(world_pos.xz * 2.5) * 0.18 + fast_fbm(world_pos.xz * 12.0) * 0.08;
	if (length(base_col) > 1.65) {
		base_col = vec3(0.46, 0.45, 0.43) - vec3(grain);
	}

	vec2 mask_uv = (world_pos.xz - roof_bounds.xy) / max(roof_bounds.zw, vec2(1.0));
	float exposed = 1.0;
	if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
		float max_roof_y = texture(roof_mask_tex, mask_uv).r * 40.0 - 5.0;
		exposed = smoothstep(0.9, 0.25, clamp((max_roof_y - world_pos.y) / 1.5, 0.0, 1.0));
	}

	float up_mask = smoothstep(0.75, 0.98, world_nrm.y) * exposed;
	float n = fast_fbm(world_pos.xz * puddle_scale);
	float wetness = smoothstep(1.0 - puddle_amount, 1.0 - puddle_amount + 0.22, n) * up_mask;
	float puddle = smoothstep(0.60, 0.90, wetness);

	float wall_dirt = (1.0 - smoothstep(0.75, 0.98, world_nrm.y)) * smoothstep(1.2, 0.0, fract(world_pos.y * 0.25)) * dirt_bottom_strength;

	ALBEDO = base_col * tint_color.rgb * mix(0.95, 0.54, wetness) * (1.0 - wall_dirt * 0.35);

	// Regentropfen-Ringe plätschern NUR wenn es tatsächlich regnet (rain_wetness > 0)!
	vec2 rip = rain_ripples(world_pos.xz, TIME) * 0.22 * puddle * clamp(rain_wetness, 0.0, 1.0);
	vec3 water_nrm = vec3(0.5 + rip.x, 0.5 + rip.y, 1.0);
	NORMAL_MAP = mix(base_nrm, water_nrm, puddle * 0.92);
	NORMAL_MAP_DEPTH = normal_strength;

	ROUGHNESS = mix(clamp(base_rgh * 0.85, 0.55, 0.90), 0.06, puddle);
	ROUGHNESS = mix(ROUGHNESS, 0.24, wetness * (1.0 - puddle));
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.75, wetness);
}
