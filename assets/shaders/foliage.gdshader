shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_dir;
global uniform float wind_strength;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool alpha_mode = true;
uniform float sway = 0.14;
uniform float wind_speed = 1.4;
uniform float tex_scale = 1.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 dir = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(0.92, 0.38);

	float wave = dot(wp.xz, dir) * 0.28 - TIME * 3.08;
	float gust = 0.65 + 0.35 * sin(wave) + 0.22 * sin(wave * 2.3 + wp.x * 0.4);

	float tree_h = clamp(VERTEX.y / 6.0, 0.0, 1.0);
	float trunk_bend = (sway > 0.1) ? (tree_h * tree_h) : 0.0;
	vec3 trunk_offset = vec3(dir.x, 0.0, dir.y) * (gust * wind_strength * 0.34) * trunk_bend;
	trunk_offset.y -= abs(gust * wind_strength) * 0.06 * trunk_bend;

	float w = alpha_mode ? UV.y : clamp(1.0 - UV.y, 0.0, 1.0);
	float leaf_bend = w * w;
	float flutter = sin(TIME * 7.5 + wp.x * 3.1 + wp.z * 2.7) * 0.18;
	vec3 leaf_offset = vec3(dir.x, 0.0, dir.y) * (gust * wind_strength * 2.2 + flutter) * sway * leaf_bend;
	leaf_offset.y -= abs(gust * wind_strength) * sway * 0.45 * leaf_bend;

	vec3 total_world = trunk_offset + leaf_offset;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(total_world, 0.0)).xyz;
}

void fragment() {
	vec4 c = texture(tex, UV * tex_scale);
	ALBEDO = c.rgb * tint * COLOR.rgb * 0.75;
	if (alpha_mode) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	ROUGHNESS = 0.36;
	SPECULAR = 0.54;
	BACKLIGHT = ALBEDO * 0.16;
}
