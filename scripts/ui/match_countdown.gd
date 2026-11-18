class_name MatchCountdown
extends CanvasLayer
## Start of a match from the menu / lobby: the screen darkens, the chosen map appears as a card in the middle,
## a big 3-2-1 counts down (tick sounds), then a flash + light sweep and the card grows to the full screen -
## exactly the picture the loading screen shows next, so the hand-over is seamless (same as the end of a round).

const COUNT := 3
const SECOND := 1.0

var _root: Control
var _dim: ColorRect
var _title: Label
var _count: Label
var _flash: ColorRect
var _card: VoteCard


## Plays the whole sequence (await it). The caller frees the node once the loading screen is up.
func run(map_id: String) -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # no clicks while counting
	add_child(_root)
	var s := _root.get_viewport_rect().size
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.025, 0.035, 0.0)
	_root.add_child(_dim)
	var w := clampf(s.x * 0.3, 260.0, 620.0)
	var card_size := Vector2(w, w / VoteCard.ASPECT)
	var target := (s - card_size) * 0.5 + Vector2(0.0, s.y * 0.07)
	_card = VoteCard.new()
	_root.add_child(_card)
	_card.setup(map_id, String(GameDirector.get_map_info(map_id)["name"]), GameDirector.get_map_preview(map_id))
	_card.disabled = true
	_card.size = card_size
	_card.position = target + Vector2(0.0, 70.0)
	_card.pivot_offset = card_size * 0.5
	_card.modulate.a = 0.0
	_title = UITheme.label("MATCH STARTET", clampi(int(s.y * 0.045), 24, 56), UITheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_title.position = Vector2(0.0, target.y - s.y * 0.30)
	_title.size = Vector2(s.x, s.y * 0.07)
	_title.modulate.a = 0.0
	_root.add_child(_title)
	_count = UITheme.label("", clampi(int(s.y * 0.14), 60, 170), UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.position = Vector2(0.0, target.y - s.y * 0.22)
	_count.size = Vector2(s.x, s.y * 0.19)
	_count.pivot_offset = _count.size * 0.5
	_root.add_child(_count)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	# intro: the room darkens, the map card rises into the middle
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dim, "color:a", 0.86, 0.4)
	tw.tween_property(_card, "modulate:a", 1.0, 0.3)
	tw.tween_property(_card, "position", target, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_title, "modulate:a", 1.0, 0.4)
	AudioManager.play_ui("ui_back", -4.0)
	for i in range(COUNT, 0, -1):
		_count.text = str(i)
		_count.scale = Vector2(1.6, 1.6)
		_count.modulate.a = 1.0
		var pop := create_tween().set_parallel(true)
		pop.tween_property(_count, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(_count, "modulate:a", 0.55, SECOND * 0.95).set_delay(0.3)
		_card.scale = Vector2(1.035, 1.035) # a little beat on every second
		create_tween().tween_property(_card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		AudioManager.play_ui("countdown_tick", -1.0 if i > 1 else 1.0)
		await get_tree().create_timer(SECOND, true, false, true).timeout
	# go: flash, light sweep, then the card fills the screen
	_count.text = ""
	_title.text = "LOS!"
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.3, 1.3)
	var go := create_tween().set_parallel(true)
	go.tween_property(_title, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	go.tween_property(_flash, "color:a", 0.38, 0.06)
	go.chain().tween_property(_flash, "color:a", 0.0, 0.4)
	_card.play_shine(0.55)
	AudioManager.play_ui("countdown_go", -3.0)
	await get_tree().create_timer(0.45, true, false, true).timeout
	AudioManager.play_ui("round_start", -8.0)
	var grow := create_tween().set_parallel(true)
	grow.tween_property(_card, "position", Vector2.ZERO, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	grow.tween_property(_card, "size", s, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	grow.tween_property(_card, "expand", 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	grow.tween_property(_title, "modulate:a", 0.0, 0.35)
	await grow.finished
