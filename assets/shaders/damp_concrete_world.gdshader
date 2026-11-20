shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform sampler2D roof_mask_tex : filter_linear, repeat_disable;
global uniform vec4 roof_bounds;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float uv_scale = 0.5;
uniform float normal_strength = 1.25;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.68;
uniform float puddle_scale = 0.09;
uniform float dirt_bottom_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fast_fbm(vec2 p) {
	return noise(p) * 0.65 + noise(p * 2.3) * 0.35;
}

vec2 rain_ripples(vec2 uv, float t) {
	vec2 p = uv * 2.6;
	vec2 n = floor(p);
	vec2 f = fract(p);
	vec2 ripple_nrm = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g);
			float phase = fract(t * 0.85 + o.x * 6.28);
			vec2 r = g + o - f;
			float d = length(r);
			float ring = sin((d - phase * 0.75) * 38.0) * exp(-d * 6.0) * (1.0 - phase);
			ring *= smoothstep(0.0, 0.08, phase) * smoothstep(0.75, 0.15, d);
			ripple_nrm += normalize(r + 0.0001) * ring;
		}
	}
	return ripple_nrm;
}

vec4 triplanar_tex(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy * uv_scale) * w.x
		 + texture(tex, p.xz * uv_scale) * w.y
		 + texture(tex, p.xy * uv_scale) * w.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = abs(world_nrm);
	w = w / (w.x + w.y + w.z + 0.0001);

	vec3 base_col = triplanar_tex(albedo_tex, world_pos, w).rgb;
	vec3 base_nrm = triplanar_tex(normal_tex, world_pos, w).rgb;
	float base_rgh = triplanar_tex(rough_tex, world_pos, w).r;

	vec2 mask_uv = (world_pos.xz - roof_bounds.xy) / max(roof_bounds.zw, vec2(1.0));
	float exposed = 1.0;
	if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
		float max_roof_y = texture(roof_mask_tex, mask_uv).r * 40.0 - 5.0;
		exposed = smoothstep(0.9, 0.25, clamp((max_roof_y - world_pos.y) / 1.5, 0.0, 1.0));
	}

	float up_mask = smoothstep(0.75, 0.98, world_nrm.y) * exposed;
	float n = fast_fbm(world_pos.xz * puddle_scale);
	float wetness = smoothstep(1.0 - puddle_amount, 1.0 - puddle_amount + 0.22, n) * up_mask;
	float puddle = smoothstep(0.60, 0.90, wetness);

	float wall_dirt = (1.0 - smoothstep(0.75, 0.98, world_nrm.y)) * smoothstep(1.2, 0.0, fract(world_pos.y * 0.25)) * dirt_bottom_strength;

	ALBEDO = base_col * tint_color.rgb * mix(0.95, 0.54, wetness) * (1.0 - wall_dirt * 0.35);

	vec2 rip = rain_ripples(world_pos.xz, TIME) * 0.22 * puddle;
	vec3 water_nrm = vec3(0.5 + rip.x, 0.5 + rip.y, 1.0);
	NORMAL_MAP = mix(base_nrm, water_nrm, puddle * 0.92);
	NORMAL_MAP_DEPTH = normal_strength;

	ROUGHNESS = mix(clamp(base_rgh * 0.9, 0.55, 0.92), 0.07, puddle);
	ROUGHNESS = mix(ROUGHNESS, 0.26, wetness * (1.0 - puddle));
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.72, wetness);
}
Verwende Code mit Vorsicht.

Datei 3: scripts/maps/block_map.gd

1. Öffne scripts/maps/block_map.gd.
2. Scrolle nach unten bis zu der Zeile var _sun_light: DirectionalLight3D (direkt unter func _on_kill_zone_entered).
3. Markiere ab genau dieser Zeile var _sun_light: DirectionalLight3D alles bis ganz zum Ende der Datei und ersetze es durch diesen vollständigen Block:
gdscript
@export_enum("clear_day", "overcast_industrial", "tropical_storm") var atmosphere_preset: String = "clear_day"

