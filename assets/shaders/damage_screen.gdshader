shader_type canvas_item;
render_mode unshaded;
// One pass for the whole "damage" look: red-flash on a hit, dark bloody dirty edges, and below 25 % health tunnel
// vision, desaturation, chromatic aberration at the edges and a slow pulse. All inputs are driven by DamageFx.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float hit : hint_range(0.0, 1.0) = 0.0; // impulse of the last hits (decays fast)
uniform float low : hint_range(0.0, 1.0) = 0.0; // hurt (below ~60 % health)
uniform float crit : hint_range(0.0, 1.0) = 0.0; // critical (below 25 %), grows towards death
uniform float pulse : hint_range(0.0, 1.0) = 0.5; // slow heartbeat phase
uniform float t = 0.0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	float d = length(c * vec2(2.0, 1.7));
	float beat = (pulse - 0.5) * 2.0;
	// chromatic aberration at the edges (critical only)
	vec2 off = c * crit * 0.018 * smoothstep(0.3, 1.0, d);
	vec3 col = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), crit * 0.55 + low * 0.12);
	// tunnel vision / darker outer area, breathing with the pulse
	float tunnel = smoothstep(0.42, 1.2, d);
	col *= 1.0 - tunnel * (crit * 0.6 * (0.88 + 0.18 * beat) + low * 0.2);
	// bloody, dirty edges: grain, large stains and radial streaks
	float dirt = vnoise(uv * vec2(6.0, 9.0)) * 0.25 + vnoise(uv * vec2(34.0, 48.0)) * 0.4 + vnoise(uv * vec2(110.0, 140.0)) * 0.35;
	float streaks = vnoise(vec2(atan(c.y * 1.7, c.x * 2.0) * 7.0, d * 4.0));
	float edge = smoothstep(0.5 - 0.12 * low - 0.1 * crit, 1.1, d);
	float strength = clamp(hit * 1.0 + low * 0.6 + crit * 0.55 * (0.82 + 0.3 * beat), 0.0, 1.25);
	float a = edge * strength * (0.5 + 0.8 * dirt) * (0.7 + 0.6 * streaks);
	vec3 blood = mix(vec3(0.42, 0.015, 0.012), vec3(0.07, 0.0, 0.0), clamp(dirt * 0.9 + edge * 0.35, 0.0, 1.0));
	col = mix(col, blood, clamp(a, 0.0, 0.93));
	// gritty grime over the whole picture: mottled red-black stains (also towards the middle, but weaker), blood-spray
	// grain and pale dust specks, so nothing stands alone like a single mark
	float mott = vnoise(uv * vec2(3.2, 2.4) + 4.7) * 0.5 + vnoise(uv * vec2(9.0, 7.0) + 1.3) * 0.3 + vnoise(uv * vec2(26.0, 22.0)) * 0.2;
	float grime_amt = clamp(hit * 0.55 + low * 0.55 + crit * 0.4, 0.0, 1.0) * (0.3 + 0.7 * smoothstep(0.2, 0.95, d));
	float stain = smoothstep(0.5, 0.72, mott) * grime_amt;
	col = mix(col, mix(vec3(0.3, 0.012, 0.01), vec3(0.04, 0.0, 0.0), smoothstep(0.55, 0.85, mott)), stain * 0.62);
	float grain = vnoise(uv * vec2(190.0, 230.0));
	col = mix(col, vec3(0.2, 0.01, 0.008), smoothstep(0.74, 0.9, grain) * grime_amt * 0.7);
	float dust = vnoise(uv * vec2(140.0, 170.0) + 9.0);
	col = mix(col, vec3(0.78, 0.72, 0.68), smoothstep(0.9, 0.97, dust) * grime_amt * 0.15);
	// the instant red flash over the whole picture
	col = mix(col, vec3(0.6, 0.03, 0.02), hit * hit * 0.34 * (0.45 + 0.55 * edge));
	COLOR = vec4(col, 1.0);
}
