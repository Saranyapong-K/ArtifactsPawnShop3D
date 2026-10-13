extends CanvasLayer
## One book for main-menu options and a real gameplay pause.

@export var pause_when_open := true
@export var preview_when_run_alone := true

const CLOCK_COLOURS := [Color.WHITE, Color("fff1dc"), Color("f7d475"), Color("401a00"), Color("15100c")]

var _root: Control
var _settings_pages: Control
var _key_page: Control
var _clock_select: OptionButton
var _heading: Label
var _resume: Button
var _menu: Button
var _is_open := false
var _was_paused := false
var _paused_by_book := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _binding_action := ""
var _key_buttons: Dictionary = {}
var _binding_hint: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 60
	_root = find_child("Screen", true, false)
	_settings_pages = find_child("SettingsPages", true, false)
	_key_page = find_child("KeyMappingPage", true, false)
	_clock_select = find_child("ClockColorSelector", true, false)
	_heading = find_child("Heading", true, false)
	_resume = find_child("ResumeButton", true, false)
	_menu = find_child("MainMenuButton", true, false)
	_binding_hint = find_child("BindingHint", true, false)
	_connect_button(_resume, _back_or_close)
	_connect_button(_menu, _return_to_menu)
	_connect_button(find_child("KeyMappingButton", true, false), _show_keys)
	_connect_button(find_child("BackSettingsButton", true, false), _show_settings)
	var quit_button: Button = find_child("QuitButton", true, false)
	quit_button.visible = not OS.has_feature("web")
	_connect_button(quit_button, func(): get_tree().quit())
	_connect_button(find_child("ResetKeysButton", true, false), func():
		if _settings(): _settings().reset_bindings()
		_refresh_keys())
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "interact", "sprint", "crouch", "toggle_hud", "inventory", "shop", "rotate_item"]:
		var key_button: Button = find_child(action.to_pascal_case() + "Key", true, false)
		_key_buttons[action] = key_button
		_connect_button(key_button, _begin_binding.bind(action))
	_connect_slider("SensitivitySlider", "SensitivityValue", "mouse_sensitivity", "", true)
	_connect_slider("MasterSlider", "MasterValue", "master_volume", "Master")
	_connect_slider("MusicSlider", "MusicValue", "music_volume", "Music")
	_connect_slider("SfxSlider", "SfxValue", "sfx_volume", "SFX")
	_connect_toggle("FullscreenToggle", "fullscreen", "set_fullscreen")
	_connect_toggle("MuteToggle", "muted", "set_muted")
	_connect_toggle("RadioNameToggle", "radio_popup", "set_radio_popup")
	var picker: ColorPickerButton = find_child("ClockColorPicker", true, false)
	if _settings(): picker.color = _settings().clock_color
	picker.color_changed.connect(func(value: Color):
		if _settings(): _settings().set_clock_color(value))
	picker.get_popup().popup_hide.connect(_sync_clock_colour)
	_clock_select.item_selected.connect(_on_clock_colour_selected)
	if _settings(): _settings().changed.connect(_sync_clock_colour)
	_sync_clock_colour()
	_refresh_keys()
	_root.hide()
	_preview_if_alone.call_deferred()

func _preview_if_alone() -> void:
	if preview_when_run_alone and get_tree().current_scene == self:
		show_options(false)

func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")

func _connect_button(button: Button, action: Callable) -> void:
	button.pressed.connect(func():
		var sfx := get_node_or_null("/root/Sfx")
		if sfx: sfx.play("click")
		action.call())

func _connect_toggle(node_name: String, setting: String, setter: String) -> void:
	var toggle: BaseButton = find_child(node_name, true, false)
	if _settings(): toggle.set_pressed_no_signal(bool(_settings().get(setting)))
	toggle.toggled.connect(func(enabled: bool):
		if _settings(): _settings().call(setter, enabled))

