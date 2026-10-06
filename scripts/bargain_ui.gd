class_name BargainUI
extends CanvasLayer
## All game UI, built in code: dialogue box, bargain panel, reveal/summary overlay.

signal offer_submitted(price: int)
signal accept_pressed
signal send_away_pressed
signal next_pressed
signal dialogue_advanced
signal count_finished   # internal: number counter reached its target

const GOLD := Color("f5c542")
const TAN := Color("e8b684")
const BROWN := Color("b8793f")
const DARK_BROWN := Color("6b3a14")
const CREAM := Color("fff1dc")

const DIALOGUE_CPS := 45.0   # typewriter speed, characters per second

# ---- Reveal counter tuning ----
const COUNT_MIN_SPEED := 15.0
const COUNT_GROWTH := 2.9
const COUNT_MAX_SPEED := 500.0
const BOUNCE_START := 200.0
const BOUNCE_TICK := 20.0

var _root: Control

# bargain panel
var _layout: VBoxContainer
var _bargain_panel: PanelContainer
var _content: VBoxContainer
var _ask_label: Label
var _sub_label: Label
var _offer_label: Label
var _slider: HSlider
var _btn_offer: Button
var _btn_accept: Button
var _btn_away: Button
var _nudge_buttons: Array[Button] = []
var _toggle: Button
var _panel_hidden := false
var _hide_tween: Tween
var _market_text := ""
var _flash_id := 0
var _tri_up: ImageTexture
var _tri_down: ImageTexture

# dialogue
var _dlg_layout: VBoxContainer
var _dlg_label: Label
var _dlg_hint: TextureRect
var _hint_tween: Tween
var _dlg_active := false
var _dlg_typing := false
var _dlg_started_ms := 0

# overlay (reveal / summary)
var _overlay: ColorRect
var _ov_title: Label
var _ov_value: Label
var _ov_sub: Label
var _ov_btn: Button

var _shake_tween: Tween
var _fx_tween: Tween
var _shake_strength := 0.0

# counter state
var _counting := false
var _count_target := 0.0
var _count_value := 0.0
var _count_time := 0.0
var _count_max_speed := COUNT_MAX_SPEED
var _last_tick := 0.0
var _tick_dir := 1.0


func _ready() -> void:
	layer = 10
	_tri_up = _triangle_tex(true)
	_tri_down = _triangle_tex(false)

	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_bargain_panel()
	_build_dialogue_panel()
	_build_toggle_and_money()
	_build_overlay()

	_layout.visible = false
	_dlg_layout.visible = false
	_toggle.visible = false

	_fit_panel()
	get_viewport().size_changed.connect(_fit_panel)


# ================= building =================

func _build_bargain_panel() -> void:
	var r := _bottom_layout(640, 14, 44)
	_layout = r[0]
	var panel: PanelContainer = r[1]
	_bargain_panel = panel

	var cc := CenterContainer.new()
	panel.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	cc.add_child(v)
	_content = v

	_ask_label = _outlined_label("", 40, Color.WHITE, BROWN, 10)
	v.add_child(_ask_label)
	_sub_label = _outlined_label("", 16, Color(1, 1, 1, 0.85), BROWN, 4)
	v.add_child(_sub_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	row.add_child(_nudge_button("-100", -100))
	row.add_child(_nudge_button("-10", -10))
	_offer_label = _outlined_label("", 24, Color.WHITE, BROWN, 6)
	_offer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_offer_label)
	row.add_child(_nudge_button("+10", 10))
	row.add_child(_nudge_button("+100", 100))

	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(0, 30)
	_slider.modulate = Color("9a5b2a")
	_slider.value_changed.connect(_on_slider_changed)
	v.add_child(_slider)

	var actions := HBoxContainer.new()
	v.add_child(actions)
	_btn_offer = _text_button("Offer", Color("e6c200"), 44)
	_btn_accept = _text_button("Accept", Color("2f9e44"), 44)
	_btn_away = _text_button("Reject", Color("d6283a"), 44)
	actions.add_child(_btn_offer)
	actions.add_child(_expander())
	actions.add_child(_btn_accept)
	actions.add_child(_expander())
	actions.add_child(_btn_away)
	_btn_offer.pressed.connect(func(): offer_submitted.emit(int(_slider.value)))
	_btn_accept.pressed.connect(func(): accept_pressed.emit())
	_btn_away.pressed.connect(func(): send_away_pressed.emit())


