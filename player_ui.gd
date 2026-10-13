extends Control
## Player UI: day, money, rent countdown, clock (after buying it), sun/moon icon.
## Attach to the PlayerUI root of player_ui.tscn. Put that scene under a CanvasLayer
## in Main so it stays on screen over the 3D world.
##
## Input Map action needed: toggle_hud (Tab).

@onready var info_panel: Control = $InfoPanel
@onready var day_label: Label = $InfoPanel/DayLabel
@onready var money_label: Label = $InfoPanel/MoneyLabel
@onready var rent_label: Label = $InfoPanel/RentLabel
@onready var clock_panel: Control = $InfoPanel/Clockpanel
@onready var time_label: Label = $InfoPanel/Clockpanel/Time
@onready var sun_icon: TextureRect = $InfoPanel/Clockpanel/Sun
@onready var moon_icon: TextureRect = $InfoPanel/Clockpanel/Moon

var _hud_tween: Tween
var _panel_shown_x: float
var _panel_hidden_x: float



func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pass_mouse_through(self)
	show_clock(false)
	set_daylight(false)
	var state := get_node_or_null("/root/GameState")
	if state:
		state.changed.connect(_sync_state)
		state.time_changed.connect(_on_time_changed)
		state.day_started.connect(_on_day_started)
		_sync_state()
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		settings.changed.connect(_apply_settings)
		_apply_settings()
	
	# Store the resting position on screen
	_panel_shown_x = info_panel.global_position.x


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud") and not event.is_echo():
		for book in get_tree().get_nodes_in_group("bargain_ui"):
			if book.visible and book._layout.visible: return
		toggle_hud()
		get_viewport().set_input_as_handled()


func _sync_state() -> void:
	var state := get_node_or_null("/root/GameState")
	if not state:
		return
	set_day(int(state.day))
	set_money(int(state.money), false)
	set_rent_countdown(int(state.rent_days_left()))
	show_clock(bool(state.clock_owned))
	var minutes := int(state.time_minutes)
	set_time(minutes / 60, minutes % 60)
	set_daylight(minutes >= 19 * 60)


func _on_time_changed(hour: int, minute: int) -> void:
	set_time(hour, minute)
	set_daylight(hour >= 19)


func _on_day_started(_day: int) -> void:
	_sync_state()


func _apply_settings() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		time_label.add_theme_color_override("font_color", settings.clock_color)


# Tab: slide the info panel out to the left and back in.
func toggle_hud() -> void:
	info_panel.visible = not info_panel.visible
	var game_ui := get_tree().get_first_node_in_group("game_ui")
	if game_ui: game_ui.set_hint_visible(info_panel.visible)

func set_day(number: int) -> void:
	day_label.text = "Day %d" % number


# Pops the money label when it changes.
func set_money(value: int, animate: bool = true) -> void:
	money_label.text = "%d G" % value
	if not animate:
		return
	await get_tree().process_frame
	money_label.pivot_offset = money_label.size / 2.0
	money_label.scale = Vector2.ONE * 1.2
	create_tween().tween_property(money_label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_rent_countdown(days_left: int) -> void:
	if days_left <= 0:
		rent_label.text = "Rent due now"
	elif days_left == 1:
		rent_label.text = "Rent in 1 Day"
	else:
		rent_label.text = "Rent in %d Days" % days_left


#show clock when player buy clock
func show_clock(on: bool) -> void:
	clock_panel.visible = on


#24-hour time
func set_time(hour: int, minute: int) -> void:
	time_label.text = "%02d:%02d" % [hour, minute]


#moon from 19:00 on. 
func set_daylight(is_night: bool) -> void:
	sun_icon.visible = not is_night
	moon_icon.visible = is_night
	

func _pass_mouse_through(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pass_mouse_through(child)
