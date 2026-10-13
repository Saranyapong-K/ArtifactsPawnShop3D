extends HBoxContainer
## Only the active price box reveals its editable value.

signal price_committed

var editing: bool = false
@export var price_font_size: int = 26
var _saved_price: float = 0.0
@onready var price: SpinBox = %ListingPrice
@onready var edit_button: Button = %EditPriceButton

func _ready() -> void:
	price.get_line_edit().add_theme_font_size_override("font_size", price_font_size)
	edit_button.pressed.connect(begin_edit)
	price.get_line_edit().gui_input.connect(_price_input)
	price.get_line_edit().text_submitted.connect(func(_text: String): commit_edit())
	%SavePriceButton.pressed.connect(commit_edit)

func begin_edit() -> void:
	# Switching rows cancels the earlier draft; only one box is active.
	for row in get_tree().get_nodes_in_group("editing_stock_price"):
		if row != self: row.cancel_edit()
	_saved_price = price.value
	editing = true
	add_to_group("editing_stock_price")
	edit_button.hide()
	price.show()
	price.get_line_edit().grab_focus()
	price.get_line_edit().select_all()

func commit_edit() -> void:
	var raw: String = price.get_line_edit().text.strip_edges().trim_suffix(" G").strip_edges()
	if not raw.is_valid_int() or int(raw) < 0:
		price.value = 1
		price.get_line_edit().text = "1 G"
	else:
		price.apply()
	_saved_price = price.value
	price_committed.emit()
	_finish_edit()

func cancel_edit() -> void:
	price.value = _saved_price
	price.get_line_edit().text = "%d G" % int(_saved_price)
	_finish_edit()

func _finish_edit() -> void:
	editing = false
	remove_from_group("editing_stock_price")
	price.hide()
	edit_button.show()
	price.get_line_edit().release_focus()

func _price_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel_edit()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Consume Escape before the pause book or stock modal handles it.
	if editing and event.is_action_pressed("ui_cancel"):
		cancel_edit()
		get_viewport().set_input_as_handled()
	elif editing and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		# Validate the raw text before SpinBox normalizes an invalid entry away.
		commit_edit()
		get_viewport().set_input_as_handled()