func _build_dialogue_panel() -> void:
	var r := _bottom_layout(1100, 30, 22)
	_dlg_layout = r[0]
	var panel: PanelContainer = r[1]
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # so a click reaches _unhandled_input

	var h := HBoxContainer.new()
	panel.add_child(h)

	_dlg_label = Label.new()
	_dlg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dlg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dlg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dlg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_label.custom_minimum_size = Vector2(900, 96)
	_dlg_label.add_theme_font_size_override("font_size", 42)
	_dlg_label.add_theme_color_override("font_color", Color("1b1b1b"))
	h.add_child(_dlg_label)

	_dlg_hint = TextureRect.new()
	_dlg_hint.texture = _tri_down
	_dlg_hint.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_dlg_hint.custom_minimum_size = Vector2(36, 36)
	_dlg_hint.pivot_offset = Vector2(18, 18)
	_dlg_hint.rotation = -PI / 2.0   # down arrow turned to point right
	_dlg_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dlg_hint.visible = false
	h.add_child(_dlg_hint)


func _build_toggle_and_money() -> void:
	_toggle = Button.new()
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.icon = _tri_down
	_toggle.custom_minimum_size = Vector2(60, 30)
	_root.add_child(_toggle)
	_toggle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 22)
	_toggle.pressed.connect(func(): _set_panel_hidden(not _panel_hidden, true))



func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.78)
	_root.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false

	var oc := CenterContainer.new()
	_overlay.add_child(oc)
	oc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 16)
	oc.add_child(ov)

	_ov_title = _outlined_label("", 48, GOLD, DARK_BROWN, 10)
	_ov_value = _outlined_label("", 96, Color.WHITE, DARK_BROWN, 14)
	_ov_value.custom_minimum_size = Vector2(700, 0)
	_ov_sub = _outlined_label("", 30, Color.WHITE, DARK_BROWN, 8)
	_ov_btn = _text_button("Next", GOLD, 44)
	_ov_btn.pressed.connect(func(): next_pressed.emit())

	ov.add_child(_ov_title)
	ov.add_child(_ov_value)
	ov.add_child(_ov_sub)
	ov.add_child(_ov_btn)


# ================= public API =================

## Typewriter line. Returns when the player presses E / Space to continue.
## (First press while typing = show the full line.)
func say(text: String) -> void:
	_overlay.visible = false   # the old reveal/summary must not stay on screen
	_counting = false
	_layout.visible = false
	_toggle.visible = false
	_dlg_layout.visible = true
	_dlg_label.text = text
	_dlg_label.visible_characters = 0
	_dlg_hint.visible = false
	_dlg_active = true
	_dlg_typing = true
	_dlg_started_ms = Time.get_ticks_msec()

	var shown := 0.0
	while _dlg_typing:
		await get_tree().process_frame
		shown += get_process_delta_time() * DIALOGUE_CPS
		_dlg_label.visible_characters = int(shown)
		if shown >= text.length():
			_dlg_typing = false
	_dlg_label.visible_characters = -1

	_dlg_hint.visible = true
	_start_hint_blink()
	await dialogue_advanced
	_stop_hint_blink()
	_dlg_active = false


func hide_dialogue() -> void:
	_dlg_active = false
	_dlg_layout.visible = false


func show_customer(_number: int, _total: int, money: int, market: int, ask: int, message: String) -> void:
	_overlay.visible = false
	_counting = false
	_root.position = Vector2.ZERO
	hide_dialogue()
	_layout.visible = true
	_toggle.visible = true
	_set_panel_hidden(false, false)

	_market_text = "market ~ %d" % market
	_sub_label.text = _market_text

	var lo := mini(int(market * 0.3), money)
	var hi := mini(int(market * 1.5), money)
	_slider.step = 1
	_slider.min_value = lo
	_slider.max_value = hi
	_slider.value = clampi(roundi(ask / 10.0) * 10, lo, hi)   # starts at the ask, rounded
	_on_slider_changed(_slider.value)

	_ask_label.text = "Ask for: %d" % ask
	if message != "":
		_flash_sub(message)
	set_controls_enabled(true)


func update_state(ask: int, _anger: float, message: String) -> void:
	_ask_label.text = "Ask for: %d" % ask
	_pop(_ask_label)
	if message != "":
		_flash_sub(message)


func show_message(text: String) -> void:
	_flash_sub(text)


func set_controls_enabled(enabled: bool) -> void:
	_btn_offer.disabled = not enabled
	_btn_accept.disabled = not enabled
	_btn_away.disabled = not enabled
	for b in _nudge_buttons:
		b.disabled = not enabled


