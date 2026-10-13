extends SceneTree
## Exercise the real controls and scene transitions after the menu migration.

class PlayerFixture extends Node3D:
	var controls_enabled := true
	func set_controls_enabled(enabled: bool) -> void:
		controls_enabled = enabled

class ManagerFixture extends Node:
	var newspaper_delivered := false
	func can_wait() -> bool: return false

var checks := 0
var failures := 0

func _init() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _check_shop_cards(shop: Control, context: String) -> void:
	var controller: Script = load("res://scripts/game_ui.gd")
	var icons := {"magnifier":"iconMagnifyingGlassesUi", "curse_detector":"iconCurseDetectorUi", "clock":"iconClockUi", "radio":"iconRadioUi"}
	for equipment: Dictionary in controller.EQUIPMENT:
		var card: Node = shop.get_node("%Equipment").get_node(controller.EQUIPMENT_NODES[equipment.id])
		_check((card.get_node("%ItemName") as Label).text == equipment.name and (card.get_node("%Price") as Label).text == "%d G" % equipment.price and (card.get_node("%Description") as Label).text == equipment.description, "%s: %s has its own saved equipment details" % [context, equipment.id])
		var icon: Texture2D = (card.get_node("%ItemIcon") as TextureRect).texture
		var icon_path: String = "res://assets/UIs/previews/roomba.res" if equipment.id == "roomba" else "res://assets/UIs/%s.png" % icons[equipment.id]
		_check(icon != null and icon.resource_path == icon_path, "%s: %s uses its equipment icon instead of the furniture icon" % [context, equipment.id])
	for furniture: Dictionary in controller.FURNITURE:
		var card: Node = shop.get_node("%Furniture").get_node(controller.FURNITURE_NODES[furniture.id])
		_check((card.get_node("%ItemName") as Label).text == furniture.name and (card.get_node("%Price") as Label).text == "%d G" % furniture.price and (card.get_node("%Description") as Label).text == "%d × %d floor cells" % [furniture.grid[0], furniture.grid[1]], "%s: %s has its own saved furniture details" % [context, furniture.id])

func _check_standalone_shop() -> void:
	# F6 runs this scene without GameUI supplying catalog details. Verify it also
	# retains inherited child overrides after Godot packs and saves the scene.
	var shop: Control = load("res://ui/shop_menu.tscn").instantiate()
	_check_shop_cards(shop, "Standalone shop")
	var saved := PackedScene.new()
	_check(saved.pack(shop) == OK, "Shop scene can be repacked with its card overrides")
	shop.free()
	var path := "user://shop-card-roundtrip.tscn"
	_check(ResourceSaver.save(saved, path) == OK, "Shop scene saves its card overrides")
	var reloaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var restored: Control = reloaded.instantiate()
	_check_shop_cards(restored, "Saved and reloaded shop")
	restored.free()

