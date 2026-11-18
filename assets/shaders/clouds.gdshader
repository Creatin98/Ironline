shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, shadows_disabled;
// A drifting layer of soft clouds high above the map (fbm noise, lit from the sun side), purely decorative.
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
uniform vec3 shade_color : source_color = vec3(0.62, 0.68, 0.8);
uniform float coverage = 0.46;
uniform float speed = 0.004;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
	return s;
}

void fragment() {
	vec2 uv = UV * 6.0 + vec2(TIME * speed, TIME * speed * 0.4);
	float n = fbm(uv);
	float n2 = fbm(uv + vec2(0.35, 0.2));
	float d = smoothstep(coverage, coverage + 0.22, n);
	float lit = clamp(0.5 + (n - n2) * 5.0, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.0, 0.45, abs(UV.x - 0.5) * 2.0 - 0.55) * 0.0;
	float fade = (1.0 - smoothstep(0.55, 1.0, length(UV - vec2(0.5)) * 2.0));
	ALBEDO = mix(shade_color, sun_color, lit);
	ALPHA = d * fade * 0.85;
}
