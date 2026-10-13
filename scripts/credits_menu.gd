extends Control
## Labels and artwork belong to the scene; this script only opens/closes it.

func _ready() -> void:
	$Center/Panel/Content/CloseButton.pressed.connect(close)
	hide()
	_preview_if_alone.call_deferred()

func _preview_if_alone() -> void:
	if get_tree().current_scene == self: open()

func open() -> void:
	show()
	$Center/Panel/Content/CloseButton.grab_focus()

func close() -> void:
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