func _run() -> void:
	var state: Node = root.get_node("GameState")
	var settings: Node = root.get_node("GameSettings")
	# Settings callbacks write a config, so this test must run with isolated APPDATA.
	if not OS.get_user_data_dir().contains("menu-scene-tests"):
		push_error("Run menu_scene_test with isolated APPDATA containing menu-scene-tests.")
		quit(1)
		return
	state.save_path = "user://menu-test-save.json"
	_check_standalone_shop()
	state.new_game()
	state.start_clock()
	var book: CanvasLayer = load("res://ui/settings_menu.tscn").instantiate()
	root.add_child(book)
	book.show_options(true)
	_check(paused and book._root.visible, "Settings opens its saved controls and pauses gameplay")
	var sensitivity: HSlider = book.find_child("SensitivitySlider", true, false)
	sensitivity.value = 0.004
	_check(is_equal_approx(settings.mouse_sensitivity, 0.004), "Sensitivity control changes the setting")
	_check((book.find_child("SensitivityValue", true, false) as Label).text == "47 %", "Sensitivity value label shows the position within its range as a percentage")
	var music: HSlider = book.find_child("MusicSlider", true, false)
	music.value = 0.25
	_check(is_equal_approx(settings.music_volume, 0.25), "Music control changes the audio setting")
	var mute: CheckBox = book.find_child("MuteToggle", true, false)
	mute.button_pressed = true
	_check(settings.muted and AudioServer.is_bus_mute(0), "Mute control changes the real audio bus")
	(book.find_child("KeyMappingButton", true, false) as Button).pressed.emit()
	_check(book._key_page.visible and not book._settings_pages.visible and paused, "Key mapping opens a separate page without unpausing")
	(book.find_child("MoveForwardKey", true, false) as Button).pressed.emit()
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_UP
	book._input(key)
	_check(settings.bindings.move_forward == KEY_UP, "Saved key button starts rebinding")
	(book.find_child("ResetKeysButton", true, false) as Button).pressed.emit()
	_check(settings.bindings.move_forward == KEY_W, "Reset keys button restores defaults")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	book._input(escape)
	_check(book._settings_pages.visible and not book._key_page.visible and paused, "Escape returns from key mapping to the open settings book")
	var colour: OptionButton = book.find_child("ClockColorSelector", true, false)
	colour.item_selected.emit(2)
	_check(settings.clock_color == Color("f7d475") and colour.selected == 2, "Clock colour dropdown applies the selected palette colour")
	var picker: ColorPickerButton = book.find_child("ClockColorPicker", true, false)
	var custom_colour := Color("736891")
	picker.color_changed.emit(custom_colour)
	_check(settings.clock_color == custom_colour and colour.selected == 5, "Custom clock colour stays available in the dropdown")
	colour.item_selected.emit(5)
	_check(picker.get_popup().visible and book._is_open and paused, "Custom colour picker opens above the paused book")
	(book.find_child("ResumeButton", true, false) as Button).pressed.emit()
	_check(not paused and not book._is_open, "Resume button closes the menu and unpauses")
	_check(not picker.get_popup().visible, "Closing the book also closes its colour picker")
	book.queue_free()
	await process_frame

	var fixture := Node.new()
	root.add_child(fixture)
	var player := PlayerFixture.new()
	var manager := ManagerFixture.new()
	fixture.add_child(player)
	fixture.add_child(manager)
	var ui: CanvasLayer = load("res://ui/game_ui.tscn").instantiate()
	fixture.add_child(ui)
	ui.player = player
	ui.manager = manager
	var artifact := ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Test coin", "Common", "normal", Vector2i.ONE)
	state.purchase(artifact, 25)
	state.set_sell_price(artifact.id, 30)
	ui.open_panel("stock")
	await process_frame
	await process_frame
	_check(root.get_visible_rect().encloses(ui.modal.get_global_rect()), "Stock panel stays inside the screen after wrapped labels settle")
	var row: Node = ui._stock.get_node("%Rows").get_child(0)
	var price: SpinBox = row.get_node("%ListingPrice")
	price.get_line_edit().text = "42"
	(row.get_node("%SavePriceButton") as Button).pressed.emit()
	_check(artifact.sell_price == 42, "Saved row button commits a typed listing price")
	price.value = 55
	state.changed.emit()
	await process_frame
	_check(is_instance_valid(row) and price.value == 55, "Wallet refresh preserves the row and unsaved draft")
	row.begin_edit()
	price.get_line_edit().text = "60"
	var cancel_price := InputEventAction.new()
	cancel_price.action = "ui_cancel"
	cancel_price.pressed = true
	row._input(cancel_price)
	_check(not row.editing and not price.visible and price.value == 55 and artifact.sell_price == 42 and ui._open, "Escape cancels only the price draft without closing stock or changing its saved price")
	row.begin_edit()
	price.get_line_edit().text = "bad price"
	var enter_price := InputEventKey.new()
	enter_price.keycode = KEY_ENTER
	enter_price.pressed = true
	row._input(enter_price)
	_check(artifact.sell_price == 1 and not row.editing, "Enter saves 1 G for invalid price input")
	var pause_book: CanvasLayer = load("res://ui/settings_menu.tscn").instantiate()
	fixture.add_child(pause_book)
	row.begin_edit()
	price.get_line_edit().text = "50"
	pause_book._input(cancel_price)
	_check(not row.editing and ui._open and not pause_book._is_open and artifact.sell_price == 1, "pause book gives Escape priority to the active price editor")
	pause_book.queue_free()
	await process_frame
	var broken := ArtifactData.create("res://assets/Relics/Goldcoin.glb", "Broken coin", "Uncommon", "broken")
	state.purchase(broken, 10)
	state.owned_items.magnifier = true
	state.changed.emit()
	await process_frame
	await process_frame
	var other: Node = ui._stock.get_node("%Rows").get_child(1)
	_check((other.get_node("%Inspection") as RichTextLabel).text.contains("Normal"), "owning a tool leaves undiscovered broken status hidden")
	row.begin_edit()
	price.get_line_edit().text = "40"
	other.begin_edit()
	_check(not row.editing and other.editing and price.value == 1, "opening another price box cancels the previous draft")
	other.cancel_edit()
	(other.get_node("%InspectDamageButton") as Button).pressed.emit()
	await process_frame
	_check(broken.inspections.get("magnifier", false) and (other.get_node("%Inspection") as RichTextLabel).text.contains("Broken"), "using the magnifier reveals the artifact's broken status")
	var restored_broken: ArtifactData = ArtifactData.from_dict(broken.to_dict())
	_check(restored_broken.inspections.get("magnifier", false), "artifact inspection findings survive save serialization")
	var stock_title: Control = ui._stock.get_node("%Heading")
	var stock_title_y: float = stock_title.global_position.y
	(ui._stock.find_child("Scroll") as ScrollContainer).scroll_vertical = 100
	await process_frame
	_check(is_equal_approx(stock_title.global_position.y, stock_title_y), "stock heading stays fixed while its rows scroll")
	state.owned_items.erase("magnifier") # The existing purchase check starts with no equipment owned.
	var shop_key := InputEventAction.new()
	shop_key.action = "shop"
	shop_key.pressed = true
	ui._unhandled_input(shop_key)
	await process_frame
	await process_frame
	_check(ui._shop.visible and not ui._stock.visible and not player.controls_enabled, "Shop shortcut changes pages without enabling movement")
	_check(root.get_visible_rect().encloses(ui.modal.get_global_rect()), "Shop panel stays inside the screen after switching pages")
	_check_shop_cards(ui._shop, "In-game shop")
	state.money = 500
	state.changed.emit()
	await process_frame
	var magnifier: Node = ui._shop.get_node("%Equipment").get_node("Magnifier")
	(magnifier.get_node("%BuyButton") as Button).pressed.emit()
	await process_frame
	_check(state.money == 141 and state.owned_items.get("magnifier", false), "Saved shop card purchases the correct equipment")
	_check((magnifier.get_node("%BuyButton") as Button).disabled, "Owned card updates in place and prevents duplicates")
	var search: LineEdit = ui._shop.get_node("%SearchField")
	search.text = "radio"
	search.text_changed.emit(search.text)
	_check(not magnifier.visible and ui._shop.get_node("%Equipment").get_node("Radio").visible and not ui._shop.get_node("%FurnitureHeading").visible, "browser search filters both equipment and furniture")
	search.text = "no-such-item"
	search.text_changed.emit(search.text)
	_check(ui._shop.get_node("%EmptySearch").visible, "browser search displays an empty result state")
	search.text = ""
	search.text_changed.emit(search.text)
	ui._unhandled_input(shop_key)
	_check(player.controls_enabled and not state.is_time_paused(), "Shop shortcut closes the panel and releases its time pause")
	fixture.queue_free()
	await process_frame

	var bargain: BargainUI = load("res://ui/bargain_interface.tscn").instantiate()
	root.add_child(bargain)
	var offered: Array[int] = []
	var saved: Array[int] = []
	var next: Array[bool] = []
	bargain.offer_submitted.connect(func(value: int): offered.append(value))
	bargain.price_submitted.connect(func(value: int): saved.append(value))
	bargain.next_pressed.connect(func(): next.append(true))
	bargain.show_customer(1, 3, 200, 75, 100, "")
	var inspected_tools: Array[String] = []
	bargain.inspection_requested.connect(func(tool: String): inspected_tools.append(tool))
	(bargain.find_child("InspectDamageButton", true, false) as Button).pressed.emit()
	(bargain.find_child("InspectCurseButton", true, false) as Button).pressed.emit()
	_check(inspected_tools == ["magnifier", "curse_detector"], "bargain inspection controls request the correct independent tools")
	var tab := InputEventAction.new()
	tab.action = "toggle_hud"
	tab.pressed = true
	bargain._input(tab)
	await create_timer(0.4, false).timeout
	_check(bargain._panel_hidden and bargain._flag.position.y <= -100 and root.get_visible_rect().encloses(bargain._toggle.get_global_rect()), "Tab slides bargain down and flag up while keeping the reveal button on screen")
	bargain._toggle.pressed.emit()
	await create_timer(0.4, false).timeout
	_check(not bargain._panel_hidden and is_zero_approx(bargain._layout.position.y) and is_zero_approx(bargain._flag.position.y), "reveal button restores bargain and flag")
	(bargain.find_child("Plus10Button", true, false) as Button).pressed.emit()
	bargain._btn_offer.pressed.emit()
	_check(offered == [110], "Bargain nudge and offer buttons use the saved controls")
	var original_title: Label = bargain._ov_title
	bargain.show_summary(1, 0, 141)
	await bargain.count_finished
	await process_frame
	_check(bargain._summary_overlay.visible and not bargain._receipt_overlay.visible, "Day summary uses its own scene")
	_check(bargain._ov_title != original_title, "Day summary has independently editable result labels")
	bargain._ov_btn.pressed.emit()
	_check(next.size() == 1, "Day summary next button emits its gameplay action once")
	bargain.show_price_editor(artifact)
	_check(bargain._price_overlay.visible and not bargain._summary_overlay.visible and not bargain._receipt_overlay.visible, "Price editor switches to its own scene")
	bargain._price_spin.get_line_edit().text = "50"
	bargain._price_save.pressed.emit()
	_check(saved == [50] and not bargain._overlay.visible, "Price editor save action stays wired after a summary")
	bargain.show_purchase(25, 50, "Test coin")
	bargain._ov_btn.pressed.emit()
	_check(next.size() == 2, "Receipt next button stays wired after changing result scenes")
	bargain.queue_free()
	await process_frame
	state.stop_clock()
	print("MENU SCENE TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