## Balatro-style reveal: number accelerates, bounces past 200, then pop + shake.
func show_reveal(true_value: int, paid: int) -> void:
	set_controls_enabled(false)
	var profit := true_value - paid
	var ratio := float(profit) / maxf(1.0, float(paid))
	var power := clampf(ratio / 3.0, 0.0, 1.0)

	var verdict := "BAD DEAL"
	var color := Color("ff5a5a")
	if ratio >= 1.5:
		verdict = "JACKPOT!!!"
		color = GOLD
	elif ratio >= 0.5:
		verdict = "GREAT FIND!"
		color = Color("7dffb2")
	elif ratio >= 0.0:
		verdict = "FAIR DEAL"
		color = Color.WHITE

	_prepare_overlay("What is it worth?")
	_ov_btn.text = "Next customer"
	await get_tree().process_frame
	_ov_value.pivot_offset = _ov_value.size / 2.0

	_start_count(float(true_value))
	await count_finished

	_ov_title.text = verdict
	_ov_title.modulate = color
	_ov_value.modulate = color
	_ov_sub.text = "Paid %d   |   Profit %+d" % [paid, profit]

	var pop := 1.15 + 0.35 * power
	var p := create_tween()
	p.tween_property(_ov_value, "scale", Vector2.ONE * pop, 0.12)
	p.tween_property(_ov_value, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_shake(4.0 + 22.0 * power, 0.2 + 0.5 * power)
	if ratio >= 1.5:
		_rainbow(2.5)
	_ov_btn.visible = true


func show_summary(day_done: int, day_profit: int, money: int) -> void:
	set_controls_enabled(false)
	_prepare_overlay("DAY %d COMPLETE" % day_done)
	_ov_title.modulate = GOLD
	_ov_btn.text = "Start next day"
	await get_tree().process_frame
	_ov_value.pivot_offset = _ov_value.size / 2.0

	_start_count(float(day_profit))
	await count_finished

	_ov_value.modulate = Color("ff5a5a") if day_profit < 0 else Color.WHITE
	_ov_sub.text = "Day profit  |  Money: %d  (saved)" % money
	var p := create_tween()
	p.tween_property(_ov_value, "scale", Vector2.ONE * 1.2, 0.12)
	p.tween_property(_ov_value, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_shake(8.0, 0.3)
	_ov_btn.visible = true


# ================= input =================

func _unhandled_input(event: InputEvent) -> void:
	if not _dlg_active:
		return
	# ignore the very same E press that started the conversation
	if Time.get_ticks_msec() - _dlg_started_ms < 250:
		return
	var advance := event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true   # left click also continues
	if advance:
		get_viewport().set_input_as_handled()
		if _dlg_typing:
			_dlg_typing = false
		else:
			dialogue_advanced.emit()


# ================= counter (exponential speed-up + bounce) =================

func _start_count(target: float) -> void:
	_count_target = target
	_count_value = 0.0
	_count_time = 0.0
	_last_tick = 0.0
	_count_max_speed = maxf(COUNT_MAX_SPEED, absf(target) / 2.0)
	_counting = true


func _process(delta: float) -> void:
	if not _counting:
		return

	_count_time += delta
	var speed := minf(COUNT_MIN_SPEED * exp(COUNT_GROWTH * _count_time), _count_max_speed)
	var step := speed * delta
	var remaining := _count_target - _count_value
	var done := false
	if absf(remaining) <= step:
		_count_value = _count_target
		done = true
	else:
		_count_value += signf(remaining) * step
	_ov_value.text = str(int(_count_value))

	if absf(_count_value) >= BOUNCE_START and absf(_count_value - _last_tick) >= BOUNCE_TICK:
		_last_tick = _count_value
		_tick_dir = -_tick_dir
		var a := 0.08 + 0.12 * clampf(absf(_count_value) / maxf(1.0, absf(_count_target)), 0.0, 1.0)
		_ov_value.scale = Vector2(1.0 + a * _tick_dir, 1.0 - a * 0.6 * _tick_dir)
		_ov_value.rotation = deg_to_rad(randf_range(-3.0, 3.0))

	var k := minf(1.0, 14.0 * delta)
	_ov_value.scale = _ov_value.scale.lerp(Vector2.ONE, k)
	_ov_value.rotation = lerpf(_ov_value.rotation, 0.0, k)

	if done:
		_counting = false
		_ov_value.scale = Vector2.ONE
		_ov_value.rotation = 0.0
		count_finished.emit()


# ================= internals =================

## Bargain panel = original width, 1/3 of the screen height (plus a small gap at the bottom).
## Text sizes scale with screen height (designed for a 648 px high window).
func _fit_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	var f := vp.y / 648.0
	var w := minf(640.0 * f, vp.x * 0.95)
	_bargain_panel.custom_minimum_size = Vector2(w, vp.y / 3.0)
	_content.custom_minimum_size = Vector2(w - 56.0, 0.0)
	_ask_label.add_theme_font_size_override("font_size", roundi(40.0 * f))
	_sub_label.add_theme_font_size_override("font_size", roundi(16.0 * f))
	_offer_label.add_theme_font_size_override("font_size", roundi(24.0 * f))
	_slider.custom_minimum_size = Vector2(0.0, 16.0 * f)
	for b in _nudge_buttons:
		b.add_theme_font_size_override("font_size", roundi(24.0 * f))
	for b in [_btn_offer, _btn_accept, _btn_away]:
		b.add_theme_font_size_override("font_size", roundi(30.0 * f))


func _set_panel_hidden(hide_it: bool, animate: bool) -> void:
	_panel_hidden = hide_it
	_toggle.icon = _tri_up if hide_it else _tri_down
	var target := (_root.size.y + 20.0) if hide_it else 0.0
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if animate:
		_hide_tween = create_tween()
		_hide_tween.tween_property(_layout, "position:y", target, 0.35) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN if hide_it else Tween.EASE_OUT)
	else:
		_layout.position.y = target


func _nudge(amount: int) -> void:
	# snaps to round numbers: 355 +10 -> 360, 355 -10 -> 350
	var a := absi(amount)
	var v := int(_slider.value)
	if amount > 0:
		v = floori(float(v) / a) * a + a
	else:
		v = ceili(float(v) / a) * a - a
	_slider.value = clampi(v, int(_slider.min_value), int(_slider.max_value))


func _on_slider_changed(v: float) -> void:
	_offer_label.text = "Your offer: %d" % int(v)


func _flash_sub(text: String) -> void:
	_sub_label.text = text
	_flash_id += 1
	var id := _flash_id
	await get_tree().create_timer(1.8).timeout
	if id == _flash_id:
		_sub_label.text = _market_text


func _pop(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2.ONE * 1.15
	create_tween().tween_property(c, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _prepare_overlay(title: String) -> void:
	hide_dialogue()
	_overlay.visible = true
	_counting = false
	_ov_title.text = title
	_ov_title.modulate = Color.WHITE
	_ov_value.text = "0"
	_ov_value.modulate = Color.WHITE
	_ov_value.scale = Vector2.ONE
	_ov_value.rotation = 0.0
	_ov_sub.text = ""
	_ov_btn.visible = false


func _start_hint_blink() -> void:
	_stop_hint_blink()
	_dlg_hint.modulate.a = 1.0
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_dlg_hint, "modulate:a", 0.25, 0.5)
	_hint_tween.tween_property(_dlg_hint, "modulate:a", 1.0, 0.5)


func _stop_hint_blink() -> void:
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_dlg_hint.modulate.a = 1.0


func _shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_shake_step, 1.0, 0.0, duration)
	_shake_tween.tween_callback(func(): _root.position = Vector2.ZERO)


func _shake_step(k: float) -> void:
	_root.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * k


func _rainbow(duration: float) -> void:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_method(_rainbow_step, 0.0, 4.0, duration)


func _rainbow_step(h: float) -> void:
	var c := Color.from_hsv(fmod(h, 1.0), 0.55, 1.0)
	_ov_value.modulate = c
	_ov_title.modulate = c


# ---------- builders / helpers ----------

## Full-screen VBox that pins a tan panel to the bottom-center. Returns [layout, panel].
func _bottom_layout(min_width: int, gap: int, bottom_pad: int, full_width: bool = false) -> Array:
	var layout := VBoxContainer.new()
	_root.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(center)

	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, gap)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(bottom)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(bottom_pad, full_width))
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	return [layout, panel]


