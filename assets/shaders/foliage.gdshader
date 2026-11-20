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
	float w = alpha_mode ? UV.y : clamp(1.0 - UV.y, 0.0, 1.0);
	float bend_factor = w * w;

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 dir = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(0.92, 0.38);

	// Durchlaufende Windböen-Wellen in Windrichtung über die ganze Map
	float wave_pos = dot(wp.xz, dir) * 0.28 - TIME * wind_speed * 2.2;
	float gust = 0.65 + 0.35 * sin(wave_pos) + 0.22 * sin(wave_pos * 2.3 + wp.x * 0.4);
	float flutter = sin(TIME * 7.5 + wp.x * 3.1 + wp.z * 2.7) * 0.18;

	// Bewegung im Welt-Raum berechnen und zurück in den lokalen Objekt-Raum drehen
	vec3 world_offset = vec3(dir.x, 0.0, dir.y) * (gust * wind_strength * 2.4 + flutter) * sway * bend_factor;
	world_offset.y -= abs(gust * wind_strength) * sway * 0.45 * bend_factor;

	vec3 local_offset = (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;
	VERTEX += local_offset;
}

void fragment() {
	vec4 c = texture(tex, UV * tex_scale);
	// Leicht abgedunkeltes, feuchtes Regen-Blattwerk
	ALBEDO = c.rgb * tint * COLOR.rgb * 0.72;
	if (alpha_mode) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	ROUGHNESS = 0.38;
	SPECULAR = 0.52;
	BACKLIGHT = ALBEDO * 0.14;
}
