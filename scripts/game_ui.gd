extends CanvasLayer

@export var menu_size := Vector2(1120, 630)
@export var preview_when_run_alone := true

signal sleep_requested
signal wait_requested
var player: Node3D
var manager: Node
var modal: Control
var content: Control
var toast_label: Label
var _open: bool = false
var _page: String = ""
var _toast_id: int = 0
var _root_control: Control
var _hint_label: Label
const STOCK_ROW = preload("res://ui/stock_row.tscn")
const OWNED_BUTTON_STYLE = preload("res://ui/shop_owned_button.tres")
var _stock: Control
var _shop: Control
var _game_over: Control
var _screen_tint: ColorRect
var _shop_expanded: bool = false
const RARITY_COLORS := {"Common": Color("895530"), "Uncommon": Color("35803f"), "Rare": Color("1d6896"), "SR": Color("9858bf"), "SSR": Color("30190c")}
const EQUIPMENT_NODES := {"magnifier":"Magnifier", "curse_detector":"CurseDetector", "clock":"Clock", "radio":"Radio", "roomba":"Roomba"}
const FURNITURE_NODES := {"furn_shelf":"DisplayShelf", "cab_open_shelf":"OpenShelf", "cab_counter_glass":"GlassCounter", "cab_weapon_rack":"WeaponRack", "furn_glass_cabinet":"GlassCabinet", "cab_tall_vitrine":"TallVitrine", "cab_combo":"CombinationCabinet", "cab_pedestal_dome":"Pedestal"}
const CONTROL_HINT := "WASD Move  •  E Interact  •  I Stock  •  B Shop  •  T Wait  •  Shift Run  •  C/Ctrl Crouch  •  ESC Pause"

const EQUIPMENT := [
	{"id":"magnifier", "name":"Magnifying glass", "price":359, "description":"Find hidden damage"},
	{"id":"curse_detector", "name":"Curse detector", "price":1000, "description":"Reveal hidden curses"},
	{"id":"clock", "name":"Clock", "price":350, "description":"Tell the time"},
	{"id":"radio", "name":"Radio", "price":200, "description":"Play shop music"},
	{"id":"roomba", "name":"Roomba", "price":2500, "description":"Cleans every mess automatically · 20 seconds each"},
]
const FURNITURE := [
	{"id":"furn_shelf", "name":"Display shelf", "price":200, "grid":[3,1]},
	{"id":"cab_open_shelf", "name":"Open shelf", "price":250, "grid":[3,1]},
	{"id":"cab_counter_glass", "name":"Glass display counter", "price":350, "grid":[3,2]},
	{"id":"cab_weapon_rack", "name":"Weapon rack", "price":500, "grid":[3,1]},
	{"id":"furn_glass_cabinet", "name":"Glass cabinet", "price":650, "grid":[2,2]},
	{"id":"cab_tall_vitrine", "name":"Tall vitrine", "price":750, "grid":[2,2]},
	{"id":"cab_combo", "name":"Combination cabinet", "price":900, "grid":[3,2]},
	{"id":"cab_pedestal_dome", "name":"Display pedestal", "price":1200, "grid":[2,2]},
]

