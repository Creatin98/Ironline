class_name DeathSkull
extends RefCounted
## A subtle skull that floats above a fallen teammate for a few seconds (visible through walls,
## like in Call of Duty). Procedural pixel-art texture, no assets.

const LIFETIME := 3.0
const PATTERN: Array[String] = [
	"....########....",
	"..############..",
	".##############.",
	".##############.",
	"################",
	"###..######..###",
	"###..######..###",
	"###...####...###",
	".######..######.",
	"..############..",
	"....########....",
	"....#.#..#.#....",
	"....#.#..#.#....",
	"....########....",
]

static var _texture: ImageTexture


static func texture() -> ImageTexture:
	if _texture == null:
		var w := 16
		var h := PATTERN.size()
		var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8) # 1 px border for the outline
		img.fill(Color(0, 0, 0, 0))
		for y in h:
			for x in w:
				if PATTERN[y][x] == "#":
					for oy in [-1, 0, 1]:
						for ox in [-1, 0, 1]:
							var px: int = x + 1 + ox
							var py: int = y + 1 + oy
							if img.get_pixel(px, py).a < 0.5:
								img.set_pixel(px, py, Color(0.05, 0.05, 0.06, 0.9))
		for y in h:
			for x in w:
				if PATTERN[y][x] == "#":
					img.set_pixel(x + 1, y + 1, Color(0.95, 0.95, 0.92, 1.0))
		img.resize((w + 2) * 3, (h + 2) * 3, Image.INTERPOLATE_NEAREST)
		_texture = ImageTexture.create_from_image(img)
	return _texture


## Spawns the marker at `pos` (world) below `parent`.
static func spawn(parent: Node, pos: Vector3) -> void:
	var s := Sprite3D.new()
	s.texture = texture()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true # visible through walls
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = 0.0085
	s.modulate = Color(1, 1, 1, 0)
	s.render_priority = 10
	parent.add_child(s)
	s.global_position = pos
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "global_position:y", pos.y + 0.35, LIFETIME)
	tw.tween_property(s, "modulate:a", 0.5, 0.35)
	tw.chain().tween_interval(LIFETIME - 1.35)
	tw.chain().tween_property(s, "modulate:a", 0.0, 1.0)
	tw.chain().tween_callback(s.queue_free)