func _panel_style(bottom_pad: int, full_width: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAN
	sb.border_color = BROWN
	if full_width:
		sb.border_width_top = 4
		sb.corner_radius_top_left = 26
		sb.corner_radius_top_right = 26
	else:
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(26)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 6
	sb.content_margin_bottom = bottom_pad
	return sb


func _outlined_label(text: String, size: int, color: Color, outline: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_size)
	return l


func _text_button(text: String, color: Color, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, color)
	b.add_theme_color_override("font_disabled_color", color.darkened(0.4))
	b.add_theme_color_override("font_outline_color", CREAM)
	b.add_theme_constant_override("outline_size", 6)
	b.mouse_entered.connect(func(): _hover(b, 1.12))
	b.mouse_exited.connect(func(): _hover(b, 1.0))
	return b


func _hover(b: Button, s: float) -> void:
	b.pivot_offset = b.size / 2.0
	create_tween().tween_property(b, "scale", Vector2.ONE * s, 0.1)


func _nudge_button(text: String, amount: int) -> Button:
	var b := _text_button(text, DARK_BROWN, 30)
	b.custom_minimum_size = Vector2(76, 0)
	b.pressed.connect(func(): _nudge(amount))
	_nudge_buttons.append(b)
	return b


func _expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Small triangle drawn in code (no font glyph needed, safe for web).
func _triangle_tex(up: bool) -> ImageTexture:
	var w := 36
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var f := float(y) / float(h - 1)
		var half := (f if up else 1.0 - f) * (w / 2.0)
		for x in w:
			if absf(x + 0.5 - w / 2.0) <= half:
				img.set_pixel(x, y, DARK_BROWN)
	return ImageTexture.create_from_image(img)