func _ready() -> void:
	add_to_group("game_ui")
	layer = 12
	_root_control = $Screen
	toast_label = $Screen/Toast
	_hint_label = $Screen/ControlHint
	_screen_tint = $Screen/ScreenTint
	_hint_label.text = CONTROL_HINT
	modal = $Screen/Modal
	content = $Screen/Modal/Pages
	_stock = content.get_node("StockMenu")
	_shop = content.get_node("ShopMenu")
	_game_over = content.get_node("GameOverMenu")
	for page: Control in [_stock, _shop]:
		var wait_button: Button = page.get_node_or_null("%WaitButton")
		if wait_button:
			wait_button.pressed.connect(_request_wait)
	(_shop.find_child("MaximizeButton") as Button).pressed.connect(func():
		_shop_expanded = not _shop_expanded
		_layout_ui())
	for button_name in ["WindowCloseButton", "MinimizeButton"]:
		(_shop.find_child(button_name) as Button).pressed.connect(close_panel)
	(_stock.get_node("%PayRentButton") as Button).pressed.connect(_pay_rent)
	var sound := get_node_or_null("/root/Sfx")
	if sound:
		(_stock.get_node("%PlayRadio") as Button).pressed.connect(sound.play_radio)
		(_stock.get_node("%PauseRadio") as Button).pressed.connect(sound.pause_radio)
		(_stock.get_node("%StopRadio") as Button).pressed.connect(sound.stop_radio)
		sound.radio_playback_changed.connect(_refresh_radio_controls)
	GameSettings.changed.connect(_refresh_hint)
	_refresh_hint()
	(_shop.get_node("%SearchField") as LineEdit).text_changed.connect(func(_text: String): _filter_shop())
	for equipment: Dictionary in EQUIPMENT:
		var card: Node = _shop.get_node("%Equipment").get_node(EQUIPMENT_NODES[equipment.id])
		var buy: Button = card.get_node("%BuyButton")
		buy.set_meta("original_buy_style", buy.get_theme_stylebox("disabled"))
		buy.pressed.connect(_buy_equipment.bind(equipment))
	for furniture: Dictionary in FURNITURE:
		var card: Node = _shop.get_node("%Furniture").get_node(FURNITURE_NODES[furniture.id])
		(card.get_node("%BuyButton") as Button).pressed.connect(_buy_furniture.bind(furniture))
	(_game_over.get_node("%MainMenuButton") as Button).pressed.connect(func():
		GameState.stop_clock()
		get_tree().change_scene_to_file("res://main_menu.tscn"))
	_refresh_shop()
	modal.hide()
	get_viewport().size_changed.connect(_layout_ui)
	# Wrapped labels settle after containers receive their width. Refit when that
	# minimum changes so an initial narrow layout cannot leave an oversized panel.
	modal.minimum_size_changed.connect(func(): _layout_ui.call_deferred())
	_layout_ui()
	_layout_ui.call_deferred()
	GameState.changed.connect(_refresh_if_open)
	_preview_if_alone.call_deferred()

func _preview_if_alone() -> void:
	if preview_when_run_alone and get_tree().current_scene == self:
		_open = true
		_page = "stock"
		modal.show()
		_refresh_page()

func _layout_ui() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_root_control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root_control.position = Vector2.ZERO
	_root_control.size = viewport_size
	modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var desired: Vector2 = Vector2(1280, 720) if _shop_expanded and _page == "shop" else menu_size
	var fit_scale: float = minf((viewport_size.x - 32.0) / desired.x, (viewport_size.y - 32.0) / desired.y)
	modal.size = desired * minf(1.0, fit_scale)
	modal.position = (viewport_size - modal.size) * 0.5
	# Cards retain four columns at the design size and wrap on narrower windows.
	var columns: int = clampi(int(modal.size.x * 0.83 / 196.0), 1, 4)
	for section: String in ["Equipment", "Furniture"]:
		(_shop.get_node("%" + section) as GridContainer).columns = columns
	toast_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_label.position = Vector2(minf(320.0, viewport_size.x * 0.28), 16.0)
	toast_label.size = Vector2(viewport_size.x - toast_label.position.x - 132.0, 96.0)
	_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint_label.position = Vector2(14.0, viewport_size.y - 26.0)

func _unhandled_input(event: InputEvent) -> void:
	var warmer := get_node_or_null("/root/AssetWarmup")
	if warmer and warmer.get("busy"):
		get_viewport().set_input_as_handled(); return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T and get_tree().get_nodes_in_group("editing_stock_price").is_empty():
		_request_wait()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		if _open and _page == "stock":
			close_panel()
		else:
			open_panel("stock")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shop"):
		if _open and _page == "shop":
			close_panel()
		else:
			open_panel("shop")
		get_viewport().set_input_as_handled()

func _request_wait() -> void:
	if manager == null:
		return
	if not manager.can_wait():
		show_notice("Finish your interaction or deal with the intruder before waiting.")
		return
	if _open:
		close_panel()
	wait_requested.emit()

func _process(_delta: float) -> void:
	if _hint_label and OS.has_feature("web"):
		_refresh_hint()

func _refresh_hint() -> void:
	if manager and manager.has_method("is_inspecting_artifact") and manager.is_inspecting_artifact():
		_hint_label.text = "Drag: rotate  •  Right-drag: move  •  Scroll: zoom  •  %s: bargain  •  ESC Pause" % GameSettings.key_name("toggle_hud")
		return
	var movement := "/".join([GameSettings.key_name("move_forward"), GameSettings.key_name("move_left"), GameSettings.key_name("move_back"), GameSettings.key_name("move_right")])
	var hint := "%s Move  •  %s Interact  •  %s Management  •  %s Shop  •  T Wait  •  %s Run  •  %s Crouch  •  ESC Pause" % [movement, GameSettings.key_name("interact"), GameSettings.key_name("inventory"), GameSettings.key_name("shop"), GameSettings.key_name("sprint"), GameSettings.key_name("crouch")]
	_hint_label.text = "Click to look around  •  " + hint if OS.has_feature("web") and player and bool(player.get("controls_enabled")) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else hint

