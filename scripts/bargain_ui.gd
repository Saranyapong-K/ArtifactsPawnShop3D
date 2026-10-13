class_name BargainUI
extends CanvasLayer
## Behaviour for editable bargain, dialogue and receipt scenes.

signal offer_submitted(price: int)
signal accept_pressed
signal send_away_pressed
signal next_pressed
signal dialogue_advanced
signal panel_visibility_changed(hidden: bool)
var _dialogue_epoch := 0
signal count_finished   # internal: number counter reached its target
signal price_submitted(price: int)
signal inspection_requested(tool: String)

@export var preview_when_run_alone := true

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
var _layout: Control
var _bargain_panel: Control
var _content: Control
var _ask_label: Label
var _sub_label: Label
var _offer_label: Label
var _slider: HSlider
var _btn_offer: Button
var _btn_accept: Button
var _btn_away: Button
var _nudge_buttons: Array[Button] = []
var _toggle: Button
var _toggle_hint: Label
var _flag: TextureRect
var _panel_hidden := false
var _hide_tween: Tween
var _market_text := ""
var _buyer_listing := 0
var _buyer_cost := 0
var _flash_id := 0
var _tri_up: Texture2D
var _tri_down: Texture2D
var _buyer_mode := false
var _wallet := 0
var _controls_allowed := true

# dialogue
var _dlg_layout: VBoxContainer
var _dlg_label: Label
var _dlg_hint: TextureRect
var _hint_tween: Tween
var _dlg_active := false
var _dlg_typing := false
var _dlg_started_ms := 0

# overlay (reveal / summary)
var _price_overlay: ColorRect
var _summary_overlay: ColorRect
var _receipt_overlay: ColorRect
var _overlay: ColorRect
var _ov_title: Label
var _ov_value: Label
var _ov_sub: Label
var _ov_btn: Button
var _price_row: HBoxContainer
var _price_spin: SpinBox
var _price_save: Button

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
	add_to_group("bargain_ui")
	layer = 10
	_tri_up = preload("res://ui/arrow_up.tres")
	_tri_down = preload("res://ui/arrow_down.tres")
	_root = find_child("Screen", true, false)
	_layout = find_child("BargainMenu", true, false)
	_bargain_panel = find_child("BargainPanel", true, false)
	_content = find_child("BargainContent", true, false)
	_ask_label = find_child("AskingPrice", true, false)
	_sub_label = find_child("ReferencePrice", true, false)
	_offer_label = find_child("OfferPrice", true, false)
	_slider = find_child("OfferSlider", true, false)
	_btn_offer = find_child("OfferButton", true, false)
	_btn_accept = find_child("AcceptButton", true, false)
	_btn_away = find_child("RejectButton", true, false)
	_toggle = find_child("TogglePanelButton", true, false)
	_toggle_hint = find_child("ToggleHint", true, false)
	_flag = find_child("BargainFlag", true, false)
	_dlg_layout = find_child("DialogueMenu", true, false)
	_dlg_label = find_child("DialogueText", true, false)
	_dlg_hint = find_child("ContinueIndicator", true, false)
	_receipt_overlay = $Screen/ReceiptMenu
	_summary_overlay = $Screen/DaySummaryMenu
	_price_overlay = $Screen/PriceEditorMenu
	_overlay = _receipt_overlay
	_ov_title = _overlay.find_child("ResultHeading", true, false)
	_ov_value = _overlay.find_child("ResultValue", true, false)
	_ov_sub = _overlay.find_child("ResultDetails", true, false)
	_ov_btn = _overlay.find_child("NextButton", true, false)
	_price_row = _overlay.find_child("PriceRow", true, false)
	_price_spin = _overlay.find_child("SellPriceInput", true, false)
	_price_save = _overlay.find_child("SavePriceButton", true, false)
	_slider.value_changed.connect(_on_slider_changed)
	_btn_offer.pressed.connect(func(): offer_submitted.emit(int(_slider.value)))
	_btn_accept.pressed.connect(func(): accept_pressed.emit())
	_btn_away.pressed.connect(func(): send_away_pressed.emit())
	_toggle.pressed.connect(func(): _set_panel_hidden(not _panel_hidden, true))
	for pair in [["InspectDamageButton", "magnifier"], ["InspectCurseButton", "curse_detector"]]:
		var inspect: Button = find_child(pair[0], true, false)
		inspect.pressed.connect(func(): inspection_requested.emit(pair[1]))
	_root.resized.connect(_position_reveal_button)
	_ov_btn.pressed.connect(func(): next_pressed.emit())
	var price_save: Button = _price_overlay.find_child("SavePriceButton", true, false)
	_wire_button_feedback(price_save)
	price_save.pressed.connect(func():
		_price_spin.apply()
		var price := int(_price_spin.value)
		hide_price_editor()
		price_submitted.emit(price))
	var nudge_names := ["Minus100Button", "Minus10Button", "Plus10Button", "Plus100Button"]
	var amounts := [-100, -10, 10, 100]
	for index in nudge_names.size():
		var button: Button = find_child(nudge_names[index], true, false)
		_nudge_buttons.append(button)
		button.pressed.connect(_nudge.bind(amounts[index]))
	for button: Button in _nudge_buttons + [_btn_offer, _btn_accept, _btn_away, _ov_btn, _price_save]:
		_wire_button_feedback(button)
	_layout.hide()
	_dlg_layout.hide()
	_overlay.hide()
	_summary_overlay.hide()
	_price_overlay.hide()
	var summary_next: Button = _summary_overlay.find_child("NextButton", true, false)
	_wire_button_feedback(summary_next)
	summary_next.pressed.connect(func(): next_pressed.emit())
	_toggle.hide()
	_flag.hide()
	_price_row.hide()
	_price_save.hide()
	_preview_if_alone.call_deferred()

