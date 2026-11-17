class_name LoadingScreen
extends CanvasLayer
## Loading screen between menu and match: a picture of the map, a funny shooter tip, a progress bar.
## The menu music keeps playing and fades out shortly before the end. Lives under the root window,
## so it survives the scene change to the game.

signal finished

const DURATION := 7.0
const MUSIC_FADE := 2.2
const TIPS: Array[String] = [
	"Tipp: Wer hinter der Kiste steht, ist nicht unsichtbar. Nur ein bisschen schlechter getroffen.",
	"Tipp: Nachladen mitten im Feuergefecht ist mutig. Meistens endet es im Respawn.",
	"Tipp: Die Granate hat einen Zünder. Bitte nicht ansehen, bis sie explodiert.",
	"Tipp: Bots haben auch Gefühle. Aber sie zielen trotzdem auf dich.",
	"Tipp: Kopfschüsse zählen mehr. Das Ziel zählt auch, wenn man in die Wand schießt.",
	"Tipp: Rennen ist schneller als Gehen. Wer hätte das gedacht.",
	"Tipp: Ducken macht dich kleiner, aber nicht weniger peinlich, wenn du trotzdem fällst.",
	"Tipp: Sprint + Ducken = eleganter Slide. Landen ist optional.",
	"Tipp: Wenn du alleine campst, ist das taktisch. Wenn dein Team campt, ist es ein Problem.",
	"Tipp: Die Minimap zeigt Schüsse. Schüsse zeigen dich. Ups.",
	"Tipp: Ein leeres Magazin ist ein sehr lauter Hinweis, dass du nachladen solltest.",
	"Tipp: Die Schrotflinte liebt die Nähe. Auf 50 Meter liebt sie nur den Himmel.",
	"Tipp: Wer zuerst schießt, trifft nicht zwingend zuerst. Wer zuerst trifft, schon.",
	"Tipp: Eine Pistole ist keine Notlösung. Sie ist eine Lebenseinstellung.",
	"Tipp: Lag ist immer schuld. Außer beim Training gegen Bots, da ist es Können.",
	"Tipp: Respawn bedeutet nicht Aufgeben. Es bedeutet Wiedergeburt mit Munition.",
	"Tipp: Schau öfter in die Ecken. Die Ecken schauen auch zurück.",
	"Tipp: Blut auf dem Bildschirm sieht dramatisch aus. Es hilft nicht beim Zielen.",
	"Tipp: Assists zählen auch. Ein halber Kill ist besser als ein ganzer Tod.",
	"Tipp: Wer Granaten wirft, sollte vorher wissen, wo er steht. Nach dem Wurf ist es zu spät.",
	"Tipp: Zieh die Waffe, bevor der Gegner um die Ecke kommt. Nicht danach.",
	"Tipp: Leertaste im Slide steht dich auf. Zweimal drücken springt. Dreimal drücken ist Panik.",
]

var _bg: TextureRect
var _tip: Label
var _bar_fill: ColorRect
var _bar_bg: ColorRect
var _percent: Label
var _title: Label
var _t := 0.0
var _tip_t := 0.0
var _tip_index := 0
var _music_fading := false
var _done := false
var _root: Control


func begin(map_id: String) -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color.BLACK
	_root.add_child(black)
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.texture = GameDirector.get_map_preview(map_id)
	_root.add_child(_bg)
	# darkening at the bottom, where the text sits
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -330.0
	shade.color = Color(0, 0, 0, 0.0)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.0, 0.75, UV.y) * 0.82); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	shade.material = mat
	_root.add_child(shade)
	var info := GameDirector.get_map_info(map_id)
	_title = UITheme.label(String(info["name"]).to_upper(), 64, UITheme.ACCENT)
	_title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_title.offset_left = 90.0
	_title.offset_top = -270.0
	_title.offset_bottom = -190.0
	_root.add_child(_title)
	_tip = UITheme.label("", 24, UITheme.TEXT)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_tip.offset_left = 90.0
	_tip.offset_right = -90.0
	_tip.offset_top = -180.0
	_tip.offset_bottom = -130.0
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_tip)
	_bar_bg = ColorRect.new()
	_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bg.offset_left = 90.0
	_bar_bg.offset_right = -90.0
	_bar_bg.offset_top = -80.0
	_bar_bg.offset_bottom = -64.0
	_bar_bg.color = Color(1, 1, 1, 0.14)
	_root.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UITheme.ACCENT
	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(0, 16)
	_bar_bg.add_child(_bar_fill)
	_percent = UITheme.label("0 %", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_percent.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_percent.offset_right = -90.0
	_percent.offset_top = -52.0
	_percent.offset_bottom = -24.0
	_root.add_child(_percent)
	_tip_index = randi() % TIPS.size()
	_tip.text = TIPS[_tip_index]
	_root.modulate.a = 1.0


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_tip_t += delta
	if _tip_t >= 3.4:
		_tip_t = 0.0
		_tip_index = (_tip_index + 1 + randi() % (TIPS.size() - 1)) % TIPS.size()
		_tip.text = TIPS[_tip_index]
	var x := clampf(_t / DURATION, 0.0, 1.0)
	var p := 1.0 - pow(1.0 - x, 1.6) # quick start, calm end
	_bar_fill.size.x = _bar_bg.size.x * p
	_percent.text = "%d %%" % int(round(p * 100.0))
	if not _music_fading and _t >= DURATION - MUSIC_FADE:
		_music_fading = true
		AudioManager.stop_music(MUSIC_FADE)
	if _t >= DURATION:
		_done = true
		finished.emit()
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 0.0, 0.6)
		tw.tween_callback(queue_free)
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
