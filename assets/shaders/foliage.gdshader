shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Foliage with wind: fronds (alpha cut, sway grows towards the tip) and bushes (sway grows with height).
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool alpha_mode = true;
uniform float sway = 0.14;
uniform float wind_speed = 1.1;
uniform float tex_scale = 1.0;

void vertex() {
	float w = alpha_mode ? UV.y : clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wind_speed;
	float gust = sin(t + wp.x * 0.33 + wp.z * 0.27) + 0.5 * sin(t * 2.3 + wp.x * 0.9 + wp.z * 0.5);
	float flutter = sin(t * 4.1 + wp.x * 2.0 + wp.z * 1.7) * 0.25;
	VERTEX.x += (gust + flutter) * sway * w * w;
	VERTEX.z += cos(t * 0.8 + wp.z * 0.4) * sway * 0.6 * w * w;
	VERTEX.y -= abs(gust) * sway * 0.25 * w * w;
}

void fragment() {
	vec4 c = texture(tex, UV * tex_scale);
	ALBEDO = c.rgb * tint * COLOR.rgb * 0.78;
	if (alpha_mode) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	BACKLIGHT = ALBEDO * 0.12;
}
