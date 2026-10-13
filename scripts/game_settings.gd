extends Node
## Settings are stored separately from the sleep-only game save.

signal changed

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_BINDINGS := {
	"move_forward": KEY_W, "move_back": KEY_S,
	"move_left": KEY_A, "move_right": KEY_D,
	"interact": KEY_E, "sprint": KEY_SHIFT,
	"crouch": KEY_C, "toggle_hud": KEY_TAB,
	"inventory": KEY_I, "shop": KEY_B, "rotate_item": KEY_R,
}

var mouse_sensitivity := 0.0025
var clock_color := Color("401a00")
var fullscreen := false
var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.8
var muted := false
var radio_popup := true
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	mouse_sensitivity = clampf(float(config.get_value("gameplay", "mouse_sensitivity", mouse_sensitivity)), 0.0005, 0.008)
	clock_color = config.get_value("gameplay", "clock_color", clock_color)
	fullscreen = bool(config.get_value("gameplay", "fullscreen", fullscreen))
	master_volume = clampf(float(config.get_value("sound", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("sound", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("sound", "sfx", sfx_volume)), 0.0, 1.0)
	muted = bool(config.get_value("sound", "muted", muted))
	radio_popup = bool(config.get_value("sound", "radio_popup", radio_popup))
	for action in DEFAULT_BINDINGS:
		bindings[action] = int(config.get_value("keys", action, DEFAULT_BINDINGS[action]))

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("gameplay", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("gameplay", "clock_color", clock_color)
	config.set_value("gameplay", "fullscreen", fullscreen)
	config.set_value("sound", "master", master_volume)
	config.set_value("sound", "music", music_volume)
	config.set_value("sound", "sfx", sfx_volume)
	config.set_value("sound", "muted", muted)
	config.set_value("sound", "radio_popup", radio_popup)
	for action in bindings:
		config.set_value("keys", action, bindings[action])
	config.save(CONFIG_PATH)

func apply_settings() -> void:
	for action in bindings:
		_apply_binding(action, int(bindings[action]))
	_apply_audio("Master", master_volume)
	_apply_audio("Music", music_volume)
	_apply_audio("SFX", sfx_volume)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	if OS.has_feature("web"):
		# Browser fullscreen requires a user gesture; handled by the checkbox.
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_binding(action: String, physical_key: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_key
	InputMap.action_add_event(action, event)
	if action == "crouch" and physical_key != KEY_CTRL and not bindings.values().has(KEY_CTRL):
		var alternate := InputEventKey.new()
		alternate.physical_keycode = KEY_CTRL
		InputMap.action_add_event(action, alternate)

func _apply_audio(bus_name: String, value: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, bus_name)
		AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.0001)))

func _notify() -> void:
	save_settings()
	changed.emit()

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.0005, 0.008)
	_notify()

func set_clock_color(value: Color) -> void:
	clock_color = value
	_notify()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
	_notify()

func set_volume(bus_name: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match bus_name:
		"Master": master_volume = value
		"Music": music_volume = value
		"SFX": sfx_volume = value
	_apply_audio(bus_name, value)
	_notify()

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), value)
	_notify()

func set_radio_popup(value: bool) -> void:
	radio_popup = value
	_notify()

func bind_key(action: String, physical_key: int) -> void:
	if not DEFAULT_BINDINGS.has(action):
		return
	# Swap a conflicting binding so both actions remain available.
	var previous := int(bindings[action])
	for other in bindings:
		if other != action and int(bindings[other]) == physical_key:
			bindings[other] = previous
			_apply_binding(other, previous)
	bindings[action] = physical_key
	for bound_action in bindings:
		_apply_binding(bound_action, int(bindings[bound_action]))
	_notify()

func reset_bindings() -> void:
	bindings = DEFAULT_BINDINGS.duplicate()
	for action in bindings:
		_apply_binding(action, int(bindings[action]))
	_notify()

func key_name(action: String) -> String:
	var code := int(bindings.get(action, DEFAULT_BINDINGS.get(action, KEY_NONE)))
	var label := OS.get_keycode_string(code)
	return label + " / Ctrl" if action == "crouch" and code != KEY_CTRL and not bindings.values().has(KEY_CTRL) else label