func set_hint_visible(on: bool) -> void:
	_hint_label.visible = on

func open_panel(page: String) -> void:
	if GameState.failed or not player or (not _open and not bool(player.get("controls_enabled"))):
		return
	_open = true
	_page = page
	add_to_group("active_game_modal")
	GameState.pause_time(&"stock_book")
	player.set_controls_enabled(false)
	modal.visible = true
	_screen_tint.show()
	_refresh_page()

func close_panel() -> void:
	_open = false
	modal.visible = false
	_screen_tint.hide()
	for row in get_tree().get_nodes_in_group("editing_stock_price"):
		row.cancel_edit()
	remove_from_group("active_game_modal")
	GameState.resume_time(&"stock_book")
	if player and not GameState.failed:
		player.set_controls_enabled(true)

func _refresh_if_open() -> void:
	if _open and _page != "game_over":
		call_deferred("_refresh_page")

func _switch_page() -> void:
	_page = "shop" if _page == "stock" else "stock"
	_refresh_page()

func _refresh_page() -> void:
	if _page == "game_over" or not _open:
		return
	if _page != "stock":
		for row in get_tree().get_nodes_in_group("editing_stock_price"):
			row.cancel_edit()
	_stock.visible = _page == "stock"
	_shop.visible = _page == "shop"
	_game_over.hide()
	$Screen/Modal/GameOverBackdrop.hide()
	_layout_ui()
	var page: Control = _stock if _page == "stock" else _shop
	var wait_button: Button = page.get_node_or_null("%WaitButton")
	if wait_button:
		wait_button.text = "Wait for customer" if GameState.time_minutes < 1230 else "Pass time"
		wait_button.tooltip_text = "Skip the gap before the next customer." if GameState.time_minutes < 1230 else "Pass time toward the next evening event or bedtime."
		wait_button.disabled = manager == null or not manager.can_wait()
	var due: int = GameState.rent_due_amount if GameState.rent_due_amount > 0 else GameState.RENT
	(page.get_node("%Wallet") as Label).text = "Day %d  ·  Wallet %d G  ·  Rent %d G due on day %d" % [GameState.day, GameState.money, due, GameState.next_rent_day] if _page == "stock" else "%d G" % GameState.money
	if _page == "stock":
		var stars: int = GameState.cleaning.stars()
		_stock.get_node("%RatingStars").rating = stars
		(_stock.get_node("%CleanlinessRating") as Label).text = "Cleanliness: %d/6 · Better offers +%d%%" % [stars, stars]
		var rent: Button = _stock.get_node("%PayRentButton")
		rent.visible = GameState.rent_due_amount > 0
		rent.text = "Pay rent · %d G" % GameState.rent_due_amount
		rent.disabled = GameState.money < GameState.rent_due_amount
		rent.tooltip_text = "You need %d G more." % (GameState.rent_due_amount - GameState.money) if rent.disabled else "Pay this rent bill."
	if _page == "stock": _refresh_stock()
	else: _refresh_shop()

