class_name MesaSky
extends Node
## Dynamic weather and sky of Mesa. Replaces the procedural sky by `mesa_sky.gdshader` and drives it: the cloud cover
## drifts slowly between airy and overcast, clouds sometimes pass in front of the sun. That moment dims the sun light
## (soft shadows weaken), tints it cooler, lowers the bloom, fades the lens flare and the sky draws a matching cloud
## around the sun - the shader gets the same `sun_cover` value, so picture and light always agree. Purely cosmetic and
## local (every machine runs its own sky). Needs a WorldEnvironment and a DirectionalLight3D named "Sun" in the map.

const SHADER := "res://assets/shaders/mesa_sky.gdshader"

var _mat: ShaderMaterial
var _env: Environment
var _sun: DirectionalLight3D
var _t: float = 0.0
var _sun_energy: float = 1.7
var _sun_color: Color = Color.WHITE
var _ambient: float = 0.95
var _glow: float = 0.5
var _cover: float = 0.0 # smoothed sun cover
var _t0: float = 0.0
## Per-map look (colours of the gradient, range of the cloud cover, weather speed). Empty = the shader defaults (Mesa).
var preset: Dictionary = {}


func _ready() -> void:
	_t0 = randf() * 600.0 # every round starts with a different sky
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if we == null or we.environment == null or _sun == null or not ResourceLoader.exists(SHADER):
		set_process(false)
		return
	_env = we.environment
	_sun_energy = _sun.light_energy
	_sun_color = _sun.light_color
	_ambient = _env.ambient_light_energy
	_glow = _env.glow_intensity
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	for k in preset.get("colors", {}):
		var c: Color = preset["colors"][k]
		_mat.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_sun.set_meta("clear", 1.0)
	_update(0.0)


func _process(delta: float) -> void:
	_t += delta
	_update(delta)
	_move_shadows(delta)


## Cloud shadows: large soft dark blobs (Decals, projected onto the ground and buildings) that drift with the wind; they match
## the cloud cover (more and darker shadows when it is cloudy) and wrap around at the edge of the area.
var _shadows: Array = []


func _build_shadows() -> void:
	var tex := _blob_texture()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in 5:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(rng.randf_range(50.0, 80.0), 40.0, rng.randf_range(34.0, 56.0))
		d.albedo_mix = 1.0
		d.modulate = Color(0.04, 0.05, 0.08, 0.0)
		d.upper_fade = 0.0
		d.lower_fade = 0.0
		d.cull_mask = 0xFFFFF
		d.position = Vector3(rng.randf_range(-70.0, 70.0), 12.0, rng.randf_range(-45.0, 45.0))
		d.rotation.y = rng.randf() * TAU
		get_parent().add_child(d)
		_shadows.append({"node": d, "speed": rng.randf_range(1.6, 3.2), "base": rng.randf_range(0.35, 0.6)})


func _move_shadows(delta: float) -> void:
	if _shadows.is_empty():
		_build_shadows()
	var cover: float = _mat.get_shader_parameter("cloud_cover")
	for sh in _shadows:
		var d: Decal = sh["node"]
		d.position += Vector3(1.0, 0.0, 0.35).normalized() * float(sh["speed"]) * delta
		if d.position.x > 90.0:
			d.position.x = -90.0
			d.position.z = randf_range(-45.0, 45.0)
		var edge := clampf((90.0 - absf(d.position.x)) / 25.0, 0.0, 1.0) # fades in and out while wrapping
		var want := float(sh["base"]) * clampf((cover - 0.25) * 2.2, 0.0, 1.0) * (1.0 - 0.6 * _cover) * edge
		d.modulate.a = lerpf(d.modulate.a, want, minf(1.0, delta * 1.5))


static func _blob_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.022
	noise.fractal_octaves = 4
	for y in n:
		for x in n:
			var p := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0)
			var fall := clampf(1.0 - p.length(), 0.0, 1.0)
			var v := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a := smoothstep(0.38, 0.72, v) * smoothstep(0.0, 0.5, fall)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Weather: slow cycle of the overall cloud cover (a few minutes) and, on top of it, clouds that cross the sun.
func _update(delta: float) -> void:
	var tt := _t + _t0
	var weather := 0.5 + 0.5 * (0.7 * sin(tt * 0.021) + 0.3 * sin(tt * 0.047 + 1.3)) # 0..1
	var cover_range: Vector2 = preset.get("cover", Vector2(0.3, 0.72))
	var cloud_cover := lerpf(cover_range.x, cover_range.y, weather)
	# a cloud reaches the sun when the cover is high enough, and then passes within ~40 s
	var passing := sin(tt * 0.11) + 0.6 * sin(tt * 0.173 + 0.7) + 0.35 * sin(tt * 0.29 + 2.1)
	var target := smoothstep(0.35 - 0.6 * (weather - 0.5), 1.15 - 0.6 * (weather - 0.5), passing)
	_cover = lerpf(_cover, target, minf(1.0, delta * 0.8) if delta > 0.0 else 1.0)
	_mat.set_shader_parameter("t", tt)
	_mat.set_shader_parameter("cloud_cover", cloud_cover)
	_mat.set_shader_parameter("sun_cover", _cover)
	var clear := 1.0 - _cover
	_sun.light_energy = _sun_energy * lerpf(0.42, 1.0, clear)
	_sun.light_color = _sun_color.lerp(Color(0.86, 0.9, 1.0), _cover * 0.6)
	_sun.set_meta("clear", clear)
	_env.ambient_light_energy = _ambient * lerpf(1.1, 0.95, clear)
	_env.glow_intensity = _glow * lerpf(0.7, 1.15, clear)