var _sun_light: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _lightning_flash: ColorRect
var _lens_rain_rect: ColorRect
var _lens_rain_mat: ShaderMaterial
var _lightning_timer: float = 3.5
var _lightning_flash_val: float = 0.0
var _outdoors_blend: float = 1.0
var _last_cam_basis: Basis = Basis.IDENTITY
var _last_cam_pos: Vector3 = Vector3.ZERO
var _visor_flow: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	if atmosphere_preset != "tropical_storm":
		RenderingServer.global_shader_parameter_set("rain_wetness", 0.0)
		return

	_wind_time += delta
	var gust := 0.85 + 0.45 * sin(_wind_time * 1.1) + 0.30 * sin(_wind_time * 2.6)
	RenderingServer.global_shader_parameter_set("wind_dir", _wind_dir)
	RenderingServer.global_shader_parameter_set("wind_strength", gust)

	if _rain_mat != null:
		var slant := 11.5 * gust
		_rain_mat.direction = Vector3(_wind_dir.x * slant, -24.0, _wind_dir.y * slant).normalized()

	var cam := get_viewport().get_camera_3d()
	var outdoors := true
	if cam != null and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3.UP * 40.0)
		outdoors = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		var dt := maxf(delta, 0.001)
		var local_vel := cam.global_basis.inverse() * ((cam.global_position - _last_cam_pos) / dt)
		var yaw_delta := _last_cam_basis.z.cross(cam.global_basis.z).y / dt
		var pitch_delta := (cam.global_basis.z.y - _last_cam_basis.z.y) / dt
		var target_flow := Vector2(
			clampf(yaw_delta * 0.18 - local_vel.x * 0.04, -1.8, 1.8),
			clampf(1.0 + pitch_delta * 0.25 - local_vel.z * 0.03, 0.25, 2.5)
		)
		_visor_flow = _visor_flow.lerp(target_flow, minf(1.0, delta * 8.0))
		_last_cam_basis = cam.global_basis
		_last_cam_pos = cam.global_position

	var wet_rate := 1.4 if outdoors else 0.35
	_outdoors_blend = move_toward(_outdoors_blend, 1.0 if outdoors else 0.0, delta * wet_rate)
	RenderingServer.global_shader_parameter_set("rain_wetness", _outdoors_blend)

	if _lens_rain_mat != null:
		_lens_rain_mat.set_shader_parameter("intensity", _outdoors_blend * clampf(gust * 0.85, 0.4, 1.0))
		_lens_rain_mat.set_shader_parameter("flow_vel", _visor_flow)

	var storm_pulse := 0.5 + 0.5 * sin(_wind_time * 0.35)
	if _sun_light != null:
		var base_energy := lerpf(1.35, 2.25, storm_pulse)
		_sun_light.light_energy = base_energy + _lightning_flash_val * 3.5
		_sun_light.light_color = Color(0.78, 0.86, 1.0) if _lightning_flash_val > 0.1 else Color(0.95, 0.84, 0.72)

	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(5.0, 12.0)
		_lightning_flash_val = 1.0
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_seed", randf() * 100.0)

	if _lightning_flash_val > 0.0:
		var flicker := 1.0 if (_lightning_flash_val > 0.75 or (_lightning_flash_val > 0.35 and _lightning_flash_val < 0.55)) else 0.12
		var intensity := _lightning_flash_val * flicker
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_intensity", intensity)
		if _lightning_flash != null:
			_lightning_flash.color.a = intensity * 0.14 * (1.0 if outdoors else 0.0)
		_lightning_flash_val = maxf(0.0, _lightning_flash_val - delta * 2.4)
	else:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("lightning_intensity", 0.0)
		if _lightning_flash != null:
			_lightning_flash.color.a = 0.0


func _upgrade_cinematic_lighting() -> void:
	for n in find_children("*", "WorldEnvironment", true, false):
		if n.get_parent() != self:
			n.queue_free()

	var env_node: WorldEnvironment = null
	for child in get_children():
		if child is WorldEnvironment:
			env_node = child
			break
	if env_node == null:
		env_node = WorldEnvironment.new()
		add_child(env_node)
	if env_node.environment == null:
		env_node.environment = Environment.new()

	var env := env_node.environment
	env.tonemap_mode = 3
	env.tonemap_exposure = 1.0
	env.tonemap_white = 7.5

	env.ssr_enabled = true
	env.ssr_max_steps = 28
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.15
	env.ssil_enabled = false

	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.58, 0.62)
	env.ambient_light_energy = 1.65

	for child in get_children():
		if child is DirectionalLight3D:
			_sun_light = child
			_sun_light.shadow_enabled = true
			_sun_light.shadow_blur = 2.2
			_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun_light.directional_shadow_max_distance = 110.0

	if atmosphere_preset == "tropical_storm":
		_apply_tropical_storm(env)
	else:
		_apply_clean_daylight(env)


