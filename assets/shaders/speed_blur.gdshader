shader_type canvas_item;
render_mode unshaded;
// Motion blur at the screen edges while sprinting: a radial blur towards the centre that only grows at the border.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float edge = smoothstep(0.32, 0.75, length(dir * vec2(1.0, 1.1)));
	vec3 col = texture(screen_tex, uv).rgb;
	float w = amount * edge * 0.06;
	vec3 sum = col;
	for (int i = 1; i <= 5; i++) {
		sum += texture(screen_tex, uv - dir * w * float(i)).rgb;
	}
	COLOR = vec4(mix(col, sum / 6.0, clamp(amount * edge * 1.4, 0.0, 1.0)), 1.0);
}
