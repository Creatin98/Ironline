shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Building glass: clear in the middle, reflective at grazing angles, slightly green at the edges, with a faint
// dirt layer. Bullet impacts (up to 8) are drawn procedurally as laminated-glass damage: a crater, radial cracks
// with forks, concentric ring cracks and a frosted halo. h0..h7 = (x, y, seed, strength), x/y in metres from the
// pane centre (y up).

uniform vec2 pane_size = vec2(1.2, 1.2);
uniform vec4 h0;
uniform vec4 h1;
uniform vec4 h2;
uniform vec4 h3;
uniform vec4 h4;
uniform vec4 h5;
uniform vec4 h6;
uniform vec4 h7;
uniform int hit_count = 0;
uniform float damage = 0.0;
uniform float variant = 0.0;
uniform vec3 tint : source_color = vec3(0.50, 0.70, 0.74);

varying vec3 lpos;

void vertex() {
	lpos = VERTEX; // pane space in metres (the box UVs are an atlas, so they are not used)
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

float spoke(vec2 d, vec2 dir, float len, float seed, float fk) {
	float along = dot(d, dir);
	if (along <= 0.0 || along > len) {
		return 0.0;
	}
	float wob = (vnoise(along * 22.0 + fk * 5.0 + seed * 9.0) - 0.5) * 0.02 * (0.5 + along * 2.0);
	float perp = abs(d.x * dir.y - d.y * dir.x + wob);
	float w = 0.0022 + 0.0040 / (1.0 + along * 14.0);
	return smoothstep(w, w * 0.25, perp) * (1.0 - smoothstep(len * 0.55, len, along));
}

float impact(vec2 p, vec4 h, out float frost) {
	vec2 d = p - h.xy;
	float r = length(d);
	float seed = h.z;
	float st = h.w;
	float reach = 0.16 + st * 0.95;
	frost = exp(-r * 8.0) * st;
	if (r > reach + 0.05) {
		return 0.0;
	}
	float c = 0.0;
	for (int k = 0; k < 11; k++) {
		float fk = float(k);
		float a = fk * 0.5712 + (hash11(seed * 13.0 + fk) - 0.5) * 0.4;
		vec2 dir = vec2(cos(a), sin(a));
		float len = reach * (0.45 + 0.55 * hash11(seed * 7.0 + fk * 3.1));
		c = max(c, spoke(d, dir, len, seed, fk));
		if (hash11(seed * 5.0 + fk * 1.7) > 0.35) {
			float side = hash11(fk * 3.0 + seed) > 0.5 ? 0.55 : -0.55;
			float fa = a + side;
			vec2 fdir = vec2(cos(fa), sin(fa));
			vec2 d2 = d - dir * (len * (0.22 + 0.2 * hash11(seed + fk * 2.0)));
			c = max(c, spoke(d2, fdir, len * 0.5, seed + 3.0, fk + 7.0));
		}
	}
	float ang = atan(d.y, d.x);
	for (int j = 1; j < 5; j++) {
		float fj = float(j);
		float rj = (0.04 * fj + 0.012 * fj * fj) * (0.8 + 0.4 * hash11(seed + fj));
		float rr = r + (vnoise(ang * 2.5 + seed * 3.0 + fj) - 0.5) * 0.012;
		float sector = step(0.35, hash11(floor((ang + 3.1416) / 0.7) + fj * 9.0 + seed * 4.0));
		float ring = smoothstep(0.0030, 0.0008, abs(rr - rj)) * sector * step(rj, reach * 0.8);
		c = max(c, ring);
	}
	c = max(c, 1.0 - smoothstep(0.006, 0.012, r)); // the crater
	return c;
}

void fragment() {
	vec2 p = lpos.xy;
	vec2 uv = p / pane_size + 0.5;
	vec4 hits[8] = vec4[8](h0, h1, h2, h3, h4, h5, h6, h7);
	float crack = 0.0;
	float frost = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= hit_count) {
			break;
		}
		float fr = 0.0;
		crack = max(crack, impact(p, hits[i], fr));
		frost = max(frost, fr);
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float grime = vnoise(p.x * 3.0 + variant * 20.0) * vnoise(p.y * 2.3 + variant * 7.0);
	float edge = 1.0 - smoothstep(0.0, 0.025, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	float dmg = clamp(crack + frost * 0.6, 0.0, 1.0);
	// soft diagonal sheen, like daylight sliding over a large pane
	float band = uv.x * 0.8 + (1.0 - uv.y) * 0.5 + variant * 0.4;
	float sheen = smoothstep(0.0, 0.25, fract(band * 0.9)) * (1.0 - smoothstep(0.25, 0.55, fract(band * 0.9)));
	ALBEDO = mix(tint * 0.30, vec3(0.93, 0.96, 0.98), clamp(crack * 0.85 + frost * 0.25, 0.0, 1.0));
	ALPHA = clamp(mix(0.14 + 0.05 * variant, 0.62, fres) + sheen * 0.07 + grime * 0.05 + crack * 0.75 + frost * 0.22 + edge * 0.28 + damage * 0.05, 0.0, 0.95);
	ROUGHNESS = mix(0.03, 0.4, dmg);
	SPECULAR = 1.0;
	METALLIC = 0.0;
}