func _apply_clean_daylight(env: Environment) -> void:
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.24, 0.44, 0.72)
	mat.sky_horizon_color = Color(0.62, 0.70, 0.78)
	mat.ground_bottom_color = Color(0.25, 0.26, 0.28)
	mat.ground_horizon_color = Color(0.55, 0.60, 0.66)
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.62, 0.68, 0.75)
	env.fog_density = 0.22
	env.fog_depth_begin = 35.0
	env.fog_depth_end = 180.0

	if _sun_light != null:
		_sun_light.light_color = Color(1.0, 0.95, 0.88)
		_sun_light.light_energy = 1.85
		_sun_light.rotation_degrees = Vector3(-42.0, -45.0, 0.0)

	var dry_img := Image.create(4, 4, false, Image.FORMAT_RF)
	dry_img.fill(Color(1.0, 0.0, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("roof_mask_tex", ImageTexture.create_from_image(dry_img))


func _apply_tropical_storm(env: Environment) -> void:
	var cloud_code := "shader_type sky;\n" \
		+ "uniform float lightning_intensity = 0.0;\n" \
		+ "uniform float lightning_seed = 0.0;\n" \
		+ "float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }\n" \
		+ "float noise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y); }\n" \
		+ "float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.05 + vec2(2.1, 7.4); a *= 0.5; } return v; }\n" \
		+ "void sky() {\n" \
		+ "	vec3 d = normalize(EYEDIR);\n" \
		+ "	vec3 sun_dir = normalize(LIGHT0_DIRECTION);\n" \
		+ "	float h = clamp(d.y, 0.005, 1.0);\n" \
		+ "	vec2 uv = d.xz / (h + 0.16) * 0.85 + vec2(TIME * 0.045, TIME * 0.02);\n" \
		+ "	float c1 = fbm(uv);\n" \
		+ "	float c2 = fbm(uv * 2.7 - c1 * 0.9 + vec2(TIME * 0.03, 0.0));\n" \
		+ "	float storm = smoothstep(0.15, 0.85, c1 * 0.6 + c2 * 0.4);\n" \
		+ "	float sun_dot = max(dot(d, sun_dir), 0.0);\n" \
		+ "	vec3 abyss = vec3(0.10, 0.12, 0.16);\n" \
		+ "	vec3 slate = vec3(0.26, 0.30, 0.36);\n" \
		+ "	vec3 steel_rim = vec3(0.48, 0.52, 0.58);\n" \
		+ "	vec3 col = mix(slate, abyss, storm);\n" \
		+ "	col = mix(col, steel_rim, smoothstep(0.55, 0.92, c2) * (1.0 - storm * 0.5));\n" \
		+ "	float sun_break = pow(sun_dot, 5.0) * (1.15 - storm * 0.65);\n" \
		+ "	float sun_core = pow(sun_dot, 90.0) * 1.4;\n" \
		+ "	float anamorphic_streak = exp(-abs(d.y - sun_dir.y) * 28.0) * pow(sun_dot, 6.0) * 0.45;\n" \
		+ "	col += vec3(1.0, 0.84, 0.66) * (sun_break + sun_core + anamorphic_streak);\n" \
		+ "	vec3 horizon = mix(vec3(0.32, 0.35, 0.40), vec3(0.56, 0.48, 0.40), pow(sun_dot, 2.0));\n" \
		+ "	col = mix(horizon, col, smoothstep(0.0, 0.30, d.y));\n" \
		+ "	if (lightning_intensity > 0.001) {\n" \
		+ "		float bolt_x = fract(sin(lightning_seed) * 43758.5453) * 2.0 - 1.0;\n" \
		+ "		float jag = (noise(vec2(d.y * 20.0, lightning_seed)) - 0.5) * 0.08;\n" \
		+ "		float bolt = exp(-abs((d.x - bolt_x * 0.7) + jag) * 160.0) * smoothstep(0.02, 0.42, d.y) * (1.0 - smoothstep(0.42, 0.60, d.y));\n" \
		+ "		float glow = exp(-length(d.xz - vec2(bolt_x * 0.7, -0.4)) * 2.4) * (0.35 + 0.65 * (1.0 - storm));\n" \
		+ "		col += vec3(0.68, 0.80, 1.0) * lightning_intensity * (bolt * 4.5 + glow * 1.6);\n" \
		+ "	}\n" \
		+ "	COLOR = col;\n" \
		+ "}\n"

	var sky_shd := Shader.new()
	sky_shd.code = cloud_code
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shd
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.36, 0.39, 0.44)
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.48
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 110.0

	if _sun_light != null:
		_sun_light.light_color = Color(1.0, 0.86, 0.72)
		_sun_light.light_energy = 1.85
		_sun_light.rotation_degrees = Vector3(-24.0, -48.0, 0.0)

	_spawn_lightning_and_lens_overlay()
	_spawn_rain_particles()
	_spawn_jungle_backdrop()
	_bake_roof_dry_mask()


func _spawn_lightning_and_lens_overlay() -> void:
	if has_node("LightningLayer"):
		return
	var layer := CanvasLayer.new()
	layer.name = "LightningLayer"
	layer.layer = 5

	var lens_code := "shader_type canvas_item;\n" \
		+ "uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;\n" \
		+ "uniform float intensity = 0.0;\n" \
		+ "uniform vec2 flow_vel = vec2(0.0, 1.0);\n" \
		+ "vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }\n" \
		+ "vec3 drop_layer(vec2 uv, float scale, float speed, float t) {\n" \
		+ "	vec2 st = uv * scale;\n" \
		+ "	vec2 id = floor(st);\n" \
		+ "	vec2 rnd = hash2(id);\n" \
		+ "	float cycle = fract(t * speed * (0.6 + rnd.x * 0.7) + rnd.y * 6.28);\n" \
		+ "	float slide = smoothstep(0.28, 1.0, cycle);\n" \