func _connect_slider(node_name: String, value_name: String, setting: String, bus: String, sensitivity := false) -> void:
	var slider: HSlider = find_child(node_name, true, false)
	var value_label: Label = find_child(value_name, true, false)
	if _settings(): slider.set_value_no_signal(float(_settings().get(setting)))
	var format_value := func(value: float):
		var fraction := inverse_lerp(slider.min_value, slider.max_value, value) if sensitivity else value
		value_label.text = "%d %%" % roundi(fraction * 100.0)
	format_value.call(slider.value)
	slider.value_changed.connect(func(value: float):
		format_value.call(value)
		if _settings():
			if sensitivity: _settings().set_mouse_sensitivity(value)
			else: _settings().set_volume(bus, value))

func _on_clock_colour_selected(index: int) -> void:
	if index < CLOCK_COLOURS.size():
		if _settings(): _settings().set_clock_color(CLOCK_COLOURS[index])
	else:
		var picker: ColorPickerButton = find_child("ClockColorPicker", true, false)
		if _settings(): picker.color = _settings().clock_color
		picker.get_popup().popup_centered(Vector2i(420, 540))

func _sync_clock_colour() -> void:
	if not _settings(): return
	var selected := CLOCK_COLOURS.size()
	for index in CLOCK_COLOURS.size():
		if _settings().clock_color.is_equal_approx(CLOCK_COLOURS[index]):
			selected = index
			break
	_clock_select.select(selected)

func _show_keys() -> void:
	_settings_pages.hide()
	_key_page.show()
	_refresh_keys()
	_key_buttons["move_forward"].grab_focus()

func _show_settings() -> void:
	_binding_action = ""
	_key_page.hide()
	_settings_pages.show()
	_refresh_keys()

func _back_or_close() -> void:
	if _key_page.visible: _show_settings()
	else: close_options()

func show_options(pause_game := true) -> void:
	if _is_open:
		return
	_is_open = true
	_was_paused = get_tree().paused
	_previous_mouse_mode = Input.mouse_mode
	_paused_by_book = pause_game and pause_when_open
	if _paused_by_book:
		get_tree().paused = true
	_heading.text = "Game pause ❚❚" if _paused_by_book else ""
	_resume.tooltip_text = "Resume game (Esc)" if _paused_by_book else "Close settings (Esc)"
	_menu.visible = _paused_by_book
	_show_settings()
	_refresh_keys()
	_root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()

func close_options() -> void:
	if not _is_open:
		return
	_binding_action = ""
	_is_open = false
	_clock_select.get_popup().hide()
	var picker: ColorPickerButton = find_child("ClockColorPicker", true, false)
	picker.get_popup().hide()
	_root.hide()
	if _paused_by_book:
		get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse_mode

func _input(event: InputEvent) -> void:
	var warmer := get_node_or_null("/root/AssetWarmup")
	if warmer and warmer.get("busy"):
		get_viewport().set_input_as_handled()
		return
	if _is_open and not _binding_action.is_empty() and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode != KEY_ESCAPE and event.physical_keycode != KEY_ESCAPE:
			if _settings(): _settings().bind_key(_binding_action, event.physical_keycode)
		_binding_action = ""
		_refresh_keys()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if not _is_open:
			var editing_price := get_tree().get_first_node_in_group("editing_stock_price")
			if editing_price and editing_price.has_method("cancel_edit"):
				editing_price.cancel_edit()
				get_viewport().set_input_as_handled()
				return
		if _is_open:
			_back_or_close()
		elif pause_when_open:
			var modal := get_tree().get_first_node_in_group("active_game_modal")
			if modal and modal.has_method("close_panel"):
				modal.close_panel()
				get_viewport().set_input_as_handled()
				return
			show_options(true)
		else:
			return
		get_viewport().set_input_as_handled()

func _begin_binding(action: String) -> void:
	_binding_action = action
	_binding_hint.text = "Press a new key, or Esc to cancel."
	_key_buttons[action].text = "Press a key…"

func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = _settings().key_name(action) if _settings() else action
	if _binding_hint:
		_binding_hint.text = "Select a key to change it. Esc returns to settings."

func _return_to_menu() -> void:
	close_options()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _exit_tree() -> void:
	if _is_open and _paused_by_book:
		get_tree().paused = _was_paused
