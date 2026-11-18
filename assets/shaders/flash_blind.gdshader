shader_type canvas_item;
render_mode unshaded;
// Full screen "flashed" look: the scene is blurred, washed out and brightened, a dark retinal afterimage sits where
// the light was, and the whole picture melts into white (white = 1).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float white : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform float wash : hint_range(0.0, 1.0) = 0.0;
uniform vec2 spot = vec2(0.5, 0.5);
uniform float spot_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float spot_size = 0.2;

void fragment() {
	vec2 uv = SCREEN_UV;
	float radius = blur * 26.0;
	vec3 c = vec3(0.0);
	for (int i = 0; i < 13; i++) {
		float a = float(i) * 2.399963; // golden angle spiral = cheap disc blur
		float r = sqrt((float(i) + 0.5) / 13.0);
		c += texture(screen_tex, uv + vec2(cos(a), sin(a)) * r * radius * SCREEN_PIXEL_SIZE).rgb;
	}
	c /= 13.0;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(luma), wash * 0.55) + vec3(wash * 0.32);
	vec2 d = (uv - spot) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float blot = smoothstep(spot_size, spot_size * 0.2, length(d));
	c = mix(c, vec3(0.17, 0.10, 0.24), blot * spot_alpha);
	c = mix(c, vec3(1.0), white);
	COLOR = vec4(c, 1.0);
}