func _refresh_stock() -> void:
	_refresh_radio_controls()
	var rows: VBoxContainer = _stock.get_node("%Rows")
	(_stock.get_node("%EmptyStock") as Label).visible = GameState.inventory.is_empty()
	var current_ids: Array[String] = []
	for artifact: ArtifactData in GameState.inventory: current_ids.append(artifact.id)
	for row in rows.get_children():
		if not str(row.get_meta("artifact_id", "")) in current_ids:
			rows.remove_child(row)
			row.queue_free()
	for artifact: ArtifactData in GameState.inventory:
		var row: Node = null
		for existing in rows.get_children():
			if existing.get_meta("artifact_id", "") == artifact.id:
				row = existing
				break
		if row == null:
			row = STOCK_ROW.instantiate()
			row.set_meta("artifact_id", artifact.id)
			rows.add_child(row)
			var listing: SpinBox = row.get_node("%ListingPrice")
			listing.max_value = artifact.max_sell_price()
			listing.value = artifact.sell_price
			row.price_committed.connect(_save_listing.bind(artifact.id, listing))
			(row.get_node("%InspectDamageButton") as Button).pressed.connect(_inspect_artifact.bind(artifact.id, "magnifier"))
			(row.get_node("%InspectCurseButton") as Button).pressed.connect(_inspect_artifact.bind(artifact.id, "curse_detector"))
		var name_label: RichTextLabel = row.get_node("%ArtifactName")
		name_label.add_theme_color_override("font_outline_color", RARITY_COLORS.get(artifact.rarity, Color("895530")))
		var title: String = artifact.display_name.replace("[", "[lb]")
		if artifact.rarity == "SSR": title = _rainbow_name(artifact.display_name)
		else: title = "[color=#fff1dc]" + title + "[/color]"
		name_label.text = "%s · [color=#fff1dc]%s · %d × %d[/color]" % [title, artifact.rarity, artifact.grid_size.x, artifact.grid_size.y]
		if artifact.rarity == "SSR":
			name_label.text = "%s · [color=#f7d475]SSR[/color] · [color=#f7e65b]%d × %d[/color]" % [title, artifact.grid_size.x, artifact.grid_size.y]
		(row.get_node("%Cost") as Label).text = "Cost %d G" % artifact.cost
		(row.get_node("%Inspection") as RichTextLabel).text = "[color=#fff1dc]Status: [/color]" + _inspection(artifact)
		(row.get_node("%InspectDamageButton") as Button).visible = GameState.owned_items.get("magnifier", false)
		(row.get_node("%InspectCurseButton") as Button).visible = GameState.owned_items.get("curse_detector", false)
		(row.get_node("%ListingPrice") as SpinBox).tooltip_text = "Tier limit: %d G" % artifact.max_sell_price()

func _save_listing(artifact_id: String, listing: SpinBox) -> void:
	# Commit typed values before reading the price, even when focus is still in the field.
	listing.apply()
	GameState.set_sell_price(artifact_id, int(listing.value))
	_play("click")

func _inspection(artifact: ArtifactData) -> String:
	var findings: Array[String] = []
	if artifact.inspections.get("magnifier", false) and artifact.status == "broken":
		findings.append("[color=#a9a4ae]Broken[/color]")
	if artifact.inspections.get("curse_detector", false) and artifact.status == "curse":
		findings.append("[color=#8bcc36]Curse[/color]")
	if artifact.inspections.get("stolen_found", false):
		findings.append("[color=#f66363]Stolen[/color]")
	return ", ".join(findings) if not findings.is_empty() else "[color=#fff1dc]Normal[/color]"

func _inspect_artifact(artifact_id: String, tool: String) -> void:
	var artifact: ArtifactData = GameState.get_artifact(artifact_id)
	if artifact == null or not GameState.owned_items.get(tool, false): return
	artifact.inspections[tool] = true
	if tool == "magnifier" and artifact.status == "stolen" and manager and manager.newspaper_delivered:
		artifact.inspections["stolen_found"] = true
	GameState.changed.emit()
	_play("click")

func _rainbow_name(title: String) -> String:
	var palette := ["ee68c8", "dd7956", "e6bf4d", "a8c951", "69b6c2", "b58bde"]
	var result := ""
	for index in title.length():
		result += "[color=#%s]%s[/color]" % [palette[(index / 3) % palette.size()], title[index].replace("[", "[lb]")]
	return result

func _is_gold(artifact: ArtifactData) -> bool:
	var item_name: String = artifact.display_name.to_lower()
	return "gold" in item_name or "crown" in item_name or "goblet" in item_name

func _refresh_radio_controls() -> void:
	if not _stock: return
	var owned: bool=GameState.owned_items.get("radio",false)
	_stock.get_node("%RadioControls").visible=owned
	_stock.get_node("%RadioStatus").visible=owned
	# Keep the track name on the parchment with room above the footer controls.
	(_stock.get_node("Scroll") as ScrollContainer).anchor_bottom=0.755 if owned else 0.795
	var sound := get_node_or_null("/root/Sfx")
	if not sound: return
	_stock.get_node("%RadioStatus").text="%s · %s" % [sound.song_name(),String(sound.song_state).capitalize()]
	_stock.get_node("%PlayRadio").disabled=sound.song_state=="playing"
	_stock.get_node("%PauseRadio").disabled=sound.song_state!="playing"
	_stock.get_node("%StopRadio").disabled=sound.song_state=="stopped"