func _preview_if_alone() -> void:
	if preview_when_run_alone and get_tree().current_scene == self:
		show_customer(1, 3, 200, 75, 100, "")


# ================= public API =================

## Typewriter line. Returns when the player presses E / Space to continue.
## (First press while typing = show the full line.)
func say(text: String) -> void:
	_dialogue_epoch += 1
	var token: int = _dialogue_epoch
	_overlay.visible = false   # the old reveal/summary must not stay on screen
	_counting = false
	_layout.visible = false
	_toggle.visible = false
	_flag.hide()
	_dlg_layout.visible = true
	_dlg_label.text = text
	_dlg_label.visible_characters = 0
	_dlg_hint.visible = false
	_dlg_active = true
	_dlg_typing = true
	_dlg_started_ms = Time.get_ticks_msec()

	var shown := 0.0
	var last_spoken := -1
	var chatter := get_node_or_null("/root/Sfx")
	while _dlg_typing and _dlg_active and token == _dialogue_epoch:
		await get_tree().process_frame
		if not _dlg_typing or not _dlg_active or token != _dialogue_epoch: break
		if get_tree().paused: continue
		shown += get_process_delta_time() * DIALOGUE_CPS
		_dlg_label.visible_characters = int(shown)
		var character := mini(int(shown), text.length()) - 1
		if character > last_spoken:
			last_spoken = character
			if chatter and text.substr(character, 1).strip_edges() != "":
				chatter.play("talk", randf_range(0.9, 1.15))
		if shown >= text.length():
			_dlg_typing = false
	if token != _dialogue_epoch or not _dlg_active: return
	_dlg_label.visible_characters = -1

	_dlg_hint.visible = true
	_start_hint_blink()
	while _dlg_active and token == _dialogue_epoch:
		await get_tree().process_frame
	if token != _dialogue_epoch: return
	_stop_hint_blink()
	_dlg_active = false


func hide_dialogue() -> void:
	_dialogue_epoch += 1
	_dlg_active = false
	_dlg_typing = false
	_stop_hint_blink()
	_dlg_layout.visible = false


func show_customer(_number: int, _total: int, money: int, market: int, ask: int, message: String) -> void:
	_buyer_mode = false
	_wallet = money
	_overlay.visible = false
	_counting = false
	_root.position = Vector2.ZERO
	hide_dialogue()
	_layout.visible = true
	_toggle.visible = true
	_flag.show()
	_refresh_inspection_buttons()
	_set_panel_hidden(false, false)

	_market_text = "Market price: %d G" % market
	_sub_label.text = _market_text

	var lo := 1 if money > 0 else 0
	var hi := maxi(lo, money)
	_slider.step = 1
	_slider.min_value = lo
	_slider.max_value = hi
	_slider.value = clampi(roundi(ask / 10.0) * 10, lo, hi)   # starts at the ask, rounded
	_on_slider_changed(_slider.value)

	_ask_label.text = "Customer's asking price: %d G" % ask
	if message != "":
		_flash_sub(message)
	set_controls_enabled(true)
	_btn_accept.disabled = ask > money


