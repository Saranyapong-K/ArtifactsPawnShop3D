extends CanvasLayer
## Always-visible player HUD (money, top right).
## Created by day_manager.gd. Call set_money(value) whenever money changes.

var _label: Label


func _ready() -> void:
	layer = 5   # below the dialogue/bargain UI (layer 10)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color("f5c542"))
	_label.add_theme_color_override("font_outline_color", Color("6b3a14"))
	_label.add_theme_constant_override("outline_size", 8)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # grows to the left, stays on screen
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_label.text = "Money: 0"


func set_money(value: int, animate: bool = true) -> void:
	_label.text = "Money: %d" % value
	if not animate:
		return
	await get_tree().process_frame
	_label.pivot_offset = _label.size / 2.0
	_label.scale = Vector2.ONE * 1.25
	create_tween().tween_property(_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
