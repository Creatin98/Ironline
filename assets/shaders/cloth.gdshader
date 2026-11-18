shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Banner / bunting cloth waving in the wind: fixed at the top (UV.y = 0) and at the pole side (UV.x = 0).
uniform vec3 color : source_color = vec3(0.7, 0.12, 0.1);
uniform vec3 stripe : source_color = vec3(0.95, 0.9, 0.8);
uniform float stripe_amount = 0.0;
uniform float amp = 0.18;
uniform float speed = 2.2;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float anchor = clamp(UV.y * 1.2 + UV.x * 0.6, 0.0, 1.0);
	float t = TIME * speed;
	float wave = sin(t + wp.x * 1.3 + wp.z * 0.9 + UV.y * 5.0) + 0.45 * sin(t * 2.2 + UV.y * 9.0 + wp.x);
	VERTEX.z += wave * amp * anchor;
	VERTEX.x += cos(t * 0.8 + UV.y * 3.0) * amp * 0.25 * anchor;
}

void fragment() {
	float s = step(0.5, fract(UV.y * 3.0));
	vec3 c = mix(color, stripe, s * stripe_amount);
	float fold = 0.88 + 0.12 * sin(UV.y * 40.0 + UV.x * 6.0);
	ALBEDO = c * fold;
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.25;
}