func show_buyer(_number: int, _total: int, _money: int, listing: int, offer: int, message: String, cost: int = 0) -> void:
	_buyer_mode = true
	_overlay.hide()
	_counting = false
	_root.position = Vector2.ZERO
	hide_dialogue()
	_layout.show()
	_toggle.show()
	_flag.show()
	_refresh_inspection_buttons()
	_set_panel_hidden(false, false)
	_buyer_listing = listing
	_buyer_cost = cost
	_market_text = _buyer_reference(offer)
	_sub_label.text = _market_text
	_slider.step = 1
	_slider.min_value = 1
	_slider.max_value = maxi(listing, offer)
	_slider.value = listing
	_on_slider_changed(_slider.value)
	_ask_label.text = "Buyer offers: %d G" % offer
	if not message.is_empty():
		_flash_sub(message)
	set_controls_enabled(true)


func update_state(ask: int, _anger: float, message: String) -> void:
	_ask_label.text = ("Buyer offers: %d G" if _buyer_mode else "Customer's asking price: %d G") % ask
	if _buyer_mode:
		_market_text = _buyer_reference(ask)
		_sub_label.text = _market_text
	_btn_accept.disabled = not _controls_allowed or (not _buyer_mode and ask > _wallet)
	_pop(_ask_label)
	if message != "":
		_flash_sub(message)

func _buyer_reference(offer: int) -> String:
	var profit := offer - _buyer_cost
	return "Listed: %d G · Accept: %d G · %s: %d G" % [_buyer_listing, offer, "Profit" if profit >= 0 else "Loss", absi(profit)]


func show_message(text: String) -> void:
	_flash_sub(text)


func set_controls_enabled(enabled: bool) -> void:
	_controls_allowed = enabled
	_btn_offer.disabled = not enabled
	_btn_accept.disabled = not enabled
	_btn_away.disabled = not enabled
	_slider.editable = enabled
	_toggle.disabled = not enabled
	for b in _nudge_buttons:
		b.disabled = not enabled


## Balatro-style reveal: number accelerates, bounces past 200, then pop + shake.
func show_reveal(_obsolete_value: int, paid: int) -> void:
	# Retained for old callers; purchases never expose a hidden value or profit.
	show_purchase(paid, paid)


func show_purchase(cost: int, listing: int, artifact_name := "Artifact") -> void:
	# Legacy callers also skip the redundant purchase receipt.
	hide_price_editor()
	_receipt_overlay.hide()
	next_pressed.emit()


func show_price_editor(artifact) -> void:
	set_controls_enabled(false)
	_prepare_overlay("SET YOUR SELL PRICE", "price")
	var cost := int(artifact.cost)
	var cap := int(artifact.max_sell_price())
	_ov_value.text = "%d G" % cost
	_ov_sub.text = "%s · Bought for %d G\nMaximum sell price: %d G" % [artifact.display_name, cost, cap]
	_price_spin.max_value = maxi(1, cap)
	var listing := int(artifact.sell_price)
	_price_spin.value = clampi(listing if listing > 0 else roundi(cost * 1.75), 1, maxi(1, cap))
	_price_row.show()
	_price_save.show()
	_price_spin.get_line_edit().grab_focus()
	_price_spin.get_line_edit().select_all()


func hide_price_editor() -> void:
	_price_row.hide()
	_price_save.hide()
	_overlay.hide()


func show_sale(price: int, profit: int, artifact_name := "Artifact") -> void:
	set_controls_enabled(false)
	_prepare_overlay("SALE COMPLETE")
	_ov_value.text = "%d G" % price
	_ov_sub.text = "%s sold · Profit %+d G" % [artifact_name, profit]
	_ov_btn.text = "Next customer"
	_ov_btn.show()


