shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float uv_scale = 0.5;
uniform float normal_strength = 1.35;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.58;
uniform float puddle_scale = 0.09;
uniform float dirt_bottom_strength : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

vec4 triplanar_tex(sampler2D tex, vec3 p, vec3 w) {
	vec4 x = texture(tex, p.zy * uv_scale);
	vec4 y = texture(tex, p.xz * uv_scale);
	vec4 z = texture(tex, p.xy * uv_scale);
	return x * w.x + y * w.y + z * w.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(world_nrm), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);

	vec3 base_col = triplanar_tex(albedo_tex, world_pos, w).rgb;
	vec3 base_nrm = triplanar_tex(normal_tex, world_pos, w).rgb;
	float base_rgh = triplanar_tex(rough_tex, world_pos, w).r;

	float up_mask = smoothstep(0.75, 0.98, world_nrm.y);
	float n = fbm(world_pos.xz * puddle_scale);
	float detail_n = fbm(world_pos.xz * puddle_scale * 3.7);
	float wetness = smoothstep(1.0 - puddle_amount, 1.0 - puddle_amount + 0.22, n * 0.75 + detail_n * 0.25) * up_mask;
	float puddle = smoothstep(0.65, 0.92, wetness);

	float wall_dirt = (1.0 - up_mask) * smoothstep(1.2, 0.0, fract(world_pos.y * 0.25)) * dirt_bottom_strength;

	vec3 final_col = base_col * tint_color.rgb * mix(1.0, 0.48, wetness) * (1.0 - wall_dirt * 0.45);
	ALBEDO = final_col;

	vec3 flat_nrm = vec3(0.5, 0.5, 1.0);
	NORMAL_MAP = mix(base_nrm, flat_nrm, puddle * 0.92);
	NORMAL_MAP_DEPTH = normal_strength;

	ROUGHNESS = mix(clamp(base_rgh * 0.9, 0.55, 0.95), 0.06, puddle);
	ROUGHNESS = mix(ROUGHNESS, 0.28, wetness * (1.0 - puddle));
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.75, wetness);
}
