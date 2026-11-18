shader_type sky;
// Dynamic sky for Mesa: gradient with warm horizon haze, three cloud layers (low cumulus, high cumulus, thin cirrus) that
// drift and whose coverage changes over time, a sun that is covered by clouds now and then (sun_cover, driven by MesaSky
// together with the sun light), silver linings, soft crepuscular rays around the sun and an HDR sun disc that blooms.
uniform vec3 zenith : source_color = vec3(0.06, 0.26, 0.78);
uniform vec3 mid_sky : source_color = vec3(0.22, 0.48, 0.92);
uniform vec3 horizon : source_color = vec3(0.92, 0.84, 0.7);
uniform vec3 ground : source_color = vec3(0.46, 0.4, 0.32);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.9, 0.72);
uniform vec3 fallback_sun_dir = vec3(0.49, 0.64, 0.59);
uniform float t = 0.0;            // seconds, set by MesaSky
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5; // weather: overall coverage
uniform float sun_cover : hint_range(0.0, 1.0) = 0.0;   // how much the sun is behind a cloud right now
uniform vec2 wind = vec2(1.0, 0.35);

float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); } // sin-free hash: stable on every GPU
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.07 + vec2(11.3, 7.1); a *= 0.5; }
	return s;
}

// plane projection of a sky direction (parallax: every layer sits at its own height)
vec2 proj(vec3 d, float height) { return d.xz / (d.y + height) ; }

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(fallback_sun_dir);
	float sdot = max(dot(dir, sd), 0.0);
	float up = clamp(dir.y, 0.0, 1.0);

	// base gradient, a warm band at the horizon and a brighter glow around the sun
	vec3 col = mix(horizon, mid_sky, smoothstep(0.0, 0.22, up));
	col = mix(col, zenith, smoothstep(0.18, 0.85, up));
	col += sun_tint * pow(sdot, 5.0) * 0.16 + sun_tint * pow(sdot, 40.0) * 0.28;

	// clouds (only above the horizon, fading into the haze)
	float fade = smoothstep(0.02, 0.28, dir.y);
	float cloud_total = 0.0;
	vec3 cloud_col = vec3(0.0);
	if (dir.y > 0.0) {
		float cov = cloud_cover;
		// layer 1: low, heavy cumulus, slow
		vec2 p1 = proj(dir, 0.22) * 1.7 + wind * t * 0.006;
		float n1 = fbm(p1);
		float n1s = fbm(p1 + sd.xz * 0.12);
		float d1 = smoothstep(0.62 - cov * 0.34, 0.8 - cov * 0.3, n1);
		float lit1 = clamp(0.5 + (n1 - n1s) * 3.6, 0.0, 1.0);
		// layer 2: higher, smaller cumulus, faster, a different direction
		vec2 p2 = proj(dir, 0.5) * 3.0 + wind.yx * t * 0.011 + 31.0;
		float n2 = fbm(p2);
		float d2 = smoothstep(0.64 - cov * 0.3, 0.82 - cov * 0.26, n2) * 0.8;
		float lit2 = clamp(0.55 + (n2 - fbm(p2 + sd.xz * 0.2)) * 3.0, 0.0, 1.0);
		// layer 3: thin streaky cirrus
		vec2 p3 = proj(dir, 0.9) * vec2(1.2, 4.0) + wind * t * 0.003 + 77.0;
		float d3 = smoothstep(0.5, 0.95, fbm(p3)) * 0.45 * (1.0 - cov * 0.4);
		// the sun is covered (or free) as MesaSky says: a big cloud grows around the sun direction
		float halo = smoothstep(0.86, 0.985, sdot);
		float sun_cloud = sun_cover * halo * (0.75 + 0.25 * vnoise(proj(dir, 0.2) * 9.0 + t * 0.02));
		d1 = max(d1, sun_cloud);
		d2 = max(d2, sun_cloud * 0.7);
		vec3 shade = vec3(0.44, 0.5, 0.64);
		vec3 lit = vec3(1.0, 0.95, 0.86);
		vec3 c1 = mix(shade, lit, lit1);
		vec3 c2 = mix(shade * 1.1, lit, lit2);
		// silver lining: thin edges towards the sun glow
		float rim1 = (1.0 - d1) * smoothstep(0.35, 0.8, n1) * pow(sdot, 4.0);
		c1 += sun_tint * rim1 * 1.4 * (1.0 - sun_cover * 0.5);
		float a3 = d3 * fade;
		float a2 = d2 * fade;
		float a1 = d1 * fade;
		col = mix(col, vec3(0.92, 0.94, 1.0) + sun_tint * pow(sdot, 6.0) * 0.4, a3);
		col = mix(col, c2, a2);
		col = mix(col, c1, a1);
		cloud_total = clamp(a1 + a2 * 0.8 + a3 * 0.3, 0.0, 1.0);
	}

	// crepuscular rays: angular streaks around the sun, strongest when clouds partly cover it
	vec3 rr = normalize(cross(vec3(0.0, 1.0, 0.0), sd));
	vec3 uu = cross(sd, rr);
	vec2 loc = vec2(dot(dir, rr), dot(dir, uu));
	float ang = atan(loc.y, loc.x);
	float rays = pow(vnoise(vec2(ang * 7.0, t * 0.02)), 3.0) * 0.6 + pow(vnoise(vec2(ang * 17.0 + 5.0, t * 0.03)), 4.0) * 0.4;
	float partial = clamp(sun_cover * 2.0, 0.0, 1.0) * (1.0 - sun_cover * 0.6) + 0.25;
	col += sun_tint * rays * pow(sdot, 3.0) * 0.45 * partial * (dir.y > -0.05 ? 1.0 : 0.0);

	// sun disc + corona (HDR so it blooms), hidden behind clouds
	if (dir.y > -0.02) {
		float disc = smoothstep(0.99955, 0.99985, sdot);
		float sun_vis = (1.0 - cloud_total) * (1.0 - sun_cover);
		col += sun_tint * disc * 14.0 * sun_vis;
		col += sun_tint * pow(sdot, 220.0) * 2.4 * sun_vis;
	}

	// ground below the horizon blends to the haze colour so there is no hard line
	if (dir.y < 0.0) {
		float k = smoothstep(0.0, -0.35, dir.y);
		col = mix(horizon * 0.96, ground, k);
	} else {
		col = mix(col, horizon, (1.0 - smoothstep(0.0, 0.07, dir.y)) * 0.6);
	}
	COLOR = col;
}
