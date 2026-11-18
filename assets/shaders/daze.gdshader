shader_type canvas_item;
render_mode unshaded;
// "Shaken" vision after a flashbang: the picture (and with it the own arm and weapon) is seen twice, the ghost image drifts
// slowly like when drunk, plus a faint slow waviness and soft vignette. `amount` 0..1.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float a = amount;
	// slow wave warp
	vec2 warp = vec2(sin(uv.y * 7.0 + t * 1.3), cos(uv.x * 6.0 + t * 1.1)) * 0.004 * a;
	vec2 base = uv + warp;
	// the ghost image drifts in a slow ellipse
	vec2 off = vec2(sin(t * 0.9), cos(t * 0.7) * 0.6) * 0.022 * a;
	vec3 c0 = texture(screen_tex, base).rgb;
	vec3 c1 = texture(screen_tex, base + off).rgb;
	vec3 c2 = texture(screen_tex, base - off * 0.6).rgb;
	vec3 col = mix(c0, (c1 + c2) * 0.5, 0.55 * a);
	// slight blur from the ghosts + dark vignette
	float d = length((uv - 0.5) * vec2(1.0, 1.2));
	col *= 1.0 - smoothstep(0.35, 0.9, d) * 0.35 * a;
	COLOR = vec4(col, 1.0);
}