func show_summary(day_done: int, day_profit: int, money: int) -> void:
	set_controls_enabled(false)
	_prepare_overlay("DAY %d COMPLETE" % day_done, "summary")
	_ov_title.modulate = GOLD
	_ov_btn.text = "Sleep & start next day"
	await get_tree().process_frame
	_ov_value.pivot_offset = _ov_value.size / 2.0

	_start_count(float(day_profit))
	await count_finished

	_ov_value.modulate = Color("ff5a5a") if day_profit < 0 else Color.WHITE
	_ov_sub.text = "Today's sales profit  |  Wallet: %d G" % money
	var p := create_tween()
	p.tween_property(_ov_value, "scale", Vector2.ONE * 1.2, 0.12)
	p.tween_property(_ov_value, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_shake(8.0, 0.3)
	_ov_btn.visible = true


# ================= input =================

func _input(event: InputEvent) -> void:
	var warmer := get_node_or_null("/root/AssetWarmup")
	if warmer and warmer.get("busy"):
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused or get_tree().get_first_node_in_group("active_game_modal"):
		return
	if visible and _layout.visible and event.is_action_pressed("toggle_hud") and not event.is_echo():
		_set_panel_hidden(not _panel_hidden, true)
		get_viewport().set_input_as_handled()

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
			_dlg_active = false
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
	_toggle_hint.visible = visible and _toggle.visible and _layout.visible
	var settings := get_node_or_null("/root/GameSettings")
	_toggle_hint.text = "%s · %s panel" % [settings.key_name("toggle_hud") if settings else "Tab", "Show" if _panel_hidden else "Hide"]
	_toggle_hint.position = Vector2(_toggle.position.x + _toggle.size.x + 8.0, _toggle.position.y + (_toggle.size.y - _toggle_hint.size.y) * 0.5)
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
	_ov_value.text = "%d G" % int(_count_value)

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

func _set_panel_hidden(hide_it: bool, animate: bool) -> void:
	_panel_hidden = hide_it
	panel_visibility_changed.emit(hide_it)
	_toggle.icon = null
	var arrow: TextureRect = _toggle.get_node("ArrowArtwork")
	arrow.pivot_offset = arrow.size * 0.5
	arrow.rotation = PI if hide_it else 0.0
	var target := (_root.size.y + 20.0) if hide_it else 0.0
	var flag_target := -120.0 if hide_it else 0.0
	var button_target: float = _root.size.y - _toggle.size.y - 12.0 if hide_it else _bargain_panel.position.y - _toggle.size.y * 0.5
	button_target=clampf(button_target,12.0,maxf(12.0,_root.size.y-_toggle.size.y-12.0))
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if animate:
		_hide_tween = create_tween().set_parallel(true)
		_hide_tween.tween_property(_layout, "position:y", target, 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_hide_tween.tween_property(_flag, "position:y", flag_target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_hide_tween.tween_property(_toggle, "position:y", button_target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		_layout.position.y = target
		_flag.position.y = flag_target
		_toggle.position.y = button_target

func _position_reveal_button() -> void:
	if _toggle == null: return
	_set_panel_hidden(_panel_hidden, false)

func _refresh_inspection_buttons() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	(find_child("InspectDamageButton", true, false) as Button).visible = state != null and state.owned_items.get("magnifier", false)
	(find_child("InspectCurseButton", true, false) as Button).visible = state != null and state.owned_items.get("curse_detector", false)


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
	_offer_label.text = ("Your price: %d G" if _buyer_mode else "Your offer: %d G") % int(v)


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


func _prepare_overlay(title: String, screen := "receipt") -> void:
	_receipt_overlay.hide()
	_summary_overlay.hide()
	_price_overlay.hide()
	_overlay = {"receipt":_receipt_overlay, "summary":_summary_overlay, "price":_price_overlay}[screen]
	_ov_title = _overlay.find_child("ResultHeading", true, false)
	_ov_value = _overlay.find_child("ResultValue", true, false)
	_ov_sub = _overlay.find_child("ResultDetails", true, false)
	_ov_btn = _overlay.find_child("NextButton", true, false)
	_price_row = _overlay.find_child("PriceRow", true, false)
	_price_spin = _overlay.find_child("SellPriceInput", true, false)
	_price_save = _overlay.find_child("SavePriceButton", true, false)
	hide_dialogue()
	_layout.hide()
	_toggle.hide()
	_flag.hide()
	_price_row.hide()
	_price_save.hide()
	_overlay.visible = true
	_counting = false
	_ov_title.text = title
	_ov_title.modulate = Color.WHITE
	_ov_value.text = "0 G"
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


func _hover(button: Button, scale_value: float) -> void:
	button.pivot_offset = button.size / 2.0
	create_tween().tween_property(button, "scale", Vector2.ONE * scale_value, 0.1)

func _wire_button_feedback(button: Button) -> void:
	button.mouse_entered.connect(_hover.bind(button, 1.12))
	button.mouse_exited.connect(_hover.bind(button, 1.0))
	button.pressed.connect(func():
		var sfx := get_node_or_null("/root/Sfx")
		if sfx: sfx.play("click"))