func _refresh_shop() -> void:
	for equipment: Dictionary in EQUIPMENT:
		var card: Node = _shop.get_node("%Equipment").get_node(EQUIPMENT_NODES[equipment.id])
		(card.get_node("%ItemName") as Label).text = equipment.name
		(card.get_node("%Price") as Label).text = "%d G" % equipment.price
		(card.get_node("%Description") as Label).text = equipment.description
		var owned: bool = bool(GameState.owned_items.get(equipment.id, false))
		var button: Button = card.get_node("%BuyButton")
		# The supplied orange button already contains its Buy lettering.
		button.text = "Owned" if owned else ""
		if owned: button.add_theme_stylebox_override("disabled", OWNED_BUTTON_STYLE)
		else: button.add_theme_stylebox_override("disabled", button.get_meta("original_buy_style"))
		button.disabled = owned or not GameState.can_buy_upgrade(int(equipment.price))
		button.tooltip_text = "Keep 50 G to start trading." if not owned and GameState.can_buy(int(equipment.price)) and not GameState.can_buy_upgrade(int(equipment.price)) else ""
		button.modulate = Color(1, 1, 1, 0.5) if not owned and button.disabled else Color.WHITE
	for furniture: Dictionary in FURNITURE:
		var card: Node = _shop.get_node("%Furniture").get_node(FURNITURE_NODES[furniture.id])
		(card.get_node("%ItemName") as Label).text = furniture.name
		(card.get_node("%Price") as Label).text = "%d G" % furniture.price
		(card.get_node("%Description") as Label).text = "%d × %d floor cells" % [furniture.grid[0], furniture.grid[1]]
		var button: Button = card.get_node("%BuyButton")
		button.text = ""
		button.disabled = manager == null or not GameState.can_buy_upgrade(int(furniture.price))
		button.tooltip_text = "Keep 50 G to start trading." if GameState.can_buy(int(furniture.price)) and not GameState.can_buy_upgrade(int(furniture.price)) else ""
		button.modulate = Color(1, 1, 1, 0.5) if button.disabled else Color.WHITE
	_filter_shop()

func _filter_shop() -> void:
	var search: String = (_shop.get_node("%SearchField") as LineEdit).text.strip_edges().to_lower()
	var found: bool = false
	for section: String in ["Equipment", "Furniture"]:
		var visible_count: int = 0
		for card in _shop.get_node("%" + section).get_children():
			var title: String = (card.get_node("%ItemName") as Label).text.to_lower()
			var description: String = (card.get_node("%Description") as Label).text.to_lower()
			card.visible = search.is_empty() or search in title or search in description
			visible_count += int(card.visible)
		(_shop.get_node("%" + section + "Heading") as Label).visible = visible_count > 0
		found = found or visible_count > 0
	(_shop.get_node("%EmptySearch") as Label).visible = not found

func _buy_equipment(equipment: Dictionary) -> void:
	if GameState.owned_items.get(equipment.id, false):
		return
	if not GameState.can_buy_upgrade(int(equipment.price)): return
	if GameState.spend(int(equipment.price)):
		GameState.set_item_owned(String(equipment.id))
		_play("coin")
		show_notice("%s purchased." % equipment.name)
	else:
		_play("error")

func _buy_furniture(furniture: Dictionary) -> void:
	if not GameState.can_buy_upgrade(int(furniture.price)): return
	var model_path: String = "res://assets/Relics/Expanded/Furniture/%s.glb" % furniture.id
	var record := {"id":"furniture-%x-%x" % [Time.get_ticks_usec(), randi()], "name":furniture.name, "model_path":model_path, "cost":int(furniture.price), "grid_size":furniture.grid, "placement":{}}
	if not ResourceLoader.exists(model_path):
		show_notice("That furniture model could not be loaded.")
		return
	if GameState.purchase_furniture(record, int(furniture.price)):
		close_panel()
		manager.place_new_furniture(GameState.get_furniture(String(record.id)))
		_play("coin")

func _pay_rent() -> void:
	if GameState.pay_rent():
		_play("coin")
		show_notice("Rent paid. Next payment is due on day %d." % GameState.next_rent_day)

func show_notice(text: String, duration: float = 5.0) -> void:
	_toast_id += 1
	var message_id: int = _toast_id
	toast_label.text = text
	await get_tree().create_timer(duration, false).timeout
	if message_id == _toast_id:
		toast_label.text = ""

func show_game_over(reason: String) -> void:
	if _open:
		close_panel()
	_open = true
	_page = "game_over"
	modal.show()
	_screen_tint.show()
	_stock.hide()
	_shop.hide()
	_game_over.show()
	_layout_ui()
	$Screen/Modal/GameOverBackdrop.show()
	(_game_over.get_node("%Reason") as Label).text = reason
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _play(sound: String) -> void:
	var audio: Node = get_node_or_null("/root/Sfx")
	if audio:
		audio.play(sound)
