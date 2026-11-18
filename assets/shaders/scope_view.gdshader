shader_type canvas_item;
render_mode unshaded;
// Looking through a rifle scope: a round, sharp and zoomed picture (second camera, scope_tex) with a fine
// reticle (mil-dots, duplex posts), a dark lens edge; around it the normal, un-zoomed picture - heavily blurred
// and darkened, as the eye sees it past the scope. `open` (0..1) is the iris: the circle grows while aiming.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D scope_tex : filter_linear;
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 0.44; // of the screen height
uniform float aspect = 1.7778; // screen width / height
uniform float zoom_flash : hint_range(0.0, 1.0) = 0.0; // a short brightening when the zoom step changes

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0); // units of the screen height, origin = screen centre
	float iris = smoothstep(0.0, 1.0, open);
	float r = max(radius * iris, 0.0001);
	float d = length(p);

	// outside: the un-zoomed picture, blurred more and more while the scope opens
	float blur_px = 18.0 * iris + 0.01;
	vec3 blurred = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 2.399963;
		float rad = sqrt((float(i) + 0.5) / 16.0);
		blurred += texture(screen_tex, uv + vec2(cos(a), sin(a)) * rad * blur_px * SCREEN_PIXEL_SIZE).rgb;
	}
	blurred /= 16.0;
	vec3 base = texture(screen_tex, uv).rgb;
	vec3 outside = mix(base, blurred, smoothstep(0.0, 0.5, iris));
	// the scope tube shades the surroundings: darker towards the edges and right around the lens
	float shade = mix(1.0, 0.42, iris * smoothstep(0.0, 0.9, d / max(radius, 0.01)));
	shade *= mix(1.0, 0.55, iris * (1.0 - smoothstep(r, r + 0.10, d)));
	outside *= shade;

	// inside: the zoomed picture
	vec2 q = p / r; // -1..1 over the lens
	vec3 inside = texture(scope_tex, q * 0.5 + vec2(0.5)).rgb;
	float rr = length(q);
	inside *= mix(1.0, 0.5, smoothstep(0.55, 1.0, rr)); // lens vignette
	inside += vec3(zoom_flash * 0.25);

	// reticle: fine cross, thicker outer posts (duplex), mil-dots, a dot in the centre; widths in pixels
	float px = SCREEN_PIXEL_SIZE.y / r; // one pixel in lens units
	float thin = px * 0.9;
	float thick = px * 3.0;
	float arm = abs(q.x) > 0.20 ? thick : thin; // horizontal line
	float arm_v = abs(q.y) > 0.20 ? thick : thin; // vertical line
	float ret = 0.0;
	ret = max(ret, 1.0 - smoothstep(arm * 0.6, arm, abs(q.y)));
	ret = max(ret, 1.0 - smoothstep(arm_v * 0.6, arm_v, abs(q.x)));
	ret *= 1.0 - smoothstep(0.015, 0.03, rr) * 0.0; // the lines run through the centre
	for (int k = 1; k <= 4; k++) {
		float off = float(k) * 0.065;
		ret = max(ret, 1.0 - smoothstep(px * 1.4, px * 2.4, length(q - vec2(off, 0.0))));
		ret = max(ret, 1.0 - smoothstep(px * 1.4, px * 2.4, length(q + vec2(off, 0.0))));
		ret = max(ret, 1.0 - smoothstep(px * 1.4, px * 2.4, length(q - vec2(0.0, off))));
		ret = max(ret, 1.0 - smoothstep(px * 1.4, px * 2.4, length(q + vec2(0.0, off))));
	}
	ret = max(ret, 1.0 - smoothstep(px * 1.8, px * 3.0, rr));
	ret *= smoothstep(1.0, 0.97, rr); // the reticle ends at the lens edge
	inside = mix(inside, vec3(0.01, 0.01, 0.012), ret * 0.92);

	// lens edge: dark ring, softly anti-aliased
	float lens = 1.0 - smoothstep(1.0 - px * 1.5, 1.0, rr);
	float ring = smoothstep(0.972, 0.99, rr) * lens;
	inside = mix(inside, vec3(0.0), ring);
	vec3 col = mix(outside, inside, lens);
	COLOR = vec4(col, 1.0);
}
